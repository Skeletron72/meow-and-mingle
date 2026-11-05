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
var _cards: Array[Dictionary] = []   # {"btn": Button, "id": String, "holder": Control, "style": String}
var _style_btn: Button
var _cozy_btn: Button
var _remove_btn: Button   # у прилавка недоступна: он обязателен
var _style := "cozy"                # какой стиль мебели показан в каталоге

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
	Ui.panel(Rect2(8, 8, 112, 48), Ui.UI_CREAM, _ui)
	var coin := Sprite2D.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(28, 28)
	coin.scale = Vector2(2, 2)
	_ui.add_child(coin)
	_coins_label = Ui.label("0", Rect2(44, 12, 76, 32), Ui.FONT_SIZE, Ui.INK, _ui, HORIZONTAL_ALIGNMENT_LEFT)
	_hint = Control.new()
	_ui.add_child(_hint)
	_style_btn = Ui.button("", Rect2(124, 8, 164, 48), "", _hint, true, Ui.UI_CREAM)   # стиль каталога: Уют, Лофт, Японский, Зимний
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_style_btn.add_theme_color_override(c, Ui.INK)
	_style_btn.add_theme_color_override("font_outline_color", Ui.CREAM)
	_style_btn.pressed.connect(_cycle_style)
	_refresh_style_button()
	var back := Ui.button("", Rect2(296, 8, 56, 48), "home", _ui)
	back.pressed.connect(_back)
	_cozy_btn = Ui.button("0", Rect2(276, 60, 76, 40), "heart", _ui, true, Ui.UI_CREAM)   # «Уют» кафе: уровень и бонус; тап — подробности
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_cozy_btn.add_theme_color_override(c, Ui.INK)
	_cozy_btn.add_theme_color_override("font_outline_color", Ui.CREAM)
	_cozy_btn.pressed.connect(_explain_cozy)
	_refresh_cozy()


func _refresh_cozy() -> void:
	Ui.set_button_text(_cozy_btn, str(GameState.cozy_score()))


func _explain_cozy() -> void:
	_toast(tr("Уют %d из %d: чаевые +%d%%, терпение гостей +%d%%") % [GameState.cozy_score(), GameState.COZY_MAX, int(round(GameState.cozy_tip_bonus() * 100.0)), int(round(GameState.cozy_patience_bonus() * 100.0))], Vector2(180, 120))


func _build_toolbar() -> void:
	_toolbar = Control.new()
	_toolbar.visible = false
	_ui.add_child(_toolbar)
	var flip := Ui.button("Зеркало", Rect2(6, 0, 116, 56), "undo", _toolbar, true)
	flip.pressed.connect(_flip_selected)
	var remove := Ui.button("Убрать", Rect2(126, 0, 108, 56), "trash", _toolbar, true)
	remove.pressed.connect(_remove_selected)
	_remove_btn = remove
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
		if bool(Data.furniture[id].get("required", false)) or bool(Data.furniture[id].get("hidden", false)):
			continue   # прилавок уже стоит (обязательный, его только двигают); раскраски прилавка в каталог не попадают
		_add_card(row, String(id))
	_apply_style_filter()


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
	var sponsored := _is_sponsored(id)
	var price_label := Ui.label(str(int(def["price"])), Rect2(0, 74, CARD_W - 30.0, 28), Ui.FONT_SIZE, Ui.INK, b, HORIZONTAL_ALIGNMENT_RIGHT)
	var coin := TextureRect.new()
	coin.texture = Ui.icon("video" if sponsored else "coin")   # спонсорская мебель — за ролики: «просмотрено/нужно» вместо цены
	coin.stretch_mode = TextureRect.STRETCH_SCALE
	coin.size = Vector2(32, 32) if sponsored else Vector2(22, 28)
	coin.position = Vector2(CARD_W - 34.0, 72) if sponsored else Vector2(CARD_W - 28.0, 74)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(coin)
	if sponsored:
		price_label.text = "%d/%d" % [Shop.decor_views(id), int(def["ad_cost"])]
		price_label.set_meta("ad_label", true)
	_cards.append({"btn": b, "id": id, "holder": holder, "style": String(def.get("style", "cozy"))})


## Стили, доступные игроку: «Уют» всегда, остальные — после задач ремонта и событий (открытие `style:<id>`).
func available_styles() -> Array[String]:
	var out: Array[String] = []
	for key in Data.styles["decor"]:
		if String(key) == "cozy" or GameState.has_unlock("style:%s" % String(key)):
			out.append(String(key))
	return out


