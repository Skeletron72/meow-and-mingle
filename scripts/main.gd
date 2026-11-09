extends Node2D
## Смена за стойкой — уровень со звёздами. Коты приходят и встают в очередь (до 3 у стойки), у каждого свой заказ и терпение:
## ждущий кот нервничает, потом злится и уходит. Заказ собираешь на подносе перетаскиванием (основа → молоко → выпечка) и
## подаёшь подносом любому коту из очереди. В конце — итог и три звезды: смена пройдена, точность, скорость (data/levels.json). Всё нарисовано кодом (BrewArt, ServingTray),
## события сопровождаются эффектами (Fx): пар, брызги, сердечки, монеты, конфетти.
##
## Режим обучения (tutorial = true): только заданные источники и заказы, без бонуса за скорость,
## неверный заказ кота не прогоняет, подсказка-рука показывает следующий шаг.

## Смена закончена (кнопка выхода): сколько подано и заработано. Когда сцена встроена в город — освобождается сам город.
signal closed(served: int, earned: int)
## Обучающая смена пройдена (все заказы из tutorial_orders поданы).
signal tutorial_finished(served: int, earned: int)

const TRAY_HOME := Vector2(180, 304)
const CAT_POS := Vector2(180, 244)
const CAT_SPAWN_X := 460.0
const SLOT_X: Array[float] = [180.0, 284.0, 76.0]   # места в очереди у стойки (по порядку занятия)
const BUBBLE_Y := 142.0
const TUTORIAL_GAP := 1.0   # в обучении: пауза до следующего кота
const PASTRY_CHANCE := 0.5
const BIN_POS := Vector2(320, 360)
const FINGER_LIFT := Vector2(0, -48)   # перетаскиваемое держим над пальцем: подушечка закрывает ~50 px под точкой касания
const COIN_POS := Vector2(28, 26)   # центр области плашки (6..54) над нижней тенью
const INK := Ui.INK

const COFFEE_SHEET: Texture2D = preload("res://assets/cafe/drinks-and-pastries.png")  # сетка 16x16, 5 колонок
const FURN: Texture2D = preload("res://assets/cafe/neko-cafe-furnitures.png")

var embedded := false   # true — смена идёт поверх города, а не отдельной сценой
var shift_served := 0
var shift_earned := 0
var streak := 0         # подряд верных заказов
var level: Dictionary = {}   # данные уровня из data/levels.json; пусто — обучение или тест
var tutorial := false
const RUSHED_PATIENCE := 0.65
const COURIER_PATIENCE := 0.8
const COLD_PRICE := 0.7      # остывший напиток: цена ×0,7 и без чаевых
const RIDDLE_PATIENCE := 1.5 # загадочный гость думает дольше
const RIDDLE_PRICE := 2
var _critic_seen := false   # критик приходит раз за смену
var _points := 0            # очки смены
var _points_cap := 0        # сколько очков можно было набрать у уже пришедших гостей
var _points_lost := 0       # сколько из них потеряно (ушёл, не то налили)
var _rescue_used := false   # страховка за ролик: раз за смену
var _hint_used := false     # подсказка к загадке за ролик: раз за смену
var _paused := false        # открыта шпаргалка рецептов: терпение, остывание и приход гостей стоят
var _pause_started := 0
var _cozy_coins := 0.0     # чаевые за смену, которые принёс Уют (для строки в итогах)
var _riddle_seen := false   # загадочный гость приходит раз за смену
var _cup_age := 0.0         # сколько секунд горячий напиток стоит на подносе
var _rail_n := 0            # сколько баночек-добавок (лёд, корица, сливки) на полке
var _clue: Node2D           # плашка с загадкой
var _title: Label           # вывеска «Тёплая Лапка» (прячется за плашкой загадки)
var tutorial_orders: Array[Dictionary] = []   # {"cat": id кота, "drink": id, "pastry": id|""} — по порядку
var tutorial_sources: Array[String] = []      # id источников, которые показаны (пусто — все)

var _cup := CupState.new()
var _sources: Array[Dictionary] = []   # {kind, id, rect, tex, icon, center}
var _drag: Dictionary = {}
var _cat: CatCustomer                  # первый ждущий кот (для подсказок обучения и тестов)
var _order: Dictionary = {}            # его заказ {"drink": id, "pastry": id|""}
var _awaiting := false                 # есть ли ждущий кот
var _queue: Array[Dictionary] = []     # очередь: {"cat", "def", "order", "patience", "max", "slot", "state": walk|wait|done, "t0", "bubble", "bar", "mood", "tick"}
var _spawned := 0
var _spawn_in := 0.8
var _run_over := false
var _stats := {"served": 0, "wrong": 0, "left": 0, "times": []}
var _result: Node2D
var _tutorial_done_sent := false
var _tutorial_index := 0
var _run_started_msec := 0
var boosters: Array[String] = []   # бустеры на эту смену (выбраны перед началом, списаны со склада)
var _auto_left := 0               # сколько заказов ещё соберёт «Автосборка»
var _forgive_left := 0            # сколько ошибок ещё простит «Помощь кота»
var _idle_msec := 0
var _shown_coins := 0.0

var _cat_layer: Node2D
var _fx: Node2D
var _tray: ServingTray
var _bin: BrewArt.Bin
var _table: BrewArt
var _cup_hint: Label
var _coach_label: Label
var _coach_hand: TextureRect
var _coach_glow: Sprite2D
var _coach_base := Vector2.ZERO
var _coin_icon: Sprite2D
var _coins_label: Label
var _served_label: Label


func _ready() -> void:
	Fx.unit = BrewArt.G   # эффекты крупного плана: пиксель эффекта = пиксель спрайтов (4)
	_build_wall()
	_cat_layer = Node2D.new()
	add_child(_cat_layer)
	_build_counter()
	_build_table()
	_tray = ServingTray.new()
	_cup.allow_double = GameState.has_upgrade("espresso_pro") and not tutorial
	_tray.position = TRAY_HOME
	add_child(_tray)
	_cup_hint = _label("Собери заказ на подносе", Rect2(64, 344, 240, 32), Color("fff1d6"), null, true)
	_cup_hint.add_theme_color_override("font_outline_color", Ui.INK)
	_cup_hint.add_theme_constant_override("outline_size", Ui.PX * 2)
	_fx = Node2D.new()
	_fx.z_index = 40
	add_child(_fx)
	_build_hud()
	_build_coach()
	GameState.coins_changed.connect(_on_coins_changed)
	_shown_coins = GameState.coins
	_coins_label.text = str(GameState.coins)
	_served_label.text = tr("Подано: %d") % GameState.served_total
	_refresh_cup()
	_begin_run()


func _exit_tree() -> void:
	Fx.unit = 2.0


# ---------------------------------------------------------------- построение сцены

func _build_wall() -> void:
	var wall := BrewArt.new()
	wall.part = BrewArt.Part.WALL
	add_child(wall)
	_title = Ui.label("Тёплая Лапка", Rect2(76, 58, 208, 36), Ui.FONT_SIZE, Color("ffe6b0"), self, HORIZONTAL_ALIGNMENT_CENTER, true)
	_title.add_theme_color_override("font_outline_color", Color("3f2815"))
	_title.add_theme_constant_override("outline_size", Ui.PX * 2)
	# банки и чашки на боковых полках рисует BrewArt
	for x in [44.0, 316.0]:
		var lamp := BrewArt.PendantLamp.new()
		lamp.position = Vector2(x, 0)
		add_child(lamp)
	Fx.motes(self, Rect2(120, 70, 190, 170), 18)


func _build_counter() -> void:
	var counter := BrewArt.new()
	counter.part = BrewArt.Part.COUNTER
	add_child(counter)
	# кофемашина и растение на столешнице; из машины идёт пар
	# кофемашина и растение стоят на боковых полках над прилавком; на их месте на прилавке — молоко и сироп (когда открыты)
	var machine := _sprite(_atlas(FURN, Rect2(131, 67, 11, 13)), Vector2(44, 200), 4.0)
	machine.offset = Vector2(0, -6.5)
	machine.z_index = 1
	Fx.steam(self, Vector2(44, 160), 5).emitting = true
	var plant := _sprite(_atlas(FURN, Rect2(97, 80, 14, 16)), Vector2(320, 200), 4.0)
	plant.offset = Vector2(0, -8)
	plant.z_index = 1
	_bin = BrewArt.Bin.new()
	_bin.position = BIN_POS
	add_child(_bin)


## Стол-стеллаж: три полки по смыслу — основы (кофе, чай, какао), добавки (молоко, сироп, лёд, корица, сливки) и выпечка. Предметы стоят на полке,
## подписи — на её передней планке. Координаты полок и ячеек ФИКСИРОВАНЫ (мышечная память пальца): закрытый предмет — тёмный силуэт на своём месте,
## закрытая полка — пустая планка с подписью «Откроется: …»; открытие ничего не сдвигает. В обучении — одна полка и только нужные предметы по центру.
const SHELF_TOPS: Array[float] = [384.0, 468.0, 552.0]


