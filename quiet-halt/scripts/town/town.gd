extends Node3D
## Корневая сцена города: собирает мир, игрока, жителей и интерфейс,
## обрабатывает действия (инструменты, предметы, разговоры, проекты).

signal act_signal

var terrain: TerrainView
var objects_view: ObjectsView
var env: EnvCtl
var player: Player
var cam: CameraRig
var hud: Hud
var villagers: Dictionary = {}
var pickups: Array[Pickup] = []
var critters: Array[Critter] = []
var glint: Glint
var train: Train

var bag_panel: BagPanel
var shop_panel: ShopPanel
var projects_panel: ProjectsPanel
var journal_panel: JournalPanel
var pause_panel: PausePanel

var test_mode: bool = false
var tool_index: int = 0
var _target: Dictionary = {}
var _target_t: float = 0.0
var _act_flag: bool = false
var _busy: bool = false
var _critter_t: float = 2.0
var _crit_rng := RandomNumberGenerator.new()
var _cutscene: bool = false
var _finale_running: bool = false
var _ambient_t: float = 0.0


func _ready() -> void:
	if not Game.in_game:
		Game.start_new_game("Тест", CharacterModel.default_look(), "Тихая Заводь", 0)
		World.state.flags.erase("arrival_pending")
		test_mode = true
	World.process_days(Clock.day_index())
	_crit_rng.randomize()

	terrain = TerrainView.new()
	terrain.name = "Terrain"
	add_child(terrain)
	objects_view = ObjectsView.new()
	objects_view.name = "Objects"
	add_child(objects_view)
	env = EnvCtl.new()
	env.name = "Env"
	add_child(env)

	player = Player.new()
	player.name = "Player"
	add_child(player)
	var pp: Array = Game.profile.get("pos", [])
	if pp.size() == 2:
		player.global_position = World.cell_center(Vector2i(int(pp[0]), int(pp[1])))
	else:
		player.global_position = World.cell_center(Vector2i(39, 9))
	cam = CameraRig.new()
	cam.name = "CameraRig"
	cam.target = player
	add_child(cam)
	cam.snap()
	_spawn_villagers()

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	_build_panels()
	hud.action_pressed.connect(_on_act)
	hud.tool_selected.connect(_select_tool)
	hud.bag_pressed.connect(func() -> void: _open_bag())
	hud.menu_pressed.connect(func() -> void: _open_pause())
	hud.camera_drag.connect(func(dx: float) -> void: cam.rotate_by(dx))

	World.project_done.connect(_on_project_done)
	World.villager_arrived.connect(_on_villager_arrived)
	Clock.day_changed.connect(func(_d: int) -> void: _update_glint())
	_select_tool(0)
	_update_glint()
	Sfx.music_on = true
	if World.flag("arrival_pending"):
		_arrival_cutscene()
	else:
		hud.banner(World.state.town_name, 2.0)


func _build_panels() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	bag_panel = BagPanel.new()
	shop_panel = ShopPanel.new()
	projects_panel = ProjectsPanel.new()
	journal_panel = JournalPanel.new()
	pause_panel = PausePanel.new()
	for p in [bag_panel, shop_panel, projects_panel, journal_panel, pause_panel]:
		layer.add_child(p)
	bag_panel.use_item.connect(_use_bag_item)
	pause_panel.journal_requested.connect(func() -> void: journal_panel.open_tab(0))
	pause_panel.quit_requested.connect(_quit_to_menu)


func _spawn_villagers() -> void:
	for v in Data.villagers:
		var st: Dictionary = World.state.villagers.get(v.id, {})
		if bool(st.get("present", false)):
			_add_villager(v)


func _add_villager(v: Dictionary) -> Villager:
	var n := Villager.new()
	n.name = "V_" + str(v.id)
	add_child(n)
	n.setup(v)
	n.global_position = World.cell_center(n.home_cell)
	villagers[v.id] = n
	return n


# ---------------------------------------------------------------- цикл

func _process(delta: float) -> void:
	env.focus = player.global_position
	player.cam_yaw = cam.yaw
	player.touch_vec = hud.touch.stick
	player.controls_enabled = Game.ui_lock == 0 and not _cutscene
	hud.touch.show_stick = bool(Game.settings.get("touch", false))
	hud.set_weather_text("%s · %s" % [Weather.name_of(env.weather), Clock.season_name()])
	_ambient_t -= delta
	if _ambient_t <= 0.0:
		_ambient_t = 0.3
		Sfx.set_ambient(1.0 if env.weather == Weather.Type.RAIN else (0.0), 0.5 if env.weather in [Weather.Type.SNOW, Weather.Type.CLOUDY, Weather.Type.FOG] else 0.15)
	_target_t -= delta
	if _target_t <= 0.0 and not _busy and not _cutscene:
		_target_t = 0.1
		_target = _find_target()
		hud.set_prompt(str(_target.get("label", "")))
	if Game.ui_lock > 0 or _cutscene:
		hud.set_prompt("")
	_update_pickups()
	_update_critters(delta)
	_check_finale()


# ---------------------------------------------------------------- ввод

