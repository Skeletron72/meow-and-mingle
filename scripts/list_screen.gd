class_name ListScreen
extends CanvasLayer
## Общий экран-список: заголовок, строка справа от заголовка (баланс), карточки-кнопки по 4 на странице, «Назад» и «Дальше».
## Строки даёт provider() — массив {"title", "sub", "right", "enabled", "press": Callable, "tint": Color(необязательно)};
## после нажатия экран перестраивается (provider вызывается заново). Используется магазином, заданиями и пропуском сезона.

signal closed

const PER_PAGE := 4
const CARD_H := 84.0
const CARD_GAP := 4.0
const X := 12.0
const W := 336.0

var title := ""
var provider: Callable
var header_provider: Callable = Callable()   # → String: что показать справа в заголовке (рыбки, звёзды)
var start_page := 0
var _page := 0
var _root: Control


func _init() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_page = start_page
	refresh()


func _rows() -> Array:
	return provider.call()


func page_count() -> int:
	return maxi(1, int(ceil(float(_rows().size()) / float(PER_PAGE))))


func refresh() -> void:
	for ch in _root.get_children():
		ch.queue_free()
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.55)
	_root.add_child(dim)
	var content_h := PER_PAGE * CARD_H + (PER_PAGE - 1) * CARD_GAP + Ui.BTN_GAP + Ui.BTN_H
	var h := Ui.page_height(content_h)
	var top := floorf((640.0 - h) / 2.0 / 2.0) * 2.0
	Ui.panel(Rect2(X, top, W, h), Ui.UI_WOOD, _root)
	var head := String(header_provider.call()) if header_provider.is_valid() else ""
	if head == "":
		Ui.label(tr(title), Rect2(X, top + Ui.PAGE_PAD_TOP, W, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		Ui.label(tr(title), Rect2(X + Ui.PAGE_PAD_X, top + Ui.PAGE_PAD_TOP, W - 2.0 * Ui.PAGE_PAD_X - 130.0, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	if head != "":
		var hl := Ui.label(head, Rect2(X + W - 24.0 - 120.0, top + Ui.PAGE_PAD_TOP, 120.0, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Color("c2891a"), _root, HORIZONTAL_ALIGNMENT_RIGHT, true)
		hl.add_theme_color_override("font_outline_color", Ui.CREAM)
		hl.add_theme_constant_override("outline_size", Ui.PX)
	var cx := X + Ui.PAGE_PAD_X
	var cw := W - 2.0 * Ui.PAGE_PAD_X
	var y := top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + Ui.PAGE_GAP
	var rows := _rows()
	_page = clampi(_page, 0, page_count() - 1)
	var first := _page * PER_PAGE
	for i in range(first, mini(rows.size(), first + PER_PAGE)):
		_card(rows[i], cx, y, cw)
		y += CARD_H + CARD_GAP
	var by := top + h - Ui.PAGE_PAD_BOTTOM - Ui.BTN_H
	if page_count() > 1:
		var half := (cw - Ui.BTN_GAP) / 2.0
		Ui.button(tr("Назад"), Rect2(cx, by, half, Ui.BTN_H), "undo", _root).pressed.connect(close)
		Ui.button(tr("Дальше") if _page < page_count() - 1 else tr("Раньше"), Rect2(cx + half + Ui.BTN_GAP, by, half, Ui.BTN_H), "", _root).pressed.connect(_turn)
	else:
		Ui.button(tr("Назад"), Rect2(cx, by, cw, Ui.BTN_H), "undo", _root).pressed.connect(close)


func _card(r: Dictionary, cx: float, y: float, cw: float) -> void:
	var enabled := bool(r.get("enabled", true))
	var b := Ui.button("", Rect2(cx, y, cw, CARD_H), "", _root)
	b.disabled = not enabled
	b.modulate = r.get("tint", Color.WHITE) if enabled else Color(0.62, 0.62, 0.62)
	var press: Callable = r.get("press", Callable())
	if press.is_valid():
		b.pressed.connect(func() -> void:
			press.call()
			if is_inside_tree():
				refresh())
	var right := String(r.get("right", ""))
	var rw := 0.0
	if right != "":
		rw = clampf(Ui.FONT_NARROW.get_string_size(tr(right), HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x + 8.0, 40.0, 110.0)
	var tw := cw - 24.0 - rw
	Ui.label(tr(String(r["title"])), Rect2(cx + 12.0, y + 12.0, tw, Ui.LINE_H), Ui.FONT_SIZE, Ui.CREAM, _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	Ui.label(String(r.get("sub", "")), Rect2(cx + 12.0, y + 12.0 + Ui.LINE_H, cw - 24.0, Ui.LINE_H), Ui.FONT_SIZE, Ui.CREAM.darkened(0.15), _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	if right != "":
		var rl := Ui.label(tr(right), Rect2(cx + cw - 12.0 - rw, y + 12.0, rw, Ui.LINE_H), Ui.FONT_SIZE, Color("ffd640"), _root, HORIZONTAL_ALIGNMENT_RIGHT, true)
		rl.add_theme_color_override("font_outline_color", Ui.INK)
		rl.add_theme_constant_override("outline_size", Ui.PX)


func _turn() -> void:
	_page = (_page + 1) % page_count()
	refresh()


func close() -> void:
	closed.emit()
	queue_free()
