class_name CafeRoom
extends Node2D
## Интерьер кафе: его видно в городе (рентген, когда мы внутри) и в режиме «украшение».
##
## Вся геометрия — на сетке 16×16 пикселей арта. Спрайты рисуются в масштабе 2, поэтому клетка T = 32 px.
## Все координаты — в системе самой комнаты (узел можно ставить куда угодно). Пол — COLS×ROWS клеток от ORIGIN,
## стена над ним — WALL_ROWS клеток по высоте.
## Мебель занимает целое число клеток (`tiles` в data/furniture.json) и хранится как клетка (c, r)
## левого верхнего угла: {"id", "c", "r", "flip"}. Спрайт ставится по низу и по центру своих клеток.
## Коты ходят по центрам клеток (путь — AStarGrid2D).

const FURN_TEX: Texture2D = preload("res://assets/cafe/neko-cafe-furnitures.png")
const S := 2.0                       # масштаб арта: 1 пиксель арта = 2 логических
const T := 32                        # клетка 16×16 арта
const COLS := 10
const ROWS := 7
const WALL_ROWS := 3                 # стена: клетки (c, wr), низ последней строки = верх пола
const ORIGIN := Vector2(0, 96)       # левый верх пола в координатах комнаты (над ним 3 клетки стены)
const ROOM_SIZE := Vector2(320, 320) # 10×10 клеток: ровно по габариту фасада кафе (Building4 при масштабе 2)
const FEET_DY := 10.0                # лапки кота ниже центра клетки

# Прилавок — обязательная, но передвигаемая мебель (id "counter" или его раскраска, убрать нельзя). На нём стоит кофемашина.
# Ряд ЗА прилавком (counter_behind) — место бариста: туда заходит только игрок, там начинается смена; гости туда не ходят.
# Ряд ПЕРЕД прилавком (counter_front) — место гостей. Оба ряда держим свободными от мебели. Кухня — у задней стены, за проходом бариста.
const COUNTER_ID := "counter"
const MACHINE_SRC := Rect2(131, 67, 11, 13)
const MACHINE_DX := 21.0   # кофемашина в третьей клетке прилавка (при отражении — в первой): сдвиг от центра узла
const MACHINE_DX_U := 5.0  # на большой П-образной стойке — на правой части основания
const MACHINE_DY := -48.0
const DEFAULT_COUNTER := Vector2i(0, 2)
## Служебка: маленькая комната в углу зала, отделённая стенами (левая стена — колонка 6, передняя — ряд 3, в передней стене проём STAFF_DOOR).
## Внутри — лестница наверх и пара коробок. Пока не куплено «Коморка», это закрытый чулан с заколоченной дверью.
const STAFF_CELLS := Rect2i(6, 0, 4, 4)            # весь блок вместе со стенами: мебель сюда не ставят
const STAFF_INNER := Rect2i(7, 0, 3, 3)            # клетки внутри
const STAFF_DOOR := Vector2i(8, 3)                 # проём в передней стене
const STAIRS_CELLS := Rect2i(8, 0, 2, 2)           # лестница (занимает клетки)
const STAIRS_STAND: Array[Vector2i] = [Vector2i(8, 2), Vector2i(9, 2)]   # перед лестницей
const STAFF_PROPS := [
	{"k": "boxes", "c": 7, "r": 0}, {"k": "sack", "c": 7, "r": 1}, {"k": "stairs_up", "c": 8, "r": 0, "w": 2, "h": 2},
]
const SPAWN_CELLS := Rect2i(4, 5, 2, 2)            # вход; тоже держим свободным
const SPAWN_CELL := Vector2i(4, 6)
## Передний ряд — витрина здания: непроходимый и без мебели, кроме проёма входа. Двери нет: из проёма сразу тротуар.
const FRONT_ROW := 6
const ENTRANCE_CELLS := Rect2i(4, 6, 2, 1)
const WALL_FIRST_ROW := 0

const WALL_COLOR := Color("cdb892")
const WALL_STRIPE := Color("d8c6a3")
const BASEBOARD := Color("a98763")
const FLOOR_A := Color("7c5a3a")
const FLOOR_B := Color("86633f")
const FLOOR_EDGE := Color("5b3d27")

var layout: Array[Dictionary] = []   # общий с GameState.layout: правки видны сразу

var actors: Node2D                   # свой слой (режим украшения): мебель сортируется по y
## Если задан (город), громоздкая мебель живёт в этом общем слое мира и сортируется по y вместе с котами и машинами.
var external_actors: Node2D
var _wall_layer: Node2D
var _flat_layer: Node2D
var _nodes: Array[Node2D] = []       # узел мебели для каждого элемента layout (тот же индекс)
var _astar: AStarGrid2D
var _lamp_glows: Array[Sprite2D] = []   # тёплые пятна света от ламп (пиксельные, additive)
var _windows: Array[WindowGlow] = []     # стёкла окон: цвет по времени суток
var _day := 1.0
var _night := 0.0
var _staff_props: Array[SpaceProp] = []   # лестница и коробки служебки
var stairs_locked := true


func _init() -> void:
	_wall_layer = Node2D.new()
	_flat_layer = Node2D.new()
	_flat_layer.y_sort_enabled = true
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(_wall_layer)
	add_child(_flat_layer)
	add_child(actors)
	_build_lights()


# ---------------------------------------------------------------- данные о мебели и клетках

static func item_def(id: String) -> Dictionary:
	return Data.furniture.get(id, {})


static func is_wall(id: String) -> bool:
	return String(item_def(id).get("slot", "floor")) == "wall"


static func is_flat(id: String) -> bool:
	return bool(item_def(id).get("flat", false))


