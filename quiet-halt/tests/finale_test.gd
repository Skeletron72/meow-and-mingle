extends Node
## Проверка финала: все страницы + часы + фонари + полночь на перроне = поезд и ключ.
func _ready() -> void:
	DialogueUI.test_mode = true
	var tz: Dictionary = Time.get_time_zone_from_system()
	var real_local: float = Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(int(real_local))
	d.hour = 0; d.minute = 30; d.second = 0
	Clock.debug_offset_sec = Time.get_unix_time_from_datetime_dict(d) - real_local
	Game.start_new_game("Т", CharacterModel.default_look(), "Т", 0)
	World.state.flags.erase("arrival_pending")
	for n in Data.notes:
		World.state.notes_found.append(n.id)
	World.state.projects["clock"].state = 3
	World.state.projects["lamps"].state = 3
	var town: Node = (load("res://scenes/town.tscn") as PackedScene).instantiate()
	add_child(town)
	await get_tree().process_frame
	town.player.global_position = World.cell_center(Vector2i(38, 9))
	await get_tree().create_timer(25.0).timeout
	print("финал: ключ=", Game.item_count("key_dispatch"), " флаг=", World.flag("finale_done"))
	get_tree().quit()
