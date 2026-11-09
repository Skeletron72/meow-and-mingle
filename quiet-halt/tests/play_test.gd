extends Node
## Автотест игрового цикла: разговор, деревья, рыбалка, лопата, проекты, сохранение.
## godot --path . res://tests/play_test.tscn  (под xvfb)

var town: Node
var fails: int = 0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  OK   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	DialogueUI.test_mode = true
	Game.start_new_game("Тест", CharacterModel.default_look(), "Тихая Заводь", 0)
	World.state.flags.erase("arrival_pending")
	town = (load("res://scenes/town.tscn") as PackedScene).instantiate()
	add_child(town)
	await _frames(5)
	print("== Жители")
	var bv: Villager = town.villagers["barkhat"]
	bv.global_position = World.cell_center(Vector2i(40, 20))
	town.player.global_position = World.cell_center(Vector2i(39, 20))
	DialogueUI.test_choices = [0, 1, 2, 2]
	await town._talk(bv)
	check(int(World.state.villagers["barkhat"].friend) > 0, "дружба выросла после разговора")
	check(int(World.state.villagers["barkhat"].request) == 1, "просьба принята")
	Game.add_item("pear", 1)
	DialogueUI.test_choices = [2, 0]
	var money0: int = Game.money()
	await town._talk(bv)
	check(Game.money() > money0, "награда за просьбу получена")

	print("== Деревья")
	var tree_a: Vector2i = Vector2i(-1, -1)
	for k in World.state.objects.keys():
		var o: Dictionary = World.state.objects[k]
		if str(o.id) == "tree_apple" and int(o.st.get("fruit", 0)) > 0:
			tree_a = WorldState.cell_of(int(k))
			break
	check(tree_a.x >= 0, "найдено яблоня с плодами")
	town.player.global_position = World.cell_center(tree_a + Vector2i(0, 1))
	await town._shake_tree(tree_a)
	await _frames(40)
	var got: int = 0
	for p in town.pickups:
		if is_instance_valid(p):
			town.player.global_position = p.global_position
			await _frames(3)
	await _frames(5)
	check(Game.item_count("apple") >= 1, "яблоки подобраны (%d)" % Game.item_count("apple"))

	print("== Цветы и посадка")
	var flower: Vector2i = Vector2i(-1, -1)
	for k in World.state.objects.keys():
		if str(World.state.objects[k].id).begins_with("flower_"):
			flower = WorldState.cell_of(int(k))
			break
	check(flower.x >= 0, "есть дикие цветы")
	town._pick_flower(flower)
	check(World.state.object_at(flower).is_empty(), "цветок сорван")
	Game.add_item("seed_tulip", 1)
	town.player.global_position = World.cell_center(Vector2i(30, 25))
	town.player.facing = Vector3(1, 0, 0)
	await town._plant("seed_tulip", "flower_tulip")
	check(not World.state.object_at(Vector2i(31, 25)).is_empty(), "семя посажено")

	print("== Рыбалка")
	town.player.global_position = World.cell_center(Vector2i(10, 30))
	town.player.facing = Vector3(0, 0, 1)
	var fish_before: int = 0
	for s in Game.profile.items:
		if str(Data.item(str(s.id)).get("category", "")) in ["fish", "junk"]:
			fish_before += int(s.count)
	town._act_flag = false
	town._use_rod()
	var waited: float = 0.0
	var seen_mark: bool = false
	while waited < 9.0 and not seen_mark:
		await get_tree().process_frame
		waited += get_process_delta_time()
		for ch in town.get_children():
			if ch is Label3D:
				seen_mark = true
	check(seen_mark, "поклёвка случилась")
	await get_tree().create_timer(0.15).timeout
	town._act_flag = true
	await get_tree().create_timer(2.5).timeout
	var fish_after: int = 0
	for s in Game.profile.items:
		if str(Data.item(str(s.id)).get("category", "")) in ["fish", "junk"]:
			fish_after += int(s.count)
	check(fish_after > fish_before, "рыба поймана")

	print("== Лопата и журнал")
	var n1: Dictionary = Data.notes[0]
	var nc := Vector2i(int(n1.cell[0]), int(n1.cell[1]))
	town.player.global_position = World.cell_center(nc + Vector2i(-1, 0))
	town.player.facing = Vector3(1, 0, 0)
	await town._use_shovel()
	check(World.state.notes_found.size() == 1, "страница 1 найдена")

	print("== Проекты")
	Game.add_money(5000)
	for pid in ["clock", "benches", "lamps", "bridge", "fountain", "flowershop", "cafe"]:
		check(World.project_available(pid), "доступен проект " + pid)
		var take: int = World.fund_project(pid, 100000)
		Game.spend_money(take)
		Clock.add_debug_hours(30.0)
		World.process_days(Clock.day_index())
		World.tick_projects()
		await _frames(2)
		check(World.project_state(pid) == 3, "проект построен: " + pid)
	check(World.flag("bridge_built"), "мост построен (флаг)")
	check(World.state.get_ground(Vector2i(40, 33)) == WorldState.Ground.BRIDGE, "мост виден в данных мира")
	check(town.villagers.has("trostinka") and town.villagers.has("flanel"), "новые жители приехали")

	print("== Сохранение")
	check(Game.save_game(), "сохранено")
	var objs: int = World.state.objects.size()
	var money: int = Game.money()
	Game.profile.money = 0
	World.state.objects.clear()
	check(Game.load_game(), "загружено")
	check(World.state.objects.size() == objs, "объекты восстановлены (%d)" % objs)
	check(Game.money() == money, "деньги восстановлены")
	check(World.project_state("cafe") == 3, "прогресс проектов восстановлен")

	print("== Итого: ", "ВСЁ ХОРОШО" if fails == 0 else "ПРОВАЛОВ: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