func _build_table() -> void:
	_table = BrewArt.new()
	_table.part = BrewArt.Part.TABLE
	add_child(_table)
	var groups: Array = [
		[
			{"kind": "base", "id": "coffee", "title": "Кофе", "tex": _drink_tex("espresso")},
			{"kind": "base", "id": "tea", "title": "Чай", "tex": _drink_tex("tea")},
			{"kind": "base", "id": "cocoa", "title": "Какао", "tex": _drink_tex("cocoa")},
		],
		[
			{"kind": "milk", "id": "milk", "title": "Молоко", "tex": PixelArt.shelf_icon("milk")},
			{"kind": "syrup", "id": "syrup", "title": "Сироп", "tex": PixelArt.shelf_icon("syrup")},
			{"kind": "extra", "id": "ice", "title": "Лёд", "unlock": "ice", "tex": PixelArt.extra_jar("ice")},
			{"kind": "extra", "id": "cinnamon", "title": "Корица", "unlock": "spice", "tex": PixelArt.extra_jar("cinnamon")},
			{"kind": "extra", "id": "cream", "title": "Сливки", "unlock": "cream", "tex": PixelArt.extra_jar("cream")},
		],
		[],
	]
	for id in _pastry_menu():
		groups[2].append({"kind": "pastry", "id": id, "title": String(Data.pastries[id]["name"]), "tex": _pastry_tex(id)})
	_table.plates = []
	_table.shelves = []
	_rail_n = 0
	var locked_text := ["", "Молочник", "Витрина"]
	for r in groups.size():
		var top := SHELF_TOPS[r]
		var items: Array = groups[r]
		var open: Array[Dictionary] = []
		for it in items:
			if _source_available(it) and not (tutorial and String(it["kind"]) == "extra"):
				open.append(it)
		if tutorial and r > 0:
			continue   # в обучении лишних полок нет
		_table.shelves.append(top)
		if open.is_empty() and r > 0:
			var sign := Ui.label(tr("Откроется: %s") % tr(String(locked_text[r])), Rect2(8.0, top + 58.0, 344.0, 24.0), 20, Ui.INK.lightened(0.15), self, HORIZONTAL_ALIGNMENT_CENTER, true)
			sign.z_index = 3
			continue
		var open_ids := {}
		for it in open:
			open_ids[String(it["id"])] = true
		var slots := _slots(r, open.size() if tutorial else [3, 5, 3][r])
		for i in slots.size():
			var cx: float = slots[i]
			if tutorial:
				_place_source(open[i].duplicate(), cx, top)
			elif i < items.size():
				var it: Dictionary = items[i]
				if open_ids.has(String(it["id"])):
					_place_source(it.duplicate(), cx, top)
				else:
					_place_silhouette(it, cx, top)
	_table.queue_redraw()


## Центры ячеек ряда r (кратны 4): основы и выпечка — 3 места, добавки — 5; в обучении — по числу предметов по центру.
func _slots(r: int, n: int) -> Array[float]:
	var step := 112.0 if (tutorial or r != 1) else 68.0
	var out: Array[float] = []
	for i in n:
		out.append(180.0 + (float(i) - (n - 1) / 2.0) * step)
	return out


## Тёмный силуэт ещё не открытого предмета на его месте (подсказка, что здесь появится) и «?» на планке.
func _place_silhouette(s: Dictionary, cx: float, top: float) -> void:
	var tex: Texture2D = s["tex"]
	var c := Vector2(cx, top + 32.0)
	var icon := _sprite(tex, c - BrewArt.content_offset(tex, String(s["kind"]) == "base") * 4.0, 4.0)
	icon.z_index = 2
	icon.modulate = Color(0.0, 0.0, 0.0, 0.32)
	var q := Ui.label("?", Rect2(cx - 34.0, top + 58.0, 68.0, 24.0), 20, Ui.INK.lightened(0.2), self, HORIZONTAL_ALIGNMENT_CENTER, true)
	q.z_index = 3


## Источник на полке: спрайт в масштабе 4 по центру ячейки, подпись на планке, зона нажатия — вся ячейка.
func _place_source(s: Dictionary, cx: float, top: float) -> void:
	var step := 68.0 if (String(s["kind"]) in ["milk", "syrup", "extra"] and not tutorial) else 112.0
	var c := Vector2(cx, top + 32.0)
	s["center"] = c
	s["shelf"] = true
	s["rect"] = Rect2(cx - step / 2.0, top, step, BrewArt.SHELF_STRIDE)
	var tex: Texture2D = s["tex"]
	var rest := c - BrewArt.content_offset(tex, String(s["kind"]) == "base") * 4.0   # рисунок по центру ячейки
	if String(s["kind"]) == "pastry":
		rest.y -= 4.0   # выпечка стоит на блюдце — чуть выше
	s["rest"] = rest
	var icon := _sprite(tex, rest, 4.0)
	icon.z_index = 2
	s["icon"] = icon
	_sources.append(s)
	if String(s["kind"]) == "extra":
		_rail_n += 1
	if String(s["kind"]) == "pastry":
		_table.plates.append(Vector2(cx, top + 56.0))
	var cap := Ui.label(tr(String(s["title"])), Rect2(cx - step / 2.0 + 2.0, top + 58.0, step - 4.0, 24.0), 20, Ui.INK, self, HORIZONTAL_ALIGNMENT_CENTER, true)   # на передней планке полки
	cap.z_index = 3
	var rest_y := icon.position.y
	var bob := icon.create_tween().set_loops()   # предметы «дышат» — приподнимаются на целый пиксель сетки, без масштаба
	bob.tween_interval(0.8 + randf() * 0.3)
	bob.tween_callback(func() -> void: icon.position.y = rest_y - Fx.PX_GRID)
	bob.tween_interval(0.8)
	bob.tween_callback(func() -> void: icon.position.y = rest_y)


## Какие источники на столе: в обучении — заданные, иначе по купленным улучшениям и открытому ремонтом (молочник, витрина, какао, сироп).
func _source_available(it: Dictionary) -> bool:
	if tutorial:
		return tutorial_sources.is_empty() or String(it["id"]) in tutorial_sources
	match String(it["kind"]):
		"milk":
			return GameState.has_upgrade("milk_pitcher")
		"syrup":
			return GameState.has_unlock("source:syrup")
		"pastry":
			return GameState.pastries_unlocked()
		"base":
			return String(it["id"]) != "cocoa" or GameState.has_unlock("drink:cocoa")
		"extra":
			return GameState.has_unlock("source:" + String(it["unlock"]))
	return true


## «Меню дня»: до трёх видов выпечки на столе — из списка уровня (pastry_menu), иначе первые доступные.
func _pastry_menu() -> Array[String]:
	var have := GameState.pastry_ids()
	var out: Array[String] = []
	var wanted: Array = level.get("pastry_menu", [])
	for id in wanted:
		if String(id) in have and out.size() < 3:
			out.append(String(id))
	if out.is_empty():
		for id in have:
			if out.size() < 3:
				out.append(id)
	return out


func _build_hud() -> void:
	Ui.panel(Rect2(8, 6, 112, 48), Ui.UI_CREAM, self).z_index = 80
	_coin_icon = _sprite(Ui.icon("coin"), COIN_POS, 2.0)
	_coin_icon.z_index = 81
	_coins_label = _label("0", Rect2(44, 12, 76, 32), INK)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_coins_label.z_index = 81
	_served_label = _label("", Rect2(124, 10, 166, 32), Color("fff1d6"), null, true)
	_served_label.add_theme_color_override("font_outline_color", INK)
	_served_label.add_theme_constant_override("outline_size", Ui.PX * 2)
	_served_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_served_label.z_index = 81
	if not tutorial:   # шпаргалка рецептов: одно касание, смена на паузе
		var book := Ui.button("", Rect2(8, 340, 52, 44), "book", self)
		book.z_index = 60
		book.pressed.connect(_open_book)
	var end_btn := Ui.button("", Rect2(296, 6, 56, 48), "exit", self)
	end_btn.z_index = 82
	end_btn.visible = not tutorial   # обучающую смену нельзя бросить
	end_btn.pressed.connect(_end_shift)


## Подсказка обучения: текст на столешнице, рука и свечение у нужного источника.
func _build_coach() -> void:
	_coach_label = _label("", Rect2(10, 346, 340, 32), Color("fff1d6"), null, true)
	_coach_label.add_theme_color_override("font_outline_color", INK)
	_coach_label.add_theme_constant_override("outline_size", Ui.PX * 2)
	_coach_label.visible = false
	_coach_label.z_index = 60
	_coach_hand = TextureRect.new()
	_coach_hand.texture = Ui.icon("hand")
	_coach_hand.stretch_mode = TextureRect.STRETCH_SCALE
	_coach_hand.size = Vector2(24, 30)
	_coach_hand.pivot_offset = Vector2(12, 4)
	_coach_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach_hand.visible = false
	_coach_hand.z_index = 61
	add_child(_coach_hand)


# ---------------------------------------------------------------- очередь котиков и заказы

func _total_customers() -> int:
	return tutorial_orders.size() if tutorial else int(level.get("customers", 8))


func _max_queue() -> int:
	return 1 if tutorial else clampi(int(level.get("queue", 3)), 1, SLOT_X.size())


## Начало (или перезапуск) смены: счётчики в ноль, коты пойдут по расписанию уровня.
func _begin_run() -> void:
	if level.is_empty() and not tutorial:
		level = Data.levels[0].duplicate(true)
	for e in _queue:
		if is_instance_valid(e["cat"]):
			(e["cat"] as CatCustomer).queue_free()
		_free_bubble(e)
	_queue.clear()
	_spawned = 0
	_spawn_in = 0.8
	_run_over = false
	_tutorial_index = 0
	_tutorial_done_sent = false
	_stats = {"served": 0, "wrong": 0, "left": 0, "times": []}
	_run_started_msec = Time.get_ticks_msec()
	Audio.music("shift")
	_critic_seen = false
	_riddle_seen = false
	_rescue_used = false
	_points = 0
	_points_cap = 0
	_points_lost = 0
	_hint_used = false
	_cozy_coins = 0.0
	_cup_age = 0.0
	_auto_left = 3 if ("auto" in boosters and not tutorial) else 0
	_forgive_left = 1 if ("cat_help" in boosters and not tutorial) else 0
	if not tutorial:
		Platform.track("level_start", {"id": String(level.get("id", "?")), "stars": GameState.level_star_count(String(level.get("id", "?")))})
	shift_served = 0
	shift_earned = 0
	streak = 0
	_update_front()
	_refresh_progress()


