extends Node
## Проверка интерфейса «глазами машины»: открывает все экраны в обоих языках и ищет
##  • текст, который не влезает в свою подпись или кнопку (обрезается многоточием или вылезает);
##  • подписи и кнопки, вылезающие за экран 360×640;
##  • координаты не по сетке арта (нечётные пиксели): из-за них линии и значки «пляшут» на полпикселя;
##  • перекрытие кнопок друг с другом внутри одного окна.
## Запуск: godot --headless --path . res://tools/ui_lint.tscn      (код выхода 1, если нашлись замечания)

var _issues: Array[String] = []
var _checked := 0
var _screen := ""


func _ready() -> void:
	GameState.suppress_popups = true
	TimeOfDay.set_process(false)
	Weather.set_process(false)
	for lang in ["ru", "en"]:
		Loc.override = lang
		Loc.apply(lang)
		await _run_all(lang)
	for i in _issues:
		print("UI: ", i)
	print("UI LINT: экранов проверено %d, замечаний %d" % [_checked, _issues.size()])
	get_tree().quit(1 if not _issues.is_empty() else 0)


func _setup_state() -> void:
	GameState.new_game()
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.layout = Data.default_layout.duplicate(true)
	GameState.repairs = ["shutters", "cleanup"]
	GameState.shifts_played = 6
	GameState.level_stars = {"l1": 7, "l2": 7, "l3": 3, "l4": 1}
	GameState.coins = 12345
	GameState.stars_bonus = 12
	GameState.upgrades = ["milk_pitcher", "display_case", "matcha_kit"]
	GameState.unlocks = ["source:syrup", "drink:cocoa", "drink:raf", "drink:sea_tea", "cat:bulka", "cat:kefir", "cat:baron"]
	Daily.time_override = Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 5, "hour": 12, "minute": 0, "second": 0})
	GameState.meta["clock_max"] = 0
	GameState.first_run_unix = Daily.time_override - 4 * 86400
	Economy.add_fish(1234, "lint")
	Economy.add_booster("auto", 12, "lint")
	Economy.add_booster("patience", 3, "lint")
	Economy.add_booster("cat_help", 1, "lint")
	Shop.add_season_xp(450, "lint")
	TimeOfDay.hour = 12.0


