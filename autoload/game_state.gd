extends Node
## Autoload "GameState": монеты, прогресс и сохранение в user://save.json.
## Меняется структура сохранения -> повысить SAVE_VERSION и дописать шаг в _migrate().

signal coins_changed(value: int)
signal setting_changed(key: String)
signal repair_done(id: String)   # задача ремонта выполнена и применена (город перерисовывает зал)

const SAVE_PATH := "user://save.json"
const SAVE_BAK := "user://save.bak"
const SAVE_TMP := "user://save.tmp"
const SAVE_VERSION := 5
## Стадии вступления (v5): игра раньше истории. 0 кадр-заставка, 1 обучающая смена (3 заказа), 2 ставни (ремонт за 1★),
## 3 расчистка зала (ремонт за 2★), 4 — не используется (был «первый магазин»), 5 вступление пройдено.
const INTRO_DONE := 5
const TUTORIAL_STARS := 3   # звёзды за обучающую смену: на них оплачиваются первые два ремонта
const META_DEFAULT := {
	"fish": 0, "boosters": {}, "purchases": [], "first_purchase_done": false,
	"daily": {"last_day": -1, "streak": 0},
	"quests": {"day": -1, "items": [], "box": false},
	"offline": {"pending": 0, "away": 0},
	"shop": {"deal_day": -1, "deal_taken": false, "starter_shown_day": -1, "starter_start": 0, "ads": {}, "last_interstitial": 0, "star_views": 0},
	"season": {"no": 1, "id": "", "start_day": -1, "xp": 0, "free": [], "premium": [], "pass": false},
	"event": {"key": "", "progress": {}, "free": [], "premium": []},
	"decor_views": {},   # id спонсорской мебели → сколько роликов уже просмотрено
	"sessions": 0, "notif_asked": false, "return_gift_pending": false, "clock_max": 0, "last_open_day": -1, "return_gift_day": -1,
}
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
var unlocks: Array[String] = []     # открытое ремонтом: "drink:cocoa", "pastry:eclair", "source:syrup", "cat:bulka"
## Мета-состояние удержания и денег (Economy, Daily, Shop): рыбки, бустеры, ежедневка, задания, офлайн-доход, покупки, сезон.
var meta: Dictionary = META_DEFAULT.duplicate(true)
var story_seen: Array[String] = []  # показанные сюжетные сцены (data/story.json)
var style: Dictionary = {}          # выбранные цвета: {"wall": "mint", "floor": "dark", "trim": "red"}
var shifts_played := 0             # завершённых смен (для подсказок: магазин после 3-й и т. п.)
var settings: Dictionary = SETTINGS_DEFAULT.duplicate()
var install_id := ""               # случайный анонимный идентификатор установки (аналитика)
var first_run_unix := 0
var suppress_popups := false       # тесты и скриншоты: окна при входе (подарок, офлайн-доход) не показываются
var away_seconds := 0              # сколько игрока не было до этого запуска (по last_visit_unix из сохранения)


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
	unlocks = []
	story_seen = []
	meta = META_DEFAULT.duplicate(true)
	style = {}
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

## Очки смены: каждый гость стоит 100 очков (критик 200); обслужил — 60…100 (быстрее — больше), ушёл или получил не то — 0, и потолок смены падает.
## Звёзды — по доле очков от максимума смены.
const POINTS_PER_GUEST := 100
const STAR_FRACTIONS := [0.5, 0.75, 0.9]


func stars_for_score(points: int, cap: int) -> int:
	var n := 0
	for f in STAR_FRACTIONS:
		if cap > 0 and float(points) >= float(cap) * float(f) - 0.001:
			n += 1
	return n


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


func has_unlock(key: String) -> bool:
	if key.begins_with("upgrade:"):
		return has_upgrade(key.substr(8))
	return key in unlocks


## Сколько уровней пройдено (хотя бы одна звезда): по этому числу открываются задачи ремонта.
func levels_cleared() -> int:
	var n := 0
	for lv in Data.levels:
		if level_star_count(String(lv["id"])) >= 1:
			n += 1
	return n


## Состояние задачи: "done", "open" (можно делать, даже если не хватает звёзд), "locked" (не выполнено условие).
func repair_state(id: String) -> String:
	if has_repair(id):
		return "done"
	var def := repair_def(id)
	if def.is_empty():
		return "locked"
	for r in def.get("requires", []):
		if not has_repair(String(r)):
			return "locked"
	if levels_cleared() < int(def.get("after", 0)):
		return "locked"
	return "open"


