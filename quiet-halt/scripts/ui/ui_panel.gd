class_name UiPanel
extends Control
## Базовое всплывающее окно: затемнение, карточка, заголовок, кнопка «Закрыть».

signal closed

var title_label: Label
var body: VBoxContainer
var card: PanelContainer
var _open: bool = false


func _init() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func build(title: String, width: float = 980.0, height: float = 600.0) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.06, 0.08, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	card = PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -width * 0.5
	card.offset_right = width * 0.5
	card.offset_top = -height * 0.5
	card.offset_bottom = height * 0.5
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	title_label = UiKit.label(title, 34, UiKit.BROWN)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close := UiKit.warm_button("Закрыть", Vector2(160, 52))
	close.pressed.connect(close_panel)
	head.add_child(close)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	v.add_child(body)


func open_panel() -> void:
	if _open:
		return
	_open = true
	visible = true
	Game.lock_ui()
	refresh()
	card.scale = Vector2(0.94, 0.94)
	card.pivot_offset = card.size * 0.5
	card.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(card, "scale", Vector2.ONE, 0.14)
	t.tween_property(card, "modulate:a", 1.0, 0.14)
	Sfx.play("click")


func close_panel() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Game.unlock_ui()
	closed.emit()
	Sfx.play("click")


func is_open() -> bool:
	return _open


func refresh() -> void:
	pass


func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("cancel") or event.is_action_pressed("menu")):
		close_panel()
		get_viewport().set_input_as_handled()


func clear_body() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
