extends Node
## Запуск: godot --headless --path . res://tools/modes_test.tscn
## Проверяет город (прогулка, рентген кафе, смена, меню), время суток и режим украшения (логика без отрисовки).
## ВНИМАНИЕ: перезаписывает user://save.json — запускайте на тестовых данных.

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("MODES FAIL: " + msg)
		_failed = true


func _ready() -> void:
	TimeOfDay.set_process(false)   # время стоит, пока тест сам его не двигает
	Weather.set_process(false)     # погода тоже стоит: ясно, пока тест её не включит
	Weather.force(Weather.Kind.CLEAR)
	_test_texts_fit()
	_test_time_of_day()
	await _test_default_layout()
	await _test_place_rules()
	await _test_level_scene()
	await _test_ground_tiles()
	await _test_world_nav()
	await _test_cat_directions()
	await _test_city()
	await _test_npc_visits()
	await _test_traffic()
	await _test_city_input()
	await _test_progress_and_menu()
	await _test_brew()
	await _test_intro()
	await _test_decorate_logic()
	await _test_decorate_input()
	_test_save_migration()
	_test_assets()
	await _test_pixel_lighting()
	await _test_brew_grid()
	await _test_weather()
	await _test_spaces()
	if _failed:
		get_tree().quit(1)
		return
	print("MODES PASS")
	get_tree().quit(0)


func _room_with(items: Array[Dictionary]) -> CafeRoom:
	var room := CafeRoom.new()
	add_child(room)
	room.set_layout(items)
	return room


func _item(id: String, c: int, r: int) -> Dictionary:
	return {"id": id, "c": c, "r": r, "flip": false}


func _new_city(inside: bool) -> Node2D:
	GameState.intro_stage = GameState.INTRO_DONE   # интро уже пройдено: проверяем обычную игру
	GameState.city_inside = inside
	GameState.layout = Data.default_layout.duplicate(true)
	var city: Node2D = load(Nav.CITY).instantiate()
	add_child(city)
	return city


