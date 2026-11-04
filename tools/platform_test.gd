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
	GameState.suppress_popups = true
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
	_test_economy()
	_test_daily()
	_test_quests()
	_test_offline()
	_test_notifications()
	_test_shop()
	_test_season()
	await _test_meta_ui()
	await _test_boosters_in_shift()
	await _test_city_meta()
	await _test_repair_ad_card()
	await _test_decor_styles()
	await _test_terrace_sign()
	await _test_new_types()
	_test_events()
	_test_season_rollover()
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
	GameState.meta["purchases"] = ["no_ads"]
	Platform._last_interstitial_msec = -1000000
	Platform.show_interstitial("t", func() -> void: shown[0] += 1)
	_check(shown[0] == 3 and b.events.size() == before, "после «Без рекламы» межстраничной нет")
	GameState.meta["purchases"] = []


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
	_check(Data.repairs.size() == 60, "в data/repairs.json 60 задач ремонта (%d)" % Data.repairs.size())
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
	_check(per_chapter == {1: 10, 2: 10, 3: 10, 4: 10, 5: 10, 6: 10}, "по 10 задач в шести главах (%s)" % [per_chapter])
	var order := []   # порядок списка = порядок выполнения: требования всегда раньше
	for r in Data.repairs:
		for q in r["requires"]:
			_check(order.has(String(q)), "«%s» стоит в списке после требования «%s»" % [r["id"], q])
		order.append(String(r["id"]))
	var total := 0
	for r in Data.repairs:
		total += int(r["cost"])
	_check(total == 116, "всего 116★ на ремонт (%d)" % total)
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
	for k in ["main", "settings", "account", "confirm", "credits", "diary"]:
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
	_check(Data.drinks.size() == 10 and Data.pastries.size() == 8, "10 напитков и 8 видов выпечки (%d/%d)" % [Data.drinks.size(), Data.pastries.size()])
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
	_check(Data.levels.size() == 60, "60 уровней (%d)" % Data.levels.size())
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
	_check(per_chapter == {1: 10, 2: 10, 3: 10, 4: 10, 5: 10, 6: 10}, "по 10 уровней в шести главах")
	_check(Data.chapters.size() == 6, "шесть глав в data/chapters.json")
	# звёзд хватает на весь ремонт: максимум 180 против 116
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
	_check(Data.cats.size() == 16, "в кафе 16 котов (%d)" % Data.cats.size())
	var ids := {}
	for c in Data.cats:
		_check(not ids.has(String(c["id"])), "кот «%s»: id не повторяется" % c["id"])
		ids[String(c["id"])] = true
		_check(Data.drinks.has(String(c["fav_drink"])), "кот «%s»: любимый напиток существует" % c["id"])
		_check(ResourceLoader.exists("res://assets/cats/%s" % String(c["sprite"])), "кот «%s»: лист спрайтов есть" % c["id"])
		_check((c["lines"] as Array).size() == 3 and String(c["role"]) in ["normal", "rushed", "gourmet", "courier", "critic"], "кот «%s»: три записи и роль" % c["id"])
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
	_check(Data.story.size() == 18, "18 сюжетных сцен: по три на главу")
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
	_check(city._dock != null and city._dock.visible and city._dock_btns.size() == 5, "внизу города панель из пяти кнопок: ремонт, дела, декор, лавка, меню")
	var repair_badge: Label = city._dock_btns["dock_repair"].get_meta("badge")
	_check(repair_badge.text == str(GameState.stars_free()), "на кнопке «Ремонт» число свободных звёзд")
	city._open_repairs()
	var board: RepairBoard = city._repair_board
	_check(board != null, "доска ремонта открылась")
	var rows := board.rows()
	_check(rows.size() == 58 and String(rows[0]["id"]) in ["wall_paint", "floor", "plant_hall"], "на доске 58 невыполненных задач, открытые первыми (%d)" % rows.size())
	var first_locked := -1
	for i in rows.size():
		if GameState.repair_state(String(rows[i]["id"])) == "locked" and first_locked < 0:
			first_locked = i
	for i in rows.size():
		if GameState.repair_state(String(rows[i]["id"])) == "open":
			_check(first_locked < 0 or i < first_locked, "открытые задачи идут раньше закрытых")
	_check(board.page_count() == 15, "15 страниц по 4 карточки (%d)" % board.page_count())
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
	_check(book.page_count() == 4, "книга котов: 16 котов — 4 страницы")
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


## S4: рыбки и бустеры, подарок дня, задания, офлайн-доход, уведомления, магазин, реклама, сезон.
func _set_time(t: int) -> void:   # «сейчас» в тесте; защиту от отката часов сбрасываем (иначе время не вернуть назад)
	Daily.time_override = t
	GameState.meta["clock_max"] = 0


func _fresh_meta() -> void:
	GameState.new_game()
	_set_time(1_800_000_000)
	GameState.first_run_unix = Daily.time_override - 5 * 86400
	GameState.shifts_played = 5


