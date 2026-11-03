extends Node2D
## Режим «прогулка по кафе»: кот-официант ходит по залу (тап/удержание по полу, стрелки или WASD).
## У стойки появляется кнопка «Готовить» — переход в кофейню. По залу гуляют посетители.

const WAITER_DEF := {"sprite": "cat-waiter-front.png", "tint": "#ffffff"}
const PANEL_Y := 560.0

var _room: CafeRoom
var _player: CatWalker
var _ambient: Array[CatWalker] = []
var _ui: CanvasLayer
var _brew_btn: Button
var _hint: Label
var _coins_label: Label
var _pressing := false
var _auto_enter := false
var _last_cell := Vector2i(-1, -1)
var _marker: Sprite2D


func _ready() -> void:
	_room = CafeRoom.new()
	add_child(_room)
	_room.set_layout(GameState.layout)
	_spawn_cats()
	_build_marker()
	_build_ui()


func _spawn_cats() -> void:
	_player = CatWalker.new()
	_player.position = CafeRoom.SPAWN_POS
	_room.actors.add_child(_player)
	_player.setup(_room, WAITER_DEF)
	_player.arrived.connect(_on_player_arrived)
	for def in Data.cats:
		var c := CatWalker.new()
		c.wander = true
		c.position = _room.random_free_point()
		_room.actors.add_child(c)
		c.setup(_room, def)
		_ambient.append(c)


## Чашка кофе над стойкой: подсказка, что здесь можно работать.
func _build_marker() -> void:
	_marker = Sprite2D.new()
	_marker.texture = Ui.atlas(preload("res://AssetPack_V01_FREE.png"), Rect2(32, 16, 16, 16))
	_marker.position = Vector2(44, 108)
	_marker.scale = Vector2(3, 3)
	_marker.z_index = 5
	add_child(_marker)
	var t := create_tween().set_loops()
	t.tween_property(_marker, "position:y", 100.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_marker, "position:y", 108.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	Ui.panel(Rect2(0, PANEL_Y, 360, 80), Ui.UI_WOOD, 7, _ui)
	var menu := Ui.button("", Rect2(12, PANEL_Y + 14, 52, 52), "home", _ui)
	menu.pressed.connect(Nav.go.bind(self, Nav.MENU))
	var deco := Ui.button("", Rect2(296, PANEL_Y + 14, 52, 52), "brush", _ui)
	deco.pressed.connect(Nav.go.bind(self, Nav.DECORATE))
	_brew_btn = Ui.button("Готовить", Rect2(80, PANEL_Y + 14, 200, 52), "play", _ui, 18)
	_brew_btn.pressed.connect(_enter_counter)
	_hint = Ui.label("Нажми на пол — кот пойдёт.\nСтойка — готовить заказы", Rect2(72, PANEL_Y + 14, 216, 52), 12, Ui.CREAM, _ui)
	_hint.add_theme_color_override("font_outline_color", Ui.INK)
	_hint.add_theme_constant_override("outline_size", 4)
	Ui.panel(Rect2(8, 8, 88, 28), Ui.UI_CREAM, 5, _ui)
	var coin := Sprite2D.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(24, 22)
	coin.scale = Vector2(2, 2)
	_ui.add_child(coin)
	_coins_label = Ui.label(str(GameState.coins), Rect2(38, 10, 54, 24), 16, Ui.INK, _ui, HORIZONTAL_ALIGNMENT_LEFT)
	GameState.coins_changed.connect(_on_coins_changed)  # метод, а не лямбда: отпишется вместе со сценой
	_update_interact()


# ---------------------------------------------------------------- управление

func _process(delta: float) -> void:
	var dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) \
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) \
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if dir != Vector2.ZERO:
		_auto_enter = false
		_player.nudge(dir, delta)
	_update_interact()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press((make_input_local(event) as InputEventMouse).position)
		else:
			_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		var p := (make_input_local(event) as InputEventMouse).position
		var cell := Vector2i(int(p.x / CafeRoom.CELL), int(p.y / CafeRoom.CELL))
		if cell != _last_cell:
			_last_cell = cell
			_player.walk_to(p)


func _on_press(p: Vector2) -> void:
	if p.y >= PANEL_Y:
		return
	for c in _ambient:
		if Rect2(c.position + Vector2(-26, -50), Vector2(52, 56)).has_point(p):
			_talk(c)
			return
	if _room.counter_hit(p):
		_auto_enter = true
		var spot := Vector2(clampf(p.x, CafeRoom.COUNTER_ZONE.position.x + 20.0, CafeRoom.COUNTER_ZONE.end.x - 20.0), CafeRoom.COUNTER_ZONE.get_center().y)
		if CafeRoom.COUNTER_ZONE.has_point(_player.position):
			_enter_counter()
		else:
			_player.walk_to(spot)
		return
	_auto_enter = false
	_pressing = true
	_last_cell = Vector2i(int(p.x / CafeRoom.CELL), int(p.y / CafeRoom.CELL))
	_player.walk_to(p)


func _talk(cat: CatWalker) -> void:
	cat.hop()
	var fav: Dictionary = Data.drinks.get(String(cat.def.get("fav_drink", "")), {})
	var text := String(cat.def.get("name", "Кот"))
	if not fav.is_empty():
		text += ": обожаю " + String(fav["name"]).to_lower()
	Ui.toast(_ui, text, cat.position + Vector2(0, -80))


func _on_player_arrived() -> void:
	if _auto_enter and _room.in_counter_zone(_player.position):
		_enter_counter()


func _update_interact() -> void:
	var near := _room.in_counter_zone(_player.position)
	_brew_btn.visible = near
	_hint.visible = not near


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)


func _enter_counter() -> void:
	set_process(false)
	Nav.go(self, Nav.BREW)
