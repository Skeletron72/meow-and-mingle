class_name ObjectsView
extends Node3D
## Визуализация объектов мира: слушает сигналы World и держит узлы в синхроне.

var nodes: Dictionary = {} # idx якоря -> Node3D


func _ready() -> void:
	World.object_added.connect(_on_added)
	World.object_removed.connect(_on_removed)
	World.object_changed.connect(_on_changed)
	for k in World.state.objects.keys():
		_spawn(int(k))


func node_at(anchor: Vector2i) -> Node3D:
	return nodes.get(WorldState.idx(anchor), null)


func _ground_y(c: Vector2i, id: String) -> float:
	if id in ["rails", "bridge_rails", "clock_face", "station"]:
		return 0.0
	var def: Dictionary = Data.object_def(id)
	var sz: Array = def.get("size", [1, 1])
	var x: float = float(c.x) + float(sz[0]) * 0.5
	var z: float = float(c.y) + float(sz[1]) * 0.5
	return World.state.height_at(x, z)


func _spawn(k: int) -> void:
	var o: Dictionary = World.state.objects[k]
	var c: Vector2i = WorldState.cell_of(k)
	var n: Node3D = PropFactory.create(o.id, o.st, int(o.rot), c)
	n.position.y = _ground_y(c, o.id)
	add_child(n)
	nodes[k] = n
	if o.id.begins_with("tree_") or o.id == "bush":
		n.rotation.y = float(int(o.rot)) * 1.3 + float(c.x) * 0.7
		var s: float = 0.88 + 0.24 * float(hash("%d,%d" % [c.x, c.y]) % 100) / 100.0
		n.scale = Vector3(s, s, s)


func _on_added(c: Vector2i) -> void:
	var k: int = WorldState.idx(c)
	if nodes.has(k):
		(nodes[k] as Node).queue_free()
		nodes.erase(k)
	if World.state.objects.has(k):
		_spawn(k)
		var n: Node3D = nodes[k]
		if n.has_meta("obj_id") and str(n.get_meta("obj_id")) not in ["rails", "station"]:
			var base: Vector3 = n.scale
			n.scale = base * 0.2
			var t := create_tween()
			t.tween_property(n, "scale", base * 1.08, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(n, "scale", base, 0.12)


func _on_removed(c: Vector2i, _id: String) -> void:
	var k: int = WorldState.idx(c)
	if nodes.has(k):
		(nodes[k] as Node).queue_free()
		nodes.erase(k)


func _on_changed(c: Vector2i) -> void:
	var k: int = WorldState.idx(c)
	if not World.state.objects.has(k):
		return
	var old_scale: Vector3 = Vector3.ONE
	var old_rot: float = 0.0
	if nodes.has(k):
		old_scale = (nodes[k] as Node3D).scale
		old_rot = (nodes[k] as Node3D).rotation.y
		(nodes[k] as Node).queue_free()
		nodes.erase(k)
	_spawn(k)
	var n: Node3D = nodes[k]
	n.scale = old_scale
	n.rotation.y = old_rot