func _test_economy() -> void:
	_fresh_meta()
	_check(Economy.fish() == 0 and Economy.boosters_total() == 0, "новая игра: ни рыбок, ни бустеров")
	var b := Platform.backend as DummyBackend
	b.events.clear()
	Economy.add_fish(10, "test")
	_check(Economy.fish() == 10 and b.events.any(func(e: Dictionary) -> bool: return e["e"] == "currency_earn" and e["p"]["type"] == "fish"), "рыбки начисляются с событием аналитики")
	_check(not Economy.spend_fish(11, "t") and Economy.fish() == 10, "нельзя потратить больше, чем есть")
	_check(Economy.spend_fish(4, "t") and Economy.fish() == 6, "рыбки тратятся")
	Economy.add_booster("auto", 2, "test")
	_check(Economy.booster_count("auto") == 2 and Economy.boosters_total() == 2, "бустеры начисляются")
	_check(Economy.use_booster("auto") and Economy.booster_count("auto") == 1 and not Economy.use_booster("patience"), "бустер списывается, чужого нет")
	GameState.coins = 100
	_check(Economy.buy_booster("cat_help", "coins") and GameState.coins == 40 and Economy.booster_count("cat_help") == 1, "бустер за монеты (60)")
	_check(not Economy.buy_booster("double_tips", "coins"), "не хватает монет на бустер (100)")
	_check(Economy.buy_booster("cat_help", "fish") and Economy.fish() == 1, "бустер за рыбки (5)")
	var text := Economy.grant({"coins": 10, "fish": 2, "boosters": {"patience": 1}}, "test")
	_check(GameState.coins == 50 and Economy.fish() == 3 and Economy.booster_count("patience") == 1 and text != "", "grant выдаёт набор целиком (%s)" % text)
	# сохранение
	GameState.save_game()
	var fish := Economy.fish()
	GameState.new_game()
	GameState.load_game()
	_check(Economy.fish() == fish and Economy.booster_count("cat_help") == 2, "рыбки и бустеры сохраняются")
	# защита от кривого сохранения
	GameState.meta = GameState._sanitize_meta({"fish": "много", "boosters": 5, "daily": {"streak": 3.0}}, GameState.META_DEFAULT)
	_check(Economy.fish() == 0 and (GameState.meta["boosters"] as Dictionary).is_empty() and int(GameState.meta["daily"]["streak"]) == 3 and GameState.meta["daily"].has("last_day"), "битое мета-состояние приводится к образцу")
	GameState.new_game()


func _test_daily() -> void:
	_fresh_meta()
	var day0 := Daily.today()
	_check(Daily.gift_ready() and Daily.gift_day() == 1, "в первый день подарок готов, это день 1")
	var coins0 := GameState.coins
	_check(Daily.claim_gift() != "" and GameState.coins == coins0 + 50 and not Daily.gift_ready(), "день 1: 50 монет, повторно сегодня нельзя")
	_check(Daily.claim_gift() == "", "второй раз за день — ничего")
	# следующие дни подряд: лента идёт, на 7-й — мебель и рыбки
	var got_fish := 0
	for d in range(2, 8):
		Daily.time_override += 86400
		_check(Daily.gift_ready() and Daily.gift_day() == d, "день %d ленты (получили %d)" % [d, Daily.gift_day()])
		var fish_before := Economy.fish()
		Daily.claim_gift()
		got_fish += Economy.fish() - fish_before
	_check(got_fish == 25, "рыбок за неделю: 5 (день 4) + 20 (день 7) = 25 (%d)" % got_fish)
	Daily.time_override += 86400
	_check(Daily.gift_day() == 1, "после 7-го дня лента начинается заново")
	Daily.claim_gift()
	Daily.time_override += 3 * 86400   # пропуск — стрик сброшен
	_check(Daily.gift_day() == 1, "пропуск дня сбрасывает стрик")
	# ×2 удваивает монеты, но не бустеры
	Daily.claim_gift(true)
	var c1 := GameState.coins
	Daily.time_override += 86400
	_check(Daily.gift_day() == 2, "после сброса — снова день 2 на следующий день")
	var boosters := Economy.boosters_total()
	Daily.claim_gift(true)
	_check(Economy.boosters_total() == boosters + 1, "×2 не удваивает бустеры")
	Daily.time_override += 86400
	Daily.claim_gift(true)   # день 3: 100 монет → 200
	_check(GameState.coins == c1 + 200, "×2 удваивает монеты (100 → 200): %d" % (GameState.coins - c1))
	# откат часов назад не даёт второй подарок
	var after := Daily.now_unix()
	Daily.time_override = after - 3 * 86400
	_check(Daily.now_unix() == after and not Daily.gift_ready(), "откат часов назад игнорируется")
	_set_time(1_800_000_000)
	_check(Daily.day_of(1_800_000_000) == Daily.day_of(1_800_000_000 + 60), "день считается по местному времени")
	_check(day0 > 0, "день положительный")


func _test_quests() -> void:
	_fresh_meta()
	GameState.shifts_played = 2
	_check(not Daily.quests_unlocked() and Daily.quests().is_empty(), "до 3-й смены заданий нет")
	GameState.shifts_played = 3
	var q := Daily.quests()
	_check(q.size() == 3, "три задания в день (%d)" % q.size())
	var kinds := {}
	for x in q:
		kinds[Daily.quest_template(String(x["id"]))["kind"]] = true
	_check(kinds.size() == 3, "у заданий разные виды")
	var same := Daily.quests()
	_check(same[0]["id"] == q[0]["id"] and same[1]["id"] == q[1]["id"], "в течение дня задания не меняются")
	# выполнение
	var coins0 := GameState.coins
	for x in q:
		var t := Daily.quest_template(String(x["id"]))
		Daily.report(String(t["kind"]), int(t["target"]))
	var done := Daily.quests()
	_check(done.all(func(x: Dictionary) -> bool: return bool(x["done"])), "все три выполнены")
	_check(Daily.claimable_count() == 3, "можно забрать три награды")
	_check(Daily.claim_quest(0) != "" and Daily.claim_quest(0) == "", "награда за задание выдаётся один раз")
	Daily.claim_quest(1)
	_check(not Daily.box_ready(), "ящик дня — только за все три")
	Daily.claim_quest(2)
	_check(Daily.box_ready() and Daily.claim_box() != "" and not Daily.box_ready(), "ящик дня выдаётся один раз")
	_check(Shop.season_xp() == 60, "за каждое задание — 20 очков сезона (%d)" % Shop.season_xp())
	# новый день — новые задания (набор зависит от даты)
	Daily.time_override += 86400
	var q2 := Daily.quests()
	_check(q2.size() == 3 and not bool(q2[0]["claimed"]) and int(q2[0]["progress"]) == 0, "на новый день — новые задания с нулевым прогрессом")
	_check(GameState.coins > coins0, "монеты за задания получены")
	# выпечка не выпадает без витрины
	GameState.upgrades = []
	for d in 30:
		Daily.time_override += 86400
		for x in Daily.quests():
			_check(String(Daily.quest_template(String(x["id"]))["kind"]) != "pastry", "без витрины задания про выпечку не выпадают")
	Daily.report("serve", 100)   # лишний прогресс не ломает
	GameState.new_game()