## Подписи не должны вылезать за карточки и кнопки (шрифт — пиксельный, ширина фиксирована).
func _test_texts_fit() -> void:
	for id in Data.furniture:
		var w := Ui.FONT_NARROW.get_string_size(String(Data.furniture[id]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
		_check(w <= 90.0, "название «%s» не влезает в карточку (%s px)" % [Data.furniture[id]["name"], w])
	var limits := {"Зеркало": 116.0, "Убрать": 108.0, "Готово": 116.0}
	for t in limits:
		var w2 := Ui.FONT_NARROW.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
		_check(w2 + 36.0 + 8.0 <= float(limits[t]), "«%s» не влезает в кнопку панели (%s px)" % [t, w2])
	var font := (load("res://assets/ui/theme.tres") as Theme).default_font
	var button_w := {"Продолжить": 252.0, "Украшение": 252.0, "Улучшения": 252.0, "Настройки": 252.0, "Аккаунт": 252.0, "Назад": 252.0,
		"Отмена": 252.0, "Сбросить": 252.0, "Выход": 252.0, "Смена": 184.0}
	for t in button_w:
		var w3 := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
		_check(w3 + 36.0 + 16.0 <= float(button_w[t]), "«%s» не влезает в кнопку (%s px)" % [t, w3])
	var narrow_w := Ui.FONT_NARROW.get_string_size("Сбросить прогресс", HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
	_check(narrow_w + 36.0 + 16.0 <= 252.0, "«Сбросить прогресс» не влезает в кнопку (%s px)" % narrow_w)
	for ch in "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя":
		_check(font.has_char(ch.unicode_at(0)) and Ui.FONT_NARROW.has_char(ch.unicode_at(0)), "в шрифте нет буквы " + ch)


func _test_time_of_day() -> void:
	TimeOfDay.hour = 12.0
	_check(TimeOfDay.night() == 0.0 and TimeOfDay.ambient().v > 0.95, "в полдень светло")
	_check(TimeOfDay.sun_progress() > 0.0 and TimeOfDay.moon_progress() < 0.0, "в полдень светит солнце")
	TimeOfDay.hour = 23.0
	_check(TimeOfDay.night() > 0.95, "в 23:00 ночь")
	_check(TimeOfDay.ambient().b > TimeOfDay.ambient().r and TimeOfDay.ambient().v < 0.7, "ночной свет тёмный и синий")
	_check(TimeOfDay.moon_progress() >= 0.0 and TimeOfDay.sun_progress() < 0.0, "ночью светит луна")
	TimeOfDay.hour = 2.0
	_check(TimeOfDay.moon_progress() >= 0.0 and TimeOfDay.night() > 0.95, "в 02:00 ночь и луна (переход через полночь)")
	TimeOfDay.hour = 19.0
	_check(TimeOfDay.indoor().v > TimeOfDay.ambient().v, "внутри светлее, чем на закате снаружи")
	TimeOfDay.hour = 23.5
	TimeOfDay.skip(1.0)
	_check(is_equal_approx(TimeOfDay.hour, 0.5), "сутки замыкаются: 23:30 + 1 ч = 00:30")
	TimeOfDay.hour = 9.75
	_check(TimeOfDay.clock_text() == "09:40", "формат часов (%s)" % TimeOfDay.clock_text())
	for h in range(0, 24):   # плавность: соседние часы не отличаются скачком
		TimeOfDay.hour = float(h)
		var a := TimeOfDay.ambient()
		TimeOfDay.hour = float(h) + 1.0
		var b := TimeOfDay.ambient()
		_check(absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.9, "резкий скачок света между %d и %d часами" % [h, h + 1])
	TimeOfDay.hour = 12.0


func _test_default_layout() -> void:
	var items: Array[Dictionary] = Data.default_layout.duplicate(true)
	var room := _room_with([])
	for it in items:
		var err := room.check_place(String(it["id"]), int(it["c"]), int(it["r"]))
		_check(err == "", "расстановка по умолчанию: %s -> %s" % [it["id"], err])
		room.layout.append(it)
	room.rebuild()
	var path := room.find_path(CafeRoom.feet_at(CafeRoom.SPAWN_CELL), CafeRoom.feet_at(Vector2i(1, 0)))
	_check(not path.is_empty(), "от двери до стойки есть путь")
	room.queue_free()
	await get_tree().process_frame


func _test_grid_alignment() -> void:
	# каждый предмет стоит ровно по клеткам: низ спрайта = низ клеток, центр по ширине = центр клеток
	for id in Data.furniture:
		var area := CafeRoom.cells(String(id), 2, 1)
		var rect := CafeRoom.sprite_rect(String(id), 2, 1)
		var top := CafeRoom.cell_pos(2, 1, CafeRoom.is_wall(String(id)))
		var foot_x := top.x + area.size.x * CafeRoom.T / 2.0
		_check(absf(rect.get_center().x - foot_x) <= CafeRoom.S, "%s: центр спрайта уехал от центра клеток больше чем на пиксель арта" % id)
		if not CafeRoom.is_flat(String(id)):
			_check(is_equal_approx(rect.end.y, top.y + area.size.y * CafeRoom.T), "%s: низ спрайта не по низу клеток" % id)
		_check(rect.size.x <= area.size.x * CafeRoom.T and fmod(rect.position.x, 2.0) == 0.0, "%s: спрайт шире клеток или сдвинут на пол-пикселя арта" % id)


func _test_place_rules() -> void:
	_test_grid_alignment()
	var room := _room_with(Data.default_layout.duplicate(true))
	_check(room.check_place("stool", 7, 2) != "", "нельзя поставить пуф в стол")
	_check(room.check_place("plant", 1, 2) == "", "растение в свободной клетке можно")
	_check(room.check_place("plant", 10, 2) != "", "за краем зала нельзя")
	_check(room.check_place("plant", 1, 0) != "", "у стойки ставить нельзя")
	_check(room.check_place("plant", 4, 5) != "", "у входа ставить нельзя")
	_check(room.check_place("plant", 1, 6) != "", "в переднем ряду (витрина) ставить нельзя")
	_check(room.check_place("window", 0, 1) != "", "окно поверх стойки нельзя")
	_check(room.check_place("window", 6, 1) != "", "окно на окно нельзя")
	_check(room.check_place("window", 4, 0) == "", "окно на свободной стене можно")
	_check(room.check_place("window", 4, 3) != "", "за нижним краем стены нельзя")
	_check(room.check_place("rug", 3, 2) == "", "коврик можно под стол (плоский)")
	# ряд мебели поперёк зала: последний предмет закрыл бы проход — должен быть отклонён именно по этой причине
	var row: Array[Dictionary] = []
	for c in [1, 3, 5]:
		row.append(_item("cabinet", c, 4))
	row.append(_item("machine", 7, 4))
	row.append(_item("machine", 8, 4))
	var sealed := _room_with(row)
	_check(not sealed.find_path(CafeRoom.feet_at(CafeRoom.SPAWN_CELL), CafeRoom.feet_at(Vector2i(1, 0))).is_empty(), "с зазором в ряду проход есть")
	_check(sealed.check_place("machine", 0, 4) == tr("Не загораживайте проход"), "последний предмет, закрывающий проход, отклонён")
	sealed.queue_free()
	var spot := room.find_free_spot("table_big")
	_check(spot.x >= 0 and room.check_place("table_big", spot.x, spot.y) == "", "find_free_spot находит место")
	room.queue_free()
	await get_tree().process_frame


func _walk(cat: CatWalker, steps := 800) -> void:
	for _i in steps:
		cat.step(0.05)


func _screen_of(city: Node2D, world_pos: Vector2) -> Vector2:
	return (city._world as Node2D).get_global_transform_with_canvas() * world_pos


func _click(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e, true)


func _move_to(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e, true)


## Редактируемый уровень: зоны, здания, предметы, земля на месте и согласованы с сеткой.
func _test_level_scene() -> void:
	var level := (load("res://scenes/street.tscn") as PackedScene).instantiate() as StreetLevel
	add_child(level)
	for kind in [StreetZone.Kind.WALK, StreetZone.Kind.LANE_EAST, StreetZone.Kind.LANE_WEST, StreetZone.Kind.CAFE_INTERIOR]:
		_check(level.zones(kind).size() >= 1, "в уровне нет зоны вида %d" % kind)
	_check(level.zones(StreetZone.Kind.WALK).size() >= 10, "есть тротуар, задний двор и проходы между домами")
	var interior := level.zones(StreetZone.Kind.CAFE_INTERIOR)[0]
	_check(is_zero_approx(fposmod(interior.position.x, 32.0)) and is_zero_approx(fposmod(interior.position.y + CafeRoom.ORIGIN.y, 32.0)), "пол кафе лежит в сетке мира 32 px")
	_check(interior.size.is_equal_approx(CafeRoom.ROOM_SIZE), "зона интерьера 320×320")
	_check(interior._get_configuration_warnings().is_empty(), "у зоны интерьера нет предупреждений редактора")
	var cafes := 0
	var rects: Array[Rect2] = []
	for b in level.get_node("Buildings").get_children():
		rects.append((b as StreetBuilding).world_rect())
		if (b as StreetBuilding).is_cafe:
			cafes += 1
			var rect := (b as StreetBuilding).world_rect()
			_check(rect.grow(12).encloses(Rect2(interior.position, interior.size)), "интерьер вписан в габарит фасада кафе")
			_check(is_equal_approx(rect.end.y, interior.position.y + 320.0), "низ интерьера на линии низа фасада")
	_check(cafes == 1, "в уровне ровно одно кафе")
	rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	for i in range(1, rects.size()):   # между домами проходы не уже трёх клеток: кот 32 px должен пройти
		_check(rects[i].position.x - rects[i - 1].end.x >= 96.0, "проход между домами %d и %d уже 96 px" % [i - 1, i])
	_check(level.world_size.x >= 2400.0 and level.world_size.y >= 900.0, "улица расширена: есть задний двор и длинная улица")
	# полосы: верхняя (на запад) выше нижней, и машины любой модели в них не пересекаются по высоте
	var west := level.zones(StreetZone.Kind.LANE_WEST)[0]
	var east := level.zones(StreetZone.Kind.LANE_EAST)[0]
	_check(west.world_rect().end.y < east.world_rect().position.y + 8.0, "полосы не накладываются")
	for v in Data.street["vehicles"]:
		_check(float(v["frame"][1]) * 2.0 <= 90.0, "машина %s выше полосы" % v["id"])
	level.queue_free()
	await get_tree().process_frame


## Земля — тайлы: слой Ground с тайлсетом; зебра повёрнута вдоль движения и без другой разметки под ней.
func _test_ground_tiles() -> void:
	var level := (load("res://scenes/street.tscn") as PackedScene).instantiate() as StreetLevel
	add_child(level)
	var ground := level.get_node("Ground") as TileMapLayer
	_check(ground != null and ground.tile_set != null and ground.get_used_cells().size() > 1500, "земля нарисована тайлами (слой Ground)")
	_check(ground.scale == Vector2(2, 2) and ground.tile_set.tile_size == Vector2i(16, 16), "клетка земли 16 px арта = 32 px мира")
	var zebra := Vector2i(4, 1)
	var dash := Vector2i(3, 1)
	for x in [34, 35, 36]:
		for y in range(25, 30):
			_check(ground.get_cell_atlas_coords(Vector2i(x, y)) == zebra, "в клетке (%d,%d) перехода не зебра" % [x, y])
	var dashes_in_crosswalk := 0
	for y in range(25, 30):
		for x in [34, 35, 36]:
			if ground.get_cell_atlas_coords(Vector2i(x, y)) == dash:
				dashes_in_crosswalk += 1
	_check(dashes_in_crosswalk == 0, "под зеброй нет разделительной разметки")
	_check(ground.get_cell_atlas_coords(Vector2i(30, 27)) == dash or ground.get_cell_atlas_coords(Vector2i(31, 27)) == dash, "вне перехода разделительная есть")
	# рисунок зебры: полосы идут вдоль движения (по x), а чередуются по y
	var img := (load("res://assets/street/tiles/street_tiles.png") as Texture2D).get_image()
	var along_x := true
	for y in range(16):
		var first := img.get_pixel(64, 16 + y)
		for x in range(1, 16):
			if img.get_pixel(64 + x, 16 + y) != first:
				along_x = false
	var changes_y := 0
	for y in range(1, 16):
		if img.get_pixel(64, 16 + y) != img.get_pixel(64, 16 + y - 1):
			changes_y += 1
	_check(along_x and changes_y >= 3, "полосы зебры идут вдоль дороги и чередуются поперёк (по x одинаково: %s, смен по y: %d)" % [along_x, changes_y])
	# земля есть на всех зонах ходьбы
	var missing := 0
	for z in level.zones(StreetZone.Kind.WALK):
		var r := (z as StreetZone).world_rect()
		for y in range(int(r.position.y / 32.0), int(r.end.y / 32.0)):
			for x in range(int(r.position.x / 32.0), int(r.end.x / 32.0)):
				if ground.get_cell_source_id(Vector2i(x, y)) < 0:
					missing += 1
	_check(missing == 0, "под зонами ходьбы нет земли в %d клетках" % missing)
	level.queue_free()
	await get_tree().process_frame


## Единая сетка: с улицы в зал и обратно — один путь через проём, без дверей и телепортов; за дома есть проходы.
func _test_world_nav() -> void:
	var city := _new_city(true)
	await get_tree().process_frame
	var nav: WorldNav = city._nav
	var rc := nav.interior_cells().position
	var ex := rc.x + CafeRoom.ENTRANCE_CELLS.position.x       # столбец проёма
	var front := rc.y + CafeRoom.FRONT_ROW                      # ряд витрины
	var inside := Vector2i(ex, rc.y + 3)
	var outside := Vector2i(ex, front + 1)
	_check(nav.is_interior(inside) and not nav.is_interior(outside), "клетки зала и улицы различаются")
	var path := nav.find_path(WorldNav.feet_at(outside), WorldNav.feet_at(inside))
	_check(not path.is_empty(), "путь с улицы в зал есть")
	var crossed_entrance := false
	for p in path:
		var c := WorldNav.cell_of_feet(p)
		if c.y == front:
			_check(c.x == ex or c.x == ex + 1, "путь пересекает витрину не в проёме (клетка %s)" % c)
			crossed_entrance = true
	_check(crossed_entrance, "путь проходит через проём входа")
	var far_cell := Vector2i(60, 23)
	var back := nav.find_path(WorldNav.feet_at(inside), WorldNav.feet_at(far_cell))
	_check(not back.is_empty() and back[back.size() - 1].distance_to(WorldNav.feet_at(far_cell)) < 1.0, "путь из зала на дальний тротуар есть")
	_check(not nav.is_walkable(Vector2i(rc.x, front)) and not nav.is_walkable(Vector2i(rc.x + 9, front)), "витрина кафе не проходима, кроме проёма")
	_check(nav.is_walkable(Vector2i(ex, front)) and nav.is_walkable(Vector2i(ex + 1, front)), "проём входа проходим")
	_check(not nav.is_walkable(Vector2i(10, 26)), "дорога не проходима")
	_check(not nav.is_walkable(rc + Vector2i(3, 2)), "стол в зале закрывает клетку")
	_check(not nav.is_walkable(Vector2i(7, 22)), "торговый автомат закрывает клетку на тротуаре")
	# за дома: задний двор и проходы между зданиями
	var yard := Vector2i(12, 6)
	_check(nav.is_walkable(yard), "задний двор проходим")
	var to_yard := nav.find_path(WorldNav.feet_at(outside), WorldNav.feet_at(yard))
	_check(not to_yard.is_empty() and to_yard[to_yard.size() - 1].distance_to(WorldNav.feet_at(yard)) < 1.0, "с тротуара можно пройти на задний двор")
	var through_alley := false
	for p in to_yard:
		var c := WorldNav.cell_of_feet(p)
		if c.y >= 10 and c.y <= 20:
			through_alley = true
			_check(not nav.is_interior(c), "путь на задний двор не идёт через кафе")
	_check(through_alley, "на задний двор ведёт проход между домами")
	# весь проходимый мир связный: нет «запертых» кусков (предметы по диагонали, узкие проходы)
	var unreachable := 0
	for y in range(0, 30):
		for x in range(0, 82):
			var cell := Vector2i(x, y)
			if nav.is_walkable(cell) and cell != outside and nav.find_path(WorldNav.feet_at(outside), WorldNav.feet_at(cell)).is_empty():
				unreachable += 1
	_check(unreachable == 0, "все проходимые клетки достижимы (недостижимых: %d)" % unreachable)
	var far := nav.find_path(WorldNav.feet_at(outside), WorldNav.feet_at(Vector2i(10, 26)))   # цель на дороге
	_check(not far.is_empty() and nav.is_walkable(WorldNav.cell_of_feet(far[far.size() - 1])), "цель на дороге заменяется ближайшей проходимой клеткой")
	city.queue_free()
	await get_tree().process_frame


## Коты ходят вбок и спиной: свои листы, боковой отражается при движении влево.
func _test_cat_directions() -> void:
	for def in Data.cats:
		var base := String(def["sprite"]).trim_suffix("-front.png")
		for view in ["front", "side", "back"]:
			_check(ResourceLoader.exists("res://assets/cats/%s-%s.png" % [base, view]), "нет листа кота %s-%s" % [base, view])
	var city := _new_city(false)
	await get_tree().process_frame
	city.set_process(false)
	for n in city._npcs:
		n["timer"] = 1000.0
		(n["cat"] as CatWalker).position = WorldNav.feet_at(Vector2i(70, 23))
	var cat: CatWalker = city._player
	cat.position = WorldNav.feet_at(Vector2i(20, 23))
	cat.walk_to(WorldNav.feet_at(Vector2i(24, 23)))
	for _i in 8:
		cat.step(0.05)
	_check(cat.facing == "side" and not cat._sprite.flip_h and cat._sprite.texture == cat._sheets["side"], "вправо: боковой лист без отражения")
	cat.walk_to(WorldNav.feet_at(Vector2i(20, 23)))
	for _i in 8:
		cat.step(0.05)
	_check(cat.facing == "side" and cat._sprite.flip_h, "влево: боковой лист отражён")
	cat.position = WorldNav.feet_at(Vector2i(20, 23))
	cat.walk_to(WorldNav.feet_at(Vector2i(20, 22)))
	for _i in 4:
		cat.step(0.05)
	_check(cat.facing == "back" and not cat._sprite.flip_h and cat._sprite.texture == cat._sheets["back"], "вверх: спиной")
	cat.walk_to(WorldNav.feet_at(Vector2i(20, 23)))
	for _i in 4:
		cat.step(0.05)
	_check(cat.facing == "front" and cat._sprite.texture == cat._sheets["front"], "вниз: лицом")
	# анимация: кадры меняются во время ходьбы
	cat.walk_to(WorldNav.feet_at(Vector2i(30, 23)))
	var frames := {}
	for _i in 40:
		cat.step(0.05)
		frames[int(cat._sprite.region_rect.position.x)] = true
	_check(frames.size() >= 3, "во время ходьбы сменяется несколько кадров (%d)" % frames.size())
	city.queue_free()
	await get_tree().process_frame


func _test_city() -> void:
	var city := _new_city(true)
	await get_tree().process_frame
	var player: CatWalker = city._player
	var nav: WorldNav = city._nav
	var rc := nav.interior_cells().position
	var ex := rc.x + CafeRoom.ENTRANCE_CELLS.position.x
	var front := rc.y + CafeRoom.FRONT_ROW
	var out_cell := Vector2i(ex, front + 1)
	var in_cell := Vector2i(ex, rc.y + 4)
	_check(nav.is_interior(WorldNav.cell_of_feet(player.position)), "игра начинается внутри кафе")
	_check(city.get("_btn_enter") == null and city.get("_btn_exit") == null, "кнопок «Войти/Выйти» нет — дверей нет")
	city._update_xray(10.0)
	city._apply_daylight()
	_check(city._xray > 0.99 and city._room.visible, "внутри круг рентгена раскрыт, виден интерьер")
	_check(is_equal_approx(float(city._hole_mat.get_shader_parameter("radius")), city._iris_r), "радиус круга передан в шейдер фасада")
	_check(city._hole_mat.shader != null and city._clip_mat.shader != null, "у фасада и у мебели есть шейдеры рентгена")
	# выходим сплошным путём: один и тот же узел, без пересадок; круг сжимается плавно
	var parent_before := player.get_parent()
	_check(player.walk_to(WorldNav.feet_at(out_cell)), "путь из кафе на улицу найден")
	var xs: Array[float] = []
	for _i in 600:
		player.step(0.05)
		city._update_xray(0.05)
		xs.append(city._xray)
	_check(player.get_parent() == parent_before and player.get_parent() == city._actors, "кот остался тем же узлом в том же слое (бесшовно)")
	_check(player.position == WorldNav.feet_at(out_cell), "кот вышел на тротуар у проёма")
	var smooth := true
	var mid := false
	for i in range(1, xs.size()):
		if xs[i] > xs[i - 1] + 0.001:
			smooth = false
		if xs[i] > 0.05 and xs[i] < 0.95:
			mid = true
	_check(smooth and mid, "круг рентгена сжимается плавно, через промежуточные радиусы (smooth=%s mid=%s)" % [smooth, mid])
	_check(city._xray < 0.01 and city._iris_r < 0.5, "снаружи круг сжался в точку")
	city._apply_daylight()
	_check(city._room.visible and city._iris_r < 0.5, "зал лежит под фасадом и виден только сквозь окна и дверь: фасад целый")
	# гость в зале при закрытом фасаде не виден; снаружи виден
	var guest: CatWalker = city._npcs[0]["cat"]
	guest.position = WorldNav.feet_at(in_cell)
	var walker: CatWalker = city._npcs[1]["cat"]
	walker.position = WorldNav.feet_at(Vector2i(ex + 6, front + 1))
	_check(not city.is_revealed(guest.position) and city.is_revealed(walker.position), "гость внутри скрыт, пока мы снаружи; прохожий виден")
	# обратно в кафе
	player.walk_to(WorldNav.feet_at(in_cell))
	var up: Array[float] = []
	for _i in 600:
		player.step(0.05)
		city._update_xray(0.05)
		up.append(city._xray)
	_check(player.position == WorldNav.feet_at(in_cell) and city._xray > 0.99, "вошли в кафе: круг раскрылся, интерьер виден")
	var opened := false
	for v in up:
		if v > 0.05 and v < 0.95:
			opened = true
	_check(opened, "круг рентгена расходится не мгновенно, а плавно")
	_check(city.is_revealed(guest.position), "внутри гость виден")
	city._apply_daylight()
	_check(city._room.visible, "внутри интерьер рисуется")
	# стойка -> кнопка смены
	player.walk_to(nav.counter_feet(1))
	_walk(player)
	city._process(0.016)
	_check(city._btn_shift.visible, "у стойки видна кнопка «Смена»")
	player.walk_to(WorldNav.feet_at(rc + Vector2i(8, 3)))
	_walk(player)
	city._process(0.016)
	_check(not city._btn_shift.visible, "вдали от стойки кнопки нет")
	_check(GameState.city_inside, "положение (в кафе) запомнено для возврата из других экранов")
	# мебель: в общем слое сортировки и с материалом обрезки
	var furniture := 0
	for ch in city._actors.get_children():
		if ch.has_meta("interior"):
			furniture += 1
			_check((ch as Node2D).material == (city._clip_mat_up if ch.has_meta("upper") else city._clip_mat), "у мебели кафе есть материал обрезки по кругу")
	_check(furniture >= 3, "мебель из раскладки есть в общем слое (%d)" % furniture)
	_check((guest.material == city._clip_mat) and player.material == null, "гости обрезаются кругом, игрок всегда виден")
	# камера следует по двум осям
	player.position = WorldNav.feet_at(Vector2i(12, 6))
	_check(city._camera_target().y < 400.0, "на заднем дворе камера уезжает вверх")
	player.position = WorldNav.feet_at(out_cell)
	_check(city._camera_target().y > 600.0, "на улице камера внизу")
	player.position = WorldNav.feet_at(in_cell)
	# освещение: ночью улица темнее, окна светятся, внутри светлее
	TimeOfDay.hour = 12.0
	city._apply_daylight()
	var day := city._ground.modulate as Color
	TimeOfDay.hour = 23.0
	city._apply_daylight()
	var night := city._ground.modulate as Color
	_check(night.v < day.v - 0.3, "ночью улица темнее")
	_check(city._room.modulate.v > night.v + 0.2, "ночью в кафе светлее, чем на улице")
	var lit := 0.0
	for g in city._glows:
		lit = maxf(lit, (g["node"] as CanvasItem).modulate.a)
	_check(lit > 0.3, "ночью горят окна, фонари и фары")
	TimeOfDay.hour = 12.0
	city._apply_daylight()
	lit = 0.0
	for g in city._glows:
		lit = maxf(lit, (g["node"] as CanvasItem).modulate.a)
	_check(lit < 0.01, "днём свечение выключено")
	# смена: поверх города, мир скрыт; по окончании возвращаемся
	city._start_shift()
	_check(city._shift_layer != null and not city._world.visible, "смена открылась поверх города")
	var shift: Node2D = city._shift_layer.get_child(0)
	_check(shift.embedded, "смена встроена в город (без смены сцены)")
	var coins_before := GameState.coins
	shift._order = {"drink": "espresso", "pastry": ""}
	shift._awaiting = true
	shift._cup.add("base", "coffee")
	shift._serve()
	_check(GameState.coins > coins_before and shift.shift_served == 1, "в смене заказ обслужен, монеты начислены")
	shift._end_shift()
	await get_tree().process_frame
	_check(city._shift_layer == null and city._world.visible and city._ui.visible, "после смены вернулись в кафе")
	# меню внутри игры
	city._open_menu()
	_check(get_tree().paused and city._menu.visible, "меню ставит игру на паузу")
	city._close_menu()
	_check(not get_tree().paused and not city._menu.visible, "меню закрывается, игра идёт дальше")
	city.queue_free()
	await get_tree().process_frame


## Коты-посетители сами заходят в кафе и выходят: путь только по проходимым клеткам, через проём.
func _test_npc_visits() -> void:
	seed(12345)
	var city := _new_city(false)   # игрок снаружи
	await get_tree().process_frame
	var nav: WorldNav = city._nav
	var front := nav.interior_cells().position.y + CafeRoom.FRONT_ROW
	city.set_process(false)
	var transitions := 0
	var was_inside: Array[bool] = []
	for n in city._npcs:
		was_inside.append(nav.is_interior(WorldNav.cell_of_feet((n["cat"] as CatWalker).position)))
	var bad_cell := false
	for _t in 12000:   # ~20 минут игры
		city._npc_tick(0.1)
		for i in city._npcs.size():
			var cat: CatWalker = city._npcs[i]["cat"]
			cat.step(0.1)
			var c := WorldNav.cell_of_feet(cat.position)
			if not nav.is_walkable(c):
				bad_cell = true
			var inside := nav.is_interior(c)
			if inside != was_inside[i]:
				transitions += 1
				was_inside[i] = inside
				_check(absi(c.y - front) <= 1, "кот пересёк границу зала не в проёме (клетка %s)" % c)
	_check(not bad_cell, "коты ходят только по проходимым клеткам")
	_check(transitions >= 4, "коты заходят в кафе и выходят из него (переходов: %d)" % transitions)
	# а видимость следует за кругом: игрок снаружи -> гости глубоко внутри не видны
	city._update_xray(10.0)
	for n in city._npcs:
		var cat: CatWalker = n["cat"]
		if nav.is_interior(WorldNav.cell_of_feet(cat.position)) and city._depth(cat.position) > 0.9:
			_check(not city.is_revealed(cat.position), "гость глубоко в зале не виден, пока фасад закрыт")
	city.queue_free()
	await get_tree().process_frame


## Машины не наезжают друг на друга: держат дистанцию и тормозят за медленной.
func _test_traffic() -> void:
	seed(7)
	var parent := Node2D.new()
	add_child(parent)
	var tr := Traffic.new()
	add_child(tr)
	var rect := Rect2(0, 444, 1440, 80)
	tr.setup(parent, Data.street["vehicles"], [{"rect": rect, "dir": 1}, {"rect": Rect2(0, 536, 1440, 80), "dir": -1}])
	# медленный ведущий и быстрый ведомый вплотную
	var lane: Dictionary = tr._lanes[0]
	var lead: Car = tr._make_car(lane)
	lead.position.x = 600.0
	lead.desired = 20.0
	lead.speed = 20.0
	var fast: Car = tr._make_car(lane)
	fast.position.x = 300.0
	fast.desired = 120.0
	fast.speed = 120.0
	tr._add(lane, lead)
	tr._add(lane, fast)
	var min_gap_seen := INF
	for _i in 600:
		lead.position.x += 0.0   # ведущий едет сам через drive (INF-зазор)
		tr.update(0.05)
		var gap := (lead.position.x - fast.position.x) - (lead.width() + fast.width()) / 2.0
		min_gap_seen = minf(min_gap_seen, gap)
	_check(min_gap_seen >= 0.0, "быстрая машина не наехала на медленную (минимальный зазор %.1f)" % min_gap_seen)
	_check(fast.speed <= lead.speed + 30.0 or fast.position.x > rect.end.x, "быстрая притормозила и едет за медленной")
	# на длинной дистанции: ни одна пара в полосе не пересекается
	for car in tr.cars():
		car.queue_free()
	tr.queue_free()
	parent.queue_free()
	await get_tree().process_frame
	var city := _new_city(true)
	await get_tree().process_frame
	city.set_process(false)
	var overlaps := 0
	var spawned := 0
	for _i in 4000:   # ~6.5 минут
		city._traffic.update(0.1)
		var by_lane := {}
		for car in city._traffic.cars():
			by_lane[roundi(car.position.y)] = by_lane.get(roundi(car.position.y), []) + [car]
		spawned = maxi(spawned, city._traffic.cars().size())
		for lane_y in by_lane:
			var cars: Array = by_lane[lane_y]
			for i in cars.size():
				for j in range(i + 1, cars.size()):
					if absf(cars[i].position.x - cars[j].position.x) < (cars[i].width() + cars[j].width()) / 2.0 - 1.0:
						overlaps += 1
	_check(overlaps == 0, "машины никогда не пересекаются на полосе (пересечений: %d)" % overlaps)
	_check(spawned >= 4, "на дороге есть машины (до %d)" % spawned)
	city.queue_free()
	await get_tree().process_frame


func _test_city_input() -> void:
	var city := _new_city(true)
	await get_tree().process_frame
	city._update_xray(10.0)
	var room: CafeRoom = city._room
	var player: CatWalker = city._player
	var rc: Vector2i = city._nav.interior_cells().position
	for n in city._npcs:   # гуляющие коты стоят где попало — убираем с места тапов
		(n["cat"] as CatWalker).position = WorldNav.feet_at(Vector2i(75, 23))
		n["timer"] = 1000.0
	# тап по полу внутри
	var floor_cell := rc + Vector2i(6, 4)
	var wp := (Vector2(floor_cell) + Vector2(0.5, 0.5)) * 32.0
	_click(_screen_of(city, wp), true)
	_click(_screen_of(city, wp), false)
	_check(player.is_moving(), "тап по полу внутри запускает ходьбу")
	_walk(player)
	_check(player.position == WorldNav.feet_at(floor_cell), "кот пришёл в клетку тапа")
	# тап по стойке
	var counter_wp: Vector2 = room.to_global(Vector2(40, 70))
	_click(_screen_of(city, counter_wp), true)
	_click(_screen_of(city, counter_wp), false)
	_check(city._pending == "shift" and player.is_moving(), "тап по стойке: кот идёт к ней, чтобы начать смену")
	_walk(player)
	_check(city._shift_layer != null, "дошёл до стойки — смена началась сама")
	city._end_shift(0, 0)
	await get_tree().process_frame
	# тап по тротуару снаружи: кот выходит сам, через проём
	var out_cell := Vector2i(8, 23)
	var out_wp := (Vector2(out_cell) + Vector2(0.5, 0.5)) * 32.0
	_click(_screen_of(city, out_wp), true)
	_click(_screen_of(city, out_wp), false)
	_check(player.is_moving(), "тап по тротуару запускает ходьбу из зала на улицу")
	_walk(player, 1500)
	_check(player.position == WorldNav.feet_at(out_cell), "кот вышел на тротуар сам, без кнопок и дверей")
	city._update_xray(10.0)
	_check(city._xray < 0.01, "вышел — круг рентгена сжался")
	# тап по фасаду кафе: кот идёт внутрь
	var facade := Vector2(540.0, 520.0)
	_click(_screen_of(city, facade), true)
	_click(_screen_of(city, facade), false)
	_check(player.is_moving(), "тап по фасаду кафе ведёт кота внутрь")
	_walk(player, 1500)
	city._update_xray(10.0)
	_check(city._nav.is_interior(WorldNav.cell_of_feet(player.position)) and city._xray > 0.99, "кот зашёл через проём, интерьер открылся")
	# тап по соседнему зданию
	player.stop()
	var closed := Vector2(120.0, 520.0)
	_click(_screen_of(city, closed), true)
	_click(_screen_of(city, closed), false)
	_check(not player.is_moving(), "тап по чужому зданию — «Здесь закрыто», кот стоит")
	# пока открыта пауза, тапы не обрабатываются
	city._open_menu()
	var pos := player.position
	_click(_screen_of(city, wp), true)
	_check(player.position == pos and not player.is_moving(), "на паузе тапы по миру игнорируются")
	city._close_menu()
	city.queue_free()
	await get_tree().process_frame


func _test_decorate_logic() -> void:
	GameState.coins = 100
	GameState.layout = Data.default_layout.duplicate(true)
	var scene: Node2D = load(Nav.DECORATE).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var n0 := GameState.layout.size()
	scene._buy("plant")
	_check(GameState.layout.size() == n0 + 1 and GameState.coins == 80, "покупка растения: -20 монет")
	scene._buy("ucounter")
	_check(GameState.layout.size() == n0 + 1 and GameState.coins == 80, "без монет не купить")
	var idx: int = GameState.layout.size() - 1
	scene._select(idx)
	scene._dragging = true
	scene._drag_start = Vector2i(int(GameState.layout[idx]["c"]), int(GameState.layout[idx]["r"]))
	scene._drag_off = Vector2i.ZERO
	scene._drag_to(CafeRoom.cell_pos(3, 2) + Vector2(10, 10))  # в клетку стола
	_check(scene._drag_err != "", "перетаскивание в стол отклонено")
	scene._drop()
	_check(Vector2i(int(GameState.layout[idx]["c"]), int(GameState.layout[idx]["r"])) == scene._drag_start, "позиция вернулась")
	scene._select(idx)
	scene._dragging = true
	scene._drag_to(CafeRoom.cell_pos(1, 5) + Vector2(10, 10))
	_check(scene._drag_err == "", "перетаскивание на свободное место: " + scene._drag_err)
	scene._drop()
	_check(int(GameState.layout[idx]["c"]) == 1 and int(GameState.layout[idx]["r"]) == 5, "позиция сохранилась")
	scene._flip_selected()
	_check(bool(GameState.layout[idx]["flip"]), "отзеркаливание")
	scene._remove_selected()
	_check(GameState.layout.size() == n0 and GameState.coins == 100, "продажа возвращает полную цену")
	scene.queue_free()
	await get_tree().process_frame


func _test_decorate_input() -> void:
	GameState.coins = 0
	GameState.layout = Data.default_layout.duplicate(true)
	var d: Node2D = load(Nav.DECORATE).instantiate()
	add_child(d)
	await get_tree().process_frame
	var table_idx := -1
	for i in GameState.layout.size():
		if GameState.layout[i]["id"] == "table_big":
			table_idx = i
	var pos: Vector2 = d.ROOM_POS
	_click(pos + Vector2(128, 190), true)   # стол: клетки (3..4, 2..3)
	_check(d._sel == table_idx and d._dragging, "нажатие на стол выбирает его")
	_move_to(pos + Vector2(64, 190))
	_click(pos + Vector2(64, 190), false)
	_check(int(GameState.layout[table_idx]["c"]) == 1 and int(GameState.layout[table_idx]["r"]) == 2, "стол перетащен ровно на 2 клетки влево")
	# в передний ряд (витрина) — нельзя: стол 2×2 в рядах 5–6 не поместится
	_click(pos + Vector2(64, 190), true)
	_move_to(pos + Vector2(64, 300))
	_click(pos + Vector2(64, 300), false)
	_check(int(GameState.layout[table_idx]["r"]) == 2, "в передний ряд (витрина) мебель не ставится")
	# в занятую клетку (к пуфику (5,3)) — отклоняется
	_click(pos + Vector2(64, 190), true)
	_move_to(pos + Vector2(176, 208))
	_click(pos + Vector2(176, 208), false)
	_check(int(GameState.layout[table_idx]["c"]) == 1, "перетаскивание на пуфик отклонено")
	# в служебку — нельзя
	_click(pos + Vector2(64, 190), true)
	_move_to(pos + Vector2(250, 150))
	_click(pos + Vector2(250, 150), false)
	_check(int(GameState.layout[table_idx]["c"]) == 1, "в служебку мебель не ставится")
	_click(pos + Vector2(20, 10), true)  # пустая стена
	_check(d._sel == -1, "тап по пустому месту снимает выделение")
	d.queue_free()
	await get_tree().process_frame


func _same(a: Array, b: Array) -> bool:
	return str(a) == str(b)


func _button_texts(node: Node, out: Array[String]) -> void:
	if node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_button_texts(c, out)


## Сохранение v4, миграция, сброс, улучшения, спрятанная кнопка сброса, магазин.
func _test_progress_and_menu() -> void:
	# новая игра
	GameState.new_game()
	_check(GameState.intro_stage == 0 and GameState.coins == 0 and GameState.upgrades.is_empty(), "новая игра: интро с нуля, касса пуста, улучшений нет")
	_check(GameState.layout.size() == Data.intro_layout.size() and GameState.layout.size() == 2, "новая игра: только стол и пуфик")
	_check(_same(GameState.drink_ids(), ["espresso", "tea"]), "новая игра: только эспрессо и чай (%s)" % [GameState.drink_ids()])
	_check(not GameState.pastries_unlocked(), "новая игра: выпечки нет")
	# старое сохранение v3 -> v4: интро пропущено, всё открыто
	_write_save({"version": 3, "coins": 55, "served_total": 9, "layout": Data.default_layout.duplicate(true), "hour": 15.0})
	GameState.new_game()
	GameState.load_game()
	_check(GameState.intro_stage == GameState.INTRO_DONE and GameState.coins == 55, "v3 -> v4: интро пропущено, монеты целы")
	_check(GameState.has_upgrade("milk_pitcher") and GameState.has_upgrade("display_case") and GameState.drink_ids().size() == 4, "v3 -> v4: всё открыто")
	_check(GameState.layout.size() == Data.default_layout.size(), "v3 -> v4: расстановка не тронута")
	# v4 пишется и читается
	GameState.new_game()
	GameState.coins = 80
	GameState.intro_stage = 3
	GameState.intro_cleaned = {"web_0": 1}
	GameState.upgrades = ["milk_pitcher"]
	GameState.keepsakes = ["photo"]
	GameState.save_game()
	GameState.new_game()
	GameState.load_game()
	_check(GameState.coins == 80 and GameState.intro_stage == 3 and _same(GameState.upgrades, ["milk_pitcher"]) and _same(GameState.keepsakes, ["photo"]) and int(GameState.intro_cleaned.get("web_0", 0)) == 1, "v4: поля интро и улучшений сохраняются")
	# улучшения
	GameState.new_game()
	GameState.coins = 29
	_check(not GameState.can_buy_upgrade("milk_pitcher") and not GameState.buy_upgrade("milk_pitcher"), "молочник не купить за 29 монет")
	GameState.coins = 100
	_check(not GameState.can_buy_upgrade("matcha_kit"), "набор матчи недоступен без молочника")
	_check(GameState.buy_upgrade("milk_pitcher") and GameState.coins == 70, "молочник куплен за 30")
	_check(not GameState.buy_upgrade("milk_pitcher"), "второй раз купить нельзя")
	_check("latte" in GameState.drink_ids() and not ("matcha_latte" in GameState.drink_ids()), "после молочника открыт латте, матчи ещё нет")
	GameState.upgrades.append("espresso_pro")
	_check(is_equal_approx(GameState.price_mult("espresso"), 1.25) and is_equal_approx(GameState.price_mult("tea"), 1.0), "кофемашина Pro: кофе дороже на 25%, чай нет")
	# сброс прогресса
	GameState.coins = 999
	GameState.save_game()
	GameState.reset_progress()
	_check(GameState.coins == 0 and GameState.intro_stage == 0 and GameState.upgrades.is_empty(), "сброс: игра начата заново")
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
	var saved: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_check(int(saved["coins"]) == 0 and int(saved["intro_stage"]) == 0, "сброс: в файле сохранения новая игра")
	# меню: сброс спрятан в «Настройки → Аккаунт», на главной и в настройках его нет
	GameState.intro_stage = GameState.INTRO_DONE
	var city := _new_city(true)
	await get_tree().process_frame
	var texts_main: Array[String] = []
	_button_texts(city._menu_pages["main"], texts_main)
	var texts_settings: Array[String] = []
	_button_texts(city._menu_pages["settings"], texts_settings)
	var texts_account: Array[String] = []
	_button_texts(city._menu_pages["account"], texts_account)
	_check(not ("Сбросить прогресс" in texts_main) and not ("Сбросить прогресс" in texts_settings), "сброса нет ни на главной странице меню, ни в настройках")
	_check("Настройки" in texts_main and "Аккаунт" in texts_settings and "Сбросить прогресс" in texts_account, "путь к сбросу: Меню → Настройки → Аккаунт")
	var texts_confirm: Array[String] = []
	_button_texts(city._menu_pages["confirm"], texts_confirm)
	_check("Сбросить" in texts_confirm and "Отмена" in texts_confirm, "сброс требует подтверждения (есть «Отмена»)")
	city._open_menu()
	city._menu_page("account")
	_check(city._menu_pages["account"].visible and not city._menu_pages["main"].visible, "страницы меню переключаются")
	city._close_menu()
	# магазин: карточки и покупка
	GameState.upgrades = []
	GameState.coins = 70
	city._open_shop()
	var texts_shop: Array[String] = []
	_button_texts(city._shop_page, texts_shop)
	_check("30" in texts_shop and "60" in texts_shop and "120" in texts_shop, "в магазине видны цены улучшений (%s)" % [texts_shop])
	city._buy_upgrade("milk_pitcher")
	_check(GameState.has_upgrade("milk_pitcher") and GameState.coins == 40, "покупка в магазине: списаны монеты, улучшение получено")
	city._buy_upgrade("display_case")
	_check(not GameState.has_upgrade("display_case"), "витрина не покупается без монет")
	city.queue_free()
	await get_tree().process_frame
	GameState.upgrades = ["milk_pitcher", "matcha_kit", "display_case"]
	GameState.coins = 0


## Мини-игра готовки: поднос, подача, улучшения в источниках, режим обучения.
func _test_brew() -> void:
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.upgrades = []
	var m: Node2D = load(Nav.BREW).instantiate()
	add_child(m)
	await get_tree().process_frame
	var ids: Array[String] = []
	for sc in m._sources:
		ids.append(String(sc["id"]))
	_check(_same(ids, ["coffee", "tea"]), "без улучшений на столе только кофе и чай (%s)" % [ids])
	_check(m._tray != null and m._tray.is_empty(), "поднос на месте и пуст")
	m._add_ingredient("base", "coffee", m._tray.position)
	_check(not m._tray.is_empty() and m._cup.base == "coffee", "ингредиент ложится на поднос")
	m._discard_cup()
	_check(m._tray.is_empty() and m._cup.is_empty(), "поднос в корзину очищает его")
	m.queue_free()
	await get_tree().process_frame
	GameState.upgrades = ["milk_pitcher", "matcha_kit", "display_case"]
	var full: Node2D = load(Nav.BREW).instantiate()
	add_child(full)
	await get_tree().process_frame
	_check(full._sources.size() == 6, "со всеми улучшениями на столе 6 источников (%d)" % full._sources.size())
	full.queue_free()
	await get_tree().process_frame
	# обучение: только кофе и чай, заказы по сценарию, без бонуса, неверный заказ кота не прогоняет
	GameState.coins = 0
	var tut: Node2D = load(Nav.BREW).instantiate()
	tut.tutorial = true
	tut.tutorial_sources = ["coffee", "tea"] as Array[String]
	tut.tutorial_orders = [{"cat": "tucha", "drink": "espresso", "pastry": ""}, {"cat": "ryzhik", "drink": "tea", "pastry": ""}] as Array[Dictionary]
	var finished := []
	tut.tutorial_finished.connect(func(served: int, earned: int) -> void: finished.append([served, earned]))
	add_child(tut)
	await get_tree().create_timer(2.2).timeout
	_check(tut._awaiting and tut._order["drink"] == "espresso", "обучение: первым пришёл заказ эспрессо")
	_check(tut._sources.size() == 2, "в обучении на столе два источника")
	tut._add_ingredient("base", "tea", tut._tray.position)   # неверный напиток
	tut._serve()
	_check(tut._awaiting and tut.shift_served == 0 and GameState.coins == 0, "обучение: неверный напиток не прогоняет кота и не платит")
	_check(tut._tray.is_empty(), "обучение: после ошибки поднос очищен")
	tut._add_ingredient("base", "coffee", tut._tray.position)
	tut._serve()
	_check(tut.shift_served == 1 and GameState.coins == 10, "обучение: эспрессо = 8 + 2 чаевых, без бонуса за скорость (монет %d)" % GameState.coins)
	await get_tree().create_timer(4.4).timeout
	_check(tut._awaiting and tut._order["drink"] == "tea", "обучение: вторым пришёл чай")
	tut._add_ingredient("base", "tea", tut._tray.position)
	tut._serve()
	_check(GameState.coins == 18, "обучение: чай = 7 + 1 = 8 (монет %d)" % GameState.coins)
	await get_tree().create_timer(4.6).timeout
	_check(finished.size() == 1 and finished[0][0] == 2 and finished[0][1] == 18, "обучение: по последнему заказу смена объявлена пройденной")
	tut.queue_free()
	await get_tree().process_frame
	GameState.coins = 0


func _intro_city(stage: int) -> Node2D:
	GameState.new_game()
	GameState.intro_stage = stage
	GameState.coins = 0
	var city: Node2D = load(Nav.CITY).instantiate()
	add_child(city)
	return city


## Интро: комикс, ставни (катсцена), расчистка на 21 тап с наградами, обучение → магазин → свободная игра.
func _test_intro() -> void:
	# комикс: 5 панелей, подписи и реплики влезают в кадр
	_check(IntroComic.PANELS.size() == 5, "в комиксе 5 панелей")
	for pn in IntroComic.PANELS:
		for line in String(pn["caption"]).split("\n"):
			_check(Ui.FONT_NARROW.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x <= 296.0, "подпись комикса не влезает в кадр: «%s»" % line)
		for ln in pn["lines"]:
			var tw := Ui.FONT_NARROW.get_string_size(String(ln["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
			_check(tw + 26.0 <= 280.0, "реплика не влезает в пузырь: «%s» (%s px)" % [ln["text"], tw])
	var taps := 0
	for d in Intro.OBJECTS:
		taps += int(d["taps"])
	_check(Intro.OBJECTS.size() == 15 and taps == Intro.TOTAL_TAPS and taps == 21, "расчистка: 15 объектов и 21 тап (%d)" % taps)
	_check(Intro.TUTORIAL_ORDERS.size() == 5, "в обучающей смене 5 заказов")
	var tut_total := 0
	for o in Intro.TUTORIAL_ORDERS:
		var price := int(Data.drinks[o["drink"]]["price"])
		tut_total += price + maxi(1, int(round(price * 0.2)))
		_check(String(o["drink"]) in ["espresso", "tea"], "в обучении только эспрессо и чай")
	_check(tut_total == 46, "обучающая смена приносит 46 монет (%d)" % tut_total)
	# стадия 1: закрытые ставни не пускают в кафе
	var city := _intro_city(1)
	await get_tree().process_frame
	var nav: WorldNav = city._nav
	var rc := nav.interior_cells().position
	var ex := rc.x + CafeRoom.ENTRANCE_CELLS.position.x
	var out_cell := Vector2i(ex, rc.y + CafeRoom.FRONT_ROW + 1)
	var in_cell := Vector2i(ex, rc.y + 3)
	_check(city._intro != null and city._intro.active() and city._npcs.is_empty(), "интро идёт, кафе пустое (гостей нет)")
	_check(nav.find_path(WorldNav.feet_at(out_cell), WorldNav.feet_at(in_cell)).is_empty(), "закрытые ставни: в кафе не пройти")
	_check(city._player.position.y > 700.0, "катсцена начинается на улице у кафе")
	_check(city._intro.light().r < 0.5, "до расчистки в зале темно")
	var before_hour := TimeOfDay.hour
	city._skip_hour()
	_check(TimeOfDay.hour == before_hour, "во время интро время не перематывается")
	# два тапа по ставням открывают их
	var shutter_p := Intro.SHUTTER_RECT.get_center()
	_check(city._intro.on_tap(shutter_p) and city._intro._knocks == 1 and GameState.intro_stage == 1, "первый тап: ставни заело")
	_check(city._intro.on_tap(shutter_p) and GameState.intro_stage == 1, "второй тап: «Пяткой!» — ставни пошли вверх")
	await get_tree().create_timer(1.6).timeout
	_check(GameState.intro_stage == 2 and city._intro._shutter == null, "ставни открыты, началась расчистка")
	_check(not nav.find_path(WorldNav.feet_at(out_cell), WorldNav.feet_at(in_cell)).is_empty(), "после открытия ставней в кафе можно войти")
	_check(city._player.is_moving(), "кот сам заходит в кафе")
	_check(city._intro._nodes.size() == 15 - 0 and is_equal_approx(city._intro.progress(), 0.0), "расчистка: объекты созданы, прогресс 0")
	_check(GameState.layout.size() == 2, "в зале только стол и пуфик")
	# тап по объекту отправляет кота к нему; тап по пустому месту — нет
	city._player.position = WorldNav.feet_at(rc + Vector2i(4, 4))
	city._update_xray(10.0)
	var web_world: Vector2 = city._room.to_global(Intro.OBJECTS[0]["pos"] + Vector2(6, 6))
	_check(city._intro.on_tap(web_world) and city._intro._target == "web_0" and city._player.is_moving(), "тап по паутине: кот идёт к ней")
	city._player.stop()
	_check(not city._intro.on_tap(city._room.to_global(Vector2(160, 300))), "тап по пустому месту интро не перехватывает")
	# все 21 тап: прогресс растёт монотонно, награды выдаются
	var finished := []
	city._intro.cleanup_finished.connect(func() -> void: finished.append(true))
	var last := 0.0
	var done_taps := 0
	for d in Intro.OBJECTS:
		for _i in int(d["taps"]):
			city._intro._act(String(d["id"]))
			done_taps += 1
			var pr: float = city._intro.progress()
			_check(pr >= last - 0.0001, "прогресс не убывает")
			last = pr
			if done_taps == 20:
				_check(finished.is_empty() and GameState.intro_stage == 2, "на 20-м тапе кафе ещё не готово")
	await get_tree().create_timer(0.7).timeout
	for ch in city.get_children():   # окно с фото ставит игру на паузу — закрываем, как игрок
		if ch is CanvasLayer and (ch as CanvasLayer).layer == 9:
			ch.queue_free()
	get_tree().paused = false
	_check(is_equal_approx(city._intro.progress(), 1.0) and finished.size() == 1, "21 тап = 100%, расчистка завершена один раз")
	_check(GameState.intro_stage == 3, "после расчистки — обучающая смена (стадия 3)")
	_check(GameState.coins == 20, "коробка с посудой дала 20 монет (%d)" % GameState.coins)
	_check("recipe_latte" in GameState.keepsakes and "photo" in GameState.keepsakes, "в коробках найдены рецепт и фото")
	var ids: Array[String] = []
	for it in GameState.layout:
		ids.append(String(it["id"]))
	_check("window" in ids and "board" in ids and "table_small" in ids and "stool" in ids, "после расчистки появились окно и доска, стол и стул на месте (%s)" % [ids])
	_check(GameState.intro_cleaned.size() == 15, "прогресс расчистки сохранён по объектам")
	_check(city._intro.light().is_equal_approx(Color.WHITE), "после расчистки свет нормальный")
	# дальше — обучающая смена в оверлее
	city._start_tutorial()
	_check(city._shift_layer != null and city._shift_layer.get_child(0).tutorial and city._shift_layer.get_child(0).tutorial_orders.size() == 5, "обучающая смена открылась поверх города")
	city._on_tutorial_finished(5, 46)
	_check(GameState.intro_stage == 4 and GameState.tutorial_served == 5 and city._shift_layer == null, "обучение пройдено: стадия 4, магазин")
	await get_tree().create_timer(2.8).timeout
	_check(city._menu.visible and city._menu_pages["shop"].visible, "после обучения сам открылся магазин улучшений")
	GameState.coins = 66
	city._buy_upgrade("milk_pitcher")
	_check(GameState.has_upgrade("milk_pitcher") and GameState.coins == 36, "в магазине куплен молочник")
	city._shop_back()
	_check(GameState.intro_stage == GameState.INTRO_DONE and city._intro == null and not city._menu.visible, "закрытие магазина завершает интро")
	_check(city._npcs.size() == 4, "после интро в кафе приходят гости")
	city.queue_free()
	await get_tree().process_frame
	# возобновление: часть расчистки уже сделана (сохранение посреди интро)
	GameState.new_game()
	GameState.intro_stage = 2
	GameState.intro_cleaned = {"web_0": 1, "dust_0": 1, "machine": 2}
	var resumed: Node2D = load(Nav.CITY).instantiate()
	add_child(resumed)
	await get_tree().process_frame
	_check(not resumed._intro._nodes.has("web_0") and resumed._intro._nodes.has("web_1"), "возобновление: сделанная паутина не рисуется")
	_check(resumed._intro._nodes["dust_0"].level == 1 and resumed._intro._nodes["dust_1"].level == 2, "возобновление: пыль с одним тапом тусклее")
	_check(is_equal_approx(resumed._intro.progress(), 4.0 / 21.0), "возобновление: прогресс %.3f" % resumed._intro.progress())
	resumed.queue_free()
	await get_tree().process_frame
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.upgrades = ["milk_pitcher", "matcha_kit", "display_case"]
	GameState.coins = 0
	TimeOfDay.set_process(false)


func _write_save(data: Dictionary) -> void:
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _test_save_migration() -> void:
	# v1: нет мебели -> расстановка по умолчанию, монеты целы
	_write_save({"version": 1, "coins": 77, "served_total": 3, "cat_progress": {}, "last_visit_unix": 0})
	GameState.layout = []
	GameState.load_game()
	_check(GameState.coins == 77, "v1: монеты сохранились")
	_check(GameState.layout.size() == Data.default_layout.size(), "v1 -> v3: выдана расстановка по умолчанию")
	# v2 (мебель в пикселях): за докупленное возвращаются монеты, остальное — по умолчанию
	var v2_layout: Array = []
	for it in ["window", "board", "table_big", "stool", "plant", "rug", "bowl", "case"]:
		v2_layout.append({"id": it, "x": 100.0, "y": 300.0, "flip": false})
	_write_save({"version": 2, "coins": 10, "layout": v2_layout})
	GameState.load_game()
	_check(GameState.coins == 10 + int(Data.furniture["case"]["price"]), "v2 -> v3: возврат за докупленную витрину")
	_check(GameState.layout.size() == Data.default_layout.size(), "v2 -> v3: расстановка по умолчанию")
	# v3 читается и пишется без потерь, вместе со временем суток
	TimeOfDay.hour = 20.5
	GameState.save_game()
	GameState.layout = []
	TimeOfDay.hour = 9.0
	GameState.load_game()
	_check(GameState.layout.size() == Data.default_layout.size(), "v3: расстановка сохраняется и читается")
	_check(is_equal_approx(TimeOfDay.hour, 20.5), "время суток сохраняется")
	# сохранение без часов (старое) -> утро по умолчанию
	_write_save({"version": 3, "coins": 1, "layout": []})
	GameState.load_game()
	_check(is_equal_approx(TimeOfDay.hour, 9.0), "без поля hour — 9:00")
	# мусор: неизвестный id, дубликат на той же клетке, выход за зал, не словарь
	_write_save({"version": 3, "coins": 1, "layout": [
		{"id": "нет_такого", "c": 1, "r": 1}, {"id": "stool", "c": 1, "r": 5}, {"id": "stool", "c": 1, "r": 5},
		{"id": "table_big", "c": 9, "r": 6}, 5]})
	GameState.load_game()
	_check(GameState.layout.size() == 1 and GameState.layout[0]["id"] == "stool", "битая мебель отбрасывается (осталось %d)" % GameState.layout.size())


func _test_assets() -> void:
	for id in Data.street["buildings"]:
		_check(ResourceLoader.exists("res://assets/street/buildings/%s.png" % id), "нет здания " + id)
	for v in Data.street["vehicles"]:
		for d in ["east", "west"]:
			_check(ResourceLoader.exists("res://assets/street/vehicles/%s_%s.png" % [v["id"], d]), "нет машины %s_%s" % [v["id"], d])
	for path in [Nav.BREW, Nav.CITY, Nav.DECORATE, "res://scenes/street.tscn"]:
		_check(ResourceLoader.exists(path), "сцена существует: " + path)


## Чистые пиксели и объёмный свет: жёсткая альфа у декора, мало уровней у свечения, шейдеры теней/неба.
func _alphas(tex: Texture2D) -> Array:
	var img := tex.get_image()
	var seen := {}
	for y in img.get_height():
		for x in img.get_width():
			seen[snappedf(img.get_pixel(x, y).a, 0.01)] = true
	return seen.keys()


func _test_pixel_lighting() -> void:
	for tex in [PixelArt.web(16), PixelArt.dust(24, 12, 3, 0.5), PixelArt.shutter(52, 18), PixelArt.shutter_bar(52), PixelArt.cover(20, 20), PixelArt.curtain(20, 20)]:
		for a in _alphas(tex):
			_check(a == 0.0 or a == 1.0, "декор: только 0/1 альфа, а найдено %s" % a)
	for tex in [PixelArt.glow(24, 24), PixelArt.cone(40, 12), PixelArt.beam(20, 40, 8), PixelArt.dither_gradient(20, 10), PixelArt.blob(10, 5)]:
		_check(_alphas(tex).size() <= 8, "свечение постеризовано: %d уровней" % _alphas(tex).size())
	_check(PixelArt.web(16) == PixelArt.web(16), "текстуры PixelArt кэшируются")
	for path in ["res://assets/shaders/sky_gradient.gdshader", "res://assets/shaders/dither_shadow.gdshader"]:
		_check(load(path) is Shader, "шейдер загружается: " + path)
	var city := _new_city(false)
	await get_tree().process_frame
	_check(city.get("_sky_bg") != null, "в городе есть небо-градиент")
	var halo: Sprite2D = Fx.pixel_light(Vector2.ZERO, Vector2(64, 64), Color(1, 0.8, 0.4, 0.5))
	_check(halo.texture.get_width() <= 64, "пиксельный ореол собран в разрешении арта")
	halo.free()
	for h in [8.0, 12.0, 19.0, 23.0]:
		TimeOfDay.hour = h
		await get_tree().process_frame
	city.queue_free()
	await get_tree().process_frame


## Мини-игра на сетке крупного плана (4 px): спрайты и поднос стоят на сетке, без дробного масштаба и поворота.
func _test_brew_grid() -> void:
	var brew: Node2D = load(Nav.BREW).instantiate()
	add_child(brew)
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	_check(Fx.unit == 4.0, "в мини-игре пиксель эффектов = пиксель спрайтов (4)")
	var cup := Ui.atlas(load("res://assets/cafe/drinks-and-pastries.png"), Rect2(32, 16, 16, 16))   # эспрессо: ручка справа
	_check(BrewArt.content_offset(cup, true).x < BrewArt.content_offset(cup, false).x, "посуду центрируем по чаше, а не по чаше с ручкой")
	var p := Fx.burst(brew, Vector2(100, 100), "sparkle", Color.WHITE, 3, 50.0)
	await get_tree().create_timer(0.2).timeout
	var sprites := p.get_children().filter(func(n: Node) -> bool: return n is Sprite2D and n.visible)
	_check(not sprites.is_empty(), "частицы летят")
	for sp: Sprite2D in sprites:
		_check(sp.scale.x >= 4.0 and fmod(absf(sp.position.x), 4.0) == 0.0 and fmod(absf(sp.position.y), 4.0) == 0.0, "частица на сетке 4 px, не мельче пикселя игры")
	var tray: ServingTray = brew.get("_tray")
	_check(tray.scale == Vector2.ONE and is_zero_approx(tray.rotation), "поднос не растянут и не повёрнут")
	_check(fmod(tray.position.x, 4.0) == 0.0 and fmod(tray.position.y, 4.0) == 0.0, "поднос стоит на сетке 4 px")
	for plate in brew.get("_table").plates:
		_check(fmod(plate.x, 4.0) == 0.0 and fmod(plate.y, 4.0) == 0.0, "центр тарелки на сетке: %s" % plate)
	for s in brew.get("_sources"):
		var icon: Sprite2D = s["icon"]
		_check(icon.scale == Vector2(4, 4), "иконка источника в целом масштабе")
		var tl: Vector2 = icon.position - Vector2(32, 32)
		_check(fmod(absf(tl.x), 4.0) == 0.0 and fmod(absf(tl.y), 4.0) == 0.0, "иконка на сетке: %s" % tl)
	var bubble: Node2D = brew.get("_bubble")
	if bubble != null:
		for c in bubble.get_children():
			if c is Sprite2D:
				_check((c as Sprite2D).scale == Vector2(2, 2), "иконка в плашке заказа — масштаб 2")
	brew.queue_free()
	await get_tree().process_frame
	_check(Fx.unit == 2.0, "после выхода из мини-игры пиксель эффектов снова 2")


func _global(name: String) -> float:
	var v: Variant = RenderingServer.global_shader_parameter_get(name)
	return float(v) if v != null else -1.0   # в headless сервер рендера пустой


## Погода, снег на земле, двери и прозрачные окна.
func _test_weather() -> void:
	Weather.force(Weather.Kind.RAIN)
	_check(_global("weather_rain") < 0.0 or (_global("weather_rain") > 0.99 and _global("weather_snowfall") < 0.01), "дождь передаётся шейдерам")
	Weather.force(Weather.Kind.SNOW)
	Weather.step(30.0)
	_check(Weather.snow_cover > 0.5, "снег копится, пока идёт снегопад: %s" % Weather.snow_cover)
	_check(_global("weather_snow") < 0.0 or _global("weather_snow") > 0.5, "покров передаётся шейдерам")
	var cover := Weather.snow_cover
	Weather.force(Weather.Kind.HEAT, cover)
	Weather.step(10.0)
	_check(Weather.snow_cover < cover, "в жару снег тает")
	Weather.force(Weather.Kind.RAIN, 0.0, 0.0)
	Weather.step(40.0)
	_check(Weather.wet > 0.5, "под дождём земля намокает")
	_check(Weather.tint().b > Weather.tint().r, "дождь холодит свет")
	_check(Weather.overcast() > 0.5, "дождь — пасмурно")
	Weather.force(Weather.Kind.CLEAR)
	_check(is_zero_approx(Weather.overcast()), "ясно — не пасмурно")
	Weather.set_mode(Weather.AUTO)
	for i in 6:
		Weather.cycle_mode()
	_check(Weather.mode == Weather.AUTO, "цикл настроек погоды замкнут: %d" % Weather.mode)
	Weather.set_mode(Weather.Kind.SNOW)
	GameState.save_game()
	Weather.set_mode(Weather.AUTO)
	GameState.load_game()
	_check(Weather.mode == Weather.Kind.SNOW, "режим погоды хранится в сохранении")
	Weather.force(Weather.Kind.CLEAR)

	# город: материалы снега, экранные эффекты, двери и окна
	Weather.force(Weather.Kind.SNOW, 0.9)
	var city := _new_city(false)
	await get_tree().process_frame
	var ground: CanvasItem = city.get("_ground").get_child(0)
	_check(ground.material is ShaderMaterial, "земля одета снежным шейдером")
	_check(city.get("_weather_fx") is WeatherFx, "в городе есть слой погоды")
	var glass: Array = city.get("_glass")
	_check(glass.size() >= 8, "окна фасадов покрыты стеклом: %d" % glass.size())
	var clear_panes := 0
	for gl: WindowGlass in glass:
		if gl.transparent:
			clear_panes += 1
	_check(clear_panes == 2, "у витрины кафе два прозрачных окна: %d" % clear_panes)
	var door: AutoDoor = city.get("_door")
	_check(door != null, "у кафе есть дверь")
	var nav: WorldNav = city.get("_nav")
	var rc := nav.interior_cells().position
	var player: CatWalker = city.get("_player")
	for n in city.get("_npcs"):   # гости не у двери: иначе она откроется для них
		(n["cat"] as CatWalker).position = WorldNav.feet_at(Vector2i(75, 23))
		n["timer"] = 1000.0
	player.position = WorldNav.feet_at(rc + Vector2i(5, 9))   # далеко на тротуаре
	city.call("_update_door")
	await get_tree().create_timer(0.6).timeout
	_check(door.open_amount < 0.05, "дверь закрыта, пока кот далеко")
	player.position = WorldNav.feet_at(rc + Vector2i(5, 7))   # у входа
	city.call("_update_door")
	await get_tree().create_timer(0.6).timeout
	_check(door.open_amount > 0.95, "дверь открывается, когда кот рядом: %s" % door.open_amount)
	_check(fmod(door._left.position.x, 2.0) == 0.0 and fmod(door._right.position.x, 2.0) == 0.0, "створки едут по сетке арта")
	nav.set_entrance_open(false)   # запертый проём (ставни интро): дверь не открывается
	city.call("_update_door")
	await get_tree().create_timer(0.6).timeout
	_check(door.open_amount < 0.05, "запертая дверь закрыта")
	nav.set_entrance_open(true)
	_check(city.get("_hole_mat").get_shader_parameter("door") != Vector4.ZERO, "в фасаде вырезан проём двери")
	# настройка погоды в меню
	var btn: Button = city.get("_weather_btn")
	_check(btn != null, "в настройках есть кнопка погоды")
	city.call("_cycle_weather")
	_check(btn.text.contains("Погода"), "кнопка показывает погоду: " + btn.text)
	Weather.force(Weather.Kind.CLEAR)
	Weather.set_mode(Weather.AUTO)
	city.queue_free()
	await get_tree().process_frame


## Служебка в зале и второй этаж: улучшения, проём и лестница, смена помещений, проходимость, сон.
func _test_spaces() -> void:
	var back_def := {}
	var up_def := {}
	for u in Data.upgrades:
		if String(u["id"]) == "back_room":
			back_def = u
		elif String(u["id"]) == "upstairs":
			up_def = u
	_check(not back_def.is_empty() and String(back_def["requires"]) == "display_case", "улучшение «Коморка» требует витрину")
	_check(not up_def.is_empty() and String(up_def["requires"]) == "back_room", "«Второй этаж» требует коморку")
	GameState.upgrades = ["milk_pitcher", "display_case"]
	GameState.coins = 1000
	_check(GameState.can_buy_upgrade("back_room") and not GameState.can_buy_upgrade("upstairs"), "этаж не купить без коморки")
	GameState.upgrades = []
	GameState.coins = 0

	# служебка занимает угол зала: мебель туда не ставят, а стоявшая там в старом сохранении возвращает деньги
	var room := CafeRoom.new()
	add_child(room)
	room.set_layout([])
	_check(room.check_place("stool", 7, 1) != "" and room.check_place("rug", 6, 0) != "", "в служебку ничего не ставят")
	_check(room.check_place("stool", 5, 1) == "" and room.check_place("stool", 6, 4) == "", "рядом со служебкой можно")
	_check(room.check_place("board", 8, 1) == "", "на стену над служебкой вешать можно")
	room.queue_free()
	GameState.coins = 0
	var kept := GameState._sanitize_layout([{"id": "stool", "c": 8, "r": 1, "flip": false}])
	_check(kept.is_empty() and GameState.coins == int(Data.furniture["stool"]["price"]), "пуфик из служебки убран, деньги возвращены")

	var city := _new_city(true)
	await get_tree().process_frame
	var nav: WorldNav = city.get("_nav")
	var rc := nav.interior_cells().position
	var player: CatWalker = city.get("_player")
	var croom: CafeRoom = city.get("_room")
	_check(city.get("_space") == 0, "сначала кот в зале")
	# закрыта, пока не куплено
	GameState.upgrades = []
	croom.refresh_staff()
	city.call("_set_space", 0, Vector2i(-1, -1))
	_check(not nav.is_walkable(rc + CafeRoom.STAFF_DOOR) and not nav.is_walkable(rc + Vector2i(8, 2)), "закрытая служебка не проходима")
	var locked_hit := croom.staff_portal_at(Vector2(256, 160))
	_check(String(locked_hit.get("id", "")) == "staff_locked", "тап по чулану даёт «заколочено»")
	city.call("_tap_portal", locked_hit, Vector2(600, 600))
	_check(city.get("_pending") == "", "заколоченная служебка не пускает")

	# куплена «Коморка»: проём открыт, внутри можно ходить, лестница и коробки — преграда
	GameState.upgrades = ["milk_pitcher", "matcha_kit", "display_case", "back_room"]
	city.call("_on_upgrade_bought", "back_room")
	_check(nav.is_walkable(rc + CafeRoom.STAFF_DOOR) and nav.is_walkable(rc + Vector2i(8, 2)) and nav.is_walkable(rc + Vector2i(7, 2)), "служебка открыта: проём и пол внутри проходимы")
	_check(not nav.is_walkable(rc + Vector2i(8, 0)) and not nav.is_walkable(rc + Vector2i(7, 0)) and not nav.is_walkable(rc + Vector2i(6, 1)) and not nav.is_walkable(rc + Vector2i(7, 3)), "лестница, коробки и стены не проходимы")
	_check(not nav.find_path(WorldNav.feet_at(rc + Vector2i(5, 5)), WorldNav.feet_at(rc + Vector2i(8, 2))).is_empty(), "из зала можно пройти в служебку")
	var stairs_hit := croom.staff_portal_at(Vector2(260, 100))
	_check(String(stairs_hit.get("id", "")) == "stairs_up", "тап по лестнице в служебке")
	_check(String(city.call("_portal_gate", stairs_hit)) != "", "лестница заколочена, пока нет «Второго этажа»")
	city.call("_tap_portal", stairs_hit, Vector2(600, 600))
	_check(city.get("_pending") == "", "заколоченная лестница не пускает")

	# второй этаж
	GameState.upgrades.append("upstairs")
	city.call("_on_upgrade_bought", "upstairs")
	_check(String(city.call("_portal_gate", stairs_hit)) == "", "после покупки лестница свободна")
	player.position = WorldNav.feet_at(rc + CafeRoom.STAIRS_STAND[0])
	city.call("_tap_portal", stairs_hit, Vector2(600, 600))
	await get_tree().create_timer(0.9).timeout
	_check(city.get("_space") == 2, "по лестнице кот поднялся в жилую зону")
	var up_rect: Rect2 = city.get("_upper_rect")
	var floor_nav: FloorNav = city.get("_floor_nav")
	_check(up_rect.position.y < croom.position.y and up_rect.end.y <= croom.position.y + 320.0, "второй этаж стоит в мире выше первого: %s" % up_rect)
	_check(up_rect.has_point(player.position) and player.nav == floor_nav, "кот наверху: на втором этаже и со своей сеткой ходьбы")
	_check(not floor_nav.is_walkable(Vector2i(3, 0)) and not floor_nav.is_walkable(Vector2i(4, 1)), "кровать занимает клетки")
	_check(not floor_nav.find_path(player.position, floor_nav.feet_at(InteriorSpace.BED_STAND[0])).is_empty(), "до кровати можно дойти")
	# с этажа не выйти: путь «на улицу» упирается в стены
	var out := floor_nav.find_path(player.position, Vector2(up_rect.end.x + 200.0, up_rect.end.y + 200.0))
	for pt in out:
		_check(up_rect.has_point(pt), "кот наверху не выходит за стены этажа: %s" % pt)
	city.call("_apply_daylight")
	city.call("_update_xray", 5.0)
	_check(city.get("_upper_hole_mat").get_shader_parameter("radius") > 1.0 and is_zero_approx(float(city.get("_hole_mat").get_shader_parameter("radius"))), "рентген открыт у второго этажа, первый закрыт")
	for n in city.get("_npcs"):   # гости зала остаются внизу и наверху не видны
		var cat: CatWalker = n["cat"]
		_check(not city.call("is_revealed", cat.position) or city.call("_depth", cat.position) < 0.05, "гость первого этажа не виден, пока кот на втором")
	# сон: ночью — до утра
	TimeOfDay.hour = 22.0
	city.call("_sleep")
	await get_tree().create_timer(0.9).timeout
	_check(is_equal_approx(TimeOfDay.hour, 7.0), "после сна утро: %s" % TimeOfDay.hour)
	# вниз, в служебку
	city.call("_use_portal", {"id": "stairs_down", "stand": InteriorSpace.STAIRS_STAND, "to": "cafe"})
	await get_tree().create_timer(0.9).timeout
	_check(city.get("_space") == 0, "лестница вниз ведёт в служебку")
	_check(nav.is_walkable(rc + Vector2i(5, 4)) and nav.is_walkable(rc + CafeRoom.STAFF_DOOR), "в зале снова проходимы его клетки")
	var back_cell := WorldNav.cell_of_feet(player.position) - rc
	_check(CafeRoom.STAFF_INNER.has_point(back_cell) and player.nav == nav, "кот спустился в служебку и снова ходит по городской сетке: %s" % back_cell)
	# магазин показывает все шесть улучшений
	GameState.upgrades = []
	city.call("_open_shop")
	var texts: Array[String] = []
	_button_texts(city.get("_shop_page"), texts)
	_check("150" in texts and "300" in texts, "в магазине видны коморка и второй этаж (%s)" % [texts])
	city.call("_close_menu")
	city.queue_free()
	await get_tree().process_frame
