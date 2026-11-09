class_name CameraRig
extends Node3D
## Камера «как в New Leaf»: сзади-сверху, плавно следует, вращается Q/E или перетаскиванием.

var target: Node3D
var yaw: float = PI
var pitch_deg: float = 36.0
var distance: float = 9.5
var zoom_target: float = 9.5
var cam: Camera3D
var shake: float = 0.0
var _yaw_vel: float = 0.0
var look_offset: Vector3 = Vector3(0, 0.9, 0)
var free_look: bool = false


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.near = 0.2
	cam.far = 260.0
	cam.current = true
	add_child(cam)


func _process(delta: float) -> void:
	var input_dir: float = Input.get_axis("cam_left", "cam_right")
	_yaw_vel = lerpf(_yaw_vel, input_dir * 1.8, minf(delta * 8.0, 1.0))
	yaw += _yaw_vel * delta
	distance = lerpf(distance, zoom_target, minf(delta * 3.0, 1.0))
	if target and not free_look:
		global_position = global_position.lerp(target.global_position + look_offset, minf(delta * 7.0, 1.0))
	var pitch: float = deg_to_rad(pitch_deg)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	cam.position = off
	cam.look_at(global_position, Vector3.UP)
	if shake > 0.0:
		shake = maxf(shake - delta * 2.0, 0.0)
		cam.h_offset = randf_range(-1, 1) * shake * 0.1
		cam.v_offset = randf_range(-1, 1) * shake * 0.1
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


func rotate_by(dx: float) -> void:
	yaw -= dx * 0.008


func snap() -> void:
	if target:
		global_position = target.global_position + look_offset
