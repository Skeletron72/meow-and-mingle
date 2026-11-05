extends Node
const KINDS := [
	["crate", 1, 1], ["sack", 1, 1], ["boxes", 1, 1], ["shelf", 2, 1], ["fridge", 1, 1], ["sink", 1, 1], ["mop", 1, 1], ["catbed", 1, 1],
	["stairs_up", 2, 2], ["stairs_up_open", 2, 2],
	["bed", 2, 2], ["wardrobe", 1, 1], ["sofa", 2, 1], ["bookshelf", 2, 1], ["lamp", 1, 1], ["stairs_down", 3, 2],
]
func _ready() -> void:
	var S: String = OS.get_cmdline_user_args()[0]
	for k in KINDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(224, 176)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var p := SpaceProp.new()
		var kid := String(k[0])
		p.kind_id = kid.replace("_open", "")
		p.cells = Vector2i(int(k[1]), int(k[2]))
		p.locked = not kid.ends_with("_open")
		p.position = Vector2(112, 160)
		vp.add_child(p)
		await get_tree().process_frame
		await get_tree().process_frame
		vp.get_texture().get_image().save_png(S + "/" + kid + ".png")
		vp.queue_free()
	get_tree().quit()
