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

# Стойка кофейни — неподвижная, у стены над клетками (0..2, 0). Отсюда начинается смена.
const COUNTER_SRC := Rect2(17, 112, 46, 16)
const COUNTER_CELLS := Rect2i(0, 0, 3, 1)          # здесь стоит кот у стойки; мебель ставить нельзя
const COUNTER_SPRITE := Rect2(0, 48, 96, 48)       # прилавок + кофемашина, для тапа
const WALL_RESERVED := Rect2i(0, 1, 3, 2)          # стена над стойкой занята
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
var _beam: Sprite2D                     # луч дневного света из окна


func _init() -> void:
	_wall_layer = Node2D.new()
	_flat_layer = Node2D.new()
	_flat_layer.y_sort_enabled = true
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(_wall_layer)
	add_child(_flat_layer)
	add_child(actors)
	_build_counter()
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


## Освещение зала: днём из окна падает луч, вечером разгораются лампы. day и night — 0..1.
func set_lighting(day: float, night: float) -> void:
	for g in _lamp_glows:
		g.modulate.a = 0.12 + 0.34 * night
	if _beam == null and _has_item("window"):
		_beam = PixelArt.sprite(PixelArt.beam(28, 64, -30), Vector2(172, 64), false)
		_beam.material = Fx.additive()
		add_child(_beam)
	if _beam != null:
		_beam.modulate = Color(1.0, 0.93, 0.72, 0.30 * day)


func _has_item(id: String) -> bool:
	for it in layout:
		if String(it["id"]) == id:
			return true
	return false


func _build_counter() -> void:
	var sp := Sprite2D.new()
	sp.texture = FURN_TEX
	sp.region_enabled = true
	sp.region_rect = COUNTER_SRC
	sp.centered = false
	sp.scale = Vector2(S, S)
	sp.position = Vector2(ORIGIN.x + (3 * T - COUNTER_SRC.size.x * S) / 2.0, ORIGIN.y - COUNTER_SRC.size.y * S)
	_wall_layer.add_child(sp)
	var machine := Sprite2D.new()
	machine.texture = FURN_TEX
	machine.region_enabled = true
	machine.region_rect = Rect2(131, 67, 11, 13)
	machine.centered = false
	machine.scale = Vector2(S, S)
	machine.position = Vector2(ORIGIN.x + 2 * T + (T - 11 * S) / 2.0, ORIGIN.y - 48.0)
	_wall_layer.add_child(machine)


