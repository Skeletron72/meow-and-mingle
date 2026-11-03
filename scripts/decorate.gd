extends Node2D
## Режим украшения: каталог мебели за монеты, перетаскивание по залу, отражение и продажа.
## Расстановка хранится в GameState.layout и сохраняется после каждого изменения.

const MAX_ITEMS := 40
const PANEL_Y := 548.0
const CARD_W := 72.0
const SEL_COLOR := Color("fff1d6")
const BAD_COLOR := Color(1.0, 0.55, 0.5)

var _room: CafeRoom
var _ui: CanvasLayer
var _sel_box: Node2D
var _toolbar: Control
var _remove_btn: Button
var _coins_label: Label
var _hint: Panel
var _cards: Array[Dictionary] = []   # {"btn": Button, "id": String}

var _sel := -1
var _dragging := false
var _drag_off := Vector2.ZERO
var _drag_start := Vector2.ZERO
var _drag_pos := Vector2.ZERO
var _drag_err := ""


func _ready() -> void:
	_room = CafeRoom.new()
	add_child(_room)
	_room.set_layout(GameState.layout)
	_sel_box = Node2D.new()
	_sel_box.z_index = 60
	_sel_box.draw.connect(_draw_selection)
	_room.add_child(_sel_box)
	_build_ui()
	GameState.coins_changed.connect(_on_coins_changed)
	_on_coins_changed(GameState.coins)


# ---------------------------------------------------------------- интерфейс

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_build_top()
	_build_toolbar()
	_build_catalog()


func _build_top() -> void:
	Ui.panel(Rect2(8, 8, 88, 28), Ui.UI_CREAM, 5, _ui)
	var coin := Sprite2D.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(24, 22)
	coin.scale = Vector2(2, 2)
	_ui.add_child(coin)
	_coins_label = Ui.label("0", Rect2(38, 10, 54, 24), 16, Ui.INK, _ui, HORIZONTAL_ALIGNMENT_LEFT)
	_hint = Ui.panel(Rect2(100, 8, 196, 28), Ui.UI_CREAM, 5, _ui)
	Ui.label("Перетащи мебель", Rect2(0, 0, 196, 28), 11, Ui.INK, _hint)
	var back := Ui.button("", Rect2(302, 6, 50, 32), "home", _ui)
	back.pressed.connect(Nav.go.bind(self, Nav.MENU))


func _build_toolbar() -> void:
	_toolbar = Control.new()
	_toolbar.visible = false
	_ui.add_child(_toolbar)
	var flip := Ui.button("Зеркало", Rect2(8, 0, 100, 40), "undo", _toolbar, 12)
	flip.pressed.connect(_flip_selected)
	_remove_btn = Ui.button("Убрать", Rect2(112, 0, 132, 40), "trash", _toolbar, 12)
	_remove_btn.pressed.connect(_remove_selected)
	var done := Ui.button("Готово", Rect2(248, 0, 104, 40), "check", _toolbar, 12)
	done.pressed.connect(_deselect)


func _build_catalog() -> void:
	Ui.panel(Rect2(0, PANEL_Y, 360, 92), Ui.UI_WOOD, 7, _ui)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, PANEL_Y + 6)
	scroll.size = Vector2(344, 80)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ui.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	scroll.add_child(row)
	for id in Data.furniture:
		_add_card(row, String(id))


func _add_card(row: Container, id: String) -> void:
	var def := CafeRoom.item_def(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(CARD_W, 66)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", Ui.stylebox(Ui.UI_CREAM, 5))
	b.add_theme_stylebox_override("hover", Ui.stylebox(Ui.UI_CREAM, 5, Color(1.06, 1.06, 1.06)))
	b.add_theme_stylebox_override("pressed", Ui.stylebox(Ui.UI_CREAM, 5, Color(0.85, 0.85, 0.85)))
	b.pressed.connect(_buy.bind(id))
	row.add_child(b)
	var r: Array = def["rect"]
	var tex := TextureRect.new()
	tex.texture = Ui.atlas(CafeRoom.FURN_TEX, Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.position = Vector2(8, 4)
	tex.size = Vector2(CARD_W - 16.0, 32)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tex)
	Ui.label(String(def["name"]), Rect2(0, 35, CARD_W, 14), 9, Ui.INK, b)
	var price := Ui.label(str(int(def["price"])), Rect2(0, 49, CARD_W - 14.0, 14), 11, Ui.INK, b, HORIZONTAL_ALIGNMENT_RIGHT)
	var coin := TextureRect.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(CARD_W - 12.0, 49)
	coin.size = Vector2(8, 11)
	coin.stretch_mode = TextureRect.STRETCH_SCALE
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(coin)
	_cards.append({"btn": b, "id": id, "price": price})


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)
	for c in _cards:
		var affordable := value >= int(CafeRoom.item_def(c["id"])["price"])
		(c["btn"] as Button).modulate = Color.WHITE if affordable else Color(0.7, 0.7, 0.7)


