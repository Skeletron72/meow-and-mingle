class_name SpaceProp
extends Node2D
## Предмет служебных помещений (см. InteriorSpace). Рисуется кодом на сетке арта (2 px), с тёмной обводкой в один пиксель, как мебель кафе.
## Начало координат — низ по центру занятых клеток (так же, как у мебели): сортировка по глубине идёт по нему.
## Виды «sheet:<id>» берут картинку из листа мебели кафе (data/furniture.json).

const OL := Color("2b2230")
const WOOD := Color("9a6a3c")
const WOOD_D := Color("6f4727")
const WOOD_L := Color("c28a50")

var kind_id := "crate"
var cells := Vector2i(1, 1)          # занятые клетки
var cell := Vector2i.ZERO            # левая верхняя клетка
var seed_id := 0
var local_pos := Vector2.ZERO        # положение в координатах пространства
var locked := true                   # для лестницы: заколочена
var glow_lamp: Sprite2D


func is_solid() -> bool:
	return true


func _draw() -> void:
	if kind_id.begins_with("sheet:"):
		_draw_sheet(kind_id.trim_prefix("sheet:"))
		return
	match kind_id:
		"crate": _crate()
		"sack": _sack()
		"shelf": _shelf()
		"fridge": _fridge()
		"sink": _sink()
		"mop": _mop()
		"stairs_up": _stairs_up()
		"bed": _bed()
		"wardrobe": _wardrobe()
		"sofa": _sofa()
		"bookshelf": _bookshelf()
		"lamp": _lamp()
		"stairs_down": _stairs_down()


# ---------------------------------------------------------------- помощники рисования

func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)


## Прямоугольник с обводкой в один пиксель арта (2 px).
func _box(x: float, y: float, w: float, h: float, fill: Color) -> void:
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), OL)
	draw_rect(Rect2(x, y, w, h), fill)


## Силуэт из строк по 2 px: halves — полуширины сверху вниз, y0 — верх.
func _blob(y0: float, halves: Array, fill: Color, shade := true) -> void:
	for i in halves.size():
		var hw: float = halves[i]
		_r(-hw - 2, y0 + i * 2, hw * 2 + 4, 2, OL)
	_r(-float(halves[0]), y0 - 2, float(halves[0]) * 2, 2, OL)
	_r(-float(halves[-1]), y0 + halves.size() * 2, float(halves[-1]) * 2, 2, OL)
	for i in halves.size():
		var hw: float = halves[i]
		_r(-hw, y0 + i * 2, hw * 2, 2, fill)
		if shade and hw >= 6:
			_r(hw - 4, y0 + i * 2, 4, 2, fill.darkened(0.16))
			_r(-hw, y0 + i * 2, 2, 2, fill.lightened(0.14))


func _draw_sheet(id: String) -> void:
	var def := CafeRoom.item_def(id)
	var src: Array = def["rect"]
	var sz := Vector2(float(src[2]), float(src[3])) * 2.0
	var dst := Rect2(floorf(-sz.x / 2.0 / 2.0) * 2.0, -sz.y, sz.x, sz.y)
	draw_texture_rect_region(CafeRoom.FURN_TEX, dst, Rect2(float(src[0]), float(src[1]), float(src[2]), float(src[3])))


# ---------------------------------------------------------------- коморка

func _crate() -> void:
	_box(-14, -26, 28, 26, WOOD)
	_r(-14, -26, 28, 4, WOOD_L)
	for x in [-8.0, 0.0, 8.0]:
		_r(x, -22, 2, 22, WOOD_D)
	_r(-14, -14, 28, 2, WOOD_D)
	_r(-12, -24, 2, 2, Color("d8d8e0"))
	_r(10, -24, 2, 2, Color("d8d8e0"))


func _sack() -> void:
	_blob(-32, [4, 6, 8, 10, 12, 12, 12, 12, 12, 12, 12, 12, 10, 8], Color("d9b98a"))
	_r(-4, -36, 8, 4, Color("7a5a3a"))                 # завязка
	_r(-6, -38, 4, 2, Color("7a5a3a"))
	_r(-4, -20, 8, 8, Color("6b4a2f"))                 # метка: кофейное зерно
	_r(-2, -18, 2, 4, Color("d9b98a"))


