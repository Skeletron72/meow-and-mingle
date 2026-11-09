class_name Villager
extends Node3D
## Житель-Ворсинка: ходит по расписанию, разговаривает, спит ночью.

var vid: String = ""
var data: Dictionary = {}
var model: VillagerModel
var home_cell: Vector2i
var _path: PackedVector2Array = PackedVector2Array()
var _path_i: int = 0
var _wait: float = 0.0
var _rng := RandomNumberGenerator.new()
var talking: bool = false
var sleeping: bool = false
var scripted: bool = false ## кат-сцена управляет им
var _face_target: Node3D
var speed: float = 1.6
var _emote: Label3D


func setup(d: Dictionary) -> void:
	data = d
	vid = str(d.id)
	var h: Array = d.home
	home_cell = Vector2i(int(h[0]) + 1, int(h[1]) + 3)
	_rng.seed = hash(vid)
	model = VillagerModel.new()
	add_child(model)
	var c: Array = d.color
	model.build(str(d.species), Color(c[0], c[1], c[2]))
	_emote = Label3D.new()
	_emote.position = Vector3(0, 1.8, 0)
	_emote.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote.font_size = 48
	_emote.pixel_size = 0.01
	_emote.outline_size = 12
	_emote.no_depth_test = true
	_emote.visible = false
	add_child(_emote)
	_wait = _rng.randf_range(0.5, 4.0)


func cell() -> Vector2i:
	return World.world_to_cell(global_position)


func _process(delta: float) -> void:
	if scripted:
		model.animate(delta, 0.0)
		return
	_update_sleep()
	if sleeping:
		return
	if talking:
		model.animate(delta, 0.0)
		if _face_target:
			_turn_to(_face_target.global_position, delta)
		return
	if _path_i < _path.size():
		var target: Vector2 = _path[_path_i]
		var tp := Vector3(target.x + 0.5, 0, target.y + 0.5)
		var d: Vector3 = tp - Vector3(global_position.x, 0, global_position.z)
		if d.length() < 0.12:
			_path_i += 1
		else:
			var step: Vector3 = d.normalized() * speed * delta
			global_position += step
			global_position.y = World.state.height_at(global_position.x, global_position.z)
			_turn_to(global_position + d, delta)
		model.animate(delta, 1.0)
	else:
		model.animate(delta, 0.0)
		_wait -= delta
		if _wait <= 0.0:
			_pick_destination()


func _turn_to(p: Vector3, delta: float) -> void:
	var d: Vector3 = p - global_position
	d.y = 0
	if d.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), minf(delta * 8.0, 1.0))


func _update_sleep() -> void:
	var h: float = Clock.hour_float()
	var should: bool = h >= 23.0 or h < 6.5
	if should and not sleeping:
		sleeping = true
		visible = false
	elif not should and sleeping:
		sleeping = false
		visible = true
		global_position = World.cell_center(home_cell)
		_path = PackedVector2Array()
		_path_i = 0


func _pick_destination() -> void:
	_wait = _rng.randf_range(2.0, 7.0)
	if _rng.randf() < 0.3:
		say_emote(["♪", "…", "!", "♥", "?"][_rng.randi() % 5], 1.6)
	for i in 6:
		var off := Vector2i(_rng.randi_range(-9, 9), _rng.randi_range(-7, 7))
		var tc: Vector2i = home_cell + off
		if World.state.is_walkable(tc) and World.state.get_ground(tc) != WorldState.Ground.WATER:
			var path: PackedVector2Array = World.find_path(cell(), tc)
			if path.size() > 1 and path.size() < 22:
				_path = path
				_path_i = 1
				return


func walk_to(c: Vector2i) -> bool:
	var path: PackedVector2Array = World.find_path(cell(), c)
	if path.size() == 0:
		return false
	_path = path
	_path_i = 1
	return true


func is_walking() -> bool:
	return _path_i < _path.size()


func start_talk(who: Node3D) -> void:
	talking = true
	_face_target = who
	_emote.visible = false


func end_talk() -> void:
	talking = false
	_face_target = null


func say_emote(text: String, secs: float = 1.5) -> void:
	_emote.text = text
	_emote.visible = true
	await get_tree().create_timer(secs).timeout
	if is_instance_valid(_emote):
		_emote.visible = false
