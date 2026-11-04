extends Node
## Autoload "Shop": магазин и деньги. Каталог (data/shop.json), покупки за реальные деньги через Platform (выдача награды — только после успешной
## покупки), восстановление покупок, «Предложение дня», стартовый набор, реклама с наградой и её дневные лимиты, правило принудительной рекламы,
## «Мурлык-пасс» (сезон, data/season_1.json).
## Правила из плана: никаких лутбоксов (состав виден заранее), «Без рекламы» не отключает рекламу за награду, первая покупка рыбок — вдвое больше.

signal purchased(sku: String)
signal season_changed

const SEASON_TIERS := 30
const SEASON_GRACE_DAYS := 3   # после конца сезона награды можно забрать ещё 3 дня, потом начинается следующий (если есть файл)


func _ready() -> void:
	Data.load_season(int((GameState.meta["season"] as Dictionary)["no"]))


## Конец сезона + льготные дни → следующий сезон (data/season_<n+1>.json), очки и награды обнуляются, пропуск нужно покупать заново.
func check_rollover() -> bool:
	var s: Dictionary = GameState.meta["season"]
	if int(s["start_day"]) < 0 or Daily.today() < int(s["start_day"]) + int(Data.season["days"]) + SEASON_GRACE_DAYS:
		return false
	var next_no := int(s["no"]) + 1
	if not Data.load_season(next_no):
		return false
	GameState.meta["season"] = {"no": next_no, "id": String(Data.season["id"]), "start_day": -1, "xp": 0, "free": [], "premium": [], "pass": false}
	Platform.track("season_start", {"no": next_no})
	season_changed.emit()
	return true


# ---------------------------------------------------------------- покупки

func owns(sku: String) -> bool:
	return sku in (GameState.meta["purchases"] as Array)


func ads_removed() -> bool:
	return owns("no_ads")


## Цена в виде текста: по данным магазина площадки (в её валюте), иначе рубли из каталога.
func price_text(sku: String) -> String:
	for p in Platform.products():
		if String(p["sku"]) == sku:
			return String(p["price"])
	for pack in Data.shop["fish_packs"]:
		if String(pack["sku"]) == sku:
			return "%d ₽" % int(pack["rub"])
	for key in ["starter", "no_ads", "season_pass"]:
		if String(Data.shop[key]["sku"]) == sku:
			return "%d ₽" % int(Data.shop[key]["rub"])
	return ""


func fish_pack(sku: String) -> Dictionary:
	for pack in Data.shop["fish_packs"]:
		if String(pack["sku"]) == sku:
			return pack
	return {}


## Сколько рыбок получит игрок за пакет прямо сейчас (в первой покупке — ×2).
func pack_fish(sku: String) -> int:
	var n := int(fish_pack(sku).get("fish", 0))
	return n * (1 if bool(GameState.meta["first_purchase_done"]) else int(Data.shop["first_purchase_multiplier"]))


## Купить за реальные деньги. cb(ok: bool, sku: String). Награда выдаётся только при ok.
func buy(sku: String, cb: Callable) -> void:
	if (sku in ["no_ads", "season_pass", "starter_pack"]) and owns(sku):
		cb.call(false, sku)
		return
	Platform.purchase(sku, func(ok: bool, bought: String) -> void:
		if ok:
			_grant(bought, false)
		cb.call(ok, bought))


func _grant(sku: String, restoring: bool) -> void:
	var purchases: Array = GameState.meta["purchases"]
	if sku == "no_ads":
		if not owns(sku):
			purchases.append(sku)
	elif sku == "season_pass":
		if not owns(sku):
			purchases.append(sku)
		(GameState.meta["season"] as Dictionary)["pass"] = true
	elif sku == "starter_pack":
		if not owns(sku):
			purchases.append(sku)
			if not restoring:
				var st: Dictionary = Data.shop["starter"]
				Economy.grant({"fish": int(st["fish"]), "boosters": st["boosters"]}, "starter_pack")
	elif not fish_pack(sku).is_empty() and not restoring:
		Economy.add_fish(pack_fish(sku), "iap:" + sku)
		GameState.meta["first_purchase_done"] = true
	GameState.save_game()
	purchased.emit(sku)
	season_changed.emit()


