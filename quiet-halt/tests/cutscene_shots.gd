extends Node
func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def

func _snap(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_arg("out", "/tmp") + "_" + n + ".png")
	print("saved ", n)

func _ready() -> void:
	DialogueUI.test_mode = true
	Game.start_new_game("Алиса", {"skin": 1, "hair": 2, "hair_color": 2, "eyes": 1, "outfit": 1, "cap": true}, "Тихая Заводь", 0)
	var town: Node = (load("res://scenes/town.tscn") as PackedScene).instantiate()
	add_child(town)
	await get_tree().create_timer(3.0).timeout
	await _snap("c1")
	await get_tree().create_timer(5.5).timeout
	await _snap("c2")
	await get_tree().create_timer(2.0).timeout
	await _snap("c3")
	await get_tree().create_timer(6.0).timeout
	await _snap("c4")
	print("arrival_pending=", World.flag("arrival_pending"), " cutscene=", town._cutscene)
	get_tree().quit()
