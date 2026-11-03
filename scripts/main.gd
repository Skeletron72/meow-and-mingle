extends Node2D
## Смена за стойкой: кот-посетитель делает заказ, ты собираешь его на подносе перетаскиванием
## (основа → молоко → выпечка) и подаёшь поднос коту. Всё нарисовано кодом (BrewArt, ServingTray),
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
const NEXT_CAT_DELAY := 1.0
const PASTRY_CHANCE := 0.5
const BIN_POS := Vector2(320, 360)
const COIN_POS := Vector2(28, 26)
const INK := Ui.INK

const COFFEE_SHEET: Texture2D = preload("res://assets/cafe/drinks-and-pastries.png")  # сетка 16x16, 5 колонок
const ICONS: Texture2D = preload("res://assets/ui/icons-essential.png")
const FURN: Texture2D = preload("res://assets/cafe/neko-cafe-furnitures.png")

var embedded := false   # true — смена идёт поверх города, а не отдельной сценой
var shift_served := 0
var shift_earned := 0
var streak := 0         # подряд верных заказов
var tutorial := false
var tutorial_orders: Array[Dictionary] = []   # {"cat": id кота, "drink": id, "pastry": id|""} — по порядку
var tutorial_sources: Array[String] = []      # id источников, которые показаны (пусто — все)

var _cup := CupState.new()
var _sources: Array[Dictionary] = []   # {kind, id, rect, tex, icon, center}
var _drag: Dictionary = {}
var _cat: CatCustomer
var _order: Dictionary = {}            # {"drink": id, "pastry": id|""}
var _awaiting := false
var _arrive_msec := 0
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
var _bubble: Node2D
var _coin_icon: Sprite2D
var _coins_label: Label
var _served_label: Label


func _ready() -> void:
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
	_spawn_cat()


# ---------------------------------------------------------------- построение сцены

