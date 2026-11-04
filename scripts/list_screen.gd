class_name ListScreen
extends CanvasLayer
## Общий экран-список поверх города: название (или имя вкладки), справа — баланс значками, ряд вкладок со значками (необязательно),
## четыре карточки (Card) на странице, внизу «Назад» и «Дальше». Магазин, задания, события, пропуск, ремонт и смены — все на этом экране,
## поэтому выглядят одинаково и всё влезает (проверка — tools/ui_lint.gd).
##
## provider(tab: int) → Array[Dictionary] — карточки (поля Card.make). После нажатия на кнопку карточки экран перестраивается.

signal closed

const PER_PAGE := 4
const X := 4.0
const W := 352.0
const PAD := 14.0          # от края рамки до карточек: 8 + 6
const TAB_H := 48.0

static var open_count := 0   # сколько списков открыто сейчас: пока есть открытые, нижняя панель города скрыта

var title := ""
var tabs: Array[Dictionary] = []          # [{"icon": "gift", "name": "Сегодня"}]
var provider: Callable
var header_provider: Callable = Callable()   # → Array[{"icon", "text"}]
var start_page := 0
var start_tab := 0
var _page := 0
var _tab := 0
var _root: Control


func _init() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	open_count += 1
	_hide_dock()
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_page = start_page
	_tab = start_tab
	refresh()


func _exit_tree() -> void:
	open_count = maxi(0, open_count - 1)
	var city := get_parent()
	if open_count == 0 and city != null and city.has_method("_refresh_dock"):
		city.call_deferred("_refresh_dock")


func _hide_dock() -> void:
	var city := get_parent()
	if city != null and city.has_method("_refresh_dock"):
		city.call("_refresh_dock")


func _rows() -> Array:
	return provider.call(_tab)


func page_count() -> int:
	return maxi(1, int(ceil(float(_rows().size()) / float(PER_PAGE))))


func current_tab() -> int:
	return _tab


func set_tab(i: int) -> void:
	_tab = clampi(i, 0, maxi(0, tabs.size() - 1))
	_page = 0
	refresh()


func refresh() -> void:
	for ch in _root.get_children():
		ch.queue_free()
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.55)
	_root.add_child(dim)
	var rows := _rows()
	_page = clampi(_page, 0, page_count() - 1)
	var cards_h := PER_PAGE * (Card.H + 4.0) - 4.0
	var tabs_h := TAB_H + 8.0 if not tabs.is_empty() else 0.0
	var inner_h := 28.0 + 8.0 + tabs_h + cards_h + 8.0 + Ui.BTN_H
	var h := 20.0 + inner_h + 30.0
	var top := Ui.snap((640.0 - h) / 2.0)
	Ui.panel(Rect2(X, top, W, h), Ui.UI_WOOD, _root)
	var cx := X + PAD
	var cw := W - 2.0 * PAD
	var y := top + 20.0
	_header(cx, y, cw)
	y += 28.0 + 8.0
	if not tabs.is_empty():
		_tab_bar(cx, y, cw)
		y += TAB_H + 8.0
	var first := _page * PER_PAGE
	for i in range(first, mini(rows.size(), first + PER_PAGE)):
		_card(rows[i], cx, y, cw)
		y += Card.H + 4.0
	var by := top + h - 30.0 - Ui.BTN_H
	if page_count() > 1:
		var half := Ui.snap((cw - Ui.BTN_GAP) / 2.0)
		Ui.button(tr("Назад"), Rect2(cx, by, half, Ui.BTN_H), "arrow_l", _root).pressed.connect(close)
		var nb := Ui.button(tr("Дальше"), Rect2(cx + half + Ui.BTN_GAP, by, half, Ui.BTN_H), "arrow_r", _root)
		nb.pressed.connect(_turn)
		_page_dots(cx + half + Ui.BTN_GAP, by - 10.0, half)
	else:
		Ui.button(tr("Назад"), Rect2(cx, by, cw, Ui.BTN_H), "arrow_l", _root).pressed.connect(close)