## Занимает ли предмет клетки (кот не пройдёт). Настенное и плоское (коврик, миска) — нет.
static func is_solid(id: String) -> bool:
	return not is_wall(id) and not is_flat(id)


static func tiles(id: String) -> Vector2i:
	var t: Array = item_def(id)["tiles"]
	return Vector2i(int(t[0]), int(t[1]))


## Клетки, которые занимает предмет с левым верхним углом (c, r).
static func cells(id: String, c: int, r: int) -> Rect2i:
	return Rect2i(Vector2i(c, r), tiles(id))


static func sprite_size(id: String) -> Vector2:
	var r: Array = item_def(id)["rect"]
	return Vector2(float(r[2]), float(r[3])) * S


## Левый верх клетки: пол (c, r) или стена (c, wr).
static func cell_pos(c: int, r: int, wall := false) -> Vector2:
	return Vector2(ORIGIN.x + c * T, (r * T) if wall else (ORIGIN.y + r * T))


## Точка «на полу» (низ по центру клеток) — по ней предмет сортируется по глубине.
static func foot_pos(id: String, c: int, r: int) -> Vector2:
	var t := tiles(id)
	var top := cell_pos(c, r, is_wall(id))
	return top + Vector2(t.x * T / 2.0, t.y * T)


## Прямоугольник спрайта в мире: по низу и по центру своих клеток (плоские — по центру).
## Сдвиг округляется вниз до целого пикселя арта (S логических), чтобы пиксели спрайта не оказывались на полпикселя.
static func sprite_rect(id: String, c: int, r: int) -> Rect2:
	var t := tiles(id)
	var sz := sprite_size(id)
	var top := cell_pos(c, r, is_wall(id))
	var x := top.x + floorf((t.x * T - sz.x) / 2.0 / S) * S
	var y := top.y + (t.y * T - sz.y)
	if is_flat(id):
		y = top.y + floorf((t.y * T - sz.y) / 2.0 / S) * S
	return Rect2(x, y, sz.x, sz.y)


static func _cell(item: Dictionary) -> Vector2i:
	return Vector2i(int(item["c"]), int(item["r"]))


## Клетка пола под точкой (в пределах поля).
static func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x - ORIGIN.x) / T), 0, COLS - 1), clampi(floori((p.y - ORIGIN.y) / T), 0, ROWS - 1))


## Клетка стены под точкой.
static func wall_cell_at(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x - ORIGIN.x) / T), 0, COLS - 1), clampi(floori(p.y / T), 0, WALL_ROWS - 1))


