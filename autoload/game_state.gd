extends Node
## Autoload "GameState": монеты, прогресс и сохранение в user://save.json.
## Меняется структура сохранения -> повысить SAVE_VERSION и дописать шаг в _migrate().

signal coins_changed(value: int)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 4
const INTRO_DONE := 5   # стадии: 0 комикс, 1 катсцена, 2 расчистка, 3 обучающая смена, 4 магазин, 5 интро пройдено

var coins: int = 0
var served_total: int = 0
var cat_progress: Dictionary = {}  # cat_id -> {"chapter": int, "likes": int} (этап 2)
var last_visit_unix: int = 0       # для чаевой банки (этап 3)
var city_inside := true            # где игрок в городе: в кафе (true) или на улице; только на время работы приложения
var layout: Array[Dictionary] = [] # расставленная мебель: {"id", "c", "r", "flip"} — клетки сетки (режим украшения)
var intro_stage := INTRO_DONE
var intro_cleaned: Dictionary = {}  # id объекта расчистки -> сколько тапов сделано
var tutorial_served := 0
var level_stars := {}              # id уровня → маска звёзд: 1 пройден, 2 точность, 4 скорость
var upgrades: Array[String] = []    # купленные функциональные улучшения (id из data/upgrades.json)
var keepsakes: Array[String] = []   # найденные в коробках памятные вещи


func _ready() -> void:
	new_game()
	load_game()   # если есть сохранение — оно перекроет начальное состояние


## Начальное состояние новой игры (интро с первой стадии, пустая касса, только стол и пуфик).
func new_game() -> void:
	coins = 0
	served_total = 0
	cat_progress = {}
	last_visit_unix = 0
	city_inside = false
	layout = Data.intro_layout.duplicate(true)
	intro_stage = 0
	intro_cleaned = {}
	tutorial_served = 0
	upgrades = []
	keepsakes = []
	level_stars = {}
	TimeOfDay.hour = 9.0
	Weather.force(Weather.Kind.CLEAR)
	Weather.set_mode(Weather.AUTO)


## Сброс прогресса из настроек аккаунта: удаляет сохранение и начинает игру заново.
func reset_progress() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_game()
	coins_changed.emit(coins)
	save_game()


# ---------------------------------------------------------------- уровни и звёзды

func _sanitize_stars(raw: Variant) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for k in raw:
			out[String(k)] = clampi(int(raw[k]), 0, 7)
	return out


func level_mask(id: String) -> int:
	return int(level_stars.get(id, 0))


## Сколько звёзд (0..3) у уровня.
func level_star_count(id: String) -> int:
	var m := level_mask(id)
	return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1)


## Уровень открыт: первый всегда, дальше — после хотя бы одной звезды на предыдущем.
func level_unlocked(index: int) -> bool:
	return index <= 0 or (index < Data.levels.size() and level_star_count(String(Data.levels[index - 1]["id"])) >= 1)


## Записывает результат: объединяет маски звёзд, возвращает число НОВЫХ звёзд.
func record_level(id: String, mask: int) -> int:
	var before := level_mask(id)
	level_stars[id] = before | mask
	var new_bits := mask & ~before
	save_game()
	return (new_bits & 1) + ((new_bits >> 1) & 1) + ((new_bits >> 2) & 1)


# ---------------------------------------------------------------- улучшения

func has_upgrade(id: String) -> bool:
	return id in upgrades


## Можно ли купить: хватает монет, ещё не куплено, выполнено условие.
func can_buy_upgrade(id: String) -> bool:
	for u in Data.upgrades:
		if String(u["id"]) == id:
			var req := String(u["requires"])
			return not has_upgrade(id) and (req == "" or has_upgrade(req)) and coins >= int(u["price"])
	return false


func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	for u in Data.upgrades:
		if String(u["id"]) == id:
			spend_coins(int(u["price"]))
	upgrades.append(id)
	save_game()
	return true


## Напитки, которые сейчас можно заказать и приготовить.
func drink_ids() -> Array[String]:
	var out: Array[String] = []
	for id in Data.drinks:
		var recipe: Dictionary = Data.drinks[id]["recipe"]
		if bool(recipe["milk"]) and not has_upgrade("milk_pitcher"):
			continue
		if String(id) == "matcha_latte" and not has_upgrade("matcha_kit"):
			continue
		out.append(String(id))
	return out


func pastries_unlocked() -> bool:
	return has_upgrade("display_case")


## Множитель цены напитка от улучшений (кофемашина Pro).
func price_mult(drink_id: String) -> float:
	var base: String = Data.drinks[drink_id]["recipe"]["base"]
	return 1.25 if has_upgrade("espresso_pro") and base == "coffee" else 1.0


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
		"intro_stage": intro_stage,
		"intro_cleaned": intro_cleaned,
		"tutorial_served": tutorial_served,
		"upgrades": upgrades,
		"keepsakes": keepsakes,
		"level_stars": level_stars,
		"weather_mode": Weather.mode,
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
	intro_stage = clampi(int(data.get("intro_stage", INTRO_DONE)), 0, INTRO_DONE)
	intro_cleaned = data.get("intro_cleaned", {})
	tutorial_served = int(data.get("tutorial_served", 0))
	upgrades = _string_array(data.get("upgrades", []))
	keepsakes = _string_array(data.get("keepsakes", []))
	level_stars = _sanitize_stars(data.get("level_stars", {}))
	Weather.set_mode(clampi(int(data.get("weather_mode", Weather.AUTO)), Weather.AUTO, Weather.Kind.SNOW))


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
	if v < 4:
		# v3 — игра уже была в разгаре: интро пропускается, все улучшения открыты, игра идёт как раньше
		data["intro_stage"] = INTRO_DONE
		data["upgrades"] = ["milk_pitcher", "matcha_kit", "display_case"]
		v = 4
	if v > SAVE_VERSION:
		push_warning("Сохранение новее игры (v%d)" % v)
	return data


func _string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for x in raw:
			out.append(String(x))
	return out


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
		elif not CafeRoom.is_wall(fixed["id"]) and CafeRoom.cells(fixed["id"], fixed["c"], fixed["r"]).intersects(CafeRoom.STAFF_CELLS):
			coins += int(Data.furniture[fixed["id"]].get("price", 0))   # стояла там, где теперь служебка: вернули деньги
	room.free()
	return out