func _active_count() -> int:
	var n := 0
	for e in _queue:
		if e["state"] != "done":
			n += 1
	return n


func _free_slot() -> int:
	var taken := {}
	for e in _queue:
		taken[int(e["slot"])] = true
	for i in SLOT_X.size():
		if not taken.has(i):
			return i
	return -1


## Первый ждущий кот в очереди (по порядку прихода) или пустой словарь.
func _front() -> Dictionary:
	for e in _queue:
		if e["state"] == "wait":
			return e
	return {}


## Обновляет «первого ждущего»: от него зависят подсказки обучения, ready-свечение и тесты (_cat, _order, _awaiting).
func _update_front() -> void:
	_refresh_clue()
	var f := _front()
	_awaiting = not f.is_empty()
	_cat = f["cat"] if _awaiting else null
	_order = f["order"] if _awaiting else {}


## Плашка с загадкой загадочного гостя: вывеска прячется, на её месте — подсказка словами (пока такой гость ждёт).
func _refresh_clue(force := false) -> void:
	var key := ""
	for e in _queue:
		if e["state"] == "wait" and String(e.get("type", "")) == "riddle":
			key = String(e["order"]["drink"])
			break
	if not force and _clue != null and is_instance_valid(_clue) and String(_clue.get_meta("key", "")) == key:
		return
	if _clue != null and is_instance_valid(_clue):
		_clue.queue_free()
	_clue = null
	if _title != null:
		_title.visible = key == ""
	if key == "":
		return
	_clue = Node2D.new()
	_clue.z_index = 70
	_clue.set_meta("key", key)
	add_child(_clue)
	Ui.panel(Rect2(12, 48, 336, 58), Ui.UI_CREAM, _clue)
	var l := Ui.label(tr(String(Data.drinks[key]["riddle"])), Rect2(22, 52, 264 if not _hint_used else 316, 48), 20, Ui.INK, _clue, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
	l.position = Vector2(22, 52)
	l.size = Vector2(264 if not _hint_used else 316, 48)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_meta("max_h", 48.0)
	if not _hint_used and not tutorial and Shop.ad_ready("riddle_hint"):   # подсказка за ролик
		var hb := Ui.button("", Rect2(292, 54, 48, 44), "video", _clue)
		hb.pressed.connect(_riddle_hint)
	Fx.rise_in(_clue, 12.0, 0.25, 2.0)


## Напитки, которые гость может заказать на этом уровне: доступные игроку и из списка уровня (pool), которые есть на столе.
func _orderable_drinks() -> Array[String]:
	var avail := GameState.drink_ids()
	var pool: Array = level.get("pool", [])
	if not pool.is_empty():
		avail = avail.filter(func(id: String) -> bool: return id in pool)
	avail = avail.filter(func(id: String) -> bool: return _drink_makeable(id))
	return avail if not avail.is_empty() else (["espresso"] as Array[String])


## Напиток можно собрать из того, что есть на столе (основа, молоко, сироп).
func _drink_makeable(id: String) -> bool:
	var r: Dictionary = Data.drinks[id]["recipe"]
	if String(r["base"]) == "cocoa" and not GameState.has_unlock("drink:cocoa"):
		return false
	if bool(r["milk"]) and not GameState.has_upgrade("milk_pitcher"):
		return false
	if bool(r.get("syrup", false)) and not GameState.has_unlock("source:syrup"):
		return false
	var need := {"ice": "source:ice", "cinnamon": "source:spice", "cream": "source:cream"}
	for m in r.get("mods", []):
		if String(m) == "double":
			if not GameState.has_upgrade("espresso_pro"):
				return false
		elif not GameState.has_unlock(String(need.get(String(m), "")) ):
			return false
	return true


## Начинка для заказа выпечки: одна (чаще) или две из доступных — сироп, сливки, корица.
func _pick_pastry_mods() -> Array[String]:
	var have: Array[String] = []
	if GameState.has_unlock("source:syrup"):
		have.append("syrup")
	if GameState.has_unlock("source:cream"):
		have.append("cream")
	if GameState.has_unlock("source:spice"):
		have.append("cinnamon")
	have.shuffle()
	var n := mini(have.size(), 2 if randf() < 0.3 else 1)
	var out: Array[String] = []
	for i in n:
		out.append(have[i])
	return out


## Терпение гостей: таланты котов и уют кафе.
func _patience_bonus() -> float:
	return 1.0 if tutorial else 1.0 + GameState.perk_total("patience") + GameState.cozy_patience_bonus()


func _spawn_customer() -> void:
	var slot := _free_slot()
	if slot < 0:
		return
	var def: Dictionary = GameState.cats_available().pick_random()
	var type := "normal"   # normal / rushed (терпение ×0,65, чаевые ×2 за быструю подачу) / gourmet (напиток + выпечка, цена ×2)
	var drink_id := ""
	var pastry_id := ""
	var pastry_mods: Array[String] = []   # начинка на выпечке
	if tutorial:
		var o: Dictionary = tutorial_orders[_tutorial_index]
		drink_id = String(o["drink"])
		pastry_id = String(o.get("pastry", ""))
		for c in Data.cats:
			if String(c["id"]) == String(o.get("cat", "")):
				def = c
	else:
		var busy := _queue.map(func(e: Dictionary) -> String: return String(e["def"]["id"]))   # одинаковых котов подряд не пускаем
		var others := GameState.cats_available().filter(func(c: Dictionary) -> bool: return not (String(c["id"]) in busy))
		if not others.is_empty():
			def = others.pick_random()
		var avail := _orderable_drinks()
		drink_id = avail.pick_random()
		if String(def.get("fav_drink", "")) in avail and randf() < 0.4:
			drink_id = String(def["fav_drink"])   # любимый напиток кот заказывает чаще
		var menu := _pastry_menu()
		var tp: Dictionary = level.get("types", {})
		var roll := randf()
		var role := String(def.get("role", "normal"))
		if role == "critic" and (_critic_seen or menu.is_empty()):
			role = "normal"   # критик приходит один раз за смену и только к выпечке
		if role in ["rushed", "gourmet", "courier", "critic"]:
			type = role   # у некоторых котов характер: Сухарик всегда спешит, Баюн и Усов — гурманы, Кефир — курьер, Барон — критик
		elif not _critic_seen and not menu.is_empty() and randf() < float(tp.get("critic", 0.0)) * 0.5:
			type = "critic"
		elif roll < float(tp.get("rushed", 0.0)):
			type = "rushed"
		elif roll < float(tp.get("rushed", 0.0)) + float(tp.get("gourmet", 0.0)):
			type = "gourmet"
		elif roll < float(tp.get("rushed", 0.0)) + float(tp.get("gourmet", 0.0)) + float(tp.get("courier", 0.0)):
			type = "courier"
		if type == "normal" and not _riddle_seen and randf() < float(level.get("riddle", 0.0)):
			type = "riddle"   # загадочный гость: вместо чека с напитком — «?» и подсказка словами
		if type == "critic":
			_critic_seen = true
		if type == "riddle":
			_riddle_seen = true
		if not menu.is_empty() and type != "courier" and (type in ["gourmet", "critic"] or randf() < float(level.get("pastry", 0.0))):
			pastry_id = menu.pick_random()
			if randf() < float(level.get("pastry_mods", 0.0)):
				pastry_mods = _pick_pastry_mods()
	var patience := INF if tutorial else float(level.get("patience", 40.0)) * randf_range(0.85, 1.15) * (RUSHED_PATIENCE if type == "rushed" else (COURIER_PATIENCE if type == "courier" else (RIDDLE_PATIENCE if type == "riddle" else 1.0))) * (1.3 if "patience" in boosters else 1.0) * _patience_bonus()
	var cat := CatCustomer.new()
	_cat_layer.add_child(cat)
	cat.setup(def)
	cat.position = Vector2(CAT_SPAWN_X, CAT_POS.y)
	var pot := GameState.POINTS_PER_GUEST * (2 if type == "critic" else 1)
	_points_cap += pot
	var e := {"pot": pot, "cat": cat, "def": def, "order": {"drink": drink_id, "pastry": pastry_id, "pastry_mods": pastry_mods}, "patience": patience, "max": patience, "type": type, "slot": slot,
		"state": "walk", "t0": 0, "bubble": null, "bar": null, "mood": 0, "tick": 0.0}
	_queue.append(e)
	cat.arrived.connect(_on_cat_arrived.bind(e))
	cat.left.connect(_on_cat_left.bind(cat))
	cat.enter(SLOT_X[slot])
	_spawned += 1
	_refresh_progress()


func _on_cat_arrived(e: Dictionary) -> void:
	if e["state"] != "walk":
		return
	e["state"] = "wait"
	e["t0"] = Time.get_ticks_msec()
	_idle_msec = Time.get_ticks_msec()
	_make_bubble(e)
	_try_autofill(e)
	Fx.burst(_fx, (e["cat"] as CatCustomer).center() + Vector2(0, -44), "sparkle", Color("fff3b0"), 5, 90.0, 40.0, 0.6, 0.8)
	_update_front()
	_refresh_cup()


## «Автосборка»: первые три заказа смены поднос собирает сам (если поднос пуст и кот первый в очереди).
func _try_autofill(e: Dictionary) -> void:
	if _auto_left <= 0 or not _cup.is_empty() or _front() != e:
		return
	_auto_left -= 1
	var order: Dictionary = e["order"]
	_cup.fill(String(order["drink"]), String(order["pastry"]), order.get("pastry_mods", []))
	_toast(tr("Автосборка!"), Vector2(180, 430))
	Audio.sfx("pop")
	Fx.burst(_fx, _tray.position + Vector2(0, -30), "sparkle", Color("ffe9a0"), 8, 130.0, 100.0, 0.7, 1.0)
	_refresh_cup()


func _on_cat_left(cat: CatCustomer) -> void:
	cat.queue_free()


## Чек над котом: иконки заказа и полоска терпения.
func _make_bubble(e: Dictionary) -> void:
	var b := Node2D.new()
	b.position = Vector2(SLOT_X[int(e["slot"])], BUBBLE_Y)
	b.z_index = 6
	add_child(b)
	var order: Dictionary = e["order"]
	var riddle := String(e.get("type", "normal")) == "riddle"
	var mods: Array = [] if riddle else (Data.drinks[String(order["drink"])]["recipe"].get("mods", []) as Array)
	var pmods: Array = order.get("pastry_mods", []) as Array
	var extra_h := 18.0 if (not mods.is_empty() or not pmods.is_empty()) else 0.0   # ряд значков добавок под иконками
	Ui.panel(Rect2(-52, -36, 104, 72 + extra_h), Ui.UI_CREAM, b)
	for i in 3:   # хвостик чека к коту
		var w := 16.0 - i * 4.0
		var tail := ColorRect.new()
		tail.position = Vector2(-w / 2.0, 36 + extra_h + i * 4)
		tail.size = Vector2(w, 4)
		tail.color = Color("fff0cd")
		tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tail)
	var drink_x := 0.0
	var icons: Array[Sprite2D] = []
	if String(order["pastry"]) != "":
		drink_x = -26.0
		var pt := _pastry_tex(order["pastry"])
		icons.append(_sprite(pt, Vector2(26, -12) - BrewArt.content_offset(pt) * 2.0, 2.0, b))
	if riddle:   # загадка: вместо напитка — «?», подсказка словами на плашке сверху
		var q := Ui.label("?", Rect2(drink_x - 24, -34, 48, 44), Ui.FONT_SIZE_BIG, Color("9a3fb0"), b, HORIZONTAL_ALIGNMENT_CENTER)
		q.add_theme_color_override("font_outline_color", Ui.CREAM)
		q.add_theme_constant_override("outline_size", Ui.PX * 2)
	else:
		var dt := _drink_tex(order["drink"])
		icons.append(_sprite(dt, Vector2(drink_x, -12) - BrewArt.content_offset(dt, true) * 2.0, 2.0, b))
	for i in mods.size():
		var mb := _sprite(PixelArt.extra_icon(String(mods[i])), Vector2(drink_x + (float(i) - (mods.size() - 1) / 2.0) * 24.0, 14), 2.0, b)
		mb.z_index = 1
	for i in pmods.size():   # начинка на выпечке — под блюдом справа
		var pb := _sprite(PixelArt.extra_icon(String(pmods[i])), Vector2(26.0 + (float(i) - (pmods.size() - 1) / 2.0) * 24.0, 14), 2.0, b)
		pb.z_index = 1
	if not is_inf(float(e["max"])):   # полоска терпения
		var back := ColorRect.new()
		back.position = Vector2(-42, 18 + extra_h)
		back.size = Vector2(84, 10)
		back.color = Ui.INK
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(back)
		var fill := ColorRect.new()
		fill.position = Vector2(-40, 20 + extra_h)
		fill.size = Vector2(80, 6)
		fill.color = Color("8dff7a")
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(fill)
		e["bar"] = fill
	e["bubble"] = b
	var kind := String(e.get("type", "normal"))
	if kind != "normal" and kind != "riddle":   # метка типа в углу чека: «!» — спешит, «x2» — гурман, «»» — курьер, «★» — критик
		var marks := {"rushed": "!", "gourmet": "x2", "courier": "»", "critic": "★"}
		var colors := {"rushed": Color("e0432f"), "gourmet": Color("c2891a"), "courier": Color("3a7fd0"), "critic": Color("9a3fb0")}
		var mark := Ui.label(String(marks[kind]), Rect2(14, -40, 44, 28), Ui.FONT_SIZE, colors[kind], b, HORIZONTAL_ALIGNMENT_RIGHT)
		mark.add_theme_color_override("font_outline_color", Ui.CREAM)
		mark.add_theme_constant_override("outline_size", Ui.PX * 2)
	Fx.rise_in(b, 24.0, 0.3, 2.0)
	for i in icons.size():   # значки подпрыгивают друг за другом (твин живёт на самой иконке и умирает вместе с ней)
		var icon := icons[i]
		var tw := icon.create_tween()
		tw.tween_interval(0.3 + i * 0.12)
		tw.tween_callback(Fx.hop.bind(icon, 8.0, 0.3, 2.0))


