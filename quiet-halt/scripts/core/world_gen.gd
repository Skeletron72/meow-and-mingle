class_name WorldGen
extends RefCounted
## Генерация стартового города «Тихая Заводь». Всё детерминировано от семени.

const G = WorldState.Ground


static func generate(ws: WorldState, seed_value: int) -> void:
	ws.world_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.07

	_ground(ws)
	_heights(ws, noise)
	_structures(ws)
	_nature(ws, rng)
	_flatten_under_objects(ws)
	ws.rebuild_derived()
	_clear_notes(ws)
	for p in Data.projects:
		ws.projects[p.id] = {"state": 0, "funded": 0, "done_day": 0}
	for v in Data.villagers:
		ws.villagers[v.id] = {"friend": 0, "talked_day": -1, "request": 0, "present": bool(v.get("start", false))}


static func _setg(ws: WorldState, x: int, z: int, g: int) -> void:
	if x >= 0 and z >= 0 and x < WorldState.W and z < WorldState.H:
		ws.ground[z * WorldState.W + x] = g


static func _rect(ws: WorldState, x0: int, z0: int, w: int, h: int, g: int) -> void:
	for z in range(z0, z0 + h):
		for x in range(x0, x0 + w):
			_setg(ws, x, z, g)


static func _ground(ws: WorldState) -> void:
	var pmin: Vector2i = WorldState.PLAY_MIN
	var pmax: Vector2i = WorldState.PLAY_MAX
	for z in WorldState.H:
		for x in WorldState.W:
			var inside: bool = x >= pmin.x and x <= pmax.x and z >= pmin.y and z <= pmax.y
			_setg(ws, x, z, G.GRASS if inside else G.HILL)
	# железная дорога
	_rect(ws, 0, 6, WorldState.W, 2, G.BED)
	# перрон и привокзальная площадь
	_rect(ws, 26, 8, 30, 3, G.PLATFORM)
	_rect(ws, 31, 16, 20, 6, G.PAVING)
	# Променад (брусчатка) и тропы
	_rect(ws, 38, 22, 5, 10, G.PAVING)
	_rect(ws, 38, 36, 5, 14, G.PATH)
	_rect(ws, 22, 22, 16, 1, G.PATH)
	_rect(ws, 43, 22, 16, 1, G.PATH)
	_rect(ws, 25, 20, 1, 2, G.PATH)
	_rect(ws, 55, 20, 1, 2, G.PATH)
	_rect(ws, 19, 28, 1, 3, G.PATH)
	_rect(ws, 49, 28, 1, 3, G.PATH)
	_rect(ws, 61, 28, 1, 3, G.PATH)
	_rect(ws, 19, 31, 43, 1, G.PATH)
	# речка с песчаными берегами
	_rect(ws, 0, 31, WorldState.W, 1, G.SAND)
	_rect(ws, 0, 36, WorldState.W, 1, G.SAND)
	_rect(ws, 0, 32, WorldState.W, 4, G.WATER)
	# озеро на юге
	for z in range(42, WorldState.H):
		for x in WorldState.W:
			var dx: float = (float(x) + 0.5 - 41.0) / 21.0
			var dz: float = (float(z) + 0.5 - 54.0) / 8.5
			var d: float = dx * dx + dz * dz
			if d < 1.0:
				_setg(ws, x, z, G.WATER)
			elif d < 1.35 and ws.get_ground(Vector2i(x, z)) != G.WATER and z <= pmax.y:
				_setg(ws, x, z, G.SAND)


static func _heights(ws: WorldState, noise: FastNoiseLite) -> void:
	var pmin: Vector2i = WorldState.PLAY_MIN
	var pmax: Vector2i = WorldState.PLAY_MAX
	for cz in range(0, WorldState.H + 1):
		for cx in range(0, WorldState.W + 1):
			var dx: float = maxf(maxf(float(pmin.x) - float(cx), float(cx) - float(pmax.x + 1)), 0.0)
			var dz: float = maxf(maxf(float(pmin.y) - float(cz), float(cz) - float(pmax.y + 1)), 0.0)
			var d: float = sqrt(dx * dx + dz * dz)
			var h: float = smoothstep(0.0, 9.0, d) * 5.5
			h += noise.get_noise_2d(float(cx), float(cz)) * (0.15 + d * 0.07)
			# мягкие холмики внутри долины
			var inside_h: float = (noise.get_noise_2d(float(cx) * 1.7 + 50.0, float(cz) * 1.7) * 0.5 + 0.5) * 0.55
			h += inside_h * (1.0 - smoothstep(0.0, 3.0, d))
			ws.height[cz * (WorldState.W + 1) + cx] = h
	# плоские зоны под путями, перроном, берегами; углубление воды
	for cz in range(0, WorldState.H + 1):
		for cx in range(0, WorldState.W + 1):
			var water: int = 0
			var flat: bool = false
			var total: int = 0
			for oz in [-1, 0]:
				for ox in [-1, 0]:
					var c := Vector2i(cx + ox, cz + oz)
					if WorldState.in_bounds(c):
						total += 1
						var g: int = ws.ground[WorldState.idx(c)]
						if g == G.WATER:
							water += 1
						elif g != G.GRASS and g != G.HILL:
							flat = true
			var i: int = cz * (WorldState.W + 1) + cx
			if water == total and total > 0:
				ws.height[i] = -0.75
			elif water > 0:
				ws.height[i] = -0.32
			elif flat:
				ws.height[i] = 0.0


