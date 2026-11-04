extends Node
## Autoload "GameState": монеты, прогресс и сохранение в user://save.json.
## Меняется структура сохранения -> повысить SAVE_VERSION и дописать шаг в _migrate().

signal coins_changed(value: int)
signal setting_changed(key: String)

const SAVE_PATH := "user://save.json"
const SAVE_BAK := "user://save.bak"
const SAVE_TMP := "user://save.tmp"
const SAVE_VERSION := 5
## Стадии вступления (v5): игра раньше истории. 0 кадр-заставка, 1 обучающая смена (3 заказа), 2 ставни (ремонт за 1★),
## 3 расчистка зала (ремонт за 2★), 4 — не используется (был «первый магазин»), 5 вступление пройдено.
const INTRO_DONE := 5
const TUTORIAL_STARS := 3   # звёзды за обучающую смену: на них оплачиваются первые два ремонта
const SETTINGS_DEFAULT := {"lang": "auto", "music": 0.8, "sfx": 1.0, "quality": "auto", "analytics": true, "notifications": true}

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
var stars_bonus := 0               # звёзды не из уровней (награда за обучение и т. п.)
var stars_spent := 0               # потрачено на ремонт
var repairs: Array[String] = []     # выполненные задачи ремонта (data/repairs.json)
var shifts_played := 0             # завершённых смен (для подсказок: магазин после 3-й и т. п.)
var settings: Dictionary = SETTINGS_DEFAULT.duplicate()
var install_id := ""               # случайный анонимный идентификатор установки (аналитика)
var first_run_unix := 0


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
	stars_bonus = 0
	stars_spent = 0
	repairs = []
	shifts_played = 0
	if install_id == "":
		install_id = "%08x%08x" % [randi(), randi()]
	if first_run_unix == 0:
		first_run_unix = int(Time.get_unix_time_from_system())
	TimeOfDay.hour = 9.0
	Weather.force(Weather.Kind.CLEAR)
	Weather.set_mode(Weather.AUTO)


## Сброс прогресса из настроек аккаунта: удаляет сохранение и начинает игру заново.
func reset_progress() -> void:
	for path in [SAVE_PATH, SAVE_BAK]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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


# ---------------------------------------------------------------- звёзды и ремонт

## Всего заработано звёзд: уровни + бонусы.
func stars_total() -> int:
	var n := stars_bonus
	for id in level_stars:
		n += level_star_count(String(id))
	return n


func stars_free() -> int:
	return maxi(stars_total() - stars_spent, 0)


func has_repair(id: String) -> bool:
	return id in repairs


func repair_def(id: String) -> Dictionary:
	for r in Data.repairs:
		if String(r["id"]) == id:
			return r
	return {}


## Оплата ремонта звёздами. false — не хватает или уже сделано (ничего не списано).
func do_repair(id: String) -> bool:
	var def := repair_def(id)
	if def.is_empty() or has_repair(id) or stars_free() < int(def["cost"]):
		return false
	stars_spent += int(def["cost"])
	repairs.append(id)
	save_game()
	Platform.track("repair_done", {"id": id, "stars_left": stars_free()})
	return true


## Какая стадия вступления идёт после обучающей смены: ставни, расчистка или сразу свободная игра.
func stage_after_tutorial() -> int:
	if not has_repair("shutters"):
		return 2
	if not has_repair("cleanup"):
		return 3
	return INTRO_DONE


func get_setting(key: String) -> Variant:
	return settings.get(key, SETTINGS_DEFAULT.get(key))


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	if key == "lang":
		Loc.apply(String(value))
	elif key == "analytics":
		Platform.analytics_enabled = bool(value)
	setting_changed.emit(key)
	save_game()


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
	Platform.track("upgrade_buy", {"id": id, "coins_left": coins})
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


## Смена закончена (не обучающая): считаем для подсказок и аналитики.
func register_shift() -> void:
	shifts_played += 1