func _free_bubble(e: Dictionary) -> void:
	var b: Node2D = e.get("bubble")
	if b != null and is_instance_valid(b):
		e["bubble"] = null
		var t := b.create_tween()   # без масштаба: плашка просто гаснет
		t.tween_property(b, "modulate:a", 0.0, 0.15)
		t.tween_callback(b.queue_free)


## Каждый кадр: терпение ждущих котов убывает, настроение и полоска меняются; по расписанию приходят новые коты; в конце — итог.
func _tick_queue(delta: float) -> void:
	for e in _queue.duplicate():
		if e["state"] != "wait" or is_inf(float(e["max"])):
			continue
		e["patience"] = float(e["patience"]) - delta
		var f := clampf(float(e["patience"]) / float(e["max"]), 0.0, 1.0)
		var cat: CatCustomer = e["cat"]
		var bar: ColorRect = e["bar"]
		if bar != null:
			bar.size.x = maxf(4.0, snappedf(80.0 * f, 4.0))
			bar.color = Color("8dff7a") if f > 0.5 else (Color("ffd640") if f > 0.25 else (Color("ff5a4a") if int(Time.get_ticks_msec() / 250) % 2 == 0 else Color("ffb0a0")))
		var mood := 0 if f > 0.5 else (1 if f > 0.25 else 2)
		if mood != int(e["mood"]):
			e["mood"] = mood
			cat.set_mood(mood)
		e["tick"] = float(e["tick"]) - delta
		if mood > 0 and float(e["tick"]) <= 0.0:
			e["tick"] = 2.6 if mood == 1 else 1.4
			if mood == 1:
				Fx.burst(_fx, cat.center() + Vector2(24, -50), "sweat", Color("8fd6ff"), 2, 60.0, 160.0, 0.7, 1.0, 40.0, Vector2(1, -0.4))
			else:
				Fx.burst(_fx, cat.center() + Vector2(20, -52), "anger", Color("ff5a4a"), 1, 20.0, 0.0, 0.6, 1.0, 20.0)
				Fx.shake(cat, 6.0, 0.3, 6, Fx.PX_GRID)
		if float(e["patience"]) <= 0.0:
			_lose_patience(e)
	if tutorial:
		_tick_tutorial(delta)
	else:
		_tick_spawn(delta)
	if not tutorial and not _run_over and _spawned >= _total_customers() and _queue.is_empty() and _tray.visible and _result == null:
		_finish_run()


func _tick_spawn(delta: float) -> void:
	if _spawned >= _total_customers() or _active_count() >= _max_queue():
		return
	_spawn_in -= delta
	if _spawn_in <= 0.0:
		_spawn_customer()
		var iv: Array = level.get("interval", [6.0, 9.0])
		_spawn_in = randf_range(float(iv[0]), float(iv[1]))
		if randf() < float(level.get("wave", 0.0)):
			_spawn_in = randf_range(0.8, 1.6)   # «волна»: следующий гость заходит почти сразу


## Обучение: по одному коту по сценарию; когда все поданы — сообщаем.
func _tick_tutorial(delta: float) -> void:
	if not _queue.is_empty():
		return
	if _tutorial_index >= tutorial_orders.size():
		if not _tutorial_done_sent:
			_tutorial_done_sent = true
			tutorial_finished.emit(shift_served, shift_earned)
		return
	_spawn_in -= delta
	if _spawn_in <= 0.0:
		_spawn_customer()
		_spawn_in = TUTORIAL_GAP


## Кот ушёл, потеряв терпение: счёт ошибок, серия сбита.
func _lose_patience(e: Dictionary) -> void:
	e["state"] = "done"
	_stats["left"] = int(_stats["left"]) + (2 if String(e.get("type", "normal")) == "critic" else 1)   # уход критика стоит двух заказов
	_points_lost += int(e.get("pot", GameState.POINTS_PER_GUEST))
	streak = 0
	_free_bubble(e)
	var cat: CatCustomer = e["cat"]
	Fx.burst(_fx, cat.center() + Vector2(0, -40), "anger", Color("ff5a4a"), 3, 60.0, 0.0, 0.7, 1.0)
	_toast(tr("%s ушёл злой!") % String(e["def"].get("name", "Кот")), Vector2(180, 392))
	Audio.sfx("angry", 0.05, -4.0)
	_shake_screen(4.0)
	cat.leave_angry()
	_queue.erase(e)
	_update_front()
	_refresh_cup()
	_refresh_progress()