func _shelf() -> void:
	_box(-30, -64, 60, 64, Color("4d3b30"))
	for y in [-44.0, -24.0, -4.0]:
		_r(-30, y, 60, 4, Color("8a6a46"))
	var cols := [Color("c9573a"), Color("e8c15a"), Color("5c8fa8"), Color("8dff7a"), Color("f4ecd8")]
	for i in 5:   # верхний ряд: коробки
		var h := 12.0 + float((seed_id + i) % 3) * 2.0
		_r(-27 + i * 11, -44 - h, 9, h, cols[(i + seed_id) % 5])
		_r(-27 + i * 11, -44 - h, 9, 2, Color(1, 1, 1, 0.3))
	for i in 4:   # средний ряд: банки
		_r(-26 + i * 14, -36, 10, 12, cols[(i * 2 + seed_id) % 5])
		_r(-26 + i * 14, -38, 10, 2, Color("c9d0da"))
	for i in 3:   # нижний ряд: мешочки
		_r(-24 + i * 18, -20, 14, 16, Color("d9b98a"))
		_r(-24 + i * 18, -20, 14, 2, Color("7a5a3a"))


func _fridge() -> void:
	_box(-14, -60, 28, 60, Color("e9eef0"))
	_r(10, -60, 4, 60, Color("c3ccd2"))
	_r(-14, -36, 28, 2, Color("98a4ac"))
	_r(8, -52, 2, 10, Color("5c6270"))
	_r(8, -30, 2, 10, Color("5c6270"))
	_r(-8, -48, 4, 4, Color("c9573a"))                # магнит
	_r(-6, -26, 6, 6, Color("e8c15a"))                # записка
	_r(-14, -2, 28, 2, Color("98a4ac"))


func _sink() -> void:
	_r(-30, -58, 60, 18, Color("cfe0e6"))             # плитка над раковиной
	for x in range(-30, 30, 10):
		_r(x, -58, 2, 18, Color("a9c4cc"))
	_r(-30, -50, 60, 2, Color("a9c4cc"))
	_box(-30, -32, 60, 32, Color("7d8594"))
	_r(-2, -30, 2, 28, Color("5c6270"))               # дверцы тумбы
	_box(-32, -40, 64, 8, Color("c9d0da"))
	_r(-18, -39, 24, 5, Color("4a5a70"))              # раковина
	_r(8, -52, 4, 12, Color("c9d0da"))                # кран
	_r(2, -52, 10, 4, Color("c9d0da"))
	_r(2, -48, 2, 4, Color("6fa8d6"))                 # капля


func _mop() -> void:
	_box(-10, -16, 20, 16, Color("c4c9d4"))
	_r(-8, -16, 16, 4, Color("6fa8d6"))
	for i in 11:   # швабра: наклонная палка в 2 пикселя арта, шаг по сетке
		_r(2.0 + i * 2.0, -16.0 - i * 4.0, 4, 4, WOOD_L if i % 2 == 0 else WOOD)
	_r(-6, -22, 10, 4, Color("e8e2d0"))
	_r(-8, -18, 4, 4, Color("e8e2d0"))


func _stairs_up() -> void:
	# лестница в стене: тёмный проём наверху, ступени к зрителю, перила по бокам
	var w := 56.0
	_box(-w / 2.0, -150, w, 96, Color("1d1522"))           # проём
	for i in 6:   # ступени сверху вниз: проступь светлая, подступенок тёмный
		var y := -86.0 + i * 14.0
		var shade := 0.10 * i
		_r(-w / 2.0, y, w, 8, Color("c28a50").darkened(0.32 - shade))
		_r(-w / 2.0, y + 8, w, 6, WOOD_D.darkened(0.2 - shade * 0.5))
	_r(-w / 2.0 - 6, -150, 6, 150, WOOD_D)                  # тетивы и перила
	_r(w / 2.0, -150, 6, 150, WOOD_D)
	_r(-w / 2.0 - 8, -150, 2, 150, OL)
	_r(w / 2.0 + 6, -150, 2, 150, OL)
	for y in [-120.0, -80.0, -40.0]:
		_r(-w / 2.0 - 8, y, 10, 4, WOOD_L)
		_r(w / 2.0, y, 10, 4, WOOD_L)
	if locked:   # заколочено крест-накрест
		for i in 22:
			var y := -120.0 + i * 4.0
			_r(snappedf(-26.0 + i * 2.4, 2.0), y, 10, 6, OL)
			_r(snappedf(26.0 - i * 2.4, 2.0) - 8, y, 10, 6, OL)
		for i in 22:
			var y := -120.0 + i * 4.0
			_r(snappedf(-24.0 + i * 2.4, 2.0), y, 6, 4, Color("c49a5e"))
			_r(snappedf(24.0 - i * 2.4, 2.0) - 6, y, 6, 4, Color("b0864a"))
		_box(-14, -60, 28, 16, Color("f4ecd8"))
		_r(-10, -54, 20, 2, OL)
		_r(-8, -50, 16, 2, OL)