func _run_all(lang: String) -> void:
	_setup_state()
	var city: Node2D = load(Nav.CITY).instantiate()
	add_child(city)
	await get_tree().process_frame
	await get_tree().process_frame
	_scan(lang, "город (шапка)", city)
	# все страницы меню
	city._open_menu()
	for page in city._menu_pages.keys():
		if page == "shop":
			continue
		city._menu_page(page)
		await get_tree().process_frame
		_scan(lang, "меню/%s" % page, city._menu)
	city._open_credits()
	for i in Data.credits.size():
		_scan(lang, "титры/%d" % i, city._menu)
		city._credits_turn()
	city._close_menu()
	city._open_shop()
	var up: ListScreen = city._upgrade_screen
	for i in up.page_count():
		await get_tree().process_frame
		_scan(lang, "улучшения/%d" % i, up)
		up._turn()
	up.close()
	# уровни, ремонт, коты
	city._open_levels()
	for i in city._levels_layer.page_count():
		await get_tree().process_frame
		_scan(lang, "выбор смены/%d" % i, city._levels_layer)
		city._levels_turn()
	city._close_levels()
	city._open_repairs()
	var board: RepairBoard = city._repair_board
	for i in board.page_count():
		await get_tree().process_frame
		_scan(lang, "ремонт/%d" % i, board)
		board._turn()
	board.close()
	await get_tree().process_frame
	var book := CatBook.new()
	city.add_child(book)
	for i in book.page_count():
		await get_tree().process_frame
		_scan(lang, "коты/%d" % i, book)
		book._turn()
	book.queue_free()
	# мета-экраны (ListScreen)
	var shop_screen := MetaScreens.open_shop(city)
	for tab in 4:
		shop_screen.set_tab(tab)
		for i in shop_screen.page_count():
			await get_tree().process_frame
			_scan(lang, "магазин/вкладка %d/%d" % [tab, i], shop_screen)
			shop_screen._turn()
	shop_screen.close()
	for entry in [ ["задания", MetaScreens.open_quests], ["события", MetaScreens.open_events], ["пропуск", MetaScreens.open_season]]:
		var s: ListScreen = entry[1].call(city)
		for i in s.page_count():
			await get_tree().process_frame
			_scan(lang, "%s/%d" % [entry[0], i], s)
			s._turn()
		s.close()
	# окна
	var g := GiftPopup.new()
	city.add_child(g)
	await get_tree().process_frame
	_scan(lang, "подарок дня", g)
	g.queue_free()
	var pops := [
		["офлайн", "С возвращением!", tr("Пока тебя не было, кафе заработало %d монет.") % 96, ["Забрать", "×2 за рекламу"]],
		["предложение", "Стартовый набор", tr("%d рыбок и 3 бустера всего за %s. Предложение действует %d ч.") % [100, "99 ₽", 72], ["Купить за 99 ₽", "Не сейчас"]],
		["напоминания", "Напоминания", "Напоминать о подарках и заработке кафе? Не чаще раза в день.", ["Включить", "Не нужно"]],
		["возвращение", "Мы скучали!", "Тебя не было несколько дней. Держи подарок: 5 рыбок и два бустера.", ["Забрать"]],
	]
	for p in pops:
		var b: Array[String] = []
		b.assign(p[3])
		var pop := InfoPopup.open(city, p[1], p[2], b)
		await get_tree().process_frame
		_scan(lang, "окно/%s" % p[0], pop)
		pop.queue_free()
	var prep := ShiftPrep.new()
	prep.level = Data.levels[21]
	city.add_child(prep)
	prep._toggle("auto")
	await get_tree().process_frame
	_scan(lang, "перед сменой", prep)
	prep.queue_free()
	for sc in [Data.story[0], Data.story[17]]:
		var st := StoryScene.new()
		st.scene = sc
		city.add_child(st)
		await get_tree().process_frame
		_scan(lang, "сюжет/%s" % sc["id"], st)
		st.queue_free()
	var rc := RepairCard.new()
	city._ui.add_child(rc)
	rc.setup("shutters")
	_scan(lang, "карточка ремонта (вступление)", rc)
	rc.queue_free()
	# письмо мамы из вступления (раньше текст не был виден)
	var intro := Intro.new()
	city.add_child(intro)
	intro.city = city
	intro._show_photo()
	await get_tree().create_timer(0.8).timeout
	for ch in city.get_children():
		if ch is CanvasLayer and (ch as CanvasLayer).layer == 9:
			_scan(lang, "письмо мамы", ch)
			ch.queue_free()
	city.get_tree().paused = false
	intro.queue_free()
	# смена
	var m: Node2D = load(Nav.BREW).instantiate()
	m.level = Data.levels[40].duplicate(true)
	city.add_child(m)
	await get_tree().create_timer(0.6).timeout
	_scan(lang, "смена", m)
	# смена с рейкой добавок: плашка загадки для каждого напитка и чек с добавками
	GameState.unlocks.append_array(["source:ice", "source:spice", "source:cream", "source:syrup", "drink:cocoa"])
	GameState.upgrades.append_array(["milk_pitcher", "espresso_pro"])
	var m2: Node2D = load(Nav.BREW).instantiate()
	m2.level = Data.levels[55].duplicate(true)
	m2.level["interval"] = [90.0, 90.0]
	city.add_child(m2)
	await get_tree().create_timer(0.5).timeout
	_scan(lang, "смена с рейкой добавок", m2)
	for id in Data.drinks:
		for q in m2._queue.duplicate():
			m2._free_bubble(q)
			(q["cat"] as Node).queue_free()
		m2._queue.clear()
		m2._riddle_seen = false
		m2.level["riddle"] = 1.0
		m2._spawn_customer()
		var q: Dictionary = m2._queue[0]
		q["type"] = "riddle"
		q["order"] = {"drink": String(id), "pastry": "eclair"}
		q["state"] = "wait"
		m2._update_front()
		m2._refresh_clue()
		await get_tree().process_frame
		_scan(lang, "загадка: %s" % id, m2._clue)
		m2._make_bubble(q)
		q["type"] = "normal"
		m2._free_bubble(q)
		m2._make_bubble(q)
		await get_tree().process_frame
		_scan(lang, "чек: %s" % id, q["bubble"])
	# шпаргалка рецептов: все 27 напитков, все страницы
	var rbook := RecipeBook.new()
	for id in Data.drinks:
		rbook.drink_ids.append(String(id))
	rbook.cell_tex = m2._drink_tex
	rbook.base_tex = func(bid: String) -> Texture2D: return m2._drink_tex({"coffee": "espresso", "tea": "tea", "cocoa": "cocoa"}[bid])
	city.add_child(rbook)
	for pg in rbook.page_count():
		rbook._page = pg
		rbook._build()
		await get_tree().process_frame
		_scan(lang, "шпаргалка рецептов, стр. %d" % (pg + 1), rbook)
	rbook.queue_free()
	m2.queue_free()
	m._stats["served"] = 9
	m._points = 640
	m._points_cap = 900
	m._points_lost = 200
	m.shift_earned = 123
	m._finish_run()
	await get_tree().create_timer(0.3).timeout
	_scan(lang, "итог смены", m._result)
	m.queue_free()
	city.queue_free()
	await get_tree().process_frame
	# украшение
	var d: Node2D = load(Nav.DECORATE).instantiate()
	add_child(d)
	await get_tree().process_frame
	_scan(lang, "украшение", d)
	d.queue_free()
	# заставка
	var comic := IntroComic.new()
	add_child(comic)
	await get_tree().create_timer(1.6).timeout
	_scan(lang, "заставка", comic)
	comic.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- проверки

