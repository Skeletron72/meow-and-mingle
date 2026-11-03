@tool
class_name StreetProp
extends Sprite2D
## Предмет на улице (дерево, фонарь, автомат...). Позиция узла — точка «на земле»: низ по центру спрайта.
## Масштаб всегда 2 (как вся графика), спрайт сам встаёт низом на позицию. Сортируется по y вместе с котами и машинами.

@export var blocks := false:        ## перекрывает клетку под собой — кот не пройдёт
	set(value):
		blocks = value
		update_configuration_warnings()
@export var emits_light := false    ## фонарь: ночью светится

func _ready() -> void:
	centered = false
	scale = Vector2(2, 2)
	_fit()
	if not texture_changed.is_connected(_fit):
		texture_changed.connect(_fit)


func _fit() -> void:
	if texture != null:
		offset = Vector2(-floorf(texture.get_width() / 2.0), -texture.get_height())


## Клетка 32×32, которую занимает предмет (для blocks).
func blocked_cell() -> Vector2i:
	return Vector2i(floori(global_position.x / 32.0), floori((global_position.y - 4.0) / 32.0))


func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray() if texture != null else PackedStringArray(["Не задана текстура."])
