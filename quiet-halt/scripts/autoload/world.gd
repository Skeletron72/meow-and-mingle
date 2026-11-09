extends Node
## Хозяин данных мира. Все изменения идут через apply(команда) — так их
## можно проверять, отменять, сохранять и (в будущем) пересылать по сети.
## Одиночная игра = хост без клиентов.

signal loaded
signal object_added(cell: Vector2i)
signal object_removed(cell: Vector2i, id: String)
signal object_changed(cell: Vector2i)
signal chunk_dirty(chunk: Vector2i)
signal project_changed(id: String)
signal project_done(id: String)
signal villager_arrived(id: String)

const G = WorldState.Ground

var state: WorldState = WorldState.new()
var nav: AStarGrid2D = AStarGrid2D.new()
var _rng := RandomNumberGenerator.new()


func new_world(seed_value: int, town_name: String, hemi: int) -> void:
	state = WorldState.new()
	state.town_name = town_name
	state.hemisphere = hemi
	WorldGen.generate(state, seed_value)
	state.start_day = Clock.day_index()
	state.last_day = Clock.day_index()
	Clock.hemisphere = hemi
	_build_nav()
	_rng.seed = seed_value
	_spawn_wild_flowers(Clock.season_for(Clock.month(), hemi))
	loaded.emit()


func load_dict(d: Dictionary) -> void:
	state = WorldState.new()
	state.from_dict(d)
	Clock.hemisphere = state.hemisphere
	_build_nav()
	loaded.emit()


# ---------- навигация ----------

func _build_nav() -> void:
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, WorldState.W, WorldState.H)
	nav.cell_size = Vector2(1, 1)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.update()
	for z in WorldState.H:
		for x in WorldState.W:
			var c := Vector2i(x, z)
			if not state.is_walkable(c):
				nav.set_point_solid(c, true)


func _refresh_nav(c: Vector2i) -> void:
	if WorldState.in_bounds(c):
		nav.set_point_solid(c, not state.is_walkable(c))


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> PackedVector2Array:
	if not WorldState.in_bounds(from_cell) or not WorldState.in_bounds(to_cell):
		return PackedVector2Array()
	if nav.is_point_solid(to_cell):
		return PackedVector2Array()
	return nav.get_point_path(from_cell, to_cell)


func cell_center(c: Vector2i) -> Vector3:
	var x: float = float(c.x) + 0.5
	var z: float = float(c.y) + 0.5
	return Vector3(x, state.height_at(x, z), z)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.z)))


# ---------- команды ----------

func apply(cmd: Dictionary) -> bool:
	match str(cmd.get("t", "")):
		"place":
			var c: Vector2i = cmd.cell
			var id: String = cmd.id
			var rot: int = int(cmd.get("rot", 0))
			if not state.can_place(id, c, rot):
				return false
			state.add_object(id, c, rot, cmd.get("st", {}))
			for fc in state.footprint_of(c):
				_refresh_nav(fc)
			object_added.emit(c)
			return true
		"remove":
			var c: Vector2i = cmd.cell
			if not state.objects.has(WorldState.idx(c)):
				return false
			var id: String = state.objects[WorldState.idx(c)].id
			var fp: Array = state.footprint_of(c)
			state.remove_object(c)
			for fc in fp:
				_refresh_nav(fc)
			object_removed.emit(c, id)
			return true
		"set_st":
			var c: Vector2i = cmd.cell
			var k: int = WorldState.idx(c)
			if not state.objects.has(k):
				return false
			var st: Dictionary = state.objects[k].st
			for key in cmd.st:
				st[key] = cmd.st[key]
			state.objects[k].st = st
			object_changed.emit(c)
			return true
		"replace":
			# убрать объект по якорю и поставить другой
			var c: Vector2i = cmd.cell
			var k: int = WorldState.idx(c)
			if state.objects.has(k):
				var old_id: String = state.objects[k].id
				var fp: Array = state.footprint_of(c)
				state.remove_object(c)
				for fc in fp:
					_refresh_nav(fc)
				object_removed.emit(c, old_id)
			return apply({"t": "place", "id": cmd.id, "cell": c, "rot": cmd.get("rot", 0), "st": cmd.get("st", {})})
		"paint_rect":
			var r: Array = cmd.rect
			for z in range(int(r[1]), int(r[1]) + int(r[3])):
				for x in range(int(r[0]), int(r[0]) + int(r[2])):
					if WorldState.in_bounds(Vector2i(x, z)):
						state.ground[z * WorldState.W + x] = int(cmd.type)
						_refresh_nav(Vector2i(x, z))
			_dirty_rect(r)
			return true
		"height_rect":
			var r: Array = cmd.rect
			for cz in range(int(r[1]), int(r[1]) + int(r[3]) + 1):
				for cx in range(int(r[0]), int(r[0]) + int(r[2]) + 1):
					if cx <= WorldState.W and cz <= WorldState.H:
						state.height[cz * (WorldState.W + 1) + cx] = float(cmd.h)
			_dirty_rect(r)
			return true
		"flag":
			state.flags[cmd.flag] = cmd.get("value", true)
			return true
	return false


func _dirty_rect(r: Array) -> void:
	var c0 := Vector2i(maxi(int(r[0]) - 1, 0) / WorldState.CHUNK, maxi(int(r[1]) - 1, 0) / WorldState.CHUNK)
	var c1 := Vector2i((int(r[0]) + int(r[2]) + 1) / WorldState.CHUNK, (int(r[1]) + int(r[3]) + 1) / WorldState.CHUNK)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			chunk_dirty.emit(Vector2i(cx, cz))


