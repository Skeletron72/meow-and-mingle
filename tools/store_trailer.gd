extends Node
## Запись трейлера из самой игры (Godot Movie Maker): 1080×1920, 30 к/с, ~27 с геймплея без подписей (подписи и финальную плашку добавляет tools/make_trailer.sh).
## Запуск: xvfb-run -a -s "-screen 0 1080x1920x24" godot --path . --rendering-driver opengl3 --resolution 1080x1920 --write-movie <файл>.avi --fixed-fps 30 res://tools/store_trailer.tscn

const Shots := preload("res://tools/store_shots.gd")


func _mark(name: String) -> void:
	print("MARK %s %.2f" % [name, float(Engine.get_frames_drawn()) / 30.0])


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


## Собирает заказ по рецепту так, как это делает игрок: ингредиенты по одному на поднос, начинки на выпечку — в правую половину.
func _make(m: Node2D, order: Dictionary) -> void:
	var tp: Vector2 = m._tray.position
	var r: Dictionary = Data.drinks[String(order["drink"])]["recipe"]
	m._add_ingredient("base", String(r["base"]), tp)
	await _wait(0.5)
	for mod in r.get("mods", []):
		if String(mod) == "cocoa":
			m._add_ingredient("base", "cocoa", tp)
			await _wait(0.4)
	if bool(r["milk"]):
		m._add_ingredient("milk", "milk", tp)
		await _wait(0.45)
	if bool(r.get("syrup", false)):
		m._add_ingredient("syrup", "syrup", tp)
		await _wait(0.45)
	for mod in r.get("mods", []):
		if String(mod) in ["ice", "cinnamon", "cream"]:
			m._add_ingredient("extra", String(mod), tp)
			await _wait(0.4)
	if String(order["pastry"]) != "":
		m._add_ingredient("pastry", String(order["pastry"]), tp)
		await _wait(0.45)
		for mod in order.get("pastry_mods", []):
			m._add_ingredient("syrup" if String(mod) == "syrup" else "extra", String(mod), tp + Vector2(40, 0))
			await _wait(0.4)


func _ready() -> void:
	get_window().size = Vector2i(1080, 1920)   # пиксель игры ровно ×3
	await get_tree().process_frame
	await get_tree().process_frame
	Loc.apply("ru")
	TimeOfDay.set_process(false)
	Weather.set_process(false)
	seed(11)
	# A. фасад ночью, снег (4 с)
	Shots.rich_progress(3, false)
	GameState.city_inside = false
	TimeOfDay.hour = 21.0
	Weather.force(Weather.Kind.SNOW, 0.6, 0.5)
	var c: Node2D = load(Nav.CITY).instantiate()
	add_child(c)
	_mark("A_facade")
	await _wait(3.0)
	c.queue_free()
	await get_tree().process_frame
	# B. уютный зал в дождь, коты ходят (5 с)
	Shots.rich_progress(3, false)
	TimeOfDay.hour = 18.4
	Weather.force(Weather.Kind.RAIN)
	var c2: Node2D = load(Nav.CITY).instantiate()
	add_child(c2)
	_mark("B_cafe")
	await _wait(4.0)
	c2.queue_free()
	await get_tree().process_frame
	# C. смена: четыре заказа руками «игрока» (12 с)
	Shots.rich_progress(3, false)
	TimeOfDay.hour = 12.0
	Weather.force(Weather.Kind.CLEAR)
	var lv: Dictionary = Data.levels[35].duplicate(true)
	lv.merge({"customers": 5, "interval": [1.5, 1.5], "patience": 300.0, "queue": 3, "riddle": 0.0, "wave": 0.0, "cool": 0.0, "speed": 14.0,
		"types": {"rushed": 0.0, "gourmet": 0.0, "courier": 0.0, "critic": 0.0}, "pool": ["mocha", "cappuccino", "vanilla_raf", "latte", "iced_latte"],
		"pastry_menu": ["syrniki", "eclair", "croissant"], "pastry": 0.8, "pastry_mods": 0.5}, true)
	var m: Node2D = load(Nav.BREW).instantiate()
	m.level = lv
	add_child(m)
	_mark("C_shift")
	await _wait(3.2)   # гости пришли
	for i in 2:
		var e: Dictionary = m._front()
		if e.is_empty():
			await _wait(0.5)
			continue
		await _make(m, e["order"])
		await _wait(0.4)
		m._serve(e)
		await _wait(1.6)
	# D. итоги (4 с)
	m._points = 1180
	m._points_cap = 1300
	m._points_lost = 100
	m._stats["served"] = 12
	m.shift_earned = 247
	m._cozy_coins = 18.0
	_mark("D_results")
	m._finish_run()
	await _wait(3.6)
	m.queue_free()
	await get_tree().process_frame
	# E. коты (2,5 с) и украшение (2,5 с)
	Shots.rich_progress(3, true)
	TimeOfDay.hour = 12.0
	var c3: Node2D = load(Nav.CITY).instantiate()
	add_child(c3)
	await _wait(1.0)
	_mark("E_cats")
	c3._open_cat_book()
	await _wait(2.2)
	c3.queue_free()
	await get_tree().process_frame
	Shots.rich_progress(3, false)
	var d: Node2D = load(Nav.DECORATE).instantiate()
	add_child(d)
	await _wait(0.8)
	d._select(4)
	_mark("F_decor")
	await _wait(2.2)
	_mark("END")
	get_tree().quit()
