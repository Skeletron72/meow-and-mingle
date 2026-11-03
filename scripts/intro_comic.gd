class_name IntroComic
extends Node2D
## Комикс-завязка новой игры: 5 панелей. Мяу находит мамин ключ и решает открыть родительскую кофейню «Тёплая Лапка».
## Все панели собираются кодом из имеющихся спрайтов (коты, мебель, здание, тайлы) и простых форм; тап — следующая панель,
## «Пропустить» — сразу в игру. После последней панели начинается катсцена открытия кафе (intro_stage = 1).

const ART_SIZE := Vector2(296, 226)
const ART_POS := Vector2(32, 150)
const PAGE_BG := Color("1f1722")
const PAPER := Color("f3e6c8")
const INK := Color("2a1d1a")

const FURN: Texture2D = preload("res://assets/cafe/neko-cafe-furnitures.png")
const DRINKS: Texture2D = preload("res://assets/cafe/drinks-and-pastries.png")
const TILES: Texture2D = preload("res://assets/street/tiles/street_tiles.png")
const BUILDING: Texture2D = preload("res://assets/street/buildings/building4.png")
const LAMP: Texture2D = preload("res://assets/street/props/lamp.png")

## Панели: заголовок-подпись, реплики {text, x, y (центр пузыря в рамке кадра), tail: куда смотрит хвостик}.
const PANELS := [
	{"build": "_panel_home", "caption": "В комоде — ключ с биркой:\n«Ставни — пяткой!»", "lines": [{"text": "Это же мамин ключ…", "x": 150, "y": 34}]},
	{"build": "_panel_street", "caption": "Ключ знал дорогу.\nМяу — не сразу.", "lines": [{"text": "Налево? Нет, направо.", "x": 150, "y": 30}]},
	{"build": "_panel_facade", "caption": "Навес выцвел. Вывеска\nтоже. Зато стоит!", "lines": [{"text": "Выцвела. Как и я.", "x": 150, "y": 28}]},
	{"build": "_panel_lock", "caption": "Замок помнил мамину лапу.\nЛапу Мяу — не очень.", "lines": [{"text": "Заело… Пожалуйста?", "x": 100, "y": 30}]},
	{"build": "_panel_decision", "caption": "Решено:\n«Тёплая Лапка» работает!", "lines": [{"text": "Будет! Сейчас… чихну.", "x": 120, "y": 26}, {"text": "Тут эспрессо дают?", "x": 190, "y": 76}]},
]

