extends Node
## Autoload "Economy": рыбки (премиум-валюта), бустеры и единый путь движения валют с событиями аналитики.
## Монеты и звёзды живут в GameState (их много и часто), здесь — «деньги» мета-игры. Все данные — в GameState.meta и сохраняются там же.
## Правило из плана: звёзды не продаются, ожиданий и «энергии» нет; рыбки ускоряют и украшают, но не закрывают контент.

signal fish_changed(value: int)
signal boosters_changed

const BOOSTER_IDS := ["patience", "double_tips", "auto", "cat_help"]


# ---------------------------------------------------------------- рыбки

func fish() -> int:
	return int(GameState.meta["fish"])


func add_fish(n: int, source: String) -> void:
	if n <= 0:
		return
	GameState.meta["fish"] = fish() + n
	Platform.track("currency_earn", {"type": "fish", "amount": n, "source": source})
	fish_changed.emit(fish())
	GameState.save_game()


## Списывает рыбки. false — не хватает, ничего не изменено.
func spend_fish(n: int, sink: String) -> bool:
	if n <= 0 or n > fish():
		return false
	GameState.meta["fish"] = fish() - n
	Platform.track("currency_spend", {"type": "fish", "amount": n, "sink": sink})
	fish_changed.emit(fish())
	GameState.save_game()
	return true


# ---------------------------------------------------------------- монеты (с источником для аналитики)

## Награда монетами не за заказ (подарки, задания, магазин): пишется событие. Заказы идут через GameState.add_coins без событий — их итог в level_end.
func earn_coins(n: int, source: String) -> void:
	if n <= 0:
		return
	GameState.add_coins(n)
	Platform.track("currency_earn", {"type": "coins", "amount": n, "source": source})


func spend_coins(n: int, sink: String) -> bool:
	if not GameState.spend_coins(n):
		return false
	Platform.track("currency_spend", {"type": "coins", "amount": n, "sink": sink})
	return true


# ---------------------------------------------------------------- бустеры

func booster_def(id: String) -> Dictionary:
	for b in Data.boosters:
		if String(b["id"]) == id:
			return b
	return {}


func booster_count(id: String) -> int:
	return int((GameState.meta["boosters"] as Dictionary).get(id, 0))


func boosters_total() -> int:
	var n := 0
	for id in BOOSTER_IDS:
		n += booster_count(id)
	return n


func add_booster(id: String, n: int, source: String) -> void:
	if n <= 0 or booster_def(id).is_empty():
		return
	(GameState.meta["boosters"] as Dictionary)[id] = booster_count(id) + n
	Platform.track("currency_earn", {"type": "booster:" + id, "amount": n, "source": source})
	boosters_changed.emit()
	GameState.save_game()


## Берёт один бустер из запаса (перед сменой). false — нет.
func use_booster(id: String) -> bool:
	if booster_count(id) <= 0:
		return false
	(GameState.meta["boosters"] as Dictionary)[id] = booster_count(id) - 1
	Platform.track("booster_use", {"id": id})
	boosters_changed.emit()
	GameState.save_game()
	return true


## Покупка бустера за монеты или рыбки. currency: "coins" | "fish".
func buy_booster(id: String, currency: String) -> bool:
	var def := booster_def(id)
	if def.is_empty():
		return false
	var ok := false
	if currency == "fish":
		ok = spend_fish(int(def["fish"]), "booster:" + id)
	else:
		ok = spend_coins(int(def["coins"]), "booster:" + id)
	if ok:
		add_booster(id, 1, "shop")
	return ok


# ---------------------------------------------------------------- выдача наград

## Выдаёт награду из данных (daily/season/deals): {"coins", "fish", "boosters": {id: n}, "furniture": id}.
## source — для аналитики. Возвращает текстовое описание для тоста.
func grant(reward: Dictionary, source: String) -> String:
	var parts: Array[String] = []
	if reward.has("coins"):
		earn_coins(int(reward["coins"]), source)
		parts.append("+%d" % int(reward["coins"]))
	if reward.has("fish"):
		add_fish(int(reward["fish"]), source)
		parts.append("%d %s" % [int(reward["fish"]), Loc.plural(int(reward["fish"]), ["рыбка", "рыбки", "рыбок"])])
	for id in reward.get("boosters", {}):
		add_booster(String(id), int(reward["boosters"][id]), source)
		parts.append("%s ×%d" % [tr(String(booster_def(String(id)).get("name", id))), int(reward["boosters"][id])])
	if reward.has("furniture"):
		GameState.place_free(String(reward["furniture"]))
		GameState.save_game()
		parts.append(tr(String(Data.furniture.get(String(reward["furniture"]), {}).get("name", "?"))))
	for key in reward.get("unlock", []):
		if not (String(key) in GameState.unlocks):
			GameState.unlocks.append(String(key))
		GameState.save_game()
		parts.append(_unlock_text(String(key)))
	return ", ".join(parts)


func _unlock_text(key: String) -> String:
	if key.begins_with("style:"):
		return tr("Стиль «%s»") % tr(String(Data.styles["decor"].get(key.substr(6), {}).get("name", key)))
	return key


## Короткое описание награды без выдачи (для карточек): «50 монет, Автосборка ×1».
func describe(reward: Dictionary) -> String:
	var parts: Array[String] = []
	if reward.has("coins"):
		parts.append("%d %s" % [int(reward["coins"]), Loc.plural(int(reward["coins"]), ["монета", "монеты", "монет"])])
	if reward.has("fish"):
		parts.append("%d %s" % [int(reward["fish"]), Loc.plural(int(reward["fish"]), ["рыбка", "рыбки", "рыбок"])])
	for id in reward.get("boosters", {}):
		parts.append("%s ×%d" % [tr(String(booster_def(String(id)).get("name", id))), int(reward["boosters"][id])])
	if reward.has("furniture"):
		parts.append(tr(String(Data.furniture.get(String(reward["furniture"]), {}).get("name", "?"))))
	for key in reward.get("unlock", []):
		parts.append(_unlock_text(String(key)))
	return ", ".join(parts)
