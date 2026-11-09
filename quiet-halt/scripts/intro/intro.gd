extends Node3D
## Вступление: ночной вагон, разговор с проводницей Фетрой, создание персонажа,
## выбор названия станции и полушария — всё внутри диалога.

var env: EnvCtl
var cam: Camera3D
var room: Node3D
var player_model: CharacterModel
var fetra: VillagerModel
var dialogue: DialogueUI
var ui: CanvasLayer
var ui_root: Control

var look: Dictionary = CharacterModel.default_look()
var player_name: String = ""
var town_name: String = "Тихая Заводь"
var hemisphere: int = 0

var _cam_pos: Vector3 = Vector3(0, 1.5, 3.8)
var _cam_look: Vector3 = Vector3(0, 1.15, -1.6)
var _layers: Array = [] # [node, speed, period]
var _t: float = 0.0
var _name_value: String = ""
var _speed_mult: float = 1.0
signal _text_done(text: String)
signal _creator_done
signal _hemi_done


func _ready() -> void:
	World.new_world(777, "Тихая Заводь", 0)
	_build_room()
	_build_scenery()
	env = EnvCtl.new()
	env.force_hour = 9.6
	env.force_weather = Weather.Type.CLEAR
	add_child(env)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true
	cam.global_position = _cam_pos
	ui = CanvasLayer.new()
	ui.layer = 12
	add_child(ui)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UiKit.theme()
	ui.add_child(ui_root)
	dialogue = DialogueUI.new()
	add_child(dialogue)
	Sfx.music_on = true
	Sfx.set_ambient(0.0, 0.35)
	_run()


func _process(delta: float) -> void:
	_t += delta
	for l in _layers:
		var n: Node3D = l[0]
		n.position.x += float(l[1]) * _speed_mult * delta
		if n.position.x > float(l[2]):
			n.position.x -= float(l[2])
	room.rotation.z = sin(_t * 2.1) * 0.0035
	room.position.y = sin(_t * 4.3) * 0.006
	_cam_pos_apply(delta)
	env.focus = Vector3(0, 0, -3)


func _cam_pos_apply(delta: float) -> void:
	var k: float = minf(delta * 2.2, 1.0)
	cam.global_position = cam.global_position.lerp(_cam_pos, k)
	var cur: Vector3 = cam.global_position + (-cam.global_transform.basis.z) * 5.0
	cam.look_at(cur.lerp(_cam_look, k), Vector3.UP)


# ---------------------------------------------------------------- декорации

