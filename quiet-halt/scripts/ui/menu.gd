extends Control
## Главное меню: живой фон — город в золотой час, плывущая камера.

var env: EnvCtl
var cam: Camera3D
var _t: float = 0.0
var _focus: Vector3 = Vector3(40.5, 1.5, 14.0)
var _quit_btn: Button


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_ui()
	Sfx.music_on = true
	Sfx.set_ambient(0.0, 0.0)


func _build_backdrop() -> void:
	var world := Node3D.new()
	add_child(world)
	if World.state.ground.is_empty() or World.state.objects.is_empty() or Game.in_game == false:
		World.new_world(20260101, "Тихая Заводь", 0)
	var terrain := TerrainView.new()
	world.add_child(terrain)
	var ov := ObjectsView.new()
	world.add_child(ov)
	env = EnvCtl.new()
	env.force_hour = 15.6
	env.force_weather = Weather.Type.CLEAR
	world.add_child(env)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 260.0
	world.add_child(cam)
	cam.current = true


func _process(delta: float) -> void:
	_t += delta
	var ang: float = 3.14159 + sin(_t * 0.12) * 0.5
	var dist: float = 17.0
	_focus = Vector3(40.5, 1.6, 15.0)
	cam.global_position = _focus + Vector3(sin(ang) * dist, 6.5 + sin(_t * 0.2), cos(ang) * dist)
	cam.look_at(_focus, Vector3.UP)
	env.focus = _focus


func _build_ui() -> void:
	var title_box := VBoxContainer.new()
	title_box.anchor_left = 0.0
	title_box.anchor_top = 0.5
	title_box.anchor_bottom = 0.5
	title_box.offset_left = 70
	title_box.offset_top = -250
	title_box.offset_right = 700
	title_box.offset_bottom = 250
	title_box.add_theme_constant_override("separation", 16)
	add_child(title_box)

	var title := UiKit.label("Тихая Заводь", 92, Color.WHITE)
	title.add_theme_color_override("font_outline_color", UiKit.BROWN)
	title.add_theme_constant_override("outline_size", 22)
	title_box.add_child(title)
	var sub := UiKit.label("Станция, которая ждёт смотрителя", 30, Color.WHITE)
	sub.add_theme_color_override("font_outline_color", UiKit.BROWN)
	sub.add_theme_constant_override("outline_size", 10)
	title_box.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	title_box.add_child(sp)

	var cont := UiKit.warm_button("Продолжить", Vector2(380, 70))
	cont.add_theme_font_size_override("font_size", 30)
	cont.disabled = not Game.has_save()
	cont.pressed.connect(_on_continue)
	title_box.add_child(cont)
	var newb := UiKit.button("Новая игра", Vector2(380, 70))
	newb.add_theme_font_size_override("font_size", 30)
	newb.pressed.connect(_on_new)
	title_box.add_child(newb)
	if OS.get_name() != "Web" and OS.get_name() != "Android" and OS.get_name() != "iOS":
		_quit_btn = UiKit.button("Выход", Vector2(380, 60))
		_quit_btn.pressed.connect(func() -> void: get_tree().quit())
		title_box.add_child(_quit_btn)
	var ver := UiKit.label("версия 0.1 · играбельный прототип", 18, Color(1, 1, 1, 0.85))
	ver.add_theme_color_override("font_outline_color", UiKit.BROWN)
	ver.add_theme_constant_override("outline_size", 6)
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 24
	ver.offset_top = -40
	add_child(ver)


func _on_continue() -> void:
	Sfx.play("click")
	if Game.load_game():
		Game.change_scene("res://scenes/town.tscn")
	else:
		Game.say_toast("Не удалось загрузить сохранение", "bad")


func _on_new() -> void:
	Sfx.play("click")
	if Game.has_save():
		var dlg := ConfirmationDialog.new()
		dlg.title = "Новая игра"
		dlg.dialog_text = "Старое сохранение будет заменено. Начать заново?"
		dlg.ok_button_text = "Начать"
		dlg.cancel_button_text = "Отмена"
		dlg.confirmed.connect(func() -> void:
			Game.delete_save()
			Game.in_game = false
			Game.change_scene("res://scenes/intro.tscn"))
		add_child(dlg)
		dlg.popup_centered(Vector2i(520, 180))
	else:
		Game.in_game = false
		Game.change_scene("res://scenes/intro.tscn")
