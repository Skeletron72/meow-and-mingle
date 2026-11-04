class_name RepairBoard
extends ListScreen
## «Ремонт кафе»: доска задач на общем экране-списке. Первыми — задачи, которые уже можно делать, потом закрытые (с причиной).
## Тап по кнопке со звёздами тратит их (GameState.do_repair); у задач с выбором (цвет стен, пола, вывески) сначала спрашивается вариант.
## Когда на ближайшую задачу не хватает 1–2 звёзд, первой стоит карточка «звезда за рекламу».

var _choosing := ""        # id задачи, для которой выбираем вариант


func _init() -> void:
	super._init()
	title = "Ремонт кафе"
	provider = _provide
	header_provider = func() -> Array: return [{"icon": "star", "text": str(GameState.stars_free())}]


## Строки доски: сначала открытые задачи, затем закрытые (по порядку списка), выполненные не показываем.
func rows() -> Array[Dictionary]:
	var open: Array[Dictionary] = []
	var locked: Array[Dictionary] = []
	for r in Data.repairs:
		match GameState.repair_state(String(r["id"])):
			"open":
				open.append(r)
			"locked":
				locked.append(r)
	return open + locked


## Карточка «звезда за рекламу» нужна, когда на ближайшую задачу не хватает звёзд (1–2) и дневной лимит не исчерпан.
func ad_card_wanted() -> bool:
	if not Shop.ad_ready("star"):
		return false
	var best := 999
	for r in rows():
		if GameState.repair_state(String(r["id"])) == "open":
			best = mini(best, int(r["cost"]) - GameState.stars_free())
	return best >= 1 and best <= 2


func _all_rows() -> Array:
	var out: Array = rows()
	if ad_card_wanted():
		out.push_front({"id": "__ad__"})
	return out


func _provide(_tab: int) -> Array:
	if _choosing != "":
		return _variant_cards()
	var cards: Array = []
	for r in _all_rows():
		cards.append(_card_for(r))
	if cards.is_empty():
		cards.append({"title": "Всё отремонтировано!", "icon": "check", "enabled": false})
	return cards


func _card_for(r: Dictionary) -> Dictionary:
	if String(r["id"]) == "__ad__":
		var views := int((GameState.meta["shop"] as Dictionary)["star_views"])
		return {"title": tr("Звезда за рекламу"), "sub": tr("Два ролика = 1★ (%d/2)") % views, "icon": "video", "tint": Color(1.1, 1.05, 0.8),
			"action": {"text": "+1", "icon": "star", "press": _watch_for_star}}
	var id := String(r["id"])
	var open := GameState.repair_state(id) == "open"
	var cost := int(r["cost"])
	if not open:
		return {"title": String(r["name"]), "sub": _lock_reason(r), "icon": "lock", "enabled": false}
	return {"title": String(r["name"]), "sub": String(r["blurb"]), "icon": String(r["icon"]),
		"action": {"text": str(cost), "icon": "star", "enabled": GameState.stars_free() >= cost, "press": _pick.bind(id)}}


func _watch_for_star() -> void:
	Shop.watch_for_star(func(ok: bool, got: bool) -> void:
		if not is_inside_tree():
			return
		if got:
			Audio.sfx("star", 0.0)
			Fx.burst(_root, Vector2(180, 300), "star", Color("ffe08a"), 12, 240.0, 200.0, 1.0, 1.2)
		elif not ok:
			Ui.toast(_root, tr("Реклама недоступна"), Vector2(180, 600))
		refresh())


## Почему задача закрыта: чего не хватает.
func _lock_reason(r: Dictionary) -> String:
	for req in r.get("requires", []):
		if not GameState.has_repair(String(req)):
			var d := GameState.repair_def(String(req))
			return tr("Сначала: %s") % tr(String(d.get("name", req)))
	return tr("Пройди смену %d") % int(r.get("after", 0))


func _pick(id: String) -> void:
	var def := GameState.repair_def(id)
	if not (def.get("variants", []) as Array).is_empty():
		_choosing = id
		_page = 0
		refresh()
		return
	_do(id, "")


## Варианты выбора (цвет): образец цвета вместо значка.
func _variant_cards() -> Array:
	var def := GameState.repair_def(_choosing)
	var key := String(def["effects"][0]["key"])
	var cards: Array = []
	for v in def["variants"]:
		var table: Dictionary = Data.styles.get(key, {})
		var sample: Dictionary = table.get(String(v["id"]), {})
		var col := Color(String(sample.get("wall", sample.get("a", sample.get("base", sample.get("ink", "cdb892"))))))
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in range(2, 14):
			for x in range(2, 14):
				img.set_pixel(x, y, col)
		cards.append({"title": String(v["name"]), "sub": String(def["name"]), "icon": ImageTexture.create_from_image(img),
			"action": {"text": tr("Выбрать"), "icon": "check", "press": _do.bind(_choosing, String(v["id"]))}})
	return cards


func _do(id: String, variant: String) -> void:
	_choosing = ""
	if GameState.do_repair(id, variant):
		Audio.sfx("star", 0.0)
		Fx.burst(_root, Vector2(180, 300), "star", Color("ffe08a"), 14, 260.0, 200.0, 1.0, 1.2)
		Fx.confetti(_root, Vector2(180, 260), 18)
	refresh()


## «Назад» из выбора варианта возвращает к списку, из списка — закрывает доску.
func close() -> void:
	if _choosing != "":
		_choosing = ""
		refresh()
		return
	super.close()


func _close() -> void:
	super.close()
