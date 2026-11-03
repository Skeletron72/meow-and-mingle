class_name PostFx
extends CanvasLayer
## Общий пост-эффект: пиксельный блум (ступенями, с дизерингом) и виньетка. Ночью свечение сильнее и берёт даже умеренно яркое,
## днём — только самое яркое. Шейдер assets/shaders/post_fx.gdshader считает по сетке пикселей арта.

const SHADER := preload("res://assets/shaders/post_fx.gdshader")

var day_threshold := 0.93
var night_threshold := 0.60
var day_bloom := 0.28
var night_bloom := 0.95
var _mat: ShaderMaterial


func _ready() -> void:
	var rect := ColorRect.new()
	rect.size = Vector2(360, 640)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	rect.material = _mat
	add_child(rect)
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var win := get_window()
	var sc := minf(float(win.size.x) / 360.0, float(win.size.y) / 640.0)
	var night := TimeOfDay.night()
	_mat.set_shader_parameter("art_px", maxf(1.0, sc * 2.0))
	_mat.set_shader_parameter("threshold", lerpf(day_threshold, night_threshold, night))
	_mat.set_shader_parameter("bloom", lerpf(day_bloom, night_bloom, night))
	_mat.set_shader_parameter("vignette", 0.45 + 0.35 * night)
