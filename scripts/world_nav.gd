class_name WorldNav
extends RefCounted
## Единая сетка ходьбы всего мира (клетка 32 px): тротуар, зал кафе и проём входа в одной сетке.
## Поэтому кот идёт с улицы в кафе и обратно сплошным путём — без дверей, телепортов и смены слоёв.
## Проходимо: клетки зон WALK и пол зала (кроме витрины) — минус мебель, зоны BLOCK и предметы с blocks.
## Интерфейс тот же, что нужен CatWalker: find_path, is_blocked, random_free_point.

const T := 32
const FEET_DY := 10.0

var _astar: AStarGrid2D
var _cols := 0
var _rows := 0
var _room_cell := Vector2i.ZERO   # клетка мира, где лежит левый верх пола зала
var _room_rect := Rect2i()        # клетки пола зала в мире


## walk — зоны ходьбы, block_rects — запретные зоны, block_cells — клетки-предметы, room — интерьер (или null).
func build(world_size: Vector2, walk: Array[Rect2], block_rects: Array[Rect2], block_cells: Array[Vector2i], room: CafeRoom) -> void:
	_cols = ceili(world_size.x / T)
	_rows = ceili(world_size.y / T)
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, _cols, _rows)
	_astar.cell_size = Vector2(T, T)
	_astar.offset = Vector2(T, T) / 2.0
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	_astar.fill_solid_region(_astar.region, true)
	for r in walk:
		_set_rect(r, false)
	if room != null:
		_room_cell = Vector2i(((room.position + CafeRoom.ORIGIN) / T).round())
		_room_rect = Rect2i(_room_cell, Vector2i(CafeRoom.COLS, CafeRoom.ROWS))
		for r in CafeRoom.ROWS:
			for c in CafeRoom.COLS:
				var open := r < CafeRoom.FRONT_ROW or CafeRoom.ENTRANCE_CELLS.has_point(Vector2i(c, r))
				_set_cell(_room_cell + Vector2i(c, r), not open)
		for b in room.solid_cells():
			for y in range(b.position.y, b.end.y):
				for x in range(b.position.x, b.end.x):
					_set_cell(_room_cell + Vector2i(x, y), true)
	for r in block_rects:
		_set_rect(r, true)
	for c in block_cells:
		_set_cell(c, true)


func _set_rect(r: Rect2, solid: bool) -> void:
	for y in _rows:
		for x in _cols:
			if r.has_point((Vector2(x, y) + Vector2(0.5, 0.5)) * T):
				_astar.set_point_solid(Vector2i(x, y), solid)


func _set_cell(c: Vector2i, solid: bool) -> void:
	if _astar.is_in_boundsv(c):
		_astar.set_point_solid(c, solid)


static func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T), floori(p.y / T))


static func cell_of_feet(feet: Vector2) -> Vector2i:
	return cell_at(feet - Vector2(0, FEET_DY))


static func feet_at(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * T + Vector2(0, FEET_DY)


func is_walkable(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell)


## Клетка внутри кафе (по полу зала).
func is_interior(cell: Vector2i) -> bool:
	return _room_rect.has_point(cell)


func interior_cells() -> Rect2i:
	return _room_rect


## Лапки у стойки (локальные клетки стойки -> мир).
func counter_feet(col: int) -> Vector2:
	return feet_at(_room_cell + Vector2i(clampi(col, 0, CafeRoom.COUNTER_CELLS.size.x - 1), 0))


func is_blocked(feet: Vector2) -> bool:
	for dx in [-8.0, 0.0, 8.0]:
		if not is_walkable(cell_of_feet(feet + Vector2(dx, 0))):
			return true
	return false


## Путь по центрам клеток (пусто — дойти нельзя). `to` — любая точка: берётся ближайшая проходимая клетка.
func find_path(from_feet: Vector2, to: Vector2) -> PackedVector2Array:
	var a := _nearest_free(cell_of_feet(from_feet))
	var b := _nearest_free(cell_at(to))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var pts := _astar.get_point_path(a, b)
	if pts.is_empty():
		return pts
	if pts.size() > 1:
		pts.remove_at(0)   # первая точка — центр текущей клетки
	for i in pts.size():
		pts[i] += Vector2(0, FEET_DY)
	return pts


func _nearest_free(c: Vector2i) -> Vector2i:
	c = Vector2i(clampi(c.x, 0, _cols - 1), clampi(c.y, 0, _rows - 1))
	if not _astar.is_point_solid(c):
		return c
	for radius in range(1, maxi(_cols, _rows)):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n := c + Vector2i(dx, dy)
				if _astar.is_in_boundsv(n) and not _astar.is_point_solid(n) and Vector2(dx, dy).length() < best_d:
					best = n
					best_d = Vector2(dx, dy).length()
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Случайная проходимая клетка: inside = true — в зале, false — на улице.
func random_cell(inside: bool) -> Vector2i:
	for _i in 60:
		var c := Vector2i(randi_range(0, _cols - 1), randi_range(0, _rows - 1))
		if is_walkable(c) and is_interior(c) == inside and not (inside and CafeRoom.SPAWN_CELLS.has_point(c - _room_cell)):
			return c
	return _room_cell + CafeRoom.SPAWN_CELL if inside else Vector2i(2, 12)


func random_free_point() -> Vector2:
	return feet_at(random_cell(false))
