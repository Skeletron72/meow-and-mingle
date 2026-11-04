class_name RepairBoard
extends CanvasLayer
## «Ремонт кафе»: доска задач. Показывает задачи, которые уже можно делать (сначала доступные, потом закрытые с причиной),
## тратит звёзды (GameState.do_repair) и для задач с выбором спрашивает вариант (цвет стен, пола, плинтуса).
## Страницы по 4 карточки, как в выборе смены; карточка — кнопка с названием, ценой в звёздах и подписью «что даст».

signal closed

const PER_PAGE := 4
const CARD_H := 84.0
const CARD_GAP := 4.0
const X := 12.0
const W := 336.0

var _page := 0
var _choosing := ""        # id задачи, для которой выбираем вариант
var _root: Control


func _init() -> void:
	layer = 7


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()


## Строки доски: сначала открытые задачи, затем закрытые (по порядку списка), выполненные не показываем.
func rows() -> Array[Dictionary]:
	var open: Array[Dictionary] = []
	var locked: Array[Dictionary] = []
	for r in Data.repairs:
		match GameState.repair_state(String(r["id"])):
			"open":
				open.append(r)
			"locked":
				locked.append(r)
	return open + locked


func page_count() -> int:
	return maxi(1, int(ceil(float(rows().size()) / float(PER_PAGE))))


func _build() -> void:
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
	var cx := X + Ui.PAGE_PAD_X
	var cw := W - 2.0 * Ui.PAGE_PAD_X
	var title := tr("Выбери вариант") if _choosing != "" else tr("Ремонт кафе")
	Ui.label(title, Rect2(X, top + Ui.PAGE_PAD_TOP, W - 80.0, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER)
	var stars := Ui.label("★%d" % GameState.stars_free(), Rect2(X + W - 90.0, top + Ui.PAGE_PAD_TOP, 66.0, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Color("c2891a"), _root, HORIZONTAL_ALIGNMENT_RIGHT)
	stars.add_theme_color_override("font_outline_color", Ui.CREAM)
	stars.add_theme_constant_override("outline_size", Ui.PX)
	var y := top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + Ui.PAGE_GAP
	var by := top + h - Ui.PAGE_PAD_BOTTOM - Ui.BTN_H
	if _choosing != "":
		_build_choice(cx, y, cw, by)
		return
	var all := rows()
	_page = clampi(_page, 0, page_count() - 1)
	var first := _page * PER_PAGE
	if all.is_empty():
		Ui.label(tr("Всё отремонтировано!"), Rect2(cx, y + 60.0, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER, true)
	for i in range(first, mini(all.size(), first + PER_PAGE)):
		_card(all[i], cx, y, cw)
		y += CARD_H + CARD_GAP
	if page_count() > 1:
		var half := (cw - Ui.BTN_GAP) / 2.0
		Ui.button(tr("Назад"), Rect2(cx, by, half, Ui.BTN_H), "undo", _root).pressed.connect(_close)
		Ui.button(tr("Дальше") if _page < page_count() - 1 else tr("Раньше"), Rect2(cx + half + Ui.BTN_GAP, by, half, Ui.BTN_H), "", _root).pressed.connect(_turn)
	else:
		Ui.button(tr("Назад"), Rect2(cx, by, cw, Ui.BTN_H), "undo", _root).pressed.connect(_close)


func _card(r: Dictionary, cx: float, y: float, cw: float) -> void:
	var id := String(r["id"])
	var open := GameState.repair_state(id) == "open"
	var cost := int(r["cost"])
	var can := open and GameState.stars_free() >= cost
	var b := Ui.button("", Rect2(cx, y, cw, CARD_H), "", _root)
	b.disabled = not can
	b.modulate = Color.WHITE if can else Color(0.62, 0.62, 0.62)
	b.pressed.connect(_pick.bind(id))
	var tw := cw - 12.0 - 12.0 - 52.0
	Ui.label(tr(String(r["name"])), Rect2(cx + 12.0, y + 12.0, tw, Ui.LINE_H), Ui.FONT_SIZE, Ui.CREAM, _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	var sub := tr(String(r["blurb"])) if open else _lock_reason(r)
	Ui.label(sub, Rect2(cx + 12.0, y + 12.0 + Ui.LINE_H, tw + 20.0, Ui.LINE_H), Ui.FONT_SIZE, Ui.CREAM.darkened(0.15), _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	var price := Ui.label("★%d" % cost, Rect2(cx + cw - 12.0 - 48.0, y + 12.0, 48.0, Ui.LINE_H), Ui.FONT_SIZE, Color("ffd640") if can or not open else Color("c9b27a"), _root, HORIZONTAL_ALIGNMENT_RIGHT)
	price.add_theme_color_override("font_outline_color", Ui.INK)
	price.add_theme_constant_override("outline_size", Ui.PX)


## Почему задача закрыта: чего не хватает.
func _lock_reason(r: Dictionary) -> String:
	for req in r.get("requires", []):
		if not GameState.has_repair(String(req)):
			var d := GameState.repair_def(String(req))
			return tr("Сначала: %s") % tr(String(d.get("name", req)))
	return tr("Пройди смену %d") % int(r.get("after", 0))


func _pick(id: String) -> void:
	var def := GameState.repair_def(id)
	if not (def.get("variants", []) as Array).is_empty():
		_choosing = id
		_build()
		return
	_do(id, "")


func _build_choice(cx: float, y: float, cw: float, by: float) -> void:
	var def := GameState.repair_def(_choosing)
	Ui.label(tr(String(def["name"])), Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER, true)
	y += Ui.LINE_H + Ui.BTN_GAP
	for v in def["variants"]:
		var key := String(def["effects"][0]["key"])
		var b := Ui.button(tr(String(v["name"])), Rect2(cx + 40.0, y, cw - 40.0, Ui.BTN_H), "", _root)
		b.pressed.connect(_do.bind(_choosing, String(v["id"])))
		# образец цвета слева от кнопки
		var table: Dictionary = Data.styles.get(key, {})
		var sample: Dictionary = table.get(String(v["id"]), {})
		var col := Color(String(sample.get("wall", sample.get("a", sample.get("base", "cdb892")))))
		var chip := ColorRect.new()
		chip.position = Vector2(cx, y + 4.0)
		chip.size = Vector2(32.0, Ui.BTN_H - Ui.SHADOW_BUTTON - 4.0)
		chip.color = col
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(chip)
		y += Ui.BTN_H + Ui.BTN_GAP
	Ui.button(tr("Назад"), Rect2(cx, by, cw, Ui.BTN_H), "undo", _root).pressed.connect(func() -> void:
		_choosing = ""
		_build())


func _do(id: String, variant: String) -> void:
	_choosing = ""
	if GameState.do_repair(id, variant):
		Audio.sfx("star", 0.0)
		Fx.burst(_root, Vector2(180, 300), "star", Color("ffe08a"), 14, 260.0, 200.0, 1.0, 1.2)
		Fx.confetti(_root, Vector2(180, 260), 18)
	_build()


func _turn() -> void:
	_page = (_page + 1) % page_count()
	_build()


func _close() -> void:
	closed.emit()
	queue_free()
