extends Node3D
## Стрелки вокзальных часов — идут по системному времени.
var _hour: MeshInstance3D
var _min: MeshInstance3D
var _pivots: Array = []

func _ready() -> void:
	for side in [1.0, -1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(0, 3.9, 1.235 * side)
		if side < 0:
			piv.rotation.y = PI
		add_child(piv)
		var hp := Node3D.new()
		var mp := Node3D.new()
		piv.add_child(hp)
		piv.add_child(mp)
		var hm := MeshKit.new()
		hm.box(Vector3(0, 0.15, 0), Vector3(0.07, 0.34, 0.02), Color(0.2, 0.17, 0.17))
		var mm := MeshKit.new()
		mm.box(Vector3(0, 0.22, 0.015), Vector3(0.045, 0.46, 0.02), Color(0.2, 0.17, 0.17))
		var a := MeshInstance3D.new()
		a.mesh = hm.build()
		hp.add_child(a)
		var b := MeshInstance3D.new()
		b.mesh = mm.build()
		mp.add_child(b)
		_pivots.append([hp, mp])

func _process(_delta: float) -> void:
	var h: float = Clock.hour_float()
	var m: float = fposmod(h, 1.0) * 60.0
	var ha: float = -TAU * fposmod(h, 12.0) / 12.0
	var ma: float = -TAU * m / 60.0
	for p in _pivots:
		(p[0] as Node3D).rotation.z = ha
		(p[1] as Node3D).rotation.z = ma
