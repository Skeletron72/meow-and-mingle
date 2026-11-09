extends Node
## Снимок города для проверки внешнего вида (запуск через xvfb):
##   godot --path . res://tests/shot.tscn -- --date=2026-07-15 --hour=12 --pos=40,12 --yaw=3.14 --out=/tmp/a.png
## Параметры: date, hour, pos (клетки x,z), yaw, dist, pitch, out, hemi, scene (town)

func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


func _ready() -> void:
	var date: String = _arg("date", "")
	var hour: float = float(_arg("hour", "-1"))
	if date != "" or hour >= 0.0:
		var d: String = date if date != "" else Time.get_date_string_from_system()
		var parts: PackedStringArray = d.split("-")
		var h: float = hour if hour >= 0.0 else 12.0
		var target: float = Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": int(h), "minute": int((h - floor(h)) * 60.0), "second": 0})
		var tz: Dictionary = Time.get_time_zone_from_system()
		var real_local: float = Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0
		Clock.debug_offset_sec = target - real_local
	var scene_name: String = _arg("scene", "town")
	if scene_name == "town" and not Game.in_game:
		pass
	var scene: Node = (load("res://scenes/%s.tscn" % scene_name) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var hemi: int = int(_arg("hemi", "0"))
	if scene_name == "town":
		Clock.hemisphere = hemi
		World.state.hemisphere = hemi
	var posarg: PackedStringArray = _arg("pos", "40,12").split(",")
	var t: Node = scene
	if "player" in t:
		t.player.global_position = World.cell_center(Vector2i(int(posarg[0]), int(posarg[1])))
		t.cam.yaw = float(_arg("yaw", "3.14159"))
		t.cam.distance = float(_arg("dist", "9.5"))
		t.cam.zoom_target = t.cam.distance
		t.cam.pitch_deg = float(_arg("pitch", "36"))
		t.cam.snap()
	var frames: int = int(_arg("frames", "12"))
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out: String = _arg("out", "/tmp/shot.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
