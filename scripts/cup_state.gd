class_name CupState
extends RefCounted
## Что сейчас лежит в чашке игрока. Чистая логика, без узлов: легко тестировать.

var base: String = ""     # "coffee" | "tea" | ""
var milk: bool = false
var syrup: bool = false
var pastry: String = ""   # id из pastries.json или ""
var mods: Array[String] = []   # добавки: "ice" лёд, "cinnamon" корица, "cream" сливки, "double" двойная порция кофе
var pastry_mods: Array[String] = []   # начинки на выпечке: "syrup", "cream", "cinnamon" (до двух)
const PASTRY_TOPPINGS := ["syrup", "cream", "cinnamon"]
const PASTRY_MODS_MAX := 2
var allow_double := false      # вторая порция кофе: открыта улучшением «Кофемашина Pro»


func is_empty() -> bool:
	return base == "" and not milk and not syrup and pastry == "" and mods.is_empty() and pastry_mods.is_empty()


func clear() -> void:
	base = ""
	milk = false
	syrup = false
	pastry = ""
	mods = []
	pastry_mods = []


## Добавляет ингредиент. Возвращает текст ошибки или "" при успехе.
func add(kind: String, id: String) -> String:
	match kind:
		"base":
			if base == id and id == "coffee" and allow_double:
				if "double" in mods:
					return "Двойная порция уже есть"
				mods.append("double")   # кофе ещё раз — двойная порция
			elif base != "" and base != id and ((base == "coffee" and id == "cocoa") or (base == "cocoa" and id == "coffee")):
				if "cocoa" in mods:
					return "Это уже добавлено"
				base = "coffee"   # кофе + какао: две основы — «мокко»
				mods.append("cocoa")
			else:
				if base != "" and base != id:
					mods.erase("double")
					mods.erase("cocoa")
				base = id
		"extra":
			if base == "":
				return "Сначала кофе или чай"
			if id in mods:
				return "Это уже добавлено"
			mods.append(id)
		"milk":
			if base == "":
				return "Сначала кофе или чай"
			milk = true
		"syrup":
			if base == "":
				return "Сначала кофе или чай"
			syrup = true
		"pastry":
			if pastry != id:
				pastry_mods = []
			pastry = id
	return ""


## Начинка на выпечку (сироп, сливки, корица): выпечка уже на подносе, не больше двух разных.
func add_to_pastry(id: String) -> String:
	if pastry == "":
		return "Сначала выпечка"
	if not (id in PASTRY_TOPPINGS):
		return "Это не кладут на выпечку"
	if id in pastry_mods:
		return "Это уже добавлено"
	if pastry_mods.size() >= PASTRY_MODS_MAX:
		return "Достаточно начинки"
	pastry_mods.append(id)
	return ""


## id напитка по рецепту (с добавками) или "" (основы ещё нет или такого напитка в меню нет).
func drink_id() -> String:
	if base == "":
		return ""
	for id in Data.drinks:
		var r: Dictionary = Data.drinks[id]["recipe"]
		if r["base"] == base and bool(r["milk"]) == milk and bool(r.get("syrup", false)) == syrup and same_mods(r.get("mods", []), mods):
			return id
	return ""


## Как выглядит чашка на подносе: точный напиток или, если такого нет, ближайший без добавок (добавки рисуются значками поверх).
func look_id() -> String:
	var id := drink_id()
	if id != "" or base == "":
		return id
	for k in Data.drinks:
		var r: Dictionary = Data.drinks[k]["recipe"]
		if r["base"] == base and bool(r["milk"]) == milk and bool(r.get("syrup", false)) == syrup and (r.get("mods", []) as Array).is_empty():
			return k
	for k in Data.drinks:
		if Data.drinks[k]["recipe"]["base"] == base:
			return k
	return ""


static func same_mods(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for m in a:
		if not (String(m) in b):
			return false
	return true


## Горячий ли напиток в чашке (остывает со временем): всё, кроме холодных — со льдом.
func is_hot() -> bool:
	return base != "" and not ("ice" in mods)


## Собирает чашку по рецепту напитка (для подсказок «Автосборки», обучения и тестов).
func fill(drink: String, pastry_id := "", pastry_toppings: Array = []) -> void:
	clear()
	var r: Dictionary = Data.drinks[drink]["recipe"]
	base = String(r["base"])
	milk = bool(r["milk"])
	syrup = bool(r.get("syrup", false))
	for m in r.get("mods", []):
		mods.append(String(m))
	pastry = pastry_id
	for m in pastry_toppings:
		pastry_mods.append(String(m))


func matches(order: Dictionary) -> bool:
	return drink_id() == String(order["drink"]) and pastry == String(order["pastry"]) and same_mods(pastry_mods, order.get("pastry_mods", []))