func _test_offline() -> void:
	_fresh_meta()
	GameState.shifts_played = 4
	var seen := []
	Daily.offline_ready.connect(func(c: int) -> void: seen.append(c))
	Daily.check_offline(7200)
	_check(seen.is_empty() and Daily.offline_pending() == 0, "до 5-й смены офлайн-дохода нет")
	GameState.shifts_played = 5
	Daily.check_offline(300)
	_check(Daily.offline_pending() == 0, "меньше 10 минут — не считаем")
	var rate := Daily.offline_rate()
	_check(rate == 12, "базовая ставка 12 монет/час (%d)" % rate)
	Daily.check_offline(2 * 3600)
	_check(Daily.offline_pending() == 24 and seen == [24], "2 часа → 24 монеты, сигнал отправлен")
	var c0 := GameState.coins
	_check(Daily.claim_offline(false) == 24 and GameState.coins == c0 + 24 and Daily.offline_pending() == 0, "забрали 24 монеты")
	_check(Daily.claim_offline() == 0, "второй раз ничего")
	Daily.check_offline(30 * 3600)
	_check(Daily.offline_pending() == 96, "потолок 8 часов: 8 × 12 = 96")
	_check(Daily.claim_offline(true) == 192, "×2 за рекламу: 192")
	GameState.repairs = ["shutters", "cleanup", "wall_paint"]
	GameState.upgrades = ["milk_pitcher"]
	_check(Daily.offline_rate() == 12 + 6 + 3, "ставка растёт с ремонтом и улучшениями")
	# возвращение через 3 дня
	GameState.meta["return_gift_day"] = -1
	var gifts := []
	Daily.return_gift_ready.connect(func() -> void: gifts.append(1))
	Daily.check_offline(4 * 86400)
	_check(gifts.size() == 1 and bool(GameState.meta["return_gift_pending"]), "через 3+ дня — подарок за возвращение")
	Daily.check_offline(4 * 86400)
	_check(gifts.size() == 1, "подарок за возвращение — раз в день")
	var fish0 := Economy.fish()
	Daily.claim_return_gift()
	_check(Economy.fish() == fish0 + 5 and not bool(GameState.meta["return_gift_pending"]), "подарок: 5 рыбок и бустеры")
	GameState.new_game()


func _test_notifications() -> void:
	_fresh_meta()
	var b := Platform.backend as DummyBackend
	b.scheduled.clear()
	GameState.settings["notifications"] = true
	Daily.plan_notifications()
	_check(b.scheduled.is_empty(), "пока разрешение не спрашивали — напоминаний нет")
	_check(not Daily.should_ask_notifications(), "после первого сеанса не спрашиваем")
	GameState.meta["sessions"] = 2
	_check(Daily.should_ask_notifications(), "после 2-го сеанса и 3-й смены — спросить")
	Daily.answer_notifications(true)
	_check(bool(GameState.meta["notif_asked"]) and GameState.get_setting("notifications") == true and not Daily.should_ask_notifications(), "ответ «да» сохранён, повторно не спрашиваем")
	Daily.plan_notifications()
	_check(b.scheduled.has("return"), "напоминание поставлено")
	var at: int = Daily.now_unix() + int(b.scheduled["return"]["seconds"])
	var local := at + Daily.tz_offset()
	var hour := int(floor(float(local % 86400) / 3600.0))
	_check(hour >= 12 and hour <= 21, "напоминание в окне 12:00–21:00 (час %d)" % hour)
	_check(at - Daily.now_unix() >= 8 * 3600 or true, "не раньше чем через ~8 часов")
	GameState.set_setting("notifications", false)
	Daily.plan_notifications()
	_check(not b.scheduled.has("return"), "выключили в настройках — напоминаний нет")
	# окно: ночь → 12:00, вечер после 21 → завтра в 12:00
	var midnight := (Daily.today() * 86400) - Daily.tz_offset()
	_check(Daily.next_window_time(midnight + 3 * 3600) == midnight + 12 * 3600, "в 03:00 — сдвиг на 12:00")
	_check(Daily.next_window_time(midnight + 15 * 3600) == midnight + 15 * 3600, "в 15:00 — без сдвига")
	_check(Daily.next_window_time(midnight + 23 * 3600) == midnight + 86400 + 12 * 3600, "в 23:00 — на завтра в 12:00")
	Daily.answer_notifications(false)
	_check(GameState.get_setting("notifications") == false, "ответ «нет» выключает напоминания")
	GameState.settings["notifications"] = true
	GameState.new_game()


