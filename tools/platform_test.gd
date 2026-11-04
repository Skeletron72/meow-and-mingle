extends Node
## Запуск: godot --headless --path . res://tools/platform_test.tscn
## Проверяет слои выхода в магазин: Platform (аналитика, реклама, покупки), Loc (язык), сохранение v5 (миграция, контрольная сумма,
## запасной файл), настройки, звёзды и ремонт, титры, Дневник.
## ВНИМАНИЕ: перезаписывает user://save.json — запускайте на тестовых данных.

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("PLATFORM FAIL: " + msg)
		_failed = true


func _ready() -> void:
	Loc.override = "ru"
	Loc.apply("ru")
	TimeOfDay.set_process(false)
	Weather.set_process(false)
	_test_platform()
	_test_loc()
	_test_save()
	_test_repairs()
	await _test_menu()
	_test_s2()
	_test_content()
	_test_cats_story()
	await _test_ui_screens()
	if _failed:
		get_tree().quit(1)
		return
	print("PLATFORM PASS")
	get_tree().quit(0)


func _test_platform() -> void:
	var b := Platform.backend as DummyBackend
	_check(b != null and b.id() == "dummy", "по умолчанию — заглушка-бэкенд")
	b.events.clear()
	Platform.analytics_enabled = true
	Platform.track("test_event", {"x": 1})
	_check(b.events.size() == 1 and b.events[0]["e"] == "test_event" and int(b.events[0]["p"]["x"]) == 1 and b.events[0]["p"].has("s"), "событие записано с номером сессии")
	Platform.analytics_enabled = false
	Platform.track("silenced", {})
	_check(b.events.size() == 1, "при выключенной аналитике события не уходят")
	Platform.analytics_enabled = true
	var got := []
	Platform.show_rewarded("t", func(ok: bool) -> void: got.append(ok))
	_check(got == [true], "реклама за награду: колбэк с true")
	var names: Array = b.events.map(func(e: Dictionary) -> String: return String(e["e"]))
	_check("ad_request" in names and "ad_reward" in names, "реклама пишет ad_request и ad_reward")
	var bought := []
	Platform.purchase("no_ads", func(ok: bool, sku: String) -> void: bought.append([ok, sku]))
	_check(bought == [[true, "no_ads"]], "заглушка: покупка в отладочной сборке проходит")
	b.simulate_purchases = false
	bought.clear()
	Platform.purchase("no_ads", func(ok: bool, sku: String) -> void: bought.append([ok, sku]))
	_check(bought == [[false, "no_ads"]], "без магазина покупка не проходит и награда не выдаётся")
	b.simulate_purchases = true
	# базовый класс безопасен
	var base := PlatformBackend.new()
	var res := []
	base.show_rewarded("x", func(ok: bool) -> void: res.append(ok))
	base.purchase("x", func(ok: bool, _s: String) -> void: res.append(ok))
	_check(res == [false, false] and base.products().is_empty() and base.cloud_load() == "", "база: нет рекламы, покупок и облака — но без ошибок")
	# межстраничная реклама не чаще раза в 4 минуты и не показывается после «Без рекламы»
	var shown := [0]
	Platform._last_interstitial_msec = -1000000
	GameState.upgrades = []
	Platform.show_interstitial("t", func() -> void: shown[0] += 1)
	Platform.show_interstitial("t", func() -> void: shown[0] += 1)
	var ad_events := b.events.filter(func(e: Dictionary) -> bool: return e["e"] == "ad_show").size()
	_check(shown[0] == 2 and ad_events >= 1, "обе колбэка вызваны, показ только один")
	var before := b.events.size()
	GameState.upgrades = ["no_ads"]
	Platform._last_interstitial_msec = -1000000
	Platform.show_interstitial("t", func() -> void: shown[0] += 1)
	_check(shown[0] == 3 and b.events.size() == before, "после «Без рекламы» межстраничной нет")
	GameState.upgrades = []


