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
	_test_texts_fit()
	_test_time_of_day()
	await _test_default_layout()
	await _test_place_rules()
	await _test_level_scene()
	await _test_world_nav()
	await _test_city()
	await _test_npc_visits()
	await _test_traffic()
	await _test_city_input()
	await _test_decorate_logic()
	await _test_decorate_input()
	_test_save_migration()
	_test_assets()
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
	var button_w := {"Продолжить": 252.0, "Украшение": 252.0, "Время +3 ч": 252.0, "Выход": 252.0, "Смена": 184.0, "Выйти": 184.0, "Войти": 184.0}
	for t in button_w:
		var w3 := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
		_check(w3 + 36.0 + 16.0 <= float(button_w[t]), "«%s» не влезает в кнопку (%s px)" % [t, w3])
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
	_check(room.check_place("rug", 7, 2) == "", "коврик можно под стол (плоский)")
	# ряд мебели поперёк зала: последний предмет закрыл бы проход — должен быть отклонён именно по этой причине
	var row: Array[Dictionary] = []
	for c in [0, 2, 4, 6]:
		row.append(_item("cabinet", c, 4))
	row.append(_item("machine", 8, 4))
	var sealed := _room_with(row)
	_check(not sealed.find_path(CafeRoom.feet_at(CafeRoom.SPAWN_CELL), CafeRoom.feet_at(Vector2i(1, 0))).is_empty(), "с зазором в ряду проход есть")
	_check(sealed.check_place("machine", 9, 4) == tr("Не загораживайте проход"), "последний предмет, закрывающий проход, отклонён")
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


## Редактируемый уровень: зоны, здания, предметы на месте и согласованы с сеткой.
func _test_level_scene() -> void:
	var level := (load("res://scenes/street.tscn") as PackedScene).instantiate() as StreetLevel
	add_child(level)
	for kind in [StreetZone.Kind.WALK, StreetZone.Kind.LANE_EAST, StreetZone.Kind.LANE_WEST, StreetZone.Kind.CAFE_INTERIOR, StreetZone.Kind.SIDEWALK, StreetZone.Kind.ROAD]:
		_check(level.zones(kind).size() >= 1, "в уровне нет зоны вида %d" % kind)
	var interior := level.zones(StreetZone.Kind.CAFE_INTERIOR)[0]
	_check(is_zero_approx(fposmod(interior.position.x, 32.0)) and is_zero_approx(fposmod(interior.position.y + CafeRoom.ORIGIN.y, 32.0)), "пол кафе лежит в сетке мира 32 px")
	_check(interior.size.is_equal_approx(CafeRoom.ROOM_SIZE), "зона интерьера 320×320")
	_check(interior._get_configuration_warnings().is_empty(), "у зоны интерьера нет предупреждений редактора")
	var cafes := 0
	for b in level.get_node("Buildings").get_children():
		if (b as StreetBuilding).is_cafe:
			cafes += 1
			var rect := (b as StreetBuilding).world_rect()
			_check(rect.grow(12).encloses(Rect2(interior.position, interior.size)), "интерьер вписан в габарит фасада кафе")
			_check(is_equal_approx(rect.end.y, interior.position.y + 320.0), "низ интерьера на линии низа фасада")
	_check(cafes == 1, "в уровне ровно одно кафе")
	# полосы: верхняя (на запад) выше нижней, и машины любой модели в них не пересекаются по высоте
	var west := level.zones(StreetZone.Kind.LANE_WEST)[0]
	var east := level.zones(StreetZone.Kind.LANE_EAST)[0]
	_check(west.world_rect().end.y < east.world_rect().position.y + 8.0, "полосы не накладываются")
	for v in Data.street["vehicles"]:
		_check(float(v["frame"][1]) * 2.0 <= 90.0, "машина %s выше полосы" % v["id"])
	level.queue_free()
	await get_tree().process_frame


