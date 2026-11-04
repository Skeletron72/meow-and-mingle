class_name PixelArt
extends RefCounted
## Настоящий пиксель-арт, рисуемый кодом: всё создаётся как Image в разрешении АРТА (1 пиксель = 1 пиксель арта) и показывается
## спрайтом в масштабе 2 с nearest-фильтром — без сглаживания и «грязных» полутонов. Градиенты (свечение, тени, лучи) —
## постеризованные, с упорядоченным дизерингом Байера. Результаты кэшируются.
##
## Все текстуры свечения/теней — белые или чёрные с альфой-уровнями; цвет и общая сила задаются modulate.

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var _cache := {}


## Порог дизеринга 0..1 для пикселя (x, y).
static func bayer(x: int, y: int) -> float:
	return (float(BAYER[(y & 3) * 4 + (x & 3)]) + 0.5) / 16.0


static func image(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			put(img, xx, yy, c)


## Линия Брезенхэма: ровно по пикселям, без сглаживания.
static func line(img: Image, a: Vector2i, b: Vector2i, c: Color) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		put(img, p.x, p.y, c)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy


## Рисунок из строк («пиксель-арт текстом»): palette — символ → цвет, «.» — прозрачно. Все строки одной длины.
static func from_rows(rows: Array, palette: Dictionary) -> ImageTexture:
	var img := image(String(rows[0]).length(), rows.size())
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			var ch := row.substr(x, 1)
			if palette.has(ch):
				put(img, x, y, palette[ch])
	return texture(img)


## Иконки источников на прилавке: пакет молока и бутылка сиропа (16×16, обводка и свет — как у остальных спрайтов).
static func shelf_icon(kind: String) -> ImageTexture:
	var pal := {"o": Color("3b2a3d"), "w": Color("f4ecd8"), "s": Color("d3c5a6"), "b": Color("5b8fd9"), "r": Color("c0392b"), "d": Color("8a2a20"), "h": Color("ee7a68"), "g": Color("e8c15a")}
	if kind == "milk":
		return from_rows([
			"................", "....oooooooo....", "...obbbbbbbbo...", "..obbbbbbbbbbo..", "..oooooooooooo..", "..owwwwwwwwwso..", "..owwwwwwwwwso..", "..owwbbbbbwwso..",
			"..owwbwwwbwwso..", "..owwbbbbbwwso..", "..owwwwwwwwwso..", "..owwwwwwwwwso..", "..owwwwwwwwwso..", "..osssssssssso..", "..oooooooooooo..", "................"], pal)
	return from_rows([
		"................", ".......oo.......", "......oggo......", "......oggo......", ".....oooooo.....", "....orrrrrro....", "...orrhrrrrro...", "..orrhrrrrrrro..",
		"..orrhrrwwrrro..", "..orrrrwwwwrro..", "..orrrrrwwrrro..", "..orrrrrrrrrdo..", "..odrrrrrrrddo..", "...oddddddddo...", "....oooooooo....", "................"], pal)


static func texture(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- декор

## Паутина в левом верхнем углу size×size (другие углы — отражением спрайта): лучи и провисающие дуги пиксельными линиями.
static func web(size: int) -> ImageTexture:
	var key := "web%d" % size
	if _cache.has(key):
		return _cache[key]
	var img := image(size, size)
	var white := Color(0.94, 0.95, 0.98, 1.0)
	var grey := Color(0.70, 0.73, 0.80, 1.0)
	var far := float(size - 1)
	var rays := 5
	for i in rays:
		var a := PI / 2.0 * float(i) / float(rays - 1)
		line(img, Vector2i.ZERO, Vector2i(roundi(cos(a) * far), roundi(sin(a) * far)), white)
	for ring in [0.38, 0.66, 0.94]:
		var prev := Vector2i.ZERO
		for i in rays:
			var a := PI / 2.0 * float(i) / float(rays - 1)
			var sag := 0.9 + 0.06 * sin(i * 2.3)
			var p := Vector2i(roundi(cos(a) * far * ring * sag), roundi(sin(a) * far * ring * sag))
			if i > 0:
				line(img, prev, p, grey if ring < 0.9 else white)
			prev = p
	_cache[key] = texture(img)
	return _cache[key]


## Пыльное пятно w×h: чем меньше `level` (1.0 → 0.5), тем реже пиксели — пыль убирается постепенно.
static func dust(w: int, h: int, seed_id: int, level: float) -> ImageTexture:
	var key := "dust%d_%d_%d_%.2f" % [w, h, seed_id, level]
	if _cache.has(key):
		return _cache[key]
	var img := image(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_id
	var tones := [Color(0.67, 0.62, 0.55), Color(0.56, 0.51, 0.45), Color(0.76, 0.71, 0.63)]
	for y in h:
		for x in w:
			var dx := (x + 0.5 - w / 2.0) / (w / 2.0)
			var dy := (y + 0.5 - h / 2.0) / (h / 2.0)
			var rank := rng.randf()
			var edge := 1.0 - clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			if edge > 0.0 and rank < edge * 0.85 * level:
				put(img, x, y, tones[rng.randi() % 3])
	_cache[key] = texture(img)
	return _cache[key]


## Рифлёная заслонка w×h пикселей арта: полосы по 6 px (блик, тело, тень, шов), ржавчина и царапины.
static func shutter(w: int, h: int) -> ImageTexture:
	var key := "shutter%d_%d" % [w, h]
	if _cache.has(key):
		return _cache[key]
	var img := image(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for y in h:
		var row := y % 6
		var odd := (y / 6) % 2 == 1
		var base := Color(0.55, 0.57, 0.63) if not odd else Color(0.49, 0.51, 0.57)
		var c := base
		match row:
			0: c = base.lightened(0.28)
			4: c = base.darkened(0.2)
			5: c = base.darkened(0.42)
		for x in w:
			put(img, x, y, c)
	for _i in 26:   # ржавчина
		var rx := rng.randi_range(0, w - 5)
		var ry := rng.randi_range(0, h - 3)
		var rw := rng.randi_range(1, 4)
		for xx in rw:
			put(img, rx + xx, ry, Color(0.54, 0.36, 0.22) if rng.randf() < 0.7 else Color(0.42, 0.27, 0.17))
	for _i in 8:   # вертикальные царапины
		var sx := rng.randi_range(2, w - 3)
		var sy := rng.randi_range(0, h - 6)
		for yy in rng.randi_range(2, 5):
			put(img, sx, sy + yy, Color(0.4, 0.42, 0.48))
	_cache[key] = texture(img)
	return _cache[key]


## Нижняя планка заслонки с ручкой-замком.
static func shutter_bar(w: int) -> ImageTexture:
	var key := "shbar%d" % w
	if _cache.has(key):
		return _cache[key]
	var img := image(w, 5)
	rect(img, 0, 0, w, 5, Color(0.30, 0.32, 0.37))
	rect(img, 0, 0, w, 1, Color(0.46, 0.48, 0.54))
	rect(img, w / 2 - 8, 1, 16, 4, Color(0.19, 0.2, 0.23))
	rect(img, w / 2 - 2, 2, 4, 2, Color(0.62, 0.55, 0.3))
	_cache[key] = texture(img)
	return _cache[key]


## Складчатое покрывало w×h на стойке.
static func cover(w: int, h: int) -> ImageTexture:
	var key := "cover%d_%d" % [w, h]
	if _cache.has(key):
		return _cache[key]
	var img := image(w, h)
	var poly := PackedVector2Array([Vector2(0, 4), Vector2(w * 0.25, 0), Vector2(w * 0.72, 2), Vector2(w - 1, 0), Vector2(w, h), Vector2(0, h)])
	for y in h:
		for x in w:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				put(img, x, y, Color(0.80, 0.78, 0.72) if (x / 3 + y / 5) % 2 == 0 else Color(0.76, 0.74, 0.68))
	for fx in [w * 0.15, w * 0.35, w * 0.6, w * 0.82]:   # складки
		line(img, Vector2i(roundi(fx), 3), Vector2i(roundi(fx) - 2, h - 3), Color(0.58, 0.56, 0.52))
	for x in w:
		put(img, x, h - 1, Color(0.52, 0.5, 0.46))
		put(img, x, h - 2, Color(0.64, 0.62, 0.58))
	_cache[key] = texture(img)
	return _cache[key]


## Шторка на окне w×h: складки и блики.
static func curtain(w: int, h: int) -> ImageTexture:
	var key := "curtain%d_%d" % [w, h]
	if _cache.has(key):
		return _cache[key]
	var img := image(w, h)
	for y in h:
		for x in w:
			var fold := (x / 4) % 2 == 0
			var c := Color(0.36, 0.33, 0.41) if fold else Color(0.28, 0.25, 0.33)
			if x % 4 == 0:
				c = c.lightened(0.18)
			put(img, x, y, c)
	for x in w:
		put(img, x, 0, Color(0.5, 0.45, 0.35))
		put(img, x, h - 1, Color(0.2, 0.18, 0.24))
	_cache[key] = texture(img)
	return _cache[key]


## Случайные тёмные пиксели (грязь на кофемашине): density 0..1.
static func noise(w: int, h: int, color: Color, density: float, seed_id: int) -> ImageTexture:
	var key := "noise%d_%d_%d_%.2f" % [w, h, seed_id, density]
	if _cache.has(key):
		return _cache[key]
	var img := image(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_id
	for y in h:
		for x in w:
			if rng.randf() < density:
				put(img, x, y, color.darkened(rng.randf() * 0.25))
	_cache[key] = texture(img)
	return _cache[key]


# ---------------------------------------------------------------- свет и тени (белые/чёрные, дизеринг)

static func _level(t: float, levels: int, x: int, y: int) -> float:
	return clampf(floorf(t * float(levels) + bayer(x, y)), 0.0, float(levels)) / float(levels)


## Эллиптическое свечение rx×ry (радиусы в пикселях арта): постеризовано на `levels` уровней с дизерингом. Белое с альфой.
static func glow(rx: int, ry: int, levels := 4, power := 1.5) -> ImageTexture:
	var key := "glow%d_%d_%d_%.1f" % [rx, ry, levels, power]
	if _cache.has(key):
		return _cache[key]
	var img := image(rx * 2, ry * 2)
	for y in ry * 2:
		for x in rx * 2:
			var dx := (x + 0.5 - rx) / rx
			var dy := (y + 0.5 - ry) / ry
			var t := pow(clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0), power)
			var a := _level(t, levels, x, y)
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	_cache[key] = texture(img)
	return _cache[key]


## Конус света (фары), направлен вправо: длина len, половина раскрытия на конце half_h.
static func cone(length: int, half_h: int, levels := 4) -> ImageTexture:
	var key := "cone%d_%d_%d" % [length, half_h, levels]
	if _cache.has(key):
		return _cache[key]
	var img := image(length, half_h * 2)
	for x in length:
		var tx := float(x) / float(length)
		var half := maxf(1.0, half_h * (0.25 + 0.75 * tx))
		for y in half_h * 2:
			var dy := absf(y + 0.5 - half_h)
			if dy <= half:
				var t := pow(1.0 - tx, 1.2) * (1.0 - dy / half * 0.6)
				var a := _level(t, levels, x, y)
				if a > 0.0:
					img.set_pixel(x, y, Color(1, 1, 1, a))
	_cache[key] = texture(img)
	return _cache[key]


## Косой луч света (параллелограмм): сверху шире/ярче, вниз затухает; shear — на сколько пикселей уезжает низ.
static func beam(w: int, h: int, shear: int, levels := 4) -> ImageTexture:
	var key := "beam%d_%d_%d" % [w, h, shear]
	if _cache.has(key):
		return _cache[key]
	var img := image(w + absi(shear), h)
	for y in h:
		var off := roundi(float(shear) * float(y) / float(h)) + (0 if shear >= 0 else absi(shear))
		var fall := 1.0 - float(y) / float(h) * 0.85
		for x in w:
			var edge := minf(float(x), float(w - 1 - x)) / (w * 0.5)
			var t := fall * clampf(edge * 2.2, 0.0, 1.0)
			var a := _level(t, levels, x + off, y)
			if a > 0.0:
				put(img, x + off, y, Color(1, 1, 1, a))
	_cache[key] = texture(img)
	return _cache[key]


## Дизеринг-градиент w×h (чёрный): по оси y — сверху плотный, вниз пропадает; flip — наоборот; horizontal — по x.
static func dither_gradient(w: int, h: int, horizontal := false, flip := false, levels := 4) -> ImageTexture:
	var key := "dg%d_%d_%s_%s_%d" % [w, h, horizontal, flip, levels]
	if _cache.has(key):
		return _cache[key]
	var img := image(w, h)
	for y in h:
		for x in w:
			var t := float(x) / float(w) if horizontal else float(y) / float(h)
			t = t if flip else 1.0 - t
			var a := _level(t, levels, x, y)
			if a > 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, a))
	_cache[key] = texture(img)
	return _cache[key]


## Пятно тени-эллипс rx×ry (чёрное, дизеринг) — под предметами, котами, мебелью.
static func blob(rx: int, ry: int, levels := 3) -> ImageTexture:
	var key := "blob%d_%d_%d" % [rx, ry, levels]
	if _cache.has(key):
		return _cache[key]
	var img := image(rx * 2, ry * 2)
	for y in ry * 2:
		for x in rx * 2:
			var dx := (x + 0.5 - rx) / rx
			var dy := (y + 0.5 - ry) / ry
			var t := clampf(1.3 - sqrt(dx * dx + dy * dy) * 1.3, 0.0, 1.0)
			var a := _level(t, levels, x, y)
			if a > 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, a))
	_cache[key] = texture(img)
	return _cache[key]


