class_name BrewArt
extends Node2D
## Пиксельная графика сцены готовки. Сцена — «крупный план»: спрайты (чашки, кот) стоят в масштабе 4, поэтому
## и всё, что рисуется кодом, лежит на той же сетке G = 4 px (пиксель арта крупного плана; клетка 16×16 = 64 px).
## У предметов тёмная обводка в один такой пиксель, как у спрайтов:
## стена с полками и вывеской, прилавок (столешница + фасад), рабочий стол с тарелками, лампы и корзина.
## Один узел — одна часть сцены: так прилавок можно рисовать поверх кота, а стол — отдельно.

enum Part { WALL, COUNTER, TABLE }

const G := 4.0              # пиксель арта в этой сцене (px логических)
const TOP_Y := 268.0       # задний край столешницы прилавка (кот стоит за ним)
const FRONT_Y := 332.0     # верх фасада прилавка
const TABLE_Y := 396.0     # верх рабочего стола
const OUTLINE := Color("2f2030")   # обводка предметов (как у спрайтов)

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
const RACK := Color("46605f")        # плитка за полками
const RACK_D := Color("3a504f")
const RACK_L := Color("587a77")
const SHELF_TOP := Color("dcae74")
const SHELF_FRONT := Color("c0884f")
const SHELF_FRONT_L := Color("d9a468")
const SHELF_FRONT_D := Color("94633a")
const SHELF_STRIDE := 84.0           # полка целиком: предмет 56 + верхняя грань 4 + передняя планка 20 + обводка 4
const SHELF_RACK_Y := 388.0          # верх стеллажа (под фасадом прилавка)

var part := Part.WALL
var plates: Array[Vector2] = []   # центры блюдец под выпечкой на полках (кратны G)
var plate_radius := 36.0
var shelves: Array[float] = []    # верх каждой полки-ряда (кратен G): предметы стоят на ней, подписи — на передней планке


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


## Пиксельный диск (строками по G).
func _disc(c: Vector2, r: float, color: Color) -> void:
	_ellipse(c, r, r, color)


## Пиксельный эллипс: строки по G, ширина строки кратна 2G.
func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	_ellipse_on(self, c, rx, ry, color)


static func _ellipse_on(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color) -> void:
	var dy := -ry
	while dy < ry:
		var k := 1.0 - pow((dy + G / 2.0) / ry, 2.0)
		var half := floorf(rx * sqrt(maxf(0.0, k)) / G) * G
		if half > 0.0:
			ci.draw_rect(Rect2(c.x - half, c.y + dy, half * 2.0, G), color)
		dy += G


## Тот же эллипс, но только в полосе x ∈ [x_min, x_max] (подсветка одной половины подноса).
static func _ellipse_clip(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color, x_min: float, x_max: float) -> void:
	var dy := -ry
	while dy < ry:
		var k := 1.0 - pow((dy + G / 2.0) / ry, 2.0)
		var half := floorf(rx * sqrt(maxf(0.0, k)) / G) * G
		if half > 0.0:
			var x0 := maxf(c.x - half, x_min)
			var x1 := minf(c.x + half, x_max)
			if x1 > x0:
				ci.draw_rect(Rect2(x0, c.y + dy, x1 - x0, G), color)
		dy += G


## Смещение «центра» рисунка в клетке 16×16 от центра клетки, целое число пикселей спрайта.
## Для посуды (bowl = true) центр — это ЧАША (колонки, почти такие же плотные, как самая широкая), без ручки:
## чашку ставят по центру чаши, а не по середине между чашей и ручкой. Для выпечки — середина рисунка.
static func content_offset(tex: Texture2D, bowl := false) -> Vector2:
	var at := tex as AtlasTexture
	if at == null:
		return Vector2.ZERO
	var key := [at.region, bowl]
	if _offsets.has(key):
		return _offsets[key]
	var img := at.atlas.get_image().get_region(Rect2i(at.region))
	var used := img.get_used_rect()
	var off := Vector2.ZERO
	if used.size.x > 0:
		var x0 := float(used.position.x)
		var x1 := float(used.end.x)
		if bowl:
			var counts: Array[int] = []
			var best := 0
			for x in img.get_width():
				var n := 0
				for y in img.get_height():
					if img.get_pixel(x, y).a > 0.0:
						n += 1
				counts.append(n)
				best = maxi(best, n)
			var first := -1
			var last := -1
			for x in counts.size():
				if float(counts[x]) >= best * 0.75:
					if first < 0:
						first = x
					last = x
			x0 = float(first)
			x1 = float(last + 1)
		off = Vector2(roundf((x0 + x1) / 2.0 - img.get_width() / 2.0), roundf(used.position.y + used.size.y / 2.0 - img.get_height() / 2.0))
	_offsets[key] = off
	return off