func _requires_done(def: Dictionary) -> bool:
	for r in def.get("requires", []):
		if not has_repair(String(r)):
			return false
	return true


## Задачи, которые сейчас можно оплатить звёздами (по порядку списка).
func open_repairs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in Data.repairs:
		if repair_state(String(r["id"])) == "open":
			out.append(r)
	return out


## Оплата ремонта звёздами и применение его эффектов. variant — выбранный вариант (для задач с выбором). false — ничего не списано.
func do_repair(id: String, variant := "") -> bool:
	var def := repair_def(id)
	if def.is_empty() or has_repair(id) or repair_state(id) != "open" or stars_free() < int(def["cost"]):
		return false
	var variants: Array = def.get("variants", [])
	if not variants.is_empty():
		var ok := false
		for v in variants:
			ok = ok or String(v["id"]) == variant
		if not ok:
			variant = String(variants[0]["id"])
	stars_spent += int(def["cost"])
	repairs.append(id)
	for e in def.get("effects", []):
		_apply_effect(e, variant)
	save_game()
	Platform.track("repair_done", {"id": id, "variant": variant, "stars_left": stars_free()})
	repair_done.emit(id)
	return true


func _apply_effect(e: Dictionary, variant: String) -> void:
	match String(e["kind"]):
		"furniture":
			place_free(String(e["id"]))
		"style":
			style[String(e["key"])] = variant
		"upgrade":
			if not has_upgrade(String(e["id"])):
				upgrades.append(String(e["id"]))
		"unlock":
			if not (String(e["key"]) in unlocks):
				unlocks.append(String(e["key"]))
		"coins":
			coins += int(e["amount"])
			coins_changed.emit(coins)


## Ставит предмет в зал бесплатно (награда ремонта) на ближайшее к центру место; нет места — возвращает его цену монетами.
func place_free(id: String) -> bool:
	if not Data.furniture.has(id):
		return false
	var room := CafeRoom.new()
	room.layout = layout
	var spot := room.find_free_spot(id)
	room.free()
	if spot.x < 0:
		coins += int(Data.furniture[id].get("price", 0))
		coins_changed.emit(coins)
		return false
	layout.append({"id": id, "c": spot.x, "r": spot.y, "flip": false})
	return true


## Задачи, которые игрок уже получил другим путём (купил улучшение за монеты), закрываем без звёзд.
func sync_repairs() -> void:
	var changed := true
	while changed:
		changed = false
		for r in Data.repairs:
			var id := String(r["id"])
			if has_repair(id) or not _requires_done(r):   # уровень не важен: улучшение уже есть
				continue
			var effects: Array = r.get("effects", [])
			var ups := effects.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "upgrade")
			if ups.is_empty() or not ups.all(func(e: Dictionary) -> bool: return has_upgrade(String(e["id"]))):
				continue
			repairs.append(id)   # улучшение уже куплено: задача считается сделанной, остальные эффекты применяем
			for e in effects:
				if String(e["kind"]) != "upgrade":
					_apply_effect(e, "")
			changed = true


## Цвета зала по выбранным вариантам: {"wall", "stripe", "base", "a", "b", "edge"} (Color).
func style_colors() -> Dictionary:
	var out := {}
	for key in ["wall", "floor", "trim", "sign"]:
		var table: Dictionary = Data.styles.get(key, {})
		var pick := String(style.get(key, ""))
		var variant: Dictionary = table.get(pick, table.get(table.keys()[0], {})) if not table.is_empty() else {}
		for k in variant:
			if String(variant[k]) != "":
				out[k] = Color(String(variant[k]))
	return out


## Приводит сохранённое мета-состояние к виду META_DEFAULT: лишнее отбрасывается, недостающее добавляется, типы выравниваются.
## Словари с пустым образцом (бустеры, счётчики рекламы) принимаются как есть.
func _sanitize_meta(raw: Variant, def: Dictionary) -> Dictionary:
	var src: Dictionary = raw if raw is Dictionary else {}
	var out := {}
	for k in def:
		var d: Variant = def[k]
		if d is Dictionary:
			if (d as Dictionary).is_empty():
				out[k] = (src[k] as Dictionary).duplicate(true) if src.get(k) is Dictionary else {}
			else:
				out[k] = _sanitize_meta(src.get(k, {}), d)
		elif d is Array:
			out[k] = (src[k] as Array).duplicate(true) if src.get(k) is Array else []
		elif d is bool:
			out[k] = bool(src.get(k, d))
		elif d is int:
			out[k] = int(src.get(k, d))
		else:
			out[k] = src.get(k, d)
	return out


