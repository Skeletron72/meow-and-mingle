class_name Nav
extends RefCounted
## Пути сцен и переходы между режимами игры.

const CITY := "res://scenes/city.tscn"          # игра: город с кафе (прогулка + смена за стойкой + меню)
const BREW := "res://main.tscn"                 # смена за стойкой: сборка заказов (в игре открывается поверх города)
const DECORATE := "res://scenes/decorate.tscn"  # режим украшения
const COMIC := "res://scenes/intro_comic.tscn"  # комикс-завязка новой игры


static func go(from: Node, path: String) -> void:
	from.get_tree().change_scene_to_file.call_deferred(path)