func _build_room() -> void:
	room = Node3D.new()
	add_child(room)
	var k := MeshKit.new()
	var wood: Color = Color(0.62, 0.44, 0.32)
	var wood_d: Color = Color(0.48, 0.33, 0.25)
	var cream: Color = Color(0.96, 0.89, 0.74)
	k.box(Vector3(0, -0.05, -0.2), Vector3(6.2, 0.1, 5.6), Color(0.66, 0.48, 0.34))
	k.box(Vector3(0, 0.0, 0.2), Vector3(3.0, 0.02, 2.2), Color(0.70, 0.30, 0.32))
	k.box(Vector3(0, 0.0, 0.2), Vector3(2.6, 0.03, 1.8), Color(0.84, 0.64, 0.42))
	k.box(Vector3(0, 3.05, -0.2), Vector3(6.2, 0.1, 5.6), cream)
	for sx in [-3.05, 3.05]:
		k.box(Vector3(sx, 0.8, -0.2), Vector3(0.1, 1.6, 5.6), wood)
		k.box(Vector3(sx, 2.3, -0.2), Vector3(0.1, 1.5, 5.6), cream)
		k.box(Vector3(sx * 0.985, 1.6, -0.2), Vector3(0.12, 0.08, 5.6), wood_d)
	# задняя стена с окном (x −1.5..1.5, y 1.0..2.5)
	k.box(Vector3(-2.3, 1.5, -2.3), Vector3(1.6, 3.0, 0.12), wood)
	k.box(Vector3(2.3, 1.5, -2.3), Vector3(1.6, 3.0, 0.12), wood)
	k.box(Vector3(0, 0.5, -2.3), Vector3(3.0, 1.0, 0.12), wood)
	k.box(Vector3(0, 2.8, -2.3), Vector3(3.0, 0.4, 0.12), cream)
	k.box(Vector3(0, 1.0, -2.2), Vector3(3.2, 0.1, 0.3), wood_d)
	k.box(Vector3(-1.52, 1.75, -2.22), Vector3(0.08, 1.6, 0.1), wood_d)
	k.box(Vector3(1.52, 1.75, -2.22), Vector3(0.08, 1.6, 0.1), wood_d)
	k.box(Vector3(0, 2.52, -2.22), Vector3(3.1, 0.08, 0.1), wood_d)
	k.box(Vector3(0, 1.75, -2.22), Vector3(0.06, 1.5, 0.06), wood_d)
	# шторы
	var teal: Color = Color(0.32, 0.58, 0.60)
	k.box(Vector3(-1.35, 1.8, -2.1), Vector3(0.45, 1.8, 0.1), teal)
	k.box(Vector3(1.35, 1.8, -2.1), Vector3(0.45, 1.8, 0.1), teal)
	# диван
	k.box(Vector3(0, 0.36, -1.85), Vector3(5.0, 0.3, 0.8), Color(0.58, 0.28, 0.32))
	k.box(Vector3(0, 0.15, -1.85), Vector3(5.0, 0.3, 0.8), wood_d)
	k.box(Vector3(-2.4, 0.5, -1.85), Vector3(0.2, 0.6, 0.8), Color(0.52, 0.24, 0.28))
	k.box(Vector3(2.4, 0.5, -1.85), Vector3(0.2, 0.6, 0.8), Color(0.52, 0.24, 0.28))
	# багажная полка и чемодан
	k.box(Vector3(2.0, 2.3, -1.9), Vector3(1.6, 0.06, 0.5), wood_d)
	k.box(Vector3(2.0, 2.52, -1.9), Vector3(0.9, 0.38, 0.4), Color(0.72, 0.5, 0.3))
	k.box(Vector3(-2.0, 2.3, -1.9), Vector3(1.4, 0.06, 0.5), wood_d)
	k.box(Vector3(-2.1, 2.46, -1.9), Vector3(0.5, 0.3, 0.4), Color(0.4, 0.5, 0.6))
	# бра
	for sx in [-2.7, 2.7]:
		k.box(Vector3(sx, 2.0, -2.2), Vector3(0.18, 0.28, 0.18), Color(1.0, 0.85, 0.5), "glow")
		k.box(Vector3(sx, 1.82, -2.2), Vector3(0.24, 0.05, 0.24), wood_d)
	# столик у окна
	k.cyl(Vector3(0, 0, -1.2), 0.05, 0.05, 0.7, wood_d, 6)
	k.cyl(Vector3(0, 0.7, -1.2), 0.45, 0.45, 0.05, wood, 10)
	k.cyl(Vector3(0.1, 0.75, -1.2), 0.1, 0.07, 0.14, Color(0.96, 0.92, 0.84), 8)
	k.cyl(Vector3(-0.15, 0.75, -1.1), 0.12, 0.12, 0.02, Color(0.86, 0.5, 0.42), 8)
	var mi := MeshInstance3D.new()
	mi.mesh = k.build()
	room.add_child(mi)
	for lx in [-2.7, 2.7]:
		var l := OmniLight3D.new()
		l.position = Vector3(lx, 1.9, -1.6)
		l.omni_range = 6.0
		l.light_color = Color(1.0, 0.9, 0.75)
		l.light_energy = 0.4
		room.add_child(l)
	# проводница и игрок
	fetra = VillagerModel.new()
	room.add_child(fetra)
	fetra.build("felt", Color(0.72, 0.60, 0.70))
	fetra.position = Vector3(-1.2, 0.5, -1.7)
	fetra.rotation.y = 0.15
	fetra.scale = Vector3(1.05, 1.05, 1.05)
	var capk := MeshKit.new()
	capk.cyl(Vector3(0, 0.0, 0), 0.36, 0.3, 0.12, Color(0.22, 0.28, 0.42), 10)
	capk.box(Vector3(0, 0.02, 0.32), Vector3(0.4, 0.03, 0.18), Color(0.16, 0.2, 0.3))
	var cap := MeshInstance3D.new()
	cap.mesh = capk.build()
	cap.position = Vector3(0, 0.92, 0.0)
	fetra.add_child(cap)
	player_model = CharacterModel.new()
	room.add_child(player_model)
	player_model.build(look)
	player_model.position = Vector3(1.0, 0.56, -1.7)
	player_model.rotation.y = 0.15
	player_model.set_sitting(true)
	player_model.visible = false


