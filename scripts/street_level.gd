@tool
class_name StreetLevel
extends Node2D
## Корень уровня улицы (scenes/street.tscn). Здесь расставляются здания, предметы, зоны и рисуется земля — прямо в редакторе:
##   Ground    — TileMapLayer с тайлсетом земли (assets/street/tiles): тротуар, дорога, зебра, трава
##   Zones     — узлы StreetZone (ходьба, полосы машин, интерьер кафе)
##   Buildings — узлы StreetBuilding
##   Props     — узлы StreetProp
## В редакторе рисуется сетка 32 px и границы мира.

@export var world_size := Vector2(2624, 960):
	set(value):
		world_size = value
		queue_redraw()


func zones(kind: StreetZone.Kind) -> Array[StreetZone]:
	var out: Array[StreetZone] = []
	for z in find_children("*", "StreetZone", true, false):
		if (z as StreetZone).kind == kind:
			out.append(z)
	return out


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var grid := Color(1, 1, 1, 0.07)
	for x in range(0, int(world_size.x) + 1, 32):
		draw_line(Vector2(x, 0), Vector2(x, world_size.y), grid, 1.0)
	for y in range(0, int(world_size.y) + 1, 32):
		draw_line(Vector2(0, y), Vector2(world_size.x, y), grid, 1.0)
	draw_rect(Rect2(Vector2.ZERO, world_size), Color(1, 1, 1, 0.5), false, 2.0)
