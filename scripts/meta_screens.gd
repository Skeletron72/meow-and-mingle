class_name MetaScreens
extends RefCounted
## Экраны мета-игры на общем списке ListScreen с карточками Card: магазин (вкладки), задания дня, события, Мурлык-пасс.
## Сами ничего не хранят — читают Shop, Daily, Economy, Events. Каждая функция rows возвращает массив карточек (см. Card.make).

const QUEST_ICONS := {"serve": "cup", "pastry": "pastry", "fast": "bolt", "level": "star", "stars": "star", "perfect": "heart", "coins": "coin", "tips": "coin"}


static func _t(text: String) -> String:
	return Loc.t(text)


static func _msg(s: Node, text: String) -> void:
	if is_instance_valid(s):
		Ui.toast(s, text, Vector2(180, 600))


## Значок награды: монеты, рыбки, бустер, мебель, открытие.
static func reward_icon(r: Dictionary) -> String:
	if r.has("furniture"):
		return "sofa"
	if r.has("boosters"):
		return Economy.booster_def(String((r["boosters"] as Dictionary).keys()[0])).get("icon", "bolt")
	if r.has("fish"):
		return "fish"
	if r.has("unlock"):
		return "star"
	return "coin"


static func balance() -> Array:
	return [{"icon": "fish", "text": str(Economy.fish())}, {"icon": "coin", "text": str(GameState.coins)}]


# ---------------------------------------------------------------- магазин

static func open_shop(parent: Node) -> ListScreen:
	Platform.track("shop_open", {"from": "menu"})
	var s := ListScreen.new()
	s.title = "Магазин"
	s.tabs = [{"icon": "gift", "name": "Сегодня"}, {"icon": "fish", "name": "Рыбки"}, {"icon": "bolt", "name": "Бустеры"}, {"icon": "bag", "name": "Ещё"}]
	s.header_provider = balance
	s.provider = func(tab: int) -> Array: return shop_rows(s, tab)
	parent.add_child(s)
	return s


static func shop_rows(s: Node, tab: int) -> Array:
	var rows: Array = []
	match tab:
		0:
			var deal := Shop.deal()
			var taken := Shop.deal_taken()
			rows.append({"title": String(deal["name"]), "sub": String(deal["desc"]) if not taken else _t("Взято. Новое — завтра."), "icon": reward_icon(deal), "tint": Color(1.1, 1.05, 0.8), "enabled": not taken,
				"action": {"text": str(int(deal["fish"])), "icon": "fish", "enabled": Economy.fish() >= int(deal["fish"]),
					"press": func() -> void: _msg(s, _t("Получено!") if Shop.buy_deal() else _t("Не хватает рыбок"))}})
			rows.append({"title": _t("Бесплатно"), "sub": _t("Предложение дня за рекламу") if not taken else _t("Взято. Новое — завтра."), "icon": "video", "enabled": not taken,
				"action": {"text": "", "icon": "video", "enabled": Shop.ad_ready("deal_free"),
					"press": func() -> void: Shop.claim_deal_free(func(ok: bool) -> void: _msg(s, _t("Получено!") if ok else _t("Реклама недоступна")))}})
			if Shop.starter_available():
				var st: Dictionary = Data.shop["starter"]
				var hours := int(ceil(float(Shop.starter_seconds_left()) / 3600.0))
				rows.append({"title": _t("Стартовый набор"), "sub": _t("%d рыбок и 3 бустера · %d ч") % [int(st["fish"]), hours], "icon": "gift", "tint": Color(1.1, 1.05, 0.8),
					"action": {"text": Shop.price_text("starter_pack"), "icon": "", "press": func() -> void: _buy(s, "starter_pack")}})
			var gift_ready := Daily.gift_ready()
			rows.append({"title": _t("Подарок дня"), "sub": _t("Заходи каждый день") if gift_ready else _t("Уже получен. Новый — завтра."), "icon": "calendar", "enabled": gift_ready,
				"action": {"text": "", "icon": "gift", "enabled": gift_ready, "press": func() -> void: _msg(s, Daily.claim_gift() if gift_ready else "")}})
		1:
			for pack in Data.shop["fish_packs"]:
				var sku := String(pack["sku"])
				rows.append({"title": _t("Рыбки: %d") % Shop.pack_fish(sku), "sub": _t("Первая покупка — вдвое больше!") if not bool(GameState.meta["first_purchase_done"]) else _t("Запас рыбок"), "icon": "fish",
					"action": {"text": Shop.price_text(sku), "icon": "", "press": func() -> void: _buy(s, sku)}})
		2:
			for b in Data.boosters:
				var id := String(b["id"])
				var coins_ok := GameState.coins >= int(b["coins"])
				var pay_fish := not coins_ok and Economy.fish() >= int(b["fish"])
				rows.append({"title": _t(String(b["name"])), "sub": _t(String(b["desc"])), "icon": String(b["icon"]), "badge": "×%d" % Economy.booster_count(id),
					"action": {"text": str(int(b["fish"]) if pay_fish else int(b["coins"])), "icon": "fish" if pay_fish else "coin", "enabled": coins_ok or pay_fish,
						"press": func() -> void:
							if Economy.buy_booster(id, "coins") or Economy.buy_booster(id, "fish"):
								_msg(s, _t("Куплено!"))
							else:
								_msg(s, _t("Не хватает монет"))}})
		_:
			if not Shop.ads_removed():
				rows.append({"title": _t("Без рекламы"), "sub": _t("Без рекламы между сменами"), "icon": "shield", "action": {"text": Shop.price_text("no_ads"), "icon": "", "press": func() -> void: _buy(s, "no_ads")}})
			if not Shop.has_pass():
				rows.append({"title": _t("Мурлык-пасс"), "sub": _t("Премиум-призы на ступенях"), "icon": "crown", "action": {"text": Shop.price_text("season_pass"), "icon": "", "press": func() -> void: _buy(s, "season_pass")}})
			rows.append({"title": _t("Вернуть покупки"), "sub": _t("Если сменил телефон"), "icon": "arrow_r",
				"action": {"text": _t("Вернуть"), "icon": "", "press": func() -> void: Shop.restore(func(n: int) -> void: _msg(s, _t("Восстановлено: %d") % n))}})
	return rows