func _build_scenery() -> void:
	var scenery := Node3D.new()
	scenery.position = Vector3(0, 0, 0)
	add_child(scenery)
	var gk := MeshKit.new()
	gk.box(Vector3(0, -1.2, -45), Vector3(260, 1.0, 90), Color(0.60, 0.60, 0.60, 0.0))
	gk.box(Vector3(0, -0.62, -3.6), Vector3(260, 0.2, 2.0), Color(0.48, 0.44, 0.42, 1.0))
	var gmi := MeshInstance3D.new()
	gmi.mesh = gk.build()
	scenery.add_child(gmi)
	# дальние холмы
	_make_layer(scenery, 0.9, 80.0, func(k: MeshKit, base: float) -> void:
		for i in 5:
			var x: float = base + float(i) * 16.0
			var r: float = 12.0 + float((i * 7) % 5) * 3.0
			k.ball(Vector3(x, -1.0, -48.0 - float(i % 3) * 8.0), Vector3(r * 1.7, r * 0.55, r), Color(0.55, 0.60, 0.55, 0.0), 10, 6))
	# средние деревья
	_make_layer(scenery, 3.6, 48.0, func(k: MeshKit, base: float) -> void:
		for i in 10:
			var x: float = base + float(i) * 4.8 + float((i * 13) % 5) * 0.4
			var z: float = -16.0 - float((i * 5) % 4) * 2.0
			if i % 3 == 0:
				k.cyl(Vector3(x, -0.6, z), 0.3, 0.2, 2.0, Color(0.45, 0.33, 0.25), 6)
				k.ball(Vector3(x, 2.4, z), Vector3(2.0, 1.7, 2.0), Color(0.66, 0.66, 0.66, 0.5), 8, 5)
			else:
				k.cyl(Vector3(x, -0.6, z), 1.6, 0.0, 4.2, Color(0.27, 0.47, 0.35), 8)
				k.cyl(Vector3(x, 1.4, z), 1.2, 0.0, 3.0, Color(0.30, 0.50, 0.38), 8))
	# ближние столбы и кусты
	_make_layer(scenery, 11.0, 30.0, func(k: MeshKit, base: float) -> void:
		for i in 3:
			var x: float = base + float(i) * 10.0
			k.cyl(Vector3(x, -0.6, -6.0), 0.12, 0.1, 5.0, Color(0.42, 0.32, 0.26), 5)
			k.box(Vector3(x, 4.0, -6.0), Vector3(1.6, 0.1, 0.1), Color(0.42, 0.32, 0.26))
		for i in 12:
			var x2: float = base + float(i) * 2.5
			k.ball(Vector3(x2, -0.35, -4.6), Vector3(0.9, 0.55, 0.7), Color(0.66, 0.66, 0.66, 0.5), 6, 4))


func _make_layer(parent: Node3D, speed: float, period: float, builder: Callable) -> void:
	var node := Node3D.new()
	parent.add_child(node)
	var k := MeshKit.new()
	for rep in 4:
		builder.call(k, -period * 2.0 + float(rep) * period)
	var mi := MeshInstance3D.new()
	mi.mesh = k.build()
	node.add_child(mi)
	_layers.append([node, speed, period])


# ---------------------------------------------------------------- сценарий

func _cam_set(pos: Vector3, look_at_p: Vector3) -> void:
	_cam_pos = pos
	_cam_look = look_at_p


