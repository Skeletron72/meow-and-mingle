class_name MetaScreens
extends RefCounted
## Экраны мета-игры на общем списке ListScreen: магазин, задания дня, Мурлык-пасс. Сами ничего не хранят — читают Shop, Daily, Economy.

# ---------------------------------------------------------------- магазин

static func open_shop(parent: Node) -> ListScreen:
	Platform.track("shop_open", {"from": "menu"})
	var s := ListScreen.new()
	s.title = "Магазин"
	s.header_provider = func() -> String: return "%d %s" % [Economy.fish(), Loc.plural(Economy.fish(), ["рыбка", "рыбки", "рыбок"])]
	s.provider = func() -> Array: return shop_rows(s)
	parent.add_child(s)
	return s


static func _t(text: String) -> String:
	return Loc.t(text)


static func _msg(s: Node, text: String) -> void:
	if is_instance_valid(s):
		Ui.toast(s, text, Vector2(180, 590))


static func shop_rows(s: Node) -> Array:
	var rows: Array = []
	# предложение дня
	var deal := Shop.deal()
	var taken := Shop.deal_taken()
	rows.append({"title": _t(String(deal["name"])), "sub": _t(String(deal["desc"])) if not taken else _t("Взято. Новое — завтра."), "tint": Color(1.1, 1.05, 0.8),
		"right": "%d %s" % [int(deal["fish"]), _t("рыб.")], "enabled": not taken and Economy.fish() >= int(deal["fish"]),
		"press": func() -> void:
			if Shop.buy_deal():
				_msg(s, _t("Получено!"))
			else:
				_msg(s, _t("Не хватает рыбок"))})
	rows.append({"title": _t("Бесплатно за рекламу"), "sub": _t("Предложение дня, раз в сутки") if not taken else _t("Взято. Новое — завтра."), "right": _t("Смотреть"),
		"enabled": not taken and Shop.ad_ready("deal_free"),
		"press": func() -> void: Shop.claim_deal_free(func(ok: bool) -> void: _msg(s, _t("Получено!") if ok else _t("Реклама недоступна")))})
	# стартовый набор
	if Shop.starter_available():
		var st: Dictionary = Data.shop["starter"]
		var hours := int(ceil(float(Shop.starter_seconds_left()) / 3600.0))
		rows.append({"title": _t("Стартовый набор"), "sub": _t("%d рыбок, 3 бустера · %d ч") % [int(st["fish"]), hours], "right": Shop.price_text("starter_pack"), "tint": Color(1.1, 1.05, 0.8),
			"press": func() -> void: _buy(s, "starter_pack")})
	# рыбки
	for pack in Data.shop["fish_packs"]:
		var sku := String(pack["sku"])
		var n := Shop.pack_fish(sku)
		rows.append({"title": _t("Рыбки: %d") % n, "sub": _t("Первая покупка ×2!") if not bool(GameState.meta["first_purchase_done"]) else _t("Запас рыбок"), "right": Shop.price_text(sku),
			"press": func() -> void: _buy(s, sku)})
	# бустеры
	for b in Data.boosters:
		var id := String(b["id"])
		rows.append({"title": _t(String(b["name"])), "sub": "%s · ×%d" % [_t(String(b["desc"])), Economy.booster_count(id)], "right": "%d %s" % [int(b["coins"]), _t("мон.")],
			"enabled": GameState.coins >= int(b["coins"]) or Economy.fish() >= int(b["fish"]),
			"press": func() -> void:
				if Economy.buy_booster(id, "coins") or Economy.buy_booster(id, "fish"):
					_msg(s, _t("Куплено!"))
				else:
					_msg(s, _t("Не хватает монет"))})
	if not Shop.ads_removed():
		rows.append({"title": _t("Без рекламы"), "sub": _t("Навсегда; награды за рекламу есть"), "right": Shop.price_text("no_ads"), "press": func() -> void: _buy(s, "no_ads")})
	if not Shop.has_pass():
		rows.append({"title": _t("Мурлык-пасс"), "sub": _t("Премиум-призы на каждой ступени"), "right": Shop.price_text("season_pass"), "press": func() -> void: _buy(s, "season_pass")})
	rows.append({"title": _t("Восстановить покупки"), "sub": _t("Вернуть покупки на новом телефоне"), "right": "",
		"press": func() -> void: Shop.restore(func(n: int) -> void: _msg(s, _t("Восстановлено: %d") % n))})
	return rows


