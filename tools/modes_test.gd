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


func _test_default_layout() -> void:
	var items: Array[Dictionary] = Data.default_layout.duplicate(true)
	var room := _room_with([])
	for i in items.size():
		var id := String(items[i]["id"])
		var err := room.check_place(id, Vector2(float(items[i]["x"]), float(items[i]["y"])))
		_check(err == "", "расстановка по умолчанию: %s -> %s" % [id, err])
		room.layout.append(items[i])
	room.rebuild()
	var path := room.find_path(CafeRoom.SPAWN_POS, CafeRoom.COUNTER_ZONE.get_center())
	_check(not path.is_empty(), "от двери до стойки есть путь")
	room.queue_free()
	await get_tree().process_frame


func _test_place_rules() -> void:
	var room := _room_with(Data.default_layout.duplicate(true))
	var table := Vector2(264, 340)
	_check(room.check_place("stool", table) != "", "нельзя поставить пуф в стол")
	_check(room.check_place("plant", Vector2(40, 300)) == "", "растение в свободном углу можно")
	_check(room.check_place("plant", Vector2(40, 100)) != "", "растение на стене нельзя")
	_check(room.check_place("window", Vector2(180, 300)) != "", "окно на пол нельзя")
	_check(room.check_place("window", Vector2(60, 100)) != "", "окно поверх стойки нельзя")
	_check(room.check_place("plant", CafeRoom.COUNTER_ZONE.get_center()) != "", "у стойки ставить нельзя")
	_check(room.check_place("plant", CafeRoom.SPAWN_POS) != "", "у двери ставить нельзя")
	_check(room.check_place("plant", Vector2(1000, 300)) != "", "за пределами зала нельзя")
	_check(room.check_place("rug", Vector2(264, 340)) == "", "коврик можно под стол (плоский)")
	# ряд мебели поперёк зала: последний предмет закрыл бы проход — должен быть отклонён именно по этой причине
	var row: Array[Dictionary] = []
	for cx in [55.0, 145.0, 235.0]:
		row.append({"id": "cabinet", "x": cx, "y": 420.0, "flip": false})
	row.append({"id": "machine", "x": 296.5, "y": 420.0, "flip": false})
	var sealed := _room_with(row)
	_check(sealed.find_path(CafeRoom.SPAWN_POS, CafeRoom.COUNTER_ZONE.get_center()).size() > 0, "с зазором в ряду проход есть")
	_check(sealed.check_place("machine", Vector2(329.5, 420.0)) == tr("Не загораживайте проход"), "последний предмет, закрывающий проход, отклонён")
	sealed.queue_free()
	var spot := room.find_free_spot("table_big")
	_check(spot != Vector2.INF and room.check_place("table_big", spot) == "", "find_free_spot находит место")
	room.queue_free()
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
	_check(w._player.position.distance_to(Vector2(60, 480)) < 2.0, "кот пришёл по тапу")
	# тап по стойке: кот идёт к ней и сам открывает готовку
	w.set_process(false)
	_click(Vector2(100, 160), true)
	_click(Vector2(100, 160), false)
	_check(w._auto_enter and w._player.is_moving(), "тап по стойке отправляет кота к стойке")
	w.queue_free()
	await get_tree().process_frame
	# украшение: перетаскивание мышью стола в занятое место и на свободное
	GameState.coins = 0
	var d: Node2D = load(Nav.DECORATE).instantiate()
	add_child(d)
	await get_tree().process_frame
	var table_idx := -1
	for i in GameState.layout.size():
		if GameState.layout[i]["id"] == "table_big":
			table_idx = i
	_click(Vector2(264, 300), true)
	_check(d._sel == table_idx and d._dragging, "нажатие на стол выбирает его")
	_move_to(Vector2(264, 440))
	_click(Vector2(264, 440), false)
	var moved_y := float(GameState.layout[table_idx]["y"])
	_check(moved_y > 380.0, "стол перетащен вниз (y=%s)" % moved_y)
	_click(Vector2(20, 120), true)  # пустая стена
	_check(d._sel == -1, "тап по пустому месту снимает выделение")
	d.queue_free()
	await get_tree().process_frame