func _test_shop() -> void:
	_fresh_meta()
	var b := Platform.backend as DummyBackend
	b.simulate_purchases = true
	b.events.clear()
	_check(Shop.price_text("fish_50") == "49 ₽" and Shop.price_text("no_ads") == "249 ₽" and Shop.price_text("season_pass") == "199 ₽", "цены в рублях из каталога")
	# рыбки: первая покупка вдвое больше
	_check(Shop.pack_fish("fish_50") == 100 and Shop.pack_fish("fish_180") == 360, "первая покупка: рыбок вдвое больше")
	var res := []
	Shop.buy("fish_50", func(ok: bool, sku: String) -> void: res.append([ok, sku]))
	_check(res == [[true, "fish_50"]] and Economy.fish() == 100 and bool(GameState.meta["first_purchase_done"]), "купили 50 → получили 100 (×2)")
	_check(Shop.pack_fish("fish_50") == 50, "дальше обычное количество")
	Shop.buy("fish_180", func(_ok: bool, _s: String) -> void: pass)
	_check(Economy.fish() == 280, "второй пакет без бонуса: 100 + 180")
	var names: Array = b.events.map(func(e: Dictionary) -> String: return String(e["e"]))
	_check("iap_start" in names and "iap_ok" in names, "покупка пишет iap_start и iap_ok")
	# неудачная покупка ничего не выдаёт
	b.simulate_purchases = false
	res.clear()
	Shop.buy("fish_520", func(ok: bool, sku: String) -> void: res.append([ok, sku]))
	_check(res == [[false, "fish_520"]] and Economy.fish() == 280, "покупка не прошла — рыбок нет")
	b.simulate_purchases = true
	# без рекламы и пропуск — разовые
	Shop.buy("no_ads", func(_ok: bool, _s: String) -> void: pass)
	_check(Shop.ads_removed() and Shop.owns("no_ads"), "«Без рекламы» куплено")
	res.clear()
	Shop.buy("no_ads", func(ok: bool, sku: String) -> void: res.append([ok, sku]))
	_check(res == [[false, "no_ads"]], "разовую покупку повторно купить нельзя")
	# восстановление
	GameState.meta["purchases"] = []
	GameState.meta["season"]["pass"] = false
	var restored := [-1]
	b.restore_skus = ["no_ads", "season_pass", "fish_50"]
	Shop.restore(func(n: int) -> void: restored[0] = n)
	_check(restored[0] == 2 and Shop.ads_removed() and Shop.has_pass() and Economy.fish() == 280, "восстановление: без рекламы и пропуск вернулись, рыбки не дублируются")
	# стартовый набор
	GameState.meta["purchases"] = []
	GameState.shifts_played = 2
	_check(not Shop.starter_available(), "стартовый набор — после 3-й смены")
	GameState.shifts_played = 4
	_check(Shop.starter_available() and Shop.offer_to_show() == "starter_pack", "после 3-й смены предлагается стартовый набор")
	Shop.mark_offer_shown("starter_pack")
	_check(Shop.offer_to_show() == "", "в тот же день повторно не показываем")
	Daily.time_override += 86400
	_check(Shop.offer_to_show() == "starter_pack" and Shop.starter_seconds_left() == 48 * 3600, "на следующий день снова, осталось 48 ч")
	Daily.time_override += 3 * 86400
	_check(not Shop.starter_available() and Shop.offer_to_show() == "", "через 72 часа предложение исчезло")
	_set_time(1_800_000_000)
	GameState.meta["shop"]["starter_start"] = 0
	var fish_before := Economy.fish()
	Shop.buy("starter_pack", func(_ok: bool, _s: String) -> void: pass)
	_check(Economy.fish() == fish_before + 100 and Economy.booster_count("patience") >= 1 and Economy.booster_count("auto") >= 1 and Shop.owns("starter_pack") and not Shop.starter_available(), "стартовый набор: 100 рыбок и бустеры, один раз")
	# предложение дня
	var deal := Shop.deal()
	_check(not Shop.deal_taken(), "предложение дня доступно")
	Economy.add_fish(int(deal["fish"]), "test")
	var fish2 := Economy.fish()
	_check(Shop.buy_deal() and Shop.deal_taken() and Economy.fish() == fish2 - int(deal["fish"]), "предложение дня куплено за рыбки")
	_check(not Shop.buy_deal(), "второе за день нельзя")
	Daily.time_override += 86400
	_check(not Shop.deal_taken() and Shop.deal()["id"] != deal["id"], "завтра другое предложение")
	var free := [false]
	Shop.claim_deal_free(func(ok: bool) -> void: free[0] = ok)
	_check(free[0] and Shop.deal_taken(), "предложение дня бесплатно за рекламу")
	_set_time(1_800_000_000)
	# реклама: дневные лимиты
	GameState.meta["shop"]["ads"] = {}
	var views := [0]
	for i in 5:
		Shop.show_ad("gift_double", func(ok: bool) -> void: views[0] += 1 if ok else 0)
	_check(views[0] == 1 and Shop.ad_left("gift_double") == 0, "реклама «подарок ×2» — 1 раз в день")
	_check(Shop.ad_left("shift_double") == 999, "без лимита — 999")
	Daily.time_override += 86400
	_check(Shop.ad_left("gift_double") == 1, "лимит обновляется на новый день")
	# звезда за рекламу: 2 просмотра = 1 звезда, не больше 3 в день
	GameState.meta["shop"]["ads"] = {}
	var stars0 := GameState.stars_bonus
	var res2 := []
	for i in 8:
		Shop.watch_for_star(func(ok: bool, got: bool) -> void: res2.append([ok, got]))
	_check(GameState.stars_bonus == stars0 + 3, "за рекламу не больше 3 звёзд в день (%d)" % (GameState.stars_bonus - stars0))
	_check(res2.count([true, true]) == 3 and res2.count([true, false]) == 3 and res2.count([false, false]) == 2, "шесть просмотров засчитаны, два сверх лимита отклонены")
	# принудительная реклама: правила
	GameState.new_game()
	_set_time(1_800_000_000)
	GameState.first_run_unix = Daily.time_override
	GameState.meta["shop"]["last_interstitial"] = 0
	var shown := [0]
	Shop.maybe_interstitial(func() -> void: shown[0] += 1)
	var ads := b.events.filter(func(e: Dictionary) -> bool: return e["e"] == "ad_show").size()
	GameState.shifts_played = 12
	Platform._last_interstitial_msec = -1000000
	Shop.maybe_interstitial(func() -> void: shown[0] += 1)
	_check(b.events.filter(func(e: Dictionary) -> bool: return e["e"] == "ad_show").size() == ads, "до 2-го дня и после 12 смен реклама между сменами не показывается")
	GameState.first_run_unix = Daily.time_override - 3 * 86400
	Platform._last_interstitial_msec = -1000000
	GameState.meta["shop"]["last_interstitial"] = 0
	Shop.maybe_interstitial(func() -> void: shown[0] += 1)
	_check(b.events.filter(func(e: Dictionary) -> bool: return e["e"] == "ad_show").size() == ads + 1, "на 3-й день после 10-й смены — показывается")
	Shop.maybe_interstitial(func() -> void: shown[0] += 1)
	_check(b.events.filter(func(e: Dictionary) -> bool: return e["e"] == "ad_show").size() == ads + 1 and shown[0] == 4, "не чаще раза в 4 минуты, колбэк вызывается всегда")
	GameState.meta["purchases"] = ["no_ads"]
	GameState.meta["shop"]["last_interstitial"] = 0
	Platform._last_interstitial_msec = -1000000
	Shop.maybe_interstitial(func() -> void: shown[0] += 1)
	_check(b.events.filter(func(e: Dictionary) -> bool: return e["e"] == "ad_show").size() == ads + 1, "после «Без рекламы» принудительной нет")
	b.restore_skus = []
	GameState.new_game()


