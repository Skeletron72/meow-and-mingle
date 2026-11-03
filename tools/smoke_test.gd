extends Node
## Запуск: godot --headless --path . res://tools/smoke_test.tscn
## Проверяет цикл «кот пришёл -> заказ собран -> монеты» и неверный заказ.

func _fail(msg: String) -> void:
	push_error("SMOKE FAIL: " + msg)
	get_tree().quit(1)


func _ready() -> void:
	var main: Node2D = load("res://main.tscn").instantiate()
	main.level = {"id": "t", "name": "Тест", "customers": 4, "interval": [0.6, 0.8], "patience": 30.0, "queue": 2, "speed": 10.0, "accuracy": 0.8, "pool": [], "pastry": 0.0}
	add_child(main)
	await get_tree().create_timer(2.4).timeout
	if not main._awaiting:
		_fail("кот не пришёл")
		return
	var order: Dictionary = main._order
	var recipe: Dictionary = Data.drinks[order["drink"]]["recipe"]
	main._cup.add("base", recipe["base"])
	if recipe["milk"]:
		main._cup.add("milk", "milk")
	if order["pastry"] != "":
		main._cup.add("pastry", order["pastry"])
	var before: int = GameState.coins
	main._serve()
	if GameState.coins <= before:
		_fail("монеты не начислены")
		return
	if not FileAccess.file_exists(GameState.SAVE_PATH):
		_fail("нет файла сохранения")
		return
	await get_tree().create_timer(2.5).timeout
	if not main._awaiting:
		_fail("второй кот не пришёл")
		return
	var coins_mid: int = GameState.coins
	main._cup.add("base", "tea" if main._order["drink"] != "tea" else "coffee")
	main._serve()
	if GameState.coins != coins_mid:
		_fail("за неверный заказ начислены монеты")
		return
	print("SMOKE PASS coins=", GameState.coins)
	get_tree().quit(0)
