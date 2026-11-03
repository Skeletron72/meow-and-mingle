class_name WeatherIcons
extends RefCounted
## Пиксельные значки погоды 13×13 (рисуются кодом): авто (облако с солнцем), ясно, дождь, туман, жара, снег.
## Тёмная обводка в один пиксель — значок читается и на терракотовой кнопке. Показываются в масштабе 2, как вся графика интерфейса.

const OL := Color("2b2230")
static var _cache := {}


static func icon(kind: int) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]
	var img := Image.create(13, 13, false, Image.FORMAT_RGBA8)
	match kind:
		-1: _sun(img, 4, 4, 3, Color("ffd640"), Color("ffb020")); _cloud(img, 1, 5, Color("f4f8ff"), Color("b9c8e0"))
		0: _sun(img, 6, 6, 4, Color("ffd640"), Color("ffb020"))
		1: _cloud(img, 0, 1, Color("c9d2e4"), Color("8c9ab8")); _drops(img)
		2: _fog(img)
		3: _sun(img, 6, 5, 4, Color("ff9a3a"), Color("ff5a2a")); _waves(img)
		4: _flake(img)
	var t := ImageTexture.create_from_image(img)
	_cache[kind] = t
	return t


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


## Диск радиуса r с обводкой и лучами.
static func _sun(img: Image, cx: int, cy: int, r: int, fill: Color, ray: Color) -> void:
	for a: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		_px(img, cx + a.x * (r + 2), cy + a.y * (r + 2), ray)
		if a.x == 0 or a.y == 0:
			_px(img, cx + a.x * (r + 1), cy + a.y * (r + 1), ray)
	for y in range(cy - r - 1, cy + r + 2):
		for x in range(cx - r - 1, cx + r + 2):
			var d := Vector2(x - cx, y - cy).length()
			if d <= r + 0.6:
				_px(img, x, y, OL if d > r - 0.4 else fill)
	_px(img, cx - 1, cy - 1, Color("fff3b0"))


## Облако из трёх кочек: светлый верх, тень снизу, обводка.
static func _cloud(img: Image, ox: int, oy: int, light: Color, shade: Color) -> void:
	var rows := [[3, 5], [2, 7], [1, 9], [0, 11], [0, 11], [1, 9]]   # [сдвиг, ширина] строк сверху вниз
	for i in rows.size():
		var x0: int = ox + rows[i][0]
		var w: int = rows[i][1]
		for x in range(x0 - 1, x0 + w + 1):
			_px(img, x, oy + i + 1, OL)
		for x in range(x0, x0 + w):
			_px(img, x, oy + i + 1, shade if i >= rows.size() - 2 else light)
	for x in range(ox + 1, ox + 10):
		_px(img, x, oy + rows.size() + 1, OL)


static func _drops(img: Image) -> void:
	for p: Vector2i in [Vector2i(2, 9), Vector2i(6, 10), Vector2i(10, 9)]:
		_px(img, p.x, p.y, Color("5ab0ff"))
		_px(img, p.x - 1, p.y + 1, Color("5ab0ff"))
		_px(img, p.x - 1, p.y + 2, Color("3a80d0"))


static func _fog(img: Image) -> void:
	# четыре полосы тумана разной длины: светлая строка и тёмная под ней
	var bands := [[2, 8, 1], [0, 11, 4], [3, 9, 7], [1, 10, 10]]   # [сдвиг, длина, строка]
	for b in bands:
		for x in range(b[0], b[0] + b[1]):
			_px(img, x, b[2], Color("d8dde8"))
			_px(img, x, b[2] + 1, OL)
		_px(img, b[0] - 1, b[2], OL)
		_px(img, b[0] + b[1], b[2], OL)


static func _waves(img: Image) -> void:
	for y in [10, 12]:
		for x in 11:
			_px(img, 1 + x, y + (1 if (x / 2) % 2 == 0 else 0), Color("ff7a3a"))


static func _flake(img: Image) -> void:
	var c := 6
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		for k in range(-5, 6):
			var p := Vector2i(c, c) + d * k
			_px(img, p.x + 1, p.y, OL)
			_px(img, p.x - 1, p.y, OL)
			_px(img, p.x, p.y + 1, OL)
			_px(img, p.x, p.y - 1, OL)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		for k in range(-5, 6):
			var p := Vector2i(c, c) + d * k
			_px(img, p.x, p.y, Color("e8f4ff"))
	_px(img, c, c, Color.WHITE)