## Единая сетка: с улицы в зал и обратно — один путь через проём, без дверей и телепортов.
func _test_world_nav() -> void:
	var city := _new_city(true)
	await get_tree().process_frame
	var nav: WorldNav = city._nav
	var inside := Vector2i(12, 8)
	var outside := Vector2i(12, 12)
	_check(nav.is_interior(inside) and not nav.is_interior(outside), "клетки зала и улицы различаются")
	var path := nav.find_path(WorldNav.feet_at(outside), WorldNav.feet_at(inside))
	_check(not path.is_empty(), "путь с улицы в зал есть")
	var crossed_entrance := false
	for p in path:
		var c := WorldNav.cell_of_feet(p)
		if c.y == 11:
			_check(c.x == 12 or c.x == 13, "путь пересекает витрину не в проёме (клетка %s)" % c)
			crossed_entrance = true
	_check(crossed_entrance, "путь проходит через проём входа")
	var back := nav.find_path(WorldNav.feet_at(inside), WorldNav.feet_at(Vector2i(30, 13)))
	_check(not back.is_empty() and back[back.size() - 1].distance_to(WorldNav.feet_at(Vector2i(30, 13))) < 1.0, "путь из зала на дальний тротуар есть")
	_check(not nav.is_walkable(Vector2i(10, 11)) and not nav.is_walkable(Vector2i(15, 11)), "витрина кафе не проходима, кроме проёма")
	_check(nav.is_walkable(Vector2i(12, 11)) and nav.is_walkable(Vector2i(13, 11)), "проём входа проходим")
	_check(not nav.is_walkable(Vector2i(10, 14)), "дорога не проходима")
	# мебель и предметы улицы закрывают клетки
	var table := Vector2i(8, 5) + Vector2i(7, 2)
	_check(not nav.is_walkable(table), "стол в зале закрывает клетку")
	_check(not nav.is_walkable(Vector2i(5, 12)), "торговый автомат закрывает клетку на тротуаре")
	# весь проходимый мир связный: нет «запертых» кусков тротуара (например, предметы по диагонали)
	var unreachable := 0
	for y in range(0, 20):
		for x in range(0, 45):
			var cell := Vector2i(x, y)
			if nav.is_walkable(cell) and nav.find_path(WorldNav.feet_at(outside), WorldNav.feet_at(cell)).is_empty() and cell != outside:
				unreachable += 1
	_check(unreachable == 0, "все проходимые клетки достижимы (недостижимых: %d)" % unreachable)
	var far := nav.find_path(WorldNav.feet_at(outside), WorldNav.feet_at(Vector2i(10, 14)))   # цель на дороге
	_check(not far.is_empty() and nav.is_walkable(WorldNav.cell_of_feet(far[far.size() - 1])), "цель на дороге заменяется ближайшей проходимой клеткой")
	city.queue_free()
	await get_tree().process_frame


