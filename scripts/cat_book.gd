class_name CatBook
extends ListScreen
## «Книга котов»: все коты кафе на общем экране-списке. Открытые — с мордочкой, любимым напитком и сердечками (симпатия растёт с каждым заказом;
## на 5-м, 15-м и 30-м заказе открывается запись — реплика кота — и дают монеты). Закрытые — тёмный силуэт и подсказка, как их позвать.
## Тап по открытому коту показывает последнюю открытую реплику.

const FRAME := Rect2(0, 16, 16, 16)


func _init() -> void:
	super._init()
	title = "Коты"
	provider = _provide
	header_provider = func() -> Array:
		var known := 0
		for c in Data.cats:
			if is_known(c):
				known += 1
		return [{"icon": "paw", "text": "%d/%d" % [known, Data.cats.size()]}]


func is_known(def: Dictionary) -> bool:
	return bool(def.get("starter", false)) or GameState.has_unlock("cat:%s" % String(def["id"]))


## Как позвать закрытого кота: задача ремонта, которая его открывает.
func hint_for(cat_id: String) -> String:
	for r in Data.repairs:
		for e in r.get("effects", []):
			if String(e["kind"]) == "unlock" and String(e["key"]) == "cat:%s" % cat_id:
				return tr("Ремонт: %s") % tr(String(r["name"]))
	return ""


func _provide(_tab: int) -> Array:
	var cards: Array = []
	for def in Data.cats:
		var known := is_known(def)
		var tex := Ui.atlas(load("res://assets/cats/%s" % String(def["sprite"])) as Texture2D, FRAME)
		var card := {"title": String(def["name"]) if known else "???", "icon": tex, "icon_tint": Color(String(def.get("tint", "#ffffff"))) if known else Color(0.12, 0.09, 0.14), "enabled": known}
		if known:
			card["sub"] = tr(String(Data.drinks[String(def["fav_drink"])]["name"])).to_lower()
			card["hearts"] = GameState.cat_entries(String(def["id"]))
			card["press"] = _say.bind(String(def["id"]))
		else:
			card["sub"] = hint_for(String(def["id"]))
		cards.append(card)
	return cards


## Последняя открытая реплика кота (тап по карточке).
func _say(cat_id: String) -> void:
	for c in Data.cats:
		if String(c["id"]) != cat_id or not is_known(c):
			continue
		var n := GameState.cat_entries(cat_id)
		var text := tr("Ещё %d заказов — и расскажу.") % (int(GameState.LIKE_STEPS[0]) - GameState.cat_likes(cat_id)) if n == 0 else tr(String(c["lines"][n - 1]))
		Ui.toast(_root, text, Vector2(180, 600))
		Audio.sfx("meow1" if randf() < 0.5 else "meow2", 0.08, -4.0)


func _close() -> void:
	close()
