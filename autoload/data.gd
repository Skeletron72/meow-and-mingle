extends Node
## Autoload "Data": читает справочники из res://data/*.json.
## Менять баланс и добавлять котов/напитки нужно в JSON, не в коде.

var cats: Array[Dictionary] = []
var drinks: Dictionary = {}    # id -> Dictionary
var pastries: Dictionary = {}  # id -> Dictionary
var furniture: Dictionary = {} # id -> Dictionary (режим украшения, см. data/furniture.json)
var default_layout: Array[Dictionary] = []  # расстановка кафе у игрока из старых сохранений
var intro_layout: Array[Dictionary] = []    # расстановка нового игрока: только стол и пуфик
var upgrades: Array[Dictionary] = []        # функциональные улучшения (data/upgrades.json), по порядку
var levels: Array[Dictionary] = []          # уровни-смены (data/levels.json), по порядку
var credits: Array[Dictionary] = []         # титры (data/credits.json)
var repairs: Array[Dictionary] = []         # задачи ремонта за звёзды (data/repairs.json), по порядку
var street: Dictionary = {}    # городские ассеты: размеры, окна фасадов, машины (data/street.json, делает tools/curate_street_assets.py)


func _ready() -> void:
	cats = _read_array("res://data/cats.json")
	for d in _read_array("res://data/drinks.json"):
		drinks[d["id"]] = d
	for p in _read_array("res://data/pastries.json"):
		pastries[p["id"]] = p
	for f in _read_array("res://data/furniture.json"):
		furniture[f["id"]] = f
	default_layout = _read_array("res://data/default_layout.json")
	intro_layout = _read_array("res://data/intro_layout.json")
	upgrades = _read_array("res://data/upgrades.json")
	levels = _read_array("res://data/levels.json")
	repairs = _read_array("res://data/repairs.json")
	var cf := FileAccess.open("res://data/credits.json", FileAccess.READ)
	if cf != null:
		var cp: Variant = JSON.parse_string(cf.get_as_text())
		if cp is Dictionary:
			for sec in (cp as Dictionary).get("sections", []):
				credits.append(sec)
	var f := FileAccess.open("res://data/street.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			street = parsed


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
