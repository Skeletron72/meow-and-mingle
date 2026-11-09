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
var boosters: Array[Dictionary] = []       # бустеры (data/boosters.json)
var deals: Array[Dictionary] = []          # предложения дня (data/deals.json)
var daily_gifts: Array[Dictionary] = []    # лента ежедневных подарков, 7 дней (data/daily.json)
var quest_pool: Array[Dictionary] = []     # шаблоны ежедневных заданий (data/quests.json)
var terrace: Array[Dictionary] = []         # места уличной террасы перед кафе (data/terrace.json)
var legal: Dictionary = {}                 # ссылки на политику, соглашение и поддержку (data/legal.json)
var shop: Dictionary = {}                  # каталог магазина (data/shop.json)
var season: Dictionary = {}                # текущий сезон «Мурлык-пасс» (data/season_<n>.json)
var events: Array[Dictionary] = []         # события (data/events.json)                # текущий сезон «Мурлык-пасс» (data/season_1.json)
var story: Array[Dictionary] = []           # сюжетные сцены (data/story.json)
var chapters: Array[Dictionary] = []        # главы кампании (data/chapters.json)
var styles: Dictionary = {}                 # палитры стен, пола и плинтусов (data/styles.json)
var repairs: Array[Dictionary] = []         # задачи ремонта за звёзды (data/repairs.json), по порядку
var places: Dictionary = {}    # места-активности на улице: id -> {name, icon, blurb} (data/places.json); здание получает место в scenes/street.tscn
var street: Dictionary = {}    # городские ассеты: размеры, окна фасадов, машины (data/street.json, делает tools/curate_street_assets.py)


func _ready() -> void:
	cats = _read_array("res://data/cats.json")
	for d in _read_array("res://data/drinks.json"):
		drinks[d["id"]] = d
	for p in _read_array("res://data/pastries.json"):
		pastries[p["id"]] = p
	for f in _read_array("res://data/furniture.json"):
		furniture[f["id"]] = f
	for pl in _read_array("res://data/places.json"):
		places[pl["id"]] = pl
	default_layout = _read_array("res://data/default_layout.json")
	intro_layout = _read_array("res://data/intro_layout.json")
	upgrades = _read_array("res://data/upgrades.json")
	levels = _read_array("res://data/levels.json")
	repairs = _read_array("res://data/repairs.json")
	chapters = _read_array("res://data/chapters.json")
	story = _read_array("res://data/story.json")
	boosters = _read_array("res://data/boosters.json")
	deals = _read_array("res://data/deals.json")
	daily_gifts = _read_array("res://data/daily.json")
	quest_pool = _read_array("res://data/quests.json")
	shop = _read_dict("res://data/shop.json")
	legal = _read_dict("res://data/legal.json")
	terrace = _read_array("res://data/terrace.json")
	season = _read_dict("res://data/season_1.json")
	events = _read_array("res://data/events.json")
	var sf := FileAccess.open("res://data/styles.json", FileAccess.READ)
	if sf != null:
		var sp: Variant = JSON.parse_string(sf.get_as_text())
		if sp is Dictionary:
			styles = sp
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


## Подгружает сезон по номеру (data/season_<n>.json); false — такого файла нет.
func load_season(n: int) -> bool:
	var path := "res://data/season_%d.json" % n
	if not FileAccess.file_exists(path):
		return false
	season = _read_dict(path)
	return true


func _read_dict(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Не удалось открыть %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


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
