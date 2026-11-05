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
	return kind_id != "catbed" and not (kind_id.begins_with("sheet:") and CafeRoom.is_flat(kind_id.trim_prefix("sheet:")))


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
		"boxes": _boxes()
		"catbed": _catbed()
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


# ---------------------------------------------------------------- вид «три четверти»
# Вся мебель рисуется так же, как мебель кафе: видна верхняя грань (светлее) и передняя (темнее), обводка 1 пиксель арта, свет сверху-слева.
# Начало координат — низ по центру занятых клеток; y вверх отрицательный.

## Брусок: передняя грань высотой front_h и верхняя высотой top_h. w — ширина, ox — сдвиг по x от центра. Возвращает левый край.
func _cube(w: float, front_h: float, top_h: float, front: Color, top: Color, ox := 0.0) -> float:
	var x := -w / 2.0 + ox
	var h := front_h + top_h
	draw_rect(Rect2(x - 2, -h - 2, w + 4, h + 4), OL)
	draw_rect(Rect2(x, -front_h, w, front_h), front)
	draw_rect(Rect2(x, -h, w, top_h), top)
	draw_rect(Rect2(x, -h, w, 2), top.lightened(0.2))                 # блик дальнего края
	draw_rect(Rect2(x, -front_h, w, 2), front.lightened(0.14))        # передний край крышки
	draw_rect(Rect2(x, -front_h, 2, front_h), front.lightened(0.1))   # свет слева
	draw_rect(Rect2(x + w - 2, -front_h, 2, front_h), front.darkened(0.16))
	draw_rect(Rect2(x, -2, w, 2), front.darkened(0.2))                # низ в тени
	return x


## Ступенька-диск: эллипс из строк по 2 px (для вёдер, ламп, мешков сверху).
func _disc(cx: float, y: float, hw: float, rows: int, fill: Color, rim := true) -> void:
	for i in rows:
		var t := float(i) / float(maxi(rows - 1, 1))
		var half := hw * (0.55 + 0.45 * sin(t * PI))
		half = roundf(half / 2.0) * 2.0
		_r(cx - half - 2, y + i * 2, half * 2 + 4, 2, OL)
	_r(cx - hw * 0.55 - 2, y - 2, hw * 1.1 + 4, 2, OL)
	_r(cx - hw * 0.55 - 2, y + rows * 2, hw * 1.1 + 4, 2, OL)
	for i in rows:
		var t := float(i) / float(maxi(rows - 1, 1))
		var half := roundf(hw * (0.55 + 0.45 * sin(t * PI)) / 2.0) * 2.0
		_r(cx - half, y + i * 2, half * 2, 2, fill)
	if rim:
		_r(cx - hw * 0.5, y, hw, 2, fill.lightened(0.25))


# ---------------------------------------------------------------- коморка

func _crate() -> void:
	var x := _cube(28, 16, 10, WOOD, WOOD_L)
	for dx in [8.0, 18.0]:   # доски верхней крышки и передней стенки
		_r(x + dx, -26, 2, 10, WOOD_D)
		_r(x + dx, -16, 2, 14, WOOD_D)
	_r(x + 2, -10, 24, 2, WOOD_D)
	_r(x + 4, -14, 2, 2, Color("d8d8e0"))                 # гвозди
	_r(x + 22, -14, 2, 2, Color("d8d8e0"))


func _sack() -> void:
	# мешок: округлое тело, сверху завязанная горловина и видна верхняя часть
	_blob(-30, [4, 6, 8, 10, 12, 12, 12, 12, 12, 12, 12, 10, 8], Color("d9b98a"))
	_r(-6, -32, 12, 2, Color("e8d0a0"))                  # свет на плече
	_r(-4, -36, 8, 4, Color("7a5a3a"))                   # завязка
	_r(-6, -38, 4, 2, Color("7a5a3a"))
	_r(-4, -18, 8, 8, Color("6b4a2f"))                   # метка: кофейное зерно
	_r(-2, -16, 2, 4, Color("d9b98a"))