## Кот под подносом при отпускании (по ближайшему к нему); пустой словарь — никого.
func _cat_at(p: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for e in _queue:
		if e["state"] != "wait" or not is_instance_valid(e["cat"]):
			continue
		var c: Vector2 = (e["cat"] as CatCustomer).position
		if Rect2(c + Vector2(-56, -86), Vector2(112, 140)).has_point(p) and absf(c.x - p.x) < best_d:
			best = e
			best_d = absf(c.x - p.x)
	return best


func _refresh_progress() -> void:
	if tutorial or level.is_empty():
		return
	var handled := int(_stats["served"]) + int(_stats["left"])
	_served_label.text = tr("%d/%d · очки %d") % [handled, _total_customers(), _points]


# ---------------------------------------------------------------- перетаскивание

func _input(event: InputEvent) -> void:
	if _paused:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(get_global_mouse_position())
		else:
			_end_drag()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_drag_to(get_global_mouse_position())


func _begin_drag(p: Vector2) -> void:
	if not _drag.is_empty():
		return
	_idle_msec = Time.get_ticks_msec()
	if not _tray.is_empty() and Rect2(_tray.position - Vector2(100, 80), Vector2(200, 120)).has_point(p):
		_drag = {"kind": "tray", "grab": FINGER_LIFT}
		_tray.z_index = 50
		_tray.create_tween().tween_property(_tray, "lift", 12.0, 0.12)   # поднимается — тень уезжает вниз
		return
	for s in _sources:
		if (s["rect"] as Rect2).has_point(p):
			var ghost := _sprite(s["tex"], _snap(p + FINGER_LIFT), 4.0)
			ghost.z_index = 100
			_drag = {"kind": s["kind"], "id": s["id"], "ghost": ghost, "src": s}
			Fx.hop(s["icon"], 8.0, 0.25)
			Fx.burst(_fx, (s["center"] as Vector2) + Vector2(0, 10), "dot", Color("ffffff"), 4, 50.0, 60.0, 0.35, 0.8)
			return


func _drag_to(p: Vector2) -> void:
	if _drag["kind"] == "tray":
		_tray.position = _snap(p + (_drag["grab"] as Vector2))
		return
	var ghost: Sprite2D = _drag["ghost"]
	ghost.position = _snap(p + FINGER_LIFT)
	if ghost.position.distance_to(_tray.position + Vector2(0, -20)) < 100.0:   # поднос обводится белым (целиком или нужной половиной), когда ингредиент над ним
		_tray.hot_half = _drop_half(String(_drag["kind"]), String(_drag["id"]), ghost.position)
	else:
		_tray.hot_half = ServingTray.Half.NONE


func _end_drag() -> void:
	if _drag.is_empty():
		return
	var d := _drag
	_drag = {}
	_tray.hot = false
	if d["kind"] == "tray":
		_drop_tray()
		return
	var ghost: Sprite2D = d["ghost"]
	var drop := ghost.position
	var hit := drop.distance_to(_tray.position + Vector2(0, -20)) < 100.0
	if not tutorial:   # телеметрия для живого теста пальцем: куда бросают, попадают ли, какая половина подноса
		Platform.track("drop", {"kind": String(d["kind"]), "id": String(d["id"]), "hit": hit, "half": int(_drop_half(String(d["kind"]), String(d["id"]), drop)), "x": int(drop.x), "y": int(drop.y), "sx": int((d["src"]["center"] as Vector2).x)})
	if hit:
		ghost.queue_free()
		_add_ingredient(String(d["kind"]), String(d["id"]), drop)
	else:   # промах: ингредиент возвращается на место
		var src: Dictionary = d["src"]
		_glide(ghost, src["rest"], 0.2).tween_callback(ghost.queue_free)
	_refresh_cup()


func _drop_tray() -> void:
	_tray.create_tween().tween_property(_tray, "lift", 0.0, 0.12)
	_tray.z_index = 0
	var drop := _tray.position
	if drop.distance_to(BIN_POS) < 52.0:
		_discard_cup()
	elif drop.distance_to(TRAY_HOME) > 40.0 and not _cat_at(drop).is_empty():
		_serve(_cat_at(drop))
	else:
		_return_tray()


func _return_tray() -> void:
	_glide(_tray, TRAY_HOME, 0.22)


## Всё с подноса — в корзину.
func _discard_cup() -> void:
	_bin.hop()
	Fx.burst(_fx, BIN_POS + Vector2(0, -16), "puff", Color(0.8, 0.8, 0.85), 6, 70.0, -20.0, 0.6, 1.0, 50.0)
	Audio.sfx("whoosh")
	_cup.clear()
	_cup_age = 0.0
	_tray.set_contents(null, null)
	_tray.set_ready(false)
	_glide(_tray, TRAY_HOME, 0.25)
	_refresh_cup()


## Очки за поданный заказ: потолок гостя (100, критик 200) × скорость: в пределах цели уровня — всё, до 1,6× цели — 80%, медленнее — 60%. В обучении очков нет.
func _order_points(elapsed: float, e: Dictionary) -> int:
	var pot := int(e.get("pot", GameState.POINTS_PER_GUEST))
	var target := float(level.get("speed", 10.0))
	var k := 1.0 if elapsed <= target else (0.8 if elapsed <= target * 1.6 else 0.6)
	return int(round(pot * k))


## Сколько шагов в заказе: основа, молоко, сироп, добавки напитка + выпечка и её начинки.
func _order_steps(order: Dictionary) -> int:
	var r: Dictionary = Data.drinks[String(order["drink"])]["recipe"]
	var n := 1 + (1 if bool(r["milk"]) else 0) + (1 if bool(r.get("syrup", false)) else 0) + (r.get("mods", []) as Array).size()
	if String(order["pastry"]) != "":
		n += 1 + (order.get("pastry_mods", []) as Array).size()
	return n


## Страховка за ролик: сложный заказ (4+ шага) собран с ошибкой — один раз за смену можно очистить поднос, и гость не уйдёт. Возвращает true, если
## показано предложение (подача отложена до ответа). Не работает в обучении, при отключённых окнах (тесты) и без доступной рекламы.
func _rescue_offer(e: Dictionary) -> bool:
	if tutorial or _rescue_used or _forgive_left > 0 or GameState.suppress_popups or _order_steps(e["order"]) < 4 or not Shop.ad_ready("rescue"):
		return false
	_pause()
	var p := InfoPopup.open(self, "Ошибка в сложном заказе", "Очистить поднос за короткий ролик? Гость подождёт, а ты попробуешь снова.", ["Исправить (ролик)", "Не надо"] as Array[String], ["video", ""] as Array[String])
	p.chosen.connect(func(i: int) -> void:
		if i != 0:
			_resume()
			_serve(e, true)
			return
		Shop.show_ad("rescue", func(ok: bool) -> void:
			_resume()
			if ok:
				_rescue_used = true
				_toast(tr("Поднос очищен, гость ждёт"), Vector2(180, 430))
				_reject_in_tutorial(e)
			else:
				_serve(e, true)))
	return true


## Подсказка к загадке за ролик: показывает состав загаданного напитка (раз за смену).
func _riddle_hint() -> void:
	if _hint_used or _paused or _clue == null:
		return
	var key := String(_clue.get_meta("key", ""))
	if key == "" or not Shop.ad_ready("riddle_hint"):
		_toast(tr("Ролик сейчас недоступен"), Vector2(180, 430))
		return
	_pause()
	Shop.show_ad("riddle_hint", func(ok: bool) -> void:
		if not ok:
			_resume()
			return
		_hint_used = true
		_refresh_clue(true)
		var book := RecipeBook.new()
		book.title_text = "Подсказка"
		book.drink_ids = [key] as Array[String]
		book.cell_tex = _drink_tex
		book.base_tex = func(id: String) -> Texture2D: return _drink_tex({"coffee": "espresso", "tea": "tea", "cocoa": "cocoa"}[id])
		book.closed.connect(_resume)
		add_child(book))


## Куда ляжет ингредиент, брошенный в точке at: вся чашка (WHOLE), напиток (DRINK) или выпечка (PASTRY). Сироп, сливки и корица ложатся на выпечку,
## если она на подносе и бросок — в правой половине; всё остальное — в напиток. Тот же расчёт рисует белую рамку.
func _drop_half(kind: String, id: String, at: Vector2) -> ServingTray.Half:
	var topping := "syrup" if kind == "syrup" else id
	if kind in ["syrup", "extra"] and _cup.pastry != "" and CupState.PASTRY_TOPPINGS.has(topping):
		return ServingTray.Half.PASTRY if at.x > _tray.position.x + ServingTray.SEAM else ServingTray.Half.DRINK
	return ServingTray.Half.WHOLE


func _add_ingredient(kind: String, id: String, at: Vector2) -> void:
	var on_pastry := _drop_half(kind, id, at) == ServingTray.Half.PASTRY
	var err := ""
	if on_pastry:   # бросили в правую половину подноса, где выпечка: сироп, сливки и корица ложатся на неё
		err = _cup.add_to_pastry("syrup" if kind == "syrup" else id)
	else:
		err = _cup.add(kind, id)
	if err != "":
		_toast(err, _tray.position + Vector2(0, -90))
		Fx.shake(_tray, 8.0, 0.3, 5, Fx.PX_GRID)
		return
	var color := Color("ffffff")
	match id:
		"coffee": color = Color("5b3320")
		"tea": color = Color("f0b84a")
		"milk": color = Color("fffaf0")
		"cocoa": color = Color("6b3f2a")
		"syrup": color = Color("c0392b")
		"ice": color = Color("bfe6f7")
		"cinnamon": color = Color("b0683a")
		"cream": color = Color("fffaf0")
	if kind == "pastry" or kind == "extra":
		Audio.sfx("pop")
		Fx.burst(_fx, at, "sparkle", Color("ffe9a0"), 7, 130.0, 100.0, 0.7, 1.0)
	else:
		Audio.sfx("pour")
		Fx.burst(_fx, _tray.position + Vector2(-40, -30), "drop", color, 10, 150.0, 520.0, 0.7, 1.0, 60.0)
	Fx.ring(_fx, _tray.position + Vector2(0, -6), Color(color, 0.9).lightened(0.2), 70.0, 0.5)
	if kind == "base" and "double" in _cup.mods:
		_toast(tr("Двойная порция!"), _tray.position + Vector2(0, -90))
	_refresh_cup()
	if kind == "pastry" or on_pastry:
		_tray.pop_pastry()
	else:
		_tray.pop_drink()


# ---------------------------------------------------------------- подача заказа

## Подача подноса коту e (пусто — первому ждущему). Начисление наград — сразу (тесты и логика), анимация — поверх.
func _serve(e: Dictionary = {}, skip_rescue := false) -> void:
	if e.is_empty():
		e = _front()
	if e.is_empty() or e["state"] != "wait":
		return
	var order: Dictionary = e["order"]
	var ok := _cup.matches(order)
	if not ok and not skip_rescue and _rescue_offer(e):
		return
	if tutorial and not ok:
		_reject_in_tutorial(e)
		return
	if not ok and _forgive_left > 0:   # «Помощь кота»: одна ошибка за смену прощается — кот не уходит
		_forgive_left -= 1
		_toast(tr("Помощь кота: ошибка прощена"), Vector2(180, 430))
		_reject_in_tutorial(e)
		return
	e["state"] = "done"
	var total := 0
	var tip := 0
	var bonus := 0
	var elapsed := (Time.get_ticks_msec() - int(e["t0"])) / 1000.0
	if ok:
		var drink_id: String = order["drink"]
		var pastry_id: String = order["pastry"]
		var price := int(round(float(Data.drinks[drink_id]["price"]) * GameState.price_mult(drink_id)))
		var combo := false
		if pastry_id != "":
			price += int(Data.pastries[pastry_id]["price"])
			var topped := (order.get("pastry_mods", []) as Array).size()
			if topped > 0:
				price += 3 * topped   # начинка на выпечке
				combo = true
		var cold := _cup_cold()
		if String(e.get("type", "normal")) == "gourmet":
			price *= 2   # гурман платит вдвое
		elif String(e.get("type", "normal")) == "riddle":
			price = int(round(price * (RIDDLE_PRICE + GameState.perk_total("riddle"))))   # отгаданная загадка — двойная цена
		elif String(e.get("type", "normal")) == "critic":
			price = int(round(price * 1.5))
		if combo:
			price = int(round(price * 1.2))   # комбо-сет: напиток + выпечка с начинкой — +20% к чеку
		var price_mult := 1.0 + GameState.perk_total("price")
		price = int(round(price * price_mult))
		if cold:
			price = int(round(price * COLD_PRICE))
		tip = maxi(1, int(round(price * 0.2)))
		var tip_mult := 1.0 + GameState.perk_total("tips") + GameState.cozy_tip_bonus()
		tip = int(round(tip * tip_mult))
		var cozy_share := GameState.cozy_tip_bonus() / tip_mult   # доля чаевых, которую дал Уют (для итогов смены)
		if pastry_id != "":
			tip = int(round(tip * (1.0 + GameState.perk_total("pastry_tips"))))
		if String(e.get("type", "normal")) == "rushed" and elapsed <= float(e["max"]) * 0.5:
			tip *= 2   # спешащий щедро благодарит за быструю подачу
		if String(e.get("type", "normal")) == "courier":
			tip = int(round(tip * 1.5))   # курьер берёт на вынос и щедр на чаевые
		if "double_tips" in boosters:
			tip *= 2
		if cold:
			tip = 0
			_toast(tr("Остыло: цена −30%, без чаевых"), Vector2(180, 470))
		_cozy_coins += float(tip) * cozy_share
		var target := float(level.get("speed", 10.0))
		bonus = 0 if tutorial else (5 if elapsed <= target * 0.6 else (2 if elapsed <= target else 0))
		if bonus > 0:
			bonus += int(GameState.perk_total("fast"))   # талант быстрого кота
		if String(e.get("type", "normal")) == "critic" and elapsed <= float(e["max"]) * 0.5:
			bonus += 30   # критик в восторге от скорости
			_toast(tr("Критик в восторге! +30"), Vector2(180, 470))
		total = price + tip + bonus
		Daily.report("coins", total)
		Daily.report("tips", tip)
		if bonus >= 5:
			Daily.report("fast")
		GameState.register_served()
		Daily.report("serve")
		Events.report("drink:" + drink_id)
		if pastry_id != "":
			Daily.report("pastry")
		var entry := -1 if tutorial else GameState.add_like(String(e["def"]["id"]))
		if entry >= 0:
			_toast(tr("Новая запись: %s (+%d)") % [String(e["def"]["name"]), int(GameState.LIKE_REWARD[entry])], Vector2(180, 430))
		shift_served += 1
		shift_earned += total
		streak += 1
		_stats["served"] = int(_stats["served"]) + 1
		(_stats["times"] as Array).append(elapsed)
		_points += _order_points(elapsed, e)
		if tutorial:
			_tutorial_index += 1
			if _tutorial_index == 1:   # первый поданный заказ: главная метрика входа (цель ≤ 20 с от запуска)
				Platform.track("ftue_step", {"step": "first_order", "t": Platform.session_seconds()})
		GameState.add_coins(total)
	else:
		streak = 0
		_stats["wrong"] = int(_stats["wrong"]) + 1
		_points_lost += int(e.get("pot", GameState.POINTS_PER_GUEST))
	_cup.clear()
	_cup_age = 0.0
	_free_bubble(e)
	_update_front()
	_set_coach(false)
	_refresh_progress()
	_play_serve(e, ok, total, tip, bonus)


func _play_serve(e: Dictionary, ok: bool, total: int, tip: int, bonus: int) -> void:
	_tray.set_ready(false)
	var cat: CatCustomer = e["cat"]
	_glide(_tray, cat.position + Vector2(0, 40), 0.25, Tween.TRANS_BACK, Tween.EASE_IN).tween_callback(_on_tray_delivered.bind(e, ok, total, tip, bonus))


func _on_tray_delivered(e: Dictionary, ok: bool, total: int, tip: int, bonus: int) -> void:
	_tray.set_contents(null, null)
	_tray.visible = false
	var cat: CatCustomer = e["cat"]
	if not is_instance_valid(cat):
		_queue.erase(e)
		_reset_tray()
		return
	var c := cat.center()
	if ok:
		cat.react_happy()
		Audio.sfx("success", 0.0)
		Audio.sfx("meow1" if randf() < 0.5 else "meow2", 0.08, -4.0)
		Fx.burst(_fx, c + Vector2(0, -36), "heart", Color("ff6b8b"), 8, 160.0, 90.0, 1.1, 1.0, 55.0)
		Fx.burst(_fx, c + Vector2(0, -30), "star", Color("ffe08a"), 6, 190.0, 160.0, 0.9, 1.0)
		Fx.ring(_fx, c, Color("ffd27a"), 90.0, 0.55)
		var coins := clampi(total / 3, 3, 9)
		Fx.coins_fly(_fx, c + Vector2(0, -20), COIN_POS, coins, _on_coin_landed)
		_toast("+%d  (чаевые %d, скорость %d)" % [total, tip, bonus], Vector2(180, 392))
		if bonus >= 5:
			Fx.confetti(_fx, c + Vector2(0, -50), 30)
			Fx.banner(_fx, "Быстро!", Vector2(180, 110), Color("ffd640"))
		elif streak >= 2:
			Fx.banner(_fx, "Серия x%d!" % streak, Vector2(180, 110), Color("8dff7a"))
			if streak >= 3:
				Fx.confetti(_fx, c + Vector2(0, -50), 22)
	else:
		cat.react_no()
		Audio.sfx("fail", 0.0)
		Fx.burst(_fx, c + Vector2(30, -50), "anger", Color("ff5a4a"), 2, 60.0, 0.0, 0.8, 1.0)
		_shake_screen(7.0)
		_toast("Не то... кот ушёл", Vector2(180, 392))
	get_tree().create_timer(0.45).timeout.connect(_finish_serve.bind(e, ok))


func _finish_serve(e: Dictionary, ok: bool) -> void:
	var cat: CatCustomer = e["cat"]
	if is_instance_valid(cat):
		if ok:
			cat.leave(true)
		else:
			cat.leave_angry()
	_queue.erase(e)
	_reset_tray()
	_refresh_progress()


func _reset_tray() -> void:
	_tray.position = TRAY_HOME
	_tray.visible = true
	Fx.rise_in(_tray, 24.0, 0.3)
	_refresh_cup()


## Обучение: кот не уходит, а мягко просит нужное.
func _reject_in_tutorial(e: Dictionary) -> void:
	var drink: Dictionary = Data.drinks[e["order"]["drink"]]
	var cat: CatCustomer = e["cat"]
	_cup.clear()
	_cup_age = 0.0
	_tray.set_contents(null, null)
	_tray.set_ready(false)
	Fx.shake(_tray, 8.0, 0.4, 6, Fx.PX_GRID)
	if is_instance_valid(cat):
		cat.react_no()
		Fx.burst(_fx, cat.center() + Vector2(30, -50), "sweat", Color("8fd6ff"), 3, 80.0, 200.0, 0.8, 1.0, 40.0, Vector2(1, -0.4))
		_toast("%s просит: %s" % [String(cat.def.get("name", "Кот")), String(drink["name"]).to_lower()], Vector2(180, 392))
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if is_instance_valid(_tray):
			_glide(_tray, TRAY_HOME, 0.25))
	_refresh_cup()