## «Восстановить покупки»: разовые покупки (без рекламы, пропуск) возвращаются; рыбки не восстанавливаются (расходуемые).
func restore(cb: Callable) -> void:
	Platform.restore_purchases(func(skus: Array) -> void:
		var n := 0
		for s in skus:
			if String(s) in ["no_ads", "season_pass"] and not owns(String(s)):
				_grant(String(s), true)
				n += 1
		cb.call(n))


# ---------------------------------------------------------------- стартовый набор

## Стартовый набор: после 3-й смены, на 72 часа с первого показа, пока не куплен.
func starter_available() -> bool:
	if owns("starter_pack") or GameState.shifts_played < int(Data.shop["starter"]["min_shifts"]):
		return false
	var s: Dictionary = GameState.meta["shop"]
	if int(s["starter_start"]) == 0:
		return true
	return Daily.now_unix() < int(s["starter_start"]) + int(Data.shop["starter"]["hours"]) * 3600


## Оставшееся время предложения (секунды); до первого показа — полное окно.
func starter_seconds_left() -> int:
	var s: Dictionary = GameState.meta["shop"]
	var total := int(Data.shop["starter"]["hours"]) * 3600
	if int(s["starter_start"]) == 0:
		return total
	return maxi(0, int(s["starter_start"]) + total - Daily.now_unix())


## Предложение, которое можно показать самим окном (не чаще раза в день): сейчас только стартовый набор.
func offer_to_show() -> String:
	if not starter_available():
		return ""
	var s: Dictionary = GameState.meta["shop"]
	if int(s["starter_shown_day"]) == Daily.today():
		return ""
	return "starter_pack"


func mark_offer_shown(sku: String) -> void:
	var s: Dictionary = GameState.meta["shop"]
	s["starter_shown_day"] = Daily.today()
	if sku == "starter_pack" and int(s["starter_start"]) == 0:
		s["starter_start"] = Daily.now_unix()
	Platform.track("offer_show", {"id": sku})
	GameState.save_game()


# ---------------------------------------------------------------- предложение дня

func deal() -> Dictionary:
	return Data.deals[Daily.today() % Data.deals.size()]


func deal_taken() -> bool:
	var s: Dictionary = GameState.meta["shop"]
	return int(s["deal_day"]) == Daily.today() and bool(s["deal_taken"])


func _take_deal(source: String) -> void:
	var d := deal()
	var reward := {}
	for k in ["coins", "boosters"]:
		if d.has(k):
			reward[k] = d[k]
	var s: Dictionary = GameState.meta["shop"]
	s["deal_day"] = Daily.today()
	s["deal_taken"] = true
	Economy.grant(reward, source)


## Купить предложение дня за рыбки. false — уже взято или не хватает.
func buy_deal() -> bool:
	if deal_taken() or not Economy.spend_fish(int(deal()["fish"]), "deal:" + String(deal()["id"])):
		return false
	_take_deal("deal")
	return true


## Бесплатно за просмотр рекламы (раз в день).
func claim_deal_free(cb: Callable) -> void:
	if deal_taken():
		cb.call(false)
		return
	show_ad("deal_free", func(ok: bool) -> void:
		if ok:
			_take_deal("deal_ad")
		cb.call(ok))


# ---------------------------------------------------------------- реклама

func _ad_state(placement: String) -> Dictionary:
	var ads: Dictionary = (GameState.meta["shop"] as Dictionary)["ads"]
	var st: Dictionary = ads.get(placement, {})
	if int(st.get("day", -1)) != Daily.today():
		st = {"day": Daily.today(), "n": 0}
		ads[placement] = st
	return st


## Сколько просмотров осталось сегодня; cap 0 в данных — без лимита (999).
func ad_left(placement: String) -> int:
	var cap := int((Data.shop["ads"] as Dictionary).get(placement, {}).get("cap", 0))
	if cap <= 0:
		return 999
	return maxi(0, cap - int(_ad_state(placement)["n"]))


func ad_ready(placement: String) -> bool:
	return ad_left(placement) > 0 and Platform.ads_ready(placement)


## Реклама за награду с дневным лимитом. cb(rewarded: bool). Лимит расходуется только за засчитанный просмотр.
func show_ad(placement: String, cb: Callable) -> void:
	if ad_left(placement) <= 0:
		cb.call(false)
		return
	Platform.show_rewarded(placement, func(ok: bool) -> void:
		if ok:
			var st := _ad_state(placement)
			st["n"] = int(st["n"]) + 1
			GameState.save_game()
		cb.call(ok))


