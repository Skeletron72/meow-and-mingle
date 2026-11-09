class_name CharacterModel
extends Node3D
## Процедурный человечек-смотритель с настройкой внешности.

const SKINS: Array = [
	Color(1.00, 0.87, 0.76), Color(0.96, 0.78, 0.62), Color(0.86, 0.64, 0.46),
	Color(0.72, 0.50, 0.35), Color(0.55, 0.37, 0.26), Color(0.40, 0.27, 0.20),
]
const HAIRS: Array = [
	Color(0.20, 0.14, 0.11), Color(0.42, 0.26, 0.16), Color(0.84, 0.66, 0.34), Color(0.86, 0.42, 0.22),
	Color(0.12, 0.12, 0.16), Color(0.76, 0.76, 0.80), Color(0.42, 0.56, 0.88), Color(0.88, 0.52, 0.72),
]
const OUTFITS: Array = [
	Color(0.30, 0.54, 0.62), Color(0.80, 0.42, 0.36), Color(0.46, 0.62, 0.38), Color(0.88, 0.66, 0.30),
	Color(0.56, 0.44, 0.68), Color(0.32, 0.38, 0.58), Color(0.90, 0.56, 0.64), Color(0.52, 0.52, 0.55),
]
const HAIR_STYLE_NAMES: Array[String] = ["Короткая", "Каре", "Хвостики", "Пучок", "Длинные"]
const EYE_NAMES: Array[String] = ["Бусинки", "Весёлые", "Большие"]

var look: Dictionary = {}
var _body: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _eyes: Node3D
var _phase: float = 0.0
var _blink: float = 2.0
var _action_tween: Tween
var moving: float = 0.0
var _sit: bool = false


static func default_look() -> Dictionary:
	return {"skin": 1, "hair": 1, "hair_color": 1, "eyes": 1, "outfit": 0, "cap": true}


func build(l: Dictionary) -> void:
	look = l
	for c in get_children():
		c.queue_free()
	var skin: Color = SKINS[int(l.get("skin", 1)) % SKINS.size()]
	var hair: Color = HAIRS[int(l.get("hair_color", 1)) % HAIRS.size()]
	var outfit: Color = OUTFITS[int(l.get("outfit", 0)) % OUTFITS.size()]
	var shirt: Color = Color(0.96, 0.92, 0.84)
	var pants: Color = Color(0.36, 0.33, 0.42)

	_body = Node3D.new()
	add_child(_body)

	# торс
	var k := MeshKit.new()
	k.cyl(Vector3(0, 0.3, 0), 0.27, 0.22, 0.46, shirt, 10)
	k.cyl(Vector3(0, 0.34, 0), 0.285, 0.235, 0.34, outfit, 10) # жилет
	k.box(Vector3(0, 0.37, 0.265), Vector3(0.05, 0.3, 0.02), Color(0.95, 0.8, 0.4))
	_part(_body, k, Vector3.ZERO)

	# голова
	_head = Node3D.new()
	_head.position = Vector3(0, 0.98, 0)
	_body.add_child(_head)
	var hk := MeshKit.new()
	hk.ball(Vector3(0, 0, 0), Vector3(0.37, 0.34, 0.35), skin, 12, 8)
	# щёки, нос
	hk.ball(Vector3(-0.2, -0.07, 0.29), Vector3(0.07, 0.04, 0.03), Color(1.0, 0.55, 0.55), 6, 3)
	hk.ball(Vector3(0.2, -0.07, 0.29), Vector3(0.07, 0.04, 0.03), Color(1.0, 0.55, 0.55), 6, 3)
	hk.ball(Vector3(0, -0.03, 0.34), Vector3(0.035, 0.03, 0.03), skin.darkened(0.08), 5, 3)
	hk.box(Vector3(0, -0.13, 0.33), Vector3(0.09, 0.016, 0.02), Color(0.55, 0.28, 0.28))
	hk.ball(Vector3(-0.37, -0.01, 0), Vector3(0.045, 0.06, 0.04), skin.darkened(0.05), 5, 3)
	hk.ball(Vector3(0.37, -0.01, 0), Vector3(0.045, 0.06, 0.04), skin.darkened(0.05), 5, 3)
	_hair(hk, int(l.get("hair", 1)), hair)
	if bool(l.get("cap", true)):
		_cap(hk)
	_part(_head, hk, Vector3.ZERO)
	_eyes = Node3D.new()
	_head.add_child(_eyes)
	_make_eyes(int(l.get("eyes", 1)))

	# руки
	_arm_l = _limb(Vector3(-0.31, 0.5, 0), outfit, shirt, skin, true)
	_arm_r = _limb(Vector3(0.31, 0.5, 0), outfit, shirt, skin, true)
	# ноги
	_leg_l = _limb(Vector3(-0.12, 0.17, 0), pants, pants, Color(0.30, 0.22, 0.20), false)
	_leg_r = _limb(Vector3(0.12, 0.17, 0), pants, pants, Color(0.30, 0.22, 0.20), false)
	_body.add_child(_arm_l)
	_body.add_child(_arm_r)
	_body.add_child(_leg_l)
	_body.add_child(_leg_r)