func _on_coin_landed() -> void:
	Audio.sfx("coin", 0.1, -8.0)
	Fx.hop(_coin_icon, 6.0, 0.25, 2.0)
	Fx.burst(_fx, COIN_POS, "sparkle", Color("fff3b0"), 3, 60.0, 0.0, 0.35, 0.7)


func _shake_screen(amp: float) -> void:
	var base := position
	var t := create_tween()
	for i in 6:
		t.tween_property(self, "position", base + _snap(Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) * (1.0 - i / 6.0)), 0.04)
	t.tween_property(self, "position", base, 0.04)


## Смена окончена: звёзды за итог (смена пройдена, точность, скорость), монеты за новые звёзды, экран итога.
func _finish_run() -> void:
	_run_over = true
	var customers := _total_customers()
	var served := int(_stats["served"])
	var times: Array = _stats["times"]
	var avg := 0.0
	for t in times:
		avg += float(t)
	avg = avg / float(times.size()) if not times.is_empty() else 0.0
	var accuracy := float(served) / float(maxi(1, customers))   # ошибки и ушедшие коты — потерянные заказы (для аналитики)
	var cap := _points_cap if _points_cap > 0 else customers * GameState.POINTS_PER_GUEST
	var stars := GameState.stars_for_score(_points, cap)
	var mask := (1 << stars) - 1   # k звёзд = первые k битов
	var new_stars := GameState.record_level(String(level.get("id", "l1")), mask)
	Platform.track("level_end", {"id": String(level.get("id", "l1")), "mask": mask, "points": _points, "cap": cap, "acc": snappedf(accuracy, 0.01), "avg": snappedf(avg, 0.1), "served": served, "lost": int(_stats["left"]), "wrong": int(_stats["wrong"]), "len": int((Time.get_ticks_msec() - _run_started_msec) / 1000)})
	if mask & 1 != 0:
		Daily.report("level")
		if int(_stats["left"]) == 0 and int(_stats["wrong"]) == 0:
			Daily.report("perfect")
	Daily.report("stars", new_stars)
	Shop.add_season_xp(new_stars * 10, "stars")
	var bonus := new_stars * 10
	if bonus > 0:
		GameState.add_coins(bonus)
		shift_earned += bonus
	_show_results(mask, bonus, cap)