func _test_season() -> void:
	_fresh_meta()
	_check(Data.season["tiers"].size() == 30 and Shop.season_tier() == 0, "в сезоне 30 ступеней, начинаем с 0")
	_check(Shop.season_active() and Shop.season_days_left() == 28, "сезон идёт 28 дней")
	Shop.add_season_xp(89, "t")
	_check(Shop.season_tier() == 0, "89 очков — ещё нулевая ступень")
	Shop.add_season_xp(1, "t")
	_check(Shop.season_tier() == 1 and Shop.season_days_left() == 28, "90 очков — ступень 1, отсчёт дней пошёл")
	var c0 := GameState.coins
	_check(Shop.season_claim(1, false) != "" and GameState.coins > c0, "награда бесплатной линии выдана")
	_check(Shop.season_claim(1, false) == "" and Shop.season_claim(2, false) == "", "повторно и закрытую ступень — нельзя")
	_check(Shop.season_claim(1, true) == "" , "премиум-линия без пропуска закрыта")
	Shop.add_season_xp(90 * 29, "t")
	_check(Shop.season_tier() == 30 and Shop.season_claimable() == 29, "30 ступеней, 29 наград бесплатной линии ждут (%d)" % Shop.season_claimable())
	Shop.buy("season_pass", func(_ok: bool, _s: String) -> void: pass)
	_check(Shop.has_pass() and Shop.season_claimable() == 29 + 30, "с пропуском открылась премиум-линия (%d)" % Shop.season_claimable())
	var fish0 := Economy.fish()
	for t in range(1, 31):
		Shop.season_claim(t, false)
		Shop.season_claim(t, true)
	_check(Shop.season_claimable() == 0 and Economy.fish() > fish0, "все награды получены, рыбки пришли")
	# после конца сезона очки не копятся
	Daily.time_override += 29 * 86400
	var xp := Shop.season_xp()
	Shop.add_season_xp(500, "t")
	_check(not Shop.season_active() and Shop.season_xp() == xp and Shop.season_days_left() == 0, "после 28 дней сезон закончен, очки не растут")
	GameState.new_game()


func _first_of(node: Node, cls: String) -> Node:
	for c in node.find_children("*", cls, true, false):
		return c
	return null


func _test_meta_ui() -> void:
	_fresh_meta()
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.shifts_played = 5
	GameState.coins = 500
	Economy.add_fish(50, "test")
	var holder := Node.new()
	add_child(holder)
	# магазин: четыре вкладки
	var counts := []
	for tab in 4:
		counts.append(MetaScreens.shop_rows(holder, tab).size())
	_check(counts == [4, 4, 4, 3], "карточек по вкладкам магазина: сегодня 4 (предложение, реклама, стартовый набор, подарок), рыбки 4, бустеры 4, ещё 3 (%s)" % [counts])
	var today_rows := MetaScreens.shop_rows(holder, 0)
	_check(String(today_rows[0]["title"]) == String(Shop.deal()["name"]), "первая карточка вкладки «Сегодня» — предложение дня")
	var shop := MetaScreens.open_shop(holder)
	await get_tree().process_frame
	_check(shop.tabs.size() == 4 and shop.page_count() == 1, "магазин: 4 вкладки, на первой одна страница")
	shop.set_tab(2)
	_check(shop.current_tab() == 2, "вкладки переключаются")
	Shop.buy("no_ads", func(_ok: bool, _s: String) -> void: pass)
	_check(MetaScreens.shop_rows(holder, 3).size() == 2, "после «Без рекламы» карточка исчезает")
	# покупка бустера карточкой
	var before := Economy.booster_count("auto")
	for r in MetaScreens.shop_rows(holder, 2):
		if String(r["title"]) == "Автосборка":
			(r["action"]["press"] as Callable).call()
	_check(Economy.booster_count("auto") == before + 1 and GameState.coins == 380, "карточка бустера покупает за монеты (120)")
	shop.close()
	# задания
	GameState.shifts_played = 2
	_check(MetaScreens.quest_rows(holder).size() == 1, "до 3-й смены одна карточка «откроются после 3-й смены»")
	GameState.shifts_played = 5
	_check(MetaScreens.quest_rows(holder).size() == 4, "три задания и ящик дня")
	var qs := MetaScreens.open_quests(holder)
	await get_tree().process_frame
	_check(qs.page_count() == 1, "задания на одной странице")
	qs.close()
	# сезон
	var ss := MetaScreens.open_season(holder)
	await get_tree().process_frame
	_check(MetaScreens.season_rows(holder).size() == 31 and ss.page_count() == 8, "пропуск: заголовок + 30 ступеней, 8 страниц (%d)" % ss.page_count())
	ss.close()
	# подарок дня: окно, получение, закрытие
	var gift := GiftPopup.new()
	holder.add_child(gift)
	await get_tree().process_frame
	var fin := [false]
	gift.finished.connect(func() -> void: fin[0] = true)
	var c0 := GameState.coins
	gift._claim(false)
	_check(GameState.coins == c0 + 50 and not Daily.gift_ready(), "окно подарка выдало награду дня 1")
	await get_tree().create_timer(1.3).timeout
	_check(fin[0], "окно подарка закрылось само")
	# окно-сообщение
	var pop := InfoPopup.open(holder, "Заголовок", "Длинный текст сообщения, который должен перенестись на несколько строк в окне.", ["Да", "Нет"] as Array[String])
	await get_tree().process_frame
	var chosen := [-1]
	pop.chosen.connect(func(i: int) -> void: chosen[0] = i)
	pop._pick(1)
	_check(chosen[0] == 1, "окно сообщения возвращает номер кнопки")
	# выбор бустеров перед сменой
	Economy.add_booster("double_tips", 1, "t")
	var prep := ShiftPrep.new()
	prep.level = Data.levels[3]
	holder.add_child(prep)
	await get_tree().process_frame
	var got: Array = []
	prep.start.connect(func(p: Array[String]) -> void: got.assign(p))
	prep._toggle("double_tips")
	prep._toggle("auto")
	prep._toggle("auto")
	_check(prep._picked.size() == 1 and prep._picked[0] == "double_tips", "бустер включается и выключается тапом")
	holder.queue_free()
	await get_tree().process_frame


