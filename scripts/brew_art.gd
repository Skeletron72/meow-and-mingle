class_name BrewArt
extends Node2D
## Пиксельная графика сцены готовки (рисуется кодом, все размеры кратны пикселю арта = 2 px):
## стена с полками и вывеской, прилавок (столешница + фасад), рабочий стол с тарелками, лампы и корзина.
## Один узел — одна часть сцены: так прилавок можно рисовать поверх кота, а стол — отдельно.

enum Part { WALL, COUNTER, TABLE }

const TOP_Y := 268.0       # задний край столешницы прилавка (кот стоит за ним)
const FRONT_Y := 332.0     # верх фасада прилавка
const TABLE_Y := 396.0     # верх рабочего стола

const WALL := Color("cdb892")
const WALL_STRIPE := Color("d8c6a3")
const BASEBOARD := Color("a98763")
const COUNTER_TOP := Color("d39b5e")
const COUNTER_TOP_D := Color("b97f48")
const COUNTER_TOP_L := Color("ecbf82")
const FRONT := Color("8b5a33")
const FRONT_D := Color("5f3b20")
const FRONT_L := Color("a87244")
const PLINTH := Color("4a2e1a")
const TABLE := Color("b98552")
const TABLE_B := Color("ab7849")
const TABLE_SEAM := Color("8d5d34")
const TABLE_GRAIN := Color("9a6a3c")
const TABLE_L := Color("dcae74")
const PLATE := Color("f4ecd8")
const PLATE_RIM := Color("d4c6a6")

var part := Part.WALL
var plates: Array[Vector2] = []   # центры тарелок на столе
var plate_radius := 38.0


func _draw() -> void:
	match part:
		Part.WALL:
			_draw_wall()
		Part.COUNTER:
			_draw_counter()
		Part.TABLE:
			_draw_table()


func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)


## Пиксельный диск (строками по 2 px).
func _disc(c: Vector2, r: float, color: Color) -> void:
	var dy := -r
	while dy < r:
		var half := floorf(sqrt(maxf(0.0, r * r - (dy + 1.0) * (dy + 1.0))) / 2.0) * 2.0
		_r(c.x - half, c.y + dy, half * 2.0, 2.0, color)
		dy += 2.0


func _draw_wall() -> void:
	_r(0, 0, 360, TOP_Y, WALL)
	for x in range(20, 360, 64):
		_r(x, 0, 32, 236, WALL_STRIPE)
	_r(0, 236, 360, 16, BASEBOARD)
	_r(0, 248, 360, 4, BASEBOARD.darkened(0.35))
	# вывеска на цепочках
	for cx in [104, 256]:
		_r(cx, 44, 2, 14, Color("4a4256"))
	_r(76, 56, 208, 40, Color("3f2815"))
	_r(80, 60, 200, 32, Color("6b4527"))
	_r(80, 60, 200, 4, Color("8a5a34"))
	_r(84, 64, 192, 24, Color("8a5a34").darkened(0.1))
	# полки по бокам от кота
	for sx in [8.0, 288.0]:
		_r(sx, 200, 64, 8, Color("8a5a34"))
		_r(sx, 200, 64, 2, Color("b98552"))
		_r(sx, 208, 64, 4, Color("3f2815"))
		_r(sx + 6, 208, 6, 14, Color("5f3b20"))
		_r(sx + 52, 208, 6, 14, Color("5f3b20"))
	# затенение по углам и под потолком: дизеринг, а не плавный градиент
	draw_texture_rect(PixelArt.dither_gradient(180, 10, false, false), Rect2(0, 0, 360, 20), false, Color(0, 0, 0, 0.30))
	draw_texture_rect(PixelArt.dither_gradient(10, 134, true, false), Rect2(0, 0, 20, 268), false, Color(0, 0, 0, 0.22))
	draw_texture_rect(PixelArt.dither_gradient(10, 134, true, true), Rect2(340, 0, 20, 268), false, Color(0, 0, 0, 0.22))


