class_name RecipeBook
extends CanvasLayer
## Шпаргалка рецептов прямо в смене: открытые напитки с «составом» значками (основа, молоко, сироп, добавки). Одно касание кнопки-книги на прилавке;
## смена на паузе, пока окно открыто (в main — флаг `_paused`, время ожидания гостей и остывание не идут). Листается по 6 строк.

signal closed

const PER_PAGE := 6
const X := 12.0
const W := 336.0
const ROW_H := 56.0
const CHIP := 32.0

var drink_ids: Array[String] = []
var cell_tex: Callable      # id напитка → текстура готовой чашки
var base_tex: Callable      # id основы (coffee/tea/cocoa) → текстура
var _page := 0
var _root: Control


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()


func page_count() -> int:
	return maxi(1, int(ceil(float(drink_ids.size()) / float(PER_PAGE))))


## Состав напитка значками: основа, молоко, сироп, добавки (лёд, корица, сливки, вторая порция, вторая основа «какао»).
func ingredient_textures(drink_id: String) -> Array[Texture2D]:
	var r: Dictionary = Data.drinks[drink_id]["recipe"]
	var out: Array[Texture2D] = []
	out.append(base_tex.call(String(r["base"])))
	if bool(r["milk"]):
		out.append(PixelArt.shelf_icon("milk"))
	if bool(r.get("syrup", false)):
		out.append(PixelArt.shelf_icon("syrup"))
	for m in r.get("mods", []):
		match String(m):
			"ice", "cinnamon", "cream":
				out.append(PixelArt.extra_jar(String(m)))
			"cocoa":
				out.append(base_tex.call("cocoa"))
			"double":
				out.append(base_tex.call("coffee"))   # вторая порция кофе: чашка кофе ещё раз
	return out


func _build() -> void:
	for ch in _root.get_children():
		ch.queue_free()
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.6)
	_root.add_child(dim)
	var h := 560.0
	var top := 40.0
	Ui.panel(Rect2(X, top, W, h), Ui.UI_WOOD, _root)
	Ui.label(tr("Рецепты"), Rect2(X, top + Ui.PAGE_PAD_TOP, W, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER)
	var cx := X + Ui.PAGE_PAD_X
	var cw := W - 2.0 * Ui.PAGE_PAD_X
	var y := top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + 4.0
	var from := _page * PER_PAGE
	for i in range(from, mini(from + PER_PAGE, drink_ids.size())):
		_row(drink_ids[i], cx, y, cw)
		y += ROW_H
	# подсказка про выпечку внизу и кнопки
	var by := top + h - Ui.PAGE_PAD_BOTTOM - Ui.BTN_H
	var note := Ui.label(tr("Начинки — и на выпечку: бросай на правую половину подноса."), Rect2(cx, by - 2.0 * Ui.LINE_H - 8.0, cw, 2.0 * Ui.LINE_H), 20, Ui.INK.lightened(0.2), _root, HORIZONTAL_ALIGNMENT_CENTER, true)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size = Vector2(cw, 2.0 * Ui.LINE_H)
	note.position.x = cx
	note.set_meta("max_h", 2.0 * Ui.LINE_H)
	if page_count() > 1:
		var third := (cw - 2.0 * Ui.BTN_GAP) / 3.0
		var prev := Ui.button("", Rect2(cx, by, third, Ui.BTN_H), "arrow_l", _root)
		prev.disabled = _page == 0
		prev.pressed.connect(_turn.bind(-1))
		Ui.button("", Rect2(cx + third + Ui.BTN_GAP, by, third, Ui.BTN_H), "close", _root).pressed.connect(close)
		var nxt := Ui.button("", Rect2(cx + 2.0 * (third + Ui.BTN_GAP), by, third, Ui.BTN_H), "arrow_r", _root)
		nxt.disabled = _page >= page_count() - 1
		nxt.pressed.connect(_turn.bind(1))
	else:
		Ui.button(tr("Закрыть"), Rect2(cx, by, cw, Ui.BTN_H), "close", _root).pressed.connect(close)


func _row(id: String, x: float, y: float, w: float) -> void:
	var strip := ColorRect.new()   # светлая плашка строки
	strip.position = Vector2(x, y)
	strip.size = Vector2(w, ROW_H - 4.0)
	strip.color = Color("f6e6c0")
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(strip)
	var cup := TextureRect.new()
	cup.texture = cell_tex.call(id)
	cup.stretch_mode = TextureRect.STRETCH_SCALE
	cup.size = Vector2(CHIP, CHIP)
	cup.position = Vector2(x + 4.0, y + (ROW_H - 4.0 - CHIP) / 2.0)
	cup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(cup)
	var name_w := 112.0
	var name := Ui.label(tr(String(Data.drinks[id]["name"])), Rect2(x + 4.0 + CHIP + 4.0, y, name_w, ROW_H - 4.0), 20, Ui.INK, _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.size = Vector2(name_w, ROW_H - 4.0)
	name.position = Vector2(x + 4.0 + CHIP + 4.0, y)
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.set_meta("max_h", ROW_H - 4.0)
	var chips := ingredient_textures(id)
	var cx := x + w - 4.0 - chips.size() * (CHIP - 2.0)   # состав прижат к правому краю плашки
	for t in chips:
		var tr_ := TextureRect.new()
		tr_.texture = t
		tr_.stretch_mode = TextureRect.STRETCH_SCALE
		tr_.size = Vector2(CHIP, CHIP)
		tr_.position = Vector2(cx, y + (ROW_H - 4.0 - CHIP) / 2.0)
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(tr_)
		cx += CHIP - 2.0


func _turn(d: int) -> void:
	_page = clampi(_page + d, 0, page_count() - 1)
	_build()


func close() -> void:
	closed.emit()
	queue_free()
