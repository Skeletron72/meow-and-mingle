class_name WeatherFx
extends CanvasLayer
## Экранные погодные эффекты поверх мира и под интерфейсом (слой 1): один прямоугольник с шейдером weather_screen.
## Внутри раскрытого интерьера погоды нет — для этого город передаёт прямоугольник зала в экранных координатах (set_mask).

const SHADER := preload("res://assets/shaders/weather_screen.gdshader")

var _rect: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	layer = 1


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.size = Vector2(360, 640)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	add_child(_rect)


func _process(_delta: float) -> void:
	# шейдер с чтением экрана дорог — выключаем, когда погоды нет
	_rect.visible = Weather.rain + Weather.fog + Weather.heat + Weather.snowfall > 0.01


## screen_rect — зал в экранных координатах (px окна 360×640); amount — насколько раскрыт интерьер.
func set_mask(screen_rect: Rect2, amount: float) -> void:
	_mat.set_shader_parameter("mask", Vector4(screen_rect.position.x / 360.0, screen_rect.position.y / 640.0, screen_rect.size.x / 360.0, screen_rect.size.y / 640.0))
	_mat.set_shader_parameter("mask_amount", amount)