## Сохранение: пишем во временный файл, проверяем, прошлое сохранение уходит в save.bak — обрыв записи не портит игру.
## В файл добавлено поле "crc" (md5 остальных полей): по нему при загрузке отличаем целое сохранение от битого.
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
		"stars_bonus": stars_bonus,
		"stars_spent": stars_spent,
		"repairs": repairs,
		"shifts_played": shifts_played,
		"settings": settings,
		"install_id": install_id,
		"first_run_unix": first_run_unix,
	}
	data["crc"] = _crc(data)
	var f := FileAccess.open(SAVE_TMP, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось записать сохранение: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data))
	f.close()
	var current := _read_save(SAVE_PATH)
	if not current.is_empty() and not current.has("_crc_bad"):   # в запасной файл — только целое сохранение
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_BAK))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_TMP), ProjectSettings.globalize_path(SAVE_PATH))


## Контрольная сумма сохранения: md5 JSON без поля "crc" (ключи отсортированы).
func _crc(data: Dictionary) -> String:
	var copy := data.duplicate()
	copy.erase("crc")
	return JSON.stringify(_canon(copy), "", true).md5_text()


## После записи в JSON и чтения обратно целые числа становятся дробными (9 → 9.0): приводим к одному виду перед суммой.
func _canon(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _canon(v[k])
		return out
	if v is Array:
		var arr := []
		for x in v:
			arr.append(_canon(x))
		return arr
	if v is float and is_finite(v) and absf(v) < 1.0e15 and is_equal_approx(v, roundf(v)):
		return int(roundf(v))
	return v


## Читает файл сохранения; пустой словарь — нет файла или он повреждён (нужен запасной).
func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_warning("Сохранение %s повреждено" % path)
		return {}
	var d: Dictionary = parsed
	if d.has("crc") and String(d["crc"]) != _crc(d):
		# содержимое менялось после записи: игру не ломаем, но сумма уже не сходится; запасное, если оно целее
		push_warning("Контрольная сумма %s не сошлась" % path)
		d["_crc_bad"] = true
	return d


func load_game() -> void:
	var d := _read_save(SAVE_PATH)
	if d.is_empty() or d.has("_crc_bad"):
		var bak := _read_save(SAVE_BAK)
		if not bak.is_empty() and not bak.has("_crc_bad"):
			d = bak
		elif d.is_empty():
			d = bak
	if d.is_empty():
		_apply_settings_side_effects()
		return
	d.erase("_crc_bad")
	var data := _migrate(d)
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
	stars_bonus = maxi(int(data.get("stars_bonus", 0)), 0)
	stars_spent = maxi(int(data.get("stars_spent", 0)), 0)
	repairs = _string_array(data.get("repairs", []))
	shifts_played = maxi(int(data.get("shifts_played", 0)), 0)
	settings = SETTINGS_DEFAULT.duplicate()
	var raw_settings: Variant = data.get("settings", {})
	if raw_settings is Dictionary:
		for k in SETTINGS_DEFAULT:
			if (raw_settings as Dictionary).has(k):
				settings[k] = raw_settings[k]
	install_id = String(data.get("install_id", install_id))
	first_run_unix = int(data.get("first_run_unix", first_run_unix))
	Weather.set_mode(clampi(int(data.get("weather_mode", Weather.AUTO)), Weather.AUTO, Weather.Kind.SNOW))
	_apply_settings_side_effects()


func _apply_settings_side_effects() -> void:
	Loc.apply(String(get_setting("lang")))
	Platform.analytics_enabled = bool(get_setting("analytics"))


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
	if v < 5:
		# v5: игра раньше истории. Старые стадии: 0 комикс, 1 ставни, 2 расчистка, 3 обучение, 4 магазин, 5 готово.
		# Новые: 0 заставка, 1 обучение, 2 ставни, 3 расчистка, 5 готово. Что игрок уже сделал, то помечаем выполненным ремонтом.
		var old := int(data.get("intro_stage", 5))
		var done_repairs: Array = []
		var stage := old
		match old:
			0, 1:
				stage = old   # ставни ещё закрыты: обучение, потом ставни
			2:
				stage = 3
				done_repairs = ["shutters"]
				data["stars_bonus"] = TUTORIAL_STARS
				data["stars_spent"] = 1
			_:
				stage = INTRO_DONE   # кафе уже расчищено (обучение при этом пропускаем): всё оплачено
				done_repairs = ["shutters", "cleanup"]
		data["intro_stage"] = stage
		data["repairs"] = done_repairs
		v = 5
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