func _shelf() -> void:
	# стеллаж с припасами: сверху видна доска, спереди три полки
	var x := _cube(60, 44, 10, Color("4d3b30"), Color("8a6a46"))
	for y in [-34.0, -22.0, -10.0]:
		_r(x + 2, y, 56, 2, Color("8a6a46"))
	var cols := [Color("c9573a"), Color("e8c15a"), Color("5c8fa8"), Color("8dff7a"), Color("f4ecd8")]
	for i in 5:   # верхняя полка: коробки
		var h := 8.0 + float((seed_id + i) % 3) * 2.0
		_r(x + 4 + i * 11, -34 - h, 9, h, cols[(i + seed_id) % 5])
		_r(x + 4 + i * 11, -34 - h, 9, 2, Color(1, 1, 1, 0.3))
	for i in 4:   # средняя: банки
		_r(x + 6 + i * 14, -22 - 10, 10, 10, cols[(i * 2 + seed_id) % 5])
		_r(x + 6 + i * 14, -22 - 12, 10, 2, Color("c9d0da"))
	for i in 3:   # нижняя: мешочки
		_r(x + 8 + i * 18, -10 - 8, 14, 8, Color("d9b98a"))
		_r(x + 8 + i * 18, -10 - 8, 14, 2, Color("7a5a3a"))


func _fridge() -> void:
	var x := _cube(28, 46, 10, Color("e9eef0"), Color("f7fafb"))
	_r(x + 24, -46, 2, 46, Color("c3ccd2"))
	_r(x + 2, -26, 24, 2, Color("98a4ac"))                # шов двух дверей
	_r(x + 20, -42, 2, 10, Color("5c6270"))               # ручки
	_r(x + 20, -22, 2, 10, Color("5c6270"))
	_r(x + 6, -40, 4, 4, Color("c9573a"))                 # магнит
	_r(x + 6, -18, 6, 6, Color("e8c15a"))                 # записка
	_r(x + 6, -54, 12, 2, Color("d4dde0"))                # решётка на крыше


func _sink() -> void:
	# тумба с раковиной: сверху видна мойка и кран, за ней плитка стены
	_r(-30, -50, 60, 14, Color("cfe0e6"))                 # плитка у стены, сразу за столешницей
	for dx in range(-30, 30, 10):
		_r(dx, -50, 2, 14, Color("a9c4cc"))
	_r(-30, -44, 60, 2, Color("a9c4cc"))
	_r(-32, -52, 64, 2, OL)
	var x := _cube(60, 26, 12, Color("7d8594"), Color("c9d0da"))
	_r(x + 28, -26, 2, 24, Color("5c6270"))               # дверцы тумбы
	_r(x + 20, -18, 2, 4, Color("c9d0da"))
	_r(x + 36, -18, 2, 4, Color("c9d0da"))
	_r(x + 8, -36, 26, 8, OL)                             # мойка сверху
	_r(x + 10, -34, 22, 4, Color("4a5a70"))
	_r(x + 10, -34, 22, 2, Color("6a7a92"))
	_r(x + 42, -44, 4, 12, Color("c9d0da"))               # кран
	_r(x + 36, -44, 10, 4, Color("c9d0da"))
	_r(x + 36, -40, 2, 4, Color("6fa8d6"))                # капля


func _mop() -> void:
	# ведро сверху видно овалом с водой, швабра торчит наклонно
	_cube(20, 12, 0, Color("c4c9d4"), Color("c4c9d4"))
	_disc(0, -26, 10, 7, Color("6fa8d6"))
	_r(-8, -14, 16, 2, Color("98a4ac"))
	for i in 11:   # швабра: наклонная палка в 2 пикселя арта, шаг по сетке
		_r(2.0 + i * 2.0, -24.0 - i * 4.0, 4, 4, WOOD_L if i % 2 == 0 else WOOD)
	_r(-6, -26, 10, 4, Color("e8e2d0"))
	_r(-8, -22, 4, 4, Color("e8e2d0"))


func _boxes() -> void:
	# две картонные коробки, сверху виден скотч
	var card := Color("c9a070")
	var x := _cube(28, 12, 8, card, card.lightened(0.18))
	_r(x + 12, -20, 4, 8, Color("e8d8b0"))
	_r(x + 12, -12, 4, 10, Color("e8d8b0"))
	_r(x + 18, -8, 8, 4, Color("f4ecd8"))                 # наклейка
	_r(x + 20, -7, 4, 2, OL)
	draw_set_transform(Vector2(-2, -20))   # вторая коробка стоит сверху
	var x2 := _cube(22, 10, 8, card.darkened(0.08), card.lightened(0.1))
	_r(x2 + 8, -18, 4, 8, Color("e8d8b0"))
	_r(x2 + 8, -10, 4, 10, Color("e8d8b0"))
	draw_set_transform(Vector2.ZERO)


func _catbed() -> void:
	# лежанка: плетёная корзина с подушкой, плоская (кот может пройти поверх)
	_blob(-14, [8, 12, 14, 14, 14, 12, 8], Color("b0864a"), false)
	_blob(-12, [6, 10, 12, 12, 10, 6], Color("d97a8c"), false)
	_r(-6, -8, 2, 2, Color("f0b4be"))
	_r(-10, -2, 20, 2, Color("8a6a3a"))


