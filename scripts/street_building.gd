@tool
class_name StreetBuilding
extends Sprite2D
## Здание. Позиция узла — левый нижний угол фасада (низ стоит на линии тротуара). Масштаб 2.
## `is_cafe` — наше кафе: его фасад становится прозрачным («рентген»), когда кот заходит внутрь.
## Окна для ночной подсветки берутся из data/street.json по имени текстуры (building4.png -> «building4»).

@export var is_cafe := false


func _ready() -> void:
	centered = false
	scale = Vector2(2, 2)
	_fit()
	if not texture_changed.is_connected(_fit):
		texture_changed.connect(_fit)


func _fit() -> void:
	if texture != null:
		offset = Vector2(0, -texture.get_height())


func building_id() -> String:
	return texture.resource_path.get_file().get_basename() if texture != null else ""


## Прямоугольник фасада в мире.
func world_rect() -> Rect2:
	var sz := texture.get_size() * 2.0
	return Rect2(global_position - Vector2(0, sz.y), sz)