# ---------------------------------------------------------------- жилая зона

func _bed() -> void:
	_box(-30, -72, 60, 14, Color("7a4a2a"))               # изголовье
	_box(-30, -62, 60, 62, Color("8a5a34"))               # рама
	_box(-26, -58, 52, 54, Color("f4ecd8"))               # матрас
	_box(-24, -56, 22, 12, Color("ffffff"))               # подушки
	_box(2, -56, 22, 12, Color("ffffff"))
	_r(-24, -46, 22, 2, Color("d8d4c8"))
	_r(2, -46, 22, 2, Color("d8d4c8"))
	_r(-26, -38, 52, 34, Color("5e8fa8"))                 # одеяло
	_r(-26, -38, 52, 4, Color("7fb0c8"))
	_r(-26, -26, 52, 4, Color("4d7a92"))
	_r(-26, -14, 52, 4, Color("4d7a92"))
	_r(-8, -22, 4, 4, Color("e8c15a"))                    # заплатка-звёздочка


func _wardrobe() -> void:
	_box(-14, -78, 28, 78, Color("8a5a34"))
	_r(-14, -80, 28, 4, Color("b98552"))
	_r(-1, -72, 2, 66, OL)
	_r(-10, -72, 8, 28, Color("6f4727"))
	_r(2, -72, 8, 28, Color("6f4727"))
	_r(-10, -40, 8, 30, Color("6f4727"))
	_r(2, -40, 8, 30, Color("6f4727"))
	_r(-6, -46, 2, 4, Color("e8c15a"))
	_r(4, -46, 2, 4, Color("e8c15a"))


func _sofa() -> void:
	_box(-30, -46, 60, 22, Color("c9573a"))               # спинка
	_box(-30, -32, 10, 32, Color("b0452c"))               # подлокотники
	_box(20, -32, 10, 32, Color("b0452c"))
	_box(-20, -28, 20, 24, Color("e0684a"))               # подушки сиденья
	_box(0, -28, 20, 24, Color("e0684a"))
	_r(-18, -26, 16, 2, Color("f0907a"))
	_r(2, -26, 16, 2, Color("f0907a"))


func _bookshelf() -> void:
	_box(-30, -72, 60, 72, Color("6b4527"))
	for y in [-52.0, -32.0, -12.0]:
		_r(-28, y, 56, 2, Color("3f2815"))
	var cols := [Color("c9573a"), Color("e8c15a"), Color("5c8fa8"), Color("6ba86b"), Color("a86bb0"), Color("f4ecd8")]
	for row in 4:
		var x := -26.0
		var i := 0
		while x < 24.0:
			var w := 4.0 + float((seed_id + i + row) % 3) * 2.0
			var h := 14.0 + float((seed_id + i * 2 + row) % 3) * 2.0
			var y := -66.0 + row * 20.0 + (16.0 - h) + 2.0
			_r(x, y + 2, w, h, cols[(i + row + seed_id) % cols.size()])
			x += w + 2.0
			i += 1


func _lamp() -> void:
	_r(-8, -4, 16, 4, OL)
	_r(-6, -4, 12, 2, Color("5a4a40"))
	_r(-1, -58, 2, 54, Color("5a4a40"))
	_box(-10, -76, 20, 18, Color("f0d9a0"))
	_r(-8, -74, 16, 4, Color("fff4c8"))


func _stairs_down() -> void:
	# лестница вниз: проём в полу, ступени уходят вглубь, перила
	_box(-28, -62, 56, 62, Color("1d1522"))
	for i in 5:
		var y := -58.0 + i * 11.0
		var c := Color("c28a50").darkened(0.15 + 0.14 * i)
		_r(-24, y, 48, 6, c)
		_r(-24, y + 6, 48, 4, c.darkened(0.35))
	_r(-30, -76, 4, 18, WOOD_L)                           # стойки и перила по краям
	_r(26, -76, 4, 18, WOOD_L)
	_box(-30, -80, 60, 4, WOOD_L)
	_r(-30, -28, 4, 28, WOOD_D)
	_r(26, -28, 4, 28, WOOD_D)
