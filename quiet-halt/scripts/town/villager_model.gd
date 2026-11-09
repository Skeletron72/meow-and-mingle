class_name VillagerModel
extends Node3D
## Ворсинки — пушистые домовые станции. Пять видов, цвет из данных.

var species: String = "fluff"
var base_color: Color = Color(1, 0.93, 0.72)
var _body: Node3D
var _eyes: Node3D
var _phase: float = 0.0
var _blink: float = 3.0
var moving: float = 0.0
var _arms: Array = []
var _feet: Array = []


func build(sp: String, col: Color) -> void:
	species = sp
	base_color = col
	for c in get_children():
		c.queue_free()
	_arms.clear()
	_feet.clear()
	_body = Node3D.new()
	add_child(_body)
	var k := MeshKit.new()
	var dark: Color = col.darkened(0.2)
	var light: Color = col.lightened(0.15)
	match sp:
		"moss":
			k.ball(Vector3(0, 0.52, 0), Vector3(0.52, 0.5, 0.5), col, 10, 7)
			k.ball(Vector3(-0.25, 0.75, 0.2), Vector3(0.22, 0.12, 0.2), dark, 6, 4)
			k.ball(Vector3(0.3, 0.45, 0.15), Vector3(0.2, 0.15, 0.2), dark, 6, 4)
			k.cyl(Vector3(0, 0.98, 0), 0.02, 0.015, 0.22, Color(0.4, 0.55, 0.3), 4)
			k.ball(Vector3(0.1, 1.22, 0), Vector3(0.14, 0.08, 0.1), Color(0.55, 0.78, 0.4), 6, 4)
			k.ball(Vector3(-0.08, 1.18, 0), Vector3(0.12, 0.07, 0.09), Color(0.45, 0.7, 0.35), 6, 4)
		"fluff":
			k.ball(Vector3(0, 0.55, 0), Vector3(0.56, 0.52, 0.54), col, 10, 7)
			for p in [Vector3(-0.3, 0.9, 0.0), Vector3(0.3, 0.88, 0.05), Vector3(0, 1.0, -0.1), Vector3(-0.45, 0.55, 0.1), Vector3(0.45, 0.55, 0.1)]:
				k.ball(p, Vector3(0.2, 0.18, 0.2), light, 7, 4)
			k.ball(Vector3(-0.28, 0.42, 0.42), Vector3(0.1, 0.06, 0.04), Color(1, 0.62, 0.65), 6, 3)
			k.ball(Vector3(0.28, 0.42, 0.42), Vector3(0.1, 0.06, 0.04), Color(1, 0.62, 0.65), 6, 3)
		"soot":
			k.ball(Vector3(0, 0.42, 0), Vector3(0.42, 0.4, 0.42), col, 9, 6)
			for i in 10:
				var a: float = TAU * float(i) / 10.0
				var dir := Vector3(cos(a), 0.15 * sin(a * 3.0), sin(a))
				var xf0: Transform3D = k.xf
				k.xf = xf0 * Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -PI * 0.5), Vector3(0, 0.42, 0) + dir * 0.36)
				k.cyl(Vector3.ZERO, 0.06, 0.0, 0.2, dark.lightened(0.1), 4)
				k.xf = xf0
		"reed":
			k.ball(Vector3(0, 0.62, 0), Vector3(0.38, 0.62, 0.36), col, 9, 7)
			for i in 6:
				var a2: float = TAU * float(i) / 6.0
				var xf1: Transform3D = k.xf
				k.xf = xf1 * Transform3D(Basis(Vector3.UP, a2) * Basis(Vector3.BACK, 0.5), Vector3(0, 1.22, 0))
				k.cyl(Vector3.ZERO, 0.03, 0.0, 0.34, Color(0.9, 0.82, 0.5), 4)
				k.xf = xf1
			k.box(Vector3(0, 0.88, 0.0), Vector3(0.78, 0.05, 0.7), Color(0.86, 0.66, 0.45))
		_: # felt
			k.ball(Vector3(0, 0.5, 0), Vector3(0.5, 0.48, 0.48), col, 10, 7)
			k.ball(Vector3(-0.3, 0.98, 0), Vector3(0.14, 0.14, 0.08), dark, 6, 4)
			k.ball(Vector3(0.3, 0.98, 0), Vector3(0.14, 0.14, 0.08), dark, 6, 4)
			k.box(Vector3(0, 0.18, 0.44), Vector3(0.26, 0.03, 0.04), dark)
			k.box(Vector3(0.0, 0.14, 0.44), Vector3(0.03, 0.08, 0.04), dark)
			k.cyl(Vector3(0, 0.22, 0), 0.38, 0.36, 0.1, Color(0.62, 0.4, 0.44), 10) # шарф
	var mi := MeshInstance3D.new()
	mi.mesh = k.build()
	mi.material_override = Mats.fuzzy()
	_body.add_child(mi)
	# лицо
	var eye_h: float = 0.6
	var eye_z: float = 0.46
	match sp:
		"soot":
			eye_h = 0.46
			eye_z = 0.38
		"reed":
			eye_h = 0.85
			eye_z = 0.34
		"fluff":
			eye_h = 0.62
			eye_z = 0.48
		"moss":
			eye_h = 0.62
			eye_z = 0.45
		_:
			eye_h = 0.58
			eye_z = 0.42
	_eyes = Node3D.new()
	_eyes.position = Vector3(0, eye_h, eye_z)
	_body.add_child(_eyes)
	var ek := MeshKit.new()
	for sx in [-1.0, 1.0]:
		if sp == "soot":
			ek.ball(Vector3(0.12 * sx, 0, 0), Vector3(0.1, 0.12, 0.04), Color(1, 1, 1), 8, 5)
			ek.ball(Vector3(0.12 * sx, 0, 0.03), Vector3(0.04, 0.05, 0.03), Color(0.1, 0.1, 0.12), 6, 4)
		else:
			ek.ball(Vector3(0.13 * sx, 0, 0), Vector3(0.05, 0.065, 0.03), Color(0.1, 0.08, 0.1), 7, 5)
			ek.ball(Vector3(0.13 * sx + 0.015, 0.03, 0.025), Vector3(0.016, 0.016, 0.01), Color(1, 1, 1), 4, 3)
	ek.box(Vector3(0, -0.11, 0.0), Vector3(0.08, 0.015, 0.02), Color(0.4, 0.2, 0.2))
	var emi := MeshInstance3D.new()
	emi.mesh = ek.build()
	_eyes.add_child(emi)
	# ручки и ножки
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.5 * sx * (0.8 if sp != "reed" else 0.62), 0.5, 0.05)
		var ak := MeshKit.new()
		ak.ball(Vector3(0.06 * sx, -0.08, 0), Vector3(0.12, 0.12, 0.12), col.darkened(0.05), 6, 4)
		var ami := MeshInstance3D.new()
		ami.mesh = ak.build()
		ami.material_override = Mats.fuzzy()
		arm.add_child(ami)
		_body.add_child(arm)
		_arms.append(arm)
		var foot := Node3D.new()
		foot.position = Vector3(0.2 * sx, 0.06, 0.08)
		var fk := MeshKit.new()
		fk.ball(Vector3(0, 0, 0.05), Vector3(0.12, 0.07, 0.16), col.darkened(0.25), 6, 4)
		var fmi := MeshInstance3D.new()
		fmi.mesh = fk.build()
		foot.add_child(fmi)
		_body.add_child(foot)
		_feet.append(foot)