func _draw_counter() -> void:
	# столешница сверху: задний край, доски, передняя кромка
	_r(0, TOP_Y, 360, FRONT_Y - TOP_Y, COUNTER_TOP)
	for y in [286.0, 304.0]:
		_r(0, y, 360, 2, COUNTER_TOP_D)
	var offs := [34.0, 150.0, 262.0]
	for i in 3:   # стыки досок вразбежку
		var row_y := TOP_Y + i * 18.0
		_r(offs[i] + (i % 2) * 40.0, row_y, 2, 18, COUNTER_TOP_D)
		_r(offs[(i + 1) % 3] + 190.0 - (i % 2) * 60.0, row_y, 2, 18, COUNTER_TOP_D)
	_r(0, TOP_Y, 360, 4, COUNTER_TOP_D.darkened(0.2))
	_r(0, FRONT_Y - 8, 360, 6, COUNTER_TOP_L)
	_r(0, FRONT_Y - 2, 360, 2, COUNTER_TOP_D)
	# фасад: филёнки
	_r(0, FRONT_Y, 360, 56, FRONT)
	_r(0, FRONT_Y, 360, 4, FRONT_L)
	for i in 4:
		var x := 10.0 + i * 88.0
		_r(x, 344, 76, 34, FRONT_D)
		_r(x + 4, 348, 68, 26, FRONT)
		_r(x + 4, 348, 68, 2, FRONT_L)
		_r(x + 4, 372, 68, 2, FRONT_D.lightened(0.05))
	_r(0, 380, 360, 8, PLINTH)
	draw_texture_rect(PixelArt.dither_gradient(180, 10, false, false), Rect2(0, 388, 360, 20), false, Color(0, 0, 0, 0.45))   # тень прилавка на стол


func _draw_table() -> void:
	_r(0, TABLE_Y, 360, 244, TABLE)
	for i in 7:
		var y := TABLE_Y + i * 36.0
		_r(0, y, 360, 36, TABLE if i % 2 == 0 else TABLE_B)
		_r(0, y, 360, 2, TABLE_SEAM)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for _i in 46:   # волокна дерева
		_r(snappedf(rng.randf_range(0, 330), 2.0), snappedf(rng.randf_range(TABLE_Y + 8, 636), 2.0), snappedf(rng.randf_range(12, 34), 2.0), 2, TABLE_GRAIN)
	_r(0, TABLE_Y, 360, 6, TABLE_L)
	_r(0, TABLE_Y + 6, 360, 2, TABLE_SEAM)
	for c in plates:   # тарелки: тень, борт, дно
		_disc(c + Vector2(0, 6), plate_radius, Color(0, 0, 0, 0.22))
		_disc(c, plate_radius, PLATE_RIM)
		_disc(c, plate_radius - 4.0, PLATE)
		_disc(c + Vector2(0, 2), plate_radius - 14.0, PLATE.darkened(0.04))


## Подвесная лампа: покачивается на шнуре; свет — additive-ореол.
class PendantLamp extends Node2D:
	var halo: Sprite2D

	func _ready() -> void:
		halo = Fx.pixel_light(Vector2(0, 74), Vector2(200, 160), Color(1.0, 0.82, 0.45, 0.5))
		add_child(halo)
		var base_x := position.x
		var sway := create_tween().set_loops()   # качается шагами по 2 px — чистые пиксели, без поворота
		sway.tween_method(func(u: float) -> void: position.x = base_x + roundf(sin(u * TAU) * 2.0 / 2.0) * 2.0, 0.0, 1.0, 3.2)
		var f := create_tween().set_loops()   # лёгкое мерцание
		f.tween_property(halo, "modulate:a", 0.38, 0.9).set_trans(Tween.TRANS_SINE)
		f.tween_property(halo, "modulate:a", 0.55, 1.1).set_trans(Tween.TRANS_SINE)

	func _draw() -> void:
		draw_rect(Rect2(-1, 0, 2, 46), Color("4a4256"))
		for i in 6:   # колпак ступеньками
			var w := 16.0 + i * 6.0
			draw_rect(Rect2(-w / 2.0, 44 + i * 4, w, 4), Color("c9573a").lightened(i * 0.03))
		draw_rect(Rect2(-4, 68, 8, 6), Color("ffe9a0"))


## Корзина для брака: подпрыгивает крышкой, когда в неё бросают.
class Bin extends Node2D:
	var lid_dy := 0.0:
		set(v):
			lid_dy = v
			queue_redraw()

	func hop() -> void:
		var t := create_tween()
		t.tween_property(self, "lid_dy", -10.0, 0.08)
		t.tween_property(self, "lid_dy", 0.0, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		for i in 9:   # корпус ступеньками, сужается книзу
			var w := 32.0 - i * 1.0
			draw_rect(Rect2(-w / 2.0, -4 + i * 4, w, 4), Color("7d8594").darkened(i * 0.02))
		for x in [-8.0, 0.0, 8.0]:
			draw_rect(Rect2(x, 2, 2, 26), Color("5c6270"))
		draw_rect(Rect2(-18, -10 + lid_dy, 36, 6), Color("a1a9b8"))
		draw_rect(Rect2(-6, -14 + lid_dy, 12, 4), Color("a1a9b8"))
