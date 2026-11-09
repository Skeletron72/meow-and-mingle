class_name Player
extends Node3D
## Игрок: движение по сетке мира, действия инструментами, взаимодействие.

signal interact_requested

const RADIUS: float = 0.3
const WALK: float = 3.4
const RUN: float = 5.6

var model: CharacterModel
var controls_enabled: bool = true
var cam_yaw: float = PI
var touch_vec: Vector2 = Vector2.ZERO
var facing: Vector3 = Vector3(0, 0, 1)
var velocity: Vector3 = Vector3.ZERO
var held_visual: Node3D
var busy: bool = false


func _ready() -> void:
	model = CharacterModel.new()
	add_child(model)
	model.build(Game.profile.get("look", CharacterModel.default_look()))
	var blob := MeshInstance3D.new()
	var d := CylinderMesh.new()
	d.top_radius = 0.38
	d.bottom_radius = 0.38
	d.height = 0.01
	d.radial_segments = 14
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0, 0.18)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	d.material = m
	blob.mesh = d
	blob.position.y = 0.02
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blob)


func cell() -> Vector2i:
	return World.world_to_cell(global_position)


func _free(p: Vector3) -> bool:
	var r: float = RADIUS
	for off in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		if not World.state.is_walkable(Vector2i(int(floor(p.x + off.x)), int(floor(p.z + off.y)))):
			return false
	return true


func _physics_process(delta: float) -> void:
	var v: Vector2 = Vector2.ZERO
	if controls_enabled and not busy:
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if touch_vec.length() > v.length():
			v = touch_vec
	var speed: float = RUN if Input.is_action_pressed("run") else WALK
	var f := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var r := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var dir: Vector3 = r * v.x + f * (-v.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var move: Vector3 = dir * speed * (1.0 if v.length() > 0.65 or speed == RUN else maxf(v.length() / 0.65, 0.0))
	var p: Vector3 = global_position
	var nx := Vector3(p.x + move.x * delta, p.y, p.z)
	if _free(nx):
		p.x = nx.x
	var nz := Vector3(p.x, p.y, p.z + move.z * delta)
	if _free(nz):
		p.z = nz.z
	p.y = World.state.height_at(p.x, p.z)
	global_position = p
	if dir.length() > 0.05:
		facing = dir.normalized()
		var target_yaw: float = atan2(facing.x, facing.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, minf(delta * 14.0, 1.0))
	model.animate(delta, clampf(dir.length() * speed / RUN, 0.0, 1.0))


func face_toward(point: Vector3) -> void:
	var d: Vector3 = point - global_position
	d.y = 0
	if d.length() > 0.01:
		facing = d.normalized()
		var t := create_tween()
		t.tween_property(model, "rotation:y", atan2(facing.x, facing.z), 0.15)


## Клетка перед игроком (на расстоянии ~1 клетки).
func front_cell(dist: float = 1.0) -> Vector2i:
	var p: Vector3 = global_position + facing * dist
	return World.world_to_cell(p)


func front_point(dist: float = 1.0) -> Vector3:
	return global_position + facing * dist
