class_name DialogueUI
extends CanvasLayer
## Диалоговое окно с «печатающимся» текстом и вариантами ответа.

signal _advance
signal _chosen(index: int)

var _root: Control
var _panel: PanelContainer
var _name_label: Label
var _text: RichTextLabel
var _arrow: Label
var _choices: VBoxContainer
var _typing: bool = false
var _waiting: bool = false
var _active: bool = false
var _line_time: float = 0.0
var _blip_pitch: float = 1.0
static var test_mode: bool = OS.get_environment("QH_AUTO") == "1" ## автотесты: диалоги проматываются сами
static var test_choices: Array = []


func _ready() -> void:
	layer = 15
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui)
	add_child(_root)
	_root.visible = false

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -560
	_panel.offset_right = 560
	_panel.offset_top = -200
	_panel.offset_bottom = -26
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 28)
	v.add_child(_text)
	_arrow = UiKit.label("▼", 26, UiKit.CORAL)
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_arrow)

	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UiKit.box(UiKit.CORAL, 14, UiKit.CORAL.darkened(0.3), 3, 14))
	tag.anchor_left = 0.5
	tag.anchor_right = 0.5
	tag.anchor_top = 1.0
	tag.anchor_bottom = 1.0
	tag.offset_left = -540
	tag.offset_top = -240
	tag.offset_bottom = -190
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tag)
	_name_label = UiKit.label("", 28, Color.WHITE)
	tag.add_child(_name_label)

	_choices = VBoxContainer.new()
	_choices.anchor_left = 0.5
	_choices.anchor_right = 0.5
	_choices.anchor_top = 1.0
	_choices.anchor_bottom = 1.0
	_choices.offset_left = 80
	_choices.offset_right = 560
	_choices.offset_bottom = -212
	_choices.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_choices.add_theme_constant_override("separation", 8)
	_root.add_child(_choices)


func begin() -> void:
	if _active:
		return
	_active = true
	Game.lock_ui()
	_root.visible = true
	_panel.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_panel, "modulate:a", 1.0, 0.15)


func end() -> void:
	if not _active:
		return
	_active = false
	_root.visible = false
	_choices.visible = false
	Game.unlock_ui()


func is_active() -> bool:
	return _active


func say(speaker: String, text: String, pitch: float = 1.0) -> void:
	begin()
	_blip_pitch = pitch
	_name_label.text = speaker
	_choices.visible = false
	_arrow.visible = false
	_text.text = text
	if test_mode:
		await get_tree().process_frame
		return
	_text.visible_characters = 0
	_typing = true
	_line_time = 0.0
	var total: int = _text.get_total_character_count()
	var shown: float = 0.0
	while _typing and shown < float(total):
		var step: float = 0.028
		await get_tree().create_timer(step).timeout
		if not _typing:
			break
		shown += 1.0
		_text.visible_characters = int(shown)
		if int(shown) % 2 == 0:
			Sfx.play("blip", _blip_pitch * randf_range(0.95, 1.08))
	_typing = false
	_text.visible_characters = -1
	_arrow.visible = true
	_waiting = true
	await _advance
	_waiting = false


func choose(speaker: String, text: String, options: Array, pitch: float = 1.0) -> int:
	begin()
	_blip_pitch = pitch
	_name_label.text = speaker
	_arrow.visible = false
	_text.text = text
	_text.visible_characters = -1
	if test_mode:
		await get_tree().process_frame
		if test_choices.is_empty():
			return options.size() - 1
		return mini(int(test_choices.pop_front()), options.size() - 1)
	for c in _choices.get_children():
		c.queue_free()
	for i in options.size():
		var b := UiKit.button(str(options[i]), Vector2(0, 58))
		b.add_theme_font_size_override("font_size", 26)
		var idx: int = i
		b.pressed.connect(func() -> void: _chosen.emit(idx))
		_choices.add_child(b)
	_choices.visible = true
	var r: int = await _chosen
	_choices.visible = false
	Sfx.play("click")
	return r


func _on_gui(event: InputEvent) -> void:
	var press: bool = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press = true
	if press:
		_try_advance()
		_root.accept_event()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("act") and not event.is_echo():
		if not _choices.visible:
			_try_advance()
		get_viewport().set_input_as_handled()


func _try_advance() -> void:
	if _choices.visible:
		return
	if _typing:
		_typing = false
		return
	if _waiting:
		_advance.emit()
