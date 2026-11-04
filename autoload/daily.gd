extends Node
## Autoload "Daily": то, что возвращает игрока каждый день — подарок дня (лента из 7 дней со стриком), три задания дня и «ящик дня»,
## офлайн-доход («пока тебя не было…»), подарок за возвращение через 3 дня и планирование напоминаний.
## Дни считаются по местному времени устройства; откат часов назад игнорируется (GameState.meta.clock_max).

signal quests_changed
signal offline_ready(coins: int)      # игрок вернулся и есть офлайн-доход: город покажет окно
signal return_gift_ready

const OFFLINE_MIN_SECONDS := 600          # меньше 10 минут — не считаем
const OFFLINE_MAX_HOURS := 8.0
const OFFLINE_MIN_SHIFTS := 5             # офлайн-доход — с 5-й смены (план 03)
const QUESTS_MIN_SHIFTS := 3              # задания — с 3-й смены
const RETURN_AFTER_DAYS := 3
const NOTIFY_WINDOW := Vector2i(12, 21)   # напоминания только в это окно местного времени
const NOTIFY_ID := "return"
const QUEST_COUNT := 3
const QUEST_XP := 20

var time_override := 0   # тесты: «сейчас» (unix); 0 — настоящее время


# ---------------------------------------------------------------- время

## Текущее время с защитой от отката часов: не меньше самого позднего, что мы видели.
func now_unix() -> int:
	var now := time_override if time_override > 0 else int(Time.get_unix_time_from_system())
	var seen := int(GameState.meta["clock_max"])
	if now > seen:
		GameState.meta["clock_max"] = now
		return now
	return seen


func tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func day_of(unix: int) -> int:
	return int(floor(float(unix + tz_offset()) / 86400.0))


func today() -> int:
	return day_of(now_unix())


# ---------------------------------------------------------------- старт сеанса

## Вызывается один раз при запуске игры (город): считает сеансы, дни, офлайн-доход и подарок за возвращение.
func start_session() -> void:
	var m: Dictionary = GameState.meta
	m["sessions"] = int(m["sessions"]) + 1
	var away := GameState.away_seconds
	GameState.away_seconds = 0
	m["last_open_day"] = today()
	check_offline(away)
	Platform.track("daily_open", {"day": today(), "sessions": m["sessions"], "away": away, "streak": int(m["daily"]["streak"])})
	GameState.save_game()


## Игрок вернулся после away секунд: начисляем офлайн-доход (в «ожидание» — получить в окне) и подарок за возвращение.
func check_offline(away: int) -> void:
	if away >= RETURN_AFTER_DAYS * 86400 and int(GameState.meta["return_gift_day"]) != today() and GameState.shifts_played >= 3:
		GameState.meta["return_gift_day"] = today()
		GameState.meta["return_gift_pending"] = true
		return_gift_ready.emit()
	if GameState.shifts_played < OFFLINE_MIN_SHIFTS or away < OFFLINE_MIN_SECONDS:
		return
	var coins := offline_amount(away)
	if coins > 0:
		(GameState.meta["offline"] as Dictionary)["pending"] = int((GameState.meta["offline"] as Dictionary)["pending"]) + coins
		(GameState.meta["offline"] as Dictionary)["away"] = away
		GameState.save_game()
		offline_ready.emit(offline_pending())


## Монеты в час: растут с ремонтом и улучшениями (кафе «обживается»).
func offline_rate() -> int:
	return 12 + 2 * GameState.repairs.size() + 3 * GameState.upgrades.size()


func offline_amount(away_seconds: int) -> int:
	var hours := minf(float(away_seconds) / 3600.0, OFFLINE_MAX_HOURS)
	return int(round(hours * float(offline_rate())))


func offline_pending() -> int:
	return int((GameState.meta["offline"] as Dictionary)["pending"])


## Забирает офлайн-доход; double — после просмотра рекламы (×2). Возвращает выданное.
func claim_offline(double := false) -> int:
	var n := offline_pending()
	if n <= 0:
		return 0
	if double:
		n *= 2
	(GameState.meta["offline"] as Dictionary)["pending"] = 0
	Economy.earn_coins(n, "offline_x2" if double else "offline")
	Platform.track("offline_claim", {"coins": n, "away": int((GameState.meta["offline"] as Dictionary)["away"]), "double": double})
	return n


