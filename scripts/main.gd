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
const COIN_POS := Vector2(28, 26)   # центр области плашки (6..54) над нижней тенью
const INK := Ui.INK

const COFFEE_SHEET: Texture2D = preload("res://assets/cafe/drinks-and-pastries.png")  # сетка 16x16, 5 колонок
const ICONS: Texture2D = preload("res://assets/ui/icons-essential.png")
const FURN: Texture2D = preload("res://assets/cafe/neko-cafe-furnitures.png")

var embedded := false   # true — смена идёт поверх города, а не отдельной сценой
var shift_served := 0
var shift_earned := 0
var streak := 0         # подряд верных заказов
var level: Dictionary = {}   # данные уровня из data/levels.json; пусто — обучение или тест
var tutorial := false
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
	_tray.position = TRAY_HOME
	add_child(_tray)
	_cup_hint = _label("Собери заказ на подносе", Rect2(8, 344, 292, 32), Color("fff1d6"), null, true)
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
	var title := Ui.label("Тёплая Лапка", Rect2(76, 58, 208, 36), Ui.FONT_SIZE, Color("ffe6b0"), self, HORIZONTAL_ALIGNMENT_CENTER, true)
	title.add_theme_color_override("font_outline_color", Color("3f2815"))
	title.add_theme_constant_override("outline_size", Ui.PX * 2)
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
	var machine := _sprite(_atlas(FURN, Rect2(131, 67, 11, 13)), Vector2(46, 288), 4.0)
	machine.offset = Vector2(0, -6.5)
	Fx.steam(self, Vector2(46, 252), 5).emitting = true
	var plant := _sprite(_atlas(FURN, Rect2(97, 80, 14, 16)), Vector2(324, 284), 4.0)
	plant.offset = Vector2(0, -8)
	_bin = BrewArt.Bin.new()
	_bin.position = BIN_POS
	add_child(_bin)


func _build_table() -> void:
	_table = BrewArt.new()
	_table.part = BrewArt.Part.TABLE
	add_child(_table)
	var bases: Array[Dictionary] = [
		{"kind": "base", "id": "coffee", "title": "Кофе", "tex": _drink_tex("espresso")},
		{"kind": "base", "id": "tea", "title": "Чай", "tex": _drink_tex("tea")},
		{"kind": "milk", "id": "milk", "title": "Молоко", "tex": _cell(0, 4)},
	]
	var pastries: Array[Dictionary] = []
	for id in Data.pastries:
		pastries.append({"kind": "pastry", "id": id, "title": String(Data.pastries[id]["name"]), "tex": _pastry_tex(id)})
	_lay_row(bases, 448.0)
	_lay_row(pastries, 564.0)
	_table.plates = []
	for s in _sources:
		_table.plates.append(s["center"])
	_table.queue_redraw()
	for s in _sources:
		var rest := (s["center"] as Vector2) - BrewArt.content_offset(s["tex"], String(s["kind"]) != "pastry") * 4.0   # рисунок по центру тарелки
		s["rest"] = rest
		var icon := _sprite(s["tex"], rest, 4.0)
		s["icon"] = icon
		var cap := _label(s["title"], Rect2((s["center"] as Vector2).x - 54, (s["center"] as Vector2).y + 44, 108, 28), Color("fff1d6"), null, true)
		cap.add_theme_color_override("font_outline_color", Color("3f2815"))
		cap.add_theme_constant_override("outline_size", Ui.PX * 2)
		var rest_y := icon.position.y
		var bob := icon.create_tween().set_loops()   # предметы на столе «дышат» — приподнимаются на целый пиксель сетки, без масштаба
		bob.tween_interval(0.8 + randf() * 0.3)
		bob.tween_callback(func() -> void: icon.position.y = rest_y - Fx.PX_GRID)
		bob.tween_interval(0.8)
		bob.tween_callback(func() -> void: icon.position.y = rest_y)


## Какие источники на столе: в обучении — заданные, иначе по купленным улучшениям (молочник, витрина).
func _source_available(it: Dictionary) -> bool:
	if tutorial:
		return tutorial_sources.is_empty() or String(it["id"]) in tutorial_sources
	match String(it["kind"]):
		"milk":
			return GameState.has_upgrade("milk_pitcher")
		"pastry":
			return GameState.pastries_unlocked()
	return true


## Раскладывает источники ряда по тарелкам; скрытые в обучении пропускаются, остальные центрируются.
func _lay_row(items: Array[Dictionary], y: float) -> void:
	var shown: Array[Dictionary] = []
	for it in items:
		if _source_available(it):
			shown.append(it)
	var xs: Array = []
	match shown.size():
		1: xs = [180.0]
		2: xs = [108.0, 252.0]
		_: xs = [68.0, 180.0, 292.0]
	for i in shown.size():
		var s: Dictionary = shown[i]
		var c := Vector2(float(xs[i]), y)
		s["center"] = c
		s["rect"] = Rect2(c - Vector2(50, 50), Vector2(100, 118))
		_sources.append(s)