## Где стоят лапки кота, стоящего в клетке.
static func feet_at(cell: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * T + Vector2(0, FEET_DY)


static func cell_of_feet(feet: Vector2) -> Vector2i:
	return cell_at(feet - Vector2(0, FEET_DY))


# ---------------------------------------------------------------- построение

func set_layout(items: Array[Dictionary]) -> void:
	layout = items
	rebuild()


func rebuild() -> void:
	for n in _nodes:
		n.get_parent().remove_child(n)
		n.queue_free()
	_nodes.clear()
	for i in layout.size():
		_nodes.append(_spawn_item(layout[i]))
	_rebuild_staff()
	rebuild_nav()


## Добавляет предмет в уже построенную комнату, не пересоздавая остальные (для интро: окно и доска появляются по ходу).
func add_item(item: Dictionary) -> Node2D:
	layout.append(item)
	var n := _spawn_item(item)
	_nodes.append(n)
	rebuild_nav()
	return n


func node_for(index: int) -> Node2D:
	return _nodes[index]


## Двигает узел предмета на клетку (c, r), не трогая layout (для перетаскивания).
func preview_move(index: int, c: int, r: int) -> void:
	var id := String(layout[index]["id"])
	_nodes[index].position = foot_pos(id, c, r) + (position if _nodes[index].has_meta("interior") else Vector2.ZERO)


func _spawn_item(item: Dictionary) -> Node2D:
	var id := String(item["id"])
	var def := item_def(id)
	var c := int(item["c"])
	var r := int(item["r"])
	var n := Node2D.new()
	n.position = foot_pos(id, c, r)
	var src: Array = def["rect"]
	if is_solid(id):   # контактная тень под мебелью
		var t := tiles(id)
		var blob := PixelArt.sprite(PixelArt.blob(t.x * 8 + 2, 4), Vector2(0, -2))
		blob.modulate = Color(1, 1, 1, 0.55)
		n.add_child(blob)
	var sp := Sprite2D.new()
	sp.texture = FURN_TEX
	sp.region_enabled = true
	sp.region_rect = Rect2(float(src[0]), float(src[1]), float(src[2]), float(src[3]))
	sp.centered = false
	sp.scale = Vector2(S, S)
	sp.position = sprite_rect(id, c, r).position - n.position
	sp.flip_h = bool(item.get("flip", false))
	if def.has("tint"):   # раскраска стиля (лофт, японский, зимний): тот же спрайт другого оттенка
		sp.modulate = Color(String(def["tint"]))
	if is_wall(id):   # настенное отбрасывает мягкую тень на стену
		var drop := Sprite2D.new()
		drop.texture = FURN_TEX
		drop.region_enabled = true
		drop.region_rect = sp.region_rect
		drop.centered = false
		drop.scale = Vector2(S, S)
		drop.position = sp.position + Vector2(4, 4)
		drop.flip_h = sp.flip_h
		drop.modulate = Color(0, 0, 0, 0.30)
		n.add_child(drop)
	n.add_child(sp)
	if is_counter(id):   # кофемашина стоит на прилавке и двигается вместе с ним
		var machine := Sprite2D.new()
		machine.texture = FURN_TEX
		machine.region_enabled = true
		machine.region_rect = MACHINE_SRC
		machine.centered = false
		machine.scale = Vector2(S, S)
		machine.flip_h = sp.flip_h
		machine.position = Vector2(-_machine_dx(id) - MACHINE_SRC.size.x * S if sp.flip_h else _machine_dx(id), MACHINE_DY)
		n.add_child(machine)
	if String(def.get("base", id)) == "window":
		var w := WindowGlow.new()
		w.position = sp.position
		n.add_child(w)
		_windows.append(w)
		w.apply(_day, _night)
	var layer: Node2D = _wall_layer if is_wall(id) else (_flat_layer if is_flat(id) else actors)
	if external_actors != null and is_solid(id):
		layer = external_actors
		n.position += position   # слой мира стоит в нуле, комната — со смещением
		n.set_meta("interior", true)
	layer.add_child(n)
	return n


func _build_lights() -> void:
	for x in [96.0, 224.0]:   # лампы под потолком: тёплые пятна на стене и полу
		var g := Fx.pixel_light(Vector2(x, 140), Vector2(230, 180), Color(1.0, 0.78, 0.42, 0.22))
		add_child(g)
		_lamp_glows.append(g)


## Освещение зала: окна светятся цветом неба (день — голубое, закат — оранжевое, ночь — тёмное со звёздами), вечером разгораются лампы.
func set_lighting(day: float, night: float) -> void:
	_day = day
	_night = night
	for g in _lamp_glows:
		g.modulate.a = 0.12 + 0.34 * night
	var alive: Array[WindowGlow] = []   # после перестройки зала (ремонт) часть окон уже освобождена
	for w in _windows:
		if is_instance_valid(w):
			alive.append(w)
	_windows = alive
	for w in _windows:
		w.apply(day, night)


## Служебка открыта (куплена «Коморка»)? От этого зависят рисунок блока, проходимость и видимость вещей внутри.
func staff_open() -> bool:
	return GameState.has_upgrade("back_room")


## Перерисовать служебку после покупки «Коморки» или «Второго этажа».
func refresh_staff() -> void:
	stairs_locked = not GameState.has_upgrade("upstairs")
	for p in _staff_props:
		p.visible = staff_open()
		if p.kind_id == "stairs_up":
			p.locked = stairs_locked
		p.queue_redraw()
	queue_redraw()


## Что под точкой (координаты комнаты): закрытый чулан, лестница (если служебка открыта) или пусто.
func staff_portal_at(p: Vector2) -> Dictionary:
	var block := Rect2(ORIGIN + Vector2(STAFF_CELLS.position) * T, Vector2(STAFF_CELLS.size) * T)
	if not staff_open():
		return {"id": "staff_locked", "stand": [STAFF_DOOR + Vector2i(0, 1)], "to": ""} if block.has_point(p) else {}
	var stairs := Rect2(ORIGIN + Vector2(STAIRS_CELLS.position) * T + Vector2(0, -96), Vector2(STAIRS_CELLS.size) * T + Vector2(0, 96))
	if stairs.has_point(p):
		return {"id": "stairs_up", "stand": STAIRS_STAND, "to": "up"}
	return {}


func _rebuild_staff() -> void:
	for p in _staff_props:
		p.queue_free()
	_staff_props.clear()
	var layer: Node2D = external_actors if external_actors != null else actors
	for d in STAFF_PROPS:
		var pr := SpaceProp.new()
		pr.kind_id = String(d["k"])
		pr.cells = Vector2i(int(d.get("w", 1)), int(d.get("h", 1)))
		pr.cell = Vector2i(int(d["c"]), int(d["r"]))
		pr.seed_id = pr.cell.x * 7 + pr.cell.y * 3
		pr.local_pos = ORIGIN + Vector2(pr.cell) * T + Vector2(pr.cells.x * T / 2.0, pr.cells.y * T)
		pr.position = pr.local_pos
		if external_actors != null:
			pr.position += position
			pr.set_meta("interior", true)
		layer.add_child(pr)
		_staff_props.append(pr)
	refresh_staff()


func _has_item(id: String) -> bool:
	for it in layout:
		if String(it["id"]) == id:
			return true
	return false


## Прилавок ли это (сам «counter» или его раскраска стиля).
static func is_counter(id: String) -> bool:
	return String(item_def(id).get("base", id)) == COUNTER_ID


static func _machine_dx(id: String) -> float:
	return MACHINE_DX_U if String(item_def(id).get("base", id)) == "ucounter" else MACHINE_DX


## Номер прилавка в раскладке (-1 — нет; такого не бывает: GameState.ensure_counter возвращает его на место).
func counter_index() -> int:
	for i in layout.size():
		if is_counter(String(layout[i]["id"])):
			return i
	return -1


## Клетки, которые занимает прилавок.
func counter_cells() -> Rect2i:
	var i := counter_index()
	if i < 0:
		return Rect2i(DEFAULT_COUNTER, Vector2i(3, 1))
	return cells(String(layout[i]["id"]), int(layout[i]["c"]), int(layout[i]["r"]))


## Ряд клеток перед прилавком: место гостей. Мебель сюда не ставят.
func counter_front() -> Rect2i:
	var a := counter_cells()
	return Rect2i(a.position.x, a.end.y, a.size.x, 1)


## Ряд клеток за прилавком: место бариста. Сюда заходит только игрок (смена начинается здесь), гости — нет. Мебель сюда не ставят.
func counter_behind() -> Rect2i:
	var a := counter_cells()
	return Rect2i(a.position.x, a.position.y - 1, a.size.x, 1)


## Только столешница прилавка (без кофемашины) и сама кофемашина — для чехла и пыли в интро.
func counter_body_rect() -> Rect2:
	var i := counter_index()
	if i < 0:
		return Rect2()
	return sprite_rect(String(layout[i]["id"]), int(layout[i]["c"]), int(layout[i]["r"]))


func machine_rect() -> Rect2:
	var i := counter_index()
	if i < 0:
		return Rect2()
	var id := String(layout[i]["id"])
	var foot := foot_pos(id, int(layout[i]["c"]), int(layout[i]["r"]))
	var flip := bool(layout[i].get("flip", false))
	return Rect2(foot.x + (-_machine_dx(id) - MACHINE_SRC.size.x * S if flip else _machine_dx(id)), foot.y + MACHINE_DY, MACHINE_SRC.size.x * S, MACHINE_SRC.size.y * S)


## Прямоугольник прилавка вместе с кофемашиной (в координатах комнаты) — для тапа и выбора.
func counter_rect() -> Rect2:
	var i := counter_index()
	if i < 0:
		return Rect2()
	return _item_rect(String(layout[i]["id"]), int(layout[i]["c"]), int(layout[i]["r"]), bool(layout[i].get("flip", false)))


## Прямоугольник предмета для выбора: у прилавка — вместе с кофемашиной.
func _item_rect(id: String, c: int, r: int, flip := false) -> Rect2:
	var rect := sprite_rect(id, c, r)
	if is_counter(id):
		var foot := foot_pos(id, c, r)
		var mx := foot.x + (-_machine_dx(id) - MACHINE_SRC.size.x * S if flip else _machine_dx(id))
		rect = rect.merge(Rect2(mx, foot.y + MACHINE_DY, MACHINE_SRC.size.x * S, MACHINE_SRC.size.y * S))
	return rect


func _draw() -> void:
	# цвета зала — по выбранным вариантам ремонта (стены, пол, плинтус); без выбора — как были
	var pal := GameState.style_colors()
	var wall_c: Color = pal.get("wall", WALL_COLOR)
	var stripe_c: Color = pal.get("stripe", WALL_STRIPE)
	var base_c: Color = pal.get("base", BASEBOARD)
	var floor_a: Color = pal.get("a", FLOOR_A)
	var floor_b: Color = pal.get("b", FLOOR_B)
	var edge_c: Color = pal.get("edge", FLOOR_EDGE)
	# стена: полосы по две клетки, совпадают с сеткой
	draw_rect(Rect2(0, 0, ROOM_SIZE.x, ORIGIN.y), wall_c)
	for c in range(0, COLS, 2):
		draw_rect(Rect2(ORIGIN.x + c * T, 0, T, ORIGIN.y - T / 2.0), stripe_c)
	draw_rect(Rect2(0, ORIGIN.y - T / 2.0, ROOM_SIZE.x, T / 2.0), base_c)
	draw_rect(Rect2(0, ORIGIN.y - 4, ROOM_SIZE.x, 4), base_c.darkened(0.35))
	# пол: шахматка по клеткам
	for r in ROWS:
		for c in COLS:
			draw_rect(Rect2(ORIGIN.x + c * T, ORIGIN.y + r * T, T, T), floor_a if (r + c) % 2 == 0 else floor_b)
	# передний ряд — подоконник витрины, кроме проёма входа
	for c in COLS:
		if not ENTRANCE_CELLS.has_point(Vector2i(c, FRONT_ROW)):
			draw_rect(Rect2(ORIGIN.x + c * T, ORIGIN.y + FRONT_ROW * T, T, T), edge_c)
			draw_rect(Rect2(ORIGIN.x + c * T, ORIGIN.y + FRONT_ROW * T, T, 4), edge_c.lightened(0.2))
	# коврик в проёме входа — ровно по его клеткам
	var mat := Rect2(ORIGIN.x + ENTRANCE_CELLS.position.x * T, ORIGIN.y + ENTRANCE_CELLS.position.y * T, ENTRANCE_CELLS.size.x * T, T)
	draw_rect(mat.grow(-4), Color("5b3d27"))
	draw_rect(mat.grow(-8), Color("7a5238"))
	_draw_staff()
	# объём: затенение под стеной, под потолком и у боковых стен — дизеринг, а не плавный градиент
	draw_texture_rect(PixelArt.dither_gradient(160, 12, false, false), Rect2(0, ORIGIN.y, 320, 24), false, Color(0, 0, 0, 0.40))
	draw_texture_rect(PixelArt.dither_gradient(160, 8, false, false), Rect2(0, 0, 320, 16), false, Color(0, 0, 0, 0.32))
	draw_texture_rect(PixelArt.dither_gradient(10, 160, true, false), Rect2(0, 0, 20, 320), false, Color(0, 0, 0, 0.28))
	draw_texture_rect(PixelArt.dither_gradient(10, 160, true, true), Rect2(300, 0, 20, 320), false, Color(0, 0, 0, 0.28))
	# рамка разреза здания
	draw_rect(Rect2(Vector2.ZERO, ROOM_SIZE), edge_c, false, 4.0)


## Служебка в углу зала. Закрыта — чулан с досчатой крышей и заколоченной дверью; открыта — разрез: пол внутри, стены, проём.
func _draw_staff() -> void:
	var ol := Color("2b2230")
	var o := ORIGIN + Vector2(STAFF_CELLS.position) * T
	var size := Vector2(STAFF_CELLS.size) * T
	var door := Rect2(ORIGIN + Vector2(STAFF_DOOR) * T, Vector2(T, T))
	if not staff_open():
		draw_rect(Rect2(o - Vector2(2, 2), size + Vector2(4, 4)), ol)
		for y in range(0, int(size.y) - 12, 8):   # доски крыши
			draw_rect(Rect2(o.x, o.y + y, size.x, 8), Color("7a5c42") if (y / 8) % 2 == 0 else Color("6a4e38"))
			draw_rect(Rect2(o.x, o.y + y, size.x, 2), Color("8e6e50"))
		draw_rect(Rect2(o.x, o.y + size.y - 12, size.x, 12), Color("4a3626"))   # передняя стенка
		draw_rect(Rect2(o.x, o.y + size.y - 12, size.x, 2), Color("5e4630"))
		draw_rect(Rect2(door.position.x + 2, o.y + size.y - 28, T - 4, 28), Color("2b2230"))   # дверь внизу, заколочена
		draw_rect(Rect2(door.position.x + 4, o.y + size.y - 26, T - 8, 26), Color("9a6a3c"))
		for i in 12:
			draw_rect(Rect2(door.position.x + 4 + i * 2, o.y + size.y - 26 + i * 2, 6, 4), ol)
			draw_rect(Rect2(door.position.x + T - 12 - i * 2, o.y + size.y - 26 + i * 2, 6, 4), ol)
		for i in 12:
			draw_rect(Rect2(door.position.x + 5 + i * 2, o.y + size.y - 25 + i * 2, 4, 2), Color("c49a5e"))
			draw_rect(Rect2(door.position.x + T - 11 - i * 2, o.y + size.y - 25 + i * 2, 4, 2), Color("b0864a"))
		draw_rect(Rect2(o.x + 40, o.y + 40, 48, 22), ol)   # табличка на крыше
		draw_rect(Rect2(o.x + 42, o.y + 42, 44, 18), Color("f4ecd8"))
		draw_rect(Rect2(o.x + 48, o.y + 48, 32, 2), ol)
		draw_rect(Rect2(o.x + 52, o.y + 53, 24, 2), ol)
		return
	# пол внутри
	var inner_o := ORIGIN + Vector2(STAFF_INNER.position) * T
	for r in STAFF_INNER.size.y:
		for c in STAFF_INNER.size.x:
			var a := Color("7b6b5c") if (r + c) % 2 == 0 else Color("827160")
			var p := inner_o + Vector2(c, r) * T
			draw_rect(Rect2(p, Vector2(T, T)), a)
			draw_rect(Rect2(p.x, p.y + T - 2, T, 2), a.darkened(0.28))
			draw_rect(Rect2(p.x + T - 2, p.y, 2, T), a.darkened(0.28))
	draw_rect(door, Color("7a5238"))   # пол в проёме
	draw_rect(Rect2(door.position.x + 2, door.position.y + 8, T - 4, 16), Color("5b3d27"))   # коврик
	# стены — невысокие перегородки (разрез дома): левая тонкая полоска от задней стены, передняя с проёмом.
	# Штукатурка в тон стены зала, светлая кромка сверху, плинтус снизу, тёмная обводка.
	var plaster := Color("d4c3a4")
	var cap := Color("efe3cc")
	var base := Color("a98763")
	var base_y := o.y + size.y        # низ передней стены = низ ряда 3
	var lx := o.x + T - 10.0          # левая перегородка: правый край колонки 6
	# левая: верхняя кромка идёт от плинтуса задней стены (y 72) вниз до торца
	draw_rect(Rect2(lx - 2, ORIGIN.y - 26, 16, base_y - ORIGIN.y + 28), ol)
	draw_rect(Rect2(lx, ORIGIN.y - 24, 12, base_y - ORIGIN.y), cap)
	draw_rect(Rect2(lx, base_y - 24, 12, 24), plaster)          # торец перегородки
	draw_rect(Rect2(lx, base_y - 6, 12, 6), base)
	draw_rect(Rect2(lx + 8, ORIGIN.y - 24, 4, base_y - ORIGIN.y - 24), plaster.darkened(0.1))   # тень на дальней кромке
	# передняя: два куска по обе стороны проёма
	var segs: Array[Rect2] = [
		Rect2(lx, base_y - 24, door.position.x - lx, 24),
		Rect2(door.end.x, base_y - 24, o.x + size.x - door.end.x, 24),
	]
	for seg in segs:
		draw_rect(Rect2(seg.position.x - 2, seg.position.y - 8, seg.size.x + 4, seg.size.y + 10), ol)
	for seg in segs:
		draw_rect(Rect2(seg.position.x, seg.position.y - 6, seg.size.x, 6), cap)       # кромка (верх стены)
		draw_rect(seg, plaster)
		draw_rect(Rect2(seg.position.x, seg.end.y - 6, seg.size.x, 6), base)            # плинтус
		draw_rect(Rect2(seg.position.x, seg.end.y - 8, seg.size.x, 2), base.darkened(0.3))
		for x in range(int(seg.position.x) + 14, int(seg.end.x) - 2, 32):                # вертикальные полосы обоев
			draw_rect(Rect2(x, seg.position.y, 2, 16), plaster.darkened(0.06))
	for x in [door.position.x - 4, door.end.x - 2]:   # косяки проёма
		draw_rect(Rect2(x, base_y - 32, 6, 32), ol)
		draw_rect(Rect2(x + 1, base_y - 31, 4, 4), cap)


# ---------------------------------------------------------------- проверка размещения

## Пустая строка — ставить можно, иначе причина отказа (для всплывающей подписи).
## `ignore` — индекс предмета, который сейчас двигаем (его самого не учитываем).
func check_place(id: String, c: int, r: int, ignore := -1) -> String:
	if item_def(id).is_empty():
		return tr("Неизвестный предмет")
	var area := cells(id, c, r)
	if is_wall(id):
		if area.position.x < 0 or area.end.x > COLS or area.position.y < WALL_FIRST_ROW or area.end.y > WALL_ROWS:
			return tr("Это вешается на стену")
		for i in layout.size():
			var other := String(layout[i]["id"])
			if i != ignore and is_wall(other) and area.intersects(cells(other, int(layout[i]["c"]), int(layout[i]["r"]))):
				return tr("Тут занято")
		return ""
	if area.position.x < 0 or area.end.x > COLS or area.position.y < 0 or area.end.y > FRONT_ROW:
		return tr("Сюда нельзя")
	if area.intersects(STAFF_CELLS):
		return tr("Тут служебка")
	var solid := is_solid(id)
	if solid and area.intersects(SPAWN_CELLS):
		return tr("Не загораживайте проход")
	if solid and not is_counter(id):   # за прилавком (бариста) и перед ним (гости) — проходы
		var ci := counter_index()
		if ci >= 0 and ci != ignore and (area.intersects(counter_front()) or area.intersects(counter_behind())):
			return tr("Не загораживайте проход")
	if is_counter(id):   # за прилавком — место бариста, перед ним — гостей: оба ряда внутри зала и свободны
		var front := Rect2i(area.position.x, area.end.y, area.size.x, 1)
		var behind := Rect2i(area.position.x, area.position.y - 1, area.size.x, 1)
		if front.end.y > FRONT_ROW or front.intersects(STAFF_CELLS) or front.intersects(SPAWN_CELLS):
			return tr("Перед прилавком нужен проход")
		if behind.position.y < 0 or behind.intersects(STAFF_CELLS):
			return tr("За прилавком нужно место для бариста")
		for i in layout.size():
			var o := String(layout[i]["id"])
			if i == ignore or not is_solid(o):
				continue
			var oa := cells(o, int(layout[i]["c"]), int(layout[i]["r"]))
			if front.intersects(oa):
				return tr("Перед прилавком нужен проход")
			if behind.intersects(oa):
				return tr("За прилавком нужно место для бариста")
	for i in layout.size():
		var other := String(layout[i]["id"])
		if i == ignore or is_wall(other):
			continue
		var same_kind := (solid and is_solid(other)) or (is_flat(id) and is_flat(other))
		if same_kind and area.intersects(cells(other, int(layout[i]["c"]), int(layout[i]["r"]))):
			return tr("Тут занято")
	if solid:
		var blocks := _solid_cells(ignore)
		blocks.append(area)
		if not _reachable(_make_grid(blocks), area if is_counter(id) else Rect2i()):
			return tr("Не загораживайте проход")
	return ""


## Место для прилавка: ближе к левой стене, на второй клетке от неё; Vector2i(-1, -1) — места нет.
func find_counter_spot(id := COUNTER_ID, ignore := -1) -> Vector2i:
	for r in [2, 3, 1, 4]:
		for c in [0, 1, 2, 3, 4, 5, 6]:
			if check_place(id, c, r, ignore) == "":
				return Vector2i(c, r)
	return Vector2i(-1, -1)


## Кухня и витрины — к задней стене, за прилавок и рядом с ним (не в зал и не к выходу).
const KITCHEN := ["cabinet", "case", "oven", "stove", "machine"]
const BACK_WALL := ["cabinet", "oven", "stove"]   # эти стоят только у задней стены (ряд 0)


static func base_id(id: String) -> String:
	return String(item_def(id).get("base", id))


static func is_kitchen(id: String) -> bool:
	return base_id(id) in KITCHEN


## Подбирает место для нового предмета по его типу: кухня — вдоль задней стены, большая стойка — вдоль витрины, столы — в зал,
## пуфы — к столам, растения — в углы, настенное — на средний ряд стены подальше от других картин. ignore — индекс предмета, который переставляем.
## Vector2i(-1, -1) — места нет.
func find_free_spot(id: String, ignore := -1) -> Vector2i:
	for cell in _preferred_cells(id, ignore):
		if check_place(id, cell.x, cell.y, ignore) == "":
			return cell
	var best := Vector2i(-1, -1)
	var best_d := INF
	var rows := WALL_ROWS if is_wall(id) else ROWS
	var center := Vector2(COLS / 2.0, rows / 2.0)
	for r in rows:
		for c in COLS:
			var d := (Vector2(c, r) + Vector2(tiles(id)) / 2.0).distance_to(center)
			if d < best_d and check_place(id, c, r, ignore) == "":
				best = Vector2i(c, r)
				best_d = d
	return best


func _preferred_cells(id: String, ignore: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var base := base_id(id)
	if is_wall(id):   # средний ряд стены, затем верхний; подальше от уже висящих картин и окон
		var cand: Array[Vector2i] = []
		for r in [1, 0]:
			for c in COLS:
				cand.append(Vector2i(c, r))
		var others: Array[Vector2] = []
		for i in layout.size():
			if i != ignore and is_wall(String(layout[i]["id"])):
				others.append(Vector2(int(layout[i]["c"]), int(layout[i]["r"])))
		cand.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := _min_dist(Vector2(a), others)
			var db := _min_dist(Vector2(b), others)
			return da > db if absf(da - db) > 0.01 else (a.y > b.y if a.y != b.y else a.x < b.x))
		return cand
	if base in BACK_WALL:   # шкаф, духовка, плита — вдоль задней стены, за проходом бариста
		for c in COLS:
			out.append(Vector2i(c, 0))
		return out
	if is_kitchen(id):   # витрина, кофемашина — в ряд с прилавком, справа от него, потом у задней стены
		var ca := counter_cells()
		for c in range(ca.end.x + 1, COLS):
			out.append(Vector2i(c, ca.position.y))
		for c in COLS:
			out.append(Vector2i(c, 0))
		return out
	if base == "ucounter":   # большая стойка — вдоль витрины
		for r in [5, 4]:
			for c in COLS:
				out.append(Vector2i(c, r))
		return out
	if base == "stool":   # пуф — рядом со столом
		for i in layout.size():
			var o := base_id(String(layout[i]["id"]))
			if i != ignore and o in ["table_big", "table_small"]:
				var a := cells(String(layout[i]["id"]), int(layout[i]["c"]), int(layout[i]["r"]))
				for y in range(a.position.y, a.end.y):
					out.append(Vector2i(a.end.x, y))
					out.append(Vector2i(a.position.x - 1, y))
				for x in range(a.position.x, a.end.x):
					out.append(Vector2i(x, a.end.y))
		return out
	if base == "plant":   # углы и края зала
		out.assign([Vector2i(5, 1), Vector2i(9, 4), Vector2i(0, 5), Vector2i(5, 4), Vector2i(0, 3), Vector2i(3, 0), Vector2i(9, 5), Vector2i(5, 0)])
		return out
	if base in ["table_big", "table_small"]:   # в зале: середина пола, не у самой витрины
		var cand2: Array[Vector2i] = []
		for r in [3, 2, 4]:
			for c in COLS:
				cand2.append(Vector2i(c, r))
		cand2.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_to(Vector2(2.5, 3.0)) < Vector2(b).distance_to(Vector2(2.5, 3.0)))
		return cand2
	return out