## Подарок за возвращение: фикс-набор.
func claim_return_gift() -> String:
	GameState.meta["return_gift_pending"] = false
	return Economy.grant({"fish": 5, "boosters": {"patience": 1, "cat_help": 1}}, "return_gift")


func on_resume() -> void:
	Platform.cancel_notification(NOTIFY_ID)
	var m: Dictionary = GameState.meta
	var away := maxi(0, now_unix() - GameState.last_visit_unix)
	if day_of(now_unix()) != int(m["last_open_day"]):
		m["last_open_day"] = today()
		Platform.track("daily_open", {"day": today(), "resume": true, "away": away})
	check_offline(away)
	quests_changed.emit()


# ---------------------------------------------------------------- подарок дня

func gift_ready() -> bool:
	return int(GameState.meta["daily"]["last_day"]) < today()


## День ленты (1..7), который будет выдан при ближайшем получении: подряд — следующий, пропуск дня — снова первый.
func gift_day() -> int:
	var d: Dictionary = GameState.meta["daily"]
	var streak := int(d["streak"])
	if int(d["last_day"]) == today() - 1:
		return (streak % Data.daily_gifts.size()) + 1
	if int(d["last_day"]) == today():
		return ((streak - 1) % Data.daily_gifts.size()) + 1   # уже получен сегодня
	return 1


## День, который «горит» в ленте: уже полученный сегодня или ближайший.
func gift_streak() -> int:
	return int(GameState.meta["daily"]["streak"])


## Забрать подарок. double — после рекламы: награда ×2 (монеты и рыбки удваиваются, бустеры и мебель — нет). Возвращает текст награды или "".
func claim_gift(double := false) -> String:
	if not gift_ready():
		return ""
	var day := gift_day()
	var d: Dictionary = GameState.meta["daily"]
	d["streak"] = day
	d["last_day"] = today()
	var reward: Dictionary = (Data.daily_gifts[day - 1] as Dictionary).duplicate(true)
	if double:
		for k in ["coins", "fish"]:
			if reward.has(k):
				reward[k] = int(reward[k]) * 2
	Platform.track("daily_claim", {"day": day, "double": double})
	return Economy.grant(reward, "daily_gift")


# ---------------------------------------------------------------- задания дня

func quests_unlocked() -> bool:
	return GameState.shifts_played >= QUESTS_MIN_SHIFTS


## Три задания на сегодня: выбор зависит только от даты (один и тот же в течение дня), разные виды, без недоступных (выпечка без витрины).
func ensure_quests() -> void:
	var q: Dictionary = GameState.meta["quests"]
	if int(q["day"]) == today() or not quests_unlocked():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = today() * 7919 + 13
	var pool: Array[Dictionary] = []
	for t in Data.quest_pool:
		if String(t["kind"]) == "pastry" and not GameState.pastries_unlocked():
			continue
		pool.append(t)
	var picked: Array = []
	var kinds := {}
	var guard := 0
	while picked.size() < QUEST_COUNT and guard < 100:
		guard += 1
		var t: Dictionary = pool[rng.randi() % pool.size()]
		if kinds.has(String(t["kind"])):
			continue
		kinds[String(t["kind"])] = true
		picked.append({"id": String(t["id"]), "progress": 0, "claimed": false})
	q["day"] = today()
	q["items"] = picked
	q["box"] = false
	quests_changed.emit()


func quest_template(id: String) -> Dictionary:
	for t in Data.quest_pool:
		if String(t["id"]) == id:
			return t
	return {}


## Задания дня как данные для экрана: {"i", "name", "target", "progress", "done", "claimed", "reward"}.
func quests() -> Array[Dictionary]:
	ensure_quests()
	var out: Array[Dictionary] = []
	var items: Array = GameState.meta["quests"]["items"]
	for i in items.size():
		var it: Dictionary = items[i]
		var t := quest_template(String(it["id"]))
		if t.is_empty():
			continue
		out.append({"i": i, "id": String(it["id"]), "name": String(t["name"]), "target": int(t["target"]), "progress": mini(int(it["progress"]), int(t["target"])),
			"done": int(it["progress"]) >= int(t["target"]), "claimed": bool(it["claimed"]), "reward": _quest_reward(t)})
	return out


