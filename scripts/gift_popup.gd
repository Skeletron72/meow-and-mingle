class_name GiftPopup
extends CanvasLayer
## «Подарок дня»: лента из 7 дней (пропуск дня сбрасывает стрик), награда ближайшего дня, кнопки «Забрать» и «×2 за рекламу».
## Монеты и рыбки удваиваются рекламой; бустеры и мебель — нет. Закрывается после получения.

signal finished

const W := 336.0
const CELL_W := 38.0
const CELL_GAP := 3.0
const CELL_H := 64.0

var _root: Control
var _toast_parent: Node


func _init() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()


func _build() -> void:
	for ch in _root.get_children():
		ch.queue_free()
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.6)
	_root.add_child(dim)
	var day := Daily.gift_day()
	var ready := Daily.gift_ready()
	var cw := W - 2.0 * Ui.PAGE_PAD_X
	var content_h := CELL_H + 8.0 + Ui.LINE_H * 2.0 + Ui.BTN_GAP + Ui.column_h(2)
	var h := Ui.page_height(content_h)
	var x := (360.0 - W) / 2.0
	var top := floorf((640.0 - h) / 2.0 / 2.0) * 2.0
	Ui.panel(Rect2(x, top, W, h), Ui.UI_WOOD, _root)
	Ui.label(tr("Подарок дня"), Rect2(x, top + Ui.PAGE_PAD_TOP, W, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER)
	var cx := x + Ui.PAGE_PAD_X
	var y := top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + Ui.PAGE_GAP
	var gifts: Array = Data.daily_gifts
	for i in gifts.size():
		_cell(i + 1, gifts[i], Vector2(cx + i * (CELL_W + CELL_GAP), y), day, ready)
	y += CELL_H + 8.0
	var reward := Economy.describe(gifts[day - 1])
	var text := tr("День %d: %s") % [day, reward] if ready else tr("Сегодня подарок уже получен. Приходи завтра!")
	var l := Ui.label(text, Rect2(cx, y, cw, Ui.LINE_H * 2.0), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.position = Vector2(cx, y)
	l.size = Vector2(cw, Ui.LINE_H * 2.0)
	y += Ui.LINE_H * 2.0 + Ui.BTN_GAP
	if ready:
		Ui.button(tr("Забрать"), Rect2(cx, y, cw, Ui.BTN_H), "check", _root).pressed.connect(_claim.bind(false))
		var ad := Ui.button(tr("×2 за рекламу"), Rect2(cx, y + Ui.BTN_H + Ui.BTN_GAP, cw, Ui.BTN_H), "play", _root)
		ad.disabled = not (Shop.ad_ready("gift_double") and _doubles(gifts[day - 1]))
		ad.modulate = Color.WHITE if not ad.disabled else Color(0.62, 0.62, 0.62)
		ad.pressed.connect(_claim.bind(true))
	else:
		Ui.button(tr("Назад"), Rect2(cx, y, cw, Ui.BTN_H), "undo", _root).pressed.connect(_close)


func _doubles(reward: Dictionary) -> bool:
	return reward.has("coins") or reward.has("fish")


func _cell(n: int, reward: Dictionary, pos: Vector2, day: int, ready: bool) -> void:
	var claimed := (n < day) if ready else (n <= Daily.gift_streak())
	var current := ready and n == day
	var bg := Ui.panel(Rect2(pos, Vector2(CELL_W, CELL_H)), Ui.UI_CREAM, _root)
	if current:
		bg.self_modulate = Color(1.15, 1.05, 0.6)
	elif claimed:
		bg.self_modulate = Color(0.75, 0.9, 0.75)
	Ui.label(str(n), Rect2(pos.x, pos.y + 2.0, CELL_W, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER, true)
	var icon := Sprite2D.new()
	if reward.has("furniture") or (reward.has("fish") and reward.has("coins")):
		icon.texture = Ui.icon("flower")   # главный подарок недели
	elif reward.has("fish"):
		icon.texture = PixelArt.fish()
	elif reward.has("boosters"):
		icon.texture = Ui.icon("hand")
	else:
		icon.texture = Ui.icon("coin")
	icon.scale = Vector2(2, 2)
	icon.position = Vector2(pos.x + CELL_W / 2.0, pos.y + 44.0)
	icon.modulate = Color(1, 1, 1, 0.45) if claimed else Color.WHITE
	_root.add_child(icon)
	if claimed:
		Ui.label("✓", Rect2(pos.x, pos.y + 32.0, CELL_W, Ui.LINE_H), Ui.FONT_SIZE, Color("3c8c4a"), _root, HORIZONTAL_ALIGNMENT_CENTER, true)


func _claim(double: bool) -> void:
	if double:
		Shop.show_ad("gift_double", func(ok: bool) -> void:
			if ok:
				_done(Daily.claim_gift(true)))
	else:
		_done(Daily.claim_gift(false))


func _done(text: String) -> void:
	Audio.sfx("star", 0.0)
	Fx.confetti(_root, Vector2(180, 300), 30)
	if text != "":
		Ui.toast(_root, text, Vector2(180, 560))
	_build()
	get_tree().create_timer(1.1).timeout.connect(_close)


func _close() -> void:
	finished.emit()
	queue_free()