func animate(delta: float, speed01: float) -> void:
	moving = lerpf(moving, speed01, minf(delta * 8.0, 1.0))
	_phase += delta * (5.0 + 7.0 * moving)
	var sw: float = sin(_phase) * moving
	_body.position.y = absf(sin(_phase)) * 0.08 * moving + sin(Time.get_ticks_msec() * 0.0025) * 0.012
	_body.rotation.z = sin(_phase) * 0.1 * moving
	if _feet.size() == 2:
		(_feet[0] as Node3D).position.z = 0.08 + sw * 0.1
		(_feet[1] as Node3D).position.z = 0.08 - sw * 0.1
	if _arms.size() == 2:
		(_arms[0] as Node3D).rotation.x = sw * 0.7
		(_arms[1] as Node3D).rotation.x = -sw * 0.7
	_blink -= delta
	if _blink < 0.0 and _eyes:
		_blink = randf_range(2.0, 5.0)
		var t := create_tween()
		t.tween_property(_eyes, "scale:y", 0.1, 0.06)
		t.tween_property(_eyes, "scale:y", 1.0, 0.08)


func bounce() -> void:
	var t := create_tween()
	t.tween_property(self, "position:y", 0.22, 0.12).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:y", 0.0, 0.14).set_ease(Tween.EASE_IN)