func _build_wall() -> void:
	var wall := BrewArt.new()
	wall.part = BrewArt.Part.WALL
	add_child(wall)
	var title := Ui.label("Тёплая Лапка", Rect2(76, 58, 208, 36), Ui.FONT_SIZE, Color("ffe6b0"), self, HORIZONTAL_ALIGNMENT_CENTER, true)
	title.add_theme_color_override("font_outline_color", Color("3f2815"))
	title.add_theme_constant_override("outline_size", Ui.PX * 2)
	# банки и чашки на боковых полках
	for i in 2:
		_sprite(_cell(i, 3), Vector2(30 + i * 28, 184), 2.0)
	_sprite(_cell(0, 0), Vector2(310, 184), 2.0)
	_sprite(_cell(3, 3), Vector2(338, 184), 2.0)
	for x in [44.0, 316.0]:
		var lamp := BrewArt.PendantLamp.new()
		lamp.position = Vector2(x, 48)
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
	var plant := _sprite(_atlas(FURN, Rect2(97, 80, 14, 16)), Vector2(322, 284), 4.0)
	plant.offset = Vector2(0, -8)
	plant.rotation = -0.03
	var sway := plant.create_tween().set_loops()
	sway.tween_property(plant, "rotation", 0.03, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(plant, "rotation", -0.03, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
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
	_lay_row(bases, 452.0)
	_lay_row(pastries, 566.0)
	_table.plates = []
	for s in _sources:
		_table.plates.append(s["center"])
	_table.queue_redraw()
	for s in _sources:
		var icon := _sprite(s["tex"], (s["center"] as Vector2) + Vector2(0, -4), 4.0)
		s["icon"] = icon
		var cap := _label(s["title"], Rect2((s["center"] as Vector2).x - 54, (s["center"] as Vector2).y + 40, 108, 28), Color("fff1d6"), null, true)
		cap.add_theme_color_override("font_outline_color", Color("3f2815"))
		cap.add_theme_constant_override("outline_size", Ui.PX * 2)
		var bob := icon.create_tween().set_loops()   # предметы на столе чуть «дышат»
		bob.tween_interval(randf() * 1.5)
		bob.tween_property(icon, "scale", Vector2(4.2, 3.9), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(icon, "scale", Vector2(4, 4), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
		2: xs = [110.0, 250.0]
		_: xs = [70.0, 180.0, 290.0]
	for i in shown.size():
		var s: Dictionary = shown[i]
		var c := Vector2(float(xs[i]), y)
		s["center"] = c
		s["rect"] = Rect2(c - Vector2(46, 46), Vector2(92, 108))
		_sources.append(s)


func _build_hud() -> void:
	Ui.panel(Rect2(8, 6, 108, 40), Ui.UI_CREAM, self).z_index = 80
	_coin_icon = _sprite(_atlas(ICONS, Rect2(210, 209, 11, 14)), COIN_POS, 2.0)
	_coin_icon.z_index = 81
	_coins_label = _label("0", Rect2(44, 8, 68, 36), INK)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_coins_label.z_index = 81
	_served_label = _label("", Rect2(124, 8, 166, 32), Color("fff1d6"), null, true)
	_served_label.add_theme_color_override("font_outline_color", INK)
	_served_label.add_theme_constant_override("outline_size", Ui.PX * 2)
	_served_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_served_label.z_index = 81
	var end_btn := Ui.button("", Rect2(300, 4, 52, 40), "exit", self)
	end_btn.z_index = 82
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


# ---------------------------------------------------------------- котики и заказы

func _spawn_cat() -> void:
	var def: Dictionary = Data.cats.pick_random()
	var drink_id: String = GameState.drink_ids().pick_random()
	var pastry_id := ""
	if tutorial:
		if _tutorial_index >= tutorial_orders.size():
			tutorial_finished.emit(shift_served, shift_earned)
			return
		var o: Dictionary = tutorial_orders[_tutorial_index]
		drink_id = String(o["drink"])
		pastry_id = String(o.get("pastry", ""))
		for c in Data.cats:
			if String(c["id"]) == String(o.get("cat", "")):
				def = c
	elif GameState.pastries_unlocked() and randf() < PASTRY_CHANCE:
		pastry_id = Data.pastries.keys().pick_random()
	_order = {"drink": drink_id, "pastry": pastry_id}
	_cat = CatCustomer.new()
	_cat_layer.add_child(_cat)
	_cat.setup(def)
	_cat.position = Vector2(CAT_SPAWN_X, CAT_POS.y)
	_cat.arrived.connect(_on_cat_arrived)
	_cat.left.connect(_on_cat_left.bind(_cat))
	_cat.enter(CAT_POS.x)


func _on_cat_arrived() -> void:
	_awaiting = true
	_arrive_msec = Time.get_ticks_msec()
	_idle_msec = _arrive_msec
	_show_bubble()
	Fx.burst(_fx, _cat.center() + Vector2(0, -44), "sparkle", Color("fff3b0"), 5, 90.0, 40.0, 0.6, 0.8)
	_refresh_cup()


func _on_cat_left(cat: CatCustomer) -> void:
	cat.queue_free()
	# не await: если игрок вышел в меню, таймер не должен будить уже удалённую сцену
	get_tree().create_timer(NEXT_CAT_DELAY).timeout.connect(_spawn_cat)


## Заказ-«чек»: бумажка с напитком и выпечкой, выпрыгивает над котом.
func _show_bubble() -> void:
	_hide_bubble()
	_bubble = Node2D.new()
	_bubble.position = Vector2(180, 146)
	_bubble.z_index = 6
	add_child(_bubble)
	Ui.panel(Rect2(-120, -50, 240, 100), Ui.UI_CREAM, _bubble)
	# хвостик чека к коту
	for i in 3:
		var w := 16.0 - i * 4.0
		var tail := ColorRect.new()
		tail.position = Vector2(-w / 2.0, 50 + i * 4)
		tail.size = Vector2(w, 4)
		tail.color = Color("fff0cd")
		tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bubble.add_child(tail)
	var drink: Dictionary = Data.drinks[_order["drink"]]
	var title: String = drink["name"]
	var pastry_id: String = _order["pastry"]
	var drink_x := 0.0
	var icons: Array[Sprite2D] = []
	if pastry_id != "":
		drink_x = -40.0
		title += " + " + String(Data.pastries[pastry_id]["name"]).to_lower()
		icons.append(_sprite(_pastry_tex(pastry_id), Vector2(44, -10), 4.0, _bubble))
	icons.append(_sprite(_drink_tex(_order["drink"]), Vector2(drink_x, -10), 4.0, _bubble))
	_label(title, Rect2(-120, 20, 240, 28), INK, _bubble, true)
	Fx.pop_in(_bubble, 0.5)
	for i in icons.size():   # значки подпрыгивают друг за другом
		Fx.pop(icons[i], 1.5, 0.55)


func _hide_bubble() -> void:
	if _bubble:
		var b := _bubble
		_bubble = null
		var t := b.create_tween().set_parallel(true)
		t.tween_property(b, "scale", Vector2(0.2, 0.2), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(b, "modulate:a", 0.0, 0.2)
		t.chain().tween_callback(b.queue_free)


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
		var t := _tray.create_tween().set_parallel(true)
		t.tween_property(_tray, "lift", 12.0, 0.12)
		t.tween_property(_tray, "scale", Vector2(1.08, 1.08), 0.12)
		return
	for s in _sources:
		if (s["rect"] as Rect2).has_point(p):
			var ghost := _sprite(s["tex"], p + Vector2(0, -24), 4.0)
			ghost.z_index = 100
			_drag = {"kind": s["kind"], "id": s["id"], "ghost": ghost, "src": s}
			Fx.pop(s["icon"], 1.35, 0.3)
			Fx.burst(_fx, (s["center"] as Vector2) + Vector2(0, 10), "dot", Color("ffffff"), 4, 50.0, 60.0, 0.35, 0.8)
			return


func _drag_to(p: Vector2) -> void:
	if _drag["kind"] == "tray":
		_tray.position = p + (_drag["grab"] as Vector2)
		_tray.rotation = lerpf(_tray.rotation, clampf(((_tray.position.x - 180.0) / 180.0) * 0.12, -0.12, 0.12), 0.5)
		return
	var ghost: Sprite2D = _drag["ghost"]
	var target := p + Vector2(0, -24)
	ghost.rotation = lerpf(ghost.rotation, clampf((target.x - ghost.position.x) * 0.03, -0.35, 0.35), 0.4)
	ghost.position = target


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
		var t := ghost.create_tween().set_parallel(true)
		t.tween_property(ghost, "position", (src["center"] as Vector2) + Vector2(0, -4), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(ghost, "rotation", 0.0, 0.2)
		t.chain().tween_callback(ghost.queue_free)
	_refresh_cup()


func _drop_tray() -> void:
	var t := _tray.create_tween().set_parallel(true)
	t.tween_property(_tray, "lift", 0.0, 0.12)
	t.tween_property(_tray, "rotation", 0.0, 0.12)
	t.tween_property(_tray, "scale", Vector2.ONE, 0.12)
	_tray.z_index = 0
	var drop := _tray.position
	if drop.distance_to(BIN_POS) < 52.0:
		_discard_cup()
	elif _awaiting and Rect2(CAT_POS - Vector2(70, 80), Vector2(140, 130)).has_point(drop) and drop.distance_to(TRAY_HOME) > 40.0:
		_serve()
	else:
		_return_tray()


func _return_tray() -> void:
	var t := _tray.create_tween()
	t.tween_property(_tray, "position", TRAY_HOME, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Всё с подноса — в корзину.
func _discard_cup() -> void:
	_bin.hop()
	Fx.burst(_fx, BIN_POS + Vector2(0, -16), "puff", Color(0.8, 0.8, 0.85), 6, 70.0, -20.0, 0.6, 1.0, 50.0)
	_cup.clear()
	_tray.set_contents(null, null)
	_tray.set_ready(false)
	var t := _tray.create_tween()
	t.tween_property(_tray, "position", TRAY_HOME, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_cup()


func _add_ingredient(kind: String, id: String, at: Vector2) -> void:
	var err := _cup.add(kind, id)
	if err != "":
		_toast(err, _tray.position + Vector2(0, -90))
		Fx.shake(_tray, 6.0, 0.3, 5)
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

## Подача подноса коту. Начисление наград — сразу (тесты и логика), анимация — поверх.
func _serve() -> void:
	var ok := _cup.matches(_order)
	if tutorial and not ok:
		_reject_in_tutorial()
		return
	_awaiting = false
	var total := 0
	var tip := 0
	var bonus := 0
	if ok:
		var drink_id: String = _order["drink"]
		var pastry_id: String = _order["pastry"]
		var price := int(round(float(Data.drinks[drink_id]["price"]) * GameState.price_mult(drink_id)))
		if pastry_id != "":
			price += int(Data.pastries[pastry_id]["price"])
		tip = maxi(1, int(round(price * 0.2)))
		var elapsed := (Time.get_ticks_msec() - _arrive_msec) / 1000.0
		bonus = 0 if tutorial else (5 if elapsed < 8.0 else (2 if elapsed < 15.0 else 0))
		total = price + tip + bonus
		GameState.register_served()
		shift_served += 1
		shift_earned += total
		streak += 1
		if tutorial:
			_tutorial_index += 1
		GameState.add_coins(total)
	else:
		streak = 0
	_cup.clear()
	_hide_bubble()
	_set_coach(false)
	_play_serve(ok, total, tip, bonus)


func _play_serve(ok: bool, total: int, tip: int, bonus: int) -> void:
	_tray.set_ready(false)
	var cat := _cat
	var t := _tray.create_tween().set_parallel(true)
	t.tween_property(_tray, "position", CAT_POS + Vector2(0, 40), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(_tray, "scale", Vector2(0.75, 0.75), 0.25)
	t.chain().tween_callback(_on_tray_delivered.bind(cat, ok, total, tip, bonus))


func _on_tray_delivered(cat: CatCustomer, ok: bool, total: int, tip: int, bonus: int) -> void:
	_tray.set_contents(null, null)
	_tray.visible = false
	if not is_instance_valid(cat):
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
		Fx.burst(_fx, c + Vector2(30, -50), "sweat", Color("8fd6ff"), 3, 80.0, 200.0, 0.8, 1.0, 40.0, Vector2(1, -0.4))
		_shake_screen(7.0)
		_toast("Не то... кот ушёл", Vector2(180, 392))
	get_tree().create_timer(0.45).timeout.connect(_finish_serve.bind(cat, ok))


func _finish_serve(cat: CatCustomer, ok: bool) -> void:
	if is_instance_valid(cat):
		cat.leave(ok)
	_reset_tray()


func _reset_tray() -> void:
	_tray.position = TRAY_HOME
	_tray.scale = Vector2.ONE
	_tray.visible = true
	Fx.pop_in(_tray, 0.4)
	_refresh_cup()


## Обучение: кот не уходит, а мягко просит нужное.
func _reject_in_tutorial() -> void:
	var drink: Dictionary = Data.drinks[_order["drink"]]
	_cup.clear()
	_tray.set_contents(null, null)
	_tray.set_ready(false)
	Fx.shake(_tray, 8.0, 0.4, 6)
	if is_instance_valid(_cat):
		_cat.react_no()
		Fx.burst(_fx, _cat.center() + Vector2(30, -50), "sweat", Color("8fd6ff"), 3, 80.0, 200.0, 0.8, 1.0, 40.0, Vector2(1, -0.4))
	_toast("%s просит: %s" % [String(_cat.def.get("name", "Кот")), String(drink["name"]).to_lower()], Vector2(180, 392))
	var t := _tray.create_tween()
	t.tween_interval(0.35)
	t.tween_property(_tray, "position", TRAY_HOME, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_cup()


func _on_coin_landed() -> void:
	Fx.pop(_coin_icon, 1.6, 0.3)
	Fx.burst(_fx, COIN_POS, "sparkle", Color("fff3b0"), 3, 60.0, 0.0, 0.35, 0.7)


func _shake_screen(amp: float) -> void:
	var base := position
	var t := create_tween()
	for i in 6:
		t.tween_property(self, "position", base + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) * (1.0 - i / 6.0), 0.04)
	t.tween_property(self, "position", base, 0.04)


## Конец смены: во встроенном режиме сообщаем городу (он закроет оверлей), отдельной сценой — возвращаемся в город.
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
	var ready := _awaiting and not _cup.is_empty() and _cup.matches(_order)
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

func _process(_delta: float) -> void:
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
				target = (s["center"] as Vector2) + Vector2(0, 40)
	elif step.has("target"):
		target = step["target"]
	_coach_hand.visible = target != Vector2.ZERO
	_coach_hand.position = target
	if _coach_glow != null:
		_coach_glow.queue_free()
		_coach_glow = null
	if step.has("source") and target != Vector2.ZERO:
		_coach_glow = Fx.glow(self, target + Vector2(0, -40), Vector2(170, 150), Color("fff0a0"))
	if not _coach_hand.has_meta("bob"):
		var bob := _coach_hand.create_tween().set_loops()
		bob.tween_property(_coach_hand, "scale", Vector2(1.15, 1.15), 0.4).set_trans(Tween.TRANS_SINE)
		bob.tween_property(_coach_hand, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)
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