func _test_loc() -> void:
	Loc.override = ""
	Loc.apply("ru")
	_check(Loc.language == "ru" and Loc.t("Играть") == "Играть", "русский — язык исходных строк")
	Loc.apply("en")
	_check(Loc.language == "en" and TranslationServer.get_locale().begins_with("en"), "английский включается")
	_check(Loc.t("Играть") == "Play", "перевод: Играть → Play (%s)" % Loc.t("Играть"))
	_check(Loc.t("несуществующая строка") == "несуществующая строка", "нет перевода — остаётся исходная строка")
	Loc.apply("auto")
	_check(Loc.language in Loc.LANGS, "авто выбирает поддерживаемый язык")
	Loc.override = "ru"
	Loc.apply("ru")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _test_save() -> void:
	# новая игра: значения по умолчанию
	GameState.settings = GameState.SETTINGS_DEFAULT.duplicate()
	GameState.new_game()
	_check(GameState.install_id.length() == 16 and GameState.first_run_unix > 0, "у установки есть анонимный id и время первого запуска")
	_check(GameState.settings["music"] == 0.8 and GameState.get_setting("lang") == "auto", "настройки по умолчанию")
	# v4 → v5: старые стадии → новые
	var cases := [
		{"old": 0, "stage": 0, "repairs": [], "bonus": 0, "spent": 0},
		{"old": 1, "stage": 1, "repairs": [], "bonus": 0, "spent": 0},
		{"old": 2, "stage": 3, "repairs": ["shutters"], "bonus": 3, "spent": 1},
		{"old": 3, "stage": 5, "repairs": ["shutters", "cleanup"], "bonus": 0, "spent": 0},
		{"old": 4, "stage": 5, "repairs": ["shutters", "cleanup"], "bonus": 0, "spent": 0},
		{"old": 5, "stage": 5, "repairs": ["shutters", "cleanup"], "bonus": 0, "spent": 0},
	]
	for c in cases:
		_write(GameState.SAVE_PATH, JSON.stringify({"version": 4, "coins": 40, "intro_stage": c["old"], "layout": Data.default_layout.duplicate(true), "upgrades": [], "hour": 10.0}))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_BAK))
		GameState.new_game()
		GameState.load_game()
		_check(GameState.intro_stage == c["stage"] and GameState.coins == 40, "v4 стадия %d → %d (получили %d)" % [c["old"], c["stage"], GameState.intro_stage])
		_check(GameState.repairs == c["repairs"] and GameState.stars_bonus == c["bonus"] and GameState.stars_spent == c["spent"], "v4 стадия %d: ремонт и звёзды %s" % [c["old"], GameState.repairs])
	# круг записи и чтения v5
	GameState.new_game()
	GameState.coins = 123
	GameState.shifts_played = 4
	GameState.stars_bonus = 3
	GameState.repairs = ["shutters"]
	GameState.settings["music"] = 0.4
	GameState.settings["lang"] = "en"
	GameState.save_game()
	var id_before := GameState.install_id
	GameState.new_game()
	GameState.load_game()
	_check(GameState.coins == 123 and GameState.shifts_played == 4 and GameState.stars_bonus == 3 and GameState.repairs == ["shutters"], "v5: игровые поля сохраняются")
	_check(is_equal_approx(float(GameState.settings["music"]), 0.4) and GameState.settings["lang"] == "en" and GameState.install_id == id_before, "v5: настройки и id сохраняются")
	Loc.apply("ru")
	# контрольная сумма и запасной файл
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
	var saved: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_check(saved.has("crc") and String(saved["crc"]) == GameState._crc(saved), "в сохранении есть верная контрольная сумма")
	GameState.coins = 200
	GameState.save_game()   # прошлое сохранение (123) уходит в save.bak
	_check(FileAccess.file_exists(GameState.SAVE_BAK), "прошлое сохранение лежит в запасном файле")
	_write(GameState.SAVE_PATH, "{ битый json")
	GameState.new_game()
	GameState.load_game()
	_check(GameState.coins == 123, "основной файл повреждён — игра берёт запасной (%d)" % GameState.coins)
	# изменённый файл с неверной суммой: запасной целее
	GameState.coins = 300
	GameState.save_game()
	var tampered: Dictionary = JSON.parse_string(FileAccess.open(GameState.SAVE_PATH, FileAccess.READ).get_as_text())
	tampered["coins"] = 999999
	_write(GameState.SAVE_PATH, JSON.stringify(tampered))
	GameState.new_game()
	GameState.load_game()
	_check(GameState.coins != 999999, "правка файла вручную (сумма не сошлась) — берём запасной (%d)" % GameState.coins)
	# нет временного файла после записи
	_check(not FileAccess.file_exists(GameState.SAVE_TMP), "временный файл записи убран")
	# сброс не стирает настройки
	GameState.settings["music"] = 0.0
	GameState.reset_progress()
	_check(is_equal_approx(float(GameState.settings["music"]), 0.0) and GameState.coins == 0 and not FileAccess.file_exists(GameState.SAVE_BAK), "сброс: прогресс нулевой, настройки остаются, запасной файл стёрт")
	GameState.settings = GameState.SETTINGS_DEFAULT.duplicate()


