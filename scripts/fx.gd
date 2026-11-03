class_name Fx
extends RefCounted
## Эффекты в пиксельном стиле: частицы (сердечки, звёздочки, монеты, пар, конфетти), «поп» и тряска узлов,
## кольца-волны, летящие монеты, баннеры. Текстуры частиц рисуются из ASCII-карт и красятся через color/modulate.
## Масштаб как у всей графики: 1 пиксель арта = PX логических.

const PX := 2.0

const ART := {
	"heart": [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."],
	"star": ["...#...", "...#...", "..###..", "#######", "..###..", ".##.##.", ".#...#."],
	"sparkle": ["..#..", "..#..", "#####", "..#..", "..#.."],
	"drop": [".#.", "###", "###", ".#."],
	"puff": ["#..#", ".##.", ".##.", "#..#"],
	"dot": ["##", "##"],
	"confetti": ["###", "###"],
	"coin": ["..YY..", ".YhhY.", "YhYYoY", "YhYYoY", ".YooY.", "..YY.."],
	"zzz": ["####", "..#.", ".#..", "####"],
	"sweat": [".#.", "###", "###", ".#."],
	"note": ["..###", "..#.#", "..#.#", "###.#", "##..."],
}
const PALETTE := {"#": Color.WHITE, "Y": Color("ffd640"), "o": Color("d69620"), "h": Color("fff4aa")}

static var _cache := {}


## Текстура частицы по имени из ART (кэшируется).
static func tex(name: String) -> ImageTexture:
	if _cache.has(name):
		return _cache[name]
	var rows: Array = ART[name]
	var img := Image.create(String(rows[0]).length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			var ch := row[x]
			if PALETTE.has(ch):
				img.set_pixel(x, y, PALETTE[ch])
	var t := ImageTexture.create_from_image(img)
	_cache[name] = t
	return t


## Мягкое круглое свечение (для additive-спрайтов).
static func halo_tex() -> GradientTexture2D:
	if _cache.has("halo"):
		return _cache["halo"]
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_cache["halo"] = t
	return t


static func additive() -> CanvasItemMaterial:
	if _cache.has("add"):
		return _cache["add"]
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_cache["add"] = m
	return m


# ---------------------------------------------------------------- частицы

## Разовый всплеск частиц (сердечки, звёзды, капли...). direction — куда летит основная масса, spread — разброс в градусах.
static func burst(parent: Node, pos: Vector2, tex_name: String, color: Color, count: int, speed: float, gravity := 220.0, life := 0.9, size := 1.0, spread := 180.0, dir := Vector2.UP) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex(tex_name)
	p.position = pos
	p.one_shot = true
	p.amount = count
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.scale_amount_min = PX * size * 0.8
	p.scale_amount_max = PX * size * 1.25
	var g := Gradient.new()
	g.colors = PackedColorArray([color, Color(color, 0.0)])
	g.offsets = PackedFloat32Array([0.55, 1.0])
	p.color_ramp = g
	p.z_index = 40
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Конфетти: случайные яркие цвета.
static func confetti(parent: Node, pos: Vector2, count := 28) -> CPUParticles2D:
	var p := burst(parent, pos, "confetti", Color.WHITE, count, 340.0, 420.0, 1.5, 1.0, 70.0, Vector2.UP)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("ff6b8b"), Color("ffd640"), Color("6bd5ff"), Color("8dff7a"), Color("c48bff")])
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	p.color_initial_ramp = g
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	return p


## Непрерывный пар (включается/выключается через emitting).
static func steam(parent: Node, pos: Vector2, amount := 7) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex("puff")
	p.position = pos
	p.amount = amount
	p.lifetime = 1.7
	p.direction = Vector2.UP
	p.spread = 14.0
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 26.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = PX * 0.9
	p.scale_amount_max = PX * 1.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	p.color_ramp = g
	p.emitting = false
	p.z_index = 20
	parent.add_child(p)
	return p