func _unhandled_input(event: InputEvent) -> void:
	if _cutscene:
		return
	if event.is_action_pressed("act") and not event.is_echo():
		_on_act()
	elif event.is_action_pressed("bag"):
		_open_bag()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_open_pause()
	elif event.is_action_pressed("tool_next"):
		_select_tool((tool_index + 1) % Game.TOOLS.size())
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_select_tool(0)
		elif event.keycode == KEY_2:
			_select_tool(1)
		elif event.keycode == KEY_3:
			_select_tool(2)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		cam.zoom_target = clampf(cam.zoom_target - 0.8, 5.0, 16.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		cam.zoom_target = clampf(cam.zoom_target + 0.8, 5.0, 16.0)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		cam.rotate_by(event.relative.x)


func _select_tool(i: int) -> void:
	tool_index = i
	Game.profile["tool"] = Game.TOOLS[i]
	hud.touch.set_tool(i)
	hud.set_tool_label(str(Data.item_name(Game.TOOLS[i])))
	Sfx.play("click")


func _open_bag() -> void:
	if Game.ui_lock == 0 and not _busy:
		bag_panel.open_panel()


func _open_pause() -> void:
	if Game.ui_lock == 0 and not _busy:
		pause_panel.open_panel()


func _quit_to_menu() -> void:
	_save_pos()
	Game.save_game()
	Sfx.music_on = false
	Game.change_scene("res://scenes/menu.tscn")


func _save_pos() -> void:
	var c: Vector2i = player.cell()
	Game.profile["pos"] = [c.x, c.y]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if player:
			_save_pos()


func _on_act() -> void:
	if _cutscene or Game.ui_lock > 0:
		return
	if _busy:
		_act_flag = true
		act_signal.emit()
		return
	_do_action()


# ---------------------------------------------------------------- цели взаимодействия

func _find_target() -> Dictionary:
	var pc: Vector3 = player.global_position
	var fwd: Vector3 = player.facing
	var best: Dictionary = {}
	var best_d: float = 2.1
	for v in villagers.values():
		var vv: Villager = v
		if not vv.visible or vv.sleeping or vv.scripted:
			continue
		var off: Vector3 = vv.global_position - pc
		off.y = 0
		var d: float = off.length()
		if d < best_d and (d < 0.7 or off.normalized().dot(fwd) > -0.25):
			best_d = d
			best = {"kind": "villager", "node": vv, "label": "Поговорить: " + str(vv.data.name)}
	if not best.is_empty():
		return best
	var cands: Dictionary = {}
	var fc: Vector2i = player.front_cell(0.8)
	var pcell: Vector2i = player.cell()
	for base in [fc, pcell]:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var a: int = World.state.anchor_at(Vector2i(base.x + dx, base.y + dz))
				if a >= 0:
					cands[a] = true
	var best_o: float = 99.0
	for a in cands.keys():
		var o: Dictionary = World.state.objects.get(int(a), {})
		if o.is_empty():
			continue
		var info: Dictionary = _object_info(o, int(a))
		if info.is_empty():
			continue
		var ac: Vector2i = WorldState.cell_of(int(a))
		var fp: Array = World.state.footprint_of(ac)
		var min_c := Vector2(1e9, 1e9)
		var max_c := Vector2(-1e9, -1e9)
		for c in fp:
			min_c.x = minf(min_c.x, float(c.x))
			min_c.y = minf(min_c.y, float(c.y))
			max_c.x = maxf(max_c.x, float(c.x + 1))
			max_c.y = maxf(max_c.y, float(c.y + 1))
		var dx2: float = maxf(maxf(min_c.x - pc.x, 0.0), pc.x - max_c.x)
		var dz2: float = maxf(maxf(min_c.y - pc.z, 0.0), pc.z - max_c.y)
		var dist: float = sqrt(dx2 * dx2 + dz2 * dz2)
		if dist < 1.15 and dist < best_o:
			best_o = dist
			info["anchor"] = ac
			best = info
	if not best.is_empty():
		return best
	return _tool_target()


func _object_info(o: Dictionary, _a: int) -> Dictionary:
	var id: String = o.id
	var def: Dictionary = Data.object_def(id)
	var st: Dictionary = o.st
	if def.has("fruit"):
		if int(st.get("fruit", 0)) > 0:
			return {"kind": "tree", "label": "Потрясти дерево"}
		return {}
	if id.begins_with("flower_"):
		return {"kind": "flower", "label": "Сорвать: " + Data.item_name(str(def.item))}
	match id:
		"board": return {"kind": "board", "label": "Путевые листы"}
		"kiosk": return {"kind": "kiosk", "label": "Привокзальная лавка"}
		"shop_flowers": return {"kind": "flowershop", "label": "Цветочная лавка"}
		"cafe": return {"kind": "cafe", "label": "Кафе «Пар и Пряник»"}
		"lot_boarded": return {"kind": "lot", "label": "Заколоченная лавка"}
		"house": return {"kind": "house", "label": "Постучать в дверь"}
		"fountain": return {"kind": "fountain", "label": "Бросить монетку"}
		"station": return {"kind": "station", "label": "Вокзал"}
		"plot_sign": return {"kind": "plot", "label": "Свободный участок"}
		"clock_face": return {"kind": "clock", "label": "Часы"}
	return {}


func _tool_target() -> Dictionary:
	var tool: String = Game.TOOLS[tool_index]
	match tool:
		"net":
			return {"kind": "tool", "tool": "net", "label": "Взмахнуть сачком"}
		"rod":
			if _water_ahead() != Vector3.INF:
				return {"kind": "tool", "tool": "rod", "label": "Забросить удочку"}
			return {"kind": "tool", "tool": "rod", "label": "Удочка (нужна вода)"}
		_:
			return {"kind": "tool", "tool": "shovel", "label": "Копать"}


func _water_ahead() -> Vector3:
	var d: float = 1.2
	while d <= 4.6:
		var p: Vector3 = player.global_position + player.facing * d
		if World.state.get_ground(World.world_to_cell(p)) == WorldState.Ground.WATER:
			return Vector3(p.x, -0.2, p.z)
		d += 0.4
	return Vector3.INF


# ---------------------------------------------------------------- действия

func _do_action() -> void:
	if _target.is_empty():
		_target = _find_target()
	if _target.is_empty():
		return
	_busy = true
	player.busy = true
	await _run_target(_target)
	_busy = false
	player.busy = false
	_target_t = 0.0


func _run_target(t: Dictionary) -> void:
	match str(t.kind):
		"villager":
			await _talk(t.node)
		"tree":
			await _shake_tree(t.anchor)
		"flower":
			_pick_flower(t.anchor)
		"board":
			projects_panel.open_panel()
			await projects_panel.closed
		"kiosk":
			shop_panel.open_shop("Привокзальная лавка", ["sapling_apple", "sapling_pear", "sapling_cherry"])
			await shop_panel.closed
		"flowershop":
			shop_panel.open_shop("Цветочная лавка", ["seed_tulip", "seed_cornflower", "seed_aster"])
			await shop_panel.closed
		"cafe":
			await _cafe()
		"lot":
			Game.say_toast("Лавка заколочена. Откройте её через «Путевые листы».", "info")
			Sfx.play("nope")
		"house":
			await _knock(t.anchor)
		"fountain":
			await _fountain()
		"station":
			await _station_door()
		"plot":
			Game.say_toast("Свободный участок. Новые жители приедут, когда в городе станет уютнее.", "info")
		"clock":
			Game.say_toast("Часы показывают %s." % Clock.time_string(), "info")
		"tool":
			match str(t.tool):
				"net": await _use_net()
				"rod": await _use_rod()
				"shovel": await _use_shovel()


func _shake_tree(anchor: Vector2i) -> void:
	var k: int = WorldState.idx(anchor)
	var o: Dictionary = World.state.objects.get(k, {})
	if o.is_empty():
		return
	var def: Dictionary = Data.object_def(o.id)
	var item: String = str(def.get("fruit", "apple"))
	var n: int = int(o.st.get("fruit", 0))
	player.face_toward(World.cell_center(anchor))
	Sfx.play("shake")
	var node: Node3D = objects_view.node_at(anchor)
	if node:
		var base: float = node.rotation.z
		var tw := create_tween()
		for i in 5:
			tw.tween_property(node, "rotation:z", 0.05 * (1.0 if i % 2 == 0 else -1.0), 0.05)
		tw.tween_property(node, "rotation:z", base, 0.05)
	cam.shake = 0.5
	await get_tree().create_timer(0.35).timeout
	World.apply({"t": "set_st", "cell": anchor, "st": {"fruit": 0}})
	var from: Vector3 = World.cell_center(anchor) + Vector3(0, 2.4, 0)
	for i in n:
		var ang: float = TAU * float(i) / float(n) + 0.5
		var to: Vector3 = World.cell_center(anchor) + Vector3(cos(ang), 0, sin(ang)) * 1.1
		to.y = World.state.height_at(to.x, to.z)
		_spawn_pickup(item, from + Vector3(cos(ang) * 0.4, 0, sin(ang) * 0.4), to)
		await get_tree().create_timer(0.08).timeout
	# иногда сверху падает… сюрприз
	if randf() < 0.08:
		Game.say_toast("Из кроны вылетела птичка. Ей не понравилось!", "info")


func _spawn_pickup(id: String, from: Vector3, to: Vector3) -> void:
	var p := Pickup.new()
	add_child(p)
	p.setup(id, from, to)
	pickups.append(p)


func _update_pickups() -> void:
	var i: int = pickups.size() - 1
	while i >= 0:
		var p: Pickup = pickups[i]
		if not is_instance_valid(p):
			pickups.remove_at(i)
		elif p.ready_to_take() and p.global_position.distance_to(player.global_position) < 1.0:
			if Game.add_item(p.item_id, 1):
				Sfx.play("pickup")
				_item_toast(p.item_id)
				p.queue_free()
				pickups.remove_at(i)
		i -= 1


func _item_toast(id: String, count: int = 1) -> void:
	Game.say_toast("Получено: %s%s" % [Data.item_name(id), "" if count == 1 else " ×%d" % count], "good")


func _pick_flower(anchor: Vector2i) -> void:
	var o: Dictionary = World.state.objects.get(WorldState.idx(anchor), {})
	if o.is_empty():
		return
	var item: String = str(Data.object_def(o.id).get("item", "tulip"))
	if not Game.can_add(item, 1):
		Game.say_toast("Рюкзак полон!", "bad")
		Sfx.play("nope")
		return
	player.face_toward(World.cell_center(anchor))
	World.apply({"t": "remove", "cell": anchor})
	Game.add_item(item, 1)
	Sfx.play("pickup")
	_item_toast(item)


func _fountain() -> void:
	if Game.money() < 10:
		Game.say_toast("Нет даже монетки…", "bad")
		return
	Game.spend_money(10)
	Sfx.play("splash")
	World.state.flags["wishes"] = int(World.state.flags.get("wishes", 0)) + 1
	var w: int = int(World.state.flags["wishes"])
	await get_tree().create_timer(0.5).timeout
	var lines: Array[String] = ["Вы загадали желание. Фонтан тихо булькнул.", "Монетка блеснула и пропала. Кажется, фонтан доволен.", "Желание принято. Станция одобрительно скрипнула."]
	Game.say_toast(lines[w % lines.size()], "info")
	if w == 7:
		Game.add_money(77)
		Game.say_toast("Фонтан вернул вам счастливые 77 пуговиц!", "good")


func _cafe() -> void:
	var d: DialogueUI = hud.dialogue
	var who: String = "Фланель" if villagers.has("flanel") else "Кафе"
	if World.flag("cafe_open"):
		await d.say(who, "Заходите, смотритель! Чай, булочки, свежие сплетни — всё горячее.", 0.9)
		var r: int = await d.choose(who, "Что желаете?", ["Чашку чая (20)", "Просто посидеть", "Не сейчас"], 0.9)
		if r == 0:
			if Game.spend_money(20):
				Sfx.play("chime")
				await d.say(who, "Ваш чай. Пейте, пока не остыл — а то заварю заново, и вы будете обязаны допить.", 0.9)
				if villagers.has("flanel"):
					_befriend("flanel", 2)
			else:
				await d.say(who, "Ничего, в другой раз. Чай подождёт.", 0.9)
		elif r == 1:
			await d.say(who, "Посидите. В тишине тоже есть вкус.", 0.9)
	d.end()


func _knock(anchor: Vector2i) -> void:
	var o: Dictionary = World.state.objects.get(WorldState.idx(anchor), {})
	var owner: String = str(o.get("st", {}).get("owner", ""))
	Sfx.play("click")
	var d: DialogueUI = hud.dialogue
	if owner != "" and villagers.has(owner):
		var v: Villager = villagers[owner]
		if v.sleeping:
			await d.say("Дом", "Тихо. Внутри кто-то посапывает. Лучше прийти утром.")
		else:
			await d.say("Дом", "Тук-тук… Хозяин сейчас гуляет по городу. Поищите %s на улице." % str(v.data.name))
	else:
		await d.say("Дом", "Тук-тук… Никто не отвечает.")
	d.end()


func _station_door() -> void:
	var d: DialogueUI = hud.dialogue
	if Game.item_count("key_dispatch") > 0:
		await d.say("Вокзал", "Латунный ключ входит в замок диспетчерской как влитой… но дверь пока не открывается. Что-то подсказывает: время ещё не пришло.")
	elif World.state.notes_found.size() >= 6:
		await d.say("Вокзал", "Дверь диспетчерской заперта. Страницы журнала говорят: ждите на перроне в полночь, когда горят все огни.")
	else:
		await d.say("Вокзал", "Внутри пыльно и тихо. В глубине зала виднеется запертая дверь с табличкой «Диспетчерская».")
	d.end()


# ---------------------------------------------------------------- инструменты

func _use_net() -> void:
	player.model.play_action("swing")
	Sfx.play("swing")
	await get_tree().create_timer(0.22).timeout
	var best: Critter = null
	var bd: float = 2.0
	for c in critters:
		if not is_instance_valid(c):
			continue
		var off: Vector3 = c.global_position - player.global_position
		off.y = 0
		var dist: float = off.length()
		if dist < bd and (dist < 0.6 or off.normalized().dot(player.facing) > 0.1):
			bd = dist
			best = c
	if best == null:
		await get_tree().create_timer(0.25).timeout
		return
	if randf() < 0.8:
		if Game.can_add(best.item_id, 1):
			Game.add_item(best.item_id, 1)
			Sfx.play("pickup")
			player.model.play_action("cheer")
			Game.say_toast("Поймали: %s!" % Data.item_name(best.item_id), "good")
			critters.erase(best)
			best.queue_free()
		else:
			Game.say_toast("Рюкзак полон!", "bad")
	else:
		Game.say_toast("Улетела!", "info")
		best._pick_target()
	await get_tree().create_timer(0.4).timeout


func _spawn_critters(delta: float) -> void:
	_critter_t -= delta
	if _critter_t > 0.0 or critters.size() >= 6:
		return
	_critter_t = _crit_rng.randf_range(2.0, 6.0)
	var table: Array = []
	var weights: Array[float] = []
	var h: float = Clock.hour_float()
	var season: int = Clock.season()
	for id in Data.items:
		var it: Dictionary = Data.items[id]
		if not it.has("bug"):
			continue
		var b: Dictionary = it.bug
		if not (season in b.seasons):
			continue
		if h < float(b.hours[0]) or h >= float(b.hours[1]):
			continue
		if env.weather == Weather.Type.RAIN or env.weather == Weather.Type.SNOW:
			continue
		table.append(id)
		weights.append(float(b.weight))
	if table.is_empty():
		return
	var total: float = 0.0
	for w in weights:
		total += w
	var r: float = _crit_rng.randf() * total
	var pick: String = table[0]
	for i in table.size():
		r -= weights[i]
		if r <= 0.0:
			pick = table[i]
			break
	var ang: float = _crit_rng.randf() * TAU
	var dist: float = _crit_rng.randf_range(5.0, 11.0)
	var pos: Vector3 = player.global_position + Vector3(cos(ang), 0, sin(ang)) * dist
	var c := Vector2i(int(pos.x), int(pos.z))
	if not World.state.is_walkable(c):
		return
	var cr := Critter.new()
	add_child(cr)
	cr.global_position = Vector3(pos.x, World.state.height_at(pos.x, pos.z) + 1.0, pos.z)
	cr.setup(pick, str(Data.items[pick].bug.kind))
	critters.append(cr)


func _update_critters(delta: float) -> void:
	_spawn_critters(delta)
	var i: int = critters.size() - 1
	while i >= 0:
		var c: Critter = critters[i]
		if not is_instance_valid(c):
			critters.remove_at(i)
		elif c.global_position.distance_to(player.global_position) > 24.0:
			c.queue_free()
			critters.remove_at(i)
		i -= 1


func _use_shovel() -> void:
	var c: Vector2i = player.front_cell(1.0)
	var g: int = World.state.get_ground(c)
	var occupied: bool = World.state.occ[WorldState.idx(c)] != 0 if WorldState.in_bounds(c) else true
	if g != WorldState.Ground.GRASS and g != WorldState.Ground.SAND and g != WorldState.Ground.PATH:
		Game.say_toast("Здесь копать нельзя.", "info")
		Sfx.play("nope")
		return
	if occupied:
		var o: Dictionary = World.state.object_at(c)
		if not o.is_empty() and o.id == "hole":
			Game.say_toast("Здесь уже вскопано.", "info")
		else:
			Game.say_toast("Что-то мешает копать.", "info")
		Sfx.play("nope")
		return
	player.face_toward(World.cell_center(c))
	player.model.play_action("dig")
	Sfx.play("dig")
	await get_tree().create_timer(0.5).timeout
	Sfx.play("dig")
	await get_tree().create_timer(0.35).timeout
	World.apply({"t": "place", "id": "hole", "cell": c})
	cam.shake = 0.25
	# страница журнала?
	var next_note: Dictionary = _next_note()
	if not next_note.is_empty() and Vector2i(int(next_note.cell[0]), int(next_note.cell[1])) == c:
		await _find_note(next_note)
		return
	# рядом с блеском (±1) — «тепло»
	var r: float = randf()
	if r < 0.30:
		var amt: int = randi_range(30, 120)
		Game.add_money(amt)
		Game.say_toast("В земле нашлось %d пуговиц!" % amt, "good")
	elif r < 0.45:
		var seeds: Array[String] = ["seed_tulip", "seed_cornflower", "seed_aster"]
		var sid: String = seeds[randi() % seeds.size()]
		if Game.add_item(sid, 1):
			Sfx.play("pickup")
			_item_toast(sid)
	elif r < 0.52:
		if Game.add_item("boot", 1):
			Game.say_toast("Старый сапог. Кто его тут закопал?", "info")
	else:
		Game.say_toast("Только земля. Зато мягкая!", "info")


func _next_note() -> Dictionary:
	var n: int = World.state.notes_found.size()
	if n >= Data.notes.size():
		return {}
	return Data.notes[n]


func _update_glint() -> void:
	if glint and is_instance_valid(glint):
		glint.queue_free()
		glint = null
	var n: Dictionary = _next_note()
	if n.is_empty():
		return
	glint = Glint.new()
	add_child(glint)
	var c := Vector2i(int(n.cell[0]), int(n.cell[1]))
	glint.global_position = World.cell_center(c) + Vector3(0, 0.08, 0)


func _find_note(n: Dictionary) -> void:
	var d: DialogueUI = hud.dialogue
	Sfx.play("chime")
	player.model.play_action("cheer")
	World.state.notes_found.append(n.id)
	_update_glint()
	hud.banner("Страница журнала %d/%d" % [World.state.notes_found.size(), Data.notes.size()], 2.0)
	await get_tree().create_timer(0.8).timeout
	await d.say("Журнал Лидии", "[i]В земле лежит промасленный свёрток. Внутри — страница, исписанная ровным почерком.[/i]", 0.7)
	await d.say(str(n.title), str(n.text), 0.8)
	if World.state.notes_found.size() == Data.notes.size():
		await d.say("Вы", "Это была последняя страница. «Жди на перроне в полночь, когда горят все огни…» Значит, нужны фонари и часы.", 1.0)
	d.end()
	Game.save_game()


func _use_rod() -> void:
	var water: Vector3 = _water_ahead()
	if water == Vector3.INF:
		Game.say_toast("Подойдите к воде и повернитесь к ней лицом.", "info")
		Sfx.play("nope")
		return
	player.face_toward(water)
	player.model.play_action("cast")
	Sfx.play("cast")
	await get_tree().create_timer(0.35).timeout
	Sfx.play("splash")
	var bobber := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = Mats.unlit(Color(0.95, 0.3, 0.28, 1.0))
	bobber.mesh = sm
	add_child(bobber)
	bobber.global_position = Vector3(water.x, -0.12, water.z)
	var t0: float = 0.0
	var wait: float = randf_range(2.0, 5.5)
	_act_flag = false
	var cancelled: bool = false
	while t0 < wait:
		await get_tree().process_frame
		t0 += get_process_delta_time()
		bobber.position.y = -0.12 + sin(t0 * 3.0) * 0.015
		if _act_flag:
			cancelled = true
			break
	if cancelled:
		Game.say_toast("Слишком рано — рыба испугалась.", "info")
		bobber.queue_free()
		player.model.play_action("rest")
		return
	# поклёвка!
	Sfx.play("bite")
	var mark := Label3D.new()
	mark.text = "!"
	mark.font_size = 120
	mark.pixel_size = 0.01
	mark.modulate = Color(1, 0.4, 0.3)
	mark.outline_size = 16
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	add_child(mark)
	mark.global_position = player.global_position + Vector3(0, 2.0, 0)
	var win: float = 0.0
	var hit: bool = false
	_act_flag = false
	while win < 1.2:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		win += dt
		bobber.position.y = -0.2 + sin(win * 30.0) * 0.04
		if _act_flag:
			hit = true
			break
	mark.queue_free()
	bobber.queue_free()
	if not hit:
		Game.say_toast("Сорвалось…", "bad")
		player.model.play_action("rest")
		return
	player.model.play_action("swing")
	Sfx.play("splash")
	var fish: String = _roll_fish()
	await get_tree().create_timer(0.35).timeout
	if Game.add_item(fish, 1):
		Sfx.play("fanfare" if Data.item(fish).price >= 450 else "pickup")
		player.model.play_action("cheer")
		var d: Dictionary = Data.item(fish)
		Game.say_toast("Поймали: %s!" % d.name, "good")
		if int(d.get("price", 0)) >= 1000:
			hud.banner("Золотая рыбка!", 2.2)
	else:
		Game.say_toast("Рюкзак полон — рыба уплыла.", "bad")


func _roll_fish() -> String:
	var h: float = Clock.hour_float()
	var season: int = Clock.season()
	var table: Array = []
	var weights: Array[float] = []
	for id in Data.items:
		var it: Dictionary = Data.items[id]
		if not it.has("fish"):
			continue
		var f: Dictionary = it.fish
		if not (season in f.seasons):
			continue
		if h < float(f.hours[0]) or h >= float(f.hours[1]):
			continue
		table.append(id)
		weights.append(float(f.weight))
	if table.is_empty():
		return "boot"
	var total: float = 0.0
	for w in weights:
		total += w
	var r: float = randf() * total
	for i in table.size():
		r -= weights[i]
		if r <= 0.0:
			return table[i]
	return table[0]


# ---------------------------------------------------------------- рюкзак → использовать

func _use_bag_item(id: String) -> void:
	var d: Dictionary = Data.item(id)
	var plant: String = str(d.get("plant", ""))
	if plant != "":
		_busy = true
		player.busy = true
		await _plant(id, plant)
		_busy = false
		player.busy = false
	elif str(d.get("category", "")) == "fruit":
		if Game.remove_item(id, 1):
			Sfx.play("pickup")
			Game.say_toast("Вкусно! %s съедено." % d.name, "good")
			player.model.play_action("cheer")


func _plant(item_id: String, obj_id: String) -> void:
	var c: Vector2i = player.front_cell(1.0)
	if World.state.get_ground(c) != WorldState.Ground.GRASS or not World.state.can_place(obj_id, c):
		Game.say_toast("Сюда не посадить. Нужна свободная трава.", "bad")
		Sfx.play("nope")
		return
	player.face_toward(World.cell_center(c))
	player.model.play_action("dig")
	Sfx.play("dig")
	await get_tree().create_timer(0.5).timeout
	if Game.remove_item(item_id, 1):
		var st: Dictionary = {"age": 0} if obj_id.begins_with("sapling_") else {"planted": true}
		World.apply({"t": "place", "id": obj_id, "cell": c, "st": st})
		Sfx.play("pickup")
		Game.say_toast("Посажено! Не забудьте вернуться.", "good")


# ---------------------------------------------------------------- проекты и жители

func _on_project_done(id: String) -> void:
	var p: Dictionary = Data.project(id)
	Sfx.play("fanfare")
	if hud:
		hud.banner("Готово: " + str(p.get("name", id)), 3.0)
		Game.say_toast(str(p.get("done_text", "")), "good")
	_update_glint()
	Game.save_game()


func _on_villager_arrived(vid: String) -> void:
	var v: Dictionary = Data.villager(vid)
	if v.is_empty() or villagers.has(vid):
		return
	var n: Villager = _add_villager(v)
	n.global_position = World.cell_center(Vector2i(34, 9))
	Game.say_toast("На станцию приехал(а) новый житель: %s!" % str(v.name), "good")


func _befriend(vid: String, amount: int) -> void:
	var st: Dictionary = World.state.villagers.get(vid, {})
	if st.is_empty():
		return
	st.friend = mini(int(st.get("friend", 0)) + amount, 100)


func _talk(v: Villager) -> void:
	var d: DialogueUI = hud.dialogue
	var vid: String = v.vid
	var vd: Dictionary = v.data
	var st: Dictionary = World.state.villagers[vid]
	var pitch: float = {"moss": 0.7, "fluff": 1.3, "soot": 1.5, "reed": 1.1, "felt": 0.9}.get(str(vd.species), 1.0)
	v.start_talk(player)
	player.face_toward(v.global_position)
	cam.zoom_target = 6.8
	var first: bool = int(st.get("friend", 0)) <= 0
	var nm: String = str(vd.name)
	if first:
		st.friend = 1
		await d.say(nm, "Здравствуйте! Я %s. Вы — наш новый смотритель? %s" % [nm, _intro_line(vid)], pitch)
	else:
		await d.say(nm, _greeting(vd), pitch)
	if int(st.get("talked_day", -1)) != Clock.day_index():
		st.talked_day = Clock.day_index()
		_befriend(vid, 3)
	while true:
		var opts: Array = ["Поболтать", "Расспросить о станции", "Есть просьба?", "Подарить что-нибудь", "До встречи"]
		var r: int = await d.choose(nm, "Чем могу помочь?", opts, pitch)
		if r == 0:
			await d.say(nm, _chat_line(vd), pitch)
		elif r == 1:
			await d.say(nm, _rumor_line(vd, st), pitch)
		elif r == 2:
			await _request(vd, st, pitch)
		elif r == 3:
			await _gift(vd, st, pitch)
		else:
			await d.say(nm, _bye_line(str(vd.personality)), pitch)
			break
	d.end()
	v.end_talk()
	cam.zoom_target = 9.5
	Game.save_game()


func _intro_line(vid: String) -> String:
	match vid:
		"barkhat": return "Не обращайте внимания на ворчание. Я просто рад, что кто-то приехал."
		"pukh": return "Ура-ура! Давно у нас никто не выходил на перрон!"
		"ugolek": return "Я Уголёк, а вы чего такой серьёзный? Расслабьтесь!"
		"trostinka": return "Добро пожаловать… я слышала, как вы подходите. Мне нравится, как вы ходите."
		_: return "Рада вас видеть. Проходите, не стесняйтесь."


func _greeting(vd: Dictionary) -> String:
	var g: Array = ["Ага, это снова вы!", "О, смотритель!", "Рад вас видеть.", "Как поживаете?"]
	if str(vd.personality) == "болтушка":
		g = ["Привет-привет-привет!", "Вы вернулись! Я так скучал! Пять минут!"]
	return g[randi() % g.size()]


func _bye_line(personality: String) -> String:
	match personality:
		"ворчун": return "Идите уже. И… заходите ещё."
		"болтушка": return "Пока-пока! Ой, я ещё хотел рассказать… ну ладно, потом!"
		"сорванец": return "Бывай! Только не ходи по ночам одна… один… в общем, осторожно!"
		"мечтательница": return "До встречи. Цветам понравился наш разговор."
		_: return "Заходите ещё. Чай всегда горячий."


func _chat_line(vd: Dictionary) -> String:
	var chat: Dictionary = vd.chat
	var pool: Array = []
	match env.weather:
		Weather.Type.RAIN: pool = chat.get("rain", [])
		Weather.Type.SNOW: pool = chat.get("snow", [])
		Weather.Type.FOG: pool = chat.get("fog", [])
		Weather.Type.CLEAR: pool = chat.get("clear", [])
	if Clock.is_night() and randf() < 0.6:
		pool = chat.get("night", pool)
	elif Clock.hour() < 10 and randf() < 0.4:
		pool = chat.get("morning", pool)
	if pool.is_empty() or randf() < 0.45:
		pool = chat.get("generic", ["…"])
	return str(pool[randi() % pool.size()])


func _rumor_line(vd: Dictionary, st: Dictionary) -> String:
	var rumors: Array = vd.get("rumors", [])
	if rumors.is_empty():
		return "Про станцию? Ничего особенного не знаю."
	var i: int = int(st.get("rumor", 0))
	st["rumor"] = i + 1
	return str(rumors[i % rumors.size()])


func _request(vd: Dictionary, st: Dictionary, pitch: float) -> void:
	var d: DialogueUI = hud.dialogue
	var nm: String = str(vd.name)
	var rq: Dictionary = vd.get("request", {})
	if rq.is_empty():
		await d.say(nm, "Сегодня у меня нет просьб. Просто будьте рядом.", pitch)
		return
	var state: int = int(st.get("request", 0))
	var item: String = str(rq.item)
	if state == 2:
		await d.say(nm, "Спасибо за помощь, я всё помню!", pitch)
	elif state == 0:
		st.request = 1
		await d.say(nm, str(rq.text), pitch)
	else:
		if Game.item_count(item) > 0:
			var r: int = await d.choose(nm, "Это ведь то, что я просил(а)? (%s)" % Data.item_name(item), ["Отдать: " + Data.item_name(item), "Пока оставлю"], pitch)
			if r == 0:
				Game.remove_item(item, 1)
				st.request = 2
				Game.add_money(int(rq.reward))
				_befriend(str(vd.id), 15)
				Sfx.play("fanfare")
				await d.say(nm, str(rq.thanks), pitch)
				Game.say_toast("Награда: %d пуговиц" % int(rq.reward), "good")
		else:
			await d.say(nm, "Всё ещё жду: %s. %s" % [Data.item_name(item), "Загляните, когда найдёте!"], pitch)


func _gift(vd: Dictionary, st: Dictionary, pitch: float) -> void:
	var d: DialogueUI = hud.dialogue
	var nm: String = str(vd.name)
	var ids: Array = []
	for s in Game.profile.items:
		var cat: String = str(Data.item(str(s.id)).get("category", ""))
		if cat in ["tool", "key", "currency"]:
			continue
		if not ids.has(str(s.id)):
			ids.append(str(s.id))
	if ids.is_empty():
		await d.say(nm, "У вас в рюкзаке пусто. Это ничего! Главное — внимание.", pitch)
		return
	var names: Array = []
	for id in ids.slice(0, 5):
		names.append(Data.item_name(str(id)))
	names.append("Передумал")
	var r: int = await d.choose(nm, "Что подарите?", names, pitch)
	if r >= names.size() - 1 or r >= ids.size():
		return
	var gid: String = str(ids[r])
	Game.remove_item(gid, 1)
	var liked: bool = (vd.get("likes", []) as Array).has(gid)
	_befriend(str(vd.id), 10 if liked else 4)
	Sfx.play("pickup")
	if liked:
		await d.say(nm, "Ох! Это же моё любимое! Вы меня балуете!", pitch)
	else:
		await d.say(nm, "Спасибо! %s — как мило с вашей стороны." % Data.item_name(gid), pitch)


# ---------------------------------------------------------------- кат-сцены

func _arrival_cutscene() -> void:
	_cutscene = true
	hud.set_visible_hud(false)
	var d: DialogueUI = hud.dialogue
	player.visible = false
	var door_x: float = 39.4
	train = Train.new()
	add_child(train)
	train.position = Vector3(door_x - 0.7 - 70.0, 0.0, 7.0)
	train.position.y = 0.12
	# жители ждут на перроне
	var spots: Dictionary = {"barkhat": Vector2i(43, 9), "pukh": Vector2i(45, 10), "ugolek": Vector2i(41, 10)}
	for vid in spots.keys():
		if villagers.has(vid):
			var v: Villager = villagers[vid]
			v.scripted = true
			v.global_position = World.cell_center(spots[vid])
			v.rotation.y = PI * 0.5
	cam.free_look = true
	cam.global_position = Vector3(36.0, 1.4, 8.2)
	cam.yaw = PI * 0.36
	cam.zoom_target = 13.0
	cam.distance = 13.0
	cam.pitch_deg = 16.0
	await Game.fade_in(0.8)
	Sfx.play("horn")
	var tw := create_tween()
	tw.tween_property(train, "position:x", door_x - 0.7, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	await get_tree().create_timer(0.8).timeout
	# вышли пассажир и проводница
	player.visible = true
	player.global_position = Vector3(door_x, 0.1, 8.3)
	player.facing = Vector3(0, 0, 1)
	var fetra := VillagerModel.new()
	add_child(fetra)
	fetra.build("felt", Color(0.72, 0.60, 0.70))
	fetra.global_position = Vector3(door_x + 1.3, 0.1, 8.4)
	fetra.rotation.y = PI * 0.5
	var ptw := create_tween()
	ptw.tween_property(player, "global_position", Vector3(door_x - 0.2, World.state.height_at(door_x, 9.5), 9.5), 1.2)
	await ptw.finished
	player.model.play_action("wave")
	cam.global_position = Vector3(41.0, 1.0, 9.4)
	cam.pitch_deg = 18.0
	cam.zoom_target = 8.5
	cam.yaw = PI * 0.3
	await d.say("Фетра", "Тихая Заводь, конечная. Выходите, смотритель, и не споткнитесь о тишину — она тут повсюду.", 0.9)
	await d.say("Фетра", "Рельсы дальше не идут. Раньше тут было людно, а теперь… сами увидите.", 0.9)
	var nm: String = World.state.town_name
	await d.say("Фетра", "Табличка на перроне давно стёрлась, но по бумагам это — «%s». Вам и решать, что с ней делать." % nm, 0.9)
	if villagers.has("barkhat"):
		var b: Villager = villagers["barkhat"]
		b.model.bounce()
		await d.say("Бархат", "Хм. Новенький. Ну, наконец-то! Я уж думал, поезда сюда ходят только по привычке.", 0.7)
		await d.say("Бархат", "Я Бархат. Бывший носильщик. Если что-то не работает — я знаю, как оно не работало раньше.", 0.7)
	if villagers.has("pukh"):
		var p: Villager = villagers["pukh"]
		p.model.bounce()
		await d.say("Пух", "Ура-ура-ура! Настоящий смотритель! Я — Пух! Мы тут все — Ворсинки. Жили в стенах и под перроном, пока было тихо.", 1.3)
	if villagers.has("ugolek"):
		var u: Villager = villagers["ugolek"]
		u.model.bounce()
		await d.say("Уголёк", "А я Уголёк. Слушайте… по ночам под перроном что-то стучит. Не бойтесь! Ну… почти не бойтесь.", 1.5)
	await d.say("Фетра", "Станцию без смотрителя поезд обходит стороной. С вас — часы, фонари и Променад. С Заводи — чай и терпение. Договорились?", 0.9)
	var r: int = await d.choose("Фетра", "Договорились?", ["Договорились!", "Попробую."], 0.9)
	await d.say("Фетра", "Вот и славно. Держите кепку, лопату, удочку и сачок. Совет: Бархата не перебивайте, Пуха слушайте вполуха, Уголька проверяйте.", 0.9)
	# даём стартовый набор
	Game.say_toast("Получено: Сачок, Удочка, Лопата и 500 пуговиц", "good")
	Sfx.play("fanfare")
	d.end()
	# поезд уезжает
	Sfx.play("horn")
	var out := create_tween()
	out.tween_property(fetra, "global_position:x", door_x + 0.7, 0.8)
	await out.finished
	fetra.queue_free()
	var go := create_tween()
	go.tween_property(train, "position:x", door_x + 90.0, 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	cam.free_look = false
	cam.pitch_deg = 36.0
	cam.zoom_target = 9.5
	cam.yaw = PI
	cam.snap()
	for vid in spots.keys():
		if villagers.has(vid):
			(villagers[vid] as Villager).scripted = false
	World.state.flags.erase("arrival_pending")
	_cutscene = false
	hud.set_visible_hud(true)
	hud.banner(nm, 2.5)
	if DialogueUI.test_mode:
		print("[smoke] прибытие завершено, игрок управляет: ", not _cutscene)
	await go.finished
	train.queue_free()
	train = null
	Game.save_game()


func _check_finale() -> void:
	if _finale_running or World.flag("finale_done") or _cutscene:
		return
	if World.state.notes_found.size() < Data.notes.size():
		return
	if World.project_state("lamps") != 3 or World.project_state("clock") != 3:
		return
	var h: int = Clock.hour()
	if h != 0:
		return
	var c: Vector2i = player.cell()
	if c.y < 8 or c.y > 10 or c.x < 28 or c.x > 52:
		return
	_finale()


func _finale() -> void:
	_finale_running = true
	_cutscene = true
	var d: DialogueUI = hud.dialogue
	hud.set_prompt("")
	Sfx.play("chime")
	await get_tree().create_timer(1.0).timeout
	Sfx.play("horn")
	train = Train.new()
	add_child(train)
	train.position = Vector3(40.7 - 70.0, 0.12, 7.0)
	var tw := create_tween()
	tw.tween_property(train, "position:x", 40.7, 8.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	cam.zoom_target = 12.0
	cam.pitch_deg = 22.0
	await tw.finished
	await get_tree().create_timer(1.2).timeout
	for i in 3:
		Sfx.play("bell", 0.8 + float(i) * 0.25)
		await get_tree().create_timer(0.7).timeout
	await d.say("Станция", "Двери вагона медленно открываются. Внутри тихо горит свет, но никого нет. На сиденье лежит латунный ключ и записка.", 0.6)
	await d.say("Записка", "«Станция снова жива. Спасибо. Ключ — от диспетчерской. Я оставила там то, что должно остаться здесь. До скорой встречи на конечной. — Л. В.»", 0.8)
	Game.add_item("key_dispatch", 1)
	Sfx.play("fanfare")
	Game.say_toast("Получено: Ключ от диспетчерской", "good")
	await d.say("Вы", "Поезд мягко гудит и трогается, увозя тишину с собой. Диспетчерская… Но это уже другая история.", 1.0)
	d.end()
	hud.banner("Продолжение следует…", 3.5)
	World.state.flags["finale_done"] = true
	var go := create_tween()
	go.tween_property(train, "position:x", 40.7 + 90.0, 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	cam.zoom_target = 9.5
	cam.pitch_deg = 36.0
	_cutscene = false
	await go.finished
	train.queue_free()
	train = null
	Game.save_game()