static func _buy(s: Node, sku: String) -> void:
	Shop.buy(sku, func(ok: bool, _sku: String) -> void:
		_msg(s, _t("Спасибо за покупку!") if ok else _t("Покупка не прошла")))


# ---------------------------------------------------------------- задания дня

static func open_quests(parent: Node) -> ListScreen:
	var s := ListScreen.new()
	s.title = "Задания дня"
	s.provider = func() -> Array: return quest_rows(s)
	parent.add_child(s)
	return s


static func quest_rows(s: Node) -> Array:
	var rows: Array = []
	if not Daily.quests_unlocked():
		rows.append({"title": _t("Задания откроются после 3-й смены"), "sub": "", "right": "", "enabled": false})
		return rows
	for q in Daily.quests():
		var i := int(q["i"])
		var state := _t("Забрать") if bool(q["done"]) and not bool(q["claimed"]) else (_t("Готово") if bool(q["claimed"]) else "")
		rows.append({"title": _t(String(q["name"])), "sub": "%d/%d · %s" % [int(q["progress"]), int(q["target"]), Economy.describe(q["reward"])], "right": state,
			"enabled": bool(q["done"]) and not bool(q["claimed"]),
			"press": func() -> void:
				var t := Daily.claim_quest(i)
				if t != "":
					Audio.sfx("coin", 0.0)
					_msg(s, t)})
	rows.append({"title": _t("Ящик дня"), "sub": _t("Все три: 3 рыбки и бустер"), "right": _t("Забрать") if Daily.box_ready() else "", "enabled": Daily.box_ready(),
		"press": func() -> void:
			var t := Daily.claim_box()
			if t != "":
				Audio.sfx("star", 0.0)
				_msg(s, t)})
	return rows


# ---------------------------------------------------------------- Мурлык-пасс

static func open_season(parent: Node) -> ListScreen:
	var s := ListScreen.new()
	s.title = "Мурлык-пасс"
	s.header_provider = func() -> String: return _t("ступень %d/30") % Shop.season_tier()
	s.provider = func() -> Array: return season_rows(s)
	# открыть на странице с ближайшей наградой
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
	rows.append({"title": _t("Мурлык-пасс"), "sub": _t("Дней: %d · очки: %d") % [left, Shop.season_xp()] if Shop.season_active() else _t("Сезон закончился. Скоро новый!"),
		"right": _t("Куплен") if Shop.has_pass() else Shop.price_text("season_pass"), "enabled": not Shop.has_pass(),
		"press": func() -> void: _buy(s, "season_pass")})
	for t in Shop.season_tiers():
		var n := int(t["tier"])
		var open := n <= Shop.season_tier()
		var free_ok := open and not Shop.season_claimed(n, false)
		var prem_ok := open and Shop.has_pass() and not Shop.season_claimed(n, true)
		var prem_text := Economy.describe(t["premium"])
		var state := _t("Забрать") if (free_ok or prem_ok) else (_t("Взято") if open and (Shop.season_claimed(n, false) and (not Shop.has_pass() or Shop.season_claimed(n, true))) else "")
		rows.append({"title": "%d. %s" % [n, Economy.describe(t["free"])], "sub": "%s %s" % [_t("Пасс:"), prem_text], "right": state,
			"enabled": free_ok or prem_ok,
			"press": func() -> void:
				var got := []
				for premium in [false, true]:
					var txt := Shop.season_claim(n, premium)
					if txt != "":
						got.append(txt)
				if not got.is_empty():
					Audio.sfx("star", 0.0)
					_msg(s, "; ".join(got))})
	return rows