## Лестница наверх у задней стены (вид три четверти): ступени поднимаются от нас вглубь, у каждой светлая проступь и тёмный подступенок;
## сверху тёмный проём. Занимает 2×2 клетки; вход — снизу.
func _stairs_up() -> void:
	var n := 6
	var sh := 10.0   # высота ступени на экране (проступь 4 + подступенок 6)
	var w0 := 56.0
	_box(-w0 / 2.0 + 4, -sh * n - 14, w0 - 8, 14, Color("1d1522"))   # проём вверху
	_r(-w0 / 2.0 + 4, -sh * n - 14, w0 - 8, 2, Color("2f2438"))
	for i in n:   # ступени снизу вверх: каждая чуть уже
		var inset := float(i) * 2.0
		var y := -sh * i
		var xl := -w0 / 2.0 + inset
		var wi := w0 - inset * 2.0
		_r(xl - 2, y - sh - 2, wi + 4, sh + 2, OL)
		_r(xl, y - 6, wi, 6, Color("6f4727"))                    # подступенок (передняя грань)
		_r(xl, y - 6, wi, 2, Color("8a5a34"))
		_r(xl, y - sh, wi, 4, WOOD_L)                             # проступь
		_r(xl, y - sh, wi, 2, WOOD_L.lightened(0.15))
	for sx in [-w0 / 2.0 - 4, w0 / 2.0]:   # боковины (тетива) и перила
		_r(sx, -sh * n - 2, 4, sh * n + 2, OL)
		_r(sx + (2 if sx < 0 else 0), -sh * n, 2, sh * n, WOOD_D)
	_r(-w0 / 2.0 - 4, -sh * n - 22, 4, 22, OL)
	_r(w0 / 2.0, -sh * n - 22, 4, 22, OL)
	if locked:   # заколочено досками крест-накрест и табличка
		for k in 8:
			var yy := -12.0 - k * 6.0
			_r(snappedf(-26.0 + k * 6.0, 2.0), yy, 8, 6, OL)
			_r(snappedf(18.0 - k * 6.0, 2.0), yy, 8, 6, OL)
			_r(snappedf(-24.0 + k * 6.0, 2.0), yy + 1, 4, 4, Color("c49a5e"))
			_r(snappedf(20.0 - k * 6.0, 2.0), yy + 1, 4, 4, Color("b0864a"))
		_box(-18, -42, 36, 16, Color("f4ecd8"))
		_r(-12, -38, 24, 2, OL)
		_r(-8, -34, 16, 2, OL)


# ---------------------------------------------------------------- жилая зона

func _bed() -> void:
	# кровать сверху: изголовье у стены, матрас с подушками и одеялом, передняя планка рамы
	_box(-30, -72, 60, 10, Color("7a4a2a"))                      # изголовье
	_r(-30, -72, 60, 2, Color("9a6a3c"))
	_box(-30, -62, 60, 62, Color("8a5a34"))                      # рама
	_box(-26, -58, 52, 48, Color("f4ecd8"))                      # матрас сверху
	_box(-24, -56, 22, 12, Color("ffffff"))                      # подушки
	_box(2, -56, 22, 12, Color("ffffff"))
	_r(-22, -46, 18, 2, Color("d8d4c8"))
	_r(4, -46, 18, 2, Color("d8d4c8"))
	_r(-26, -40, 52, 28, Color("5e8fa8"))                        # одеяло
	_r(-26, -40, 52, 4, Color("7fb0c8"))                         # отворот
	_r(-26, -28, 52, 2, Color("4d7a92"))
	_r(-26, -18, 52, 2, Color("4d7a92"))
	_r(-8, -26, 4, 4, Color("e8c15a"))                           # заплатка-звёздочка
	_r(-26, -10, 52, 6, Color("a56d3c"))                         # передняя планка рамы
	_r(-26, -10, 52, 2, Color("c08850"))


func _wardrobe() -> void:
	var x := _cube(28, 56, 10, Color("8a5a34"), Color("b98552"))
	_r(x + 13, -54, 2, 52, OL)                                   # щель между дверцами
	for dx in [2.0, 16.0]:
		_r(x + dx, -50, 10, 20, Color("6f4727"))                 # филёнки
		_r(x + dx, -26, 10, 20, Color("6f4727"))
		_r(x + dx, -50, 10, 2, Color("9a6a3c"))
		_r(x + dx, -26, 10, 2, Color("9a6a3c"))
	_r(x + 10, -34, 2, 4, Color("e8c15a"))                       # ручки
	_r(x + 16, -34, 2, 4, Color("e8c15a"))
	_r(x + 2, -62, 24, 2, Color("d09a60"))                       # карниз