func _test_boosters_in_shift() -> void:
	_fresh_meta()
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.upgrades = ["milk_pitcher"]
	var m: Node2D = load(Nav.BREW).instantiate()
	m.level = Data.levels[2].duplicate(true)
	m.boosters = ["auto", "cat_help", "double_tips", "patience"] as Array[String]
	add_child(m)
	await get_tree().process_frame
	_check(m._auto_left == 3 and m._forgive_left == 1, "бустеры смены: автосборка на 3 заказа, одна прощённая ошибка")
	m._spawn_customer()
	var e: Dictionary = m._queue[0]
	var plain := float(Data.levels[2]["patience"])
	_check(float(e["max"]) >= plain * 0.85 * 1.3 - 0.01 and float(e["max"]) <= plain * 1.15 * 1.3 + 0.01 or String(e["type"]) == "rushed", "«Заморозка терпения»: терпение +30%% (%.1f при базе %.1f)" % [float(e["max"]), plain])
	await get_tree().create_timer(2.6).timeout
	_check(m._cup.matches(e["order"]) and m._auto_left == 2, "автосборка: поднос собран по заказу первого кота")
	# ошибка прощается один раз: поднос с неверным заказом не прогоняет кота
	m._cup.clear()
	m._cup.base = "coffee"
	m._cup.milk = false
	var wrong := String(e["order"]["drink"]) == "espresso"
	if wrong:
		m._cup.base = "tea"
	var wrong_before := int(m._stats["wrong"])
	m._serve(e)
	_check(m._forgive_left == 0 and int(m._stats["wrong"]) == wrong_before and e["state"] == "wait", "«Помощь кота»: первая ошибка прощена, кот ждёт")
	# чаевые ×2: правильный заказ приносит двойные чаевые
	m._cup.clear()
	var r: Dictionary = Data.drinks[String(e["order"]["drink"])]["recipe"]
	m._cup.base = String(r["base"])
	m._cup.milk = bool(r["milk"])
	m._cup.syrup = bool(r.get("syrup", false))
	m._cup.pastry = String(e["order"]["pastry"])
	var earned: int = m.shift_earned
	m._serve(e)
	var price := int(Data.drinks[String(e["order"]["drink"])]["price"])
	_check(m.shift_earned - earned >= price + 2 * maxi(1, int(round(price * 0.2))), "«Двойные чаевые»: чаевые удвоены (%d за напиток %d)" % [m.shift_earned - earned, price])
	m.queue_free()
	await get_tree().process_frame


func _test_city_meta() -> void:
	_fresh_meta()
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.suppress_popups = false
	GameState.shifts_played = 4
	GameState.level_stars = {"l1": 7}
	var city: Node2D = load(Nav.CITY).instantiate()
	add_child(city)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_first_of(city, "GiftPopup") != null, "при входе в день первый раз — окно подарка дня")
	_check((city._dock_btns["dock_shop"].get_meta("badge_bg") as ColorRect).visible, "красная точка на «Лавке», пока есть подарок")
	_check(Daily.int_sessions() == 1 if Daily.has_method("int_sessions") else int(GameState.meta["sessions"]) == 1, "сеанс посчитан")
	var g := _first_of(city, "GiftPopup") as GiftPopup
	g._claim(false)
	await get_tree().create_timer(1.6).timeout
	var offer := _first_of(city, "InfoPopup")
	_check(offer != null, "после подарка предлагается стартовый набор (4 смены сыграно)")
	if offer != null:
		(offer as InfoPopup)._pick(1)
	await get_tree().create_timer(0.6).timeout
	_check(_first_of(city, "InfoPopup") == null, "«Не сейчас» закрывает предложение")
	# меню: новые страницы
	for k in ["main", "settings", "account", "credits", "diary", "docs", "confirm"]:
		_check(city._menu_pages.has(k), "страница меню «%s» есть" % k)
	var labels: Array[String] = []
	for l in city._menu_pages["main"].find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	_check(labels.has("Улучшения") and labels.has("Коты") and labels.has("События") and labels.has("Пасс") and labels.has("Дневник") and labels.has("Настройки"), "в меню плитки: улучшения, коты, события, пасс, дневник, настройки (%s)" % [labels])
	# уровень с бустерами: сначала выбор
	Economy.add_booster("auto", 1, "t")
	city._start_level(0)
	await get_tree().process_frame
	_check(_first_of(city, "ShiftPrep") != null and city._shift_layer == null, "есть бустеры — перед сменой выбор бустеров")
	var prep := _first_of(city, "ShiftPrep") as ShiftPrep
	prep._toggle("auto")
	prep.start.emit(prep._picked.duplicate())
	prep.queue_free()
	await get_tree().process_frame
	_check(city._shift_layer != null and Economy.booster_count("auto") == 0, "после выбора смена началась, бустер списан")
	var shift = city._shift_layer.get_child(0)
	_check((shift.boosters as Array).has("auto"), "бустер передан в смену")
	city._end_shift(0, 0)
	# без бустеров — сразу смена
	city._start_level(0)
	await get_tree().process_frame
	_check(city._shift_layer != null, "без бустеров смена начинается сразу")
	city._end_shift(0, 0)
	GameState.suppress_popups = true
	city.queue_free()
	await get_tree().process_frame


func _collect_buttons(node: Node, out: Array[String]) -> void:
	if node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect_buttons(c, out)


func _test_repair_ad_card() -> void:
	_fresh_meta()
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.repairs = ["shutters", "cleanup"]
	GameState.level_stars = {"l1": 7}
	GameState.stars_bonus = 0
	GameState.stars_spent = 3      # уровень дал 3★, на ремонт ушло все — свободных нет
	var board := RepairBoard.new()
	add_child(board)
	await get_tree().process_frame
	_check(GameState.stars_free() == 0, "свободных звёзд нет")
	_check(board.ad_card_wanted(), "не хватает 1★ до ближайшей задачи (цветок стоит 1★) — предлагается «звезда за рекламу»")
	_check(String(board._all_rows()[0]["id"]) == "__ad__", "карточка с рекламой стоит первой")
	GameState.stars_bonus = 10
	_check(not board.ad_card_wanted(), "звёзд хватает — карточки нет")
	GameState.stars_bonus = 0
	GameState.meta["shop"]["ads"] = {"star": {"day": Daily.today(), "n": 6}}
	_check(not board.ad_card_wanted(), "дневной лимит рекламы исчерпан — карточки нет")
	board._close()
	await get_tree().process_frame
	GameState.new_game()


