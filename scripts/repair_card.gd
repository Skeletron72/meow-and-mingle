class_name RepairCard
extends Control
## Карточка «Ремонт кафе» во вступлении: сколько звёзд есть и какая задача ремонта следующая. Игрок тратит звёзды одним тапом по кнопке.
## Пока задач две (ставни, расчистка), дальше список растёт в data/repairs.json (доска ремонта — RepairBoard).

signal chosen(id: String)

const W := 336.0

var _task := ""


## Строит карточку внизу экрана для ближайшей задачи, которую можно оплатить сейчас.
func setup(task_id: String) -> void:
	_task = task_id
	var def := GameState.repair_def(task_id)
	var cost := int(def.get("cost", 1))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := 20.0 + 28.0 + 8.0 + 32.0 + 8.0 + Card.H + 30.0
	var x := (360.0 - W) / 2.0
	var top := 640.0 - h - 16.0
	Ui.panel(Rect2(x, top, W, h), Ui.UI_WOOD, self)
	Ui.label(tr("Ремонт кафе"), Rect2(x, top + 20.0, W, 28.0), Ui.FONT_SIZE, Ui.INK, self, HORIZONTAL_ALIGNMENT_CENTER)
	# звёзды: свободные — золотые, остальные — серые
	var have := GameState.stars_free()
	var shown := maxi(have, cost)
	var sx := Ui.snap(180.0 - shown * 18.0)
	for i in shown:
		var star := TextureRect.new()
		star.texture = Ui.icon("star" if i < have else "star_off")
		star.stretch_mode = TextureRect.STRETCH_SCALE
		star.size = Vector2(32, 32)
		star.position = Vector2(sx + i * 36.0, top + 20.0 + 28.0 + 8.0)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(star)
	var card := Card.make(self, Rect2(x + 14.0, top + 20.0 + 28.0 + 8.0 + 32.0 + 8.0, W - 28.0, Card.H), {
		"title": String(def.get("name", task_id)), "sub": String(def.get("blurb", "")), "icon": String(def.get("icon", "home")),
		"action": {"text": str(cost), "icon": "star", "enabled": have >= cost, "press": func() -> void: chosen.emit(_task)}})
	# рука-указатель: подпрыгивает по сетке 4 px рядом с кнопкой
	var hand := Sprite2D.new()
	hand.texture = Ui.icon("hand")
	hand.scale = Vector2(2, 2)
	hand.position = Vector2(x + W - 36.0, card.position.y + Card.H - 4.0)
	add_child(hand)
	var loop := hand.create_tween().set_loops()
	loop.tween_callback(func() -> void: Fx.hop(hand, 8.0, 0.4, 4.0))
	loop.tween_interval(0.9)
