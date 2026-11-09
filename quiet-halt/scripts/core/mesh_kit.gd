class_name MeshKit
extends RefCounted
## Процедурные низкополигональные меши с цветом в вершинах.
## Все модели игры (деревья, дома, персонажи) собираются отсюда — внешних ассетов нет.

var xf: Transform3D = Transform3D.IDENTITY
var ao: float = 0.82 ## затемнение низа деталей (дешёвая имитация AO)
var _s: Dictionary = {}


func _surf(name: String) -> Dictionary:
	if not _s.has(name):
		_s[name] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray()}
	return _s[name]


func _push(sf: Dictionary, p: Vector3, n: Vector3, c: Color) -> void:
	var vv: PackedVector3Array = sf.v
	var nn: PackedVector3Array = sf.n
	var cc: PackedColorArray = sf.c
	vv.append(xf * p)
	nn.append((xf.basis * n).normalized())
	cc.append(c)
	sf.v = vv
	sf.n = nn
	sf.c = cc


func _tri(sf: Dictionary, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, inside: Vector3 = Vector3(INF, INF, INF), out_n: Vector3 = Vector3.ZERO) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	if out_n != Vector3.ZERO:
		n = out_n
	elif inside.x != INF and n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
	_push(sf, a, n, ca)
	_push(sf, b, n, cb)
	_push(sf, c, n, cc)


func _dark(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## Коробка. center — центр, size — размеры.
func box(center: Vector3, size: Vector3, color: Color, surf: String = "main") -> void:
	var sf: Dictionary = _surf(surf)
	var h: Vector3 = size * 0.5
	var lo: Color = _dark(color, ao)
	var p: Array = []
	for i in 8:
		p.append(center + Vector3(h.x if (i & 1) else -h.x, h.y if (i & 2) else -h.y, h.z if (i & 4) else -h.z))
	# грани: индексы вершин (против часовой, снаружи)
	var faces: Array = [
		[1, 5, 7, 3], [4, 0, 2, 6], # +x, -x
		[2, 3, 7, 6], [4, 5, 1, 0], # +y, -y
		[5, 4, 6, 7], [0, 1, 3, 2], # +z, -z
	]
	var norms: Array = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for fi in faces.size():
		var f: Array = faces[fi]
		var fn: Vector3 = norms[fi]
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var d: Vector3 = p[f[3]]
		var ca: Color = lo if a.y < center.y else color
		var cb: Color = lo if b.y < center.y else color
		var cc: Color = lo if c.y < center.y else color
		var cd: Color = lo if d.y < center.y else color
		_tri(sf, a, b, c, ca, cb, cc, Vector3(INF, INF, INF), fn)
		_tri(sf, a, c, d, ca, cc, cd, Vector3(INF, INF, INF), fn)


## Цилиндр/конус: base — центр нижнего основания.
func cyl(base: Vector3, r0: float, r1: float, height: float, color: Color, sides: int = 8, surf: String = "main", cap: bool = true) -> void:
	var sf: Dictionary = _surf(surf)
	var lo: Color = _dark(color, ao)
	for i in sides:
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var c0 := Vector3(cos(a0), 0, sin(a0))
		var c1 := Vector3(cos(a1), 0, sin(a1))
		var b0: Vector3 = base + c0 * r0
		var b1: Vector3 = base + c1 * r0
		var t0: Vector3 = base + Vector3(0, height, 0) + c0 * r1
		var t1: Vector3 = base + Vector3(0, height, 0) + c1 * r1
		var n0: Vector3 = Vector3(c0.x * height, r0 - r1, c0.z * height).normalized()
		var n1: Vector3 = Vector3(c1.x * height, r0 - r1, c1.z * height).normalized()
		# боковая грань
		_push(sf, b0, n0, lo)
		_push(sf, t0, n0, color)
		_push(sf, b1, n1, lo)
		if r1 > 0.0001:
			_push(sf, b1, n1, lo)
			_push(sf, t0, n0, color)
			_push(sf, t1, n1, color)
		if cap and r1 > 0.0001:
			var top: Vector3 = base + Vector3(0, height, 0)
			_push(sf, top, Vector3.UP, color)
			_push(sf, t1, Vector3.UP, color)
			_push(sf, t0, Vector3.UP, color)


## Эллипсоид со сглаженными нормалями.
func ball(center: Vector3, radii: Vector3, color: Color, seg: int = 10, rings: int = 6, surf: String = "main") -> void:
	var sf: Dictionary = _surf(surf)
	for r in rings:
		var p0: float = PI * float(r) / float(rings) - PI * 0.5
		var p1: float = PI * float(r + 1) / float(rings) - PI * 0.5
		for s in seg:
			var a0: float = TAU * float(s) / float(seg)
			var a1: float = TAU * float(s + 1) / float(seg)
			var v00: Vector3 = _sph(p0, a0)
			var v01: Vector3 = _sph(p0, a1)
			var v10: Vector3 = _sph(p1, a0)
			var v11: Vector3 = _sph(p1, a1)
			var pts: Array = [v00, v10, v11, v00, v11, v01]
			for q in pts:
				var v: Vector3 = q
				var n: Vector3 = Vector3(v.x / (radii.x * radii.x), v.y / (radii.y * radii.y), v.z / (radii.z * radii.z)).normalized()
				var col: Color = color
				if v.y < -0.3:
					col = _dark(color, lerpf(1.0, ao, clampf(-v.y * 1.2, 0.0, 1.0)))
				_push(sf, center + Vector3(v.x * radii.x, v.y * radii.y, v.z * radii.z), n, col)


func _sph(phi: float, theta: float) -> Vector3:
	return Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta))