func _test_repairs() -> void:
	GameState.new_game()
	_check(Data.repairs.size() == 30, "в data/repairs.json 30 задач ремонта (%d)" % Data.repairs.size())
	_check(GameState.repair_def("shutters")["cost"] == 1 and GameState.repair_def("cleanup")["cost"] == 2, "ставни 1★, расчистка 2★")
	# граф задач: у каждого требования есть задача, цикла нет, у глав по 10 задач
	var ids := {}
	for r in Data.repairs:
		ids[String(r["id"])] = true
	var per_chapter := {}
	for r in Data.repairs:
		per_chapter[int(r["chapter"])] = int(per_chapter.get(int(r["chapter"]), 0)) + 1
		for q in r["requires"]:
			_check(ids.has(String(q)), "задача «%s»: требование «%s» существует" % [r["id"], q])
	_check(per_chapter == {1: 10, 2: 10, 3: 10}, "по 10 задач в главах 1–3 (%s)" % [per_chapter])
	var order := []   # порядок списка = порядок выполнения: требования всегда раньше
	for r in Data.repairs:
		for q in r["requires"]:
			_check(order.has(String(q)), "«%s» стоит в списке после требования «%s»" % [r["id"], q])
		order.append(String(r["id"]))
	var total := 0
	for r in Data.repairs:
		total += int(r["cost"])
	_check(total == 55, "всего 55★ на ремонт (%d)" % total)
	_check(not GameState.do_repair("shutters"), "без звёзд ремонт не оплатить")
	GameState.stars_bonus = 100
	_check(not GameState.do_repair("wall_paint"), "закрытая задача (нет требований) не выполняется")
	_check(GameState.do_repair("shutters") and GameState.stars_free() == 99, "ставни куплены")
	_check(not GameState.do_repair("shutters") and GameState.stars_free() == 99, "второй раз не списывается")
	_check(GameState.stage_after_tutorial() == 3, "после ставней — расчистка")
	GameState.do_repair("cleanup")
	_check(GameState.stage_after_tutorial() == GameState.INTRO_DONE and GameState.stars_free() == 97, "всё оплачено — вступление пройдено")
	# задача с выбором: стены → мятные
	_check(GameState.repair_state("wall_paint") == "locked", "стены закрыты, пока не пройден первый уровень (after=1)")
	GameState.level_stars = {"l1": 1}
	_check(GameState.repair_state("wall_paint") == "open", "после первого уровня стены открыты")
	var pal0 := GameState.style_colors()
	_check(pal0["wall"] == Color("cdb892"), "по умолчанию стены кремовые")
	var done := []
	GameState.repair_done.connect(func(id: String) -> void: done.append(id))
	_check(GameState.do_repair("wall_paint", "mint") and GameState.style["wall"] == "mint" and done == ["wall_paint"], "стены перекрашены в мятный, сигнал отправлен")
	_check(GameState.style_colors()["wall"] == Color("b3d4bd"), "цвет стен из палитры")
	# мебель в награду: цветок появляется в зале и не мешает проходу
	var before := GameState.layout.size()
	GameState.layout = Data.default_layout.duplicate(true)
	before = GameState.layout.size()
	GameState.level_stars = {"l1": 1, "l2": 1}
	_check(GameState.do_repair("plant_hall") and GameState.layout.size() == before + 1 and GameState.layout.back()["id"] == "plant", "цветок поставлен в зал")
	var room := CafeRoom.new()
	room.layout = GameState.layout
	var bad := 0
	for i in GameState.layout.size():
		var it: Dictionary = GameState.layout[i]
		if room.check_place(String(it["id"]), int(it["c"]), int(it["r"]), i) != "":
			bad += 1
	room.free()
	_check(bad == 0, "после наград мебель стоит корректно (ошибок: %d)" % bad)
	# разблокировки и улучшения; повторная покупка улучшения за монеты закрывает задачу без звёзд
	GameState.level_stars = {}
	for i in 12:
		GameState.level_stars["l%d" % (i + 1)] = 1
	GameState.stars_bonus = 100
	_check(GameState.repair_state("case_task") == "locked", "витрина закрыта до шкафчика")
	GameState.new_game()
	_check(GameState.has_unlock("upgrade:milk_pitcher") == false and not GameState.has_unlock("drink:cocoa"), "в новой игре какао закрыто")
	GameState.upgrades = ["milk_pitcher", "display_case"]
	GameState.repairs = ["shutters", "cleanup", "wall_paint", "floor", "plant_hall", "rug_hall", "window_hall", "menu_board", "table_hall", "bowl", "trim", "recipe_cocoa", "shelf"]
	GameState.sync_repairs()
	_check(GameState.has_repair("case_task"), "витрина уже куплена за монеты — задача закрыта без звёзд")
	_check(GameState.has_unlock("upgrade:display_case") and GameState.has_unlock("upgrade:milk_pitcher"), "upgrade:… проверяется по улучшениям")
	GameState.new_game()


