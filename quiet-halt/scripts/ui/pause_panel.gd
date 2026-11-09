class_name PausePanel
extends UiPanel
## Меню паузы: сохранить, дневник, настройки, выход.

signal journal_requested
signal quit_requested

var _debug_box: VBoxContainer
var _touch_check: CheckButton


func _init() -> void:
	super._init()
	build("Пауза", 560, 700)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	body.add_child(v)
	var b_cont := UiKit.button("Продолжить", Vector2(0, 58))
	b_cont.pressed.connect(close_panel)
	v.add_child(b_cont)
	var b_save := UiKit.button("Сохранить игру", Vector2(0, 58))
	b_save.pressed.connect(func() -> void:
		if Game.save_game():
			Game.say_toast("Игра сохранена", "good")
		else:
			Game.say_toast("Не удалось сохранить", "bad"))
	v.add_child(b_save)
	var b_j := UiKit.button("Дневник смотрителя", Vector2(0, 58))
	b_j.pressed.connect(func() -> void:
		close_panel()
		journal_requested.emit())
	v.add_child(b_j)
	v.add_child(_slider("Музыка", "music"))
	v.add_child(_slider("Звуки", "sfx"))
	_touch_check = CheckButton.new()
	_touch_check.text = "Экранный джойстик"
	_touch_check.focus_mode = Control.FOCUS_NONE
	_touch_check.toggled.connect(func(on: bool) -> void: Game.set_setting("touch", on))
	v.add_child(_touch_check)
	var dbg := CheckButton.new()
	dbg.text = "Режим тестирования"
	dbg.focus_mode = Control.FOCUS_NONE
	dbg.toggled.connect(func(on: bool) -> void:
		Game.set_setting("debug", on)
		_debug_box.visible = on)
	v.add_child(dbg)
	_debug_box = VBoxContainer.new()
	_debug_box.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for hrs in [1, 6, 24]:
		var b := UiKit.button("+%d ч" % hrs, Vector2(0, 48))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hh: float = float(hrs)
		b.pressed.connect(func() -> void:
			Clock.add_debug_hours(hh)
			Game.say_toast("Время перемотано на %d ч" % int(hh)))
		h.add_child(b)
	_debug_box.add_child(h)
	var money_b := UiKit.button("+1000 пуговиц", Vector2(0, 48))
	money_b.pressed.connect(func() -> void: Game.add_money(1000))
	_debug_box.add_child(money_b)
	v.add_child(_debug_box)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var b_q := UiKit.warm_button("В главное меню", Vector2(0, 58))
	b_q.pressed.connect(func() -> void:
		close_panel()
		quit_requested.emit())
	v.add_child(b_q)


func _slider(label_text: String, key: String) -> Control:
	var h := HBoxContainer.new()
	h.add_child(UiKit.label(label_text, 24))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Game.settings.get(key, 0.6))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 40)
	s.value_changed.connect(func(v: float) -> void:
		Game.set_setting(key, v)
		if key == "sfx":
			Sfx.play("pickup"))
	h.add_child(s)
	return h


func refresh() -> void:
	_touch_check.set_pressed_no_signal(bool(Game.settings.get("touch", false)))
	_debug_box.visible = bool(Game.settings.get("debug", false))
