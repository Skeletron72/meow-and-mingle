extends Node
## Снимок сцены для проверки вёрстки (нужен дисплей, например xvfb):
##   xvfb-run -a godot --path . res://tools/screenshot.tscn -- res://scenes/menu.tscn /tmp/menu.png [секунды]
## Сохранение игры при этом не затрагивается только если сцена ничего не покупает — снимайте на копии user://.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: Node = (load(args[0]) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().create_timer(float(args[2]) if args.size() > 2 else 1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(args[1])
	get_tree().quit()
