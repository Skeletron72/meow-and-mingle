extends Node
## Autoload "Data": читает справочники из res://data/*.json.
## Менять баланс и добавлять котов/напитки нужно в JSON, не в коде.

var cats: Array[Dictionary] = []
var drinks: Dictionary = {}    # id -> Dictionary
var pastries: Dictionary = {}  # id -> Dictionary
var furniture: Dictionary = {} # id -> Dictionary (режим украшения, см. data/furniture.json)
var default_layout: Array[Dictionary] = []  # расстановка кафе у нового игрока


func _ready() -> void:
	cats = _read_array("res://data/cats.json")
	for d in _read_array("res://data/drinks.json"):
		drinks[d["id"]] = d
	for p in _read_array("res://data/pastries.json"):
		pastries[p["id"]] = p
	for f in _read_array("res://data/furniture.json"):
		furniture[f["id"]] = f
	default_layout = _read_array("res://data/default_layout.json")


func _read_array(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Не удалось открыть %s" % path)
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		for item in parsed:
			if item is Dictionary:
				out.append(item)
	else:
		push_error("Ожидался массив в %s" % path)
	return out
