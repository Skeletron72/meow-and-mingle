class_name StreetNav
extends RefCounted
## «Навигация» по тротуару для котов на улице: полоса, по которой можно ходить. Препятствий нет —
## мебель и фонари стоят у стен и бордюра. Тот же интерфейс, что и у CafeRoom (find_path, is_blocked, random_free_point).

var band: Rect2


func _init(walk_band: Rect2) -> void:
	band = walk_band


func find_path(_from_feet: Vector2, to: Vector2) -> PackedVector2Array:
	var p := Vector2(clampf(to.x, band.position.x, band.end.x), clampf(to.y, band.position.y, band.end.y))
	return PackedVector2Array([p])


func is_blocked(feet: Vector2) -> bool:
	return not band.has_point(feet)


func random_free_point() -> Vector2:
	return Vector2(randf_range(band.position.x, band.end.x), randf_range(band.position.y, band.end.y))