static var _offsets := {}


## Предмет из строк [y, полуширина, цвет] с обводкой в один пиксель сетки и бликом слева / тенью справа.
static func shape(ci: CanvasItem, rows: Array, outline := OUTLINE, shade := true) -> void:
	for i in rows.size():
		var row: Array = rows[i]
		var y: float = row[0]
		var hw: float = row[1]
		ci.draw_rect(Rect2(-hw - G, y, (hw + G) * 2.0, G), outline)
		if i == 0:
			ci.draw_rect(Rect2(-hw, y - G, hw * 2.0, G), outline)
		if i == rows.size() - 1:
			ci.draw_rect(Rect2(-hw, y + G, hw * 2.0, G), outline)
	for row in rows:
		var y: float = row[0]
		var hw: float = row[1]
		var c: Color = row[2]
		ci.draw_rect(Rect2(-hw, y, hw * 2.0, G), c)
		if shade and hw >= G * 2.0:
			ci.draw_rect(Rect2(-hw, y, G, G), c.lightened(0.18))
			ci.draw_rect(Rect2(hw - G, y, G, G), c.darkened(0.18))


func _draw_wall() -> void:
	_r(0, 0, 360, TOP_Y, WALL)
	for x in range(20, 360, 64):
		_r(x, 0, 32, 236, WALL_STRIPE)
	_r(0, 236, 360, 16, BASEBOARD)
	_r(0, 248, 360, 4, BASEBOARD.darkened(0.35))
	# вывеска на цепочках
	for cx in [100, 252]:   # цепи идут от потолка
		for y in range(0, 56, 8):
			_r(cx, y, 4, 8, Color("4a4256"))
			_r(cx, y + 4, 4, 4, Color("6b6178"))
	_r(76, 56, 208, 40, Color("3f2815"))
	_r(80, 60, 200, 32, Color("6b4527"))
	_r(80, 60, 200, 4, Color("8a5a34"))
	_r(84, 64, 192, 24, Color("8a5a34").darkened(0.1))
	# полки по бокам от кота: на каждой по одной вещи
	for sx in [8.0, 288.0]:
		_r(sx, 200, 64, 8, Color("8a5a34"))
		_r(sx, 200, 64, 4, Color("b98552"))
		_r(sx, 208, 64, 4, Color("3f2815"))
		_r(sx + 8, 212, 8, 12, Color("5f3b20"))
		_r(sx + 48, 212, 8, 12, Color("5f3b20"))
	# затенение по углам и под потолком: дизеринг в пикселях сетки (по 4 px)
	draw_texture_rect(PixelArt.dither_gradient(90, 5, false, false), Rect2(0, 0, 360, 20), false, Color(0, 0, 0, 0.30))
	draw_texture_rect(PixelArt.dither_gradient(5, 67, true, false), Rect2(0, 0, 20, 268), false, Color(0, 0, 0, 0.22))
	draw_texture_rect(PixelArt.dither_gradient(5, 67, true, true), Rect2(340, 0, 20, 268), false, Color(0, 0, 0, 0.22))


func _draw_counter() -> void:
	# столешница сверху: четыре ряда досок по 16, стыки вразбежку
	_r(0, TOP_Y, 360, FRONT_Y - TOP_Y, COUNTER_TOP)
	for i in 4:
		var row_y := TOP_Y + i * 16.0
		_r(0, row_y + 12.0, 360, 4, COUNTER_TOP_D)
		for j in 2:
			var x := floorf(fmod(36.0 + i * 92.0 + j * 180.0, 356.0) / G) * G
			_r(x, row_y, 4, 12, COUNTER_TOP_D)
	_r(0, TOP_Y, 360, 4, COUNTER_TOP_D.darkened(0.2))
	_r(0, FRONT_Y - 12, 360, 8, COUNTER_TOP_L)
	_r(0, FRONT_Y - 4, 360, 4, COUNTER_TOP_D)
	# фасад: филёнки
	_r(0, FRONT_Y, 360, 56, FRONT)
	_r(0, FRONT_Y, 360, 4, FRONT_L)
	for i in 4:
		var x := 12.0 + i * 88.0
		_r(x, 344, 72, 32, FRONT_D)
		_r(x + 4, 348, 64, 24, FRONT)
		_r(x + 4, 348, 64, 4, FRONT_L)
		_r(x + 4, 368, 64, 4, FRONT_D.lightened(0.05))
	_r(0, 380, 360, 8, PLINTH)
	draw_texture_rect(PixelArt.dither_gradient(90, 5, false, false), Rect2(0, 388, 360, 20), false, Color(0, 0, 0, 0.45))   # тень прилавка на стол