func _toast(text: String, pos: Vector2) -> void:
	Ui.toast(_ui, text, pos)


# ---------------------------------------------------------------- выбор и перетаскивание

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press((make_input_local(event) as InputEventMouse).position)
		elif _dragging:
			_drop()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to((make_input_local(event) as InputEventMouse).position)


func _on_press(p: Vector2) -> void:
	if p.y >= PANEL_Y:
		return
	var i := _room.hit_test(p)
	if i < 0:
		if _room.counter_hit(p):
			_toast("Стойку нельзя двигать", p)
		_deselect()
		return
	_select(i)
	var item := GameState.layout[i]
	_drag_start = Vector2(float(item["x"]), float(item["y"]))
	_drag_pos = _drag_start
	_drag_off = _drag_start - p
	_drag_err = ""
	_dragging = true


func _select(i: int) -> void:
	_sel = i
	var id := String(GameState.layout[i]["id"])
	var price := int(CafeRoom.item_def(id)["price"])
	_remove_btn.text = "Убрать +%d" % price
	_hint.visible = false
	_toolbar.visible = true
	# панель инструментов уходит от выбранного предмета: вверх или вниз
	var y := float(GameState.layout[i]["y"])
	_toolbar.position = Vector2(0, 500.0 if y < 300.0 else 44.0)
	_sel_box.queue_redraw()


func _deselect() -> void:
	_sel = -1
	_dragging = false
	_toolbar.visible = false
	_hint.visible = true
	_sel_box.queue_redraw()


func _drag_to(p: Vector2) -> void:
	var id := String(GameState.layout[_sel]["id"])
	var pos := CafeRoom.snap(p + _drag_off)
	pos.x = clampf(pos.x, 0.0, float(CafeRoom.ROOM_W))
	pos.y = clampf(pos.y, 0.0 if CafeRoom.is_wall(id) else CafeRoom.FLOOR.position.y, CafeRoom.WALL_ZONE.end.y if CafeRoom.is_wall(id) else CafeRoom.FLOOR.end.y)
	_drag_pos = pos
	_drag_err = _room.check_place(id, pos, _sel)
	var n := _room.node_for(_sel)
	n.position = pos
	n.modulate = BAD_COLOR if _drag_err != "" else Color.WHITE
	_sel_box.queue_redraw()


func _drop() -> void:
	_dragging = false
	var n := _room.node_for(_sel)
	n.modulate = Color.WHITE
	if _drag_err != "":
		n.position = _drag_start
		_toast(_drag_err, _drag_pos + Vector2(0, -60))
	elif _drag_pos != _drag_start:
		GameState.layout[_sel]["x"] = _drag_pos.x
		GameState.layout[_sel]["y"] = _drag_pos.y
		_room.rebuild_nav()
		GameState.save_game()
	_drag_err = ""
	_sel_box.queue_redraw()


func _draw_selection() -> void:
	if _sel < 0 or _sel >= GameState.layout.size():
		return
	var id := String(GameState.layout[_sel]["id"])
	var pos := _room.node_for(_sel).position
	var r := CafeRoom.sprite_rect(id, pos).grow(3)
	var col := BAD_COLOR if _drag_err != "" else SEL_COLOR
	_sel_box.draw_rect(r, col, false, 2.0)
	if not CafeRoom.is_wall(id):
		_sel_box.draw_rect(CafeRoom.foot_rect(id, pos), Color(col, 0.28), true)


# ---------------------------------------------------------------- покупка, отражение, продажа

func _buy(id: String) -> void:
	var price := int(CafeRoom.item_def(id)["price"])
	if GameState.layout.size() >= MAX_ITEMS:
		_toast("Кафе переполнено", Vector2(180, 480))
		return
	if GameState.coins < price:
		_toast("Не хватает монет", Vector2(180, 480))
		return
	var spot := _room.find_free_spot(id)
	if spot == Vector2.INF:
		_toast("Нет свободного места", Vector2(180, 480))
		return
	GameState.layout.append({"id": id, "x": spot.x, "y": spot.y, "flip": false})
	_room.rebuild()
	GameState.spend_coins(price)  # сохраняет и расстановку
	_select(GameState.layout.size() - 1)


func _flip_selected() -> void:
	if _sel < 0:
		return
	GameState.layout[_sel]["flip"] = not bool(GameState.layout[_sel]["flip"])
	_room.rebuild()
	GameState.save_game()
	_sel_box.queue_redraw()


func _remove_selected() -> void:
	if _sel < 0:
		return
	var id := String(GameState.layout[_sel]["id"])
	var price := int(CafeRoom.item_def(id)["price"])
	var pos := Vector2(float(GameState.layout[_sel]["x"]), float(GameState.layout[_sel]["y"]))
	GameState.layout.remove_at(_sel)
	_room.rebuild()
	_deselect()
	GameState.add_coins(price)  # возврат полной цены; заодно сохраняет расстановку
	_toast("+%d" % price, pos + Vector2(0, -50))