## Звезда за рекламу (нехватка звёзд до задачи): 2 просмотра = 1 звезда, не чаще 3 звёзд в день.
## cb(ok, got_star).
func watch_for_star(cb: Callable) -> void:
	show_ad("star", func(ok: bool) -> void:
		if not ok:
			cb.call(false, false)
			return
		var s: Dictionary = GameState.meta["shop"]
		s["star_views"] = int(s["star_views"]) + 1
		var got := false
		if int(s["star_views"]) >= int(Data.shop["ads"]["star"]["per"]):
			s["star_views"] = 0
			GameState.stars_bonus += 1
			got = true
			Platform.track("currency_earn", {"type": "star", "amount": 1, "source": "ad"})
		GameState.save_game()
		cb.call(true, got))


## Принудительная реклама между сменами: не раньше 10-й смены и 2-го дня, не чаще раза в 4 минуты, не при «Без рекламы».
func maybe_interstitial(cb: Callable) -> void:
	var rule: Dictionary = Data.shop["interstitial"]
	var first_day := Daily.day_of(GameState.first_run_unix)
	if ads_removed() or GameState.shifts_played < int(rule["min_shifts"]) or Daily.today() - first_day < int(rule["min_day"]) - 1:
		cb.call()
		return
	var s: Dictionary = GameState.meta["shop"]
	if Daily.now_unix() - int(s["last_interstitial"]) < int(rule["gap_s"]):
		cb.call()
		return
	s["last_interstitial"] = Daily.now_unix()
	Platform.show_interstitial("between_shifts", cb)


# ---------------------------------------------------------------- Мурлык-пасс (сезон)

func season_tiers() -> Array:
	return Data.season.get("tiers", [])


func season_started() -> bool:
	return int((GameState.meta["season"] as Dictionary)["start_day"]) >= 0


## Сезон идёт: стартует с первых очков, длится `days` дней.
func season_active() -> bool:
	var s: Dictionary = GameState.meta["season"]
	if int(s["start_day"]) < 0:
		return true
	return Daily.today() < int(s["start_day"]) + int(Data.season["days"])


func season_days_left() -> int:
	var s: Dictionary = GameState.meta["season"]
	if int(s["start_day"]) < 0:
		return int(Data.season["days"])
	return maxi(0, int(s["start_day"]) + int(Data.season["days"]) - Daily.today())


func season_xp() -> int:
	return int((GameState.meta["season"] as Dictionary)["xp"])


## Открытых ступеней (0..30).
func season_tier() -> int:
	return mini(SEASON_TIERS, season_xp() / int(Data.season["xp_per_tier"]))


func has_pass() -> bool:
	return bool((GameState.meta["season"] as Dictionary)["pass"])


func add_season_xp(n: int, source: String) -> void:
	if n <= 0 or not season_active():
		return
	var s: Dictionary = GameState.meta["season"]
	if String(s["id"]) != String(Data.season["id"]):
		s["id"] = String(Data.season["id"])
	if int(s["start_day"]) < 0:
		s["start_day"] = Daily.today()
	var before := season_tier()
	s["xp"] = season_xp() + n
	if season_tier() > before:
		Platform.track("season_tier", {"tier": season_tier(), "source": source})
	season_changed.emit()


func season_claimed(tier: int, premium: bool) -> bool:
	return tier in ((GameState.meta["season"] as Dictionary)["premium" if premium else "free"] as Array)


## Забрать награду ступени. Премиум-линия — только с купленным пропуском. Возвращает текст награды или "".
func season_claim(tier: int, premium: bool) -> String:
	if tier < 1 or tier > season_tier() or season_claimed(tier, premium) or (premium and not has_pass()):
		return ""
	var line: Array = (GameState.meta["season"] as Dictionary)["premium" if premium else "free"]
	line.append(tier)
	var reward: Dictionary = season_tiers()[tier - 1]["premium" if premium else "free"]
	Platform.track("season_claim", {"tier": tier, "premium": premium})
	season_changed.emit()
	return Economy.grant(reward, "season")


## Сколько наград сейчас можно забрать (для значка).
func season_claimable() -> int:
	var n := 0
	for t in range(1, season_tier() + 1):
		if not season_claimed(t, false):
			n += 1
		if has_pass() and not season_claimed(t, true):
			n += 1
	return n