func flag(name: String) -> bool:
	return bool(state.flags.get(name, false))


# ---------- проекты ----------

func project_state(id: String) -> int:
	return int(state.projects.get(id, {}).get("state", 0))


func project_available(id: String) -> bool:
	var p: Dictionary = Data.project(id)
	if p.is_empty():
		return false
	for r in p.get("requires", []):
		if project_state(str(r)) != 3:
			return false
	return true


## Вложить пуговицы. Возвращает, сколько реально принято.
func fund_project(id: String, amount: int) -> int:
	if not project_available(id) or project_state(id) >= 2:
		return 0
	var p: Dictionary = Data.project(id)
	var st: Dictionary = state.projects[id]
	var need: int = int(p.cost) - int(st.funded)
	var take: int = mini(amount, need)
	if take <= 0:
		return 0
	st.funded = int(st.funded) + take
	st.state = 1
	if int(st.funded) >= int(p.cost):
		st.state = 2
		st["ready_day"] = Clock.day_index() + 1
	project_changed.emit(id)
	return take


func tick_projects() -> void:
	for p in Data.projects:
		var id: String = p.id
		var st: Dictionary = state.projects.get(id, {})
		if int(st.get("state", 0)) != 2:
			continue
		var rd: int = int(st.get("ready_day", 0))
		var d: int = Clock.day_index()
		if d > rd or (d == rd and Clock.hour() >= 6):
			_complete_project(id)


func _complete_project(id: String) -> void:
	var p: Dictionary = Data.project(id)
	for e in p.get("effects", []):
		match str(e.op):
			"place":
				apply({"t": "place", "id": e.id, "cell": Vector2i(int(e.cell[0]), int(e.cell[1])), "rot": int(e.get("rot", 0))})
			"replace":
				apply({"t": "replace", "id": e.id, "cell": Vector2i(int(e.cell[0]), int(e.cell[1])), "rot": int(e.get("rot", 0))})
			"paint":
				apply({"t": "paint_rect", "rect": e.rect, "type": int(e.type)})
			"height":
				apply({"t": "height_rect", "rect": e.rect, "h": float(e.h)})
			"flag":
				apply({"t": "flag", "flag": e.flag})
			"villager":
				_villager_moves_in(str(e.id))
	state.projects[id].state = 3
	state.projects[id].done_day = Clock.day_index()
	project_changed.emit(id)
	project_done.emit(id)


func _villager_moves_in(vid: String) -> void:
	var v: Dictionary = Data.villager(vid)
	if v.is_empty():
		return
	state.villagers[vid].present = true
	var h: Array = v.home
	var c := Vector2i(int(h[0]), int(h[1]))
	var sz: int = state.villagers.size()
	apply({"t": "replace", "id": "house", "cell": c, "st": {"owner": vid, "style": sz}})
	villager_arrived.emit(vid)


# ---------- новый день ----------

func process_days(up_to_day: int) -> void:
	var from: int = maxi(state.last_day + 1, up_to_day - 30)
	for d in range(from, up_to_day + 1):
		_new_day(d)
	state.last_day = up_to_day
	tick_projects()


func _new_day(day: int) -> void:
	_rng.seed = hash("%d|%d" % [state.world_seed, day])
	var season: int = Clock.season_for(int(Time.get_datetime_dict_from_unix_time(day * 86400).month), state.hemisphere)
	var to_remove: Array = []
	var to_grow: Array = []
	for k in state.objects.keys():
		var o: Dictionary = state.objects[k]
		var def: Dictionary = Data.object_def(o.id)
		var c: Vector2i = WorldState.cell_of(int(k))
		var st: Dictionary = o.st
		if def.has("fruit"):
			st["fruit"] = mini(int(st.get("fruit", 0)) + 1, 3)
			object_changed.emit(c)
		elif def.has("grows"):
			st["age"] = int(st.get("age", 0)) + 1
			if int(st.age) >= int(def.days):
				to_grow.append([c, str(def.grows)])
		elif o.id == "hole":
			to_remove.append(c)
		elif st.has("wild"):
			st["wild"] = int(st.wild) + 1
			if int(st.wild) >= 3:
				to_remove.append(c)
	for c in to_remove:
		apply({"t": "remove", "cell": c})
	for g in to_grow:
		apply({"t": "replace", "cell": g[0], "id": g[1], "st": {"fruit": 0}})
	_spawn_wild_flowers(season)


func _spawn_wild_flowers(season: int) -> void:
	var kinds: Array = ["flower_tulip", "flower_cornflower", "flower_aster", "flower_hellebore"]
	var kind: String = kinds[[0, 1, 2, 3][season]]
	var count: int = 14 if season != 3 else 6
	var pmin: Vector2i = WorldState.PLAY_MIN
	var pmax: Vector2i = WorldState.PLAY_MAX
	var tries: int = 120
	while count > 0 and tries > 0:
		tries -= 1
		var c := Vector2i(_rng.randi_range(pmin.x, pmax.x), _rng.randi_range(pmin.y + 5, pmax.y))
		if state.get_ground(c) != G.GRASS or not state.can_place(kind, c):
			continue
		apply({"t": "place", "id": kind, "cell": c, "st": {"wild": 0}})
		count -= 1