func _build_hud() -> void:
	Ui.panel(Rect2(8, 6, 108, 48), Ui.UI_CREAM, self).z_index = 80
	_coin_icon = _sprite(_atlas(ICONS, Rect2(210, 209, 11, 14)), COIN_POS, 2.0)
	_coin_icon.z_index = 81
	_coins_label = _label("0", Rect2(44, 12, 68, 32), INK)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_coins_label.z_index = 81
	_served_label = _label("", Rect2(124, 10, 166, 32), Color("fff1d6"), null, true)
	_served_label.add_theme_color_override("font_outline_color", INK)
	_served_label.add_theme_constant_override("outline_size", Ui.PX * 2)
	_served_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_served_label.z_index = 81
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
	var f := _front()
	_awaiting = not f.is_empty()
	_cat = f["cat"] if _awaiting else null
	_order = f["order"] if _awaiting else {}


func _spawn_customer() -> void:
	var slot := _free_slot()
	if slot < 0:
		return
	var def: Dictionary = Data.cats.pick_random()
	var drink_id := ""
	var pastry_id := ""
	if tutorial:
		var o: Dictionary = tutorial_orders[_tutorial_index]
		drink_id = String(o["drink"])
		pastry_id = String(o.get("pastry", ""))
		for c in Data.cats:
			if String(c["id"]) == String(o.get("cat", "")):
				def = c
	else:
		var avail := GameState.drink_ids()
		var pool: Array = level.get("pool", [])
		if not pool.is_empty():
			avail = avail.filter(func(id: String) -> bool: return id in pool)
		drink_id = (avail if not avail.is_empty() else GameState.drink_ids()).pick_random()
		if GameState.pastries_unlocked() and randf() < float(level.get("pastry", 0.0)):
			pastry_id = Data.pastries.keys().pick_random()
		var busy := _queue.map(func(e: Dictionary) -> String: return String(e["def"]["id"]))   # одинаковых котов подряд не пускаем
		var others := Data.cats.filter(func(c: Dictionary) -> bool: return not (String(c["id"]) in busy))
		if not others.is_empty():
			def = others.pick_random()
	var patience := INF if tutorial else float(level.get("patience", 40.0)) * randf_range(0.85, 1.15)
	var cat := CatCustomer.new()
	_cat_layer.add_child(cat)
	cat.setup(def)
	cat.position = Vector2(CAT_SPAWN_X, CAT_POS.y)
	var e := {"cat": cat, "def": def, "order": {"drink": drink_id, "pastry": pastry_id}, "patience": patience, "max": patience, "slot": slot,
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
	Fx.burst(_fx, (e["cat"] as CatCustomer).center() + Vector2(0, -44), "sparkle", Color("fff3b0"), 5, 90.0, 40.0, 0.6, 0.8)
	_update_front()
	_refresh_cup()


func _on_cat_left(cat: CatCustomer) -> void:
	cat.queue_free()


## Чек над котом: иконки заказа и полоска терпения.
func _make_bubble(e: Dictionary) -> void:
	var b := Node2D.new()
	b.position = Vector2(SLOT_X[int(e["slot"])], BUBBLE_Y)
	b.z_index = 6
	add_child(b)
	Ui.panel(Rect2(-52, -36, 104, 72), Ui.UI_CREAM, b)
	for i in 3:   # хвостик чека к коту
		var w := 16.0 - i * 4.0
		var tail := ColorRect.new()
		tail.position = Vector2(-w / 2.0, 36 + i * 4)
		tail.size = Vector2(w, 4)
		tail.color = Color("fff0cd")
		tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tail)
	var order: Dictionary = e["order"]
	var drink_x := 0.0
	var icons: Array[Sprite2D] = []
	if String(order["pastry"]) != "":
		drink_x = -26.0
		var pt := _pastry_tex(order["pastry"])
		icons.append(_sprite(pt, Vector2(26, -12) - BrewArt.content_offset(pt) * 2.0, 2.0, b))
	var dt := _drink_tex(order["drink"])
	icons.append(_sprite(dt, Vector2(drink_x, -12) - BrewArt.content_offset(dt, true) * 2.0, 2.0, b))
	if not is_inf(float(e["max"])):   # полоска терпения
		var back := ColorRect.new()
		back.position = Vector2(-42, 18)
		back.size = Vector2(84, 10)
		back.color = Ui.INK
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(back)
		var fill := ColorRect.new()
		fill.position = Vector2(-40, 20)
		fill.size = Vector2(80, 6)
		fill.color = Color("8dff7a")
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(fill)
		e["bar"] = fill
	e["bubble"] = b
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
	_stats["left"] = int(_stats["left"]) + 1
	streak = 0
	_free_bubble(e)
	var cat: CatCustomer = e["cat"]
	Fx.burst(_fx, cat.center() + Vector2(0, -40), "anger", Color("ff5a4a"), 3, 60.0, 0.0, 0.7, 1.0)
	_toast("%s ушёл злой!" % String(e["def"].get("name", "Кот")), Vector2(180, 392))
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
	_served_label.text = tr("Коты: %d/%d") % [handled, _total_customers()]


