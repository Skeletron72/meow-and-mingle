class_name InteriorSpace
extends Node2D
## Служебные помещения того же здания: коморка за кухней и прилавком (BACK) и жилая зона на втором этаже (UP).
## Стоят в том же месте мира, что и зал кафе, и показываются вместо него, когда кот переходит через дверь или лестницу
## (город переключает пространство — см. city.gd). Сетка та же: 10×7 клеток пола и 3 клетки стены, клетка 32 px, пиксель арта 2 px.
##
## Предметы — SpaceProp: рисуются кодом (мебель из листа кафе берётся оттуда) и стоят в общем слое мира, поэтому сортируются
## по глубине вместе с котами и режутся тем же кругом рентгена. Двери и лестницы — «порталы»: тап по ним ведёт кота к клетке
## рядом, и там он переходит в другое помещение.

enum Kind { BACK, UP }

const T := 32
const COLS := 10
const ROWS := 7
const ORIGIN := Vector2(0, 96)
const ROOM_SIZE := Vector2(320, 320)
const FEET_DY := 10.0

const BACK_DOOR_CELLS: Array[Vector2i] = [Vector2i(4, 6), Vector2i(5, 6)]       # коморка → кафе
const STAIRS_STAND: Array[Vector2i] = [Vector2i(7, 2), Vector2i(8, 2), Vector2i(9, 2)]   # перед лестницей
const BED_STAND: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2)]             # у кровати

var kind := Kind.BACK
var external_actors: Node2D
var props: Array[SpaceProp] = []
var portals: Array[Dictionary] = []     # {"id", "hit": Rect2 (комната), "stand": Array[Vector2i], "to": "cafe"/"back"/"up"}
var stairs_locked := true               # коморка: лестница заколочена, пока не куплен «Второй этаж»
var _wall_layer: Node2D
var _glows: Array[Sprite2D] = []
var _windows: Array[CafeRoom.WindowGlow] = []
var _stairs: SpaceProp


func setup(k: Kind, actors: Node2D) -> void:
	kind = k
	external_actors = actors
	_wall_layer = Node2D.new()
	add_child(_wall_layer)
	if kind == Kind.BACK:
		_build_back()
	else:
		_build_up()
	set_active(false)


# ---------------------------------------------------------------- состав помещений

func _add(def: Dictionary) -> SpaceProp:
	var p := SpaceProp.new()
	p.kind_id = String(def["k"])
	p.cells = Vector2i(int(def.get("w", 1)), int(def.get("h", 1)))
	p.cell = Vector2i(int(def["c"]), int(def["r"]))
	p.seed_id = int(def["c"]) * 7 + int(def["r"]) * 3
	p.local_pos = ORIGIN + Vector2(p.cell) * T + Vector2(p.cells.x * T / 2.0, p.cells.y * T)
	p.position = p.local_pos + position   # общий слой мира стоит в нуле, пространство — со смещением
	p.set_meta("interior", true)
	external_actors.add_child(p)
	props.append(p)
	return p


func _build_back() -> void:
	for d in [
		{"k": "shelf", "c": 0, "r": 0, "w": 2}, {"k": "shelf", "c": 2, "r": 0, "w": 2},
		{"k": "fridge", "c": 4, "r": 0}, {"k": "sink", "c": 5, "r": 0, "w": 2},
		{"k": "sack", "c": 0, "r": 2}, {"k": "sack", "c": 0, "r": 3}, {"k": "crate", "c": 1, "r": 2}, {"k": "boxes", "c": 0, "r": 4},
		{"k": "sheet:table_big", "c": 3, "r": 3, "w": 2, "h": 2}, {"k": "sheet:stool", "c": 2, "r": 4}, {"k": "sheet:stool", "c": 5, "r": 4},
		{"k": "catbed", "c": 1, "r": 5}, {"k": "mop", "c": 9, "r": 4},
	]:
		_add(d)
	_stairs = _add({"k": "stairs_up", "c": 7, "r": 0, "w": 3, "h": 2})
	portals = [
		{"id": "stairs_up", "hit": Rect2(ORIGIN.x + 7 * T, 0, 3 * T, ORIGIN.y + 2 * T), "stand": STAIRS_STAND, "to": "up"},
		{"id": "door_cafe", "hit": Rect2(ORIGIN.x + 4 * T, ORIGIN.y + 6 * T - 8, 2 * T, T + 8), "stand": BACK_DOOR_CELLS, "to": "cafe"},
	]
	for x in [96.0, 224.0]:   # тёплые лужи света от лампочек на шнурах
		var g := Fx.pixel_light(Vector2(x, 150), Vector2(240, 190), Color(1.0, 0.8, 0.45, 0.3))
		add_child(g)
		_glows.append(g)


