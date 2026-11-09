class_name Pickup
extends Node3D
## Упавший предмет на земле: подпрыгивает, подбирается при приближении.

var item_id: String = ""
var _t: float = 0.0
var _landed: bool = false
var _mesh: MeshInstance3D


func setup(id: String, from: Vector3, to: Vector3) -> void:
	item_id = id
	var d: Dictionary = Data.item(id)
	var ca: Array = d.get("color", [0.8, 0.5, 0.3])
	var k := MeshKit.new()
	var col := Color(ca[0], ca[1], ca[2])
	match str(d.get("shape", "fruit")):
		"flower":
			k.cyl(Vector3.ZERO, 0.02, 0.02, 0.2, Color(0.4, 0.65, 0.3), 4)
			k.ball(Vector3(0, 0.22, 0), Vector3(0.12, 0.08, 0.12), col, 6, 4)
		_:
			k.ball(Vector3(0, 0.12, 0), Vector3(0.13, 0.13, 0.13), col, 8, 5)
			k.cyl(Vector3(0, 0.22, 0), 0.01, 0.01, 0.07, Color(0.4, 0.3, 0.2), 3)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = k.build()
	add_child(_mesh)
	global_position = from
	var t := create_tween()
	t.tween_property(self, "global_position:y", to.y + 0.02, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "global_position:x", to.x, 0.45)
	t.parallel().tween_property(self, "global_position:z", to.z, 0.45)
	t.tween_callback(func() -> void: _landed = true)


func ready_to_take() -> bool:
	return _landed


func _process(delta: float) -> void:
	_t += delta
	if _landed and _mesh:
		_mesh.position.y = 0.04 + sin(_t * 3.0) * 0.03
		_mesh.rotation.y += delta * 1.4