func _part(parent: Node3D, k: MeshKit, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = k.build()
	mi.position = pos
	parent.add_child(mi)
	return mi


func _limb(pivot_pos: Vector3, c1: Color, c2: Color, end: Color, arm: bool) -> Node3D:
	var n := Node3D.new()
	n.position = pivot_pos
	var k := MeshKit.new()
	if arm:
		k.cyl(Vector3(0, -0.3, 0), 0.075, 0.09, 0.32, c1, 7)
		k.ball(Vector3(0, -0.33, 0), Vector3(0.08, 0.08, 0.08), end, 6, 4)
	else:
		k.cyl(Vector3(0, -0.12, 0), 0.085, 0.09, 0.24, c1, 7)
		k.ball(Vector3(0, -0.15, 0.04), Vector3(0.11, 0.07, 0.15), end, 6, 4)
	_part(n, k, Vector3.ZERO)
	return n


func _hair(k: MeshKit, style: int, c: Color) -> void:
	var c2: Color = c.lightened(0.08)
	match style:
		0:
			k.ball(Vector3(0, 0.1, -0.03), Vector3(0.39, 0.30, 0.38), c, 10, 6)
			k.ball(Vector3(0.05, 0.2, 0.2), Vector3(0.28, 0.1, 0.18), c2, 7, 4)
		1:
			k.ball(Vector3(0, 0.07, -0.04), Vector3(0.42, 0.34, 0.41), c, 10, 6)
			k.ball(Vector3(-0.35, -0.12, -0.02), Vector3(0.12, 0.2, 0.2), c, 6, 4)
			k.ball(Vector3(0.35, -0.12, -0.02), Vector3(0.12, 0.2, 0.2), c, 6, 4)
			k.ball(Vector3(0, 0.2, 0.2), Vector3(0.3, 0.1, 0.18), c2, 7, 4)
		2:
			k.ball(Vector3(0, 0.1, -0.03), Vector3(0.39, 0.30, 0.38), c, 10, 6)
			k.ball(Vector3(-0.46, -0.2, -0.05), Vector3(0.13, 0.2, 0.13), c, 6, 4)
			k.ball(Vector3(0.46, -0.2, -0.05), Vector3(0.13, 0.2, 0.13), c, 6, 4)
			k.ball(Vector3(0, 0.2, 0.2), Vector3(0.3, 0.1, 0.18), c2, 7, 4)
		3:
			k.ball(Vector3(0, 0.1, -0.03), Vector3(0.39, 0.30, 0.38), c, 10, 6)
			k.ball(Vector3(0, 0.42, -0.08), Vector3(0.17, 0.17, 0.17), c2, 7, 5)
			k.ball(Vector3(0, 0.2, 0.2), Vector3(0.3, 0.1, 0.18), c2, 7, 4)
		_:
			k.ball(Vector3(0, 0.08, -0.04), Vector3(0.42, 0.34, 0.41), c, 10, 6)
			k.ball(Vector3(0, -0.3, -0.26), Vector3(0.34, 0.52, 0.14), c, 8, 5)
			k.ball(Vector3(0, 0.2, 0.2), Vector3(0.3, 0.1, 0.18), c2, 7, 4)


func _cap(k: MeshKit) -> void:
	var navy: Color = Color(0.22, 0.28, 0.42)
	k.cyl(Vector3(0, 0.2, -0.02), 0.4, 0.34, 0.16, navy, 10)
	k.cyl(Vector3(0, 0.34, -0.02), 0.34, 0.3, 0.05, Color(0.26, 0.33, 0.48), 10)
	k.box(Vector3(0, 0.22, 0.38), Vector3(0.44, 0.04, 0.2), Color(0.16, 0.2, 0.3))
	k.ball(Vector3(0, 0.3, 0.33), Vector3(0.06, 0.06, 0.03), Color(0.95, 0.78, 0.30), 6, 4)


func _make_eyes(style: int) -> void:
	for c in _eyes.get_children():
		c.queue_free()
	var k := MeshKit.new()
	for sx in [-1.0, 1.0]:
		var x: float = 0.14 * sx
		match style:
			0:
				k.ball(Vector3(x, 0.02, 0.325), Vector3(0.04, 0.05, 0.03), Color(0.1, 0.08, 0.1), 6, 4)
			1:
				k.ball(Vector3(x, 0.02, 0.325), Vector3(0.05, 0.065, 0.03), Color(0.1, 0.08, 0.1), 6, 4)
				k.ball(Vector3(x + 0.012, 0.045, 0.345), Vector3(0.015, 0.015, 0.01), Color(1, 1, 1), 4, 3)
			_:
				k.ball(Vector3(x, 0.02, 0.322), Vector3(0.07, 0.085, 0.035), Color(0.12, 0.09, 0.12), 8, 5)
				k.ball(Vector3(x + 0.02, 0.05, 0.352), Vector3(0.025, 0.028, 0.012), Color(1, 1, 1), 5, 3)
				k.ball(Vector3(x - 0.02, -0.01, 0.35), Vector3(0.012, 0.012, 0.01), Color(1, 1, 1), 4, 3)
	_part(_eyes, k, Vector3.ZERO)


func animate(delta: float, speed01: float) -> void:
	moving = lerpf(moving, speed01, minf(delta * 10.0, 1.0))
	_phase += delta * (6.0 + 6.0 * moving) * (0.4 + 0.6 * moving)
	var sw: float = sin(_phase) * 0.7 * moving
	if _action_tween == null or not _action_tween.is_running():
		_arm_l.rotation.x = sw
		_arm_r.rotation.x = -sw
	if not _sit:
		_leg_l.rotation.x = -sw
		_leg_r.rotation.x = sw
	_body.position.y = absf(sin(_phase)) * 0.06 * moving + sin(Time.get_ticks_msec() * 0.003) * 0.008 * (1.0 - moving)
	_body.rotation.z = sin(_phase) * 0.04 * moving
	_blink -= delta
	if _blink < 0.0:
		_blink = randf_range(2.0, 5.0)
		var t := create_tween()
		t.tween_property(_eyes, "scale:y", 0.1, 0.06)
		t.tween_property(_eyes, "scale:y", 1.0, 0.08)


func set_sitting(on: bool) -> void:
	if on:
		_leg_l.rotation.x = -1.45
		_leg_r.rotation.x = -1.45
		_sit = true
	else:
		_sit = false


## Короткие «действия»: взмах сачка, копание, заброс удочки, радость.
func play_action(kind: String) -> void:
	if _action_tween and _action_tween.is_running():
		_action_tween.kill()
	_action_tween = create_tween()
	match kind:
		"swing":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.6, 0.12)
			_action_tween.tween_property(_arm_r, "rotation:x", -0.4, 0.18)
			_action_tween.tween_property(_arm_r, "rotation:x", 0.0, 0.2)
		"dig":
			for i in 2:
				_action_tween.tween_property(_arm_r, "rotation:x", -1.8, 0.14)
				_action_tween.parallel().tween_property(_body, "rotation:x", 0.35, 0.14)
				_action_tween.tween_property(_arm_r, "rotation:x", -0.2, 0.14)
				_action_tween.parallel().tween_property(_body, "rotation:x", 0.0, 0.14)
		"cast":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.4, 0.2)
			_action_tween.tween_property(_arm_r, "rotation:x", -0.9, 0.2)
		"hold":
			_action_tween.tween_property(_arm_r, "rotation:x", -0.9, 0.15)
		"cheer":
			_action_tween.tween_property(_arm_l, "rotation:x", -2.9, 0.15)
			_action_tween.parallel().tween_property(_arm_r, "rotation:x", -2.9, 0.15)
			_action_tween.parallel().tween_property(self, "position:y", position.y + 0.25, 0.15)
			_action_tween.tween_property(self, "position:y", position.y, 0.15)
			_action_tween.tween_property(_arm_l, "rotation:x", 0.0, 0.25)
			_action_tween.parallel().tween_property(_arm_r, "rotation:x", 0.0, 0.25)
		"wave":
			for i in 3:
				_action_tween.tween_property(_arm_r, "rotation:z", -2.4, 0.15)
				_action_tween.tween_property(_arm_r, "rotation:z", -1.8, 0.15)
			_action_tween.tween_property(_arm_r, "rotation:z", 0.0, 0.2)
		"rest":
			_action_tween.tween_property(_arm_r, "rotation:x", 0.0, 0.1)