func _test_walk() -> void:
	var scene: Node2D = load(Nav.WALK).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var player: CatWalker = scene._player
	var start := player.position
	_check(player.walk_to(Vector2(300, 480)), "путь до точки на полу найден")
	for _i in 600:
		player.step(0.05)
	_check(player.position.distance_to(Vector2(300, 480)) < 2.0 and not player.is_moving(), "кот дошёл до цели")
	_check(player.position != start, "кот сдвинулся")
	# цель внутри стола: кот не должен встать в мебель
	player.walk_to(Vector2(264, 320))
	for _i in 600:
		player.step(0.05)
	_check(not scene._room.is_blocked(player.position), "кот не залез в мебель")
	# идём к стойке — кнопка «Готовить» должна появиться
	player.walk_to(CafeRoom.COUNTER_ZONE.get_center())
	for _i in 800:
		player.step(0.05)
	scene.set_process(true)
	scene._update_interact()
	_check(scene._brew_btn.visible, "у стойки видна кнопка «Готовить»")
	scene.queue_free()
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
	# перетаскивание: растение в занятое место отклоняется
	var idx: int = GameState.layout.size() - 1
	scene._select(idx)
	scene._drag_start = Vector2(float(GameState.layout[idx]["x"]), float(GameState.layout[idx]["y"]))
	scene._drag_off = Vector2.ZERO
	scene._dragging = true
	scene._drag_to(Vector2(264, 340))
	_check(scene._drag_err != "", "перетаскивание в стол отклонено")
	scene._drop()
	_check(is_equal_approx(float(GameState.layout[idx]["x"]), scene._drag_start.x), "позиция вернулась")
	scene._select(idx)
	scene._dragging = true
	scene._drag_start = Vector2(float(GameState.layout[idx]["x"]), float(GameState.layout[idx]["y"]))
	scene._drag_to(Vector2(60, 420))
	_check(scene._drag_err == "", "перетаскивание на свободное место: " + scene._drag_err)
	scene._drop()
	_check(is_equal_approx(float(GameState.layout[idx]["x"]), 60.0), "позиция сохранилась")
	scene._flip_selected()
	_check(bool(GameState.layout[idx]["flip"]), "отзеркаливание")
	scene._remove_selected()
	_check(GameState.layout.size() == n0 and GameState.coins == 100, "продажа возвращает полную цену")
	scene.queue_free()
	await get_tree().process_frame


func _test_save_migration() -> void:
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "coins": 77, "served_total": 3, "cat_progress": {}, "last_visit_unix": 0}))
	f.close()
	GameState.layout = []
	GameState.load_game()
	_check(GameState.coins == 77, "v1: монеты сохранились")
	_check(GameState.layout.size() == Data.default_layout.size(), "v1 -> v2: выдана расстановка по умолчанию")
	GameState.save_game()
	GameState.layout = []
	GameState.load_game()
	_check(GameState.layout.size() == Data.default_layout.size(), "v2: расстановка сохраняется и читается")
	# мусор в сохранении
	f = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 2, "coins": 1, "layout": [{"id": "нет_такого", "x": 1, "y": 1}, {"id": "stool", "x": 100, "y": 300}, 5]}))
	f.close()
	GameState.load_game()
	_check(GameState.layout.size() == 1 and GameState.layout[0]["id"] == "stool", "неизвестная мебель отбрасывается")


func _test_menu() -> void:
	var menu: Node2D = load(Nav.MENU).instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check(menu._first_button != null and menu._first_button.text == "Играть", "меню построено")
	menu.queue_free()
	for path in [Nav.BREW, Nav.WALK, Nav.DECORATE]:
		_check(ResourceLoader.exists(path), "сцена существует: " + path)