func _quest_reward(t: Dictionary) -> Dictionary:
	var r := {}
	for k in ["coins", "fish"]:
		if t.has(k):
			r[k] = int(t[k])
	return r


## Событие игры: kind из data/quests.json (serve, pastry, fast, level, stars, perfect, coins, tips), n — на сколько продвинулось.
func report(kind: String, n := 1) -> void:
	if not quests_unlocked() or n <= 0:
		return
	ensure_quests()
	var changed := false
	for it in GameState.meta["quests"]["items"]:
		var t := quest_template(String(it["id"]))
		if String(t.get("kind", "")) != kind or bool(it["claimed"]):
			continue
		var was := int(it["progress"]) >= int(t["target"])
		it["progress"] = int(it["progress"]) + n
		changed = true
		if not was and int(it["progress"]) >= int(t["target"]):
			Platform.track("quest_done", {"id": String(it["id"])})
	if changed:
		quests_changed.emit()


func claim_quest(i: int) -> String:
	var list := quests()
	if i < 0 or i >= list.size() or not bool(list[i]["done"]) or bool(list[i]["claimed"]):
		return ""
	GameState.meta["quests"]["items"][i]["claimed"] = true
	Shop.add_season_xp(QUEST_XP, "quest")
	quests_changed.emit()
	return Economy.grant(list[i]["reward"], "quest")


func box_ready() -> bool:
	var list := quests()
	return list.size() == QUEST_COUNT and list.all(func(x: Dictionary) -> bool: return bool(x["claimed"])) and not bool(GameState.meta["quests"]["box"])


## «Ящик дня» за все три задания: рыбки и случайный бустер.
func claim_box() -> String:
	if not box_ready():
		return ""
	GameState.meta["quests"]["box"] = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var b := String(Economy.BOOSTER_IDS[rng.randi() % Economy.BOOSTER_IDS.size()])
	quests_changed.emit()
	return Economy.grant({"fish": 3, "boosters": {b: 1}}, "quest_box")


## Сколько заданий можно забрать прямо сейчас (для значка на кнопке).
func claimable_count() -> int:
	var n := 0
	for qd in quests():
		if bool(qd["done"]) and not bool(qd["claimed"]):
			n += 1
	return n + (1 if box_ready() else 0)


# ---------------------------------------------------------------- напоминания

## Ближайший момент в окне 12:00–21:00 местного времени, не раньше unix.
func next_window_time(unix: int) -> int:
	var local := unix + tz_offset()
	var day_start := int(floor(float(local) / 86400.0)) * 86400
	var sec := local - day_start
	if sec < NOTIFY_WINDOW.x * 3600:
		return day_start + NOTIFY_WINDOW.x * 3600 - tz_offset()
	if sec > NOTIFY_WINDOW.y * 3600:
		return day_start + 86400 + NOTIFY_WINDOW.x * 3600 - tz_offset()
	return unix


## При сворачивании: одно напоминание (не чаще раза в день) через ~8 часов, сдвинутое в окно. Текст — по тому, что будет ждать.
func plan_notifications() -> void:
	Platform.cancel_notification(NOTIFY_ID)
	if not bool(GameState.get_setting("notifications")) or not bool(GameState.meta["notif_asked"]):
		return
	var now := now_unix()
	var at := next_window_time(now + int(OFFLINE_MAX_HOURS * 3600.0))
	var body := tr("Кафе заработало монеты, пока тебя не было!")
	if day_of(at) > int(GameState.meta["daily"]["last_day"]):
		body = tr("Подарок дня уже ждёт тебя!")
	Platform.schedule_notification(NOTIFY_ID, float(at - now), tr("Тёплая Лапка"), body)


## Пора ли спросить разрешение на уведомления: после 2-го сеанса и 3-й смены, один раз.
func should_ask_notifications() -> bool:
	return not bool(GameState.meta["notif_asked"]) and int(GameState.meta["sessions"]) >= 2 and GameState.shifts_played >= 3


func answer_notifications(allow: bool) -> void:
	GameState.meta["notif_asked"] = true
	if allow:
		Platform.request_notification_permission(func(granted: bool) -> void:
			GameState.set_setting("notifications", granted)
			Platform.track("push_permission", {"result": granted}))
	else:
		GameState.set_setting("notifications", false)
		Platform.track("push_permission", {"result": false})
	GameState.save_game()
