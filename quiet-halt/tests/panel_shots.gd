extends Node
## Скриншоты окон интерфейса в городе.

func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


func _snap(n: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_arg("out", "/tmp") + "_" + n + ".png")
	print("saved ", n)


func _ready() -> void:
	DialogueUI.test_mode = true
	Game.start_new_game("Алиса", CharacterModel.default_look(), "Тихая Заводь", 0)
	World.state.flags.erase("arrival_pending")
	Game.set_setting("touch", true)
	var town: Node = (load("res://scenes/town.tscn") as PackedScene).instantiate()
	add_child(town)
	await get_tree().process_frame
	for id in ["apple", "pear", "carp", "crucian", "goldfish", "tulip", "butterfly", "seed_aster", "sapling_cherry", "firefly", "boot"]:
		Game.add_item(id, 3 if id in ["apple", "crucian"] else 1)
	Game.profile.caught["carp"] = 1
	Game.profile.caught["butterfly"] = 2
	World.state.villagers["barkhat"].friend = 55
	World.state.villagers["pukh"].friend = 12
	World.state.notes_found.append("n1")
	World.state.notes_found.append("n2")
	await get_tree().create_timer(0.5).timeout
	await _snap("0_hud")
	town.bag_panel.open_panel()
	await _snap("1_bag")
	town.bag_panel._select("carp")
	await _snap("1b_bag_sel")
	town.bag_panel.close_panel()
	town.shop_panel.open_shop("Привокзальная лавка", ["sapling_apple", "sapling_pear", "sapling_cherry"])
	await _snap("2_shop_buy")
	town.shop_panel._set_tab(1)
	await _snap("3_shop_sell")
	town.shop_panel.close_panel()
	town.projects_panel.open_panel()
	await _snap("4_projects")
	town.projects_panel.close_panel()
	town.journal_panel.open_tab(0)
	await _snap("5_journal")
	town.journal_panel.open_tab(1)
	await _snap("6_residents")
	town.journal_panel.open_tab(2)
	await _snap("7_collection")
	town.journal_panel.close_panel()
	town.pause_panel.open_panel()
	await _snap("8_pause")
	town.pause_panel.close_panel()
	var v: Villager = town.villagers["pukh"]
	v.global_position = town.player.global_position + Vector3(1.0, 0, 0)
	DialogueUI.test_mode = false
	town._talk(v)
	await get_tree().create_timer(1.5).timeout
	await _snap("9_dialogue")
	get_tree().quit()