func _scan(lang: String, screen: String, root: Node) -> void:
	_checked += 1
	_screen = "[%s] %s" % [lang, screen]
	var buttons: Array[Button] = []
	_walk(root, buttons)
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a := buttons[i].get_global_rect()
			var b := buttons[j].get_global_rect()
			if a.size.x > 8 and b.size.x > 8 and a.intersection(b).get_area() > 4.0 and buttons[i].get_parent() == buttons[j].get_parent() and not (buttons[i] is BaseButton and buttons[i].get_parent() == null):
				_add("кнопки перекрываются: «%s» и «%s»" % [buttons[i].text, buttons[j].text])


func _walk(n: Node, buttons: Array[Button]) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is ScrollContainer:
		return   # прокручиваемое (каталог украшения): за краем — нормально
	if n is Label:
		_check_label(n as Label)
	elif n is Button:
		var b := n as Button
		_check_button(b)
		if b.text != "" and b.size.x > 8:
			buttons.append(b)
	for c in n.get_children():
		_walk(c, buttons)


func _text_size(font: Font, text: String, size: int) -> Vector2:
	var w := 0.0
	var lines := text.split("\n")
	for l in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return Vector2(w, font.get_height(size) * lines.size())


func _check_label(l: Label) -> void:
	var text := l.get_parent().tr(l.text) if l.text != "" else ""
	if text.strip_edges() == "":
		return
	var font: Font = l.get_theme_font("font")
	var size := l.get_theme_font_size("font_size")
	var rect := l.get_global_rect()
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		var wrapped := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, size)
		var limit: float = float(l.get_meta("max_h")) if l.has_meta("max_h") else rect.size.y
		if wrapped.y > limit + 1.0:
			_add("подпись «%s» не помещается по высоте (%d > %d, ширина %d)" % [text.left(30).replace("\n", " "), wrapped.y, limit, rect.size.x])
	else:
		var need := _text_size(font, text, size)
		if need.x > rect.size.x + 1.0:
			_add("подпись «%s» шире рамки (%d > %d)" % [text.left(30).replace("\n", " "), need.x, rect.size.x])
	if rect.position.x < -1.0 or rect.end.x > 361.0 and rect.size.x < 400.0 or rect.position.y < -1.0 or rect.end.y > 641.0 and rect.size.y < 400.0:
		_add("подпись «%s» за краем экрана %s" % [text.left(24), rect])
	if int(rect.position.x) % 2 != 0 or int(rect.position.y) % 2 != 0:
		_add("подпись «%s» не по сетке арта: (%s, %s)" % [text.left(24), rect.position.x, rect.position.y])


func _check_button(b: Button) -> void:
	if b.text.strip_edges() == "":
		return
	var text := b.get_parent().tr(b.text)
	var font: Font = b.get_theme_font("font")
	var size := b.get_theme_font_size("font_size")
	var sb := b.get_theme_stylebox("normal")
	var inner := b.size.x - sb.content_margin_left - sb.content_margin_right
	var need := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if need > inner + 1.0:
		_add("кнопка «%s» шире поля (%d > %d)" % [text.left(30), need, inner])
	var rect := b.get_global_rect()
	if rect.position.x < -1.0 or rect.end.x > 361.0 or rect.position.y < -1.0 or rect.end.y > 641.0:
		_add("кнопка «%s» за краем экрана %s" % [text.left(24), rect])
	if int(rect.position.x) % 2 != 0 or int(rect.position.y) % 2 != 0 or int(rect.size.x) % 2 != 0 or int(rect.size.y) % 2 != 0:
		_add("кнопка «%s» не по сетке арта: %s" % [text.left(24), rect])


func _add(msg: String) -> void:
	var line := "%s: %s" % [_screen, msg]
	if not (line in _issues):
		_issues.append(line)
