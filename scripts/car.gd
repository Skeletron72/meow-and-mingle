class_name Car
extends Node2D
## Машина на дороге: едет вдоль улицы. Лист из `assets/street/vehicles` — 4×3 кадра «покачивания» (12 fps).
## Начало координат — низ колёс по центру.

const SHEET_DIR := "res://assets/street/vehicles/"
const FPS := 12.0
const ACCEL := 90.0
const BRAKE := 220.0

var speed := 90.0       # текущая скорость, px/с
var desired := 90.0     # желаемая скорость, когда впереди никого нет
var dir := 1            # 1 — на восток (вправо), -1 — на запад
var frame := Vector2i(84, 40)   # размер кадра в пикселях арта
var halo: Sprite2D      # свет фар (лежит в слое свечения города, двигаем снаружи)

var _sprite: Sprite2D
var _t := 0.0


func setup(def: Dictionary, direction: int) -> void:
	dir = direction
	var f: Array = def["frame"]
	frame = Vector2i(int(f[0]), int(f[1]))
	_sprite = Sprite2D.new()
	_sprite.texture = load(SHEET_DIR + "%s_%s.png" % [def["id"], "east" if dir > 0 else "west"]) as Texture2D
	_sprite.region_enabled = true
	_sprite.centered = false
	_sprite.scale = Vector2(CafeRoom.S, CafeRoom.S)
	_sprite.position = Vector2(-frame.x * CafeRoom.S / 2.0, -frame.y * CafeRoom.S)
	add_child(_sprite)
	_set_frame(0)
	_t = randf() * 12.0


func width() -> float:
	return frame.x * CafeRoom.S


## Где у машины фары (в её координатах): впереди, на уровне капота.
func headlight_offset() -> Vector2:
	return Vector2(dir * (width() / 2.0 - 4.0), -frame.y * CafeRoom.S * 0.35)


## Один шаг движения. gap — свободное расстояние до идущей впереди машины (INF — дорога пуста), lead_speed — её скорость.
## Скорость выбирается так, чтобы успеть остановиться в зазоре (за min_gap до неё), и меняется плавно.
func drive(delta: float, gap: float, lead_speed: float, min_gap: float) -> void:
	var target := desired
	if gap < INF:
		var room := maxf(0.0, gap - min_gap)
		target = minf(desired, sqrt(2.0 * BRAKE * room) + lead_speed * 0.5)
		if room <= 0.0:
			target = minf(target, lead_speed)
	speed = move_toward(speed, target, (ACCEL if target > speed else BRAKE) * delta)
	position.x += dir * speed * delta


func _process(delta: float) -> void:
	_t += delta * FPS * clampf(speed / 90.0, 0.3, 1.5)   # колёса крутятся быстрее на скорости
	_set_frame(int(_t) % 12)


func _set_frame(i: int) -> void:
	_sprite.region_rect = Rect2((i % 4) * frame.x, (i / 4) * frame.y, frame.x, frame.y)


func _draw() -> void:
	var pts := PackedVector2Array()
	var rx := width() / 2.0 - 4.0
	for k in 20:
		var a := TAU * k / 20.0
		pts.append(Vector2(roundf(cos(a) * rx), roundf(sin(a) * 6.0)))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.22))
