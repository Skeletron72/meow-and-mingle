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
	_check(Data.repairs.size() == 2 and GameState.repair_def("shutters")["cost"] == 1 and GameState.repair_def("cleanup")["cost"] == 2, "в data/repairs.json две задачи: ставни (1★) и расчистка (2★)")
	_check(not GameState.do_repair("shutters"), "без звёзд ремонт не оплатить")
	GameState.level_stars = {"l1": 7}   # три звезды с уровня
	_check(GameState.stars_total() == 3 and GameState.stars_free() == 3, "звёзды уровней считаются")
	_check(GameState.do_repair("shutters") and GameState.stars_free() == 2, "ставни куплены")
	_check(not GameState.do_repair("shutters") and GameState.stars_free() == 2, "второй раз не списывается")
	_check(GameState.stage_after_tutorial() == 3, "после ставней — расчистка")
	GameState.do_repair("cleanup")
	_check(GameState.stage_after_tutorial() == GameState.INTRO_DONE and GameState.stars_free() == 0, "всё оплачено — вступление пройдено")
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
