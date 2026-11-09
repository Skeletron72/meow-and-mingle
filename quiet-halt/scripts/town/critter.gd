class_name Critter
extends Node3D
## Бабочка или светлячок: порхает над землёй, ловится сачком.

var item_id: String = "butterfly"
var kind: String = "butterfly"
var _vel: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _wing_l: Node3D
var _wing_r: Node3D
var _target: Vector3
var _alt: float = 1.0
var _blink: float = 0.0


func setup(id: String, k: String) -> void:
	item_id = id
	kind = k
	var d: Dictionary = Data.item(id)
	var ca: Array = d.get("color", [1, 1, 0.5])
	var col := Color(ca[0], ca[1], ca[2])
	if kind == "firefly":
		var kk := MeshKit.new()
		kk.ball(Vector3.ZERO, Vector3(0.05, 0.04, 0.07), Color(0.25, 0.22, 0.2), 5, 3)
		kk.ball(Vector3(0, -0.01, -0.07), Vector3(0.04, 0.04, 0.04), col, 5, 3, "glow")
		var mi := MeshInstance3D.new()
		mi.mesh = kk.build()
		mi.material_override = null
		add_child(mi)
		var gl := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = Mats.unlit(Color(col.r, col.g, col.b, 0.35))
		gl.mesh = sm
		gl.position = Vector3(0, 0, -0.07)
		add_child(gl)
		_alt = randf_range(0.6, 1.4)
	else:
		var bk := MeshKit.new()
		bk.ball(Vector3.ZERO, Vector3(0.03, 0.03, 0.11), Color(0.25, 0.2, 0.2), 5, 3)
		var body := MeshInstance3D.new()
		body.mesh = bk.build()
		add_child(body)
		for s in [-1.0, 1.0]:
			var wk := MeshKit.new()
			wk.ball(Vector3(0.12 * s, 0, 0), Vector3(0.12, 0.01, 0.1), col, 6, 3)
			var piv := Node3D.new()
			var wmi := MeshInstance3D.new()
			wmi.mesh = wk.build()
			piv.add_child(wmi)
			add_child(piv)
			if s < 0:
				_wing_l = piv
			else:
				_wing_r = piv
		_alt = randf_range(0.8, 1.7)
	_pick_target()


func _pick_target() -> void:
	_target = global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	_target.y = World.state.height_at(_target.x, _target.z) + _alt + randf_range(-0.3, 0.4)


func _process(delta: float) -> void:
	_t += delta
	var to: Vector3 = _target - global_position
	if to.length() < 0.4:
		_pick_target()
	_vel = _vel.lerp(to.normalized() * (1.1 if kind == "firefly" else 1.7), minf(delta * 2.0, 1.0))
	global_position += _vel * delta
	global_position.y += sin(_t * 5.0) * 0.004
	if _vel.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(_vel.x, _vel.z), minf(delta * 4.0, 1.0))
	if _wing_l:
		var a: float = sin(_t * 26.0) * 0.9
		_wing_l.rotation.z = a
		_wing_r.rotation.z = -a
	if kind == "firefly":
		var k: float = 0.55 + 0.45 * sin(_t * 3.0 + _alt * 6.0)
		scale = Vector3.ONE * (0.8 + k * 0.4)
