class_name Fx
extends RefCounted
## Эффекты в пиксельном стиле: частицы (сердечки, звёздочки, монеты, пар, конфетти), «поп» и тряска узлов,
## кольца-волны, летящие монеты, баннеры. Текстуры частиц рисуются из ASCII-карт и красятся через color/modulate.
## Масштаб как у всей графики: 1 пиксель арта = PX логических.

const PX_GRID := 4.0   # пиксель арта «крупного плана» (мини-игра): спрайты там ×4
const PX := 2.0

## Размер «пикселя эффектов» в текущей сцене (логических px). Не меньше пикселя игры: в городе 2, в мини-игре готовки (спрайты ×4) — 4.
## Сцена ставит его при старте и возвращает 2 при выходе. Все частицы, кольца, монеты и свечения считаются от него.
static var unit := 2.0

const ART := {
	"heart": [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."],
	"star": ["...#...", "...#...", "..###..", "#######", "..###..", ".##.##.", ".#...#."],
	"sparkle": ["..#..", "..#..", "#####", "..#..", "..#.."],
	"drop": [".#.", "###", "###", ".#."],
	"puff": ["#..#", ".##.", ".##.", "#..#"],
	"dot": ["##", "##"],
	"mote": ["#"],
	"confetti": ["###", "###"],
	"coin": ["..YY..", ".YhhY.", "YhYYoY", "YhYYoY", ".YooY.", "..YY.."],
	"zzz": ["####", "..#.", ".#..", "####"],
	"sweat": [".#.", "###", "###", ".#."],
	"note": ["..###", "..#.#", "..#.#", "###.#", "##..."],
	"key": ["..YYY..", ".Yh..Y.", ".Y...Y.", "..YYY..", "...Y...", "...YY..", "...Y...", "...YY..", "...Y..."],
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
	var k := maxf(1.0, roundf(size))   # целое число пикселей сетки: частица не мельче пикселя игры
	p.scale_amount_min = unit * k
	p.scale_amount_max = unit * k
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
	p.scale_amount_min = unit
	p.scale_amount_max = unit
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
	p.texture = tex("mote")
	p.position = rect.get_center()
	p.amount = amount
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.direction = Vector2(-0.3, 1.0)
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = unit
	p.scale_amount_max = unit
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


## Подскок на месте строго по сетке: узел не масштабируется и не вращается, высота кратна step.
static func hop(n: Node2D, height := 8.0, time := 0.3, step := 4.0) -> void:
	var base_y := n.position.y
	var t := n.create_tween()
	t.tween_method(func(u: float) -> void: n.position.y = base_y - snappedf(sin(u * PI) * height, step), 0.0, 1.0, time)
	t.tween_callback(func() -> void: n.position.y = base_y)


## Появление «выезжает снизу» шагами по сетке (без масштаба) + проявление.
static func rise_in(n: CanvasItem, dy := 16.0, time := 0.3, step := 4.0) -> void:
	var base: Vector2 = n.position
	n.modulate.a = 0.0
	var t := n.create_tween()
	t.tween_method(func(u: float) -> void:
		n.position = base + Vector2(0, snappedf(dy * (1.0 - u), step))
		n.modulate.a = 1.0 if u > 0.25 else 0.0, 0.0, 1.0, time)
	t.tween_callback(func() -> void:
		n.position = base
		n.modulate.a = 1.0)


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
static func shake(n: Node2D, amp := 6.0, time := 0.35, shakes := 6, step := 2.0) -> void:
	var base := n.position
	var t := n.create_tween()
	for i in shakes:
		var k := 1.0 - float(i) / float(shakes)
		t.tween_property(n, "position:x", base.x + snappedf((amp if i % 2 == 0 else -amp) * k, step), time / shakes)
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
		s.scale = Vector2(unit, unit)
		s.position = from
		s.z_index = 60
		s.visible = false
		parent.add_child(s)
		var mid := (from + to) / 2.0 + Vector2(randf_range(-70.0, 70.0), -randf_range(70.0, 130.0))
		var t := s.create_tween()
		t.tween_interval(0.07 * i)
		t.tween_callback(func() -> void: s.visible = true)
		var step := func(u: float) -> void:
			var pos := from.lerp(mid, u).lerp(mid.lerp(to, u), u)
			s.position = Vector2(snappedf(pos.x, unit), snappedf(pos.y, unit))
			s.flip_h = int(u * 6.0) % 2 == 1   # «вращение» монеты зеркалом, без дробного масштаба
		t.tween_method(step, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_callback(func() -> void:
			on_land.call()
			s.queue_free())


## Крупная надпись: выезжает снизу шагами по сетке, зависает и улетает вверх (без масштаба).
static func banner(parent: Node, text: String, pos: Vector2, color: Color, outline := Ui.INK) -> void:
	var l := Ui.label(text, Rect2(pos - Vector2(170, 24), Vector2(340, 48)), Ui.FONT_SIZE_BIG, color, parent, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 8)
	l.z_index = 90
	var base_y := l.position.y
	var t := l.create_tween()
	t.tween_method(func(u: float) -> void:
		l.position.y = base_y + snappedf(24.0 * (1.0 - u), 4.0)
		l.modulate.a = 1.0 if u > 0.2 else 0.0, 0.0, 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.55)
	t.tween_method(func(u: float) -> void:
		l.position.y = base_y - snappedf(40.0 * u, 4.0)
		l.modulate.a = 1.0 - u, 0.0, 1.0, 0.5)
	t.tween_callback(l.queue_free)


## Пиксельное свечение: постеризованное, с дизерингом; размер size — в логических px (диаметры по x и y), позиция привязана к сетке арта.
static func pixel_light(pos: Vector2, size: Vector2, color: Color, levels := 4, power := 1.5) -> Sprite2D:
	var rx := maxi(2, roundi(size.x / (2.0 * unit)))
	var ry := maxi(2, roundi(size.y / (2.0 * unit)))
	var s := PixelArt.sprite(PixelArt.glow(rx, ry, levels, power), pos, true, unit)
	s.modulate = color
	s.material = additive()
	return s


## Пульсирующее пиксельное свечение вокруг точки (возвращает спрайт, чтобы его можно было убрать).
static func glow(parent: Node, pos: Vector2, size: Vector2, color: Color) -> Sprite2D:
	var s := pixel_light(pos, size, Color(color, 0.0))
	parent.add_child(s)
	var t := s.create_tween().set_loops()
	t.tween_property(s, "modulate:a", 0.6, 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(s, "modulate:a", 0.25, 0.5).set_trans(Tween.TRANS_SINE)
	return s


## Пиксельное кольцо (квадратики по сетке эффектов: сторона 2 unit).
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
		var u := Fx.unit
		var n := maxi(12, int(radius * 0.9 / (u / 2.0)))
		for i in n:
			var a := TAU * i / n
			var p := Vector2(roundf(cos(a) * radius / u) * u, roundf(sin(a) * radius / u) * u)
			draw_rect(Rect2(p - Vector2(u, u), Vector2(u * 2.0, u * 2.0)), Color(color, alpha))
