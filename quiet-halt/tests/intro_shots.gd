extends Node
## Скриншоты шагов вступления: godot --path . res://tests/intro_shots.tscn -- --out=/tmp/x

func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


func _snap(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_arg("out", "/tmp") + "_" + n + ".png")
	print("saved ", n)


func _ready() -> void:
	DialogueUI.test_mode = true
	var intro: Node = (load("res://scenes/intro.tscn") as PackedScene).instantiate()
	add_child(intro)
	# ждём окно имени
	await get_tree().create_timer(2.5).timeout
	await _snap("1_name")
	intro._text_done.emit("Алиса")
	await get_tree().create_timer(1.5).timeout
	intro.look = {"skin": 2, "hair": 3, "hair_color": 3, "eyes": 2, "outfit": 3, "cap": true}
	intro._refresh_preview()
	await _snap("2_creator")
	intro._creator_done.emit()
	await get_tree().create_timer(1.5).timeout
	await _snap("3_station")
	intro._text_done.emit("Тихая Заводь")
	await get_tree().create_timer(1.5).timeout
	await _snap("4_hemi")
	get_tree().quit()
