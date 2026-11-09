class_name Glint
extends Node3D
## Мерцание в земле — место, где закопана страница журнала.

var _t: float = 0.0


func _ready() -> void:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.gravity = Vector3(0, 0.2, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	sm.radial_segments = 4
	sm.rings = 2
	sm.material = Mats.unlit(Color(1.0, 0.92, 0.5, 0.95))
	p.mesh = sm
	add_child(p)
	var k := MeshKit.new()
	k.ball(Vector3(0, 0.0, 0), Vector3(0.14, 0.03, 0.1), Color(0.95, 0.85, 0.5), 6, 3, "glow")
	var mi := MeshInstance3D.new()
	mi.mesh = k.build()
	mi.material_override = Mats.always_glow()
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	scale = Vector3.ONE * (0.85 + 0.15 * sin(_t * 3.0))