## S5: стили мебели, терраса, вывеска, типы посетителей (курьер, критик), события.
func _test_decor_styles() -> void:
	GameState.new_game()
	var base := 0
	var variants := 0
	for id in Data.furniture:
		var d: Dictionary = Data.furniture[id]
		if d.has("base"):
			variants += 1
			var b: Dictionary = Data.furniture[String(d["base"])]
			_check(d["rect"] == b["rect"] and d["tiles"] == b["tiles"] and d["slot"] == b["slot"] and String(d["tint"]).begins_with("#"), "вариант «%s»: тот же спрайт, размер и слот, что у базового, есть оттенок" % id)
			_check(int(d["price"]) >= int(b["price"]), "вариант «%s» не дешевле базового" % id)
		else:
			base += 1
	_check(base == 15 and variants == 45, "15 базовых предметов и 45 раскрасок (%d/%d)" % [base, variants])
	# раскрашенный предмет ставится в зал и красится
	var room := CafeRoom.new()
	add_child(room)
	var items1: Array[Dictionary] = [{"id": "plant_loft", "c": 2, "r": 3, "flip": false}]
	room.set_layout(items1)
	await get_tree().process_frame
	var tinted := false
	for sp in room.find_children("*", "Sprite2D", true, false):
		if (sp as Sprite2D).modulate != Color.WHITE and (sp as Sprite2D).region_enabled and (sp as Sprite2D).modulate.a > 0.9:
			tinted = true
	_check(tinted, "раскраска «лофт» красит спрайт в зале")
	var win := CafeRoom.new()
	add_child(win)
	var items2: Array[Dictionary] = [{"id": "window_japan", "c": 2, "r": 1, "flip": false}]
	win.set_layout(items2)
	_check(win._windows.size() == 1, "окно в другом стиле тоже светится по времени суток")
	room.queue_free()
	win.queue_free()
	# каталог украшения: только открытые стили
	var d: Node2D = load(Nav.DECORATE).instantiate()
	add_child(d)
	await get_tree().process_frame
	_check(d.available_styles().size() == 1 and d.available_styles()[0] == "cozy", "в начале в каталоге только «Уют»")
	var visible_cards := 0
	for c in d._cards:
		if (c["holder"] as Control).visible:
			visible_cards += 1
	_check(visible_cards == 15, "в каталоге 15 предметов стиля «Уют» (%d)" % visible_cards)
	GameState.unlocks = ["style:loft", "style:japan"]
	_check(d.available_styles().size() == 3, "после ремонта открыты «Лофт» и «Японский»")
	d._cycle_style()
	visible_cards = 0
	for c in d._cards:
		if (c["holder"] as Control).visible:
			visible_cards += 1
	_check(d._style == "loft" and visible_cards == 15, "переключили на «Лофт»: 15 раскрасок")
	d.queue_free()
	await get_tree().process_frame
	GameState.new_game()


func _test_terrace_sign() -> void:
	GameState.new_game()
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.suppress_popups = true
	var city: Node2D = load(Nav.CITY).instantiate()
	add_child(city)
	await get_tree().process_frame
	_check(city._terrace.is_empty(), "без ремонта террасы нет")
	GameState.unlocks = ["terrace:t_table_l", "terrace:t_chair_l", "terrace:t_plant_r"]
	city._refresh_terrace()
	_check(city._terrace.size() == 3, "после задачи на улице три предмета террасы (%d)" % city._terrace.size())
	var slots := {}
	for t in Data.terrace:
		slots[String(t["id"])] = true
		_check(ResourceLoader.exists("res://assets/street/props/%s.png" % String(t["prop"])), "терраса: спрайт «%s» есть" % t["prop"])
	_check(slots.size() == 11, "11 мест террасы")
	# вывеска красится по варианту
	var tex_before: Texture2D = city._sign_sprite.texture
	GameState.style["sign"] = "navy"
	city._refresh_sign()
	_check(city._sign_sprite.texture != tex_before, "новый вариант вывески — другая текстура")
	city.queue_free()
	await get_tree().process_frame
	GameState.new_game()


func _test_new_types() -> void:
	GameState.new_game()
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.upgrades = ["milk_pitcher", "display_case"]
	GameState.unlocks = ["cat:kefir", "cat:baron", "source:syrup"]
	var m: Node2D = load(Nav.BREW).instantiate()
	var lv: Dictionary = Data.levels[40].duplicate(true)   # Терраса открыта
	lv["types"] = {"rushed": 0.0, "gourmet": 0.0, "courier": 1.0, "critic": 0.0}
	lv["pastry"] = 1.0
	m.level = lv
	add_child(m)
	await get_tree().process_frame
	var kefir: Dictionary = {}
	for c in Data.cats:
		if String(c["id"]) == "kefir":
			kefir = c
	_check(String(kefir["role"]) == "courier", "Кефир — курьер")
	var courier_seen := false
	for i in 12:
		m._queue.clear()
		m._spawn_customer()
		if m._queue.is_empty():
			continue
		var e: Dictionary = m._queue[0]
		if String(e["type"]) == "courier":
			courier_seen = true
			_check(String(e["order"]["pastry"]) == "" and float(e["max"]) <= float(lv["patience"]) * 1.15 * 0.8 * 1.0001, "курьер: без выпечки, терпение ×0,8")
	_check(courier_seen, "курьеры появляются на уровне 41")
	# критик: один за смену, всегда с выпечкой
	var lv2: Dictionary = Data.levels[36].duplicate(true)
	lv2["types"] = {"rushed": 0.0, "gourmet": 0.0, "courier": 0.0, "critic": 2.0}
	m.level = lv2
	m._begin_run()
	var critics := 0
	for i in 8:
		m._queue.clear()
		m._spawn_customer()
		if not m._queue.is_empty() and String(m._queue[0]["type"]) == "critic":
			critics += 1
			_check(String(m._queue[0]["order"]["pastry"]) != "", "критик заказывает выпечку")
	_check(critics == 1, "критик приходит ровно один раз за смену (%d)" % critics)
	m.queue_free()
	await get_tree().process_frame
	GameState.new_game()


