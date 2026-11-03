extends Node2D
## Главное меню: выбор режима. Интерфейс строится кодом, как и в остальных сценах.

const CAT_SHEET: Texture2D = preload("res://assets/cats/cat-waiter-front.png")
const BTN_X := 50.0
const BTN_W := 260.0
const BTN_H := 50.0

var _cat: Sprite2D
var _coins_label: Label
var _first_button: Button


func _ready() -> void:
	_build_background()
	_build_title()
	_build_buttons()
	_build_coins()
	GameState.coins_changed.connect(_on_coins_changed)
	_on_coins_changed(GameState.coins)


func _build_background() -> void:
	var wall := ColorRect.new()
	wall.size = Vector2(360, 400)
	wall.color = CafeRoom.WALL_COLOR
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wall)
	for x in range(12, 360, 48):
		var stripe := ColorRect.new()
		stripe.position = Vector2(x, 0)
		stripe.size = Vector2(24, 384)
		stripe.color = CafeRoom.WALL_STRIPE
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stripe)
	var base := ColorRect.new()
	base.position = Vector2(0, 384)
	base.size = Vector2(360, 16)
	base.color = CafeRoom.BASEBOARD
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	var floor_rect := ColorRect.new()
	floor_rect.position = Vector2(0, 400)
	floor_rect.size = Vector2(360, 240)
	floor_rect.color = CafeRoom.FLOOR_A
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_rect)


func _build_title() -> void:
	var tex := Ui.atlas(CAT_SHEET, Rect2(0, 16, 16, 16))
	_cat = Sprite2D.new()
	_cat.texture = tex
	_cat.position = Vector2(180, 150)
	_cat.scale = Vector2(8, 8)
	add_child(_cat)
	var t := create_tween().set_loops()
	t.tween_property(_cat, "position:y", 142.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_cat, "position:y", 150.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var title := Ui.label("Meow & Mingle", Rect2(0, 224, 360, 40), 30, Ui.CREAM, self)
	title.add_theme_color_override("font_outline_color", Ui.INK)
	title.add_theme_constant_override("outline_size", 8)
	Ui.label("кошачья кофейня", Rect2(0, 262, 360, 20), 14, Ui.INK, self)


func _build_buttons() -> void:
	_first_button = Ui.button("Играть", Rect2(BTN_X, 330, BTN_W, BTN_H), "play", self, 20)
	_first_button.pressed.connect(Nav.go.bind(self, Nav.BREW))
	var walk := Ui.button("Прогулка по кафе", Rect2(BTN_X, 394, BTN_W, BTN_H), "cat", self, 17)
	walk.pressed.connect(Nav.go.bind(self, Nav.WALK))
	var deco := Ui.button("Украшение", Rect2(BTN_X, 458, BTN_W, BTN_H), "brush", self, 17)
	deco.pressed.connect(Nav.go.bind(self, Nav.DECORATE))
	if OS.has_feature("pc"):
		var quit := Ui.button("Выход", Rect2(BTN_X + 40, 536, BTN_W - 80, 40), "exit", self, 14)
		quit.pressed.connect(get_tree().quit)
	_first_button.focus_mode = Control.FOCUS_ALL
	_first_button.grab_focus.call_deferred()


func _build_coins() -> void:
	Ui.panel(Rect2(10, 10, 88, 28), Ui.UI_CREAM, 5, self)
	var coin := Sprite2D.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(26, 24)
	coin.scale = Vector2(2, 2)
	add_child(coin)
	_coins_label = Ui.label("0", Rect2(40, 12, 54, 24), 16, Ui.INK, self, HORIZONTAL_ALIGNMENT_LEFT)


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)