func _sofa() -> void:
	# диван: у спинки видна верхняя грань, сиденье из двух подушек, подлокотники — брусочки по краям
	_box(-30, -44, 60, 12, Color("b0452c"))                      # спинка сверху
	_r(-30, -44, 60, 2, Color("d0654a"))
	_box(-30, -34, 60, 14, Color("c9573a"))                      # спинка спереди
	_box(-30, -30, 10, 30, Color("b0452c"))                      # подлокотники
	_box(20, -30, 10, 30, Color("b0452c"))
	_r(-30, -30, 10, 2, Color("d0654a"))
	_r(20, -30, 10, 2, Color("d0654a"))
	_box(-20, -22, 20, 18, Color("e0684a"))                      # подушки сиденья: верх
	_box(0, -22, 20, 18, Color("e0684a"))
	_r(-18, -20, 16, 2, Color("f0907a"))
	_r(2, -20, 16, 2, Color("f0907a"))
	_r(-20, -8, 20, 6, Color("c9573a"))                          # передний край сиденья
	_r(0, -8, 20, 6, Color("c9573a"))


func _bookshelf() -> void:
	var x := _cube(60, 58, 10, Color("6b4527"), Color("9a6a3c"))
	for y in [-44.0, -28.0, -12.0]:
		_r(x + 2, y, 56, 2, Color("3f2815"))
	var cols := [Color("c9573a"), Color("e8c15a"), Color("5c8fa8"), Color("6ba86b"), Color("a86bb0"), Color("f4ecd8")]
	var bottoms := [-44.0, -28.0, -12.0, -2.0]   # книги стоят на досках
	for row in 4:
		var bx := x + 4.0
		var i := 0
		while bx < x + 54.0:
			var w := 4.0 + float((seed_id + i + row) % 3) * 2.0
			var h := (10.0 + float((seed_id + i * 2 + row) % 3) * 2.0) if row < 3 else 6.0
			_r(bx, float(bottoms[row]) - h, w, h, cols[(i + row + seed_id) % cols.size()])
			bx += w + 2.0
			i += 1


func _lamp() -> void:
	# торшер: круглое основание, стойка, абажур — трапеция с видимым светлым верхом
	_disc(0, -8, 10, 4, Color("5a4a40"), false)
	_r(-2, -46, 4, 40, OL)
	_r(0, -46, 2, 40, Color("5a4a40"))
	for i in 7:   # абажур: расширяется книзу
		var hw := 8.0 + float(i) * 1.0
		hw = roundf(hw / 2.0) * 2.0
		_r(-hw - 2, -76 + i * 4.0, hw * 2 + 4, 4, OL)
	_r(-8, -80, 16, 2, OL)
	for i in 7:
		var hw := roundf((8.0 + float(i)) / 2.0) * 2.0
		_r(-hw, -76 + i * 4.0, hw * 2, 4, Color("f0d9a0") if i > 0 else Color("fff4c8"))
	_r(-6, -76, 12, 4, Color("fff4c8"))
	_r(-hw_of(6), -52, 4, 4, Color("d8c080"))


func hw_of(i: int) -> float:
	return roundf((8.0 + float(i)) / 2.0) * 2.0


## Лестница вниз: проём в полу (вид три четверти). Спереди — светлая кромка пола, внутри уходят вглубь ступени, всё темнее;
## по заднему краю — балюстрада. Занимает 3×2 клетки.
func _stairs_down() -> void:
	_box(-46, -62, 92, 54, Color("1d1522"))                      # проём
	var steps := 6
	for i in steps:
		var y := -8.0 - float(i) * 8.0                           # ступени уходят вверх по экрану (вглубь)
		var c := Color("c28a50").darkened(0.1 + 0.11 * i)
		_r(-44, y - 8, 88, 8, c.darkened(0.35))                  # подступенок
		_r(-44, y - 8, 88, 4, c)                                 # проступь
		_r(-44, y - 8, 88, 2, c.lightened(0.15))
	_r(-46, -8, 92, 8, Color("b98552"))                          # кромка пола спереди
	_r(-46, -8, 92, 2, Color("dcae74"))
	_r(-46, -2, 92, 2, WOOD_D)
	for bx in [-46.0, -16.0, 14.0, 44.0]:                        # балюстрада по заднему краю
		_r(bx, -86, 4, 24, WOOD_L)
		_r(bx, -86, 4, 2, OL)
	_box(-46, -90, 92, 4, WOOD_L)
