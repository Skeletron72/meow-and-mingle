class_name Train
extends Node3D
## Паровозик с двумя вагонами. Борт с дверями смотрит на +Z (в сторону перрона).

var length: float = 14.0


func _ready() -> void:
	var k := MeshKit.new()
	var teal: Color = Color(0.32, 0.58, 0.60)
	var cream: Color = Color(0.97, 0.90, 0.74)
	var red: Color = Color(0.78, 0.36, 0.32)
	var dark: Color = Color(0.25, 0.26, 0.30)
	# локомотив (x от 0 до 3.6), движется в сторону +X
	var xf0: Transform3D = k.xf
	k.xf = xf0 * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(2.5, 0.9, 0))
	k.cyl(Vector3(0, -1.1, 0), 0.62, 0.62, 2.2, dark, 12)
	k.xf = xf0
	k.box(Vector3(1.15, 1.8, 0), Vector3(0.4, 0.2, 0.4), dark)
	k.cyl(Vector3(2.9, 1.3, 0), 0.22, 0.32, 0.7, dark, 8)
	k.box(Vector3(0.7, 1.35, 0), Vector3(1.4, 1.6, 1.5), red)
	k.box(Vector3(0.7, 2.2, 0), Vector3(1.6, 0.14, 1.7), dark)
	k.box(Vector3(0.7, 1.4, 0.76), Vector3(0.5, 0.5, 0.05), Color(1.0, 0.9, 0.6), "glow")
	k.box(Vector3(0.7, 1.4, -0.76), Vector3(0.5, 0.5, 0.05), Color(1.0, 0.9, 0.6), "glow")
	k.cyl(Vector3(3.5, 0.4, 0), 0.0, 0.0, 0.01, dark, 3)
	for wx in [0.4, 1.4, 2.4, 3.0]:
		for wz in [-0.7, 0.7]:
			var xf1: Transform3D = k.xf
			k.xf = xf1 * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(wx, 0.38, wz))
			k.cyl(Vector3(0, -0.06, 0), 0.34, 0.34, 0.12, Color(0.28, 0.28, 0.32), 10)
			k.xf = xf1
	k.box(Vector3(3.6, 0.55, 0), Vector3(0.3, 0.5, 1.2), dark)
	# вагоны
	for c in 2:
		var cx: float = -1.2 - float(c) * 4.7
		k.box(Vector3(cx, 1.25, 0), Vector3(4.4, 1.7, 1.6), teal if c == 0 else Color(0.52, 0.42, 0.62))
		k.box(Vector3(cx, 0.5, 0), Vector3(4.5, 0.18, 1.7), dark)
		k.box(Vector3(cx, 2.15, 0), Vector3(4.6, 0.14, 1.8), cream)
		k.gable(Vector3(cx, 2.2, 0), 4.6, 1.2, 0.35, cream, 0.0)
		for wi in 4:
			var wx2: float = cx - 1.6 + float(wi) * 1.05
			k.box(Vector3(wx2, 1.5, 0.82), Vector3(0.7, 0.6, 0.05), Color(1.0, 0.9, 0.6), "glow")
			k.box(Vector3(wx2, 1.5, -0.82), Vector3(0.7, 0.6, 0.05), Color(1.0, 0.9, 0.6), "glow")
		k.box(Vector3(cx + 1.9, 0.95, 0.82), Vector3(0.7, 1.3, 0.06), Color(0.48, 0.32, 0.26))
		for wx3 in [-1.6, 1.6]:
			for wz in [-0.7, 0.7]:
				var xf2: Transform3D = k.xf
				k.xf = xf2 * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(cx + wx3, 0.38, wz))
				k.cyl(Vector3(0, -0.06, 0), 0.3, 0.3, 0.12, Color(0.28, 0.28, 0.32), 10)
				k.xf = xf2
	var mi := MeshInstance3D.new()
	mi.mesh = k.build()
	add_child(mi)
	var smoke := CPUParticles3D.new()
	smoke.position = Vector3(2.9, 2.1, 0)
	smoke.amount = 14
	smoke.lifetime = 2.2
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 15.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.0
	smoke.gravity = Vector3(0, 0.3, 0)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.2
	smoke.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = Mats.unlit(Color(0.95, 0.95, 0.97, 0.4))
	smoke.mesh = sm
	add_child(smoke)