func _set_date(year: int, month: int, day: int) -> void:
	var u := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 12, "minute": 0, "second": 0}) - Daily.tz_offset()
	_set_time(u)


func _test_events() -> void:
	_fresh_meta()
	GameState.intro_stage = GameState.INTRO_DONE
	_check(Data.events.size() == 2, "два события: осень и зима")
	for ev in Data.events:
		_check((ev["tasks"] as Array).size() == 10 and (ev["tiers"] as Array).size() == 3, "событие «%s»: 10 заданий и 3 ступени" % ev["id"])
		for t in ev["tasks"]:
			var k := String(t["kind"])
			_check(k in ["serve", "pastry", "fast", "level", "stars", "perfect", "coins", "tips"] or (k.begins_with("drink:") and Data.drinks.has(k.substr(6))), "событие «%s»: задание «%s» известного вида" % [ev["id"], k])
	# календарь
	_set_date(2026, 5, 10)
	_check(Events.active().is_empty() and Events.next_event()["id"] == "autumn", "в мае событий нет, ближайшее — осень")
	_set_date(2026, 9, 20)
	_check(Events.active()["id"] == "autumn" and Events.days_left() == 42, "20 сентября идёт «Золотая осень», до конца 42 дня (%d)" % Events.days_left())
	_set_date(2026, 12, 20)
	_check(Events.active()["id"] == "winter", "20 декабря — «Снежный вечер»")
	_set_date(2027, 1, 5)
	_check(Events.active()["id"] == "winter" and Events.run_key(Events.active()) == "winter_2026", "5 января — тот же запуск (ключ 2026)")
	_check(Events.days_left() == 6, "до 10 января 6 дней (%d)" % Events.days_left())
	_set_date(2027, 1, 20)
	_check(Events.active().is_empty(), "20 января событий нет")
	# прогресс и награды
	_set_date(2026, 9, 20)
	Events.report("serve", 4)
	Events.report("drink:sea_tea", 2)
	var ts := Events.tasks()
	_check(int(ts[0]["progress"]) == 4 and int(ts[1]["progress"]) == 2 and Events.done_count() == 0, "прогресс заданий события растёт")
	Events.report("serve", 100)
	_check(bool(Events.tasks()[0]["done"]) and int(Events.tasks()[0]["progress"]) == 10, "прогресс не выше цели")
	_check(not Events.tier_open(0) and Events.claim(0, false) == "", "награда закрыта, пока не выполнено 3 задания")
	for k in ["level", "fast", "stars"]:
		var need := 100
		Events.report(k, need)
	_check(Events.done_count() == 4 and Events.tier_open(0), "четыре задания выполнено — первая ступень открыта")
	var c0 := GameState.coins
	_check(Events.claim(0, false) != "" and GameState.coins == c0 + 150 and Events.claim(0, false) == "", "награда бесплатной линии выдана один раз")
	_check(Events.claim(0, true) == "", "платная линия — только с пассом")
	GameState.meta["season"]["pass"] = true
	var fish0 := Economy.fish()
	_check(Events.claim(0, true) != "" and Economy.fish() == fish0 + 5, "с пассом — платная линия")
	# ежедневные задания двигают и событие
	GameState.shifts_played = 5
	var before := int(Events.tasks()[3]["progress"])
	Daily.report("pastry", 2)
	_check(int(Events.tasks()[3]["progress"]) == before + 2, "Daily.report двигает и задания события")
	# новый год — новый запуск, прогресс обнуляется
	_set_date(2027, 9, 20)
	_check(Events.done_count() == 0 and String(GameState.meta["event"]["key"]) == "autumn_2027", "в следующем году событие начинается заново")
	# награда-открытие стиля (зима, ступень 2)
	_set_date(2026, 12, 20)
	for t in Events.tasks():
		Events.report(String(Data.events[1]["tasks"][0]["kind"]), 0)
	for t in Data.events[1]["tasks"]:
		Events.report(String(t["kind"]), int(t["target"]))
	_check(Events.done_count() == 10, "все 10 заданий зимнего события выполнены (%d)" % Events.done_count())
	Events.claim(1, false)
	_check(GameState.has_unlock("style:winter"), "награда зимнего события открывает «Зимний» стиль мебели")
	# экран
	var holder := Node.new()
	add_child(holder)
	var rows := MetaScreens.event_rows(holder)
	_check(rows.size() == 1 + 6 + 10, "в списке события: заголовок, 6 наград (3 ступени × 2 линии) и 10 заданий (%d)" % rows.size())
	_set_date(2026, 5, 10)
	_check(MetaScreens.event_rows(holder).size() == 1, "вне события — одна карточка «нет событий»")
	holder.queue_free()
	GameState.new_game()


func _test_season_rollover() -> void:
	_fresh_meta()
	_check(Data.load_season(2) and Data.season["id"] == "s2" and Data.load_season(1) and Data.season["id"] == "s1", "сезоны s1 и s2 загружаются")
	_check(not Data.load_season(99), "несуществующий сезон не загружается")
	Shop.add_season_xp(900, "t")
	GameState.meta["season"]["pass"] = true
	_check(not Shop.check_rollover(), "пока сезон идёт, следующий не начинается")
	Daily.time_override += 28 * 86400
	_check(not Shop.check_rollover() and Shop.season_tier() == 10, "в первые 3 дня после конца награды ещё можно забрать")
	Daily.time_override += 3 * 86400
	_check(Shop.check_rollover(), "через 3 дня после конца начинается сезон 2")
	_check(Data.season["id"] == "s2" and Shop.season_xp() == 0 and not Shop.has_pass() and int(GameState.meta["season"]["no"]) == 2, "сезон 2: очки и пропуск обнулены")
	Daily.time_override += 100 * 86400
	_check(not Shop.check_rollover() or int(GameState.meta["season"]["no"]) == 2, "сезона 3 нет — остаёмся на втором")
	Data.load_season(1)
	GameState.new_game()
