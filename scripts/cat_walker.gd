class_name CatWalker
extends Node2D
## Кот, который ходит по комнате кафе: игрок (официант) или гуляющий посетитель.
## Начало координат — «ноги». Кот — одна клетка 16×16; в кафе ходит по центрам клеток (путь — CafeRoom.find_path),
## на улице — по тротуару (StreetNav). Куда идти, определяет `nav`, поэтому одного кота можно переносить между ними.

signal arrived

const SHEET_DIR := "res://assets/cats/"
const SPEED := 96.0   # 3 клетки в секунду
const WALK_FPS := 7.0
const FRAME := 16

var wander := false         # гуляющий кот сам выбирает, куда идти
var def: Dictionary = {}
var nav: Object   # CafeRoom (в кафе) или StreetNav (на улице): find_path, is_blocked, random_free_point

var facing := "front"       # "front" (вниз) | "side" (вбок, лист нарисован вправо) | "back" (вверх)

var _sprite: Sprite2D
var _shadow: Sprite2D
var _sheets := {}           # вид -> лист 64×32
var _path := PackedVector2Array()
var _path_i := 0
var _anim_t := 0.0
var _idle_left := 0.0
var _hop: Tween


func setup(navigation: Object, cat_def: Dictionary) -> void:
	nav = navigation
	def = cat_def
	# у каждого кота три листа: cat-<имя>-front / -side / -back (в def["sprite"] указан front)
	var base := String(def["sprite"]).trim_suffix("-front.png")
	for view in ["front", "side", "back"]:
		_sheets[view] = load(SHEET_DIR + "%s-%s.png" % [base, view]) as Texture2D
	_shadow = PixelArt.sprite(PixelArt.blob(8, 3), Vector2.ZERO)   # пиксельная тень под лапками
	_shadow.modulate = Color(1, 1, 1, 0.6)
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.texture = _sheets["front"]
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
	var p: PackedVector2Array = nav.find_path(position, target)
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
	if not nav.is_blocked(nx):
		position = nx
		moved = true
	var ny := position + Vector2(0.0, step.y)
	if not nav.is_blocked(ny):
		position = ny
		moved = true
	if moved:
		_animate(dir, delta)
	else:
		_set_frame(0)
	return moved


## Подключает материал обрезки рентгена (мебель и гости внутри здания видны только в круге).
func use_clip_material(mat: Material) -> void:
	material = mat
	_sprite.use_parent_material = true
	_shadow.use_parent_material = true


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
				if walk_to(nav.random_free_point()):
					break


## Вид по направлению: вбок — боковой лист (отражается, когда идём влево), вверх — спиной, вниз — лицом.
func _face(dir: Vector2) -> void:
	if absf(dir.x) >= absf(dir.y):
		facing = "side"
		_sprite.flip_h = dir.x < 0.0
	else:
		facing = "back" if dir.y < 0.0 else "front"
		_sprite.flip_h = false
	_sprite.texture = _sheets[facing]


func _animate(dir: Vector2, delta: float) -> void:
	_face(dir)
	_anim_t += delta * WALK_FPS
	_set_frame(int(_anim_t) % 4)
	_sprite.position.y = -FRAME * CafeRoom.S + 2.0 - absf(sin(_anim_t * PI / 2.0)) * float(Ui.PX)


func _set_frame(i: int) -> void:
	_sprite.region_rect = Rect2(i * FRAME, FRAME, FRAME, FRAME)  # нижний ряд листа: 4 кадра
	if i == 0:
		_sprite.position.y = -FRAME * CafeRoom.S + 2.0
