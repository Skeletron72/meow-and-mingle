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
	await _test_city()
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
	_check(room.check_place("plant", 4, 5) != "", "у двери ставить нельзя")
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


func _test_city() -> void:
	var city := _new_city(true)
	await get_tree().process_frame
	var player: CatWalker = city._player
	var room: CafeRoom = city._room
	_check(city._inside and player.get_parent() == room.actors and player.nav == room, "игра начинается внутри кафе")
	_check(city._indoor.visible and (city._shells["building4"] as Sprite2D).modulate.a < 0.01, "внутри фасад прозрачен, виден интерьер")
	# интерьер лежит ровно в габарите фасада
	var shell: Sprite2D = city._shells["building4"]
	var shell_rect := Rect2(shell.position, shell.texture.get_size() * 2.0)
	var room_rect := Rect2(city._indoor.position, CafeRoom.ROOM_SIZE)
	_check(shell_rect.grow(12).encloses(room_rect) and is_equal_approx(room_rect.end.y, shell_rect.end.y), "интерьер вписан в габарит фасада")
	_check(absf(city._door_x - room_rect.get_center().x) < 1.0, "дверь на улице строго над ковриком у входа")
	# ходьба по залу
	var goal := Vector2i(8, 5)
	_check(player.walk_to(CafeRoom.feet_at(goal)), "путь внутри кафе найден")
	_walk(player)
	_check(player.position == CafeRoom.feet_at(goal), "кот встал ровно в центр клетки")
	player.walk_to(CafeRoom.feet_at(Vector2i(7, 2)))   # клетка стола
	_walk(player)
	_check(not room.is_blocked(player.position), "кот не залез в мебель")
	# стойка -> кнопка смены
	player.walk_to(CafeRoom.feet_at(Vector2i(1, 0)))
	_walk(player)
	city._update_actions()
	_check(city._btn_shift.visible and not city._btn_exit.visible, "у стойки видна кнопка «Смена»")
	# ковёр у двери -> кнопка «Выйти»
	player.walk_to(CafeRoom.feet_at(Vector2i(4, 6)))
	_walk(player)
	city._update_actions()
	_check(city._btn_exit.visible and not city._btn_shift.visible, "у двери видна кнопка «Выйти»")
	# выход на улицу: рентген выключается, интерьер не рисуется
	city._exit_cafe()
	city._xray = 0.0
	city._xray_tween.kill()
	city._apply_daylight()
	_check(not city._inside and not city._indoor.visible, "снаружи интерьер не рисуется")
	_check(is_equal_approx((city._shells["building4"] as Sprite2D).modulate.a, 1.0), "снаружи видно здание")
	_check(player.get_parent() == city._actors and player.nav == city._street_nav, "снаружи кот ходит по тротуару")
	_check(absf(player.position.x - city._door_x) < 1.0, "кот вышел ровно из двери")
	city._update_actions()
	_check(city._btn_enter.visible, "у двери снаружи видна кнопка «Войти»")
	player.walk_to(Vector2(900, 430))
	_walk(player)
	_check(player.position.distance_to(Vector2(900, 430)) < 1.0, "кот прошёл по тротуару")
	city._update_actions()
	_check(not city._btn_enter.visible, "вдали от двери кнопки «Войти» нет")
	city._enter_cafe()
	city._xray = 1.0
	city._xray_tween.kill()
	city._apply_daylight()
	_check(city._inside and city._indoor.visible and player.get_parent() == room.actors, "вошли обратно: интерьер виден")
	_check(GameState.city_inside, "положение (в кафе) запомнено для возврата из других экранов")
	# освещение: ночью улица темнее, окна светятся, внутри светлее
	TimeOfDay.hour = 12.0
	city._apply_daylight()
	var day := city._outdoor.modulate as Color
	TimeOfDay.hour = 23.0
	city._apply_daylight()
	var night := city._outdoor.modulate as Color
	_check(night.v < day.v - 0.3, "ночью улица темнее")
	_check(city._indoor.modulate.v > night.v + 0.2, "ночью в кафе светлее, чем на улице")
	var lit := 0.0
	for g in city._glows:
		lit = maxf(lit, (g["node"] as CanvasItem).modulate.a)
	_check(lit > 0.3, "ночью горят окна и фонари")
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
	# машины
	_check(city._cars.size() >= 3, "по дороге едут машины")
	var x0: float = city._cars[0].position.x
	city._cars[0]._process(0.5)
	_check(not is_equal_approx(city._cars[0].position.x, x0), "машина едет")
	city.queue_free()
	await get_tree().process_frame


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


