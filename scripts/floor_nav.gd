class_name FloorNav
extends RefCounted
## Сетка ходьбы отдельного этажа (второй этаж стоит в мире выше первого, у него своя комната 10×7 клеток).
## Тот же интерфейс, что у WorldNav и CafeRoom (find_path, is_blocked, random_free_point), поэтому кот, поднявшись по лестнице,
## просто получает эту сетку вместо городской и не может выйти за стены. Координаты путей — мировые.

const T := 32
const FEET_DY := 10.0

var origin := Vector2.ZERO      # левый верх пола в мире
var _astar: AStarGrid2D


func setup(world_origin: Vector2, mask: PackedByteArray) -> void:
	origin = world_origin
	rebuild(mask)


func rebuild(mask: PackedByteArray) -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, InteriorSpace.COLS, InteriorSpace.ROWS)
	_astar.cell_size = Vector2(T, T)
	_astar.offset = origin + Vector2(T, T) / 2.0
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for r in InteriorSpace.ROWS:
		for c in InteriorSpace.COLS:
			if mask[r * InteriorSpace.COLS + c] == 0:
				_astar.set_point_solid(Vector2i(c, r), true)


func feet_at(cell: Vector2i) -> Vector2:
	return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * T + Vector2(0, FEET_DY)


func cell_of_feet(feet: Vector2) -> Vector2i:
	var p := feet - Vector2(0, FEET_DY) - origin
	return Vector2i(clampi(floori(p.x / T), 0, InteriorSpace.COLS - 1), clampi(floori(p.y / T), 0, InteriorSpace.ROWS - 1))


func is_walkable(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell)


func nearest_free_cell(c: Vector2i) -> Vector2i:
	c = Vector2i(clampi(c.x, 0, InteriorSpace.COLS - 1), clampi(c.y, 0, InteriorSpace.ROWS - 1))
	if is_walkable(c):
		return c
	for radius in range(1, InteriorSpace.COLS):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n := c + Vector2i(dx, dy)
				if is_walkable(n) and Vector2(dx, dy).length() < best_d:
					best = n
					best_d = Vector2(dx, dy).length()
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Путь по центрам клеток (пусто — дойти нельзя). `to` — любая точка: берётся ближайшая проходимая клетка этажа.
func find_path(from_feet: Vector2, to: Vector2, _guest := false) -> PackedVector2Array:
	var a := nearest_free_cell(cell_of_feet(from_feet))
	var tc := Vector2i(clampi(floori((to.x - origin.x) / T), 0, InteriorSpace.COLS - 1), clampi(floori((to.y - origin.y) / T), 0, InteriorSpace.ROWS - 1))
	var b := nearest_free_cell(tc)
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var pts := _astar.get_point_path(a, b)
	if pts.is_empty():
		return pts
	if pts.size() > 1:
		pts.remove_at(0)
	for i in pts.size():
		pts[i] += Vector2(0, FEET_DY)
	return pts


func is_blocked(feet: Vector2) -> bool:
	for dx in [-8.0, 0.0, 8.0]:
		var p: Vector2 = feet + Vector2(dx, -FEET_DY) - origin
		if p.x < 0.0 or p.x >= InteriorSpace.COLS * T or p.y < 0.0 or p.y >= InteriorSpace.ROWS * T:
			return true
		if _astar.is_point_solid(Vector2i(floori(p.x / T), floori(p.y / T))):
			return true
	return false


func random_free_point() -> Vector2:
	for _i in 40:
		var c := Vector2i(randi_range(0, InteriorSpace.COLS - 1), randi_range(0, InteriorSpace.ROWS - 1))
		if is_walkable(c):
			return feet_at(c)
	return feet_at(Vector2i(5, 4))