func _draw_table() -> void:
	# стеллаж: тёмная плитка с мелким дизерингом, на нём полки с передней планкой под подписи
	_r(0, SHELF_RACK_Y, 360, 640.0 - SHELF_RACK_Y, RACK)
	for y in range(int(SHELF_RACK_Y), 640, 16):   # швы плитки: ряды по 16, стыки вразбежку
		_r(0, y, 360, 4, RACK_D)
		var off := 0.0 if int((y - SHELF_RACK_Y) / 16.0) % 2 == 0 else 32.0
		for x in range(int(off), 360, 64):
			_r(x, y + 4, 4, 12, RACK_D)
	draw_texture_rect(PixelArt.dither_gradient(90, 6, false, false), Rect2(0, SHELF_RACK_Y, 360, 24), false, Color(0, 0, 0, 0.55))   # тень прилавка
	for top in shelves:
		var y := top + 56.0
		_r(0, y + 28.0, 360, 8, Color(0, 0, 0, 0.22))   # тень полки на плитке
		_r(0, y, 360, 4, SHELF_TOP)
		_r(0, y + 4, 360, 20, SHELF_FRONT)
		_r(0, y + 4, 360, 4, SHELF_FRONT_L)
		_r(0, y + 20, 360, 4, SHELF_FRONT_D)
		_r(0, y + 24, 360, 4, OUTLINE)
	for c in plates:   # блюдца под выпечкой: плоский овал на верхней грани полки
		_ellipse(c + Vector2(0, 0), plate_radius + G, 8.0, OUTLINE)
		_ellipse(c + Vector2(0, -G), plate_radius, 8.0, PLATE_RIM)
		_ellipse(c + Vector2(0, -G), plate_radius - 8.0, 4.0, PLATE)


## Подвесная лампа: узел стоит в точке подвеса (у верха кадра), шнур идёт от потолка; качается шагами по 4 px,
## верх шнура неподвижен — как маятник. Свет — additive-ореол.
class PendantLamp extends Node2D:
	const DROP := 48.0   # от точки подвеса до колпака
	var halo: Sprite2D
	var swing := 0:   # -1, 0, 1 — отклонение нижнего конца в пикселях сетки
		set(v):
			swing = v
			if halo != null:
				halo.position.x = v * BrewArt.G
			queue_redraw()

	func _ready() -> void:
		halo = Fx.pixel_light(Vector2(0, DROP + 28.0), Vector2(200, 160), Color(1.0, 0.82, 0.45, 0.5))
		add_child(halo)
		var sway := create_tween().set_loops()
		sway.tween_method(func(u: float) -> void: swing = roundi(sin(u * TAU)), 0.0, 1.0, 3.2)
		var f := create_tween().set_loops()   # лёгкое мерцание
		f.tween_property(halo, "modulate:a", 0.38, 0.9).set_trans(Tween.TRANS_SINE)
		f.tween_property(halo, "modulate:a", 0.55, 1.1).set_trans(Tween.TRANS_SINE)

	func _draw() -> void:
		var g := BrewArt.G
		var rows := int(DROP / g)
		for i in rows:   # шнур: сдвиг растёт книзу, верх на месте
			var off := snappedf(swing * g * float(i) / float(rows - 1), g)
			draw_rect(Rect2(off - 2, i * g, 4, g), BrewArt.OUTLINE)
		draw_set_transform(Vector2(swing * g, DROP - 8.0))
		var cap := Color("6b5f78")
		var red := Color("d65a3c")
		BrewArt.shape(self, [[0, 8, cap], [4, 12, red], [8, 16, red], [12, 20, red], [16, 24, red], [20, 28, red.darkened(0.08)]])
		BrewArt.shape(self, [[28, 8, Color("ffe9a0")]], BrewArt.OUTLINE, false)   # лампочка
		draw_set_transform(Vector2.ZERO)


## Корзина для брака: подпрыгивает крышкой, когда в неё бросают.
class Bin extends Node2D:
	var lid_dy := 0.0:
		set(v):
			lid_dy = v
			queue_redraw()

	func hop() -> void:
		var t := create_tween()
		t.tween_method(func(u: float) -> void: lid_dy = -snappedf(sin(u * PI) * 12.0, 4.0), 0.0, 1.0, 0.28)
		t.tween_callback(func() -> void: lid_dy = 0.0)

	func _draw() -> void:
		var body := Color("7d8594")
		var rows: Array = []
		for i in 7:   # корпус сужается книзу
			rows.append([4 + i * 4, 16 if i < 4 else 12, body])
		BrewArt.shape(self, rows)
		for x in [-8.0, 4.0]:
			draw_rect(Rect2(x, 8, 4, 20), Color("5c6270"))
		var lid := Color("a1a9b8")
		BrewArt.shape(self, [[-8 + lid_dy, 20, lid]])
		BrewArt.shape(self, [[-16 + lid_dy, 8, lid]])
