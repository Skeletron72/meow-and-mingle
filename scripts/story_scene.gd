class_name StoryScene
extends CanvasLayer
## Сюжетная сцена: затемнение, портрет говорящего, имя и реплика в рамке. Тап — следующая реплика, «Пропустить» — закрыть.
## Данные — data/story.json; кто говорит: "meow" (Мяу) или id кота из data/cats.json. Показывается один раз (GameState.story_seen).

signal finished

const BASE_Y := 392.0

var scene: Dictionary = {}
var _index := -1
var _root: Control
var _label: Label
var _name: Label
var _face: Sprite2D
var _busy := false


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.size = Vector2(360, 640)
	add_child(_root)
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0.06, 0.04, 0.09, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.72, 0.4)
	var title := Ui.label(tr(String(scene["title"])), Rect2(0, 120, 360, 36), Ui.FONT_SIZE, Color("ffd9a0"), _root, HORIZONTAL_ALIGNMENT_CENTER, true)
	title.add_theme_color_override("font_outline_color", Color("5b3a22"))
	title.add_theme_constant_override("outline_size", Ui.PX * 2)
	_face = Sprite2D.new()
	_face.scale = Vector2(8, 8)
	_face.position = Vector2(180, 276)
	_root.add_child(_face)
	var h := 152.0
	Ui.panel(Rect2(12, BASE_Y, 336, h), Ui.UI_WOOD, _root)
	_name = Ui.label("", Rect2(12 + Ui.PAGE_PAD_X, BASE_Y + 12.0, 336 - 2 * Ui.PAGE_PAD_X, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK.lightened(0.1), _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	_label = Ui.label("", Rect2(12 + Ui.PAGE_PAD_X, BASE_Y + 12.0 + Ui.LINE_H + 4.0, 336 - 2 * Ui.PAGE_PAD_X, Ui.LINE_H * 3.0), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.position.y = BASE_Y + 12.0 + Ui.LINE_H + 4.0
	_label.size = Vector2(336 - 2 * Ui.PAGE_PAD_X, Ui.LINE_H * 3.0)
	var skip := Ui.button(tr("Пропустить"), Rect2(222, 584, 126, 48), "", _root, true)
	skip.pressed.connect(_finish)
	var hint := Ui.label(tr("Нажми — дальше"), Rect2(12, 596, 206, 32), Ui.FONT_SIZE, Color("b8a58c"), _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	var blink := hint.create_tween().set_loops()
	blink.tween_property(hint, "modulate:a", 0.3, 0.7).set_trans(Tween.TRANS_SINE)
	blink.tween_property(hint, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	_root.gui_input.connect(_on_input)
	_next()


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_next()


## Кто говорит: имя, текстура лица и цвет.
static func speaker(who: String) -> Dictionary:
	if who == "meow":
		return {"name": "Мяу", "sprite": "cat-waiter-front.png", "tint": "#ffffff"}
	for c in Data.cats:
		if String(c["id"]) == who:
			return {"name": String(c["name"]), "sprite": String(c["sprite"]), "tint": String(c.get("tint", "#ffffff"))}
	return {"name": "", "sprite": "cat-waiter-front.png", "tint": "#ffffff"}


func _next() -> void:
	if _busy:
		return
	_index += 1
	var lines: Array = scene["lines"]
	if _index >= lines.size():
		_finish()
		return
	_busy = true
	var line: Dictionary = lines[_index]
	var sp := speaker(String(line["who"]))
	_name.text = tr(String(sp["name"]))
	_label.text = tr(String(line["text"]))
	_face.texture = load("res://assets/cats/%s" % String(sp["sprite"])) as Texture2D
	_face.region_enabled = true
	_face.region_rect = Rect2(0, 16, 16, 16)
	_face.modulate = Color(String(sp["tint"]))
	Fx.hop(_face, 16.0, 0.25, 4.0)
	Audio.sfx("meow1" if _index % 2 == 0 else "meow2", 0.1, -6.0)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: _busy = false)


func _finish() -> void:
	GameState.mark_story_seen(String(scene["id"]))
	finished.emit()
	queue_free()
