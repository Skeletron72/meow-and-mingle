extends Node2D
## Главная сцена кофейни (этап 1): кот приходит, заказ в пузыре, сборка перетаскиванием, монеты.
## Весь интерфейс строится кодом, чтобы прототип был одним файлом сцены + скриптом.

const CUP_POS := Vector2(180, 322)    # центр чашки на стойке
const CAT_POS := Vector2(180, 262)
const CAT_SPAWN_X := 460.0
const NEXT_CAT_DELAY := 1.5
const PASTRY_CHANCE := 0.5
const TRASH_POS := Vector2(318, 322)
const INK := Color("4a2e1a")

const COFFEE_SHEET: Texture2D = preload("res://AssetPack_V01_FREE.png")  # сетка 16x16, 5 колонок
const ICONS: Texture2D = preload("res://IconsEssential.png")
const FURN: Texture2D = preload("res://assets/cafe/neko-cafe-furnitures.png")
const UI_CREAM: Texture2D = preload("res://assets/ui/SimpleColorContainer1_cream.png")
const UI_WOOD: Texture2D = preload("res://assets/ui/WoodenContainer5.png")

var _cup := CupState.new()
var _sources: Array[Dictionary] = []   # {kind, id, rect, tex}
var _drag: Dictionary = {}             # {kind, id, ghost}
var _cat: CatCustomer
var _order: Dictionary = {}            # {"drink": id, "pastry": id|""}
var _awaiting := false
var _arrive_msec := 0

var _cat_layer: Node2D
var _cup_sprite: Sprite2D
var _cup_pastry: Sprite2D
var _cup_hint: Label
var _bubble: Node2D
var _coins_label: Label
var _served_label: Label


func _ready() -> void:
	_build_background()
	_cat_layer = Node2D.new()
	add_child(_cat_layer)
	_build_counter()
	_build_tray()
	_build_hud()
	GameState.coins_changed.connect(_on_coins_changed)
	_on_coins_changed(GameState.coins)
	_refresh_cup()
	_spawn_cat()


# ---------------------------------------------------------------- построение сцены

func _build_background() -> void:
	_rect(Rect2(0, 0, 360, 300), Color("cdb892"))
	_rect(Rect2(0, 300, 360, 340), Color("7c5a3a"))
	var board := _sprite(_atlas(FURN, Rect2(112, 18, 32, 20)), Vector2(180, 88), 4.0)
	board.z_index = 0


func _build_counter() -> void:
	var tex := _atlas(FURN, Rect2(16, 111, 48, 18))
	for x in [-12.0, 180.0]:
		var s := _sprite(tex, Vector2(x + 96.0, 292.0 + 36.0), 4.0)
		s.z_index = 1
	_cup_sprite = _sprite(_drink_tex("espresso"), CUP_POS, 4.0)
	_cup_sprite.z_index = 2
	_cup_pastry = _sprite(null, CUP_POS + Vector2(58, 8), 3.0)
	_cup_pastry.z_index = 2
	_cup_hint = _label("Собери заказ ниже", Rect2(80, 358, 200, 16), 10, Color("fff1d6"))
	_cup_hint.z_index = 2
	var trash := _sprite(_atlas(ICONS, Rect2(80, 208, 15, 17)), TRASH_POS, 2.0)
	trash.z_index = 2


func _build_tray() -> void:
	var tray := _panel(Rect2(10, 380, 340, 252), UI_WOOD, 7)
	tray.z_index = 1
	_tray_label("Напитки", Vector2(24, 392))
	_tray_label("Витрина", Vector2(24, 492))
	_add_source("base", "coffee", "Кофе", _drink_tex("espresso"), Vector2(70, 446))
	_add_source("base", "tea", "Чай", _drink_tex("tea"), Vector2(180, 446))
	_add_source("milk", "milk", "Молоко", _cell(0, 4), Vector2(290, 446))
	var x := 70.0
	for id in Data.pastries:
		_add_source("pastry", id, String(Data.pastries[id]["name"]), _pastry_tex(id), Vector2(x, 548))
		x += 110.0


func _build_hud() -> void:
	var coin := _sprite(_atlas(ICONS, Rect2(210, 209, 11, 14)), Vector2(24, 22), 2.0)
	coin.z_index = 5
	_coins_label = _label("0", Rect2(40, 11, 120, 22), 16, INK)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_coins_label.z_index = 5
	_served_label = _label("", Rect2(120, 14, 180, 18), 11, INK)
	_served_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_served_label.z_index = 5
	var menu_btn := Ui.button("", Rect2(306, 6, 46, 32), "home", self)
	menu_btn.z_index = 5
	menu_btn.pressed.connect(Nav.go.bind(self, Nav.MENU))


func _add_source(kind: String, id: String, title: String, tex: Texture2D, center: Vector2) -> void:
	var icon := _sprite(tex, center, 3.0)
	icon.z_index = 2
	var cap := _label(title, Rect2(center.x - 50, center.y + 28, 100, 16), 11, INK)
	cap.z_index = 2
	_sources.append({
		"kind": kind, "id": id, "tex": tex,
		"rect": Rect2(center - Vector2(40, 36), Vector2(80, 80)),
	})


func _tray_label(text: String, pos: Vector2) -> void:
	var l := _label(text, Rect2(pos, Vector2(120, 16)), 11, INK)
	l.z_index = 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


# ---------------------------------------------------------------- котики и заказы

func _spawn_cat() -> void:
	var def: Dictionary = Data.cats.pick_random()
	var drink_id: String = Data.drinks.keys().pick_random()
	var pastry_id := ""
	if randf() < PASTRY_CHANCE:
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
	_show_bubble()