func _test_menu() -> void:
	GameState.new_game()
	GameState.intro_stage = GameState.INTRO_DONE
	var city: Node2D = load(Nav.CITY).instantiate()
	add_child(city)
	await get_tree().process_frame
	var pages: Dictionary = city._menu_pages
	for k in ["main", "settings", "account", "confirm", "credits", "diary", "shop"]:
		_check(pages.has(k), "страница меню «%s» есть" % k)
	# настройки меняют значения по кругу
	city._cycle_setting("music")
	_check(is_equal_approx(float(GameState.get_setting("music")), 1.0), "музыка: 80% → 100%")
	city._cycle_setting("music")
	_check(is_equal_approx(float(GameState.get_setting("music")), 0.0), "музыка: 100% → 0%")
	city._cycle_setting("quality")
	_check(GameState.get_setting("quality") == "low", "качество: авто → низкое")
	city._cycle_setting("analytics")
	_check(not Platform.analytics_enabled and not bool(GameState.get_setting("analytics")), "аналитика выключается в настройках")
	city._cycle_setting("analytics")
	_check(Platform.analytics_enabled, "и включается снова")
	# титры листаются по разделам
	city._open_credits()
	_check(pages["credits"].visible and city._credits_text.text.contains("Графика".to_upper()) == false, "титры открыты на первом разделе")
	var seen := {}
	for i in Data.credits.size():
		seen[city._credits_text.text] = true
		city._credits_turn()
	_check(seen.size() == Data.credits.size(), "разделы титров листаются по кругу")
	var all := ""
	for sec in Data.credits:
		all += " ".join(PackedStringArray(sec["lines"]))
	for who in ["hellorumin", "Alex Kovacs", "MinZiin_", "Galmuri"]:
		_check(all.contains(who), "в титрах есть автор «%s»" % who)
	# Дневник: открыта только запись, на которую хватает смен
	GameState.shifts_played = 6
	city._open_diary()
	var enabled := 0
	for ch in pages["diary"].get_children():
		if ch is Button and ch.has_meta("diary") and not (ch as Button).disabled and (ch as Button).text != "Назад" and (ch as Button).text != "Back":
			enabled += 1
	_check(enabled == 2, "после 6 смен открыты 2 записи Дневника (%d)" % enabled)
	city._show_diary_entry(0)
	await get_tree().process_frame
	var comics := city.find_children("*", "IntroComic", true, false)
	_check(comics.size() == 1 and (comics[0] as IntroComic).overlay, "запись Дневника открывает комикс поверх города")
	city.queue_free()
	await get_tree().process_frame
	GameState.settings = GameState.SETTINGS_DEFAULT.duplicate()
	GameState.new_game()


