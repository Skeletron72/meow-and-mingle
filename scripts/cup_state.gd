class_name CupState
extends RefCounted
## Что сейчас лежит в чашке игрока. Чистая логика, без узлов: легко тестировать.

var base: String = ""     # "coffee" | "tea" | ""
var milk: bool = false
var pastry: String = ""   # id из pastries.json или ""


func is_empty() -> bool:
	return base == "" and not milk and pastry == ""


func clear() -> void:
	base = ""
	milk = false
	pastry = ""


## Добавляет ингредиент. Возвращает текст ошибки или "" при успехе.
func add(kind: String, id: String) -> String:
	match kind:
		"base":
			base = id
		"milk":
			if base == "":
				return "Сначала кофе или чай"
			milk = true
		"pastry":
			pastry = id
	return ""


## id напитка по рецепту или "" (основы ещё нет).
func drink_id() -> String:
	if base == "":
		return ""
	for id in Data.drinks:
		var r: Dictionary = Data.drinks[id]["recipe"]
		if r["base"] == base and bool(r["milk"]) == milk:
			return id
	return ""


func matches(order: Dictionary) -> bool:
	return drink_id() == String(order["drink"]) and pastry == String(order["pastry"])