static func _min_dist(p: Vector2, others: Array[Vector2]) -> float:
	var best := 99.0
	for o in others:
		best = minf(best, p.distance_to(o))
	return best


func hit_test(p: Vector2) -> int:
	var best := -1
	var best_y := -INF
	for i in layout.size():
		var id := String(layout[i]["id"])
		if _item_rect(id, int(layout[i]["c"]), int(layout[i]["r"]), bool(layout[i].get("flip", false))).has_point(p):
			# плоские предметы под ногами, настенные «глубже» мебели
			var depth := _nodes[i].position.y - (1000.0 if is_flat(id) else 0.0) - (2000.0 if is_wall(id) else 0.0)
			if depth > best_y:
				best_y = depth
				best = i
	return best


func counter_hit(p: Vector2) -> bool:
	return counter_rect().has_point(p)


# ---------------------------------------------------------------- сетка путей

## Проходимость зала для города: пол без витрины (кроме проёма входа) минус громоздкая мебель.
func walk_mask() -> PackedByteArray:
	var g := _make_grid(_solid_cells(-1))
	_seal_pockets(g)
	var m := PackedByteArray()
	m.resize(COLS * ROWS)
	for r in ROWS:
		for c in COLS:
			m[r * COLS + c] = 0 if g.is_point_solid(Vector2i(c, r)) else 1
	if staff_open():   # внутри служебки ходить можно: пол внутри, проём в передней стене; лестница и коробки — преграда
		for y in range(STAFF_INNER.position.y, STAFF_INNER.end.y):
			for x in range(STAFF_INNER.position.x, STAFF_INNER.end.x):
				m[y * COLS + x] = 1
		m[STAFF_DOOR.y * COLS + STAFF_DOOR.x] = 1
		for p in _staff_props:
			for y in range(p.cell.y, p.cell.y + p.cells.y):
				for x in range(p.cell.x, p.cell.x + p.cells.x):
					m[y * COLS + x] = 0
	return m