# ---------------------------------------------------------------- перетаскивание

func _input(event: InputEvent) -> void:
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
		_drag = {"kind": "tray", "grab": _tray.position - p}
		_tray.z_index = 50
		_tray.create_tween().tween_property(_tray, "lift", 12.0, 0.12)   # поднимается — тень уезжает вниз
		return
	for s in _sources:
		if (s["rect"] as Rect2).has_point(p):
			var ghost := _sprite(s["tex"], p + Vector2(0, -24), 4.0)
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
	ghost.position = _snap(p + Vector2(0, -24))


func _end_drag() -> void:
	if _drag.is_empty():
		return
	var d := _drag
	_drag = {}
	if d["kind"] == "tray":
		_drop_tray()
		return
	var ghost: Sprite2D = d["ghost"]
	var drop := ghost.position
	if drop.distance_to(_tray.position + Vector2(0, -20)) < 100.0:
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
	_cup.clear()
	_tray.set_contents(null, null)
	_tray.set_ready(false)
	_glide(_tray, TRAY_HOME, 0.25)
	_refresh_cup()


func _add_ingredient(kind: String, id: String, at: Vector2) -> void:
	var err := _cup.add(kind, id)
	if err != "":
		_toast(err, _tray.position + Vector2(0, -90))
		Fx.shake(_tray, 8.0, 0.3, 5, Fx.PX_GRID)
		return
	var color := Color("ffffff")
	match id:
		"coffee": color = Color("5b3320")
		"tea": color = Color("f0b84a")
		"milk": color = Color("fffaf0")
	if kind == "pastry":
		Fx.burst(_fx, at, "sparkle", Color("ffe9a0"), 7, 130.0, 100.0, 0.7, 1.0)
	else:
		Fx.burst(_fx, _tray.position + Vector2(-40, -30), "drop", color, 10, 150.0, 520.0, 0.7, 1.0, 60.0)
	Fx.ring(_fx, _tray.position + Vector2(0, -6), Color(color, 0.9).lightened(0.2), 70.0, 0.5)
	_refresh_cup()
	if kind == "pastry":
		_tray.pop_pastry()
	else:
		_tray.pop_drink()


# ---------------------------------------------------------------- подача заказа

## Подача подноса коту e (пусто — первому ждущему). Начисление наград — сразу (тесты и логика), анимация — поверх.
func _serve(e: Dictionary = {}) -> void:
	if e.is_empty():
		e = _front()
	if e.is_empty() or e["state"] != "wait":
		return
	var order: Dictionary = e["order"]
	var ok := _cup.matches(order)
	if tutorial and not ok:
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
		if pastry_id != "":
			price += int(Data.pastries[pastry_id]["price"])
		tip = maxi(1, int(round(price * 0.2)))
		var target := float(level.get("speed", 10.0))
		bonus = 0 if tutorial else (5 if elapsed <= target * 0.6 else (2 if elapsed <= target else 0))
		total = price + tip + bonus
		GameState.register_served()
		shift_served += 1
		shift_earned += total
		streak += 1
		_stats["served"] = int(_stats["served"]) + 1
		(_stats["times"] as Array).append(elapsed)
		if tutorial:
			_tutorial_index += 1
		GameState.add_coins(total)
	else:
		streak = 0
		_stats["wrong"] = int(_stats["wrong"]) + 1
	_cup.clear()
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
	var accuracy := float(served) / float(maxi(1, customers))   # ошибки и ушедшие коты — потерянные заказы
	var mask := 0
	if served * 2 >= customers:
		mask |= 1
		if accuracy >= float(level.get("accuracy", 0.8)):
			mask |= 2
		if avg > 0.0 and avg <= float(level.get("speed", 10.0)) and served * 10 >= customers * 6:
			mask |= 4
	var new_stars := GameState.record_level(String(level.get("id", "l1")), mask)
	var bonus := new_stars * 10
	if bonus > 0:
		GameState.add_coins(bonus)
		shift_earned += bonus
	_show_results(mask, bonus, accuracy, avg)


