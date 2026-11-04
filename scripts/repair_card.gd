class_name RepairCard
extends Control
## Карточка «Ремонт кафе»: сколько звёзд есть и какая задача ремонта следующая. Игрок тратит звёзды одним тапом.
## Пока задач две (ставни, расчистка), дальше список растёт в data/repairs.json (этап «Ремонт и контент»).

signal chosen(id: String)

const W := 300.0

var _task := ""


## Строит карточку внизу экрана для ближайшей задачи, которую можно оплатить сейчас.
func setup(task_id: String) -> void:
	_task = task_id
	var def := GameState.repair_def(task_id)
	var cost := int(def.get("cost", 1))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := Ui.page_height(Ui.PAGE_TITLE_H + Ui.PAGE_GAP + 28.0 + Ui.BTN_GAP + Ui.BTN_H)
	var x := (360.0 - W) / 2.0
	var top := 640.0 - h - 24.0
	Ui.panel(Rect2(x, top, W, h), Ui.UI_WOOD, self)
	Ui.label(tr("Ремонт кафе"), Rect2(x, top + Ui.PAGE_PAD_TOP, W, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, self, HORIZONTAL_ALIGNMENT_CENTER)
	var y := top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + Ui.PAGE_GAP
	var cw := W - 2.0 * Ui.PAGE_PAD_X
	# ряд звёзд: свободные — золотые, остальные — тёмные
	var have := GameState.stars_free()
	var shown := maxi(have, cost)
	var sx := x + W / 2.0 - shown * 12.0 + 12.0
	for i in shown:
		var star := Sprite2D.new()
		star.texture = Fx.tex("bigstar")
		star.scale = Vector2(2, 2)
		star.position = Vector2(sx + i * 24.0, y + 14.0)
		star.modulate = Color("ffd640") if i < have else Color("5a4636")
		add_child(star)
	y += 28.0 + Ui.BTN_GAP
	var label := "%s  ★%d" % [tr(String(def.get("name", task_id))), cost]
	var b := Ui.button(label, Rect2(x + Ui.PAGE_PAD_X, y, cw, Ui.BTN_H), String(def.get("icon", "")), self, true)
	b.disabled = have < cost
	b.pressed.connect(func() -> void: chosen.emit(_task))
	# рука-указатель: подпрыгивает по сетке 4 px над правым краем кнопки (повторяется, пока карточка открыта)
	var hand := Sprite2D.new()
	hand.texture = Ui.icon("hand")
	hand.scale = Vector2(2, 2)
	hand.position = Vector2(x + W - Ui.PAGE_PAD_X - 18.0, y + Ui.BTN_H + 8.0)
	hand.rotation = 0.0
	add_child(hand)
	var loop := hand.create_tween().set_loops()
	loop.tween_callback(func() -> void: Fx.hop(hand, 8.0, 0.4, 4.0))
	loop.tween_interval(0.9)
