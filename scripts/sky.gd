class_name CitySky
extends Node2D
## Небо за городом (рисуется в экранных координатах, лежит на отдельном CanvasLayer под миром):
## градиент по времени суток, звёзды, солнце/луна, облака и далёкий силуэт города с параллаксом.
## Всё рисуется «пикселями» по 2 px — как остальная графика.

const W := 360.0
const H := 640.0
const PX := 2.0

var camera_x := 0.0   # где сейчас камера в мире (задаёт город); от неё зависит сдвиг силуэта

var _stars: Array[Vector3] = []     # x, y, фаза мерцания
var _clouds: Array[Vector3] = []    # x, y, скорость
var _skyline: Array[Rect2] = []     # силуэты в «мировых» координатах дальнего плана


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in 70:
		_stars.append(Vector3(snappedf(rng.randf_range(0, W), PX), snappedf(rng.randf_range(0, 300), PX), rng.randf_range(0, TAU)))
	for _i in 6:
		_clouds.append(Vector3(rng.randf_range(0, W + 120), snappedf(rng.randf_range(24, 140), PX), rng.randf_range(4, 10)))
	var x := 0.0
	while x < 2400.0:
		var w := snappedf(rng.randf_range(40, 90), PX)
		_skyline.append(Rect2(x, 0, w, snappedf(rng.randf_range(60, 170), PX)))
		x += w + snappedf(rng.randf_range(0, 24), PX)


func _process(delta: float) -> void:
	for i in _clouds.size():
		var c := _clouds[i]
		c.x -= c.z * delta
		if c.x < -100.0:
			c.x = W + 20.0
		_clouds[i] = c
	queue_redraw()


func _draw() -> void:
	var top := TimeOfDay.sky_top()
	var bottom := TimeOfDay.sky_bottom()
	var night := TimeOfDay.night()
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]), PackedColorArray([top, top, bottom, bottom]))
	# звёзды
	if night > 0.3:
		var t := Time.get_ticks_msec() / 1000.0
		for s in _stars:
			var a := night * (0.55 + 0.45 * sin(t * 2.0 + s.z))
			draw_rect(Rect2(s.x, s.y, PX, PX), Color(1.0, 1.0, 0.9, a))
	_draw_body(TimeOfDay.sun_progress(), 8, Color(1.0, 0.92, 0.55), true)
	_draw_body(TimeOfDay.moon_progress(), 6, Color(0.95, 0.95, 0.85), false)
	# облака
	var cloud_col := Color.WHITE.lerp(bottom.lightened(0.15), clampf(night, 0.0, 1.0) * 0.85)
	cloud_col.a = 0.85
	for c in _clouds:
		_draw_cloud(Vector2(snappedf(c.x, PX), c.y), cloud_col)
	# далёкий силуэт: два слоя, чем дальше — тем медленнее едет и светлее
	for layer in 2:
		var factor := 0.12 if layer == 0 else 0.22
		var col := bottom.lerp(top, 0.35).darkened(0.18 + 0.12 * layer)
		for r in _skyline:
			var x := snappedf(r.position.x + layer * 37.0 - camera_x * factor, PX)
			x = fposmod(x + 200.0, 2400.0) - 200.0
			if x > W or x + r.size.x < 0.0:
				continue
			draw_rect(Rect2(x, 330.0 - r.size.y * (0.7 if layer == 0 else 1.0), r.size.x, 400.0), col)


## Солнце или луна как пиксельный диск, движется по дуге через экран.
func _draw_body(p: float, radius: int, color: Color, glow: bool) -> void:
	if p < 0.0:
		return
	var cx := snappedf(-16.0 + p * (W + 32.0), PX)
	var cy := snappedf(92.0 - sin(p * PI) * 66.0, PX)
	if glow:
		for r in [radius + 5, radius + 3]:
			_disc(Vector2(cx, cy), r, Color(color, 0.12))
	_disc(Vector2(cx, cy), radius, color)
	if not glow:
		# «кратеры» и фаза: тёмные пиксели
		draw_rect(Rect2(cx - 4, cy - 4, 4, 4), color.darkened(0.12))
		draw_rect(Rect2(cx + 2, cy + 2, 4, 4), color.darkened(0.12))


func _disc(c: Vector2, r: int, color: Color) -> void:
	for dy in range(-r, r + 1):
		var half := int(round(sqrt(float(r * r - dy * dy))))
		draw_rect(Rect2(c.x - half * PX, c.y + dy * PX, half * 2 * PX, PX), color)


func _draw_cloud(p: Vector2, color: Color) -> void:
	draw_rect(Rect2(p.x + 12, p.y, 36, PX), color)
	draw_rect(Rect2(p.x + 4, p.y + PX, 60, PX), color)
	draw_rect(Rect2(p.x, p.y + PX * 2, 68, PX * 2), color)
	draw_rect(Rect2(p.x + 8, p.y + PX * 4, 52, PX), color)