static func _place(ws: WorldState, id: String, x: int, z: int, st: Dictionary = {}, rot: int = 0) -> void:
	if ws.can_place(id, Vector2i(x, z), rot):
		ws.add_object(id, Vector2i(x, z), rot, st)


static func _structures(ws: WorldState) -> void:
	ws.add_object("rails", Vector2i(0, 6))
	ws.add_object("station", Vector2i(36, 11))
	ws.add_object("kiosk", Vector2i(31, 9))
	ws.add_object("board", Vector2i(49, 9))
	var idx_house: int = 0
	for v in Data.villagers:
		var h: Array = v.home
		if bool(v.get("start", false)):
			ws.add_object("house", Vector2i(int(h[0]), int(h[1])), 0, {"owner": v.id, "style": idx_house})
		else:
			ws.add_object("plot_sign", Vector2i(int(h[0]), int(h[1])), 0, {"for": v.id})
		idx_house += 1
	for p in [[33, 18], [43, 18], [33, 24], [43, 24]]:
		ws.add_object("lot_boarded", Vector2i(p[0], p[1]), 1 if int(p[0]) < 40 else 3)


static func _nature(ws: WorldState, rng: RandomNumberGenerator) -> void:
	var pmin: Vector2i = WorldState.PLAY_MIN
	var pmax: Vector2i = WorldState.PLAY_MAX
	# деревья внутри долины
	var tries: int = 1400
	var placed: int = 0
	while tries > 0 and placed < 150:
		tries -= 1
		var x: int = rng.randi_range(pmin.x, pmax.x)
		var z: int = rng.randi_range(pmin.y + 5, pmax.y)
		if not _free_grass(ws, x, z, 2):
			continue
		var r: float = rng.randf()
		var id: String = "tree_oak"
		if r < 0.14:
			id = "tree_apple"
		elif r < 0.25:
			id = "tree_pear"
		elif r < 0.36:
			id = "tree_cherry"
		elif r < 0.55:
			id = "tree_pine"
		elif r < 0.75:
			id = "bush"
		elif r < 0.82:
			id = "rock"
		var st: Dictionary = {}
		if id.begins_with("tree_") and Data.object_def(id).has("fruit"):
			st = {"fruit": 3}
		ws.add_object(id, Vector2i(x, z), rng.randi_range(0, 3), st)
		placed += 1
	# сосны на холмах вокруг долины
	for z in range(0, WorldState.H):
		for x in range(0, WorldState.W):
			var c := Vector2i(x, z)
			if ws.ground[WorldState.idx(c)] != G.HILL:
				continue
			var dx: int = maxi(maxi(pmin.x - x, x - pmax.x), 0)
			var dz: int = maxi(maxi(pmin.y - z, z - pmax.y), 0)
			var d: int = maxi(dx, dz)
			if d < 1 or d > 11:
				continue
			if z >= 6 and z <= 7:
				continue # рельсы
			if rng.randf() < 0.14 and ws.can_place("tree_pine", c):
				ws.add_object("tree_pine", c, rng.randi_range(0, 3))


static func _free_grass(ws: WorldState, x: int, z: int, margin: int) -> bool:
	for dz in range(-margin, margin + 1):
		for dx in range(-margin, margin + 1):
			var c := Vector2i(x + dx, z + dz)
			if not WorldState.in_bounds(c):
				return false
			var g: int = ws.ground[WorldState.idx(c)]
			if g != G.GRASS:
				return false
			if ws.occ[WorldState.idx(c)] != 0 and (absi(dx) <= 1 and absi(dz) <= 1):
				return false
	return true


static func _flatten_under_objects(ws: WorldState) -> void:
	for k in ws.objects.keys():
		var o: Dictionary = ws.objects[k]
		var id: String = o.id
		if id.begins_with("tree_") or id == "bush" or id == "rock" or id == "rails":
			continue
		var a: Vector2i = WorldState.cell_of(int(k))
		var def: Dictionary = Data.object_def(id)
		var sz: Array = def.get("size", [1, 1])
		for dz in range(0, int(sz[1]) + 1):
			for dx in range(0, int(sz[0]) + 1):
				var cx: int = a.x + dx
				var cz: int = a.y + dz
				if cx <= WorldState.W and cz <= WorldState.H:
					ws.height[cz * (WorldState.W + 1) + cx] = 0.0


## Места, где закопаны страницы журнала, должны быть свободны и проходимы.
static func _clear_notes(ws: WorldState) -> void:
	for n in Data.notes:
		var c := Vector2i(int(n.cell[0]), int(n.cell[1]))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var cc := Vector2i(c.x + dx, c.y + dz)
				var a: int = ws.anchor_at(cc)
				if a >= 0 and ws.objects.has(a):
					var id: String = ws.objects[a].id
					if id.begins_with("tree_") or id == "bush" or id == "rock":
						ws.remove_object(WorldState.cell_of(a))
		if ws.ground[WorldState.idx(c)] in [G.WATER, G.HILL]:
			push_warning("Страница " + str(n.id) + " попала в воду!")
