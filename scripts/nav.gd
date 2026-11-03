class_name Nav
extends RefCounted
## Пути сцен и переходы между режимами игры.

const MENU := "res://scenes/menu.tscn"
const BREW := "res://main.tscn"                 # кофейня: сборка заказов
const WALK := "res://scenes/cafe_walk.tscn"     # прогулка по кафе
const DECORATE := "res://scenes/decorate.tscn"  # режим украшения


static func go(from: Node, path: String) -> void:
	from.get_tree().change_scene_to_file.call_deferred(path)