## Пылинки в луче света: медленно плавают и мерцают.
static func motes(parent: Node, rect: Rect2, amount := 16) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex("dot")
	p.position = rect.get_center()
	p.amount = amount
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.direction = Vector2(-0.3, 1.0)
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = PX * 0.5
	p.scale_amount_max = PX * 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = rect.size / 2.0
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.95, 0.75, 0.0), Color(1, 0.95, 0.75, 0.75), Color(1, 0.95, 0.75, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.color_ramp = g
	p.z_index = 1
	parent.add_child(p)
	return p


# ---------------------------------------------------------------- анимации узлов

## «Поп»: узел резко увеличивается и пружинит обратно.
static func pop(n: Node2D, from := 1.3, time := 0.45) -> void:
	var base := n.scale
	n.scale = base * from
	var t := n.create_tween()
	t.tween_property(n, "scale", base, time).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Появление: из нуля с пружиной.
static func pop_in(n: Node2D, time := 0.5, delay := 0.0) -> void:
	var base := n.scale
	n.scale = Vector2.ZERO
	var t := n.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(n, "scale", base, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Сплющивание-растяжение прыжка (по спрайту) + подскок.
static func squash_hop(n: Node2D, height := 18.0) -> void:
	var base_s := n.scale
	var base_y := n.position.y
	var t := n.create_tween()
	t.tween_property(n, "scale", Vector2(base_s.x * 1.18, base_s.y * 0.82), 0.08)
	t.tween_property(n, "scale", Vector2(base_s.x * 0.88, base_s.y * 1.16), 0.10)
	t.parallel().tween_property(n, "position:y", base_y - height, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(n, "position:y", base_y, 0.14).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(n, "scale", base_s, 0.14)


## Тряска по горизонтали (отрицательный ответ «нет» или удар).
static func shake(n: Node2D, amp := 6.0, time := 0.35, shakes := 6) -> void:
	var base := n.position
	var t := n.create_tween()
	for i in shakes:
		var k := 1.0 - float(i) / float(shakes)
		t.tween_property(n, "position:x", base.x + (amp if i % 2 == 0 else -amp) * k, time / shakes)
	t.tween_property(n, "position", base, 0.03)


## Кольцо-волна, расходящееся от точки (пиксельное).
static func ring(parent: Node, pos: Vector2, color: Color, max_radius := 56.0, time := 0.45) -> void:
	var r := Ring.new()
	r.position = pos
	r.color = color
	r.z_index = 30
	parent.add_child(r)
	var t := r.create_tween().set_parallel(true)
	t.tween_property(r, "radius", max_radius, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(r, "alpha", 0.0, time)
	t.chain().tween_callback(r.queue_free)


## Монеты летят дугой от точки к точке (HUD-счётчику). on_land вызывается на каждой монете.
static func coins_fly(parent: Node, from: Vector2, to: Vector2, count: int, on_land: Callable) -> void:
	for i in count:
		var s := Sprite2D.new()
		s.texture = tex("coin")
		s.scale = Vector2(PX, PX)
		s.position = from
		s.z_index = 60
		s.visible = false
		parent.add_child(s)
		var mid := (from + to) / 2.0 + Vector2(randf_range(-70.0, 70.0), -randf_range(70.0, 130.0))
		var t := s.create_tween()
		t.tween_interval(0.07 * i)
		t.tween_callback(func() -> void: s.visible = true)
		var step := func(u: float) -> void:
			s.position = from.lerp(mid, u).lerp(mid.lerp(to, u), u)
			s.scale = Vector2(PX * absf(cos(u * TAU * 2.0)) + 0.4, PX)
		t.tween_method(step, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_callback(func() -> void:
			on_land.call()
			s.queue_free())


## Крупная надпись: выпрыгивает, зависает и улетает вверх.
static func banner(parent: Node, text: String, pos: Vector2, color: Color, outline := Ui.INK) -> void:
	var l := Ui.label(text, Rect2(pos - Vector2(170, 24), Vector2(340, 48)), Ui.FONT_SIZE_BIG, color, parent, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 8)
	l.pivot_offset = Vector2(170, 24)
	l.z_index = 90
	l.scale = Vector2.ZERO
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.55)
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 40.0, 0.5)
	t.tween_property(l, "modulate:a", 0.0, 0.5)
	t.chain().tween_callback(l.queue_free)


## Пульсирующее свечение вокруг узла (возвращает спрайт, чтобы его можно было убрать).
static func glow(parent: Node, pos: Vector2, size: Vector2, color: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = halo_tex()
	s.position = pos
	s.scale = size / 128.0
	s.modulate = Color(color, 0.0)
	s.material = additive()
	parent.add_child(s)
	var t := s.create_tween().set_loops()
	t.tween_property(s, "modulate:a", 0.55, 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(s, "modulate:a", 0.2, 0.5).set_trans(Tween.TRANS_SINE)
	return s


## Пиксельное кольцо (рисуется квадратиками по сетке 2 px).
class Ring extends Node2D:
	var radius := 4.0:
		set(v):
			radius = v
			queue_redraw()
	var alpha := 1.0:
		set(v):
			alpha = v
			queue_redraw()
	var color := Color.WHITE

	func _draw() -> void:
		var n := maxi(12, int(radius * 0.9))
		for i in n:
			var a := TAU * i / n
			var p := Vector2(roundf(cos(a) * radius / 2.0) * 2.0, roundf(sin(a) * radius / 2.0) * 2.0)
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color(color, alpha))