func _draw() -> void:
	# стена: полосы по две клетки, совпадают с сеткой
	draw_rect(Rect2(0, 0, ROOM_SIZE.x, ORIGIN.y), WALL_COLOR)
	for c in range(0, COLS, 2):
		draw_rect(Rect2(ORIGIN.x + c * T, 0, T, ORIGIN.y - T / 2.0), WALL_STRIPE)
	draw_rect(Rect2(0, ORIGIN.y - T / 2.0, ROOM_SIZE.x, T / 2.0), BASEBOARD)
	draw_rect(Rect2(0, ORIGIN.y - 4, ROOM_SIZE.x, 4), BASEBOARD.darkened(0.35))
	# пол: шахматка по клеткам
	for r in ROWS:
		for c in COLS:
			draw_rect(Rect2(ORIGIN.x + c * T, ORIGIN.y + r * T, T, T), FLOOR_A if (r + c) % 2 == 0 else FLOOR_B)
	# передний ряд — подоконник витрины, кроме проёма входа
	for c in COLS:
		if not ENTRANCE_CELLS.has_point(Vector2i(c, FRONT_ROW)):
			draw_rect(Rect2(ORIGIN.x + c * T, ORIGIN.y + FRONT_ROW * T, T, T), FLOOR_EDGE)
			draw_rect(Rect2(ORIGIN.x + c * T, ORIGIN.y + FRONT_ROW * T, T, 4), FLOOR_EDGE.lightened(0.2))
	# коврик в проёме входа — ровно по его клеткам
	var mat := Rect2(ORIGIN.x + ENTRANCE_CELLS.position.x * T, ORIGIN.y + ENTRANCE_CELLS.position.y * T, ENTRANCE_CELLS.size.x * T, T)
	draw_rect(mat.grow(-4), Color("5b3d27"))
	draw_rect(mat.grow(-8), Color("7a5238"))
	# объём: затенение под стеной, под потолком и у боковых стен — дизеринг, а не плавный градиент
	draw_texture_rect(PixelArt.dither_gradient(160, 12, false, false), Rect2(0, ORIGIN.y, 320, 24), false, Color(0, 0, 0, 0.40))
	draw_texture_rect(PixelArt.dither_gradient(160, 8, false, false), Rect2(0, 0, 320, 16), false, Color(0, 0, 0, 0.32))
	draw_texture_rect(PixelArt.dither_gradient(10, 160, true, false), Rect2(0, 0, 20, 320), false, Color(0, 0, 0, 0.28))
	draw_texture_rect(PixelArt.dither_gradient(10, 160, true, true), Rect2(300, 0, 20, 320), false, Color(0, 0, 0, 0.28))
	# рамка разреза здания
	draw_rect(Rect2(Vector2.ZERO, ROOM_SIZE), FLOOR_EDGE, false, 4.0)


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
		if area.intersects(WALL_RESERVED):
			return tr("Тут занято")
		for i in layout.size():
			var other := String(layout[i]["id"])
			if i != ignore and is_wall(other) and area.intersects(cells(other, int(layout[i]["c"]), int(layout[i]["r"]))):
				return tr("Тут занято")
		return ""
	if area.position.x < 0 or area.end.x > COLS or area.position.y < 0 or area.end.y > FRONT_ROW:
		return tr("Сюда нельзя")
	var solid := is_solid(id)
	if solid and (area.intersects(SPAWN_CELLS) or area.intersects(COUNTER_CELLS)):
		return tr("Не загораживайте проход")
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
		if not _reachable(_make_grid(blocks)):
			return tr("Не загораживайте проход")
	return ""


## Подбирает свободную клетку для нового предмета, ближе к центру зала. Vector2i(-1, -1) — места нет.
func find_free_spot(id: String) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var rows := WALL_ROWS if is_wall(id) else ROWS
	var center := Vector2(COLS / 2.0, rows / 2.0)
	for r in rows:
		for c in COLS:
			var d := (Vector2(c, r) + Vector2(tiles(id)) / 2.0).distance_to(center)
			if d < best_d and check_place(id, c, r) == "":
				best = Vector2i(c, r)
				best_d = d
	return best


func hit_test(p: Vector2) -> int:
	var best := -1
	var best_y := -INF
	for i in layout.size():
		var id := String(layout[i]["id"])
		if sprite_rect(id, int(layout[i]["c"]), int(layout[i]["r"])).has_point(p):
			# плоские предметы под ногами, настенные «глубже» мебели
			var depth := _nodes[i].position.y - (1000.0 if is_flat(id) else 0.0) - (2000.0 if is_wall(id) else 0.0)
			if depth > best_y:
				best_y = depth
				best = i
	return best


func counter_hit(p: Vector2) -> bool:
	return COUNTER_SPRITE.has_point(p)


# ---------------------------------------------------------------- сетка путей

func rebuild_nav() -> void:
	_astar = _make_grid(_solid_cells(-1))


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
	return g


## Можно ли дойти от двери до стойки в такой сетке.
func _reachable(g: AStarGrid2D) -> bool:
	var a := _free_cell(g, SPAWN_CELL)
	var b := _free_cell(g, Vector2i(1, 0))
	if a.x < 0 or b.x < 0:
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
func find_path(from_feet: Vector2, to: Vector2) -> PackedVector2Array:
	var a := _free_cell(_astar, cell_of_feet(from_feet))
	var b := _free_cell(_astar, cell_at(to))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var pts := _astar.get_point_path(a, b)
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
		if not _astar.is_point_solid(c) and not SPAWN_CELLS.has_point(c):
			return feet_at(c)
	return feet_at(SPAWN_CELL)


func in_entrance_zone(feet: Vector2) -> bool:
	return ENTRANCE_CELLS.has_point(cell_of_feet(feet))


func in_counter_zone(feet: Vector2) -> bool:
	return COUNTER_CELLS.has_point(cell_of_feet(feet))
