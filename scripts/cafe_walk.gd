extends Node2D
## Режим «прогулка по кафе»: кот-официант ходит по залу (тап/удержание по полу, стрелки или WASD).
## У стойки появляется кнопка «Готовить» — переход в кофейню. По залу гуляют посетители.

const WAITER_DEF := {"sprite": "cat-waiter-front.png", "tint": "#ffffff"}
const PANEL_Y := 544.0

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
	_player.position = CafeRoom.feet_at(CafeRoom.SPAWN_CELL)
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
	_marker.texture = Ui.atlas(preload("res://assets/cafe/drinks-and-pastries.png"), Rect2(32, 16, 16, 16))
	_marker.position = Vector2(68, 124)
	_marker.scale = Vector2(2, 2)
	_marker.z_index = 5
	add_child(_marker)
	var t := create_tween().set_loops()
	t.tween_property(_marker, "position:y", 116.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_marker, "position:y", 124.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	Ui.panel(Rect2(0, PANEL_Y, 360, 96), Ui.UI_WOOD, _ui)
	var menu := Ui.button("", Rect2(12, PANEL_Y + 16, 64, 56), "home", _ui)
	menu.pressed.connect(Nav.go.bind(self, Nav.MENU))
	var deco := Ui.button("", Rect2(284, PANEL_Y + 16, 64, 56), "brush", _ui)
	deco.pressed.connect(Nav.go.bind(self, Nav.DECORATE))
	_brew_btn = Ui.button("Готовить", Rect2(88, PANEL_Y + 16, 184, 56), "play", _ui)
	_brew_btn.pressed.connect(_enter_counter)
	_hint = Ui.label("Нажми на пол —\nкот пойдёт", Rect2(80, PANEL_Y + 12, 200, 64), Ui.FONT_SIZE, Ui.CREAM, _ui, HORIZONTAL_ALIGNMENT_CENTER, true)
	_hint.add_theme_color_override("font_outline_color", Ui.INK)
	_hint.add_theme_constant_override("outline_size", Ui.PX)
	Ui.panel(Rect2(8, 8, 104, 40), Ui.UI_CREAM, _ui)
	var coin := Sprite2D.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(28, 28)
	coin.scale = Vector2(2, 2)
	_ui.add_child(coin)
	_coins_label = Ui.label(str(GameState.coins), Rect2(44, 10, 64, 36), Ui.FONT_SIZE, Ui.INK, _ui, HORIZONTAL_ALIGNMENT_LEFT)
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
		var cell := CafeRoom.cell_at(p)
		if cell != _last_cell:
			_last_cell = cell
			_player.walk_to(p)


func _on_press(p: Vector2) -> void:
	if p.y >= PANEL_Y:
		return
	for c in _ambient:
		if Rect2(c.position + Vector2(-16, -34), Vector2(32, 40)).has_point(p):
			_talk(c)
			return
	if _room.counter_hit(p):
		_auto_enter = true
		if _room.in_counter_zone(_player.position):
			_enter_counter()
		else:
			var col := clampi(CafeRoom.cell_at(p).x, 0, CafeRoom.COUNTER_CELLS.size.x - 1)
			_player.walk_to(CafeRoom.feet_at(Vector2i(col, 0)))
		return
	_auto_enter = false
	_pressing = true
	_last_cell = CafeRoom.cell_at(p)
	_player.walk_to(p)


func _talk(cat: CatWalker) -> void:
	cat.hop()
	var fav: Dictionary = Data.drinks.get(String(cat.def.get("fav_drink", "")), {})
	var text := String(cat.def.get("name", "Кот"))
	if not fav.is_empty():
		text += ": обожаю " + String(fav["name"]).to_lower()
	Ui.toast(_ui, text, cat.position + Vector2(0, -72))


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)


func _on_player_arrived() -> void:
	if _auto_enter and _room.in_counter_zone(_player.position):
		_enter_counter()


func _update_interact() -> void:
	var near := _room.in_counter_zone(_player.position)
	_brew_btn.visible = near
	_hint.visible = not near


func _enter_counter() -> void:
	set_process(false)
	Nav.go(self, Nav.BREW)