func _sanitize_style(raw: Variant) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for key in raw:
			if Data.styles.has(String(key)) and (Data.styles[String(key)] as Dictionary).has(String(raw[key])):
				out[String(key)] = String(raw[key])
	return out


## Какая стадия вступления идёт после обучающей смены: ставни, расчистка или сразу свободная игра.
func stage_after_tutorial() -> int:
	if not has_repair("shutters"):
		return 2
	if not has_repair("cleanup"):
		return 3
	return INTRO_DONE


## Сцены, которые нужно показать после события: kind — "repair" или "level", id — задача или уровень. Уже показанные не повторяются.
func story_for(kind: String, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in Data.story:
		var t: Dictionary = s["trigger"]
		if String(t["kind"]) == kind and String(t["id"]) == id and not (String(s["id"]) in story_seen):
			out.append(s)
	return out


func mark_story_seen(id: String) -> void:
	if not (id in story_seen):
		story_seen.append(id)
		save_game()


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
	sync_repairs()
	save_game()
	Platform.track("upgrade_buy", {"id": id, "coins_left": coins})
	return true


func _needs_met(item: Dictionary) -> bool:
	for k in item.get("needs", []):
		if not has_unlock(String(k)):
			return false
	return true


## Напитки, которые сейчас можно заказать и приготовить (все условия `needs` из drinks.json выполнены).
func drink_ids() -> Array[String]:
	var out: Array[String] = []
	for id in Data.drinks:
		if _needs_met(Data.drinks[id]):
			out.append(String(id))
	return out


func pastries_unlocked() -> bool:
	return has_upgrade("display_case")


## Выпечка в продаже: пусто, пока нет витрины; иначе все, чьи условия выполнены (по порядку).
func pastry_ids() -> Array[String]:
	var out: Array[String] = []
	if not pastries_unlocked():
		return out
	for id in Data.pastries:
		if _needs_met(Data.pastries[id]):
			out.append(String(id))
	return out


## Коты, которые приходят в кафе: трое первых всегда, остальные — после задач ремонта ("cat:id").
func cats_available() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in Data.cats:
		if bool(c.get("starter", false)) or has_unlock("cat:%s" % String(c["id"])):
			out.append(c)
	return out


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


# ---------------------------------------------------------------- коты: симпатия и записи

const LIKE_STEPS := [5, 15, 30]       # сколько заказов нужно коту для 1-й, 2-й и 3-й записи в «Книге котов»
const LIKE_REWARD := [20, 40, 80]     # монеты за запись


func cat_likes(id: String) -> int:
	return int((cat_progress.get(id, {}) as Dictionary).get("likes", 0))


## Сколько записей открыто (0..3).
func cat_entries(id: String) -> int:
	var n := 0
	for step in LIKE_STEPS:
		if cat_likes(id) >= int(step):
			n += 1
	return n


## Кот получил свой заказ: +1 симпатия. Возвращает номер новой записи (0..2) или -1; монеты за запись начисляются сразу.
func add_like(id: String) -> int:
	var before := cat_entries(id)
	var rec: Dictionary = cat_progress.get(id, {"likes": 0})
	rec["likes"] = int(rec.get("likes", 0)) + 1
	cat_progress[id] = rec
	var after := cat_entries(id)
	if after > before:
		add_coins(int(LIKE_REWARD[after - 1]))
		Platform.track("cat_entry", {"cat": id, "entry": after})
		return after - 1
	return -1

# ---------------------------------------------------------------- таланты котов и «Уют» кафе

const PERK_CAP := {"tips": 0.3, "patience": 0.25, "pastry_tips": 0.4, "warm": 0.4, "fast": 3.0, "riddle": 0.6, "price": 0.12}
## Талант кота работает, когда он в кафе и у него открыта первая запись (5 заказов).
func perk_active(cat_id: String) -> bool:
	for c in Data.cats:
		if String(c["id"]) == cat_id:
			return c.has("perk") and (bool(c.get("starter", false)) or has_unlock("cat:%s" % cat_id)) and cat_entries(cat_id) >= 1
	return false


## Сумма действующих талантов одного вида (с потолком).
func perk_total(kind: String) -> float:
	var sum := 0.0
	for c in Data.cats:
		var p: Dictionary = c.get("perk", {})
		if String(p.get("kind", "")) == kind and perk_active(String(c["id"])):
			sum += float(p["value"])
	return minf(sum, float(PERK_CAP.get(kind, 1.0)))


## Описание таланта кота для «Книги котов».
func perk_text(def: Dictionary) -> String:
	var p: Dictionary = def.get("perk", {})
	var v := float(p.get("value", 0.0))
	match String(p.get("kind", "")):
		"tips": return tr("+%d%% чаевых") % int(round(v * 100.0))
		"patience": return tr("+%d%% терпения") % int(round(v * 100.0))
		"pastry_tips": return tr("+%d%% чаевых с выпечки") % int(round(v * 100.0))
		"warm": return tr("горячее дольше +%d%%") % int(round(v * 100.0))
		"fast": return tr("+%d за скорость") % int(v)
		"riddle": return tr("+%d%% за загадки") % int(round(v * 100.0))
		"price": return tr("+%d%% к цене") % int(round(v * 100.0))
	return ""


const COZY_MAX := 100                      # потолок шкалы уюта
const COZY_TIPS := 0.35                    # чаевые при уюте 100: +35%
const COZY_PATIENCE := 0.20                # терпение гостей при уюте 100: +20%
const COZY_VARIETY := 2                    # очков за каждый вид мебели, которая есть в кафе


## Очки уюта: `cozy` каждого предмета в зале (из data/furniture.json) + бонус за разнообразие видов.
func cozy_points() -> int:
	var pts := 0
	var kinds := {}
	for it in layout:
		var id := String(it.get("id", ""))
		if not Data.furniture.has(id):
			continue
		pts += int(Data.furniture[id].get("cozy", 1))
		kinds[id] = true
	return pts + COZY_VARIETY * kinds.size()


## Уют 0…100: от него растут чаевые и терпение гостей (линейно до потолка).
func cozy_score() -> int:
	return clampi(cozy_points(), 0, COZY_MAX)


func cozy_tip_bonus() -> float:
	return COZY_TIPS * float(cozy_score()) / float(COZY_MAX)


func cozy_patience_bonus() -> float:
	return COZY_PATIENCE * float(cozy_score()) / float(COZY_MAX)


## Тестовая сборка («Для тестов»): открывает источники, рецепты, улучшения и выпечку, чтобы сразу играть смены главы 4+.
func debug_unlock_all() -> void:
	for key in ["source:syrup", "source:ice", "source:spice", "source:cream", "drink:cocoa", "drink:raf", "drink:sea_tea", "drink:hot_choc", "drink:caramel", "drink:sbiten", "pastry:syrniki", "pastry:eclair", "pastry:pirozhok", "pastry:medovik", "pastry:keks"]:
		if not (key in unlocks):
			unlocks.append(key)
	for u in Data.upgrades:
		if not has_upgrade(String(u["id"])):
			upgrades.append(String(u["id"]))
	shifts_played = maxi(shifts_played, 10)
	coins += 2000
	coins_changed.emit(coins)
	save_game()


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
		"unlocks": unlocks,
		"story_seen": story_seen,
		"meta": meta,
		"style": style,
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
	away_seconds = maxi(0, int(Time.get_unix_time_from_system()) - last_visit_unix) if last_visit_unix > 0 else 0
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
	unlocks = _string_array(data.get("unlocks", []))
	story_seen = _string_array(data.get("story_seen", []))
	meta = _sanitize_meta(data.get("meta", {}), META_DEFAULT)
	style = _sanitize_style(data.get("style", {}))
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
	sync_repairs()
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
	# прилавок обязателен: нет в сохранении (старые игры, ошибка) — ставим на подходящее место, при нехватке места убираем мебель с участка и возвращаем её цену
	var has_counter := false
	for it in out:
		if CafeRoom.is_counter(String(it["id"])):
			has_counter = true
	if not has_counter:
		var spot := room.find_counter_spot()
		if spot.x < 0:
			spot = CafeRoom.DEFAULT_COUNTER
			var zone := Rect2i(spot.x, spot.y, 3, 2)
			for k in range(out.size() - 1, -1, -1):
				var oid := String(out[k]["id"])
				if CafeRoom.is_solid(oid) and CafeRoom.cells(oid, int(out[k]["c"]), int(out[k]["r"])).intersects(zone):
					coins += int(Data.furniture[oid].get("price", 0))
					out.remove_at(k)
		out.insert(0, {"id": CafeRoom.COUNTER_ID, "c": spot.x, "r": spot.y, "flip": false})
	room.free()
	return out
