class_name TerrainView
extends Node3D
## Строит меш земли по данным мира чанками. Перестраивает чанк при изменении.

const G = WorldState.Ground

var _chunks: Dictionary = {}
var _dirty: Dictionary = {}
var _water: MeshInstance3D


func _ready() -> void:
	World.chunk_dirty.connect(func(c: Vector2i) -> void: _dirty[c] = true)
	rebuild_all()
	_make_water()


func rebuild_all() -> void:
	for ch in _chunks.values():
		(ch as Node).queue_free()
	_chunks.clear()
	var nx: int = ceili(float(WorldState.W) / float(WorldState.CHUNK))
	var nz: int = ceili(float(WorldState.H) / float(WorldState.CHUNK))
	for cz in nz:
		for cx in nx:
			_build_chunk(Vector2i(cx, cz))


func _process(_delta: float) -> void:
	if _dirty.is_empty():
		return
	for c in _dirty.keys():
		_build_chunk(c)
	_dirty.clear()


func _make_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(float(WorldState.W) + 40.0, float(WorldState.H) + 40.0)
	pm.subdivide_width = 90
	pm.subdivide_depth = 70
	_water = MeshInstance3D.new()
	_water.mesh = pm
	_water.material_override = Mats.water()
	_water.position = Vector3(float(WorldState.W) * 0.5, -0.2, float(WorldState.H) * 0.5)
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)


func _cell_color(ws: WorldState, x: int, z: int) -> Color:
	var g: int = ws.ground[z * WorldState.W + x]
	var h: int = hash("%d,%d" % [x, z])
	var v: float = float(h & 0xFF) / 255.0
	match g:
		G.GRASS:
			var b: float = 0.60 + v * 0.10
			return Color(b, b, b, 0.0)
		G.HILL:
			var b2: float = 0.46 + v * 0.08
			return Color(b2 * 0.9, b2, b2 * 0.95, 0.0)
		G.PATH:
			return Color(0.88 + v * 0.03, 0.77 + v * 0.03, 0.58, 1.0)
		G.SAND:
			return Color(0.95, 0.87 + v * 0.03, 0.66, 1.0)
		G.PLATFORM:
			var plank: float = 0.0 if ((x + z) % 2 == 0) else 0.03
			return Color(0.74 - plank, 0.68 - plank, 0.62 - plank, 1.0)
		G.BED:
			return Color(0.50 + v * 0.05, 0.45, 0.42, 1.0)
		G.PAVING:
			var chk: float = 0.0 if ((x + z) % 2 == 0) else 0.045
			return Color(0.84 - chk, 0.78 - chk, 0.72 - chk, 1.0)
		G.BRIDGE:
			var pl: float = 0.0 if (z % 2 == 0) else 0.05
			return Color(0.68 - pl, 0.48 - pl, 0.32 - pl, 1.0)
		G.WATER:
			return Color(0.56, 0.62, 0.52, 1.0)
	return Color(1, 0, 1, 1)


func _normal_at(ws: WorldState, cx: int, cz: int) -> Vector3:
	var hl: float = ws.corner_h(cx - 1, cz)
	var hr: float = ws.corner_h(cx + 1, cz)
	var hu: float = ws.corner_h(cx, cz - 1)
	var hd: float = ws.corner_h(cx, cz + 1)
	return Vector3(hl - hr, 2.0, hu - hd).normalized()


func _build_chunk(ch: Vector2i) -> void:
	var ws: WorldState = World.state
	var x0: int = ch.x * WorldState.CHUNK
	var z0: int = ch.y * WorldState.CHUNK
	var x1: int = mini(x0 + WorldState.CHUNK, WorldState.W)
	var z1: int = mini(z0 + WorldState.CHUNK, WorldState.H)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for z in range(z0, z1):
		for x in range(x0, x1):
			var col: Color = _cell_color(ws, x, z)
			var p00 := Vector3(x, ws.corner_h(x, z), z)
			var p10 := Vector3(x + 1, ws.corner_h(x + 1, z), z)
			var p11 := Vector3(x + 1, ws.corner_h(x + 1, z + 1), z + 1)
			var p01 := Vector3(x, ws.corner_h(x, z + 1), z + 1)
			var n00: Vector3 = _normal_at(ws, x, z)
			var n10: Vector3 = _normal_at(ws, x + 1, z)
			var n11: Vector3 = _normal_at(ws, x + 1, z + 1)
			var n01: Vector3 = _normal_at(ws, x, z + 1)
			# порядок обхода по часовой стрелке при взгляде сверху (Godot)
			var tris: Array
			if (x + z) % 2 == 0:
				tris = [[p00, p10, p11, n00, n10, n11], [p00, p11, p01, n00, n11, n01]]
			else:
				tris = [[p00, p10, p01, n00, n10, n01], [p10, p11, p01, n10, n11, n01]]
			for t in tris:
				var a: Vector3 = t[0]
				var b: Vector3 = t[1]
				var c: Vector3 = t[2]
				var order: Array = [0, 1, 2]
				if (b - a).cross(c - a).y > 0.0:
					order = [0, 2, 1]
				for o in order:
					verts.append(t[o])
					norms.append(t[3 + o])
					cols.append(col)
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, Mats.main())
	var mi: MeshInstance3D
	if _chunks.has(ch):
		mi = _chunks[ch]
	else:
		mi = MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [ch.x, ch.y]
		add_child(mi)
		_chunks[ch] = mi
	mi.mesh = mesh