static func _buy(s: Node, sku: String) -> void:
	Shop.buy(sku, func(ok: bool, _sku: String) -> void:
		_msg(s, _t("Спасибо за покупку!") if ok else _t("Покупка не прошла")))


# ---------------------------------------------------------------- задания дня

static func open_quests(parent: Node) -> ListScreen:
	var s := ListScreen.new()
	s.title = "Задания дня"
	s.header_provider = balance
	s.provider = func(_tab: int) -> Array: return quest_rows(s)
	parent.add_child(s)
	return s


static func quest_rows(s: Node) -> Array:
	var rows: Array = []
	if not Daily.quests_unlocked():
		rows.append({"title": _t("Задания откроются после 3-й смены"), "icon": "lock", "enabled": false})
		return rows
	for q in Daily.quests():
		var i := int(q["i"])
		var t := Daily.quest_template(String(q["id"]))
		var claimable := bool(q["done"]) and not bool(q["claimed"])
		var row := {"title": _t(String(q["name"])), "icon": QUEST_ICONS.get(String(t["kind"]), "star"), "enabled": not bool(q["claimed"])}
		if bool(q["claimed"]):
			row["sub"] = _t("Получено")
		elif claimable:
			row["sub"] = Economy.describe(q["reward"])
			row["action"] = {"text": "", "icon": "gift", "press": func() -> void:
				var txt := Daily.claim_quest(i)
				if txt != "":
					Audio.sfx("coin", 0.0)
					_msg(s, txt)}
		else:
			row["progress"] = [int(q["progress"]), int(q["target"])]
			row["action"] = {"text": Economy.describe(q["reward"]).split(" ")[0], "icon": reward_icon(q["reward"]), "enabled": false}
		rows.append(row)
	rows.append({"title": _t("Ящик дня"), "sub": _t("Все три: рыбки и бустер"), "icon": "gift", "enabled": Daily.box_ready() or not bool(GameState.meta["quests"]["box"]),
		"action": {"text": "", "icon": "gift", "enabled": Daily.box_ready(), "press": func() -> void:
			var txt := Daily.claim_box()
			if txt != "":
				Audio.sfx("star", 0.0)
				_msg(s, txt)}})
	return rows


# ---------------------------------------------------------------- события

static func open_events(parent: Node) -> ListScreen:
	var s := ListScreen.new()
	s.title = "События"
	s.header_provider = func() -> Array: return [{"icon": "clock", "text": _t("дней: %d") % Events.days_left()}] if not Events.active().is_empty() else []
	s.provider = func(_tab: int) -> Array: return event_rows(s)
	parent.add_child(s)
	return s


