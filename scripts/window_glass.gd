class_name WindowGlass
extends Node2D
## Стекло окна фасада (рисуется в пикселях арта поверх спрайта здания): за стеклом — крошечная комната (шторы, цветок, кот на подоконнике),
## сверху отражение неба с бликами; в дождь по стеклу бегут капли, в туман оно запотевает, в снегопад в углах появляется иней.
## «Прозрачное» стекло витрины кафе (transparent = true) не закрашивает комнату — только отражение, капли и иней: зал виден насквозь.

var size := Vector2i(16, 20)     # размер окна, px арта
var transparent := false
var seed_id := 0
var _tint := Color(0.7, 0.85, 1.0)
var _day := 1.0
var _rain := 0.0
var _fog := 0.0
var _snow := 0.0
var _kind := 0


func _ready() -> void:
	_kind = abs(seed_id) % 4


## tint — цвет отражаемого неба; day 0..1 — дневной свет (ночью окно светится изнутри — это рисуют свечения города).
func apply(tint: Color, day: float, rain: float, fog: float, snow: float) -> void:
	if tint.is_equal_approx(_tint) and is_equal_approx(day, _day) and is_equal_approx(rain, _rain) and is_equal_approx(fog, _fog) and is_equal_approx(snow, _snow):
		return
	_tint = tint
	_day = day
	_rain = rain
	_fog = fog
	_snow = snow
	queue_redraw()


func _px(x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if not transparent:
		_draw_room(w, h)
	# отражение неба: ровный тон + диагональные блики
	_px(0, 0, w, h, Color(_tint, (0.10 if transparent else 0.20) * _day))
	var g := Color(1, 1, 1, (0.30 if transparent else 0.38) * _day)
	for sx in [w / 4, w / 2 + 2]:   # два диагональных блика: идут снизу-слева вверх-вправо, с разрывами
		for k in h:
			var x: int = sx + (h - 1 - k) / 2
			if x >= 0 and x < w and k % 4 != 3:
				_px(x, k, 1, 1, g)
	# дождь: капли и подтёки
	if _rain > 0.05:
		var n := int(6.0 * _rain) + 2
		for i in n:
			var hx := int(fposmod(float(seed_id * 7 + i * 13), float(maxi(1, w - 1))))
			var hy := int(fposmod(float(seed_id * 5 + i * 29), float(maxi(1, h - 3))))
			_px(hx, hy, 1, 2, Color(0.85, 0.93, 1.0, 0.65))
			_px(hx, hy + 2, 1, 1, Color(0.85, 0.93, 1.0, 0.3))
	# туман: запотевшее стекло шахматкой
	if _fog > 0.05:
		for y in h:
			for x in w:
				if (x + y) % 2 == 0:
					_px(x, y, 1, 1, Color(0.9, 0.93, 0.96, 0.28 * _fog))
	# снег: иней в нижних углах ступеньками
	if _snow > 0.25:
		var k := int(clampf(_snow * 4.0, 1.0, 4.0))
		for i in k:
			_px(i, h - 1 - (k - 1 - i), 1, k - i, Color(0.95, 0.97, 1.0, 0.9))
			_px(w - 1 - i, h - 1 - (k - 1 - i), 1, k - i, Color(0.95, 0.97, 1.0, 0.9))


## Комната за стеклом: тёплая стена, шторы и предмет на подоконнике (зависит от seed_id).
func _draw_room(w: int, h: int) -> void:
	_px(0, 0, w, h, Color("2a1f24"))
	_px(0, h / 2, w, h - h / 2, Color("33262a"))   # низ комнаты чуть светлее
	var curtain := Color("7d3b4a") if seed_id % 3 == 0 else (Color("4b6b7a") if seed_id % 3 == 1 else Color("8a6a3a"))
	match _kind:
		0:   # шторы с обеих сторон
			_px(0, 0, maxi(2, w / 5), h, curtain)
			_px(w - maxi(2, w / 5), 0, maxi(2, w / 5), h, curtain)
			_px(maxi(2, w / 5), 0, w - 2 * maxi(2, w / 5), 1, curtain.darkened(0.3))
		1:   # штора слева и цветок на подоконнике
			_px(0, 0, maxi(2, w / 4), h, curtain)
			_px(w - 5, h - 4, 3, 2, Color("3f8a4a"))
			_px(w - 5, h - 2, 3, 2, Color("a5603a"))
		2:   # кот на подоконнике
			var fur := Color("0d0b10")
			var cx := w / 2 - 2
			_px(cx, h - 5, 5, 4, fur)
			_px(cx + 1, h - 8, 4, 3, fur)
			_px(cx + 1, h - 9, 1, 1, fur)
			_px(cx + 4, h - 9, 1, 1, fur)
			_px(cx + 2, h - 7, 1, 1, Color("ffd24a"))
			_px(cx + 4, h - 7, 1, 1, Color("ffd24a"))
		_:   # лампа
			_px(w / 2, h / 3, 1, h / 3, Color("5a4a40"))
			_px(w / 2 - 2, h / 3 - 2, 5, 3, Color("d4a24a"))
