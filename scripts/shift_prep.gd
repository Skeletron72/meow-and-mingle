class_name ShiftPrep
extends CanvasLayer
## Перед сменой: название, три цели уровня (звёзды за смену, точность и скорость) и выбор бустеров из запаса. Показывается, только если бустеры есть,
## чтобы без них путь «тап по уровню → смена» оставался в один шаг. Выбранные бустеры списываются при старте (в городе), здесь только выбор.

signal start(picked: Array[String])
signal cancelled

const W := 336.0

var level: Dictionary = {}
var _picked: Array[String] = []
var _root: Control


func _init() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()


func _owned() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in Data.boosters:
		if Economy.booster_count(String(b["id"])) > 0:
			out.append(b)
	return out


func _build() -> void:
	for ch in _root.get_children():
		ch.queue_free()
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.55)
	_root.add_child(dim)
	var owned := _owned()
	var cw := W - 2.0 * Ui.PAGE_PAD_X
	var goals_h := Ui.LINE_H * 3.0
	var content_h := goals_h + 12.0 + Ui.LINE_H + 4.0 + owned.size() * (Ui.BTN_H + Ui.BTN_GAP) + Ui.BTN_H + Ui.BTN_GAP + Ui.BTN_H
	var h := Ui.page_height(content_h)
	var x := (360.0 - W) / 2.0
	var top := floorf((640.0 - h) / 2.0 / 2.0) * 2.0
	Ui.panel(Rect2(x, top, W, h), Ui.UI_WOOD, _root)
	Ui.label(tr(String(level.get("name", ""))), Rect2(x, top + Ui.PAGE_PAD_TOP, W, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER)
	var cx := x + Ui.PAGE_PAD_X
	var y := top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + Ui.PAGE_GAP
	var mask := GameState.level_mask(String(level.get("id", "")))
	var goals := [
		tr("Пройти смену"),
		tr("Точность не ниже %d%%") % int(round(float(level.get("accuracy", 0.8)) * 100.0)),
		tr("Среднее время до %.1f с") % float(level.get("speed", 10.0)),
	]
	for i in 3:
		var star := Sprite2D.new()
		star.texture = Fx.tex("bigstar")
		star.scale = Vector2(2, 2)
		star.position = Vector2(cx + 9.0, y + i * Ui.LINE_H + 14.0)
		star.modulate = Color("ffd640") if (mask >> i) & 1 == 1 else Color("3d2c1c")
		_root.add_child(star)
		Ui.label(goals[i], Rect2(cx + 26.0, y + i * Ui.LINE_H, cw - 26.0, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	y += goals_h + 12.0
	Ui.label(tr("Бустеры (на одну смену):"), Rect2(cx, y, cw, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK.lightened(0.2), _root, HORIZONTAL_ALIGNMENT_CENTER, true)
	y += Ui.LINE_H + 4.0
	for b in owned:
		var id := String(b["id"])
		var on := id in _picked
		var btn := Ui.button(("✓ " if on else "") + "%s ×%d" % [tr(String(b["name"])), Economy.booster_count(id)], Rect2(cx, y, cw, Ui.BTN_H), String(b["icon"]), _root, true)
		btn.modulate = Color(1.15, 1.1, 0.7) if on else Color.WHITE
		btn.pressed.connect(_toggle.bind(id))
		y += Ui.BTN_H + Ui.BTN_GAP
	Ui.button(tr("Начать смену"), Rect2(cx, y, cw, Ui.BTN_H), "play", _root).pressed.connect(func() -> void:
		start.emit(_picked.duplicate())
		queue_free())
	y += Ui.BTN_H + Ui.BTN_GAP
	Ui.button(tr("Назад"), Rect2(cx, y, cw, Ui.BTN_H), "undo", _root).pressed.connect(func() -> void:
		cancelled.emit()
		queue_free())


func _toggle(id: String) -> void:
	if id in _picked:
		_picked.erase(id)
	else:
		_picked.append(id)
	_build()