func _show_results(mask: int, bonus: int, accuracy: float, avg: float) -> void:
	_result = Node2D.new()
	_result.z_index = 150
	add_child(_result)
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.55)
	_result.add_child(dim)
	# рамка 336 px: орнаменты 20 px по углам, бортик 22 px снизу; содержимое — в колонке 268 px по центру
	var x := 12.0
	var w := 336.0
	var cx := x + Ui.PAGE_PAD_X
	var cw := w - 2.0 * Ui.PAGE_PAD_X
	var top := 96.0
	var h := 466.0
	Ui.panel(Rect2(x, top, w, h), Ui.UI_WOOD, _result)
	var done := mask & 1 != 0
	var y := top + Ui.PAGE_PAD_TOP
	Ui.label("Смена пройдена!" if done else "Смена не удалась", Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK, _result, HORIZONTAL_ALIGNMENT_CENTER)
	y += Ui.LINE_H
	Ui.label(String(level.get("name", "")), Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK.lightened(0.25), _result, HORIZONTAL_ALIGNMENT_CENTER)
	y += Ui.LINE_H + 12.0
	var captions := ["Смена", "Точность", "Скорость"]
	var values := ["", "%d%%" % int(round(accuracy * 100.0)), "%.1f с" % avg]
	var star_y := y + 18.0
	for i in 3:
		var sx := cx + cw / 6.0 + i * cw / 3.0   # центры трёх колонок
		var star := _sprite(Fx.tex("bigstar"), Vector2(sx, star_y), 4.0, _result)
		star.modulate = Color("5a4636") if (mask >> i) & 1 == 0 else Color("ffd640")
		Ui.label(captions[i], Rect2(sx - cw / 6.0, y + 44.0, cw / 3.0, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK, _result, HORIZONTAL_ALIGNMENT_CENTER, true)
		Ui.label(values[i], Rect2(sx - cw / 6.0, y + 44.0 + Ui.LINE_H, cw / 3.0, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK.lightened(0.3), _result, HORIZONTAL_ALIGNMENT_CENTER, true)
		if (mask >> i) & 1 == 1:
			star.visible = false
			var tw := star.create_tween()
			tw.tween_interval(0.25 + i * 0.3)
			tw.tween_callback(func() -> void:
				star.visible = true
				Fx.hop(star, 12.0, 0.3)
				Fx.burst(_result, Vector2(sx, star_y), "sparkle", Color("fff3b0"), 6, 120.0, 60.0, 0.6, 1.0))
	y += 44.0 + Ui.LINE_H * 2.0 + 8.0
	var need := "Цель: точность %d%%, до %d с" % [int(round(float(level.get("accuracy", 0.8)) * 100.0)), int(level.get("speed", 10.0))]
	Ui.label(need, Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK.lightened(0.3), _result, HORIZONTAL_ALIGNMENT_CENTER, true)
	y += Ui.LINE_H + 6.0
	var lines := "Подано: %d из %d\nОшибок: %d, ушло злыми: %d" % [int(_stats["served"]), _total_customers(), int(_stats["wrong"]), int(_stats["left"])]
	Ui.label(lines, Rect2(cx, y, cw, Ui.LINE_H * 2.0), Ui.FONT_SIZE, Ui.INK, _result, HORIZONTAL_ALIGNMENT_CENTER, true)
	y += Ui.LINE_H * 2.0 + 4.0
	Ui.label("Заработано: %d" % shift_earned + ("  (звёзды +%d)" % bonus if bonus > 0 else ""), Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Color("3c8c4a"), _result, HORIZONTAL_ALIGNMENT_CENTER, true)
	var by := top + h - Ui.PAGE_PAD_BOTTOM - Ui.BTN_H
	Ui.button("Ещё раз", Rect2(cx, by - Ui.BTN_H - Ui.BTN_GAP, cw, Ui.BTN_H), "play", _result).pressed.connect(_restart_run)
	Ui.button("В кафе", Rect2(cx, by, cw, Ui.BTN_H), "exit", _result).pressed.connect(_end_shift)


func _restart_run() -> void:
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
	var did := _cup.drink_id()
	_tray.set_contents(_drink_tex(did) if did != "" else null, _pastry_tex(_cup.pastry) if _cup.pastry != "" else null)
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

func _process(delta: float) -> void:
	if not _run_over and _result == null:
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
		return {"text": "Перетащи %s на поднос" % ("кофе" if id == "coffee" else "чай"), "source": id}
	if bool(recipe["milk"]) and not _cup.milk:
		return {"text": "Добавь молока", "source": "milk"}
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
				target = (s["center"] as Vector2) + Vector2(0, 44)
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
