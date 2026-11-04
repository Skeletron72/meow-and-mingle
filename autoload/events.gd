extends Node
## Autoload "Events": временные события (data/events.json) — 7–60 дней по календарю, 10 заданий, 3 ступени наград (бесплатная и платная линии;
## платная — у владельцев «Мурлык-пасса»). Задания считаются теми же событиями игры, что и ежедневные (Daily.report) + «подай N таких-то напитков».
## Состояние — GameState.meta["event"]; новый запуск события (год или id другой) сбрасывает прогресс.

signal changed


# ---------------------------------------------------------------- календарь

## Дата «сейчас» в виде {"month", "day", "year"} (местное время устройства).
func _date() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(Daily.now_unix() + Daily.tz_offset())


func _md(text: String) -> int:   # "09-01" → 901
	var p := text.split("-")
	return int(p[0]) * 100 + int(p[1])


## Событие, идущее сегодня, или {}. Событие может переходить через Новый год (15.12–10.01).
func active() -> Dictionary:
	var d := _date()
	var now_md := int(d["month"]) * 100 + int(d["day"])
	for ev in Data.events:
		var a := _md(String(ev["start"]))
		var b := _md(String(ev["end"]))
		if (a <= b and now_md >= a and now_md <= b) or (a > b and (now_md >= a or now_md <= b)):
			return ev
	return {}


## Ключ запуска: id + год начала (на новый год события начинаются заново).
func run_key(ev: Dictionary) -> String:
	var d := _date()
	var a := _md(String(ev["start"]))
	var b := _md(String(ev["end"]))
	var now_md := int(d["month"]) * 100 + int(d["day"])
	var year := int(d["year"])
	if a > b and now_md <= b:
		year -= 1   # январская часть зимнего события принадлежит прошлогоднему запуску
	return "%s_%d" % [String(ev["id"]), year]


func days_left() -> int:
	var ev := active()
	if ev.is_empty():
		return 0
	var d := _date()
	var end_md := _md(String(ev["end"]))
	var end_year := int(d["year"])
	if _md(String(ev["start"])) > end_md and int(d["month"]) * 100 + int(d["day"]) > end_md:
		end_year += 1
	var end_unix := Time.get_unix_time_from_datetime_dict({"year": end_year, "month": end_md / 100, "day": end_md % 100, "hour": 23, "minute": 59, "second": 59})
	return maxi(0, int(ceil(float(end_unix - (Daily.now_unix() + Daily.tz_offset())) / 86400.0)))


func next_event() -> Dictionary:
	var d := _date()
	var now_md := int(d["month"]) * 100 + int(d["day"])
	var best := {}
	var best_gap := 99999
	for ev in Data.events:
		var gap := (_md(String(ev["start"])) - now_md + 1300) % 1300
		if gap > 0 and gap < best_gap:
			best_gap = gap
			best = ev
	return best


## Подготавливает состояние под текущий запуск; возвращает его (или {}, если события нет).
func _state() -> Dictionary:
	var ev := active()
	if ev.is_empty():
		return {}
	var st: Dictionary = GameState.meta["event"]
	var key := run_key(ev)
	if String(st["key"]) != key:
		st["key"] = key
		st["progress"] = {}
		st["free"] = []
		st["premium"] = []
	return st


# ---------------------------------------------------------------- задания и награды

## Задания события для экрана: {"id", "name", "target", "progress", "done"}.
func tasks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ev := active()
	var st := _state()
	if ev.is_empty():
		return out
	for t in ev["tasks"]:
		var p := int((st["progress"] as Dictionary).get(String(t["id"]), 0))
		out.append({"id": String(t["id"]), "name": String(t["name"]), "target": int(t["target"]), "progress": mini(p, int(t["target"])), "done": p >= int(t["target"])})
	return out


func done_count() -> int:
	return tasks().filter(func(t: Dictionary) -> bool: return bool(t["done"])).size()


## Событие игры: kind — как в data/quests.json или "drink:<id>"; n — на сколько продвинулось.
func report(kind: String, n := 1) -> void:
	var ev := active()
	if ev.is_empty() or GameState.intro_stage < GameState.INTRO_DONE:
		return
	var st := _state()
	var progress: Dictionary = st["progress"]
	var any := false
	for t in ev["tasks"]:
		if String(t["kind"]) != kind:
			continue
		var id := String(t["id"])
		var before := int(progress.get(id, 0))
		if before >= int(t["target"]):
			continue
		progress[id] = before + n
		any = true
		if before + n >= int(t["target"]):
			Platform.track("event_task", {"event": String(ev["id"]), "task": id})
	if any:
		changed_emit()


func changed_emit() -> void:
	changed.emit()


func tiers() -> Array:
	return active().get("tiers", [])


func tier_open(i: int) -> bool:
	return done_count() >= int(tiers()[i]["need"])


func tier_claimed(i: int, premium: bool) -> bool:
	var st := _state()
	return not st.is_empty() and i in (st["premium" if premium else "free"] as Array)


## Забрать награду ступени (платная линия — только с «Мурлык-пассом»). Возвращает текст награды или "".
func claim(i: int, premium: bool) -> String:
	var st := _state()
	if st.is_empty() or i < 0 or i >= tiers().size() or not tier_open(i) or tier_claimed(i, premium) or (premium and not Shop.has_pass()):
		return ""
	(st["premium" if premium else "free"] as Array).append(i)
	Platform.track("event_claim", {"event": String(active()["id"]), "tier": i + 1, "premium": premium})
	changed_emit()
	return Economy.grant(tiers()[i]["premium" if premium else "free"], "event")


func claimable_count() -> int:
	var n := 0
	for i in tiers().size():
		if tier_open(i) and not tier_claimed(i, false):
			n += 1
		if tier_open(i) and Shop.has_pass() and not tier_claimed(i, true):
			n += 1
	return n
