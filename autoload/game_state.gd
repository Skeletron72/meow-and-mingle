extends Node
## Autoload "GameState": монеты, прогресс и сохранение в user://save.json.
## Меняется структура сохранения -> повысить SAVE_VERSION и дописать шаг в _migrate().

signal coins_changed(value: int)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3

var coins: int = 0
var served_total: int = 0
var cat_progress: Dictionary = {}  # cat_id -> {"chapter": int, "likes": int} (этап 2)
var last_visit_unix: int = 0       # для чаевой банки (этап 3)
var city_inside := true            # где игрок в городе: в кафе (true) или на улице; только на время работы приложения
var layout: Array[Dictionary] = [] # расставленная мебель: {"id", "c", "r", "flip"} — клетки сетки (режим украшения)


func _ready() -> void:
	layout = Data.default_layout.duplicate(true)
	load_game()


func add_coins(amount: int) -> void:
	coins += amount
	coins_changed.emit(coins)
	save_game()


## Списывает монеты. false — не хватает, ничего не изменено.
func spend_coins(amount: int) -> bool:
	if amount > coins:
		return false
	coins -= amount
	coins_changed.emit(coins)
	save_game()
	return true


func register_served() -> void:
	served_total += 1


func save_game() -> void:
	last_visit_unix = int(Time.get_unix_time_from_system())
	var data := {
		"version": SAVE_VERSION,
		"coins": coins,
		"served_total": served_total,
		"cat_progress": cat_progress,
		"last_visit_unix": last_visit_unix,
		"layout": layout,
		"hour": TimeOfDay.hour,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось записать сохранение: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_warning("Сохранение повреждено, начинаем заново")
		return
	var data := _migrate(parsed as Dictionary)
	coins = int(data.get("coins", 0))
	served_total = int(data.get("served_total", 0))
	cat_progress = data.get("cat_progress", {})
	last_visit_unix = int(data.get("last_visit_unix", 0))
	layout = _sanitize_layout(data.get("layout", null))
	TimeOfDay.hour = clampf(float(data.get("hour", 9.0)), 0.0, 24.0)


func _migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 0))
	if v < 3:
		# v2 хранил мебель в пикселях и до сетки 16×16 — переводить нечего. Расстановка по умолчанию,
		# а за всё, что игрок докупил сверх неё, возвращаем монеты (v1 мебели не знал).
		var refund := 0
		var free_left := {"window": 1, "board": 1, "table_big": 1, "stool": 1, "plant": 1, "rug": 1, "bowl": 1}
		var old: Variant = data.get("layout", null)
		if v == 2 and old is Array:
			for item in old:
				if not (item is Dictionary) or not Data.furniture.has(String(item.get("id", ""))):
					continue
				var id := String(item["id"])
				if int(free_left.get(id, 0)) > 0:
					free_left[id] = int(free_left[id]) - 1
				else:
					refund += int(Data.furniture[id]["price"])
		data["coins"] = int(data.get("coins", 0)) + refund
		data["layout"] = Data.default_layout.duplicate(true)
		v = 3
	if v > SAVE_VERSION:
		push_warning("Сохранение новее игры (v%d)" % v)
	return data


## Оставляет только корректную мебель: известные id, клетки внутри зала, без наложений и без перекрытия прохода.
## Не массив -> расстановка по умолчанию.
func _sanitize_layout(raw: Variant) -> Array[Dictionary]:
	if not (raw is Array):
		return Data.default_layout.duplicate(true)
	var room := CafeRoom.new()  # только для проверки размещения, в дерево не добавляется
	var out: Array[Dictionary] = []
	room.layout = out
	for item in raw:
		if not (item is Dictionary) or not Data.furniture.has(String(item.get("id", ""))):
			continue
		var fixed := {
			"id": String(item["id"]),
			"c": int(item.get("c", -1)),
			"r": int(item.get("r", -1)),
			"flip": bool(item.get("flip", false)),
		}
		if room.check_place(fixed["id"], fixed["c"], fixed["r"]) == "":
			out.append(fixed)
	room.free()
	return out