func _test_city() -> void:
	var city := _new_city(true)
	await get_tree().process_frame
	var player: CatWalker = city._player
	var room: CafeRoom = city._room
	var nav: WorldNav = city._nav
	_check(nav.is_interior(WorldNav.cell_of_feet(player.position)), "игра начинается внутри кафе")
	_check(city.get("_btn_enter") == null and city.get("_btn_exit") == null, "кнопок «Войти/Выйти» нет — дверей нет")
	city._update_xray(10.0)
	city._apply_daylight()
	_check(city._xray > 0.99 and city._room.visible and city._cafe.modulate.a < 0.01, "внутри фасад прозрачен, виден интерьер")
	# выходим сплошным путём: один и тот же узел, без пересадок; рентген закрывается плавно
	var parent_before := player.get_parent()
	_check(player.walk_to(WorldNav.feet_at(Vector2i(12, 12))), "путь из кафе на улицу найден")
	var xs: Array[float] = []
	for _i in 600:
		player.step(0.05)
		city._update_xray(0.05)
		xs.append(city._xray)
	_check(player.get_parent() == parent_before and player.get_parent() == city._actors, "кот остался тем же узлом в том же слое (бесшовно)")
	_check(player.position == WorldNav.feet_at(Vector2i(12, 12)), "кот вышел на тротуар у проёма")
	var smooth := true
	var mid := false
	for i in range(1, xs.size()):
		if xs[i] > xs[i - 1] + 0.001:
			smooth = false
		if xs[i] > 0.05 and xs[i] < 0.95:
			mid = true
	_check(smooth and mid, "рентген закрывается плавно: проходит промежуточные значения (smooth=%s mid=%s)" % [smooth, mid])
	_check(city._xray < 0.01, "снаружи рентген выключен")
	city._apply_daylight()
	_check(not city._room.visible and is_equal_approx(city._cafe.modulate.a, 1.0), "снаружи интерьер не рисуется, видно здание")
	city._update_xray(0.0)
	# гость в зале при закрытом фасаде не виден; снаружи виден
	var guest: CatWalker = city._npcs[0]["cat"]
	guest.position = WorldNav.feet_at(Vector2i(12, 8))
	var walker: CatWalker = city._npcs[1]["cat"]
	walker.position = WorldNav.feet_at(Vector2i(20, 12))
	city._apply_daylight()
	_check(not guest.visible and walker.visible, "гость внутри скрыт, пока мы снаружи; прохожий виден")
	# обратно в кафе
	player.walk_to(WorldNav.feet_at(Vector2i(12, 8)))
	var up: Array[float] = []
	for _i in 600:
		player.step(0.05)
		city._update_xray(0.05)
		up.append(city._xray)
	_check(player.position == WorldNav.feet_at(Vector2i(12, 8)) and city._xray > 0.99, "вошли в кафе: интерьер виден")
	var rising := true
	for i in range(1, up.size()):
		if up[i] < up[i - 1] - 0.001:
			rising = false
	_check(rising, "рентген открывается плавно")
	city._apply_daylight()
	_check(guest.visible, "внутри гость виден")
	# стойка -> кнопка смены
	player.walk_to(nav.counter_feet(1))
	_walk(player)
	city._process(0.016)
	_check(city._btn_shift.visible, "у стойки видна кнопка «Смена»")
	player.walk_to(WorldNav.feet_at(Vector2i(14, 8)))
	_walk(player)
	city._process(0.016)
	_check(not city._btn_shift.visible, "вдали от стойки кнопки нет")
	_check(GameState.city_inside, "положение (в кафе) запомнено для возврата из других экранов")
	# мебель: в интерьере и сортируется вместе с котами
	var furniture := 0
	for ch in city._actors.get_children():
		if ch.has_meta("interior"):
			furniture += 1
			_check(ch.get_parent() == city._actors, "мебель кафе в общем слое сортировки")
	_check(furniture >= 3, "мебель из раскладки есть в общем слое (%d)" % furniture)
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
	city.set_process(false)
	var transitions := 0
	var was_inside: Array[bool] = []
	for n in city._npcs:
		was_inside.append(nav.is_interior(WorldNav.cell_of_feet((n["cat"] as CatWalker).position)))
	var bad_cell := false
	for _t in 9000:   # ~15 минут игры
		city._npc_tick(0.1)
		for i in city._npcs.size():
			var cat: CatWalker = city._npcs[i]["cat"]
			cat.step(0.1)
			var c := WorldNav.cell_of_feet(cat.position)
			if not nav.is_walkable(WorldNav.cell_of_feet(cat.position + Vector2(0, 0))) and not nav.is_walkable(c):
				bad_cell = true
			var inside := nav.is_interior(c)
			if inside != was_inside[i]:
				transitions += 1
				was_inside[i] = inside
				_check(absi(c.y - 11) <= 1, "кот пересёк границу зала не в проёме (клетка %s)" % c)
	_check(not bad_cell, "коты ходят только по проходимым клеткам")
	_check(transitions >= 4, "коты заходят в кафе и выходят из него (переходов: %d)" % transitions)
	# а видимость следует за рентгеном: игрок снаружи -> гости внутри не рисуются
	city._update_xray(10.0)
	city._apply_daylight()
	for n in city._npcs:
		var cat: CatWalker = n["cat"]
		if nav.is_interior(WorldNav.cell_of_feet(cat.position)) and city._depth(cat.position) > 0.9:
			_check(not cat.visible, "гость глубоко в зале не рисуется, пока фасад закрыт")
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
	for n in city._npcs:   # гуляющие коты стоят где попало — убираем с места тапов
		(n["cat"] as CatWalker).position = WorldNav.feet_at(Vector2i(40, 12))
		n["timer"] = 1000.0
	# тап по полу внутри
	var floor_cell := Vector2i(14, 9)
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
	var out_cell := Vector2i(8, 12)
	var out_wp := (Vector2(out_cell) + Vector2(0.5, 0.5)) * 32.0
	_click(_screen_of(city, out_wp), true)
	_click(_screen_of(city, out_wp), false)
	_check(player.is_moving(), "тап по тротуару запускает ходьбу из зала на улицу")
	_walk(player, 1500)
	_check(player.position == WorldNav.feet_at(out_cell), "кот вышел на тротуар сам, без кнопок и дверей")
	city._update_xray(10.0)
	_check(city._xray < 0.01, "вышел — рентген выключился")
	# тап по фасаду кафе: кот идёт внутрь
	var facade := Vector2(420.0, 200.0)
	_click(_screen_of(city, facade), true)
	_click(_screen_of(city, facade), false)
	_check(player.is_moving(), "тап по фасаду кафе ведёт кота внутрь")
	_walk(player, 1500)
	city._update_xray(10.0)
	_check(city._nav.is_interior(WorldNav.cell_of_feet(player.position)) and city._xray > 0.99, "кот зашёл через проём, интерьер открылся")
	# тап по соседнему зданию
	player.stop()
	var closed := Vector2(120.0, 250.0)
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
	scene._drag_to(CafeRoom.cell_pos(7, 2) + Vector2(10, 10))  # в клетку стола
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
	_click(pos + Vector2(256, 190), true)   # стол: клетки (7..8, 2..3)
	_check(d._sel == table_idx and d._dragging, "нажатие на стол выбирает его")
	_move_to(pos + Vector2(256, 254))
	_click(pos + Vector2(256, 254), false)
	_check(int(GameState.layout[table_idx]["c"]) == 7 and int(GameState.layout[table_idx]["r"]) == 4, "стол перетащен ровно на 2 клетки вниз")
	# в передний ряд (витрина) — нельзя: стол 2×2 в рядах 5–6 не поместится
	_click(pos + Vector2(256, 250), true)
	_move_to(pos + Vector2(256, 300))
	_click(pos + Vector2(256, 300), false)
	_check(int(GameState.layout[table_idx]["r"]) == 4, "в передний ряд (витрина) мебель не ставится")
	# в занятую клетку (к пуфику (6,3)) — отклоняется
	_click(pos + Vector2(256, 250), true)
	_move_to(pos + Vector2(240, 208))
	_click(pos + Vector2(240, 208), false)
	_check(int(GameState.layout[table_idx]["r"]) == 4, "перетаскивание на пуфик отклонено")
	_click(pos + Vector2(20, 10), true)  # пустая стена
	_check(d._sel == -1, "тап по пустому месту снимает выделение")
	d.queue_free()
	await get_tree().process_frame


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