## Заголовок слева (имя вкладки или экрана), баланс справа значками: «рыбка 1234», «монета 560».
func _header(cx: float, y: float, cw: float) -> void:
	var items: Array = header_provider.call() if header_provider.is_valid() else []
	var chips_w := 0.0
	var widths: Array[float] = []
	for it in items:
		var tw := Ui.FONT_NARROW.get_string_size(String(it["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x
		var wi := Ui.snap(32.0 + 4.0 + tw + 8.0)
		widths.append(wi)
		chips_w += wi
	var name_text := tr(String(tabs[_tab]["name"])) if not tabs.is_empty() else tr(title)
	if items.is_empty():
		Ui.label(name_text, Rect2(cx, y, cw, 28.0), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER)
		return
	Ui.label(name_text, Rect2(cx, y, cw - chips_w - 8.0, 28.0), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	var x := cx + cw - chips_w
	for i in items.size():
		var ic := TextureRect.new()
		ic.texture = Ui.icon(String(items[i]["icon"]))
		ic.stretch_mode = TextureRect.STRETCH_SCALE
		ic.size = Vector2(32, 32)
		ic.position = Ui.snap_v(Vector2(x, y - 2.0))
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(ic)
		var tl := Ui.label(String(items[i]["text"]), Rect2(x + 36.0, y, widths[i] - 36.0, 28.0), Ui.FONT_SIZE, Color("9a6a12"), _root, HORIZONTAL_ALIGNMENT_LEFT, true)
		tl.add_theme_color_override("font_outline_color", Ui.CREAM)
		tl.add_theme_constant_override("outline_size", Ui.PX)
		x += widths[i]


func _tab_bar(cx: float, y: float, cw: float) -> void:
	var gap := 8.0
	var tw := Ui.snap((cw - gap * (tabs.size() - 1)) / tabs.size())
	for i in tabs.size():
		var b := Ui.button("", Rect2(cx + i * (tw + gap), y, tw, TAB_H), String(tabs[i]["icon"]), _root)
		b.modulate = Color(1.2, 1.12, 0.7) if i == _tab else Color(0.82, 0.78, 0.74)
		b.pressed.connect(set_tab.bind(i))
		if tabs[i].has("dot") and bool((tabs[i]["dot"] as Callable).call()):   # красная точка: во вкладке есть что забрать
			var dot := ColorRect.new()
			dot.color = Color("e0432f")
			dot.position = Vector2(cx + i * (tw + gap) + tw - 14.0, y + 2.0)
			dot.size = Vector2(12, 12)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_root.add_child(dot)


## Точки страниц над кнопкой «Дальше»: видно, сколько страниц и на какой мы.
func _page_dots(x: float, y: float, w: float) -> void:
	var n := page_count()
	if n > 12:
		return
	var step := 8.0
	var total := n * step
	var sx := x + Ui.snap((w - total) / 2.0)
	for i in n:
		var d := ColorRect.new()
		d.position = Vector2(sx + i * step, y)
		d.size = Vector2(4, 4)
		d.color = Ui.INK if i == _page else Ui.INK.lightened(0.55)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(d)


func _card(r: Dictionary, cx: float, y: float, cw: float) -> void:
	var o := r.duplicate()
	# нажатие кнопки карточки перестраивает экран
	if o.has("action") and (o["action"] as Dictionary).has("press"):
		var a: Dictionary = (o["action"] as Dictionary).duplicate()
		var press: Callable = a["press"]
		a["press"] = func() -> void:
			press.call()
			if is_inside_tree():
				refresh()
		o["action"] = a
	if o.has("press"):
		var cp: Callable = o["press"]
		o["press"] = func() -> void:
			cp.call()
			if is_inside_tree():
				refresh()
	Card.make(_root, Rect2(cx, y, cw, Card.H), o)


func _turn() -> void:
	_page = (_page + 1) % page_count()
	refresh()


func close() -> void:
	closed.emit()
	queue_free()
