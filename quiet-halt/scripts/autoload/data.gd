extends Node
## Загрузка данных игры из JSON (data-driven: баланс правится без кода).

var items: Dictionary = {}
var objects: Dictionary = {}
var projects: Array = []
var villagers: Array = []
var notes: Array = []

var _villager_by_id: Dictionary = {}


func _ready() -> void:
	for it in _read("items.json", []):
		items[str(it.id)] = it
	objects = _read("objects.json", {})
	projects = _read("projects.json", [])
	villagers = _read("villagers.json", [])
	notes = _read("notes.json", [])
	for v in villagers:
		_villager_by_id[str(v.id)] = v


func _read(file: String, fallback: Variant) -> Variant:
	var path: String = "res://data/" + file
	if not FileAccess.file_exists(path):
		push_error("Нет файла данных: " + path)
		return fallback
	var txt: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_error("Ошибка JSON: " + path)
		return fallback
	return parsed


func item(id: String) -> Dictionary:
	return items.get(id, {"id": id, "name": id, "category": "misc", "shape": "junk", "color": [0.6, 0.6, 0.6], "price": 0})


func item_name(id: String) -> String:
	return str(item(id).get("name", id))


func object_def(id: String) -> Dictionary:
	return objects.get(id, {"size": [1, 1], "block": false})


func villager(id: String) -> Dictionary:
	return _villager_by_id.get(id, {})


func project(id: String) -> Dictionary:
	for p in projects:
		if p.id == id:
			return p
	return {}