func _show_results(mask: int, bonus: int, cap: int) -> void:
	_result = Node2D.new()
	_result.z_index = 150
	add_child(_result)
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.55)
	_result.add_child(dim)
	var x := 12.0
	var w := 336.0
	var cx := x + Ui.PAGE_PAD_X
	var cw := w - 2.0 * Ui.PAGE_PAD_X
	var has_cozy := GameState.cozy_score() > 0
	var h := 506.0 + (28.0 if has_cozy else 0.0)
	var top := floorf((640.0 - h) / 2.0 / 2.0) * 2.0
	Ui.panel(Rect2(x, top, w, h), Ui.UI_WOOD, _result)
	var stars := (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1)
	var y := top + Ui.PAGE_PAD_TOP
	Ui.label("Смена пройдена!" if stars > 0 else "Смена не удалась", Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK, _result, HORIZONTAL_ALIGNMENT_CENTER)
	y += Ui.LINE_H
	Ui.label(String(level.get("name", "")), Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK.lightened(0.25), _result, HORIZONTAL_ALIGNMENT_CENTER)
	y += Ui.LINE_H + 8.0
	# очки: крупное число, «из N», шкала с тремя звёздами на порогах; серая часть шкалы — очки, которые уже не набрать (ушёл гость, не то налили)
	var score := Ui.label("0", Rect2(cx, y, cw, 56.0), Ui.FONT_SIZE_BIG, Ui.INK, _result, HORIZONTAL_ALIGNMENT_CENTER)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: score.text = str(int(round(v))), 0.0, float(_points), 0.8)
	y += 56.0
	Ui.label(tr("из %d") % cap, Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK.lightened(0.3), _result, HORIZONTAL_ALIGNMENT_CENTER, true)
	y += Ui.LINE_H + 22.0
	var bar := Rect2(cx, y, cw, 24.0)
	var back := ColorRect.new()
	back.position = bar.position - Vector2(4, 4)
	back.size = bar.size + Vector2(8, 8)
	back.color = Ui.INK
	_result.add_child(back)
	var inner := ColorRect.new()
	inner.position = bar.position
	inner.size = bar.size
	inner.color = Color("6b5640")
	_result.add_child(inner)
	var ceiling := clampf(float(cap - _points_lost) / float(maxi(1, cap)), 0.0, 1.0)
	if ceiling < 1.0:   # потерянное: тёмная штриховая часть справа от потолка
		var lost := ColorRect.new()
		lost.position = Vector2(bar.position.x + snappedf(bar.size.x * ceiling, 4.0), bar.position.y)
		lost.size = Vector2(bar.end.x - lost.position.x, bar.size.y)
		lost.color = Color("3a2a22")
		_result.add_child(lost)
	var fill := ColorRect.new()
	fill.position = bar.position
	fill.size = Vector2(0, bar.size.y)
	fill.color = Color("ffd640")
	_result.add_child(fill)
	var fw := snappedf(bar.size.x * clampf(float(_points) / float(maxi(1, cap)), 0.0, 1.0), 4.0)
	fill.create_tween().tween_property(fill, "size:x", fw, 0.8)
	for i in 3:
		var fx_: float = float(GameState.STAR_FRACTIONS[i])
		var px := bar.position.x + snappedf(bar.size.x * fx_, 2.0)
		var tick := ColorRect.new()
		tick.position = Vector2(px - 2.0, bar.position.y - 4.0)
		tick.size = Vector2(4, bar.size.y + 8.0)
		tick.color = Ui.INK
		_result.add_child(tick)
		var lit := (mask >> i) & 1 == 1
		var star := _sprite(Ui.icon("star" if lit else "star_off"), Vector2(px, bar.position.y + bar.size.y / 2.0), 2.0, _result)
		star.z_index = 1
		if lit:
			star.visible = false
			var st := star.create_tween()
			st.tween_interval(0.7 + i * 0.3)
			st.tween_callback(func() -> void:
				Audio.sfx("star", 0.0)
				star.visible = true
				Fx.hop(star, 12.0, 0.3)
				Fx.burst(_result, star.position, "sparkle", Color("fff3b0"), 6, 120.0, 60.0, 0.6, 1.0))
	y += bar.size.y + 16.0
	if _points_lost > 0:
		Ui.label(tr("Упущено: %d") % _points_lost, Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK.lightened(0.3), _result, HORIZONTAL_ALIGNMENT_CENTER, true)
	y += Ui.LINE_H
	Ui.label(tr("Заработано: %d") % shift_earned + ("  (+%d)" % bonus if bonus > 0 else ""), Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Color("3c8c4a"), _result, HORIZONTAL_ALIGNMENT_CENTER, true)
	if has_cozy:   # замыкаем петлю «купил мебель → увидел прирост»: сколько чаевых принёс Уют
		y += Ui.LINE_H
		var heart := _sprite(Ui.icon("heart"), Vector2(cx + 16.0, y + Ui.LINE_H / 2.0), 2.0, _result)
		heart.z_index = 1
		Ui.label(tr("Бонус за Уют %d: +%d") % [GameState.cozy_score(), int(round(_cozy_coins))], Rect2(cx + 36.0, y, cw - 36.0, Ui.LINE_H), Ui.FONT_SIZE, Color("b0455a"), _result, HORIZONTAL_ALIGNMENT_LEFT, true)
	var by := top + h - Ui.PAGE_PAD_BOTTOM - Ui.BTN_H
	Ui.button("Ещё раз", Rect2(cx, by - Ui.BTN_H - Ui.BTN_GAP, cw, Ui.BTN_H), "play", _result).pressed.connect(_restart_run)
	Ui.button("В кафе", Rect2(cx, by, cw, Ui.BTN_H), "exit", _result).pressed.connect(_leave_results)
	# реклама за награду: после смены — монеты ×2; после проваленной — бустер «Помощь кота»
	var extra_y := by - 2.0 * (Ui.BTN_H + Ui.BTN_GAP)
	if stars > 0 and shift_earned > 0 and Shop.ad_ready("shift_double"):
		var b := Ui.button(tr("Заработок ×2 (реклама)"), Rect2(cx, extra_y, cw, Ui.BTN_H), "coin", _result)
		b.pressed.connect(_double_earnings.bind(b))
	elif stars == 0 and Shop.ad_ready("help"):
		var b2 := Ui.button(tr("Помощь кота (реклама)"), Rect2(cx, extra_y, cw, Ui.BTN_H), "cat", _result)
		b2.pressed.connect(_help_by_ad.bind(b2))


func _double_earnings(btn: Button) -> void:
	btn.disabled = true
	Shop.show_ad("shift_double", func(ok: bool) -> void:
		if ok:
			Economy.earn_coins(shift_earned, "shift_double")
			_toast(tr("Монеты удвоены: +%d") % shift_earned, Vector2(180, 40))
			btn.queue_free()
		else:
			btn.disabled = false)


func _help_by_ad(btn: Button) -> void:
	btn.disabled = true
	Shop.show_ad("help", func(ok: bool) -> void:
		if ok:
			Economy.add_booster("cat_help", 1, "ad")
			_toast(tr("Помощь кота получена!"), Vector2(180, 40))
			btn.queue_free()
		else:
			btn.disabled = false)


