class_name AutoDoor
extends Node2D
## Раздвижная стеклянная дверь кафе: две створки, вырезанные из текстуры фасада, разъезжаются шагами по пикселю арта,
## когда рядом кот, и закрываются, когда он отошёл. Стекло створок прозрачно, края режет проём (шейдер door_leaf).
## Стоит в слое зданий поверх фасада; сам фасад в проёме вырезан (xray_hole, uniform door).

const SHADER := preload("res://assets/shaders/door_leaf.gdshader")
const OPEN_TIME := 0.38

var rect := Rect2()          # проём в мире
var open_amount := 0.0:      # 0 закрыта, 1 открыта настежь
	set(v):
		open_amount = clampf(v, 0.0, 1.0)
		_place()
var _left: Sprite2D
var _right: Sprite2D
var _mat: ShaderMaterial
var _tween: Tween
var _target := false
var _half_w := 0.0


## texture — текстура фасада, src — проём в пикселях текстуры (x, y, w, h), world_pos — левый верх проёма в мире.
func setup(texture: Texture2D, src: Rect2i, world_pos: Vector2) -> void:
	rect = Rect2(world_pos, Vector2(src.size) * 2.0)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("clip", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	var half := int(src.size.x / 2)   # левая створка — меньшая половина, правая — остаток
	_half_w = float(half) * 2.0
	_left = _leaf(texture, Rect2(src.position.x, src.position.y, half, src.size.y))
	_right = _leaf(texture, Rect2(src.position.x + half, src.position.y, src.size.x - half, src.size.y))
	_place()


func _leaf(texture: Texture2D, region: Rect2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.region_enabled = true
	s.region_rect = region
	s.centered = false
	s.scale = Vector2(2, 2)
	s.material = _mat
	add_child(s)
	return s


func _place() -> void:
	if _left == null:
		return
	var shift := snappedf(open_amount * _half_w, 2.0)   # шаги по пикселю арта
	_left.position = rect.position + Vector2(-shift, 0)
	_right.position = rect.position + Vector2(_half_w + shift, 0)


## Открыть или закрыть (плавно, но кадры стоят на сетке).
func set_open(open: bool) -> void:
	if open == _target:
		return
	_target = open
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	var from := open_amount
	var to := 1.0 if open else 0.0
	_tween.tween_method(func(u: float) -> void: open_amount = u, from, to, OPEN_TIME * absf(to - from)).set_trans(Tween.TRANS_SINE)


func is_open() -> bool:
	return open_amount > 0.5


## Круг рентгена: створки режутся им так же, как фасад.
func set_iris(center: Vector2, radius: float, region: Vector4) -> void:
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("radius", radius)
	_mat.set_shader_parameter("region", region)