func _cycle_style() -> void:
	var list := available_styles()
	_style = list[(list.find(_style) + 1) % list.size()]
	_apply_style_filter()
	_refresh_style_button()


func _refresh_style_button() -> void:
	var name_text := String(Data.styles["decor"][_style]["name"])
	Ui.set_button_text(_style_btn, tr("Стиль: %s") % tr(name_text))


## Спонсорская мебель продаётся за ролики (если реклама не отключена покупкой «Без рекламы») и открыта с 3-й смены.
func _is_sponsored(id: String) -> bool:
	return int(CafeRoom.item_def(id).get("ad_cost", 0)) > 0 and not Shop.ads_removed()


func _apply_style_filter() -> void:
	for c in _cards:
		var hidden_ad := int(CafeRoom.item_def(String(c["id"])).get("ad_cost", 0)) > 0 and GameState.shifts_played < 3
		(c["holder"] as Control).visible = String(c["style"]) == _style and not hidden_ad


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)
	for c in _cards:
		var affordable := value >= int(CafeRoom.item_def(c["id"])["price"]) or _is_sponsored(String(c["id"]))
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
	_remove_btn.disabled = CafeRoom.is_counter(String(GameState.layout[i]["id"]))
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
	var def := CafeRoom.item_def(id)
	var price := int(def["price"])
	if GameState.layout.size() >= MAX_ITEMS:
		_toast("Кафе переполнено", Vector2(180, 470))
		return
	if _is_sponsored(id):   # за ролики; место проверяем заранее, чтобы не тратить просмотры впустую
		if _room.find_free_spot(id).x < 0:
			_toast("Нет свободного места", Vector2(180, 470))
			return
		if not Shop.ad_ready("decor"):
			_toast("Ролик сейчас недоступен", Vector2(180, 470))
			return
		Shop.watch_for_item(id, int(def["ad_cost"]), func(ok: bool, got: bool) -> void:
			if not ok:
				return
			_refresh_cards()
			if got:
				_place(id, 0)
			else:
				_toast(tr("Ещё роликов: %d") % (int(def["ad_cost"]) - Shop.decor_views(id)), Vector2(180, 470)))
		return
	if GameState.coins < price:
		_toast("Не хватает монет", Vector2(180, 470))
		return
	_place(id, price)


## Ставит купленный предмет на свободное место и выбирает его; price монет списывается (0 — подарок за ролики).
func _place(id: String, price: int) -> void:
	var spot := _room.find_free_spot(id)
	if spot.x < 0:
		_toast("Нет свободного места", Vector2(180, 470))
		return
	GameState.layout.append({"id": id, "c": spot.x, "r": spot.y, "flip": false})
	_room.rebuild()
	_refresh_cozy()
	if price > 0:
		GameState.spend_coins(price)  # сохраняет и расстановку
	else:
		GameState.save_game()
	_select(GameState.layout.size() - 1)


## Обновляет «просмотрено/нужно» на карточках спонсорской мебели.
func _refresh_cards() -> void:
	for c in _cards:
		var id := String(c["id"])
		if _is_sponsored(id):
			for n in (c["btn"] as Control).get_children():
				if n is Label and (n as Label).has_meta("ad_label"):
					(n as Label).text = "%d/%d" % [Shop.decor_views(id), int(CafeRoom.item_def(id)["ad_cost"])]


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
	if CafeRoom.is_counter(String(item["id"])):   # прилавок обязателен: его можно переставить, но не убрать
		_toast_at(tr("Прилавок нужен кафе: его можно только двигать"), _room.node_for(_sel).position + Vector2(0, -50))
		return
	if int(CafeRoom.item_def(String(item["id"])).get("ad_cost", 0)) > 0:   # спонсорский подарок не продаётся (иначе — монеты за ролики)
		_toast("Подарок поставщика не убрать, только двигать", Vector2(180, 470))
		return
	var price := int(CafeRoom.item_def(String(item["id"]))["price"])
	var at := _room.node_for(_sel).position
	GameState.layout.remove_at(_sel)
	_room.rebuild()
	_refresh_cozy()
	_deselect()
	GameState.add_coins(price)  # возврат полной цены; заодно сохраняет расстановку
	_toast_at("+%d" % price, at + Vector2(0, -50))
