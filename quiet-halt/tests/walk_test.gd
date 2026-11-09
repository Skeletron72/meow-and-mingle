extends Node
## Проверка: жители гуляют днём, игрок ходит и упирается в препятствия.
func _ready() -> void:
	var tz: Dictionary = Time.get_time_zone_from_system()
	var real_local: float = Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(int(real_local))
	d.hour = 12; d.minute = 0; d.second = 0
	Clock.debug_offset_sec = Time.get_unix_time_from_datetime_dict(d) - real_local
	Game.start_new_game("Т", CharacterModel.default_look(), "Т", 0)
	World.state.flags.erase("arrival_pending")
	var town: Node = (load("res://scenes/town.tscn") as PackedScene).instantiate()
	add_child(town)
	await get_tree().process_frame
	var start: Dictionary = {}
	for id in town.villagers:
		start[id] = (town.villagers[id] as Node3D).global_position
	# игрок идёт «вниз» (на юг от вокзала) — эмулируем стик
	town.player.global_position = World.cell_center(Vector2i(40, 20))
	town.cam.yaw = PI
	await get_tree().process_frame
	town.hud.touch.stick = Vector2(0, -1) # вперёд (камера смотрит на юг)
	var t0: Vector3 = town.player.global_position
	await get_tree().create_timer(3.0).timeout
	town.hud.touch.stick = Vector2.ZERO
	var t1: Vector3 = town.player.global_position
	print("игрок прошёл: ", t0.distance_to(t1), " по z: ", t1.z - t0.z)
	# упереться в воду
	town.player.global_position = World.cell_center(Vector2i(10, 30))
	town.hud.touch.stick = Vector2(0, -1)
	await get_tree().create_timer(2.5).timeout
	print("у реки z=", town.player.global_position.z, " (вода начинается с 32, остановка должна быть < 32)")
	town.hud.touch.stick = Vector2.ZERO
	await get_tree().create_timer(14.0).timeout
	var moved: int = 0
	for id in town.villagers:
		var dd: float = (town.villagers[id] as Node3D).global_position.distance_to(start[id])
		print(id, " сместился на ", snappedf(dd, 0.1), " sleeping=", town.villagers[id].sleeping)
		if dd > 0.5:
			moved += 1
	print("гуляют: ", moved, " из ", town.villagers.size())
	get_tree().quit()