func _on_cat_left(cat: CatCustomer) -> void:
	cat.queue_free()
	# не await: если игрок вышел в меню, таймер не должен будить уже удалённую сцену
	get_tree().create_timer(NEXT_CAT_DELAY).timeout.connect(_spawn_cat)


func _show_bubble() -> void:
	_hide_bubble()
	_bubble = Node2D.new()
	_bubble.z_index = 3
	add_child(_bubble)
	_panel(Rect2(95, 138, 170, 84), UI_CREAM, 5, _bubble)
	var drink: Dictionary = Data.drinks[_order["drink"]]
	var title: String = drink["name"]
	var pastry_id: String = _order["pastry"]
	var drink_x := 180.0
	if pastry_id != "":
		drink_x = 150.0
		var pastry: Dictionary = Data.pastries[pastry_id]
		_sprite(_pastry_tex(pastry_id), Vector2(210, 168), 3.0, _bubble)
		title += " + " + String(pastry["name"]).to_lower()
	_sprite(_drink_tex(_order["drink"]), Vector2(drink_x, 168), 3.0, _bubble)
	_label(title, Rect2(95, 198, 170, 16), 10, INK, _bubble)


func _hide_bubble() -> void:
	if _bubble:
		_bubble.queue_free()
		_bubble = null


# ---------------------------------------------------------------- перетаскивание

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(get_global_mouse_position())
		else:
			_end_drag()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		(_drag["ghost"] as Sprite2D).position = get_global_mouse_position() + Vector2(0, -24)


func _begin_drag(p: Vector2) -> void:
	if not _drag.is_empty():
		return
	if not _cup.is_empty() and Rect2(CUP_POS - Vector2(40, 40), Vector2(80, 80)).has_point(p):
		_start_drag("cup", "", _cup_sprite.texture, 4.0, p)
		_cup_sprite.modulate.a = 0.3
		return
	for s in _sources:
		if (s["rect"] as Rect2).has_point(p):
			_start_drag(s["kind"], s["id"], s["tex"], 3.0, p)
			return


func _start_drag(kind: String, id: String, tex: Texture2D, s: float, p: Vector2) -> void:
	var ghost := _sprite(tex, p + Vector2(0, -24), s)
	ghost.z_index = 100
	_drag = {"kind": kind, "id": id, "ghost": ghost}


func _end_drag() -> void:
	if _drag.is_empty():
		return
	var kind: String = _drag["kind"]
	var id: String = _drag["id"]
	var ghost: Sprite2D = _drag["ghost"]
	var drop := ghost.position
	ghost.queue_free()
	_drag = {}
	if kind == "cup":
		if drop.distance_to(TRASH_POS) < 36.0:
			_cup.clear()
		elif _awaiting and drop.distance_to(CUP_POS) > 50.0 and Rect2(CAT_POS - Vector2(56, 60), Vector2(112, 100)).has_point(drop):
			_serve()
	elif drop.distance_to(CUP_POS) < 60.0:
		var err := _cup.add(kind, id)
		if err != "":
			_toast(err, CUP_POS + Vector2(0, 50))
	_refresh_cup()


# ---------------------------------------------------------------- подача заказа

func _serve() -> void:
	_awaiting = false
	var ok := _cup.matches(_order)
	if ok:
		var drink_id: String = _order["drink"]
		var pastry_id: String = _order["pastry"]
		var price := int(Data.drinks[drink_id]["price"])
		if pastry_id != "":
			price += int(Data.pastries[pastry_id]["price"])
		var tip := maxi(1, int(round(price * 0.2)))
		var elapsed := (Time.get_ticks_msec() - _arrive_msec) / 1000.0
		var bonus := 5 if elapsed < 8.0 else (2 if elapsed < 15.0 else 0)
		GameState.register_served()
		GameState.add_coins(price + tip + bonus)
		_toast("+%d  (чаевые %d, скорость %d)" % [price + tip + bonus, tip, bonus], CAT_POS + Vector2(0, -90))
	else:
		_toast("Не то... кот ушёл", CAT_POS + Vector2(0, -90))
	_cat.leave(ok)
	_cup.clear()
	_hide_bubble()
	_refresh_cup()


# ---------------------------------------------------------------- отображение

func _refresh_cup() -> void:
	var did := _cup.drink_id()
	if did == "":
		_cup_sprite.texture = _drink_tex("espresso")
		_cup_sprite.modulate.a = 0.25
	else:
		_cup_sprite.texture = _drink_tex(did)
		_cup_sprite.modulate.a = 1.0
	_cup_pastry.visible = _cup.pastry != ""
	if _cup.pastry != "":
		_cup_pastry.texture = _pastry_tex(_cup.pastry)
	_cup_hint.visible = _cup.is_empty()


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)
	_served_label.text = tr("Подано: %d") % GameState.served_total


func _toast(text: String, pos: Vector2) -> void:
	var l := _label(text, Rect2(pos - Vector2(130, 0), Vector2(260, 18)), 12, INK)
	l.z_index = 50
	var t := create_tween().set_parallel(true)
	t.tween_property(l, "position:y", pos.y - 36.0, 1.4)
	t.tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.6)
	t.chain().tween_callback(l.queue_free)


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


func _rect(r: Rect2, color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.position = r.position
	c.size = r.size
	c.color = color
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _panel(r: Rect2, tex: Texture2D, margin: int, parent: Node = null) -> Panel:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", sb)
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else self).add_child(p)
	return p


func _label(text: String, r: Rect2, font_size: int, color: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else self).add_child(l)
	return l