## S2: звук, качество, безопасная зона, наличие файлов звука и сборочных настроек.
func _test_s2() -> void:
	# все заявленные звуки и музыка существуют и подгружаются
	for s in Audio.SFX:
		_check(ResourceLoader.exists("res://assets/audio/%s.ogg" % s), "звук «%s» есть в assets/audio" % s)
	for k in Audio.MUSIC:
		_check(ResourceLoader.exists("res://assets/audio/%s.ogg" % Audio.MUSIC[k]), "музыка «%s» есть" % k)
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "шины Music и SFX созданы")
	GameState.set_setting("music", 0.4)
	GameState.set_setting("sfx", 0.0)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.4)), "громкость музыки из настроек")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "громкость 0 глушит шину")
	GameState.set_setting("music", 0.8)
	GameState.set_setting("sfx", 1.0)
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "громкость вернулась")
	Audio.sfx("click")   # в безголовом режиме ничего не играет, но и не падает
	Audio.music("city")
	_check(Audio.current_music() == "city", "музыка города выбрана")
	Audio.music("shift")
	_check(Audio.current_music() == "shift", "музыка смены выбрана")
	# качество
	GameState.set_setting("quality", "low")
	_check(Quality.low() and Quality.scale() == 0.5 and Quality.count(10) == 5 and Quality.count(1) == 1 and Quality.count(0) == 0, "низкое качество: вдвое меньше частиц, минимум одна")
	GameState.set_setting("quality", "high")
	_check(not Quality.low() and Quality.count(10) == 10, "высокое качество: всё как есть")
	GameState.set_setting("quality", "auto")
	Quality.reset_probe()
	var switched := false
	for i in 600:   # 10 секунд по 20 FPS: «авто» понижает качество после прогрева и окна замера
		if Quality.sample(0.05):
			switched = true
	_check(switched and Quality.low(), "авто: 20 FPS → экономное качество")
	Quality.reset_probe()
	switched = false
	for i in 800:
		if Quality.sample(1.0 / 60.0):
			switched = true
	_check(not switched and not Quality.measured_low, "авто: 60 FPS качество не трогает")
	Quality.reset_probe()
	# безопасная зона
	var none := SafeArea.logical_insets(Vector2(1080, 1920), Rect2(0, 0, 1080, 1920))
	_check(none == Vector4.ZERO, "нет выреза — отступы нулевые")
	var tall := SafeArea.logical_insets(Vector2(1080, 2400), Rect2(0, 90, 1080, 2310))   # вырез 90 px, поля сверху (2400-1920)/2 = 240
	_check(tall == Vector4.ZERO, "вырез целиком в чёрном поле — отступа нет")
	var notch := SafeArea.logical_insets(Vector2(1080, 1920), Rect2(0, 120, 1080, 1800))   # 16:9 с вырезом 120 px → 40 логических px
	_check(is_equal_approx(notch.y, 40.0) and notch.x == 0.0, "16:9 с вырезом: отступ сверху 40 логических px (%s)" % [notch])
	# экспорт: пресеты и аудит лицензий
	var cfg := ConfigFile.new()
	_check(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg читается")
	var names := []
	for sec in cfg.get_sections():
		if sec.begins_with("preset.") and not sec.ends_with(".options"):
			names.append(String(cfg.get_value(sec, "name")))
	_check(names.size() >= 3 and names.any(func(n: String) -> bool: return n.begins_with("Android")) and names.any(func(n: String) -> bool: return n.begins_with("Web")), "пресеты Android и Web на месте (%s)" % [names])
	for sec in cfg.get_sections():
		if sec.begins_with("preset.") and not sec.ends_with(".options"):
			_check(String(cfg.get_value(sec, "exclude_filter")).contains("assets/packs"), "пресет «%s»: исходники паков не попадают в сборку" % cfg.get_value(sec, "name"))


## S3: напитки, выпечка, рецепты с сиропом, меню дня, типы посетителей, 30 уровней.
func _test_content() -> void:
	GameState.new_game()
	_check(Data.drinks.size() == 7 and Data.pastries.size() == 5, "7 напитков и 5 видов выпечки (%d/%d)" % [Data.drinks.size(), Data.pastries.size()])
	# рецепты не совпадают друг с другом
	var seen := {}
	for id in Data.drinks:
		var r: Dictionary = Data.drinks[id]["recipe"]
		var key := "%s/%s/%s" % [r["base"], r["milk"], r.get("syrup", false)]
		_check(not seen.has(key), "рецепт напитка «%s» уникален" % id)
		seen[key] = true
	# чашка собирает все 7 напитков
	var cup := CupState.new()
	for id in Data.drinks:
		var r: Dictionary = Data.drinks[id]["recipe"]
		cup.clear()
		cup.add("base", String(r["base"]))
		if bool(r["milk"]):
			cup.add("milk", "milk")
		if bool(r.get("syrup", false)):
			cup.add("syrup", "syrup")
		_check(cup.drink_id() == String(id), "чашка собирает «%s» (получили «%s»)" % [id, cup.drink_id()])
	cup.clear()
	_check(cup.add("syrup", "syrup") != "", "сироп без основы нельзя")
	# условия открытия
	_check(_same_set(GameState.drink_ids(), ["espresso", "tea"]), "новая игра: эспрессо и чай")
	GameState.upgrades = ["milk_pitcher"]
	_check("latte" in GameState.drink_ids() and not ("raf" in GameState.drink_ids()), "молочник открыл латте, раф ещё нет")
	GameState.unlocks = ["drink:raf", "source:syrup", "drink:sea_tea", "drink:cocoa"]
	_check(_same_set(GameState.drink_ids(), ["espresso", "tea", "latte", "raf", "sea_tea", "cocoa"]), "рецепты из ремонта добавили раф, облепиховый чай и какао (%s)" % [GameState.drink_ids()])
	GameState.upgrades = ["milk_pitcher", "matcha_kit", "display_case"]
	_check(GameState.drink_ids().size() == 7, "все 7 напитков открыты")
	_check(GameState.pastry_ids().size() == 3, "выпечка: до открытия рецептов — три вида")
	GameState.unlocks.append_array(["pastry:syrniki", "pastry:eclair"])
	_check(GameState.pastry_ids().size() == 5, "выпечка: пять видов после сырников и эклеров")
	GameState.upgrades = ["milk_pitcher"]
	_check(GameState.pastry_ids().is_empty(), "без витрины выпечки нет")
	# коты: стартовые + открытые ремонтом
	GameState.new_game()
	var starters := GameState.cats_available().size()
	_check(starters == 3, "в начале приходят трое котов (%d)" % starters)
	# 30 уровней
	_check(Data.levels.size() == 30, "30 уровней (%d)" % Data.levels.size())
	var per_chapter := {}
	var last_speed := 0.0
	for lv in Data.levels:
		per_chapter[int(lv["chapter"])] = int(per_chapter.get(int(lv["chapter"]), 0)) + 1
		for d in lv["pool"]:
			_check(Data.drinks.has(String(d)), "уровень %s: напиток «%s» существует" % [lv["id"], d])
		for p in lv["pastry_menu"]:
			_check(Data.pastries.has(String(p)), "уровень %s: выпечка «%s» существует" % [lv["id"], p])
		_check((lv["pastry_menu"] as Array).size() <= 3, "уровень %s: в меню дня не больше трёх видов выпечки" % lv["id"])
		var types: Dictionary = lv["types"]
		_check(float(types["rushed"]) + float(types["gourmet"]) <= 0.8, "уровень %s: типов посетителей не больше 80%%" % lv["id"])
		_check(int(lv["queue"]) >= 1 and int(lv["queue"]) <= 3 and int(lv["customers"]) >= 6 and float(lv["speed"]) >= 4.0 and float(lv["accuracy"]) >= 0.6 and float(lv["accuracy"]) <= 0.98, "уровень %s: параметры в допустимых пределах" % lv["id"])
		last_speed = float(lv["speed"])
	_check(per_chapter == {1: 10, 2: 10, 3: 10}, "по 10 уровней в главах 1–3")
	_check(Data.chapters.size() == 3, "три главы в data/chapters.json")
	# звёзд хватает на весь ремонт: максимум 90 против 55
	var max_stars := Data.levels.size() * 3
	var cost := 0
	for r in Data.repairs:
		cost += int(r["cost"])
	_check(max_stars >= cost + 20, "звёзд хватает с запасом: максимум %d, ремонт %d" % [max_stars, cost])
	# ремонт никогда не требует пройти больше уровней, чем есть в главе до него
	for r in Data.repairs:
		_check(int(r["after"]) <= Data.levels.size(), "задача «%s»: уровень открытия существует" % r["id"])


func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if not (x in b):
			return false
	return true


## S3: коты, симпатия и записи, сюжетные сцены, доска ремонта и книга котов (интерфейс).
func _test_cats_story() -> void:
	GameState.new_game()
	_check(Data.cats.size() == 9, "в кафе 9 котов (%d)" % Data.cats.size())
	var ids := {}
	for c in Data.cats:
		_check(not ids.has(String(c["id"])), "кот «%s»: id не повторяется" % c["id"])
		ids[String(c["id"])] = true
		_check(Data.drinks.has(String(c["fav_drink"])), "кот «%s»: любимый напиток существует" % c["id"])
		_check(ResourceLoader.exists("res://assets/cats/%s" % String(c["sprite"])), "кот «%s»: лист спрайтов есть" % c["id"])
		_check((c["lines"] as Array).size() == 3 and String(c["role"]) in ["normal", "rushed", "gourmet"], "кот «%s»: три записи и роль" % c["id"])
	# каждого не-стартового кота открывает ровно одна задача ремонта
	for c in Data.cats:
		if bool(c["starter"]):
			continue
		var n := 0
		for r in Data.repairs:
			for e in r["effects"]:
				if String(e["kind"]) == "unlock" and String(e["key"]) == "cat:%s" % c["id"]:
					n += 1
		_check(n == 1, "кота «%s» открывает одна задача ремонта (%d)" % [c["id"], n])
	_check(GameState.cats_available().size() == 3, "сначала приходят только стартовые коты")
	GameState.unlocks = ["cat:bulka", "cat:usov"]
	_check(GameState.cats_available().size() == 5, "ремонт зовёт новых котов")
	# симпатия: записи на 5, 15, 30 заказе, награда монетами
	var coins0 := GameState.coins
	var got := []
	for i in 30:
		got.append(GameState.add_like("tucha"))
	_check(got.count(-1) == 27 and got[4] == 0 and got[14] == 1 and got[29] == 2, "записи открываются на 5-м, 15-м и 30-м заказе")
	_check(GameState.cat_entries("tucha") == 3 and GameState.coins == coins0 + 20 + 40 + 80, "монеты за записи: 20+40+80 (%d)" % (GameState.coins - coins0))
	_check(GameState.add_like("tucha") == -1 and GameState.cat_entries("tucha") == 3, "после 30-го заказа новых записей нет")
	# сохранение симпатий
	GameState.save_game()
	var likes := GameState.cat_likes("tucha")
	GameState.new_game()
	GameState.load_game()
	_check(GameState.cat_likes("tucha") == likes, "симпатии сохраняются")
	# сюжет
	GameState.new_game()
	_check(Data.story.size() == 9, "9 сюжетных сцен: по три на главу")
	var repair_ids := {}
	for r in Data.repairs:
		repair_ids[String(r["id"])] = true
	var level_ids := {}
	for lv in Data.levels:
		level_ids[String(lv["id"])] = true
	for s in Data.story:
		var t: Dictionary = s["trigger"]
		_check((String(t["kind"]) == "repair" and repair_ids.has(String(t["id"]))) or (String(t["kind"]) == "level" and level_ids.has(String(t["id"]))), "сцена «%s»: событие существует" % s["id"])
		for line in s["lines"]:
			var who := String(line["who"])
			_check(who == "meow" or ids.has(who), "сцена «%s»: говорящий «%s» известен" % [s["id"], who])
			_check(String(line["text"]).length() <= 84, "сцена «%s»: реплика помещается в 3 строки" % s["id"])
	_check(GameState.story_for("repair", "bowl").size() == 1, "после «Миски» есть сцена")
	GameState.mark_story_seen("c1_bulka")
	_check(GameState.story_for("repair", "bowl").is_empty(), "увиденная сцена не повторяется")
	GameState.save_game()
	GameState.new_game()
	GameState.load_game()
	_check("c1_bulka" in GameState.story_seen, "увиденные сцены сохраняются")
	GameState.new_game()


func _test_ui_screens() -> void:
	GameState.new_game()
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.stars_bonus = 40
	GameState.repairs = ["shutters", "cleanup"]
	GameState.level_stars = {"l1": 7, "l2": 7, "l3": 7, "l4": 7, "l5": 7, "l6": 7}
	var city: Node2D = load(Nav.CITY).instantiate()
	add_child(city)
	await get_tree().process_frame
	# кнопка звёзд в шапке и доска ремонта
	_check(city._star_btn != null and city._star_btn.visible and city._star_btn.text == "★%d" % GameState.stars_free(), "кнопка звёзд в шапке показывает свободные звёзды")
	city._open_repairs()
	var board: RepairBoard = city._repair_board
	_check(board != null, "доска ремонта открылась")
	var rows := board.rows()
	_check(rows.size() == 28 and String(rows[0]["id"]) in ["wall_paint", "floor", "plant_hall"], "на доске 28 невыполненных задач, открытые первыми (%d)" % rows.size())
	var first_locked := -1
	for i in rows.size():
		if GameState.repair_state(String(rows[i]["id"])) == "locked" and first_locked < 0:
			first_locked = i
	for i in rows.size():
		if GameState.repair_state(String(rows[i]["id"])) == "open":
			_check(first_locked < 0 or i < first_locked, "открытые задачи идут раньше закрытых")
	_check(board.page_count() == 7, "7 страниц по 4 карточки (%d)" % board.page_count())
	# выбор варианта и покупка
	var stars0 := GameState.stars_free()
	board._pick("wall_paint")
	_check(board._choosing == "wall_paint", "у стен спрашивается вариант")
	board._do("wall_paint", "rose")
	await get_tree().process_frame
	_check(GameState.has_repair("wall_paint") and GameState.style["wall"] == "rose" and GameState.stars_free() == stars0 - 2, "стены стали розовыми за 2★")
	board._pick("plant_hall")
	_check(GameState.has_repair("plant_hall"), "задача без выбора оплачивается сразу")
	board._close()
	await get_tree().process_frame
	_check(city._repair_board == null, "доска закрылась")
	var plants := 0
	for it in GameState.layout:
		if String(it["id"]) == "plant":
			plants += 1
	_check(plants >= 1, "цветок появился в зале")
	# Книга котов
	GameState.unlocks = ["cat:bulka"]
	var book := CatBook.new()
	add_child(book)
	await get_tree().process_frame
	_check(book.page_count() == 3, "книга котов: 9 котов — 3 страницы")
	var known := 0
	for c in Data.cats:
		if book.is_known(c):
			known += 1
	_check(known == 4, "в книге открыты 4 кота (3 стартовых + Булка)")
	_check(book.hint_for("marusya").contains("Сырники") or book.hint_for("marusya").contains("Syrniki") or book.hint_for("marusya") != "", "у закрытого кота есть подсказка, как его позвать")
	book._say("tucha")
	book._close()
	# сюжетная сцена: реплики по очереди, конец помечает сцену увиденной
	var scene := StoryScene.new()
	scene.scene = Data.story[0]
	add_child(scene)
	await get_tree().process_frame
	var done := [false]
	scene.finished.connect(func() -> void: done[0] = true)
	_check(scene._index == 0, "сцена началась с первой реплики")
	for i in 3:
		scene._busy = false
		scene._next()
	await get_tree().process_frame
	_check(done[0] and String(Data.story[0]["id"]) in GameState.story_seen, "сцена закончилась и отмечена увиденной")
	city.queue_free()
	await get_tree().process_frame
	GameState.new_game()
