class_name WorldState
extends RefCounted
## Чистые данные мира (без узлов). Это единственный источник правды о городе:
## его сериализуют для сохранения и (в будущем) отправляют по сети клиентам.

const W: int = 80
const H: int = 60
const CHUNK: int = 16
const PLAY_MIN: Vector2i = Vector2i(5, 6)
const PLAY_MAX: Vector2i = Vector2i(74, 53)
const VERSION: int = 1

enum Ground { GRASS, PATH, SAND, WATER, PLATFORM, BED, PAVING, BRIDGE, HILL }

var world_seed: int = 1
var town_name: String = "Тихая Заводь"
var hemisphere: int = 0
var start_day: int = 0
var last_day: int = 0

var ground: PackedByteArray = PackedByteArray()
var height: PackedFloat32Array = PackedFloat32Array() # (W+1)*(H+1), высоты углов клеток
var objects: Dictionary = {} # idx клетки-якоря -> {id, rot, st}
var projects: Dictionary = {} # id -> {state, funded, done_day}
var villagers: Dictionary = {} # id -> {friend, talked_day, request, present}
var flags: Dictionary = {}
var notes_found: Array = []

## Производные данные (не сохраняются).
var occ: PackedInt32Array = PackedInt32Array() # idx -> idx якоря + 1, либо 0
var blocked: PackedByteArray = PackedByteArray()


static func idx(c: Vector2i) -> int:
	return c.y * W + c.x


static func cell_of(i: int) -> Vector2i:
	return Vector2i(i % W, i / W)


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func _init() -> void:
	ground.resize(W * H)
	height.resize((W + 1) * (H + 1))
	occ.resize(W * H)
	blocked.resize(W * H)


func get_ground(c: Vector2i) -> int:
	if not in_bounds(c):
		return Ground.HILL
	return ground[idx(c)]


func corner_h(cx: int, cz: int) -> float:
	cx = clampi(cx, 0, W)
	cz = clampi(cz, 0, H)
	return height[cz * (W + 1) + cx]


## Высота поверхности в мировой точке (билинейно по углам клетки).
func height_at(x: float, z: float) -> float:
	var fx: float = clampf(x, 0.0, float(W) - 0.001)
	var fz: float = clampf(z, 0.0, float(H) - 0.001)
	var cx: int = int(fx)
	var cz: int = int(fz)
	var tx: float = fx - float(cx)
	var tz: float = fz - float(cz)
	var h00: float = corner_h(cx, cz)
	var h10: float = corner_h(cx + 1, cz)
	var h01: float = corner_h(cx, cz + 1)
	var h11: float = corner_h(cx + 1, cz + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func object_at(c: Vector2i) -> Dictionary:
	if not in_bounds(c):
		return {}
	var a: int = occ[idx(c)]
	if a == 0:
		return {}
	var o: Dictionary = objects.get(a - 1, {})
	return o


func anchor_at(c: Vector2i) -> int:
	if not in_bounds(c):
		return -1
	return occ[idx(c)] - 1


func is_walkable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	if blocked[idx(c)] != 0:
		return false
	var g: int = ground[idx(c)]
	if g == Ground.WATER or g == Ground.BED or g == Ground.HILL:
		return false
	return true


func rebuild_derived() -> void:
	occ.fill(0)
	blocked.fill(0)
	for k in objects.keys():
		_register(int(k))


func _footprint(anchor_idx: int) -> Array:
	var o: Dictionary = objects[anchor_idx]
	var def: Dictionary = Data.object_def(o.id)
	var sz: Array = def.get("size", [1, 1])
	var a: Vector2i = cell_of(anchor_idx)
	var w: int = int(sz[0])
	var h: int = int(sz[1])
	if int(o.get("rot", 0)) % 2 == 1:
		var t: int = w
		w = h
		h = t
	var out: Array = []
	for dz in h:
		for dx in w:
			var c := Vector2i(a.x + dx, a.y + dz)
			if in_bounds(c):
				out.append(c)
	return out


func _register(anchor_idx: int) -> void:
	var def: Dictionary = Data.object_def(objects[anchor_idx].id)
	var blk: bool = bool(def.get("block", false))
	for c in _footprint(anchor_idx):
		occ[idx(c)] = anchor_idx + 1
		if blk:
			blocked[idx(c)] = 1


func _unregister(anchor_idx: int) -> void:
	for c in _footprint(anchor_idx):
		occ[idx(c)] = 0
		blocked[idx(c)] = 0


func footprint_of(anchor: Vector2i) -> Array:
	return _footprint(idx(anchor))


func can_place(id: String, c: Vector2i, rot: int = 0) -> bool:
	var def: Dictionary = Data.object_def(id)
	var sz: Array = def.get("size", [1, 1])
	var w: int = int(sz[0])
	var h: int = int(sz[1])
	if rot % 2 == 1:
		var t: int = w
		w = h
		h = t
	for dz in h:
		for dx in w:
			var cc := Vector2i(c.x + dx, c.y + dz)
			if not in_bounds(cc):
				return false
			if occ[idx(cc)] != 0:
				return false
			var g: int = ground[idx(cc)]
			if g == Ground.WATER or g == Ground.HILL:
				return false
	return true


func add_object(id: String, c: Vector2i, rot: int = 0, st: Dictionary = {}) -> void:
	var i: int = idx(c)
	objects[i] = {"id": id, "rot": rot, "st": st}
	_register(i)


func remove_object(c: Vector2i) -> void:
	var i: int = idx(c)
	if objects.has(i):
		_unregister(i)
		objects.erase(i)


# ---------- сериализация ----------

func to_dict() -> Dictionary:
	var objs: Array = []
	for k in objects.keys():
		var o: Dictionary = objects[k]
		objs.append([int(k), o.id, int(o.get("rot", 0)), o.get("st", {})])
	return {
		"v": VERSION,
		"seed": world_seed,
		"town": town_name,
		"hemi": hemisphere,
		"start_day": start_day,
		"last_day": last_day,
		"ground": Marshalls.raw_to_base64(ground),
		"height": Marshalls.raw_to_base64(height.to_byte_array()),
		"objects": objs,
		"projects": projects,
		"villagers": villagers,
		"flags": flags,
		"notes": notes_found,
	}


func from_dict(d: Dictionary) -> void:
	world_seed = int(d.get("seed", 1))
	town_name = str(d.get("town", "Тихая Заводь"))
	hemisphere = int(d.get("hemi", 0))
	start_day = int(d.get("start_day", 0))
	last_day = int(d.get("last_day", 0))
	ground = Marshalls.base64_to_raw(str(d.get("ground", "")))
	height = Marshalls.base64_to_raw(str(d.get("height", ""))).to_float32_array()
	objects.clear()
	for e in d.get("objects", []):
		objects[int(e[0])] = {"id": str(e[1]), "rot": int(e[2]), "st": e[3] if e[3] is Dictionary else {}}
	projects = d.get("projects", {})
	villagers = d.get("villagers", {})
	flags = d.get("flags", {})
	notes_found = d.get("notes", [])
	occ.resize(W * H)
	blocked.resize(W * H)
	rebuild_derived()