## Спрайт из текстуры арта в масштабе px (по умолчанию 2; центрирован; позиция привязывается к сетке).
static func sprite(tex: Texture2D, pos: Vector2, centered := true, px := 2.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2(px, px)
	s.centered = centered
	s.position = Vector2(roundf(pos.x / px) * px, roundf(pos.y / px) * px)
	return s


## Вывеска кафе: название «ТЁПЛАЯ ЛАПКА» собственным пиксельным шрифтом 5×7 (кириллица, только нужные буквы) и лапки по бокам.
## Размер 104×8 — ровно серая доска на фасаде (building4.png: x 33..136, y 101..108); текст стоит на рядах 0..6.
const SIGN_GLYPHS := {
	"Т": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"Ё": [".#.#.", "#####", "#....", "####.", "#....", "#....", "#####"],
	"П": ["#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#"],
	"Л": ["..###", ".#..#", ".#..#", ".#..#", "#...#", "#...#", "#...#"],
	"А": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"Я": [".####", "#...#", "#...#", ".####", "..#.#", ".#..#", "#...#"],
	"К": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	" ": ["...", "...", "...", "...", "...", "...", "..."],
}
const SIGN_PAW := ["..#.#..", ".......", "#.....#", "..###..", ".#####.", ".#####.", "..###.."]


static func sign_texture(text: String, w := 104, h := 8) -> ImageTexture:
	var key := "sign_%s_%d_%d" % [text, w, h]
	if _cache.has(key):
		return _cache[key]
	var img := image(w, h)
	var ink := Color("202e37")
	var total := 0
	for ch in text:
		total += (SIGN_GLYPHS[ch][0] as String).length() + 1
	total -= 1
	var paw_w := 7
	var span := paw_w + 3 + total + 3 + paw_w
	var x := (w - span) / 2
	_draw_pattern(img, SIGN_PAW, x, 0, Color("c9573a"))
	x += paw_w + 3
	for ch in text:
		var g: Array = SIGN_GLYPHS[ch]
		_draw_pattern(img, g, x, 0, ink)
		x += (g[0] as String).length() + 1
	x += 2
	_draw_pattern(img, SIGN_PAW, x, 0, Color("c9573a"))
	_cache[key] = texture(img)
	return _cache[key]


static func _draw_pattern(img: Image, rows: Array, ox: int, oy: int, c: Color) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				put(img, ox + x, oy + y, c)
