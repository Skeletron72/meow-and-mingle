extends Node
## Autoload "GameState": монеты, прогресс и сохранение в user://save.json.
## Меняется структура сохранения -> повысить SAVE_VERSION и дописать шаг в _migrate().

signal coins_changed(value: int)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2

var coins: int = 0
var served_total: int = 0
var cat_progress: Dictionary = {}  # cat_id -> {"chapter": int, "likes": int} (этап 2)
var last_visit_unix: int = 0       # для чаевой банки (этап 3)
var layout: Array[Dictionary] = [] # расставленная мебель: {"id", "x", "y", "flip"} (режим украшения)


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


func _migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 0))
	if v < 2:
		data["layout"] = Data.default_layout.duplicate(true)  # v2: добавлен режим украшения
		v = 2
	if v > SAVE_VERSION:
		push_warning("Сохранение новее игры (v%d)" % v)
	return data


## Отбрасывает записи с неизвестной мебелью и приводит типы; не массив -> расстановка по умолчанию.
func _sanitize_layout(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		return Data.default_layout.duplicate(true)
	for item in raw:
		if item is Dictionary and Data.furniture.has(String(item.get("id", ""))):
			out.append({
				"id": String(item["id"]),
				"x": float(item.get("x", 0.0)),
				"y": float(item.get("y", 0.0)),
				"flip": bool(item.get("flip", false)),
			})
	return out
