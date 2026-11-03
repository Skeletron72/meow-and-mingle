class_name CatCustomer
extends Node2D
## Кот-посетитель за прилавком: заходит вприпрыжку, ждёт (дышит, моргает), радуется или качает головой, уходит.
## Заказ и награды живут в main.gd.

signal arrived
signal left

const SPRITE_DIR := "res://assets/cats/"
const FRAME_IDLE := Rect2(0, 16, 16, 16)   # нижний ряд листа 64x32, первый кадр (кот анфас)
const FRAME_BLINK := Rect2(32, 0, 16, 16)  # верхний ряд: «сжавшийся» кадр — моргание
const PIXEL_SCALE := 4.0

var def: Dictionary = {}
var _sprite: Sprite2D
var _idle: Tween
var _blink: Timer
var _leaving := false


func setup(cat_def: Dictionary) -> void:
	def = cat_def
	_sprite = Sprite2D.new()
	_sprite.texture = load(SPRITE_DIR + String(def["sprite"])) as Texture2D
	_sprite.region_enabled = true
	_sprite.region_rect = FRAME_IDLE
	_sprite.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	_sprite.modulate = Color(String(def.get("tint", "#ffffff")))
	add_child(_sprite)
	_blink = Timer.new()
	_blink.one_shot = true
	_blink.timeout.connect(_do_blink)
	add_child(_blink)


## Центр кота (для эффектов): чуть выше «ног».
func center() -> Vector2:
	return global_position + Vector2(0, -6)


func enter(target_x: float) -> void:
	var dist := absf(position.x - target_x)
	var time := dist / 380.0 + 0.4
	var t := create_tween()
	var from_x := position.x
	t.tween_method(func(u: float) -> void: position.x = snappedf(lerpf(from_x, target_x, u), PIXEL_SCALE), 0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var bob := create_tween()   # шаги: подпрыгивает на ходу
	bob.tween_method(_walk_bob, 0.0, 1.0, time)
	t.tween_callback(_on_arrived)


func _walk_bob(u: float) -> void:
	_sprite.position.y = -snappedf(absf(sin(u * PI * 9.0)) * 8.0 * (1.0 - u * 0.6), PIXEL_SCALE)   # шаги по целым пикселям


func leave(happy: bool) -> void:
	_leaving = true
	_stop_idle()
	_sprite.position.y = 0.0
	if not happy:
		_sprite.modulate = _sprite.modulate.darkened(0.35)
	var t := create_tween()
	if happy:
		t.tween_callback(func() -> void: _sprite.position.y = -PIXEL_SCALE * 3.0)
		t.tween_interval(0.12)
		t.tween_callback(func() -> void: _sprite.position.y = 0.0)
		t.tween_interval(0.12)
	var from_x := position.x
	t.tween_method(func(u: float) -> void: position.x = snappedf(lerpf(from_x, -80.0, u), PIXEL_SCALE), 0.0, 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var bob := create_tween()
	bob.tween_interval(0.24)
	bob.tween_method(_walk_bob, 0.0, 1.0, 1.0)
	t.tween_callback(func() -> void: left.emit())


## Радость: сплющивание-растяжение с прыжком.
func react_happy() -> void:
	_stop_idle()
	_sprite.position.y = 0.0
	Fx.hop(_sprite, 24.0, 0.45, PIXEL_SCALE)
	get_tree().create_timer(0.5).timeout.connect(_start_idle)


## «Не то!»: качает головой.
func react_no() -> void:
	_stop_idle()
	Fx.shake(_sprite, 8.0, 0.5, 8, PIXEL_SCALE)
	get_tree().create_timer(0.6).timeout.connect(_start_idle)


func _on_arrived() -> void:
	_sprite.position.y = 0.0
	Fx.hop(_sprite, 8.0, 0.3, PIXEL_SCALE)
	_start_idle()
	arrived.emit()


func _start_idle() -> void:
	if _leaving:
		return
	_stop_idle()
	_sprite.position = Vector2.ZERO
	_idle = create_tween().set_loops()
	_idle.tween_interval(0.6)   # «дыхание» целым пикселем: вверх на 4 px и обратно
	_idle.tween_callback(func() -> void: _sprite.position.y = -PIXEL_SCALE)
	_idle.tween_interval(0.6)
	_idle.tween_callback(func() -> void: _sprite.position.y = 0.0)
	_blink.start(randf_range(1.2, 3.5))


func _stop_idle() -> void:
	if _idle:
		_idle.kill()
		_idle = null
	if _blink:
		_blink.stop()


func _do_blink() -> void:
	_sprite.region_rect = FRAME_BLINK
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(_sprite):
			_sprite.region_rect = FRAME_IDLE
			if _idle != null:
				_blink.start(randf_range(1.2, 3.5)))
