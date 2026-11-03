extends Node
## Запуск: godot --headless --path . res://tools/modes_test.tscn
## Проверяет меню, прогулку по кафе и режим украшения (логика без отрисовки).
## ВНИМАНИЕ: перезаписывает user://save.json — запускайте на тестовых данных.

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("MODES FAIL: " + msg)
		_failed = true


func _ready() -> void:
	_test_texts_fit()
	await _test_default_layout()
	await _test_place_rules()
	await _test_walk()
	await _test_input()
	await _test_decorate()
	_test_save_migration()
	await _test_menu()
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


## Подписи не должны вылезать за карточки и кнопки (шрифт — пиксельный, ширина фиксирована).
func _test_texts_fit() -> void:
	for id in Data.furniture:
		var w := Ui.FONT_NARROW.get_string_size(String(Data.furniture[id]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
		_check(w <= 90.0, "название «%s» не влезает в карточку (%s px)" % [Data.furniture[id]["name"], w])
	for t in {"Зеркало": 116.0, "Убрать": 108.0, "Готово": 116.0}:
		var w2 := Ui.FONT_NARROW.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
		_check(w2 + 36.0 + 8.0 <= {"Зеркало": 116.0, "Убрать": 108.0, "Готово": 116.0}[t], "«%s» не влезает в кнопку панели (%s px)" % [t, w2])
	var menu_w: float = ThemeDB.fallback_font.get_string_size("Прогулка по кафе", HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
	var font := (load("res://assets/ui/theme.tres") as Theme).default_font
	menu_w = font.get_string_size("Прогулка по кафе", HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
	_check(menu_w + 36.0 + 16.0 <= 300.0, "«Прогулка по кафе» не влезает в кнопку меню (%s px)" % menu_w)
	# шрифты содержат всю кириллицу (включая О, П, Ё)
	for ch in "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя":
		_check(font.has_char(ch.unicode_at(0)) and Ui.FONT_NARROW.has_char(ch.unicode_at(0)), "в шрифте нет буквы " + ch)


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
		var area := CafeRoom.cells(String(id), 2, 3)
		var rect := CafeRoom.sprite_rect(String(id), 2, 3)
		var top := CafeRoom.cell_pos(2, 3, CafeRoom.is_wall(String(id)))
		var foot_x := top.x + area.size.x * CafeRoom.T / 2.0
		_check(absf(rect.get_center().x - foot_x) <= CafeRoom.S, "%s: центр спрайта уехал от центра клеток больше чем на пиксель арта" % id)
		if not CafeRoom.is_flat(String(id)):
			_check(is_equal_approx(rect.end.y, top.y + area.size.y * CafeRoom.T), "%s: низ спрайта не по низу клеток" % id)
		_check(rect.size.x <= area.size.x * CafeRoom.T and fmod(rect.position.x, 2.0) == 0.0, "%s: спрайт шире клеток или сдвинут на пол-пикселя арта" % id)


func _test_place_rules() -> void:
	_test_grid_alignment()
	var room := _room_with(Data.default_layout.duplicate(true))
	_check(room.check_place("stool", 7, 4) != "", "нельзя поставить пуф в стол")
	_check(room.check_place("plant", 1, 3) == "", "растение в свободной клетке можно")
	_check(room.check_place("plant", 10, 3) != "", "за краем зала нельзя")
	_check(room.check_place("plant", 1, 0) != "", "у стойки ставить нельзя")
	_check(room.check_place("plant", 4, 8) != "", "у двери ставить нельзя")
	_check(room.check_place("window", 0, 3) != "", "окно поверх стойки нельзя")
	_check(room.check_place("window", 6, 3) != "", "окно на окно нельзя")
	_check(room.check_place("window", 4, 0) != "", "в верхний ряд стены (под HUD) вешать нельзя")
	_check(room.check_place("window", 4, 4) == "", "окно на свободной стене можно")
	_check(room.check_place("rug", 7, 4) == "", "коврик можно под стол (плоский)")
	# ряд мебели поперёк зала: последний предмет закрыл бы проход — должен быть отклонён именно по этой причине
	var row: Array[Dictionary] = []
	for c in [0, 2, 4, 6]:
		row.append(_item("cabinet", c, 5))
	row.append(_item("machine", 8, 5))
	var sealed := _room_with(row)
	_check(not sealed.find_path(CafeRoom.feet_at(CafeRoom.SPAWN_CELL), CafeRoom.feet_at(Vector2i(1, 0))).is_empty(), "с зазором в ряду проход есть")
	_check(sealed.check_place("machine", 9, 5) == tr("Не загораживайте проход"), "последний предмет, закрывающий проход, отклонён")
	sealed.queue_free()
	var spot := room.find_free_spot("table_big")
	_check(spot.x >= 0 and room.check_place("table_big", spot.x, spot.y) == "", "find_free_spot находит место")
	room.queue_free()
	await get_tree().process_frame


func _test_walk() -> void:
	var scene: Node2D = load(Nav.WALK).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var player: CatWalker = scene._player
	var start := player.position
	var goal := Vector2i(8, 8)
	_check(player.walk_to(CafeRoom.feet_at(goal)), "путь до клетки найден")
	for _i in 600:
		player.step(0.05)
	_check(player.position == CafeRoom.feet_at(goal) and not player.is_moving(), "кот встал ровно в центр клетки")
	_check(player.position != start, "кот сдвинулся")
	# цель внутри стола: кот не должен встать в мебель
	player.walk_to(Vector2(270, 350))
	for _i in 600:
		player.step(0.05)
	_check(not scene._room.is_blocked(player.position), "кот не залез в мебель")
	# идём к стойке — кнопка «Готовить» должна появиться
	player.walk_to(CafeRoom.feet_at(Vector2i(1, 0)))
	for _i in 800:
		player.step(0.05)
	scene.set_process(true)
	scene._update_interact()
	_check(scene._brew_btn.visible, "у стойки видна кнопка «Готовить»")
	scene.queue_free()
	await get_tree().process_frame


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


func _test_input() -> void:
	# прогулка: тап по полу ведёт кота
	GameState.layout = Data.default_layout.duplicate(true)
	var w: Node2D = load(Nav.WALK).instantiate()
	add_child(w)
	await get_tree().process_frame
	for c in w._ambient:  # гуляющие коты стоят где попало — убираем с места тапа
		c.wander = false
		c.position = Vector2(300, 250)
	_click(Vector2(60, 480), true)
	_click(Vector2(60, 480), false)
	_check(w._player.is_moving(), "тап по полу запускает ходьбу")
	for _i in 600:
		w._player.step(0.05)
	_check(w._player.position == CafeRoom.feet_at(CafeRoom.cell_at(Vector2(60, 480))), "кот пришёл в клетку тапа")
	# тап по стойке: кот идёт к ней и сам открывает готовку
	w.set_process(false)
	_click(Vector2(60, 170), true)
	_click(Vector2(60, 170), false)
	_check(w._auto_enter and w._player.is_moving(), "тап по стойке отправляет кота к стойке")
	w.queue_free()
	await get_tree().process_frame
	# украшение: перетаскивание стола мышью по клеткам
	GameState.coins = 0
	var d: Node2D = load(Nav.DECORATE).instantiate()
	add_child(d)
	await get_tree().process_frame
	var table_idx := -1
	for i in GameState.layout.size():
		if GameState.layout[i]["id"] == "table_big":
			table_idx = i
	_click(Vector2(276, 350), true)
	_check(d._sel == table_idx and d._dragging, "нажатие на стол выбирает его")
	_move_to(Vector2(276, 446))
	_click(Vector2(276, 446), false)
	_check(int(GameState.layout[table_idx]["r"]) == 7 and int(GameState.layout[table_idx]["c"]) == 7, "стол перетащен ровно на 3 клетки вниз")
	# в занятую клетку (к пуфику) — отклоняется, стол остаётся
	_click(Vector2(276, 446), true)
	_move_to(Vector2(254, 362))  # клетка (7,5): стол (смещение -1) встал бы на пуфик (6,5)
	_click(Vector2(254, 362), false)
	_check(int(GameState.layout[table_idx]["r"]) == 7, "перетаскивание на пуфик отклонено")
	_click(Vector2(20, 120), true)  # пустая стена
	_check(d._sel == -1, "тап по пустому месту снимает выделение")
	d.queue_free()
	await get_tree().process_frame


func _test_decorate() -> void:
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
	scene._drag_to(CafeRoom.cell_pos(7, 4) + Vector2(10, 10))  # в клетку стола
	_check(scene._drag_err != "", "перетаскивание в стол отклонено")
	scene._drop()
	_check(Vector2i(int(GameState.layout[idx]["c"]), int(GameState.layout[idx]["r"])) == scene._drag_start, "позиция вернулась")
	scene._select(idx)
	scene._dragging = true
	scene._drag_to(CafeRoom.cell_pos(1, 6) + Vector2(10, 10))
	_check(scene._drag_err == "", "перетаскивание на свободное место: " + scene._drag_err)
	scene._drop()
	_check(int(GameState.layout[idx]["c"]) == 1 and int(GameState.layout[idx]["r"]) == 6, "позиция сохранилась")
	scene._flip_selected()
	_check(bool(GameState.layout[idx]["flip"]), "отзеркаливание")
	scene._remove_selected()
	_check(GameState.layout.size() == n0 and GameState.coins == 100, "продажа возвращает полную цену")
	scene.queue_free()
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
	# v3 читается и пишется без потерь
	GameState.save_game()
	GameState.layout = []
	GameState.load_game()
	_check(GameState.layout.size() == Data.default_layout.size(), "v3: расстановка сохраняется и читается")
	# мусор: неизвестный id, дубликат на той же клетке, выход за зал, не словарь
	_write_save({"version": 3, "coins": 1, "layout": [
		{"id": "нет_такого", "c": 1, "r": 1}, {"id": "stool", "c": 1, "r": 6}, {"id": "stool", "c": 1, "r": 6},
		{"id": "table_big", "c": 9, "r": 9}, 5]})
	GameState.load_game()
	_check(GameState.layout.size() == 1 and GameState.layout[0]["id"] == "stool", "битая мебель отбрасывается (осталось %d)" % GameState.layout.size())


func _test_menu() -> void:
	var menu: Node2D = load(Nav.MENU).instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check(menu._first_button != null and menu._first_button.text == "Играть", "меню построено")
	menu.queue_free()
	for path in [Nav.BREW, Nav.WALK, Nav.DECORATE]:
		_check(ResourceLoader.exists(path), "сцена существует: " + path)