## «В кафе»: между сменами иногда показывается принудительная реклама (не раньше 10-й смены; правила — Shop.maybe_interstitial).
func _leave_results() -> void:
	Shop.maybe_interstitial(_end_shift)


func _restart_run() -> void:
	boosters.clear()   # бустеры были на одну смену
	if _result != null:
		_result.queue_free()
		_result = null
	_begin_run()


## Выход со смены: во встроенном режиме сообщаем городу (он закроет оверлей), отдельной сценой — возвращаемся в город.
func _end_shift() -> void:
	if embedded:
		closed.emit(shift_served, shift_earned)
	else:
		Nav.go(self, Nav.CITY)


# ---------------------------------------------------------------- отображение

func _refresh_cup() -> void:
	var did := _cup.look_id()
	_tray.set_contents(_drink_tex(did) if did != "" else null, _pastry_tex(_cup.pastry) if _cup.pastry != "" else null)
	_tray.set_mods(_cup.mods if did != "" else [], _cup.pastry_mods)
	if _cup.is_empty():
		_cup_age = 0.0
	_update_warmth()
	_cup_hint.visible = _cup.is_empty() and not tutorial
	var ready := false
	for q in _queue:   # поднос готов, если его заказ совпал с заказом хоть одного ждущего кота
		if q["state"] == "wait" and not _cup.is_empty() and _cup.matches(q["order"]):
			ready = true
	if ready and not _tray.has_meta("was_ready"):
		Fx.burst(_fx, _tray.position + Vector2(0, -50), "star", Color("ffe08a"), 8, 150.0, 120.0, 0.8, 1.0)
	if ready:
		_tray.set_meta("was_ready", true)
	elif _tray.has_meta("was_ready"):
		_tray.remove_meta("was_ready")
	_tray.set_ready(ready)
	_update_coach()


func _on_coins_changed(value: int) -> void:
	var from := _shown_coins
	var step := func(v: float) -> void:
		_shown_coins = v
		_coins_label.text = str(int(round(v)))
	create_tween().tween_method(step, from, float(value), 0.7).set_trans(Tween.TRANS_SINE)
	_served_label.text = tr("Подано: %d") % GameState.served_total


func _toast(text: String, pos: Vector2) -> void:
	Ui.toast(self, text, pos)


# ---------------------------------------------------------------- подсказки обучения

## За сколько секунд остывает горячий напиток на подносе (0 — не остывает: обучение, ранние смены).
func _cool_limit() -> float:
	if tutorial:
		return 0.0
	return float(level.get("cool", 0.0)) * (1.0 + GameState.perk_total("warm"))


func _cup_cold() -> bool:
	var lim := _cool_limit()
	return lim > 0.0 and _cup.is_hot() and _cup_age > lim


## Пар идёт, пока напиток горячий; на 70% срока пар пропадает («остывает»), потом чашка синеет.
func _update_warmth() -> void:
	var lim := _cool_limit()
	var w := 0
	if lim > 0.0 and _cup.is_hot() and not _cup.is_empty():
		w = 2 if _cup_age > lim else (1 if _cup_age > lim * 0.7 else 0)
	if w != _tray.warmth:
		_tray.warmth = w
		if w == 2:
			_toast(tr("Напиток остыл — заварить заново?"), Vector2(180, 430))


## Шпаргалка: открытые напитки с составом. Пока она открыта, смена стоит; при закрытии время ожидания каждого кота сдвигается на длину паузы.
func _open_book() -> void:
	if _paused or _run_over or _result != null or tutorial:
		return
	_pause()
	var book := RecipeBook.new()
	var ids: Array[String] = []
	for id in GameState.drink_ids():
		if _drink_makeable(id):
			ids.append(id)
	book.drink_ids = ids
	book.cell_tex = _drink_tex
	book.base_tex = func(id: String) -> Texture2D: return _drink_tex({"coffee": "espresso", "tea": "tea", "cocoa": "cocoa"}[id])
	book.closed.connect(_resume)
	add_child(book)
	Platform.track("recipe_book", {"drinks": ids.size()})


func _pause() -> void:
	_paused = true
	_pause_started = Time.get_ticks_msec()


func _resume() -> void:
	if not _paused:
		return
	var gap := Time.get_ticks_msec() - _pause_started
	for q in _queue:
		q["t0"] = int(q["t0"]) + gap
	_run_started_msec += gap
	_idle_msec += gap
	_paused = false


func _process(delta: float) -> void:
	if _paused:
		return
	if not _run_over and _result == null:
		if not _cup.is_empty() and _cup.is_hot() and _cool_limit() > 0.0:
			_cup_age += delta
			_update_warmth()
		_tick_queue(delta)
	if tutorial and _awaiting and Time.get_ticks_msec() - _idle_msec > 8000 and _drag.is_empty():
		_update_coach()


## Что игроку делать дальше: нужный источник → «неси поднос».
func _next_step() -> Dictionary:
	if _cup.matches(_order):
		return {"text": "Готово! Неси поднос коту", "target": Vector2(180, 250), "ready": true}
	var drink: Dictionary = Data.drinks[_order["drink"]]
	var recipe: Dictionary = drink["recipe"]
	if _cup.base == "":
		var id := String(recipe["base"])
		return {"text": "Перетащи %s на поднос" % {"coffee": "кофе", "tea": "чай", "cocoa": "какао"}.get(id, id), "source": id}
	if bool(recipe["milk"]) and not _cup.milk:
		return {"text": "Добавь молока", "source": "milk"}
	if bool(recipe.get("syrup", false)) and not _cup.syrup:
		return {"text": "Добавь сироп", "source": "syrup"}
	for m in recipe.get("mods", []):
		if String(m) == "double":
			if not ("double" in _cup.mods):
				return {"text": "Ещё порцию кофе", "source": "coffee"}
		elif not (String(m) in _cup.mods):
			return {"text": "Добавь добавку", "source": String(m)}
	if String(_order["pastry"]) != "" and _cup.pastry != String(_order["pastry"]):
		return {"text": "Добавь выпечку", "source": String(_order["pastry"])}
	return {"text": "Не то налили? Тащи поднос в корзину", "target": BIN_POS, "ready": false}


func _update_coach() -> void:
	if not tutorial or not _awaiting:
		_set_coach(false)
		return
	var step := _next_step()
	_coach_label.text = String(step["text"])
	_coach_label.visible = true
	var target := Vector2.ZERO
	if step.has("source"):
		for s in _sources:
			if String(s["id"]) == String(step["source"]):
				target = (s["center"] as Vector2) + Vector2(0, 40)
	elif step.has("target"):
		target = step["target"]
	_coach_hand.visible = target != Vector2.ZERO
	_coach_base = target
	_coach_hand.position = target
	if _coach_glow != null:
		_coach_glow.queue_free()
		_coach_glow = null
	if step.has("source") and target != Vector2.ZERO:
		_coach_glow = Fx.glow(self, target + Vector2(0, -40), Vector2(170, 150), Color("fff0a0"))
	if not _coach_hand.has_meta("bob"):
		var bob := _coach_hand.create_tween().set_loops()   # рука «тычет» вниз на пиксель сетки
		bob.tween_callback(func() -> void: _coach_hand.position = _coach_base + Vector2(0, 4))
		bob.tween_interval(0.4)
		bob.tween_callback(func() -> void: _coach_hand.position = _coach_base)
		bob.tween_interval(0.4)
		_coach_hand.set_meta("bob", true)


func _set_coach(on: bool) -> void:
	_coach_label.visible = on
	_coach_hand.visible = on
	if not on and _coach_glow != null:
		_coach_glow.queue_free()
		_coach_glow = null


# ---------------------------------------------------------------- помощники

func _cell(col: int, row: int) -> AtlasTexture:
	return _atlas(COFFEE_SHEET, Rect2(col * 16, row * 16, 16, 16))


func _drink_tex(id: String) -> AtlasTexture:
	var d: Dictionary = Data.drinks[id]
	return _cell(int(d["col"]), int(d["row"]))


func _pastry_tex(id: String) -> AtlasTexture:
	var d: Dictionary = Data.pastries[id]
	return _cell(int(d["col"]), int(d["row"]))


func _atlas(tex: Texture2D, region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = region
	return a


## Привязка к сетке крупного плана (4 px): всё, что движется под пальцем, стоит только на целых пикселях.
func _snap(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, Fx.PX_GRID), snappedf(p.y, Fx.PX_GRID))


## Плавно ведёт узел к точке, но кадры стоят на сетке (без дробных пикселей). Возвращает Tween — к нему можно добавить шаг.
func _glide(n: Node2D, to: Vector2, time: float, trans := Tween.TRANS_BACK, ease := Tween.EASE_OUT) -> Tween:
	var from := n.position
	var t := n.create_tween()
	t.tween_method(func(u: float) -> void: n.position = _snap(from.lerp(to, u)), 0.0, 1.0, time).set_trans(trans).set_ease(ease)
	return t


func _sprite(tex: Texture2D, pos: Vector2, s: float, parent: Node = null) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.position = pos
	sp.scale = Vector2(s, s)
	(parent if parent else self).add_child(sp)
	return sp


## Подпись; narrow — узкий шрифт для длинных строк. Размер всегда кратен сетке шрифта (см. Ui).
func _label(text: String, r: Rect2, color: Color, parent: Node = null, narrow := false) -> Label:
	return Ui.label(tr(text), r, Ui.FONT_SIZE, color, parent if parent else self, HORIZONTAL_ALIGNMENT_CENTER, narrow)
