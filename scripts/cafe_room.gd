class_name CafeRoom
extends Node2D
## Комната кафе, общая для режимов «прогулка» и «украшение».
## Рисует стены/пол, ставит мебель из `layout` (массив {"id","x","y","flip"}, ссылка на GameState.layout),
## проверяет, можно ли поставить предмет, и ищет пути для котов (AStarGrid2D по сетке CELL).
##
## Координаты мебели — точка «на полу» (низ по центру спрайта). Спрайты рисуются в 3 раза крупнее исходных.

const FURN_TEX: Texture2D = preload("res://assets/cafe/neko-cafe-furnitures.png")
const S := 3.0                      # масштаб мебели и котов
const CELL := 12                    # клетка сетки поиска пути, px
const ROOM_W := 360
const ROOM_H := 560
const WALL_H := 192
const FLOOR := Rect2(10, 200, 340, 346)       # где могут стоять ноги и основания мебели
const WALL_ZONE := Rect2(4, 6, 352, 170)      # где можно вешать настенное
const WALK_RADIUS := 7.0                      # «толщина» кота при обходе мебели

# Стойка кофейни — неподвижная, у стены. Из неё запускается готовка.
const COUNTER_SRC := Rect2(17, 112, 46, 16)
const COUNTER_SCALE := 4.0
const COUNTER_POS := Vector2(104, 192)
const COUNTER_SPRITE := Rect2(12, 128, 184, 64)
const COUNTER_FOOT := Rect2(12, 176, 184, 18)
const COUNTER_ZONE := Rect2(12, 200, 184, 34)  # здесь кот «у стойки»; мебель сюда ставить нельзя
const SPAWN_POS := Vector2(180, 520)
const SPAWN_ZONE := Rect2(150, 486, 60, 60)    # у двери; тоже держим свободным

const WALL_COLOR := Color("cdb892")
const WALL_STRIPE := Color("d8c6a3")
const BASEBOARD := Color("a98763")
const FLOOR_A := Color("7c5a3a")
const FLOOR_B := Color("86633f")

var layout: Array[Dictionary] = []   # общий с GameState.layout: правки видны сразу

var actors: Node2D                   # сюда добавлять котов: сортируются по y вместе с мебелью
var _wall_layer: Node2D
var _flat_layer: Node2D
var _nodes: Array[Node2D] = []       # узел мебели для каждого элемента layout (тот же индекс)
var _astar: AStarGrid2D


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


# ---------------------------------------------------------------- данные о мебели

static func item_def(id: String) -> Dictionary:
	return Data.furniture.get(id, {})


static func is_wall(id: String) -> bool:
	return String(item_def(id).get("slot", "floor")) == "wall"


static func is_flat(id: String) -> bool:
	return bool(item_def(id).get("flat", false))


## Занимает ли предмет место (кот не пройдёт). Настенное и плоское (коврик, миска) — нет.
static func is_solid(id: String) -> bool:
	return not is_wall(id) and not is_flat(id)


static func sprite_size(id: String) -> Vector2:
	var r: Array = item_def(id)["rect"]
	return Vector2(float(r[2]), float(r[3])) * S


static func sprite_rect(id: String, pos: Vector2) -> Rect2:
	var sz := sprite_size(id)
	return Rect2(pos - Vector2(sz.x / 2.0, sz.y), sz)


## Основание предмета на полу (используется для столкновений и путей).
static func foot_rect(id: String, pos: Vector2) -> Rect2:
	var sz := sprite_size(id)
	var depth := minf(float(item_def(id)["foot"]) * S, sz.y)
	return Rect2(pos.x - sz.x / 2.0, pos.y - depth, sz.x, depth)


## Привязка к сетке расстановки (2 пикселя исходного спрайта).
static func snap(p: Vector2) -> Vector2:
	return Vector2(roundf(p.x / 6.0) * 6.0, roundf(p.y / 6.0) * 6.0)


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


func node_for(index: int) -> Node2D:
	return _nodes[index]


