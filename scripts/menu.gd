extends Node2D
## Главное меню: выбор режима. Интерфейс строится кодом, как и в остальных сценах.
## Фон разлинован по той же сетке 16×16 (клетка 32 px), что и кафе.

const CAT_SHEET: Texture2D = preload("res://assets/cats/cat-waiter-front.png")
const FLOOR_Y := 384
const BTN_X := 30.0
const BTN_W := 300.0
const BTN_H := 56.0

var _cat: Sprite2D
var _coins_label: Label
var _first_button: Button


func _ready() -> void:
	_build_title()
	_build_buttons()
	_build_coins()
	GameState.coins_changed.connect(_on_coins_changed)
	_on_coins_changed(GameState.coins)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 360, FLOOR_Y), CafeRoom.WALL_COLOR)
	for x in range(20, 360, 64):
		draw_rect(Rect2(x, 0, 32, FLOOR_Y - 16), CafeRoom.WALL_STRIPE)
	draw_rect(Rect2(0, FLOOR_Y - 16, 360, 16), CafeRoom.BASEBOARD)
	draw_rect(Rect2(0, FLOOR_Y - 4, 360, 4), CafeRoom.BASEBOARD.darkened(0.35))
	for r in range((640 - FLOOR_Y) / CafeRoom.T):
		for c in range(-1, 11):
			draw_rect(Rect2(20 + c * CafeRoom.T, FLOOR_Y + r * CafeRoom.T, CafeRoom.T, CafeRoom.T), CafeRoom.FLOOR_A if (r + c) % 2 == 0 else CafeRoom.FLOOR_B)


func _build_title() -> void:
	_cat = Sprite2D.new()
	_cat.texture = Ui.atlas(CAT_SHEET, Rect2(0, 16, 16, 16))
	_cat.position = Vector2(180, 144)
	_cat.scale = Vector2(8, 8)
	add_child(_cat)
	var t := create_tween().set_loops()
	t.tween_property(_cat, "position:y", 136.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_cat, "position:y", 144.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var title := Ui.label("Meow & Mingle", Rect2(0, 208, 360, 56), Ui.FONT_SIZE_BIG, Ui.CREAM, self, HORIZONTAL_ALIGNMENT_CENTER, true)
	title.add_theme_color_override("font_outline_color", Ui.INK)
	title.add_theme_constant_override("outline_size", Ui.PX * 3)
	Ui.label("кошачья кофейня", Rect2(0, 268, 360, 32), Ui.FONT_SIZE, Ui.INK, self)


func _build_buttons() -> void:
	_first_button = Ui.button("Играть", Rect2(BTN_X, 328, BTN_W, BTN_H), "play", self)
	_first_button.pressed.connect(Nav.go.bind(self, Nav.BREW))
	var walk := Ui.button("Прогулка по кафе", Rect2(BTN_X, 400, BTN_W, BTN_H), "cat", self)
	walk.pressed.connect(Nav.go.bind(self, Nav.WALK))
	var deco := Ui.button("Украшение", Rect2(BTN_X, 472, BTN_W, BTN_H), "brush", self)
	deco.pressed.connect(Nav.go.bind(self, Nav.DECORATE))
	if OS.has_feature("pc"):
		var quit := Ui.button("Выход", Rect2(BTN_X + 60, 556, BTN_W - 120, 48), "exit", self)
		quit.pressed.connect(get_tree().quit)
	_first_button.focus_mode = Control.FOCUS_ALL
	_first_button.grab_focus.call_deferred()


func _build_coins() -> void:
	Ui.panel(Rect2(8, 8, 104, 40), Ui.UI_CREAM, self)
	var coin := Sprite2D.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(28, 28)
	coin.scale = Vector2(2, 2)
	add_child(coin)
	_coins_label = Ui.label("0", Rect2(44, 10, 64, 36), Ui.FONT_SIZE, Ui.INK, self, HORIZONTAL_ALIGNMENT_LEFT)


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)
