class_name ServingTray
extends Node2D
## Поднос, на котором собирается и подаётся заказ: на нём чашка и (если заказана) выпечка.
## Рисуется кодом на сетке 4 px (овальный металлический поднос с обводкой и ручками), без масштаба и поворота;
## сам узел тащится к коту целиком.
## Начало координат — центр подноса.

const RIM := Color("6f7686")
const RIM_L := Color("8c94a6")
const INNER := Color("b9c1cf")
const INNER_D := Color("a3acbc")
const DRINK_POS := Vector2(-32, -20)
const PASTRY_POS := Vector2(36, -20)

var lift := 0.0:            # приподнятость при перетаскивании: тень уезжает вниз
	set(v):
		lift = v
		queue_redraw()
var drink: Sprite2D
var _drink_pos := DRINK_POS
var _pastry_pos := PASTRY_POS
var pastry: Sprite2D
var _steam: CPUParticles2D
var _glow: Sprite2D
var _badges: Array[Sprite2D] = []
var warmth := 0:   # 0 горячо (идёт пар), 1 остывает (пара нет), 2 остыл (чашка синеет)
	set(v):
		warmth = v
		if _steam != null:
			_steam.emitting = drink != null and drink.visible and warmth == 0
		if drink != null:
			drink.modulate = Color(0.74, 0.84, 1.0) if warmth == 2 else Color.WHITE


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
		_drink_pos = DRINK_POS - BrewArt.content_offset(drink_tex, true) * 4.0   # рисунок по центру своего места
		drink.position = _drink_pos
	pastry.visible = pastry_tex != null
	if pastry_tex != null:
		pastry.texture = pastry_tex
		_pastry_pos = PASTRY_POS - BrewArt.content_offset(pastry_tex) * 4.0
		pastry.position = _pastry_pos
	_steam.emitting = drink.visible and warmth == 0


## Значки добавок (лёд, корица, сливки, вторая порция) в ряд под чашкой.
func set_mods(mods: Array) -> void:
	for b in _badges:
		b.queue_free()
	_badges.clear()
	var n := mods.size()
	for i in n:
		var b := Sprite2D.new()
		b.texture = PixelArt.extra_icon("double" if String(mods[i]) == "double" else String(mods[i]))
		b.scale = Vector2(2, 2)
		b.position = Vector2(-32.0 + (float(i) - (n - 1) / 2.0) * 24.0, 14.0)
		add_child(b)
		_badges.append(b)


func pop_drink() -> void:
	Fx.hop(drink, 12.0, 0.35)


func pop_pastry() -> void:
	Fx.hop(pastry, 12.0, 0.35)


## Подсветка «заказ собран верно — подавай».
func set_ready(on: bool) -> void:
	if on and _glow == null:
		_glow = Fx.glow(self, Vector2(0, -16), Vector2(300, 120), Color("ffd27a"))
		var bob := create_tween().set_loops()   # содержимое подпрыгивает шагами по 4 px — пиксели остаются целыми
		bob.tween_method(_bob, 0.0, 1.0, 1.0)
		set_meta("ready_tween", bob)
	elif not on and _glow != null:
		_glow.queue_free()
		_glow = null
		if has_meta("ready_tween"):
			(get_meta("ready_tween") as Tween).kill()
			remove_meta("ready_tween")
		drink.position = _drink_pos
		pastry.position = _pastry_pos


func _bob(u: float) -> void:
	var dy := -4.0 * roundf(absf(sin(u * PI)))
	drink.position.y = _drink_pos.y + dy
	pastry.position.y = _pastry_pos.y + dy


func _draw() -> void:
	var g := BrewArt.G
	var rx := 76.0
	var ry := 28.0
	var up := snappedf(lift, g)
	BrewArt._ellipse_on(self, Vector2(0, 12 + up), rx + g, ry, Color(0, 0, 0, 0.25))   # тень (при подъёме уезжает вниз)
	for sx in [-1.0, 1.0]:   # ручки по краям
		draw_rect(Rect2(sx * (rx + 4) - 8, -8, 16, 16), BrewArt.OUTLINE)
		draw_rect(Rect2(sx * (rx + 4) - 4, -4, 8, 8), RIM)
	BrewArt._ellipse_on(self, Vector2.ZERO, rx + g, ry + g, BrewArt.OUTLINE)
	BrewArt._ellipse_on(self, Vector2.ZERO, rx, ry, RIM)
	BrewArt._ellipse_on(self, Vector2(0, g), rx - 2 * g, ry - 2 * g, RIM_L)    # светлый нижний край борта
	BrewArt._ellipse_on(self, Vector2(0, -g), rx - 2 * g, ry - 2 * g, INNER_D)
	BrewArt._ellipse_on(self, Vector2(0, g / 2.0 * 2.0), rx - 3 * g, ry - 3 * g, INNER)
	draw_rect(Rect2(-48, -20, 20, 4), Color(1, 1, 1, 0.6))   # блик
	draw_rect(Rect2(-24, -20, 8, 4), Color(1, 1, 1, 0.6))