var _index := -1
var _page: Node2D
var _busy := false
var _hint: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(360, 640)
	bg.color = PAGE_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var title := Ui.label("Тёплая Лапка", Rect2(0, 18, 360, 36), Ui.FONT_SIZE, Color("ffd9a0"), self, HORIZONTAL_ALIGNMENT_CENTER, true)
	title.add_theme_color_override("font_outline_color", Color("5b3a22"))
	title.add_theme_constant_override("outline_size", Ui.PX * 2)
	var skip := Ui.button("Пропустить", Rect2(222, 590, 126, 40), "", self, true)
	skip.pressed.connect(_finish)
	_hint = Ui.label("Нажми, чтобы читать дальше", Rect2(10, 596, 210, 32), Ui.FONT_SIZE, Color("b8a58c"), self, HORIZONTAL_ALIGNMENT_LEFT, true)
	var blink := _hint.create_tween().set_loops()
	blink.tween_property(_hint, "modulate:a", 0.3, 0.7).set_trans(Tween.TRANS_SINE)
	blink.tween_property(_hint, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	_next()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_next()


func _next() -> void:
	if _busy:
		return
	if _index >= PANELS.size() - 1:
		_finish()
		return
	_busy = true
	_index += 1
	var old := _page
	_page = _build_page(PANELS[_index])
	_page.position = Vector2(360, 0)
	var t := create_tween().set_parallel(true)
	t.tween_property(_page, "position:x", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if old != null:
		t.tween_property(old, "position:x", -360.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(old.queue_free)
	get_tree().create_timer(0.45).timeout.connect(_after_slide)


func _after_slide() -> void:
	_busy = false
	_show_lines(_page, PANELS[_index])


func _finish() -> void:
	if GameState.intro_stage == 0:
		GameState.intro_stage = 1
		GameState.save_game()
	Nav.go(self, Nav.CITY)


## Страница: бумага с рамкой, кадр с обрезкой, подпись под кадром. Реплики появляются позже (_show_lines).
func _build_page(def: Dictionary) -> Node2D:
	var page := Node2D.new()
	add_child(page)
	var frame := ColorRect.new()
	frame.position = ART_POS - Vector2(14, 14)
	frame.size = ART_SIZE + Vector2(28, 126)
	frame.color = PAPER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(frame)
	var border := ColorRect.new()
	border.position = ART_POS - Vector2(6, 6)
	border.size = ART_SIZE + Vector2(12, 12)
	border.color = INK
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(border)
	var clip := Control.new()
	clip.position = ART_POS
	clip.size = ART_SIZE
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(clip)
	var art := Node2D.new()
	clip.add_child(art)
	call(String(def["build"]), art)
	var cap := Ui.label(String(def["caption"]), Rect2(ART_POS.x, ART_POS.y + ART_SIZE.y + 14, ART_SIZE.x, 64), Ui.FONT_SIZE, INK, page, HORIZONTAL_ALIGNMENT_CENTER, true)
	cap.modulate.a = 0.0
	cap.create_tween().tween_property(cap, "modulate:a", 1.0, 0.5).set_delay(0.3)
	page.set_meta("clip", clip)
	return page


## Реплики героев: пузырь с хвостиком выпрыгивает в кадре.
func _show_lines(page: Node2D, def: Dictionary) -> void:
	var clip: Control = page.get_meta("clip")
	var delay := 0.0
	for ln in def["lines"]:
		var b := Node2D.new()
		var text := String(ln["text"])
		var w := clampf(text.length() * 10.5 + 26.0, 100.0, 280.0)
		b.position = Vector2(clampf(float(ln["x"]), w / 2.0 + 4.0, ART_SIZE.x - w / 2.0 - 4.0), float(ln["y"]))
		clip.add_child(b)
		Ui.panel(Rect2(-w / 2.0, -20, w, 40), Ui.UI_CREAM, b)
		for i in 3:
			var tail := ColorRect.new()
			tail.position = Vector2(-8.0 + i * 2.0, 20 + i * 4)
			tail.size = Vector2(16 - i * 4, 4)
			tail.color = Color("fff0cd")
			tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(tail)
		Ui.label(text, Rect2(-w / 2.0, -16, w, 32), Ui.FONT_SIZE, INK, b, HORIZONTAL_ALIGNMENT_CENTER, true)
		Fx.pop_in(b, 0.45, delay)
		delay += 0.7


# ---------------------------------------------------------------- рисование кадров

func _r(art: Node2D, x: float, y: float, w: float, h: float, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(r)
	return r


func _spr(art: Node2D, tex: Texture2D, pos: Vector2, scale: float, region := Rect2()) -> Sprite2D:
	var s := Sprite2D.new()
	if region.size != Vector2.ZERO:
		s.texture = tex
		s.region_enabled = true
		s.region_rect = region
	else:
		s.texture = tex
	s.position = pos
	s.scale = Vector2(scale, scale)
	art.add_child(s)
	return s


func _cat(art: Node2D, view: String, pos: Vector2, scale: float, tint := Color.WHITE, flip := false) -> Sprite2D:
	var s := _spr(art, load("res://assets/cats/cat-waiter-%s.png" % view) as Texture2D, pos, scale, Rect2(0, 16, 16, 16))
	s.modulate = tint
	s.flip_h = flip
	return s


func _gradient(art: Node2D, top: Color, bottom: Color, steps := 14) -> void:
	for i in steps:
		_r(art, 0, i * ART_SIZE.y / steps, ART_SIZE.x, ART_SIZE.y / steps + 1, top.lerp(bottom, float(i) / (steps - 1)))


func _disc(art: Node2D, c: Vector2, r: float, color: Color) -> void:
	var y := -r
	while y < r:
		var half := floorf(sqrt(maxf(0.0, r * r - (y + 1.0) * (y + 1.0))) / 2.0) * 2.0
		_r(art, c.x - half, c.y + y, half * 2.0, 2.0, color)
		y += 2.0


func _halo(art: Node2D, pos: Vector2, size: Vector2, color: Color) -> void:
	art.add_child(Fx.pixel_light(pos, size, color))


## Панель 1: вечер дома, на столе ключ.
func _panel_home(art: Node2D) -> void:
	_gradient(art, Color("1b1830"), Color("33274a"))
	_r(art, 0, 150, ART_SIZE.x, 76, Color("4a3328"))             # пол
	_r(art, 0, 150, ART_SIZE.x, 4, Color("6a4a38"))
	for x in range(0, 296, 48):
		_r(art, x, 154, 2, 72, Color("3a281f"))
	_r(art, 214, 20, 56, 48, Color("2a2540"))                     # окно с луной
	_r(art, 218, 24, 48, 40, Color("141a3a"))
	_disc(art, Vector2(250, 40), 10, Color("f6f0c8"))
	_r(art, 242, 24, 2, 40, Color("2a2540"))
	# часы с тикающей стрелкой
	_disc(art, Vector2(40, 46), 16, Color("e8dcc0"))
	_disc(art, Vector2(40, 46), 12, Color("f8f0dc"))
	var hand := _r(art, 39, 36, 2, 10, INK)
	hand.pivot_offset = Vector2(1, 10)
	var tick := hand.create_tween().set_loops()
	tick.tween_property(hand, "rotation", TAU, 12.0)
	# стол, пуфик, кот, чашка, ключ
	var table := _spr(art, FURN, Vector2(200, 142), 4.0, Rect2(81, 81, 14, 15))
	table.offset = Vector2(0, -7.5)
	var stool := _spr(art, FURN, Vector2(120, 150), 4.0, Rect2(81, 66, 14, 13))
	stool.offset = Vector2(0, -6.5)
	var cat := _cat(art, "front", Vector2(124, 108), 4.0)
	var bob := cat.create_tween().set_loops()
	bob.tween_property(cat, "position:y", 104.0, 0.9).set_trans(Tween.TRANS_SINE)
	bob.tween_property(cat, "position:y", 108.0, 0.9).set_trans(Tween.TRANS_SINE)
	_spr(art, DRINKS, Vector2(180, 92), 2.0, Rect2(32, 16, 16, 16))
	var key := _spr(art, Fx.tex("key"), Vector2(210, 90), 3.0)
	var kb := key.create_tween().set_loops()
	kb.tween_property(key, "rotation", 0.12, 0.8).set_trans(Tween.TRANS_SINE)
	kb.tween_property(key, "rotation", -0.12, 0.8).set_trans(Tween.TRANS_SINE)
	_halo(art, Vector2(190, 110), Vector2(260, 200), Color(1.0, 0.75, 0.4, 0.45))
	var sp := Fx.burst(art, Vector2(210, 84), "sparkle", Color("fff3b0"), 4, 40.0, 0.0, 1.2, 0.8)
	sp.one_shot = false
	sp.explosiveness = 0.0
	Fx.motes(art, Rect2(60, 60, 200, 100), 12)


## Панель 2: улица на закате, кот идёт спиной.
func _panel_street(art: Node2D) -> void:
	_gradient(art, Color("5a3a7a"), Color("ff9a5a"), 16)
	_disc(art, Vector2(228, 128), 16, Color("ffd9a0"))
	_halo(art, Vector2(228, 128), Vector2(220, 160), Color(1.0, 0.7, 0.4, 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 6:   # силуэты домов с окнами
		var w := snappedf(rng.randf_range(36, 60), 2.0)
		var h := snappedf(rng.randf_range(60, 110), 2.0)
		var x := i * 52.0 - 8.0
		_r(art, x, 160 - h, w, h, Color("2e2040"))
		for wy in range(int(160 - h + 8), 150, 16):
			for wx in range(int(x + 6), int(x + w - 8), 14):
				if rng.randf() < 0.55:
					_r(art, wx, wy, 6, 8, Color("ffcf70"))
	for tx in range(0, 296, 32):   # тротуар из тайлов
		for ty in range(160, 226, 32):
			_spr(art, TILES, Vector2(tx + 16, ty + 16), 2.0, Rect2(0, 0, 16, 16)).modulate = Color(1.0, 0.82, 0.7)
	_r(art, 0, 160, ART_SIZE.x, 6, Color(0.3, 0.2, 0.3, 0.55))
	var lamp := _spr(art, LAMP, Vector2(56, 196), 2.0)
	lamp.offset = Vector2(0, -float(LAMP.get_height()) / 2.0)
	_halo(art, Vector2(56, 100), Vector2(120, 120), Color(1.0, 0.8, 0.45, 0.5))
	# кот идёт спиной слева направо
	var cat := _cat(art, "back", Vector2(40, 186), 4.0)
	var walk := cat.create_tween().set_loops()
	walk.tween_property(cat, "position:x", 210.0, 4.5)
	walk.tween_callback(func() -> void: cat.position.x = 40.0)
	var frames := cat.create_tween().set_loops()
	for i in 4:
		frames.tween_callback(func() -> void: cat.region_rect = Rect2(i * 16, 16, 16, 16))
		frames.tween_interval(0.14)
	var step := cat.create_tween().set_loops()
	step.tween_property(cat, "offset:y", -3.0, 0.14)
	step.tween_property(cat, "offset:y", 0.0, 0.14)


## Панель 3: фасад кафе снизу вверх — выцвел, паутина.
func _panel_facade(art: Node2D) -> void:
	_gradient(art, Color("4a3c6a"), Color("d98a6a"), 14)
	var bld := _spr(art, BUILDING, Vector2(-22, -96), 2.0)
	bld.centered = false
	bld.modulate = Color(0.62, 0.62, 0.7)
	_r(art, 70, 96, 156, 32, Color("3f2815"))                       # вывеска
	_r(art, 74, 100, 148, 24, Color("5a4a40"))
	var sign := Ui.label("Тёплая Лапка", Rect2(70, 98, 156, 28), Ui.FONT_SIZE, Color("9a8a78"), art, HORIZONTAL_ALIGNMENT_CENTER, true)
	sign.rotation = -0.02
	for x in [92, 196]:
		_r(art, x, 80, 2, 16, Color("4a4256"))
	_web(art, Vector2(6, 128), 1, 1, 24)
	_web(art, Vector2(290, 128), -1, 1, 24)
	_web(art, Vector2(150, 96), 1, 1, 16)
	var cat := _cat(art, "back", Vector2(148, 206), 3.0)
	cat.offset = Vector2(0, -8)
	var sway := cat.create_tween().set_loops()
	sway.tween_property(cat, "rotation", 0.04, 1.2).set_trans(Tween.TRANS_SINE)
	sway.tween_property(cat, "rotation", -0.04, 1.2).set_trans(Tween.TRANS_SINE)
	Fx.motes(art, Rect2(40, 90, 220, 120), 14)


## Паутина-веер из угла: dir_x/dir_y — куда расходятся нити.
func _web(art: Node2D, corner: Vector2, dir_x: int, dir_y: int, size_art: int) -> void:
	var w := PixelArt.sprite(PixelArt.web(size_art), corner, false)
	w.flip_h = dir_x < 0
	w.flip_v = dir_y < 0
	w.position = Vector2(corner.x - (size_art * 2.0 if dir_x < 0 else 0.0), corner.y - (size_art * 2.0 if dir_y < 0 else 0.0))
	w.modulate = Color(1, 1, 1, 0.92)
	art.add_child(w)


## Панель 4: крупно — заклинившая заслонка, ключ в лапе.
func _panel_lock(art: Node2D) -> void:
	_r(art, 0, 0, ART_SIZE.x, ART_SIZE.y, Color("2c2a33"))
	var shutter := Node2D.new()
	art.add_child(shutter)
	_draw_shutter(shutter, Rect2(18, 8, 260, 182), 0.0)
	var rattle := shutter.create_tween().set_loops()
	for i in 3:
		rattle.tween_property(shutter, "position:x", 5.0, 0.05)
		rattle.tween_property(shutter, "position:x", -5.0, 0.05)
	rattle.tween_property(shutter, "position:x", 0.0, 0.05)
	rattle.tween_interval(0.9)
	var cat := _cat(art, "side", Vector2(70, 170), 7.0)
	cat.offset = Vector2(0, -2)
	var key := _spr(art, Fx.tex("key"), Vector2(150, 150), 4.0)
	key.rotation = -0.8
	var kk := key.create_tween().set_loops()
	kk.tween_property(key, "rotation", -0.5, 0.12)
	kk.tween_property(key, "rotation", -0.9, 0.12)
	var onom := Ui.label("ДЁРГ!", Rect2(150, 70, 140, 56), Ui.FONT_SIZE_BIG, Color("ffd640"), art, HORIZONTAL_ALIGNMENT_CENTER, true)
	onom.add_theme_color_override("font_outline_color", Color("5b2a1a"))
	onom.add_theme_constant_override("outline_size", 8)
	onom.pivot_offset = Vector2(70, 28)
	onom.rotation = -0.14
	var pulse := onom.create_tween().set_loops()
	pulse.tween_property(onom, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK)
	pulse.tween_property(onom, "scale", Vector2.ONE, 0.18)
	pulse.tween_interval(0.6)


## Пиксельная заслонка в кадре: lift 0..1 — насколько поднята.
func _draw_shutter(root: Node2D, rect: Rect2, lift: float) -> void:
	var w_art := int(rect.size.x / 2.0)
	var h_art := int(rect.size.y / 2.0)
	var vis := int(round(h_art * (1.0 - lift)))
	var slats := PixelArt.sprite(PixelArt.shutter(w_art, h_art), rect.position, false)
	slats.region_enabled = true
	slats.region_rect = Rect2(0, 0, w_art, maxi(vis - 5, 0))
	root.add_child(slats)
	var bar := PixelArt.sprite(PixelArt.shutter_bar(w_art), Vector2(rect.position.x, rect.position.y + maxi(vis - 5, 0) * 2.0), false)
	root.add_child(bar)


## Панель 5: заслонка приподнята, свет и пыль, Мяу улыбается, у стены хмурый Тучка.
func _panel_decision(art: Node2D) -> void:
	_r(art, 0, 0, ART_SIZE.x, ART_SIZE.y, Color("2c2a33"))
	var warm := Polygon2D.new()
	warm.polygon = PackedVector2Array([Vector2(18, 70), Vector2(278, 70), Vector2(278, 226), Vector2(18, 226)])
	warm.color = Color("ffd98a")
	art.add_child(warm)
	_halo(art, Vector2(148, 150), Vector2(300, 190), Color(1.0, 0.9, 0.6, 0.55))
	var sh := Node2D.new()
	art.add_child(sh)
	_draw_shutter(sh, Rect2(18, 8, 260, 182), 0.62)
	var cloud := Fx.steam(art, Vector2(148, 150), 14)
	cloud.lifetime = 2.2
	cloud.initial_velocity_max = 40.0
	cloud.spread = 80.0
	cloud.scale_amount_max = 4.0
	cloud.emission_sphere_radius = 40.0
	cloud.emitting = true
	var mya := _cat(art, "front", Vector2(80, 172), 6.0)
	Fx.squash_hop(mya, 8.0)
	var hop := mya.create_tween().set_loops()
	hop.tween_interval(1.4)
	hop.tween_callback(func() -> void: Fx.squash_hop(mya, 10.0))
	var tucha := load("res://assets/cats/cat-black-front.png") as Texture2D
	var t := _spr(art, tucha, Vector2(228, 178), 4.0, Rect2(0, 16, 16, 16))
	var grump := _r(art, 204, 118, 44, 14, Color("6a6a78"))   # «личное облачко» над Тучкой
	grump.modulate.a = 0.9
	_r(art, 212, 112, 28, 8, Color("6a6a78"))
	Fx.burst(art, Vector2(150, 60), "sparkle", Color("fff3b0"), 8, 80.0, 20.0, 1.4, 1.0)
