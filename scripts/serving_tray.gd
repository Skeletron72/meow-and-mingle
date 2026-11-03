class_name ServingTray
extends Node2D
## Поднос, на котором собирается и подаётся заказ: на нём чашка и (если заказана) выпечка.
## Рисуется кодом (пиксельный металлический поднос с ручками), сам узел тащится к коту целиком.
## Начало координат — центр подноса.

const RIM := Color("6f7686")
const RIM_L := Color("8c94a6")
const INNER := Color("b9c1cf")
const INNER_D := Color("a3acbc")
const DRINK_POS := Vector2(-40, -26)
const PASTRY_POS := Vector2(48, -22)

var lift := 0.0:            # приподнятость при перетаскивании: тень уезжает вниз
	set(v):
		lift = v
		queue_redraw()
var drink: Sprite2D
var pastry: Sprite2D
var _steam: CPUParticles2D
var _glow: Sprite2D


func _ready() -> void:
	drink = Sprite2D.new()
	drink.scale = Vector2(4, 4)
	drink.position = DRINK_POS
	drink.visible = false
	add_child(drink)
	pastry = Sprite2D.new()
	pastry.scale = Vector2(4, 4)
	pastry.position = PASTRY_POS
	pastry.visible = false
	add_child(pastry)
	_steam = Fx.steam(self, DRINK_POS + Vector2(0, -34))


func is_empty() -> bool:
	return not drink.visible and not pastry.visible


## Выставляет содержимое подноса (null — нет). Пар идёт только над напитком.
func set_contents(drink_tex: Texture2D, pastry_tex: Texture2D) -> void:
	drink.visible = drink_tex != null
	if drink_tex != null:
		drink.texture = drink_tex
	pastry.visible = pastry_tex != null
	if pastry_tex != null:
		pastry.texture = pastry_tex
	_steam.emitting = drink.visible


func pop_drink() -> void:
	Fx.pop(drink, 1.35, 0.5)


func pop_pastry() -> void:
	Fx.pop(pastry, 1.35, 0.5)


## Подсветка «заказ собран верно — подавай».
func set_ready(on: bool) -> void:
	if on and _glow == null:
		_glow = Fx.glow(self, Vector2(0, -16), Vector2(300, 120), Color("ffd27a"))
		var bob := create_tween().set_loops()   # содержимое подпрыгивает шагами по 2 px — пиксели остаются целыми
		bob.tween_method(_bob, 0.0, 1.0, 1.0)
		set_meta("ready_tween", bob)
	elif not on and _glow != null:
		_glow.queue_free()
		_glow = null
		if has_meta("ready_tween"):
			(get_meta("ready_tween") as Tween).kill()
			remove_meta("ready_tween")
		drink.position = DRINK_POS
		pastry.position = PASTRY_POS


func _bob(u: float) -> void:
	var dy := -2.0 * roundf(absf(sin(u * PI)) * 2.0)
	drink.position.y = DRINK_POS.y + dy
	pastry.position.y = PASTRY_POS.y + dy


func _draw() -> void:
	draw_rect(Rect2(-84, 18 + lift, 168, 8), Color(0, 0, 0, 0.25))   # тень
	draw_rect(Rect2(-96, -4, 12, 8), RIM)                            # ручки
	draw_rect(Rect2(84, -4, 12, 8), RIM)
	draw_rect(Rect2(-92, -2, 4, 2), RIM_L)
	draw_rect(Rect2(88, -2, 4, 2), RIM_L)
	var rows := [[-20, 4], [-16, 0], [-12, 0], [-8, 0], [-4, 0], [0, 0], [4, 0], [8, 0], [12, 0], [16, 4]]
	for r in rows:   # борт: скруглённые углы ступеньками
		draw_rect(Rect2(-84 + r[1], r[0], 168 - r[1] * 2, 4), RIM)
	for r in rows.slice(1, rows.size() - 1):   # дно
		var inset: int = 4 if (r[0] == -16 or r[0] == 12) else 0
		draw_rect(Rect2(-76 + inset, r[0], 152 - inset * 2, 4), INNER)
	draw_rect(Rect2(-72, -16, 144, 2), Color(1, 1, 1, 0.55))
	draw_rect(Rect2(-72, 12, 144, 2), INNER_D)
	draw_rect(Rect2(-80, -20, 160, 2), RIM_L)
