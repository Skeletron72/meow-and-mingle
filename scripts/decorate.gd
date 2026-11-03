extends Node2D
## Режим украшения: каталог мебели за монеты, перетаскивание по клеткам сетки 16×16, отражение и продажа.
## Расстановка хранится в GameState.layout и сохраняется после каждого изменения.

const MAX_ITEMS := 40
const PANEL_Y := 494.0
const ROOM_POS := Vector2(20, 64)     # где на экране стоит комната (её размер 320×320)
const TOOLBAR_Y := 400.0
const CARD_W := 96.0
const CARD_H := 116.0   # свободно 106 px (контур 2, бортик 8): превью 40 + название 28 + цена 28 + воздух
const SEL_COLOR := Color("fff1d6")
const BAD_COLOR := Color(1.0, 0.55, 0.5)

var _room: CafeRoom
var _ui: CanvasLayer
var _sel_box: Node2D
var _toolbar: Control
var _hint: Control
var _coins_label: Label
var _cards: Array[Dictionary] = []   # {"btn": Button, "id": String}

var _sel := -1
var _dragging := false
var _drag_off := Vector2i.ZERO       # клетка предмета минус клетка под пальцем в момент нажатия
var _drag_start := Vector2i.ZERO
var _drag_cell := Vector2i.ZERO
var _drag_err := ""


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(360, 640)
	backdrop.color = Color("2e2330")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_room = CafeRoom.new()
	_room.position = ROOM_POS
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
	Ui.panel(Rect2(8, 8, 108, 48), Ui.UI_CREAM, _ui)
	var coin := Sprite2D.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(28, 28)
	coin.scale = Vector2(2, 2)
	_ui.add_child(coin)
	_coins_label = Ui.label("0", Rect2(44, 12, 68, 32), Ui.FONT_SIZE, Ui.INK, _ui, HORIZONTAL_ALIGNMENT_LEFT)
	_hint = Control.new()
	_ui.add_child(_hint)
	Ui.panel(Rect2(124, 8, 164, 48), Ui.UI_CREAM, _hint)
	Ui.label("Тяни мебель", Rect2(124, 12, 164, 32), Ui.FONT_SIZE, Ui.INK, _hint, HORIZONTAL_ALIGNMENT_CENTER, true)
	var back := Ui.button("", Rect2(296, 8, 56, 48), "home", _ui)
	back.pressed.connect(_back)


func _build_toolbar() -> void:
	_toolbar = Control.new()
	_toolbar.visible = false
	_ui.add_child(_toolbar)
	var flip := Ui.button("Зеркало", Rect2(6, 0, 116, 56), "undo", _toolbar, true)
	flip.pressed.connect(_flip_selected)
	var remove := Ui.button("Убрать", Rect2(126, 0, 108, 56), "trash", _toolbar, true)
	remove.pressed.connect(_remove_selected)
	var done := Ui.button("Готово", Rect2(238, 0, 116, 56), "check", _toolbar, true)
	done.pressed.connect(_deselect)


func _build_catalog() -> void:
	Ui.panel(Rect2(0, PANEL_Y, 360, 146), Ui.UI_WOOD, _ui)   # деревянная рамка: 8 сверху, 14 снизу, карточки между ними
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(14, PANEL_Y + Ui.WOOD_EDGE)
	scroll.size = Vector2(332, CARD_H)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # листается пальцем или колесом мыши
	_ui.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	scroll.add_child(row)
	for id in Data.furniture:
		_add_card(row, String(id))


func _add_card(row: Container, id: String) -> void:
	var def := CafeRoom.item_def(id)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CARD_W, CARD_H)
	row.add_child(holder)
	var b := Ui.button("", Rect2(0, 0, CARD_W, CARD_H), "", holder, false, Ui.UI_CREAM)
	b.pressed.connect(_buy.bind(id))
	# миниатюра: в масштабе 2, если помещается, иначе 1
	var r: Array = def["rect"]
	var size := Vector2(float(r[2]), float(r[3]))
	var k := 2.0 if size.x * 2.0 <= 80.0 and size.y * 2.0 <= 40.0 else 1.0
	var tex := TextureRect.new()
	tex.texture = Ui.atlas(CafeRoom.FURN_TEX, Rect2(float(r[0]), float(r[1]), size.x, size.y))
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.size = size * k
	tex.position = Vector2(roundf((CARD_W - tex.size.x) / 4.0) * 2.0, roundf((40.0 - tex.size.y) / 4.0) * 2.0 + 4.0)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tex)
	Ui.label(String(def["name"]), Rect2(0, 46, CARD_W, 28), Ui.FONT_SIZE, Ui.INK, b, HORIZONTAL_ALIGNMENT_CENTER, true)
	Ui.label(str(int(def["price"])), Rect2(0, 74, CARD_W - 30.0, 28), Ui.FONT_SIZE, Ui.INK, b, HORIZONTAL_ALIGNMENT_RIGHT)
	var coin := TextureRect.new()
	coin.texture = Ui.icon("coin")
	coin.stretch_mode = TextureRect.STRETCH_SCALE
	coin.size = Vector2(22, 28)
	coin.position = Vector2(CARD_W - 28.0, 74)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(coin)
	_cards.append({"btn": b, "id": id})


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)
	for c in _cards:
		var affordable := value >= int(CafeRoom.item_def(c["id"])["price"])
		(c["btn"] as Button).modulate = Color.WHITE if affordable else Color(0.7, 0.7, 0.7)