## Двускатная крыша вдоль оси X: ширина (x), глубина (z), высота конька.
func gable(base: Vector3, width: float, depth: float, height: float, color: Color, overhang: float = 0.12, surf: String = "main") -> void:
	var sf: Dictionary = _surf(surf)
	var hw: float = width * 0.5 + overhang
	var hd: float = depth * 0.5 + overhang
	var lo: Color = _dark(color, ao)
	var a := base + Vector3(-hw, 0, -hd)
	var b := base + Vector3(-hw, 0, hd)
	var c := base + Vector3(hw, 0, hd)
	var d := base + Vector3(hw, 0, -hd)
	var r0 := base + Vector3(-hw, height, 0)
	var r1 := base + Vector3(hw, height, 0)
	var ins: Vector3 = base + Vector3(0, height * 0.3, 0)
	# скаты
	_tri(sf, b, c, r1, lo, lo, color, ins)
	_tri(sf, b, r1, r0, lo, color, color, ins)
	_tri(sf, d, a, r0, lo, lo, color, ins)
	_tri(sf, d, r0, r1, lo, color, color, ins)
	# фронтоны
	_tri(sf, a, b, r0, lo, lo, color, ins)
	_tri(sf, c, d, r1, lo, lo, color, ins)


## Четырёхскатная пирамида (шатёр).
func pyramid(base: Vector3, width: float, depth: float, height: float, color: Color, surf: String = "main") -> void:
	var sf: Dictionary = _surf(surf)
	var hw: float = width * 0.5
	var hd: float = depth * 0.5
	var lo: Color = _dark(color, ao)
	var a := base + Vector3(-hw, 0, -hd)
	var b := base + Vector3(-hw, 0, hd)
	var c := base + Vector3(hw, 0, hd)
	var d := base + Vector3(hw, 0, -hd)
	var top := base + Vector3(0, height, 0)
	var ins: Vector3 = base + Vector3(0, height * 0.3, 0)
	_tri(sf, b, c, top, lo, lo, color, ins)
	_tri(sf, c, d, top, lo, lo, color, ins)
	_tri(sf, d, a, top, lo, lo, color, ins)
	_tri(sf, a, b, top, lo, lo, color, ins)


## Плоский круг/диск (например циферблат): лежит в плоскости XY, смотрит в +Z.
func disc(center: Vector3, radius: float, color: Color, sides: int = 16, surf: String = "main") -> void:
	var sf: Dictionary = _surf(surf)
	for i in sides:
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		_push(sf, center, Vector3.BACK, color)
		_push(sf, center + Vector3(cos(a0), sin(a0), 0) * radius, Vector3.BACK, color)
		_push(sf, center + Vector3(cos(a1), sin(a1), 0) * radius, Vector3.BACK, color)


func build(extra_cull_both: bool = false) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var names: Array = _s.keys()
	names.sort() # "glow" < "main"
	for name in names:
		var sf: Dictionary = _s[name]
		if (sf.v as PackedVector3Array).is_empty():
			continue
		_fix_winding(sf)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = sf.v
		arrays[Mesh.ARRAY_NORMAL] = sf.n
		arrays[Mesh.ARRAY_COLOR] = sf.c
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(mesh.get_surface_count() - 1, name)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.glow() if name == "glow" else Mats.main())
	return mesh


## Godot считает лицевыми грани с обходом по часовой стрелке — выравниваем по нормалям.
func _fix_winding(sf: Dictionary) -> void:
	var v: PackedVector3Array = sf.v
	var n: PackedVector3Array = sf.n
	var c: PackedColorArray = sf.c
	var i: int = 0
	while i + 2 < v.size():
		var g: Vector3 = (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
		if g.dot(n[i] + n[i + 1] + n[i + 2]) > 0.0:
			var tv: Vector3 = v[i + 1]
			v[i + 1] = v[i + 2]
			v[i + 2] = tv
			var tn: Vector3 = n[i + 1]
			n[i + 1] = n[i + 2]
			n[i + 2] = tn
			var tc: Color = c[i + 1]
			c[i + 1] = c[i + 2]
			c[i + 2] = tc
		i += 3
	sf.v = v
	sf.n = n
	sf.c = c