func _spawn_item(item: Dictionary) -> Node2D:
	var id := String(item["id"])
	var def := item_def(id)
	var n := Node2D.new()
	n.position = Vector2(float(item["x"]), float(item["y"]))
	var r: Array = def["rect"]
	var sp := Sprite2D.new()
	sp.texture = FURN_TEX
	sp.region_enabled = true
	sp.region_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	sp.centered = false
	sp.scale = Vector2(S, S)
	sp.position = Vector2(-sprite_size(id).x / 2.0, -sprite_size(id).y)
	sp.flip_h = bool(item.get("flip", false))
	n.add_child(sp)
	var layer: Node2D = _wall_layer if is_wall(id) else (_flat_layer if is_flat(id) else actors)
	layer.add_child(n)
	return n


func _build_counter() -> void:
	var sp := Sprite2D.new()
	sp.texture = FURN_TEX
	sp.region_enabled = true
	sp.region_rect = COUNTER_SRC
	sp.centered = false
	sp.scale = Vector2(COUNTER_SCALE, COUNTER_SCALE)
	sp.position = COUNTER_SPRITE.position
	_wall_layer.add_child(sp)
	var machine := Sprite2D.new()
	machine.texture = FURN_TEX
	machine.region_enabled = true
	machine.region_rect = Rect2(131, 67, 11, 13)
	machine.centered = false
	machine.scale = Vector2(COUNTER_SCALE, COUNTER_SCALE)
	machine.position = Vector2(140, 112)
	_wall_layer.add_child(machine)


func _draw() -> void:
	draw_rect(Rect2(0, 0, ROOM_W, WALL_H), WALL_COLOR)
	for x in range(12, ROOM_W, 48):
		draw_rect(Rect2(x, 0, 24, WALL_H - 16), WALL_STRIPE)
	draw_rect(Rect2(0, WALL_H - 16, ROOM_W, 16), BASEBOARD)
	draw_rect(Rect2(0, WALL_H - 2, ROOM_W, 2), BASEBOARD.darkened(0.35))
	var rows := int(ceil((ROOM_H - WALL_H) / 24.0))
	for ry in rows:
		for cx in 15:
			var c := FLOOR_A if (ry + cx) % 2 == 0 else FLOOR_B
			draw_rect(Rect2(cx * 24, WALL_H + ry * 24, 24, 24), c)
	# коврик у входа
	draw_rect(Rect2(SPAWN_POS.x - 30, ROOM_H - 20, 60, 14), Color("5b3d27"))
	draw_rect(Rect2(SPAWN_POS.x - 26, ROOM_H - 17, 52, 8), Color("7a5238"))


# ---------------------------------------------------------------- проверка размещения

## Пустая строка — ставить можно, иначе причина отказа (для всплывающей подписи).
## `ignore` — индекс предмета, который сейчас двигаем (его самого не учитываем).
func check_place(id: String, pos: Vector2, ignore := -1) -> String:
	if item_def(id).is_empty():
		return tr("Неизвестный предмет")
	if is_wall(id):
		var r := sprite_rect(id, pos)
		if not WALL_ZONE.encloses(r):
			return tr("Это вешается на стену")
		if r.intersects(COUNTER_SPRITE):
			return tr("Тут занято")
		for i in layout.size():
			var other := String(layout[i]["id"])
			if i != ignore and is_wall(other) and r.intersects(sprite_rect(other, _pos(layout[i]))):
				return tr("Тут занято")
		return ""
	var fr := foot_rect(id, pos)
	if not FLOOR.encloses(fr):
		return tr("Сюда нельзя")
	var solid := is_solid(id)
	if solid and (fr.intersects(SPAWN_ZONE) or fr.intersects(COUNTER_ZONE)):
		return tr("Не загораживайте проход")
	for i in layout.size():
		var other := String(layout[i]["id"])
		if i == ignore or is_wall(other):
			continue
		var both_solid := solid and is_solid(other)
		var both_flat := is_flat(id) and is_flat(other)
		if (both_solid or both_flat) and fr.intersects(foot_rect(other, _pos(layout[i]))):
			return tr("Тут занято")
	if solid:
		var foots := _solid_foots(ignore)
		foots.append(fr)
		if not _reachable(_make_grid(foots)):
			return tr("Не загораживайте проход")
	return ""


