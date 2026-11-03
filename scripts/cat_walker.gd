class_name CatWalker
extends Node2D
## Кот, который ходит по комнате кафе: игрок (официант) или гуляющий посетитель.
## Начало координат — «ноги». Кот — одна клетка 16×16 и ходит по центрам клеток (путь — CafeRoom.find_path).

signal arrived

const SHEET_DIR := "res://assets/cats/"
const SPEED := 96.0   # 3 клетки в секунду
const WALK_FPS := 7.0
const FRAME := 16

var wander := false         # гуляющий кот сам выбирает, куда идти
var def: Dictionary = {}
var room: CafeRoom

var _sprite: Sprite2D
var _path := PackedVector2Array()
var _path_i := 0
var _anim_t := 0.0
var _idle_left := 0.0
var _hop: Tween


func setup(cafe_room: CafeRoom, cat_def: Dictionary) -> void:
	room = cafe_room
	def = cat_def
	_sprite = Sprite2D.new()
	_sprite.texture = load(SHEET_DIR + String(def["sprite"])) as Texture2D
	_sprite.region_enabled = true
	_sprite.centered = false
	_sprite.scale = Vector2(CafeRoom.S, CafeRoom.S)
	_sprite.position = Vector2(-FRAME * CafeRoom.S / 2.0, -FRAME * CafeRoom.S + 2.0)
	_sprite.modulate = Color(String(def.get("tint", "#ffffff")))
	add_child(_sprite)
	_set_frame(0)
	_idle_left = randf_range(0.5, 3.0)


func is_moving() -> bool:
	return _path_i < _path.size()


## Идти к точке. false — пути нет (кот остаётся на месте).
func walk_to(target: Vector2) -> bool:
	var p := room.find_path(position, target)
	if p.is_empty():
		return false
	_path = p
	_path_i = 0
	return true


func stop() -> void:
	_path = PackedVector2Array()
	_path_i = 0


## Шаг по клавиатуре: dir — направление. Возвращает true, если сдвинулся.
func nudge(dir: Vector2, delta: float) -> bool:
	stop()
	var step := dir.normalized() * SPEED * delta
	var moved := false
	var nx := position + Vector2(step.x, 0.0)
	if not room.is_blocked(nx):
		position = nx
		moved = true
	var ny := position + Vector2(0.0, step.y)
	if not room.is_blocked(ny):
		position = ny
		moved = true
	if moved:
		_animate(dir, delta)
	else:
		_set_frame(0)
	return moved


func hop() -> void:
	if _hop:
		_hop.kill()
	_hop = create_tween()
	_hop.tween_property(_sprite, "position:y", _sprite.position.y - 8.0, 0.1)
	_hop.tween_property(_sprite, "position:y", -FRAME * CafeRoom.S + 2.0, 0.1)


func _process(delta: float) -> void:
	step(delta)


## Один шаг симуляции (отдельный метод, чтобы тест мог прогонять время без кадров).
func step(delta: float) -> void:
	if is_moving():
		var target := _path[_path_i]
		var to := target - position
		var dist := to.length()
		var move := SPEED * delta
		if dist <= move:
			position = target
			_path_i += 1
			if not is_moving():
				_set_frame(0)
				arrived.emit()
		else:
			position += to / dist * move
			_animate(to, delta)
	elif wander:
		_idle_left -= delta
		if _idle_left <= 0.0:
			_idle_left = randf_range(2.0, 6.0)
			for _i in 5:
				if walk_to(room.random_free_point()):
					break


func _animate(dir: Vector2, delta: float) -> void:
	_anim_t += delta * WALK_FPS
	_set_frame(int(_anim_t) % 4)
	_sprite.position.y = -FRAME * CafeRoom.S + 2.0 - absf(sin(_anim_t * PI / 2.0)) * float(Ui.PX)
	if absf(dir.x) > 0.1:
		_sprite.flip_h = dir.x < 0.0


func _set_frame(i: int) -> void:
	_sprite.region_rect = Rect2(i * FRAME, FRAME, FRAME, FRAME)  # нижний ряд листа: 4 кадра
	if i == 0:
		_sprite.position.y = -FRAME * CafeRoom.S + 2.0


func _draw() -> void:
	# мягкая тень под лапками
	var pts := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		pts.append(Vector2(roundf(cos(a) * 11.0), roundf(sin(a) * 4.0)))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.22))