func _run() -> void:
	await Game.fade_in(1.0)
	var d: DialogueUI = dialogue
	_cam_set(Vector3(0.0, 1.5, 3.4), Vector3(-0.3, 1.05, -1.6))
	await get_tree().create_timer(1.0).timeout
	await d.say("Фетра", "Ох, не спите? Хорошо. Кому-то надо услышать, как стучат колёса. Билет, пожалуйста.", 0.9)
	await d.say("Фетра", "«В один конец, до Тихой Заводи». Хм… Давненько сюда не брали билетов. Одиннадцать лет, если не ошибаюсь.", 0.9)
	await d.say("Фетра", "Я — Фетра, проводница. А вас как записать в книгу пассажиров?", 0.9)
	d.end()
	player_name = await _ask_text("Ваше имя", "Как вас зовут?", "", "Странник", 14)
	player_model.visible = true
	_cam_set(Vector3(0.9, 1.45, 2.0), Vector3(0.7, 1.05, -1.7))
	await d.say("Фетра", "%s… красиво. Загляните-ка в зеркало над столиком, пока я ставлю печать." % player_name, 0.9)
	d.end()
	await _creator()
	_cam_set(Vector3(0.2, 1.5, 3.4), Vector3(0.0, 1.05, -1.6))
	await d.say("Фетра", "Совсем другое дело! В такой кепке сразу видно — смотритель. Только кепка тут не главное.", 0.9)
	await d.say("Фетра", "Табличка на станции давно стёрлась. Как будем записывать вашу станцию и городок вокруг неё?", 0.9)
	d.end()
	town_name = await _ask_text("Название станции", "Название вашей станции", "Тихая Заводь", "Тихая Заводь", 22)
	await d.say("Фетра", "«%s». Звучит как пароль. Теперь последнее — откуда вы ехали?" % town_name, 0.9)
	await d.say("Фетра", "Говорят, от этого зависит, как у нас идут времена года: у одних зима в декабре, у других — в июне. Нужно знать, какого берега вы родом.", 0.9)
	d.end()
	await _hemisphere()
	_cam_set(Vector3(0.0, 1.5, 3.4), Vector3(0.0, 1.1, -1.6))
	var hemi_txt: String = "северных" if hemisphere == 0 else "южных"
	await d.say("Фетра", "Из %s краёв. Запомнила. Значит, у вас сейчас — %s, и этого лучше держаться." % [hemi_txt, Clock.season_name().to_lower()], 0.9)
	await d.say("Фетра", "И ещё. Последний смотритель, Лидия Верст, уехала в ночь большого тумана. Часы встали, поезда обходят станцию стороной.", 0.8)
	await d.say("Фетра", "Никто не знает, куда она делась. А вы вот приехали. Это уже что-то.", 0.8)
	Sfx.play("horn")
	await d.say("Поезд", "Колёса замедляются. За окном проплывают тёмные ели, потом — старая платформа, и тусклый фонарь у кромки перрона.", 0.6)
	d.end()
	# замедляем сцену
	create_tween().tween_property(self, "_speed_mult", 0.0, 3.0)
	await get_tree().create_timer(0.3).timeout
	await d.say("Фетра", "Конечная! Тихая Заводь. Вас уже ждут, смотритель. Не грустите — тут тише, чем кажется, и теплее.", 0.9)
	d.end()
	_finish()


func _finish() -> void:
	Sfx.music_on = false
	Game.start_new_game(player_name, look, town_name, hemisphere)
	Game.change_scene("res://scenes/town.tscn", 0.9)


# ---------------------------------------------------------------- окна ввода

func _ask_text(title: String, prompt: String, initial: String, fallback: String, max_len: int) -> String:
	if DialogueUI.test_mode:
		await get_tree().process_frame
		return initial if initial != "" else "Алиса"
	var card := PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -300
	card.offset_right = 300
	card.offset_top = -130
	card.offset_bottom = 130
	ui_root.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	v.add_child(UiKit.label(title, 34))
	v.add_child(UiKit.label(prompt, 22, UiKit.BROWN_L))
	var le := LineEdit.new()
	le.text = initial
	le.placeholder_text = fallback
	le.max_length = max_len
	le.custom_minimum_size = Vector2(0, 60)
	le.add_theme_font_size_override("font_size", 30)
	v.add_child(le)
	var ok := UiKit.warm_button("Готово", Vector2(0, 60))
	v.add_child(ok)
	Game.lock_ui()
	var submit := func() -> void:
		var txt: String = le.text.strip_edges()
		_text_done.emit(txt if txt != "" else fallback)
	ok.pressed.connect(submit)
	le.text_submitted.connect(func(_t: String) -> void: submit.call())
	le.grab_focus()
	var res: String = await _text_done
	Game.unlock_ui()
	Sfx.play("pickup")
	card.queue_free()
	return res