## Подбирает свободное место для нового предмета, ближе к центру. Vector2.INF — места нет.
func find_free_spot(id: String) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	var area := WALL_ZONE if is_wall(id) else FLOOR
	var center := Vector2(ROOM_W / 2.0, area.get_center().y)
	var y := area.position.y
	while y <= area.end.y + 6.0:
		var x := area.position.x
		while x <= area.end.x + 6.0:
			var p := Vector2(x, y)
			var d := p.distance_to(center)
			if d < best_d and check_place(id, p) == "":
				best = p
				best_d = d
			x += 12.0
		y += 12.0
	return best


func hit_test(p: Vector2) -> int:
	var best := -1
	var best_y := -INF
	for i in layout.size():
		var id := String(layout[i]["id"])
		var pos := _pos(layout[i])
		if sprite_rect(id, pos).has_point(p):
			# плоские предметы под ногами, настенные «глубже» мебели
			var depth := pos.y - (1000.0 if is_flat(id) else 0.0) - (2000.0 if is_wall(id) else 0.0)
			if depth > best_y:
				best_y = depth
				best = i
	return best


func counter_hit(p: Vector2) -> bool:
	return COUNTER_SPRITE.has_point(p)


static func _pos(item: Dictionary) -> Vector2:
	return Vector2(float(item["x"]), float(item["y"]))


# ---------------------------------------------------------------- сетка путей

func rebuild_nav() -> void:
	_astar = _make_grid(_solid_foots(-1))


func _solid_foots(ignore: int) -> Array[Rect2]:
	var out: Array[Rect2] = [COUNTER_FOOT]
	for i in layout.size():
		var id := String(layout[i]["id"])
		if i != ignore and is_solid(id):
			out.append(foot_rect(id, _pos(layout[i])))
	return out


func _make_grid(foots: Array[Rect2]) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, ROOM_W / CELL, ROOM_H / CELL)
	g.cell_size = Vector2(CELL, CELL)
	g.offset = Vector2(CELL / 2.0, CELL / 2.0)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	var grown: Array[Rect2] = []
	for f in foots:
		grown.append(f.grow(WALK_RADIUS))
	for cy in g.region.size.y:
		for cx in g.region.size.x:
			var c := Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
			var blocked := c.x < FLOOR.position.x + WALK_RADIUS or c.x > FLOOR.end.x - WALK_RADIUS \
				or c.y < FLOOR.position.y or c.y > FLOOR.end.y
			if not blocked:
				for r in grown:
					if r.has_point(c):
						blocked = true
						break
			if blocked:
				g.set_point_solid(Vector2i(cx, cy), true)
	return g


## Можно ли дойти от двери до стойки в такой сетке.
func _reachable(g: AStarGrid2D) -> bool:
	var a := _free_cell(g, _cell(SPAWN_POS))
	var b := _free_cell(g, _cell(COUNTER_ZONE.get_center()))
	if a.x < 0 or b.x < 0:
		return false
	return not g.get_id_path(a, b).is_empty()


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, ROOM_W / CELL - 1), clampi(int(p.y / CELL), 0, ROOM_H / CELL - 1))


## Ближайшая свободная клетка (кольцами). (-1,-1) — свободных нет.
func _free_cell(g: AStarGrid2D, c: Vector2i) -> Vector2i:
	if not g.is_point_solid(c):
		return c
	for radius in range(1, 40):
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


func is_blocked(p: Vector2) -> bool:
	return _astar.is_point_solid(_cell(p))


## Путь для кота по свободным клеткам (пусто — дойти нельзя). Последняя точка — сама цель, если она свободна.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := _free_cell(_astar, _cell(from))
	var b := _free_cell(_astar, _cell(to))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var pts := _astar.get_point_path(a, b)
	if pts.is_empty():
		return pts
	pts.remove_at(0)  # первая точка — центр текущей клетки, кот и так в ней
	if not is_blocked(to):
		if pts.is_empty():
			pts.append(to)
		else:
			pts[pts.size() - 1] = to
	return pts


func random_free_point() -> Vector2:
	for _i in 40:
		var p := Vector2(randf_range(FLOOR.position.x, FLOOR.end.x), randf_range(FLOOR.position.y, FLOOR.end.y))
		if not is_blocked(p) and not SPAWN_ZONE.has_point(p):
			return p
	return SPAWN_POS


func in_counter_zone(feet: Vector2) -> bool:
	return COUNTER_ZONE.grow(8).has_point(feet)
