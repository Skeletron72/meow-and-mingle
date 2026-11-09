class_name Hud
extends CanvasLayer
## Экранный интерфейс города: часы, погода, деньги, цель, тосты, управление.

signal action_pressed
signal tool_selected(index: int)
signal bag_pressed
signal menu_pressed
signal camera_drag(dx: float)

var root: Control
var touch: TouchControls
var dialogue: DialogueUI
var _time_label: Label
var _date_label: Label
var _weather_label: Label
var _money_label: Label
var _objective: Label
var _objective_plate: PanelContainer
var _toasts: VBoxContainer
var _banner: Label
var _tool_name: Label
var _hint_t: float = 0.0


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)

	# часы / дата / погода
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	_time_label = UiKit.label("12:00", 38)
	_date_label = UiKit.label("", 20, UiKit.BROWN_L)
	_weather_label = UiKit.label("", 20)
	info.add_child(_time_label)
	info.add_child(_date_label)
	info.add_child(_weather_label)
	var iplate: PanelContainer = UiKit.plate(info, 14)
	iplate.position = Vector2(16, 14)
	iplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(iplate)

	# деньги
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 8)
	var icon := ItemIcon.new("_button")
	icon.show_bg = false
	icon.custom_minimum_size = Vector2(42, 42)
	money.add_child(icon)
	_money_label = UiKit.label("0", 32)
	money.add_child(_money_label)
	var mplate: PanelContainer = UiKit.plate(money, 10)
	mplate.anchor_left = 1.0
	mplate.anchor_right = 1.0
	mplate.offset_left = -230
	mplate.offset_right = -16
	mplate.offset_top = 14
	mplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mplate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(mplate)

	# цель
	_objective = UiKit.label("", 22)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(520, 0)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_plate = UiKit.plate(_objective, 10)
	_objective_plate.anchor_left = 0.5
	_objective_plate.anchor_right = 0.5
	_objective_plate.offset_left = -280
	_objective_plate.offset_right = 280
	_objective_plate.offset_top = 14
	_objective_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_objective_plate)

	# тосты
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -300
	_toasts.offset_right = 300
	_toasts.offset_top = 120
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)

	# название инструмента
	_tool_name = UiKit.label("", 24)
	_tool_name.add_theme_color_override("font_outline_color", UiKit.CREAM)
	_tool_name.add_theme_constant_override("outline_size", 8)
	_tool_name.anchor_left = 1.0
	_tool_name.anchor_right = 1.0
	_tool_name.anchor_top = 1.0
	_tool_name.anchor_bottom = 1.0
	_tool_name.offset_left = -560
	_tool_name.offset_right = -270
	_tool_name.offset_top = -170
	_tool_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_tool_name)

	# баннер по центру (крупные события)
	_banner = UiKit.label("", 54, Color.WHITE)
	_banner.add_theme_color_override("font_outline_color", UiKit.BROWN)
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.offset_top = 210
	_banner.offset_bottom = 290
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	touch = TouchControls.new()
	touch.show_stick = bool(Game.settings.get("touch", false))
	root.add_child(touch)
	touch.action_pressed.connect(func() -> void: action_pressed.emit())
	touch.tool_pressed.connect(func(i: int) -> void: tool_selected.emit(i))
	touch.bag_pressed.connect(func() -> void: bag_pressed.emit())
	touch.menu_pressed.connect(func() -> void: menu_pressed.emit())
	touch.camera_drag.connect(func(dx: float) -> void: camera_drag.emit(dx))

	dialogue = DialogueUI.new()
	add_child(dialogue)

	Game.money_changed.connect(_on_money)
	Game.toast.connect(show_toast)
	_on_money(Game.money())


func _on_money(m: int) -> void:
	_money_label.text = str(m)
	var t := create_tween()
	_money_label.pivot_offset = _money_label.size * 0.5
	t.tween_property(_money_label, "scale", Vector2(1.18, 1.18), 0.08)
	t.tween_property(_money_label, "scale", Vector2.ONE, 0.12)


func _process(delta: float) -> void:
	_time_label.text = Clock.time_string()
	_date_label.text = Clock.date_string()
	_hint_t -= delta
	var obj: String = Game.objective()
	if _objective.text != obj:
		_objective.text = obj
		_objective_plate.visible = obj != ""
		_objective_plate.size = Vector2.ZERO


func set_weather_text(text: String) -> void:
	_weather_label.text = text


func set_prompt(text: String) -> void:
	touch.set_prompt(text)


func set_tool_label(text: String) -> void:
	_tool_name.text = text


func show_toast(text: String, kind: String = "info") -> void:
	var p := PanelContainer.new()
	var col: Color = UiKit.CREAM
	var border: Color = UiKit.BROWN_L
	if kind == "good":
		col = Color(0.88, 0.97, 0.86)
		border = Color(0.35, 0.62, 0.35)
	elif kind == "bad":
		col = Color(0.99, 0.88, 0.84)
		border = UiKit.CORAL
	p.add_theme_stylebox_override("panel", UiKit.box(col, 14, border, 3, 12))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.18)
	t.tween_interval(2.4)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
		break


func banner(text: String, secs: float = 2.4) -> void:
	_banner.text = text
	var t := create_tween()
	t.tween_property(_banner, "modulate:a", 1.0, 0.3)
	t.tween_interval(secs)
	t.tween_property(_banner, "modulate:a", 0.0, 0.6)


func set_visible_hud(v: bool) -> void:
	root.visible = v