static func event_rows(s: Node) -> Array:
	var rows: Array = []
	var ev := Events.active()
	if ev.is_empty():
		var nxt := Events.next_event()
		rows.append({"title": _t("Сейчас нет событий"), "sub": (_t("Скоро: %s") % _t(String(nxt["name"]))) if not nxt.is_empty() else "", "icon": "calendar", "enabled": false})
		return rows
	rows.append({"title": _t(String(ev["name"])), "sub": _t(String(ev["blurb"])), "icon": "calendar", "tint": Color(1.1, 1.05, 0.8)})
	var tiers := Events.tiers()
	for i in tiers.size():
		var tier: Dictionary = tiers[i]
		var open := Events.tier_open(i)
		for premium in [false, true]:
			var ok: bool = open and not Events.tier_claimed(i, premium) and (not premium or Shop.has_pass())
			var line: String = "premium" if premium else "free"
			var claimed := Events.tier_claimed(i, premium)
			rows.append({"title": "%d %s" % [int(tier["need"]), Loc.plural(int(tier["need"]), ["задание", "задания", "заданий"])] + (" · " + _t("пасс") if premium else ""), "sub": Economy.describe(tier[line]), "icon": reward_icon(tier[line]),
				"enabled": not claimed,
				"action": {"text": "" if not claimed else _t("Взято"), "icon": "gift" if not claimed else "", "enabled": ok,
					"press": func() -> void:
						var txt := Events.claim(i, premium)
						if txt != "":
							Audio.sfx("star", 0.0)
							_msg(s, txt)}})
	for t in Events.tasks():
		rows.append({"title": _t(String(t["name"])), "icon": "check" if bool(t["done"]) else "star_off", "progress": [int(t["progress"]), int(t["target"])], "enabled": not bool(t["done"])})
	return rows


# ---------------------------------------------------------------- Мурлык-пасс

static func open_season(parent: Node) -> ListScreen:
	var s := ListScreen.new()
	s.title = "Мурлык-пасс"
	s.header_provider = func() -> Array: return [{"icon": "star", "text": "%d/30" % Shop.season_tier()}]
	s.provider = func(_tab: int) -> Array: return season_rows(s)
	var target := 0
	for t in range(1, Shop.SEASON_TIERS + 1):
		if t > Shop.season_tier() or not Shop.season_claimed(t, false) or (Shop.has_pass() and not Shop.season_claimed(t, true)):
			target = t
			break
	s.start_page = clampi((target + 1) / ListScreen.PER_PAGE, 0, 7)
	parent.add_child(s)
	return s


static func season_rows(s: Node) -> Array:
	var rows: Array = []
	var left := Shop.season_days_left()
	rows.append({"title": _t("Мурлык-пасс"), "sub": _t("Дней: %d · очки: %d") % [left, Shop.season_xp()] if Shop.season_active() else _t("Сезон закончился. Скоро новый!"), "icon": "crown", "tint": Color(1.1, 1.05, 0.8),
		"action": {} if Shop.has_pass() else {"text": Shop.price_text("season_pass"), "icon": "", "press": func() -> void: _buy(s, "season_pass")}})
	for t in Shop.season_tiers():
		var n := int(t["tier"])
		var open := n <= Shop.season_tier()
		var free_ok := open and not Shop.season_claimed(n, false)
		var prem_ok := open and Shop.has_pass() and not Shop.season_claimed(n, true)
		var all_taken := open and Shop.season_claimed(n, false) and (not Shop.has_pass() or Shop.season_claimed(n, true))
		rows.append({"title": "%d: %s" % [n, Economy.describe(t["free"])], "sub": "%s %s" % [_t("Пасс:"), Economy.describe(t["premium"])], "icon": reward_icon(t["free"]) if open else "lock",
			"enabled": not all_taken,
			"action": {"text": "" if not all_taken else _t("Взято"), "icon": "gift" if not all_taken else "", "enabled": free_ok or prem_ok,
				"press": func() -> void:
					var got := []
					for premium in [false, true]:
						var txt := Shop.season_claim(n, premium)
						if txt != "":
							got.append(txt)
					if not got.is_empty():
						Audio.sfx("star", 0.0)
						_msg(s, "; ".join(got))}})
	return rows