func _test_city_input() -> void:
	var city := _new_city(true)
	await get_tree().process_frame
	var room: CafeRoom = city._room
	var player: CatWalker = city._player
	for v in city._visitors:   # гости стоят где попало — убираем с места тапов
		v.wander = false
		v.position = CafeRoom.feet_at(Vector2i(9, 1))
	# тап по полу внутри
	var floor_cell := Vector2i(6, 5)
	var wp: Vector2 = room.to_global(CafeRoom.cell_pos(floor_cell.x, floor_cell.y) + Vector2(16, 16))
	_click(_screen_of(city, wp), true)
	_click(_screen_of(city, wp), false)
	_check(player.is_moving(), "тап по полу внутри запускает ходьбу")
	_walk(player)
	_check(player.position == CafeRoom.feet_at(floor_cell), "кот пришёл в клетку тапа")
	# тап по стойке
	var counter_wp: Vector2 = room.to_global(Vector2(40, 70))
	_click(_screen_of(city, counter_wp), true)
	_click(_screen_of(city, counter_wp), false)
	_check(city._pending == "shift" and player.is_moving(), "тап по стойке: кот идёт к ней, чтобы начать смену")
	# тап по коврику у двери
	city._pending = ""
	var door_wp: Vector2 = room.to_global(CafeRoom.cell_pos(4, 6) + Vector2(16, 16))
	_click(_screen_of(city, door_wp), true)
	_click(_screen_of(city, door_wp), false)
	_check(city._pending == "exit", "тап по коврику у двери: кот идёт выходить")
	_walk(player)
	_check(not city._inside, "дошёл до двери и вышел на улицу")
	city._xray = 0.0
	city._xray_tween.kill()
	# тап по дороге-тротуару снаружи
	var out_wp := Vector2(city._door_x - 120.0, 430.0)
	_click(_screen_of(city, out_wp), true)
	_click(_screen_of(city, out_wp), false)
	_check(player.is_moving(), "тап по тротуару снаружи запускает ходьбу")
	_walk(player)
	_check(player.position.distance_to(out_wp) < 1.0, "кот пришёл по тапу на улице")
	# тап по двери кафе
	var door_out := Vector2(city._door_x, 360.0)
	_click(_screen_of(city, door_out), true)
	_click(_screen_of(city, door_out), false)
	_check(city._pending == "enter", "тап по двери кафе: кот идёт входить")
	_walk(player)
	_check(city._inside, "дошёл до двери и вошёл в кафе")
	# пока открыта пауза или смена, тапы не обрабатываются
	city._open_menu()
	var inside_pos := player.position
	_click(_screen_of(city, wp), true)
	_check(player.position == inside_pos and not player.is_moving(), "на паузе тапы по миру игнорируются")
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
	_move_to(pos + Vector2(256, 286))
	_click(pos + Vector2(256, 286), false)
	_check(int(GameState.layout[table_idx]["c"]) == 7 and int(GameState.layout[table_idx]["r"]) == 5, "стол перетащен ровно на 3 клетки вниз")
	# в занятую клетку (к пуфику (6,3)) — отклоняется
	_click(pos + Vector2(256, 300), true)
	_move_to(pos + Vector2(240, 208))
	_click(pos + Vector2(240, 208), false)
	_check(int(GameState.layout[table_idx]["r"]) == 5, "перетаскивание на пуфик отклонено")
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
	for path in [Nav.BREW, Nav.CITY, Nav.DECORATE]:
		_check(ResourceLoader.exists(path), "сцена существует: " + path)