func _build_up() -> void:
	for d in [
		{"k": "bookshelf", "c": 0, "r": 0, "w": 2}, {"k": "lamp", "c": 2, "r": 0},
		{"k": "bed", "c": 3, "r": 0, "w": 2, "h": 2}, {"k": "wardrobe", "c": 5, "r": 0},
		{"k": "sofa", "c": 1, "r": 3, "w": 2}, {"k": "sheet:table_small", "c": 1, "r": 5}, {"k": "sheet:plant", "c": 9, "r": 3},
	]:
		_add(d)
	_stairs = _add({"k": "stairs_down", "c": 7, "r": 0, "w": 3, "h": 2})
	var bed := props[2]
	portals = [
		{"id": "stairs_down", "hit": Rect2(ORIGIN.x + 7 * T, ORIGIN.y - 28, 3 * T, 2 * T + 28), "stand": STAIRS_STAND, "to": "back"},
		{"id": "bed", "hit": Rect2(bed.local_pos.x - 32, bed.local_pos.y - 76, 64, 80), "stand": BED_STAND, "to": ""},
	]
	for wc in [2, 6]:   # окна в стене
		var def := CafeRoom.item_def("window")
		var src: Array = def["rect"]
		var sp := Sprite2D.new()
		sp.texture = CafeRoom.FURN_TEX
		sp.region_enabled = true
		sp.region_rect = Rect2(float(src[0]), float(src[1]), float(src[2]), float(src[3]))
		sp.centered = false
		sp.scale = Vector2(2, 2)
		sp.position = Vector2(wc * T + (2 * T - float(src[2]) * 2.0) / 2.0, T + (T - float(src[3]) * 2.0) / 2.0 + 8.0)
		_wall_layer.add_child(sp)
		var gl := CafeRoom.WindowGlow.new()
		gl.position = sp.position
		_wall_layer.add_child(gl)
		_windows.append(gl)
	var lamp := Fx.pixel_light(props[1].local_pos + Vector2(0, -60), Vector2(190, 160), Color(1.0, 0.85, 0.5, 0.0))
	add_child(lamp)
	_glows.append(lamp)


# ---------------------------------------------------------------- состояние

func set_active(on: bool) -> void:
	visible = on
	for p in props:
		p.visible = on


func set_stairs_locked(locked: bool) -> void:
	stairs_locked = locked
	if _stairs != null:
		_stairs.locked = locked
		_stairs.queue_redraw()


## Освещение: днём в окна падает свет, вечером разгораются лампы. day и night — 0..1.
func set_lighting(day: float, night: float) -> void:
	for i in _glows.size():
		var g := _glows[i]
		if kind == Kind.UP:
			g.modulate.a = 0.10 + 0.40 * night   # торшер
		else:
			g.modulate.a = 0.34 + 0.16 * night
	for w in _windows:
		w.apply(day, night)


