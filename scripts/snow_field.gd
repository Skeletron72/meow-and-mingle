class_name SnowField
extends Node2D
## Снегопад настоящими частицами в мире: снежинки — спрайты, которые падают и покачиваются в мировых координатах,
## поэтому при движении камеры остаются на месте (а не «стекают» по экрану). Позиция каждой снегопад привязывается к сетке арта (2 px).
## Область — вид камеры с запасом; вылетевшие за край снежинки возвращаются с противоположной стороны.
## Внутри раскрытого зала снега нет (mask / mask_amount).

const COUNT := 240
const MARGIN := 40.0

var camera: Camera2D
var mask := Rect2()            # зал на этаже кота (мир)
var mask_amount := 0.0
var _flakes: Array[Dictionary] = []   # {"sp", "pos", "vy", "sway", "phase", "big"}
var _t := 0.0


func _ready() -> void:
	z_index = 25
	for i in COUNT:
		var sp := Sprite2D.new()
		sp.texture = Fx.tex("mote")
		sp.centered = false
		var big := i % 4 == 0
		sp.scale = Vector2(4, 4) if big else Vector2(2, 2)
		sp.modulate = Color(1, 1, 1, 0.95 if big else 0.8)
		var shade := Sprite2D.new()   # голубая тень-подложка: белая снежинка видна и на белом снегу
		shade.texture = sp.texture
		shade.centered = false
		shade.scale = sp.scale
		shade.modulate = Color(0.55, 0.68, 0.9, 0.55)
		add_child(shade)
		add_child(sp)
		_flakes.append({"sp": sp, "shade": shade, "pos": Vector2(randf() * 400.0, randf() * 700.0), "vy": randf_range(26.0, 48.0) * (0.75 if big else 1.0), "sway": randf_range(4.0, 12.0), "phase": randf() * TAU, "big": big})


func _process(delta: float) -> void:
	if camera == null:
		return
	var amount := Weather.snowfall
	visible = amount > 0.01
	if not visible:
		return
	_t += delta
	var c := camera.get_screen_center_position()
	var view := Rect2(c - Vector2(180.0, 320.0) - Vector2(MARGIN, MARGIN), Vector2(360.0, 640.0) + Vector2(MARGIN, MARGIN) * 2.0)
	var active := int(COUNT * amount)
	for i in _flakes.size():
		var f: Dictionary = _flakes[i]
		var sp: Sprite2D = f["sp"]
		var shade: Sprite2D = f["shade"]
		if i >= active:
			sp.visible = false
			shade.visible = false
			continue
		var p: Vector2 = f["pos"]
		p.y += float(f["vy"]) * delta
		p.x += sin(_t * 0.9 + float(f["phase"])) * float(f["sway"]) * delta
		# мировая позиция остаётся при движении камеры; за краем вида — возврат с другой стороны
		p.x = view.position.x + fposmod(p.x - view.position.x, view.size.x)
		p.y = view.position.y + fposmod(p.y - view.position.y, view.size.y)
		f["pos"] = p
		sp.position = Vector2(snappedf(p.x, 2.0), snappedf(p.y, 2.0))
		sp.visible = not (mask_amount > 0.5 and mask.has_point(p))
		shade.visible = sp.visible
		shade.position = sp.position + Vector2(2, 2)
