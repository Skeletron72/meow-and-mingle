class_name TouchControls
extends Control
## Экранное управление: стик, кнопка действия, инструменты, рюкзак, меню.
## Работает с мультитачем (ходим и жмём действие одновременно) и с мышью.

signal action_pressed
signal tool_pressed(index: int)
signal bag_pressed
signal menu_pressed
signal camera_drag(dx: float)

var stick: Vector2 = Vector2.ZERO
var prompt: String = ""
var selected_tool: int = 0
var show_stick: bool = false

var _stick_touch: int = -2
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _cam_touch: int = -2
var _cam_last: float = 0.0
var _btn_touch: Dictionary = {}
var _tool_icons: Array[ItemIcon] = []
var _prompt_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in Game.TOOLS.size():
		var ic := ItemIcon.new(Game.TOOLS[i])
		ic.custom_minimum_size = Vector2(84, 84)
		ic.size = Vector2(84, 84)
		add_child(ic)
		_tool_icons.append(ic)
	_prompt_label = UiKit.label("", 26, UiKit.BROWN)
	_prompt_label.add_theme_color_override("font_outline_color", UiKit.CREAM)
	_prompt_label.add_theme_constant_override("outline_size", 8)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_prompt_label)
	resized.connect(_layout)
	_layout()


func action_center() -> Vector2:
	return Vector2(size.x - 120, size.y - 120)


func _tool_pos(i: int) -> Vector2:
	return Vector2(size.x - 270 - float(i) * 96.0, size.y - 85)


func bag_center() -> Vector2:
	return Vector2(size.x - 52, 150)


func menu_center() -> Vector2:
	return Vector2(size.x - 52, 222)


func _layout() -> void:
	for i in _tool_icons.size():
		_tool_icons[i].position = _tool_pos(i) - Vector2(42, 42)
	_prompt_label.size = Vector2(520, 36)
	_prompt_label.position = Vector2(size.x - 520 - 30, size.y - 270)
	queue_redraw()


func set_prompt(text: String) -> void:
	if text != prompt:
		prompt = text
		_prompt_label.text = text
		queue_redraw()


func set_tool(i: int) -> void:
	selected_tool = i
	for j in _tool_icons.size():
		_tool_icons[j].selected = j == i
		_tool_icons[j].queue_redraw()


func _draw() -> void:
	# кнопка действия
	var ac: Vector2 = action_center()
	draw_circle(ac, 84, Color(0.0, 0.0, 0.0, 0.12))
	draw_circle(ac, 78, UiKit.CORAL)
	draw_arc(ac, 78, 0, TAU, 40, UiKit.CORAL.darkened(0.3), 5.0, true)
	var f: Font = ThemeDB.fallback_font
	var label: String = "Действие" if prompt != "" else "Рука"
	var w: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(f, ac + Vector2(-w * 0.5, 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	# рюкзак
	var bc: Vector2 = bag_center()
	draw_circle(bc, 34, Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.95))
	draw_arc(bc, 34, 0, TAU, 28, UiKit.BROWN_L, 3.0, true)
	draw_rect(Rect2(bc + Vector2(-13, -8), Vector2(26, 24)), Color(0.78, 0.5, 0.35))
	draw_arc(bc + Vector2(0, -9), 9, PI, TAU, 10, UiKit.BROWN, 3.0)
	draw_rect(Rect2(bc + Vector2(-8, 3), Vector2(16, 8)), Color(0.95, 0.8, 0.5))
	# меню
	var mc: Vector2 = menu_center()
	draw_circle(mc, 34, Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.95))
	draw_arc(mc, 34, 0, TAU, 28, UiKit.BROWN_L, 3.0, true)
	for dy in [-10, 0, 10]:
		draw_line(mc + Vector2(-14, dy), mc + Vector2(14, dy), UiKit.BROWN, 4.0, true)
	# стик
	if show_stick:
		var base: Vector2 = _stick_origin if _stick_touch != -2 else Vector2(150, size.y - 150)
		draw_circle(base, 90, Color(0, 0, 0, 0.10))
		draw_arc(base, 90, 0, TAU, 40, Color(UiKit.BROWN.r, UiKit.BROWN.g, UiKit.BROWN.b, 0.5), 4.0, true)
		var knob: Vector2 = base + (stick * 60.0 if _stick_touch != -2 else Vector2.ZERO)
		draw_circle(knob, 40, Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.9))
		draw_arc(knob, 40, 0, TAU, 28, UiKit.BROWN_L, 3.0, true)


func _hit_button(p: Vector2) -> String:
	if p.distance_to(action_center()) < 86:
		return "action"
	if p.distance_to(bag_center()) < 38:
		return "bag"
	if p.distance_to(menu_center()) < 38:
		return "menu"
	for i in Game.TOOLS.size():
		if p.distance_to(_tool_pos(i)) < 44:
			return "tool%d" % i
	return ""


func _press_button(name: String) -> void:
	match name:
		"action": action_pressed.emit()
		"bag": bag_pressed.emit()
		"menu": menu_pressed.emit()
		_:
			if name.begins_with("tool"):
				tool_pressed.emit(int(name.substr(4)))


func _input(event: InputEvent) -> void:
	if Game.ui_lock > 0:
		_release_all()
		return
	var is_touch: bool = event is InputEventScreenTouch or event is InputEventScreenDrag
	var is_mouse: bool = (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device != InputEvent.DEVICE_ID_EMULATION
	if not is_touch and not is_mouse:
		return
	var idx: int = -1
	var pos: Vector2 = Vector2.ZERO
	var pressed: bool = false
	var released: bool = false
	var drag: bool = false
	if event is InputEventScreenTouch:
		idx = event.index
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		idx = event.index
		pos = event.position
		drag = true
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return
		idx = 100 + event.button_index
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	else:
		pos = event.position
		drag = true
		idx = 100 + MOUSE_BUTTON_LEFT if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 else (100 + MOUSE_BUTTON_RIGHT if (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 else -1)
		if idx == -1:
			return
	if pressed:
		var b: String = _hit_button(pos)
		if b != "":
			_btn_touch[idx] = b
			_press_button(b)
			get_viewport().set_input_as_handled()
			return
		if show_stick and pos.x < size.x * 0.4 and pos.y > size.y * 0.35 and _stick_touch == -2:
			_stick_touch = idx
			_stick_origin = pos
			_stick_pos = pos
			stick = Vector2.ZERO
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if _cam_touch == -2 and pos.x > size.x * 0.35 and pos.y > 70:
			_cam_touch = idx
			_cam_last = pos.x
			return
	elif released:
		if idx == _stick_touch:
			_stick_touch = -2
			stick = Vector2.ZERO
			queue_redraw()
		if idx == _cam_touch:
			_cam_touch = -2
		_btn_touch.erase(idx)
	elif drag:
		if idx == _stick_touch:
			var d: Vector2 = (pos - _stick_origin) / 80.0
			stick = d.limit_length(1.0)
			queue_redraw()
		elif idx == _cam_touch:
			camera_drag.emit(pos.x - _cam_last)
			_cam_last = pos.x


func _release_all() -> void:
	if _stick_touch != -2 or _cam_touch != -2:
		_stick_touch = -2
		_cam_touch = -2
		stick = Vector2.ZERO
		queue_redraw()