## Клетки пола, по которым можно ходить (1 — можно): пол минус предметы, плюс дверь вниз в коморке.
func walk_mask() -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(COLS * ROWS)
	for r in ROWS - 1:
		for c in COLS:
			m[r * COLS + c] = 1
	if kind == Kind.BACK:
		for c in BACK_DOOR_CELLS:
			m[c.y * COLS + c.x] = 1
	for p in props:
		if p.is_solid():
			for y in range(p.cell.y, p.cell.y + p.cells.y):
				for x in range(p.cell.x, p.cell.x + p.cells.x):
					m[y * COLS + x] = 0
	return m


## Портал, по которому попали тапом (комнатные координаты), или пустой словарь.
func portal_at(p: Vector2) -> Dictionary:
	for d in portals:
		if (d["hit"] as Rect2).has_point(p):
			return d
	return {}


static func cell_pos_feet(cell: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * T + Vector2(0, FEET_DY)


# ---------------------------------------------------------------- пол и стены

func _draw() -> void:
	if kind == Kind.BACK:
		_draw_back_room()
	else:
		_draw_living()


## Коморка: тёплая штукатурка, зелёная панель по низу стены, медная труба, плитка пола с затёртыми швами, лампочки на шнурах.
func _draw_back_room() -> void:
	var plaster := Color("b79d7c")
	draw_rect(Rect2(0, 0, ROOM_SIZE.x, ORIGIN.y), plaster)
	for c in range(0, COLS, 2):
		draw_rect(Rect2(c * T, 0, T, 50), plaster.lightened(0.05))
	var panel := Color("4f6b5a")
	draw_rect(Rect2(0, 50, ROOM_SIZE.x, 34), panel)          # зелёная панель
	draw_rect(Rect2(0, 50, ROOM_SIZE.x, 4), Color("86a38e"))
	draw_rect(Rect2(0, 54, ROOM_SIZE.x, 2), Color("3a5244"))
	for c in COLS:
		draw_rect(Rect2(c * T + 30, 56, 2, 28), Color("3a5244"))
	draw_rect(Rect2(0, 84, ROOM_SIZE.x, 12), Color("3d3a36"))   # плинтус
	draw_rect(Rect2(0, 84, ROOM_SIZE.x, 2), Color("5a5650"))
	# медная труба вдоль стены под потолком
	draw_rect(Rect2(0, 10, 320, 8), Color("2b2230"))
	draw_rect(Rect2(0, 12, 320, 4), Color("c8824e"))
	draw_rect(Rect2(0, 12, 320, 2), Color("e8a870"))
	for x in range(40, 320, 80):
		draw_rect(Rect2(x, 8, 6, 12), Color("5c5048"))
	# часы над холодильником, доска объявлений над полками, сковороды над раковиной
	draw_rect(Rect2(138, 24, 24, 24), Color("2b2230"))
	draw_rect(Rect2(140, 26, 20, 20), Color("f4ecd8"))
	draw_rect(Rect2(148, 30, 2, 8), Color("2b2230"))
	draw_rect(Rect2(148, 36, 6, 2), Color("2b2230"))
	draw_rect(Rect2(20, 28, 86, 28), Color("2b2230"))
	draw_rect(Rect2(22, 30, 82, 24), Color("a87a4a"))
	for i in 5:
		var nc: Color = [Color("f4ecd8"), Color("e8c15a"), Color("8fd6ff"), Color("f4ecd8"), Color("ff9db0")][i]
		draw_rect(Rect2(28 + i * 16, 34 + (i % 2) * 8, 10, 12), nc)
		draw_rect(Rect2(32 + i * 16, 34 + (i % 2) * 8, 2, 2), Color("c9573a"))
	draw_rect(Rect2(172, 22, 44, 4), Color("2b2230"))
	for i in 3:
		var px := 178 + i * 14
		draw_rect(Rect2(px, 26, 2, 8), Color("5c5048"))
		draw_rect(Rect2(px - 4, 34, 10, 8), Color("2b2230"))
		draw_rect(Rect2(px - 2, 36, 6, 4), Color("9aa2b0"))
	# пол: тёплая плитка, швы потёрты, пара пятен
	for r in ROWS:
		for c in COLS:
			var a := Color("7b6b5c") if (r + c) % 2 == 0 else Color("827160")
			var o := Vector2(c * T, ORIGIN.y + r * T)
			draw_rect(Rect2(o, Vector2(T, T)), a)
			draw_rect(Rect2(o.x, o.y + T - 2, T, 2), a.darkened(0.28))
			draw_rect(Rect2(o.x + T - 2, o.y, 2, T), a.darkened(0.28))
			draw_rect(Rect2(o.x, o.y, T, 2), a.lightened(0.07))
			if (c * 7 + r * 13) % 5 == 0:
				draw_rect(Rect2(o.x + 8 + (c % 3) * 4, o.y + 10, 6, 4), a.darkened(0.12))
	# дорожка от двери в кафе
	draw_rect(Rect2(4 * T + 4, ORIGIN.y + 3 * T, 2 * T - 8, 3 * T), Color("2b2230"))
	draw_rect(Rect2(4 * T + 6, ORIGIN.y + 3 * T + 2, 2 * T - 12, 3 * T - 2), Color("8a3a3a"))
	draw_rect(Rect2(4 * T + 10, ORIGIN.y + 3 * T + 2, 2 * T - 20, 3 * T - 2), Color("a64a4a"))
	# передний ряд — тёмная стена здания; дверь в кафе
	for c in COLS:
		if BACK_DOOR_CELLS.has(Vector2i(c, 6)):
			draw_rect(Rect2(c * T, ORIGIN.y + 6 * T, T, T), Color("7a5238"))
			continue
		draw_rect(Rect2(c * T, ORIGIN.y + 6 * T, T, T), Color("3d3a36"))
		draw_rect(Rect2(c * T, ORIGIN.y + 6 * T, T, 4), Color("5a5650"))
	var door := Rect2(4 * T, ORIGIN.y + 6 * T, 2 * T, T)
	draw_rect(door.grow(2), Color("2b2230"), false, 2.0)
	draw_rect(Rect2(door.position.x + 6, door.position.y + 8, door.size.x - 12, 16), Color("5b3d27"))
	draw_rect(Rect2(door.position.x + 22, door.position.y + 2, 20, 4), Color("f4ecd8"))   # табличка «в кафе»
	# лампочки на шнурах
	for x in [96, 224]:
		draw_rect(Rect2(x - 1, 0, 2, 26), Color("2b2230"))
		draw_rect(Rect2(x - 5, 24, 10, 4), Color("2b2230"))
		draw_rect(Rect2(x - 4, 28, 8, 8), Color("2b2230"))
		draw_rect(Rect2(x - 2, 30, 4, 4), Color("fff1b0"))
	_draw_shading()


func _draw_living() -> void:
	var wall := Color("a9b8b2") if kind == Kind.BACK else Color("dcb9a4")
	var stripe := wall.lightened(0.07)
	var base := Color("6d7c78") if kind == Kind.BACK else Color("a0705a")
	draw_rect(Rect2(0, 0, ROOM_SIZE.x, ORIGIN.y), wall)
	for c in range(0, COLS, 2):
		draw_rect(Rect2(c * T, 0, T, ORIGIN.y - T / 2.0), stripe)
	draw_rect(Rect2(0, ORIGIN.y - T / 2.0, ROOM_SIZE.x, T / 2.0), base)
	draw_rect(Rect2(0, ORIGIN.y - 4, ROOM_SIZE.x, 4), base.darkened(0.35))
	if kind == Kind.BACK:   # труба и кафельная полоса: служебное помещение
		draw_rect(Rect2(0, 24, 320, 6), Color("7d8594"))
		draw_rect(Rect2(0, 24, 320, 2), Color("a1a9b8"))
		for x in range(48, 320, 96):
			draw_rect(Rect2(x, 20, 6, 14), Color("5c6270"))
	for r in ROWS:
		for c in COLS:
			var a: Color
			if kind == Kind.BACK:
				a = Color("6f7a78") if (r + c) % 2 == 0 else Color("79857f")
			else:
				a = Color("9a6b43") if r % 2 == 0 else Color("a5744a")
			draw_rect(Rect2(c * T, ORIGIN.y + r * T, T, T), a)
			if kind == Kind.UP:   # стыки досок
				draw_rect(Rect2(c * T, ORIGIN.y + r * T, T, 2), a.darkened(0.18))
				draw_rect(Rect2(((c + r * 3) % 4) * 8 + c * T, ORIGIN.y + r * T, 2, T), a.darkened(0.12))
	# передний ряд — стена здания (в коморке в ней дверь в кафе)
	for c in COLS:
		var edge := Color("5b3d27") if kind == Kind.UP else Color("4a5654")
		if kind == Kind.BACK and BACK_DOOR_CELLS.has(Vector2i(c, 6)):
			draw_rect(Rect2(c * T, ORIGIN.y + 6 * T, T, T), Color("7a5238"))
			continue
		draw_rect(Rect2(c * T, ORIGIN.y + 6 * T, T, T), edge)
		draw_rect(Rect2(c * T, ORIGIN.y + 6 * T, T, 4), edge.lightened(0.2))
	if kind == Kind.BACK:   # косяк и коврик двери в кафе
		var door := Rect2(4 * T, ORIGIN.y + 6 * T, 2 * T, T)
		draw_rect(door.grow(2), Color("2b2230"), false, 2.0)
		draw_rect(Rect2(door.position.x + 6, door.position.y + 8, door.size.x - 12, 16), Color("5b3d27"))
	else:   # ковёр у дивана
		draw_rect(Rect2(0, ORIGIN.y + 3 * T, 4 * T, 3 * T), Color("2b2230"))
		draw_rect(Rect2(4, ORIGIN.y + 3 * T + 4, 4 * T - 8, 3 * T - 8), Color("b2556a"))
		draw_rect(Rect2(12, ORIGIN.y + 3 * T + 12, 4 * T - 24, 3 * T - 24), Color("d97a8c"))
		draw_rect(Rect2(12, ORIGIN.y + 3 * T + 12, 4 * T - 24, 3 * T - 24), Color("f0b4be"), false, 2.0)
		# рамка с фото мамы на стене
		draw_rect(Rect2(138, 30, 24, 30), Color("2b2230"))
		draw_rect(Rect2(142, 34, 16, 22), Color("f4ecd8"))
		draw_rect(Rect2(146, 44, 8, 8), Color("c9a070"))
		draw_rect(Rect2(146, 40, 2, 4), Color("c9a070"))
		draw_rect(Rect2(152, 40, 2, 4), Color("c9a070"))
	_draw_shading()


func _draw_shading() -> void:
	# объём: затенение под стеной, под потолком и у боковых стен — дизеринг
	draw_texture_rect(PixelArt.dither_gradient(160, 12, false, false), Rect2(0, ORIGIN.y, 320, 24), false, Color(0, 0, 0, 0.40))
	draw_texture_rect(PixelArt.dither_gradient(160, 8, false, false), Rect2(0, 0, 320, 16), false, Color(0, 0, 0, 0.32))
	draw_texture_rect(PixelArt.dither_gradient(10, 160, true, false), Rect2(0, 0, 20, 320), false, Color(0, 0, 0, 0.28))
	draw_texture_rect(PixelArt.dither_gradient(10, 160, true, true), Rect2(300, 0, 20, 320), false, Color(0, 0, 0, 0.28))
	draw_rect(Rect2(Vector2.ZERO, ROOM_SIZE), Color("5b3d27"), false, 4.0)