func _toast(text: String, pos: Vector2) -> void:
	Ui.toast(_ui, text, pos)


## Тост у точки комнаты (координаты комнаты -> экран).
func _toast_at(text: String, room_pos: Vector2) -> void:
	_toast(text, _room.to_global(room_pos))


func _back() -> void:
	GameState.save_game()
	Nav.go(self, Nav.CITY)


# ---------------------------------------------------------------- выбор и перетаскивание

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press((_room.make_input_local(event) as InputEventMouse).position)
		elif _dragging:
			_drop()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to((_room.make_input_local(event) as InputEventMouse).position)


func _pointer_cell(id: String, p: Vector2) -> Vector2i:
	return CafeRoom.wall_cell_at(p) if CafeRoom.is_wall(id) else CafeRoom.cell_at(p)


func _on_press(p: Vector2) -> void:   # p — в координатах комнаты
	if _room.to_global(p).y >= PANEL_Y:
		return
	var i := _room.hit_test(p)
	if i < 0:
		if _room.counter_hit(p):
			_toast_at("Стойку нельзя двигать", p)
		_deselect()
		return
	_select(i)
	var item := GameState.layout[i]
	_drag_start = Vector2i(int(item["c"]), int(item["r"]))
	_drag_cell = _drag_start
	_drag_off = _drag_start - _pointer_cell(String(item["id"]), p)
	_drag_err = ""
	_dragging = true


func _select(i: int) -> void:
	_sel = i
	_hint.visible = false
	_toolbar.visible = true
	_toolbar.position = Vector2(0, TOOLBAR_Y)   # под комнатой: ничего не закрывает
	_sel_box.queue_redraw()


func _deselect() -> void:
	_sel = -1
	_dragging = false
	_toolbar.visible = false
	_hint.visible = true
	_sel_box.queue_redraw()


func _drag_to(p: Vector2) -> void:
	var id := String(GameState.layout[_sel]["id"])
	var cell := _pointer_cell(id, p) + _drag_off
	_drag_cell = cell
	_drag_err = _room.check_place(id, cell.x, cell.y, _sel)
	_room.preview_move(_sel, cell.x, cell.y)
	_room.node_for(_sel).modulate = BAD_COLOR if _drag_err != "" else Color.WHITE
	_sel_box.queue_redraw()


func _drop() -> void:
	_dragging = false
	var n := _room.node_for(_sel)
	n.modulate = Color.WHITE
	if _drag_err != "":
		_room.preview_move(_sel, _drag_start.x, _drag_start.y)
		_toast_at(_drag_err, n.position + Vector2(0, -60))
	elif _drag_cell != _drag_start:
		GameState.layout[_sel]["c"] = _drag_cell.x
		GameState.layout[_sel]["r"] = _drag_cell.y
		_room.rebuild()  # переносит и спрайт (его смещение зависит от клетки), и сетку путей
		GameState.save_game()
	_drag_err = ""
	_sel_box.queue_redraw()


## Клетки предмета (подсвечиваются) и рамка вокруг его спрайта. Во время перетаскивания — по текущей клетке.
func _draw_selection() -> void:
	if _sel < 0 or _sel >= GameState.layout.size():
		return
	var item := GameState.layout[_sel]
	var id := String(item["id"])
	var cell := _drag_cell if _dragging else Vector2i(int(item["c"]), int(item["r"]))
	var col := BAD_COLOR if _drag_err != "" else SEL_COLOR
	var area := CafeRoom.cells(id, cell.x, cell.y)
	var top := CafeRoom.cell_pos(cell.x, cell.y, CafeRoom.is_wall(id))
	var footprint := Rect2(top, Vector2(area.size) * CafeRoom.T)
	_sel_box.draw_rect(footprint, Color(col, 0.25), true)
	_sel_box.draw_rect(CafeRoom.sprite_rect(id, cell.x, cell.y).grow(2).merge(footprint), col, false, 2.0)


# ---------------------------------------------------------------- покупка, отражение, продажа

func _buy(id: String) -> void:
	var price := int(CafeRoom.item_def(id)["price"])
	if GameState.layout.size() >= MAX_ITEMS:
		_toast("Кафе переполнено", Vector2(180, 470))
		return
	if GameState.coins < price:
		_toast("Не хватает монет", Vector2(180, 470))
		return
	var spot := _room.find_free_spot(id)
	if spot.x < 0:
		_toast("Нет свободного места", Vector2(180, 470))
		return
	GameState.layout.append({"id": id, "c": spot.x, "r": spot.y, "flip": false})
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
	var item := GameState.layout[_sel]
	var price := int(CafeRoom.item_def(String(item["id"]))["price"])
	var at := _room.node_for(_sel).position
	GameState.layout.remove_at(_sel)
	_room.rebuild()
	_deselect()
	GameState.add_coins(price)  # возврат полной цены; заодно сохраняет расстановку
	_toast_at("+%d" % price, at + Vector2(0, -50))
