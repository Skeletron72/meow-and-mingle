class_name InteriorSpace
extends Node2D
## Второй этаж того же здания — жилая зона (UP). Стоит в том же месте мира, что и зал кафе, и показывается вместо него,
## когда кот поднимается по лестнице из служебки (город переключает пространство — см. city.gd). Сетка та же: 10×7 клеток пола и 3 клетки стены, клетка 32 px, пиксель арта 2 px.
##
## Предметы — SpaceProp: рисуются кодом (мебель из листа кафе берётся оттуда) и стоят в общем слое мира, поэтому сортируются
## по глубине вместе с котами и режутся тем же кругом рентгена. Двери и лестницы — «порталы»: тап по ним ведёт кота к клетке
## рядом, и там он переходит в другое помещение.

enum Kind { UP }

const T := 32
const COLS := 10
const ROWS := 4   # у второго этажа 4 клетки пола: он занимает верх фасада (крыша и стена с окнами)
const ORIGIN := Vector2(0, 96)
const ROOM_SIZE := Vector2(320, 224)
const FEET_DY := 10.0

const STAIRS_STAND: Array[Vector2i] = [Vector2i(7, 2), Vector2i(8, 2), Vector2i(9, 2)]   # перед лестницей вниз
const BED_STAND: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2)]             # у кровати

var kind := Kind.UP
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
	p.set_meta("upper", true)   # второй этаж: режется своим кругом
	external_actors.add_child(p)
	props.append(p)
	return p


func _build_up() -> void:
	for d in [
		{"k": "bookshelf", "c": 0, "r": 0, "w": 2}, {"k": "lamp", "c": 2, "r": 0},
		{"k": "bed", "c": 3, "r": 0, "w": 2, "h": 2}, {"k": "wardrobe", "c": 5, "r": 0},
		{"k": "sofa", "c": 1, "r": 2, "w": 2}, {"k": "sheet:table_small", "c": 1, "r": 3}, {"k": "sheet:plant", "c": 9, "r": 3},
	]:
		_add(d)
	_stairs = _add({"k": "stairs_down", "c": 7, "r": 0, "w": 3, "h": 2})
	refresh_rewards()
	var bed := props[2]
	portals = [
		{"id": "stairs_down", "hit": Rect2(ORIGIN.x + 7 * T, ORIGIN.y - 28, 3 * T, 2 * T + 28), "stand": STAIRS_STAND, "to": "cafe"},
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
		g.modulate.a = 0.10 + 0.40 * night   # торшер
	for w in _windows:
		w.apply(day, night)


## Клетки пола, по которым можно ходить (1 — можно): пол минус предметы, плюс дверь вниз в коморке.
func walk_mask() -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(COLS * ROWS)
	for r in ROWS:
		for c in COLS:
			m[r * COLS + c] = 1
	for p in props:
		if p.is_solid():
			for y in range(p.cell.y, p.cell.y + p.cells.y):
				for x in range(p.cell.x, p.cell.x + p.cells.x):
					m[y * COLS + x] = 0
	return m


## Награды ремонта для жилой зоны (ковёр, цветы, столик для писем): ставятся на свои места наверху, когда открыты (`up:*` в unlocks).
const REWARDS := {"up:rug": {"k": "sheet:rug", "c": 3, "r": 3, "w": 2}, "up:plant": {"k": "sheet:plant", "c": 6, "r": 0}, "up:table": {"k": "sheet:table_small", "c": 6, "r": 2}}


func refresh_rewards() -> void:
	for key in REWARDS:
		if not GameState.has_unlock(String(key)):
			continue
		var def: Dictionary = REWARDS[key]
		var have := false
		for p in props:
			if p.kind_id == String(def["k"]) and p.cell == Vector2i(int(def["c"]), int(def["r"])):
				have = true
		if not have:
			_add(def)


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
	var wall := Color("dcb9a4")
	var stripe := wall.lightened(0.07)
	var base := Color("a0705a")
	draw_rect(Rect2(0, 0, ROOM_SIZE.x, ORIGIN.y), wall)
	for c in range(0, COLS, 2):
		draw_rect(Rect2(c * T, 0, T, ORIGIN.y - T / 2.0), stripe)
	draw_rect(Rect2(0, ORIGIN.y - T / 2.0, ROOM_SIZE.x, T / 2.0), base)
	draw_rect(Rect2(0, ORIGIN.y - 4, ROOM_SIZE.x, 4), base.darkened(0.35))
	for r in ROWS:
		for c in COLS:
			var a := Color("9a6b43") if r % 2 == 0 else Color("a5744a")
			draw_rect(Rect2(c * T, ORIGIN.y + r * T, T, T), a)
			draw_rect(Rect2(c * T, ORIGIN.y + r * T, T, 2), a.darkened(0.18))   # стыки досок
			draw_rect(Rect2(((c + r * 3) % 4) * 8 + c * T, ORIGIN.y + r * T, 2, T), a.darkened(0.12))
	# ковёр у дивана
	draw_rect(Rect2(0, ORIGIN.y + 2 * T, 4 * T, 2 * T), Color("2b2230"))
	draw_rect(Rect2(4, ORIGIN.y + 2 * T + 4, 4 * T - 8, 2 * T - 8), Color("b2556a"))
	draw_rect(Rect2(12, ORIGIN.y + 2 * T + 10, 4 * T - 24, 2 * T - 20), Color("d97a8c"))
	draw_rect(Rect2(12, ORIGIN.y + 2 * T + 10, 4 * T - 24, 2 * T - 20), Color("f0b4be"), false, 2.0)
	draw_rect(Rect2(0, ROOM_SIZE.y - 8, ROOM_SIZE.x, 8), Color("5b3d27"))   # плинтус у передней стены дома
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
	draw_texture_rect(PixelArt.dither_gradient(10, 112, true, false), Rect2(0, 0, 20, 224), false, Color(0, 0, 0, 0.28))
	draw_texture_rect(PixelArt.dither_gradient(10, 112, true, true), Rect2(300, 0, 20, 224), false, Color(0, 0, 0, 0.28))
	draw_rect(Rect2(Vector2.ZERO, ROOM_SIZE), Color("5b3d27"), false, 4.0)