## Показать/спрятать зал целиком вместе с мебелью, живущей в общем слое мира (когда кот в коморке или наверху).
func set_present(on: bool) -> void:
	visible = on
	for n in _nodes:
		n.visible = on
	for p in _staff_props:
		p.visible = on and staff_open()


func rebuild_nav() -> void:
	_astar = _make_grid(_solid_cells(-1))
	_seal_pockets(_astar)


## Клетки зала (локальные), занятые громоздкой мебелью.
func solid_cells() -> Array[Rect2i]:
	return _solid_cells(-1)


func _solid_cells(ignore: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for i in layout.size():
		var id := String(layout[i]["id"])
		if i != ignore and is_solid(id):
			out.append(cells(id, int(layout[i]["c"]), int(layout[i]["r"])))
	return out


## Закрывает клетки, до которых от входа не дойти (карман за прилавком и мебелью): там ни коту, ни гостю делать нечего.
func _seal_pockets(g: AStarGrid2D) -> void:
	var start := _free_cell(g, SPAWN_CELL)
	if start.x < 0:
		return
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if g.is_in_boundsv(n) and not g.is_point_solid(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	for y in ROWS:
		for x in COLS:
			var p := Vector2i(x, y)
			if not g.is_point_solid(p) and not seen.has(p) and not STAFF_CELLS.has_point(p):
				g.set_point_solid(p, true)


func _make_grid(blocks: Array[Rect2i]) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, COLS, ROWS)
	g.cell_size = Vector2(T, T)
	g.offset = ORIGIN + Vector2(T, T) / 2.0
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	for b in blocks:
		for y in range(b.position.y, b.end.y):
			for x in range(b.position.x, b.end.x):
				g.set_point_solid(Vector2i(x, y), true)
	for c in COLS:   # витрина
		if not ENTRANCE_CELLS.has_point(Vector2i(c, FRONT_ROW)):
			g.set_point_solid(Vector2i(c, FRONT_ROW), true)
	for y in range(STAFF_CELLS.position.y, STAFF_CELLS.end.y):   # служебка: для украшения блок целиком занят
		for x in range(STAFF_CELLS.position.x, STAFF_CELLS.end.x):
			g.set_point_solid(Vector2i(x, y), true)
	return g


## Можно ли дойти от двери до стойки в такой сетке.
func _reachable(g: AStarGrid2D, counter_area := Rect2i()) -> bool:
	var a := _free_cell(g, SPAWN_CELL)
	var ca := counter_cells() if counter_area.size == Vector2i.ZERO else counter_area
	var front := Rect2i(ca.position.x, ca.end.y, ca.size.x, 1)
	var behind := Rect2i(ca.position.x, ca.position.y - 1, ca.size.x, 1)
	var b := _free_cell(g, front.position + Vector2i(front.size.x / 2, 0))
	var bh := behind.position + Vector2i(behind.size.x / 2, 0)   # бариста должен дойти до места за прилавком
	if a.x < 0 or not g.is_in_boundsv(bh) or g.is_point_solid(bh) or g.get_id_path(a, bh).is_empty():
		return false
	if a.x < 0 or b.x < 0:
		return false
	var door_front := STAFF_DOOR + Vector2i(0, 1)   # и до двери в служебку
	if g.is_point_solid(door_front) or g.get_id_path(a, door_front).is_empty():
		return false
	return not g.get_id_path(a, b).is_empty()


## Ближайшая свободная клетка (кольцами). (-1,-1) — свободных нет.
func _free_cell(g: AStarGrid2D, c: Vector2i) -> Vector2i:
	if not g.is_point_solid(c):
		return c
	for radius in range(1, maxi(COLS, ROWS)):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n := c + Vector2i(dx, dy)
				if g.is_in_boundsv(n) and not g.is_point_solid(n) and Vector2(dx, dy).length() < best_d:
					best = n
					best_d = Vector2(dx, dy).length()
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Занята ли клетка под лапками (для движения по клавишам: проверяем и «плечи» кота).
func is_blocked(feet: Vector2) -> bool:
	for dx in [-8.0, 0.0, 8.0]:
		var p: Vector2 = feet + Vector2(dx, -FEET_DY)
		if p.x < ORIGIN.x or p.x >= ORIGIN.x + COLS * T or p.y < ORIGIN.y or p.y >= ORIGIN.y + ROWS * T:
			return true
		if _astar.is_point_solid(cell_at(p)):
			return true
	return false


## Путь для кота по центрам клеток (пусто — дойти нельзя). `to` — любая точка, берётся её клетка.
func find_path(from_feet: Vector2, to: Vector2, guest := false) -> PackedVector2Array:
	var shut: Array[Vector2i] = []
	if guest:   # гостям за прилавок нельзя
		for c in staff_only_cells():
			if _astar.is_in_boundsv(c) and not _astar.is_point_solid(c):
				_astar.set_point_solid(c, true)
				shut.append(c)
	var a := _free_cell(_astar, cell_of_feet(from_feet))
	var b := _free_cell(_astar, cell_at(to))
	var pts := PackedVector2Array() if a.x < 0 or b.x < 0 else _astar.get_point_path(a, b)
	for c in shut:
		_astar.set_point_solid(c, false)
	if pts.is_empty():
		return pts
	if pts.size() > 1:
		pts.remove_at(0)  # первая точка — центр текущей клетки
	for i in pts.size():
		pts[i] += Vector2(0, FEET_DY)
	return pts


func random_free_point() -> Vector2:
	for _i in 40:
		var c := Vector2i(randi_range(0, COLS - 1), randi_range(0, ROWS - 1))
		if not _astar.is_point_solid(c) and not SPAWN_CELLS.has_point(c) and not (c in staff_only_cells()):
			return feet_at(c)
	return feet_at(SPAWN_CELL)


func in_entrance_zone(feet: Vector2) -> bool:
	return ENTRANCE_CELLS.has_point(cell_of_feet(feet))


## Игрок встал за прилавок — можно начинать смену.
func in_counter_zone(feet: Vector2) -> bool:
	return counter_behind().has_point(cell_of_feet(feet))


## Клетки, куда гостям нельзя (место бариста за прилавком).
func staff_only_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var b := counter_behind()
	for x in range(b.position.x, b.end.x):
		out.append(Vector2i(x, b.position.y))
	return out


## Стёкла окна поверх спрайта: цвет берётся у неба (TimeOfDay), ночью — звёзды, вокруг окна пиксельное свечение.
class WindowGlow extends Node2D:
	const PANES := [Rect2(2, 3, 12, 5), Rect2(16, 3, 12, 5), Rect2(2, 10, 12, 5), Rect2(16, 10, 12, 5)]   # в пикселях спрайта окна
	const STARS := [Vector2(5, 4), Vector2(11, 6), Vector2(20, 5), Vector2(25, 7), Vector2(7, 12), Vector2(22, 13)]
	var _top := Color.WHITE
	var _bottom := Color.WHITE
	var _night := 0.0
	var _glow: Sprite2D

	func _ready() -> void:
		_glow = Fx.pixel_light(Vector2(30, 17), Vector2(150, 110), Color(1, 1, 1, 0.3))
		add_child(_glow)
		move_child(_glow, 0)

	func apply(day: float, night: float) -> void:
		_night = night
		_bottom = TimeOfDay.sky_bottom().lerp(Color("c9e8ff"), day * 0.5).lightened(0.12)
		_top = TimeOfDay.sky_top().lerp(Color("8ec7f5"), day * 0.5).lightened(0.05)
		if _glow != null:
			_glow.modulate = Color(_bottom.lightened(0.2), 0.10 + 0.25 * day + 0.12 * night)
		queue_redraw()

	func _draw() -> void:
		var s := CafeRoom.S
		for p: Rect2 in PANES:
			var r := Rect2(p.position * s, p.size * s)
			draw_rect(r, _top)
			draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.5, r.size.x, r.size.y * 0.5), _bottom)
			if _night < 0.6:   # блик стекла днём
				var g := Color(1, 1, 1, 0.55 * (1.0 - _night))
				for k in 3:
					draw_rect(Rect2(r.position.x + (r.size.x - 4 * s) + k * s, r.position.y + k * s, 2 * s, s), g)
		if _night > 0.5:
			for st: Vector2 in STARS:
				draw_rect(Rect2(st * s, Vector2(s, s)), Color(1, 1, 0.85, (_night - 0.5) * 2.0))