func _creator() -> void:
	if DialogueUI.test_mode:
		await get_tree().process_frame
		return
	var card := PanelContainer.new()
	card.anchor_left = 0.0
	card.anchor_right = 0.0
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = 30
	card.offset_right = 520
	card.offset_top = -300
	card.offset_bottom = 300
	ui_root.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	v.add_child(UiKit.label("Внешность", 34))
	var rows: Array = [
		["Кожа", "skin", CharacterModel.SKINS.size(), null],
		["Причёска", "hair", CharacterModel.HAIR_STYLE_NAMES.size(), CharacterModel.HAIR_STYLE_NAMES],
		["Цвет волос", "hair_color", CharacterModel.HAIRS.size(), null],
		["Глаза", "eyes", CharacterModel.EYE_NAMES.size(), CharacterModel.EYE_NAMES],
		["Жилет", "outfit", CharacterModel.OUTFITS.size(), null],
	]
	var value_labels: Dictionary = {}
	for r in rows:
		var key: String = r[1]
		var cnt: int = r[2]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UiKit.label(str(r[0]), 24))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		var bl := UiKit.button("<", Vector2(54, 48))
		var vl := UiKit.label("", 22)
		vl.custom_minimum_size = Vector2(110, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var br := UiKit.button(">", Vector2(54, 48))
		var names: Variant = r[3]
		var upd := func() -> void:
			var i: int = int(look[key])
			vl.text = str(names[i]) if names != null else "%d / %d" % [i + 1, cnt]
		upd.call()
		value_labels[key] = upd
		bl.pressed.connect(func() -> void:
			look[key] = (int(look[key]) + cnt - 1) % cnt
			upd.call()
			_refresh_preview())
		br.pressed.connect(func() -> void:
			look[key] = (int(look[key]) + 1) % cnt
			upd.call()
			_refresh_preview())
		h.add_child(bl)
		h.add_child(vl)
		h.add_child(br)
		v.add_child(h)
	var cap := CheckButton.new()
	cap.text = "Кепка смотрителя"
	cap.button_pressed = bool(look.get("cap", true))
	cap.focus_mode = Control.FOCUS_NONE
	cap.toggled.connect(func(on: bool) -> void:
		look["cap"] = on
		_refresh_preview())
	v.add_child(cap)
	var rnd := UiKit.button("Случайно", Vector2(0, 52))
	rnd.pressed.connect(func() -> void:
		for r in rows:
			look[r[1]] = randi() % int(r[2])
			(value_labels[r[1]] as Callable).call()
		_refresh_preview()
		Sfx.play("pickup"))
	v.add_child(rnd)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp2)
	var ok := UiKit.warm_button("Готово", Vector2(0, 62))
	ok.pressed.connect(func() -> void: _creator_done.emit())
	v.add_child(ok)
	Game.lock_ui()
	await _creator_done
	Game.unlock_ui()
	Sfx.play("pickup")
	card.queue_free()


func _refresh_preview() -> void:
	player_model.build(look)
	player_model.set_sitting(true)
	Sfx.play("click")


func _hemisphere() -> void:
	if DialogueUI.test_mode:
		await get_tree().process_frame
		return
	var card := PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -440
	card.offset_right = 440
	card.offset_top = -210
	card.offset_bottom = 210
	ui_root.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	v.add_child(UiKit.label("Откуда вы ехали?", 36))
	var info := UiKit.label("", 24, UiKit.BROWN_L)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 90)
	v.add_child(info)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var north := UiKit.button("Из северных краёв\n(зима — в декабре)", Vector2(0, 110))
	var south := UiKit.button("Из южных краёв\n(зима — в июне)", Vector2(0, 110))
	north.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	south.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(north)
	h.add_child(south)
	var ok := UiKit.warm_button("Это мой берег", Vector2(0, 64))
	v.add_child(ok)
	var show := func(hemi: int) -> void:
		hemisphere = hemi
		Clock.hemisphere = hemi
		World.state.hemisphere = hemi
		env.update_now(true)
		var months: Array[String] = ["", "январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
		info.text = "Сейчас у вас: %s (%s). Окно вагона уже показывает, как выглядит этот сезон." % [Clock.season_name().to_lower(), months[Clock.month()]]
		for pair in [[north, 0], [south, 1]]:
			var b: Button = pair[0]
			if hemi == int(pair[1]):
				b.add_theme_stylebox_override("normal", UiKit.box(UiKit.GOLD, 14, UiKit.GOLD.darkened(0.3), 4, 14))
				b.add_theme_stylebox_override("hover", UiKit.box(UiKit.GOLD, 14, UiKit.GOLD.darkened(0.3), 4, 14))
				b.add_theme_color_override("font_color", UiKit.BROWN)
				b.add_theme_color_override("font_hover_color", UiKit.BROWN)
				b.add_theme_color_override("font_outline_color", UiKit.GOLD)
			else:
				b.remove_theme_stylebox_override("normal")
				b.remove_theme_stylebox_override("hover")
				b.remove_theme_color_override("font_color")
				b.remove_theme_color_override("font_hover_color")
				b.remove_theme_color_override("font_outline_color")
		Sfx.play("click")
	north.pressed.connect(func() -> void: show.call(0))
	south.pressed.connect(func() -> void: show.call(1))
	show.call(hemisphere)
	ok.pressed.connect(func() -> void: _hemi_done.emit())
	Game.lock_ui()
	await _hemi_done
	Game.unlock_ui()
	Sfx.play("pickup")
	card.queue_free()
