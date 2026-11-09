extends Node
## Кадры для карточки магазина: богатый прогресс игрока и 8 сцен в разрешении 1080×1920 (ровно ×3 к 360×640).
## Запуск: xvfb-run -a -s "-screen 0 1080x1920x24" godot --path . --rendering-driver opengl3 --resolution 1080x1920 res://tools/store_shots.tscn -- <папка> [ru|en]

var out := ""


func _snap(name: String, wait := 0.6) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


## Игрок середины игры: кафе обставлено, открыты рецепты и добавки, коты в книге, звёзды на уровнях, монеты.
static func rich_progress(max_chapter := 3, many_cats := false, stars := 14) -> void:
	GameState.new_game()
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.suppress_popups = true
	GameState.city_inside = true
	GameState.layout.append({"id": "window", "c": 5, "r": 1, "flip": false})
	for r in Data.repairs:
		if int(r["chapter"]) > max_chapter:
			continue
		GameState.repairs.append(String(r["id"]))
		for e in r["effects"]:
			if String(e["kind"]) in ["furniture", "counter", "unlock", "upgrade", "style"]:
				GameState._apply_effect(e, "")
	GameState.debug_unlock_all()
	GameState.coins = 1280
	GameState.shifts_played = 40
	for i in 26:
		GameState.level_stars[String(Data.levels[i]["id"])] = 7 if i % 3 != 1 else 3
	for k in GameState.unlocks.duplicate():   # в кадрах — только узнаваемые коты (стартовые и Булка), без экзотических раскрасок
		if String(k).begins_with("cat:"):
			GameState.unlocks.erase(k)
	GameState.unlocks.append("cat:bulka")
	var likes := {"pryanik": 31, "tucha": 16, "ryzhik": 9, "bulka": 6}
	if many_cats:
		likes.merge({"suharik": 17, "bayun": 5, "marusya": 12, "dymka": 5}, true)
	for k in likes:
		GameState.cat_progress[k] = {"likes": likes[k]}
		if not (("cat:%s" % k) in GameState.unlocks):
			GameState.unlocks.append("cat:%s" % k)
	GameState.stars_bonus = stars
	Economy.add_booster("patience", 2, "store")
	Economy.add_booster("double_tips", 1, "store")


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	Loc.apply(a[1] if a.size() > 1 else "ru")
	TimeOfDay.set_process(false)
	Weather.set_process(false)
	seed(7)
	# 1–2: смена
	rich_progress()
	var lv: Dictionary = Data.levels[35].duplicate(true)
	lv["types"] = {"rushed": 0.0, "gourmet": 0.0, "courier": 0.0, "critic": 0.0}
	lv.merge({"customers": 14, "interval": [1.4, 1.4], "patience": 180.0, "queue": 3, "riddle": 0.0, "pool": ["mocha", "cappuccino", "iced_latte", "vanilla_raf", "latte", "pumpkin_raf"], "pastry_menu": ["syrniki", "eclair", "croissant"], "pastry": 0.9, "pastry_mods": 0.6, "cool": 0.0}, true)
	var m: Node2D = load(Nav.BREW).instantiate()
	m.level = lv
	add_child(m)
	await get_tree().create_timer(5.5).timeout
	m._cup.fill("mocha", "")
	m._refresh_cup()
	m._points = 420
	m._stats["served"] = 4
	m._refresh_progress()
	await _snap("01_shift", 0.5)
	m.queue_free()
	await get_tree().process_frame
	rich_progress()
	lv["riddle"] = 1.0
	lv["pastry_mods"] = 0.0
	var m2: Node2D = load(Nav.BREW).instantiate()
	m2.level = lv
	add_child(m2)
	await get_tree().create_timer(4.5).timeout
	m2._cup.fill("pumpkin_raf", "croissant")
	m2._refresh_cup()
	m2._points = 560
	m2._stats["served"] = 6
	m2._refresh_progress()
	await _snap("02_riddle", 0.5)
	m2._stats["served"] = 12
	m2._points = 1130
	m2._points_cap = 1300
	m2._points_lost = 100
	m2.shift_earned = 247
	m2._cozy_coins = 18.0
	m2._finish_run()
	await _snap("03_results", 2.2)
	m2.queue_free()
	await get_tree().process_frame
	# 3: кафе в дождь, вечер
	rich_progress()
	TimeOfDay.hour = 18.4
	Weather.force(Weather.Kind.RAIN)
	var c: Node2D = load(Nav.CITY).instantiate()
	add_child(c)
	await _snap("04_cafe_rain", 4.0)
	c.queue_free()
	await get_tree().process_frame
	# 4: ремонт: открыты задачи 3-й главы, звёзд хватает на пару
	rich_progress(1, false, 6)
	TimeOfDay.hour = 12.0
	Weather.force(Weather.Kind.CLEAR)
	var c1: Node2D = load(Nav.CITY).instantiate()
	add_child(c1)
	await get_tree().create_timer(1.2).timeout
	c1._open_repairs()
	await _snap("05_repairs", 1.0)
	c1.queue_free()
	await get_tree().process_frame
	# 5: книга котов
	rich_progress(3, true)
	TimeOfDay.hour = 12.0
	Weather.force(Weather.Kind.CLEAR)
	var c2: Node2D = load(Nav.CITY).instantiate()
	add_child(c2)
	await get_tree().create_timer(1.5).timeout
	c2._open_cat_book()
	await _snap("06_cats", 1.0)
	c2.queue_free()
	await get_tree().process_frame
	# 6: украшение
	rich_progress()
	var d: Node2D = load(Nav.DECORATE).instantiate()
	add_child(d)
	await get_tree().create_timer(0.8).timeout
	d._select(4)
	await _snap("07_decorate", 0.8)
	d.queue_free()
	await get_tree().process_frame
	# 7: снег и фасад (улица)
	rich_progress()
	GameState.city_inside = false
	TimeOfDay.hour = 21.0
	Weather.force(Weather.Kind.SNOW, 0.6, 0.5)
	var c3: Node2D = load(Nav.CITY).instantiate()
	add_child(c3)
	await _snap("08_snow_night", 4.0)
	c3._open_meta("quests")
	await _snap("09_quests", 1.0)
	get_tree().quit()
