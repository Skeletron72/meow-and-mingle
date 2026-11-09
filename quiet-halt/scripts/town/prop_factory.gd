class_name PropFactory
extends RefCounted
## Строит 3D-модели объектов мира из примитивов (MeshKit). Меши кэшируются.

static var _cache: Dictionary = {}

const FOL: Color = Color(0.66, 0.66, 0.66, 0.5)
const BLOS: Color = Color(0.70, 0.70, 0.70, 0.25)
const WOOD: Color = Color(0.55, 0.38, 0.26, 1.0)
const WOOD_L: Color = Color(0.72, 0.55, 0.38, 1.0)
const STONE: Color = Color(0.70, 0.68, 0.66, 1.0)
const WARM: Color = Color(1.0, 0.82, 0.45, 1.0)

const HOUSE_WALLS: Array = [
	Color(0.97, 0.90, 0.76), Color(0.78, 0.88, 0.76), Color(0.96, 0.80, 0.70),
	Color(0.76, 0.86, 0.94), Color(0.92, 0.80, 0.88), Color(0.95, 0.88, 0.62),
]
const HOUSE_ROOFS: Array = [
	Color(0.78, 0.38, 0.30), Color(0.38, 0.52, 0.62), Color(0.55, 0.42, 0.62),
	Color(0.30, 0.55, 0.45), Color(0.82, 0.52, 0.28), Color(0.62, 0.34, 0.36),
]


static func _fol(shade: float = 1.0) -> Color:
	return Color(FOL.r * shade, FOL.g * shade, FOL.b * shade, FOL.a)


## Построить узел для объекта. cell — якорь, rot — поворот (×90°).
static func create(id: String, st: Dictionary, rot: int, cell: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "%s_%d_%d" % [id, cell.x, cell.y]
	var def: Dictionary = Data.object_def(id)
	var sz: Array = def.get("size", [1, 1])
	var corner: bool = id in ["rails", "bridge_rails"]
	var w: float = float(sz[0])
	var d: float = float(sz[1])
	if corner:
		root.position = Vector3(float(cell.x), 0, float(cell.y))
	else:
		var rw: float = w
		var rd: float = d
		if rot % 2 == 1:
			rw = d
			rd = w
		root.position = Vector3(float(cell.x) + rw * 0.5, 0, float(cell.y) + rd * 0.5)
	if id == "clock_face":
		root.position = Vector3(40.5, 0, 13.5)
	var variant: String = _variant(id, st)
	var key: String = id + "|" + variant
	if not _cache.has(key):
		_cache[key] = _build(id, st)
	var mesh: Mesh = _cache[key]
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "Mesh"
		if rot != 0 and not corner and id != "station":
			mi.rotation.y = float(rot) * PI * 0.5
		root.add_child(mi)
	_extras(root, id, st, rot)
	root.set_meta("obj_id", id)
	root.set_meta("cell", cell)
	return root


static func _variant(id: String, st: Dictionary) -> String:
	if id.begins_with("tree_") and st.has("fruit"):
		return str(int(st.get("fruit", 0)))
	if id == "house":
		return str(int(st.get("style", 0)) % 6)
	if id.begins_with("sapling_"):
		return str(mini(int(st.get("age", 0)), 3))
	return ""


static func _extras(root: Node3D, id: String, st: Dictionary, rot: int) -> void:
	match id:
		"lamp":
			var l := OmniLight3D.new()
			l.position = Vector3(0, 2.35, 0)
			l.omni_range = 7.0
			l.light_color = Color(1.0, 0.82, 0.55)
			l.light_energy = 0.0
			l.shadow_enabled = false
			l.set_script(load("res://scripts/town/night_light.gd"))
			root.add_child(l)
		"clock_face":
			var hands := Node3D.new()
			hands.set_script(load("res://scripts/town/clock_hands.gd"))
			root.add_child(hands)
		"fountain":
			var p := CPUParticles3D.new()
			p.position = Vector3(0, 1.55, 0)
			p.amount = 36
			p.lifetime = 1.1
			p.direction = Vector3(0, 1, 0)
			p.spread = 18.0
			p.initial_velocity_min = 2.6
			p.initial_velocity_max = 3.4
			p.gravity = Vector3(0, -9.0, 0)
			var sm := SphereMesh.new()
			sm.radius = 0.04
			sm.height = 0.08
			sm.radial_segments = 4
			sm.rings = 2
			sm.material = Mats.unlit(Color(0.75, 0.92, 1.0, 0.9))
			p.mesh = sm
			root.add_child(p)
		"station":
			pass


# =====================================================================

static func _build(id: String, st: Dictionary) -> Mesh:
	var k := MeshKit.new()
	match id:
		"tree_oak":
			_tree(k, 1.0, 0.0)
		"tree_apple":
			_tree(k, 0.9, 0.0)
			_fruit_balls(k, Color(0.88, 0.22, 0.20, 1.0), int(st.get("fruit", 0)), 1.0)
		"tree_pear":
			_tree(k, 0.95, 0.0)
			_fruit_balls(k, Color(0.80, 0.84, 0.28, 1.0), int(st.get("fruit", 0)), 1.0)
		"tree_cherry":
			_tree(k, 0.9, 1.0)
			_fruit_balls(k, Color(0.65, 0.08, 0.20, 1.0), int(st.get("fruit", 0)), 0.8)
		"tree_pine":
			_pine(k)
		"sapling_apple", "sapling_pear", "sapling_cherry":
			_sapling(k, int(st.get("age", 0)))
		"bush":
			k.ball(Vector3(0, 0.38, 0), Vector3(0.62, 0.42, 0.62), _fol(1.0), 8, 5)
			k.ball(Vector3(0.34, 0.3, 0.2), Vector3(0.4, 0.32, 0.4), _fol(0.92), 7, 4)
			k.ball(Vector3(-0.3, 0.28, -0.2), Vector3(0.38, 0.3, 0.38), _fol(1.05), 7, 4)
		"rock":
			k.ball(Vector3(0, 0.24, 0), Vector3(0.52, 0.36, 0.44), Color(0.62, 0.62, 0.64), 6, 4)
			k.ball(Vector3(0.38, 0.14, 0.2), Vector3(0.28, 0.2, 0.26), Color(0.70, 0.70, 0.72), 6, 3)
		"flower_tulip", "flower_cornflower", "flower_aster", "flower_hellebore":
			_flowers(k, id)
		"hole":
			k.cyl(Vector3(0, 0.005, 0), 0.38, 0.38, 0.02, Color(0.30, 0.20, 0.14), 8)
			k.ball(Vector3(0.45, 0.04, 0.1), Vector3(0.26, 0.1, 0.22), Color(0.48, 0.34, 0.24), 6, 3)
		"rails":
			_rails(k)
		"station":
			_station(k)
		"kiosk":
			_kiosk(k)
		"board":
			_board(k)
		"bench":
			_bench(k)
		"lamp":
			_lamp(k)
		"fountain":
			_fountain(k)
		"bridge_rails":
			_bridge_rails(k)
		"clock_face":
			_clock_face(k)
		"house":
			_house(k, int(st.get("style", 0)))
		"plot_sign":
			_plot_sign(k)
		"lot_boarded":
			_lot(k, false)
		"shop_flowers":
			_shop(k, 0)
		"cafe":
			_shop(k, 1)
		_:
			k.box(Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), Color(1, 0, 1))
	return k.build()


static func _tree(k: MeshKit, s: float, blossom: float) -> void:
	k.cyl(Vector3(0, 0, 0), 0.26 * s, 0.17 * s, 1.5 * s, WOOD, 7)
	var f1: Color = BLOS if blossom > 0.5 else _fol(1.0)
	var f2: Color = BLOS if blossom > 0.5 else _fol(0.94)
	var f3: Color = BLOS if blossom > 0.5 else _fol(1.08)
	k.ball(Vector3(0, 2.15 * s, 0), Vector3(1.3, 1.05, 1.3) * s, f1, 10, 6)
	k.ball(Vector3(0.65 * s, 1.85 * s, 0.3 * s), Vector3(0.85, 0.72, 0.85) * s, f2, 8, 5)
	k.ball(Vector3(-0.6 * s, 1.9 * s, -0.4 * s), Vector3(0.9, 0.76, 0.9) * s, f3, 8, 5)
	k.ball(Vector3(0.1 * s, 2.7 * s, -0.1 * s), Vector3(0.8, 0.6, 0.8) * s, f1, 8, 4)


static func _fruit_balls(k: MeshKit, col: Color, n: int, s: float) -> void:
	var pos: Array = [Vector3(0.9, 1.95, 0.5), Vector3(-0.8, 2.2, 0.7), Vector3(0.2, 1.7, -1.0), Vector3(-0.3, 2.9, 0.4), Vector3(0.7, 2.4, -0.6)]
	for i in mini(n + 0, 5):
		k.ball(pos[i] * 0.9, Vector3(0.14, 0.14, 0.14) * s, col, 6, 4)


static func _pine(k: MeshKit) -> void:
	var dark: Color = Color(0.26, 0.46, 0.34)
	k.cyl(Vector3(0, 0, 0), 0.2, 0.14, 0.8, Color(0.42, 0.30, 0.22), 6)
	k.cyl(Vector3(0, 0.5, 0), 1.25, 0.0, 1.5, dark, 8)
	k.cyl(Vector3(0, 1.4, 0), 0.98, 0.0, 1.35, Color(dark.r * 1.05, dark.g * 1.05, dark.b * 1.05), 8)
	k.cyl(Vector3(0, 2.25, 0), 0.7, 0.0, 1.2, Color(dark.r * 1.1, dark.g * 1.1, dark.b * 1.1), 8)


static func _sapling(k: MeshKit, age: int) -> void:
	var s: float = 0.5 + 0.18 * float(age)
	k.cyl(Vector3(0, 0, 0), 0.05 * s, 0.035 * s, 0.7 * s, WOOD, 5)
	k.ball(Vector3(0, 0.8 * s, 0), Vector3(0.36, 0.3, 0.36) * s, _fol(1.0), 6, 4)
	k.ball(Vector3(0.12 * s, 0.6 * s, 0.1 * s), Vector3(0.22, 0.18, 0.22) * s, _fol(1.1), 5, 3)


static func _flowers(k: MeshKit, id: String) -> void:
	var item_id: String = str(Data.object_def(id).get("item", "tulip"))
	var col_arr: Array = Data.item(item_id).get("color", [1, 0.5, 0.5])
	var col := Color(col_arr[0], col_arr[1], col_arr[2])
	var stem: Color = Color(0.40, 0.65, 0.30)
	var spots: Array = [Vector3(0, 0, 0), Vector3(0.22, 0, 0.12), Vector3(-0.18, 0, 0.2)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var hgt: float = 0.34 + 0.06 * float(i)
		k.cyl(p, 0.018, 0.012, hgt, stem, 4)
		match id:
			"flower_tulip":
				k.ball(p + Vector3(0, hgt + 0.05, 0), Vector3(0.09, 0.12, 0.09), col, 6, 4)
			"flower_cornflower":
				k.ball(p + Vector3(0, hgt + 0.03, 0), Vector3(0.1, 0.06, 0.1), col, 6, 3)
				k.ball(p + Vector3(0, hgt + 0.06, 0), Vector3(0.04, 0.04, 0.04), Color(0.2, 0.2, 0.5), 4, 3)
			"flower_aster":
				k.ball(p + Vector3(0, hgt + 0.03, 0), Vector3(0.12, 0.05, 0.12), col, 6, 3)
				k.ball(p + Vector3(0, hgt + 0.07, 0), Vector3(0.05, 0.04, 0.05), Color(0.98, 0.85, 0.3), 4, 3)
			_:
				k.ball(p + Vector3(0, hgt + 0.02, 0), Vector3(0.1, 0.08, 0.1), col, 6, 3)
				k.ball(p + Vector3(0, hgt + 0.04, 0), Vector3(0.04, 0.04, 0.04), Color(0.7, 0.85, 0.4), 4, 3)


# ---------- инфраструктура ----------

static func _rails(k: MeshKit) -> void:
	# локальные координаты: x = мировой x, z = мировой z - 6
	var steel: Color = Color(0.62, 0.64, 0.68)
	var sleeper: Color = Color(0.40, 0.30, 0.24)
	var x: float = 0.3
	while x < 80.0:
		k.box(Vector3(x, 0.05, 1.0), Vector3(0.22, 0.1, 1.5), sleeper)
		x += 0.62
	k.box(Vector3(40, 0.14, 0.55), Vector3(80, 0.08, 0.08), steel)
	k.box(Vector3(40, 0.14, 1.45), Vector3(80, 0.08, 0.08), steel)
	# жёлтая линия у края перрона (мировой z = 8.15)
	k.box(Vector3(41, 0.02, 2.2), Vector3(30, 0.03, 0.18), Color(0.98, 0.82, 0.25))


static func _house(k: MeshKit, style: int) -> void:
	var wall: Color = HOUSE_WALLS[style % HOUSE_WALLS.size()]
	var roof: Color = HOUSE_ROOFS[style % HOUSE_ROOFS.size()]
	k.box(Vector3(0, 0.85, 0), Vector3(2.5, 1.7, 2.3), wall)
	k.box(Vector3(0, 0.08, 0), Vector3(2.6, 0.16, 2.4), STONE)
	k.gable(Vector3(0, 1.7, 0), 2.5, 2.3, 1.15, roof, 0.18)
	k.box(Vector3(0.7, 2.7, -0.4), Vector3(0.36, 0.9, 0.36), Color(0.62, 0.45, 0.4))
	# дверь и окна (лицо — +z)
	k.box(Vector3(0, 0.6, 1.16), Vector3(0.6, 1.1, 0.08), Color(0.48, 0.30, 0.22))
	k.box(Vector3(0, 1.22, 1.16), Vector3(0.6, 0.12, 0.1), Color(0.48, 0.30, 0.22))
	k.box(Vector3(0.14, 0.58, 1.22), Vector3(0.08, 0.08, 0.04), WARM)
	k.box(Vector3(-0.85, 1.0, 1.17), Vector3(0.5, 0.5, 0.06), WARM, "glow")
	k.box(Vector3(0.85, 1.0, 1.17), Vector3(0.5, 0.5, 0.06), WARM, "glow")
	k.box(Vector3(-0.85, 1.0, 1.19), Vector3(0.56, 0.04, 0.04), WOOD_L)
	k.box(Vector3(0.85, 1.0, 1.19), Vector3(0.56, 0.04, 0.04), WOOD_L)
	k.box(Vector3(1.27, 1.0, 0.2), Vector3(0.06, 0.5, 0.5), WARM, "glow")
	# ступенька и цветочный ящик
	k.box(Vector3(0, 0.05, 1.45), Vector3(0.9, 0.1, 0.5), STONE)
	k.box(Vector3(-0.85, 0.65, 1.26), Vector3(0.55, 0.14, 0.16), WOOD)
	k.ball(Vector3(-0.85, 0.76, 1.26), Vector3(0.24, 0.1, 0.08), Color(0.95, 0.5, 0.6), 5, 3)


static func _lot(k: MeshKit, open: bool) -> void:
	var wall: Color = Color(0.74, 0.68, 0.62)
	k.box(Vector3(0, 1.15, 0), Vector3(3.5, 2.3, 3.3), wall)
	k.box(Vector3(0, 0.08, 0), Vector3(3.6, 0.16, 3.4), STONE)
	k.gable(Vector3(0, 2.3, 0), 3.5, 3.3, 1.2, Color(0.60, 0.52, 0.50), 0.2)
	k.box(Vector3(0, 0.8, 1.68), Vector3(0.9, 1.5, 0.08), Color(0.42, 0.32, 0.28))
	# заколоченные доски
	var plank: Color = Color(0.62, 0.50, 0.36)
	var xf0: Transform3D = k.xf
	k.xf = xf0 * Transform3D(Basis(Vector3.BACK, 0.5), Vector3(0, 0.8, 1.74))
	k.box(Vector3.ZERO, Vector3(1.3, 0.16, 0.05), plank)
	k.xf = xf0 * Transform3D(Basis(Vector3.BACK, -0.5), Vector3(0, 0.8, 1.76))
	k.box(Vector3.ZERO, Vector3(1.3, 0.16, 0.05), plank)
	k.xf = xf0
	k.box(Vector3(-1.1, 1.3, 1.68), Vector3(0.7, 0.7, 0.06), Color(0.30, 0.28, 0.3))
	k.box(Vector3(1.1, 1.3, 1.68), Vector3(0.7, 0.7, 0.06), Color(0.30, 0.28, 0.3))
	# табличка «Сдаётся»
	k.cyl(Vector3(1.55, 0, 2.05), 0.04, 0.04, 0.8, WOOD, 4)
	k.box(Vector3(1.55, 0.9, 2.05), Vector3(0.6, 0.36, 0.05), Color(0.95, 0.80, 0.30))


static func _shop(k: MeshKit, kind: int) -> void:
	var wall: Color = Color(0.98, 0.90, 0.88) if kind == 0 else Color(0.97, 0.86, 0.68)
	var roof: Color = Color(0.82, 0.45, 0.52) if kind == 0 else Color(0.62, 0.36, 0.28)
	var stripe: Color = Color(0.95, 0.55, 0.65) if kind == 0 else Color(0.95, 0.62, 0.25)
	k.box(Vector3(0, 1.15, 0), Vector3(3.5, 2.3, 3.3), wall)
	k.box(Vector3(0, 0.08, 0), Vector3(3.6, 0.16, 3.4), STONE)
	k.gable(Vector3(0, 2.3, 0), 3.5, 3.3, 1.2, roof, 0.2)
	k.box(Vector3(1.0, 3.4, -0.6), Vector3(0.4, 1.0, 0.4), Color(0.62, 0.45, 0.4))
	# витрина и дверь
	k.box(Vector3(-0.85, 0.95, 1.68), Vector3(1.3, 1.1, 0.06), WARM, "glow")
	k.box(Vector3(-0.85, 1.55, 1.7), Vector3(1.4, 0.08, 0.06), WOOD_L)
	k.box(Vector3(-0.85, 0.4, 1.7), Vector3(1.4, 0.08, 0.06), WOOD_L)
	k.box(Vector3(0.95, 0.8, 1.68), Vector3(0.8, 1.5, 0.08), Color(0.48, 0.30, 0.22))
	k.box(Vector3(0.95, 1.2, 1.74), Vector3(0.4, 0.4, 0.04), WARM, "glow")
	# полосатый навес
	for i in 8:
		var cx: float = -1.7 + 0.43 * float(i)
		var col: Color = stripe if i % 2 == 0 else Color(0.99, 0.96, 0.92)
		var xf0: Transform3D = k.xf
		k.xf = xf0 * Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(cx + 0.2, 1.95, 2.15))
		k.box(Vector3.ZERO, Vector3(0.43, 0.06, 1.0), col)
		k.xf = xf0
	# вывеска
	k.box(Vector3(0, 2.55, 1.72), Vector3(1.6, 0.36, 0.08), WOOD)
	k.box(Vector3(0, 2.55, 1.77), Vector3(1.4, 0.22, 0.04), stripe)
	if kind == 0:
		# цветочные ящики с цветами
		for i in 3:
			var fx: float = -1.4 + 0.5 * float(i)
			k.box(Vector3(fx, 0.18, 2.35), Vector3(0.42, 0.28, 0.3), WOOD)
			k.ball(Vector3(fx, 0.42, 2.35), Vector3(0.2, 0.18, 0.16), [Color(0.95, 0.45, 0.55), Color(0.55, 0.6, 0.98), Color(0.98, 0.85, 0.3)][i], 6, 4)
	else:
		# столик и зонт
		k.cyl(Vector3(-1.2, 0, 2.55), 0.04, 0.04, 0.7, WOOD, 5)
		k.cyl(Vector3(-1.2, 0.7, 2.55), 0.4, 0.4, 0.05, Color(0.95, 0.9, 0.8), 8)
		k.cyl(Vector3(1.6, 0, 2.5), 0.03, 0.03, 1.5, WOOD, 4)
		k.cyl(Vector3(1.6, 1.5, 2.5), 0.7, 0.0, 0.35, stripe, 8)


static func _plot_sign(k: MeshKit) -> void:
	k.cyl(Vector3(0, 0, 0), 0.05, 0.05, 1.1, WOOD, 5)
	k.box(Vector3(0, 0.95, 0), Vector3(0.7, 0.4, 0.06), Color(0.95, 0.88, 0.62))
	k.box(Vector3(0, 0.95, 0.04), Vector3(0.5, 0.06, 0.02), Color(0.5, 0.35, 0.25))
	k.box(Vector3(0, 0.82, 0.04), Vector3(0.4, 0.04, 0.02), Color(0.5, 0.35, 0.25))


static func _station(k: MeshKit) -> void:
	var wall: Color = Color(0.96, 0.88, 0.74)
	var trim: Color = Color(0.45, 0.32, 0.30)
	var roof: Color = Color(0.40, 0.50, 0.60)
	k.box(Vector3(0, 0.08, 0), Vector3(8.8, 0.16, 4.7), STONE)
	k.box(Vector3(0, 1.3, 0), Vector3(8.2, 2.5, 3.6), wall)
	# боковые крылья — крыши
	k.gable(Vector3(-2.7, 2.55, 0), 3.4, 3.6, 1.1, roof, 0.2)
	k.gable(Vector3(2.7, 2.55, 0), 3.4, 3.6, 1.1, roof, 0.2)
	# башня с часами
	k.box(Vector3(0, 2.55, 0), Vector3(2.1, 5.1, 2.3), Color(0.94, 0.85, 0.70))
	k.box(Vector3(0, 5.15, 0), Vector3(2.3, 0.18, 2.5), trim)
	k.pyramid(Vector3(0, 5.2, 0), 2.4, 2.6, 1.6, Color(0.42, 0.52, 0.62))
	k.cyl(Vector3(0, 6.7, 0), 0.04, 0.04, 0.6, trim, 4)
	# «мёртвые» циферблаты (до починки) на обеих сторонах
	for side in [-1.0, 1.0]:
		var xf0: Transform3D = k.xf
		if side < 0:
			k.xf = xf0 * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		k.disc(Vector3(0, 3.9, 1.17), 0.62, Color(0.62, 0.60, 0.58))
		k.disc(Vector3(0, 3.9, 1.18), 0.5, Color(0.84, 0.82, 0.78))
		k.box(Vector3(0.1, 3.95, 1.19), Vector3(0.28, 0.05, 0.02), Color(0.35, 0.33, 0.33))
		k.box(Vector3(-0.03, 3.85, 1.19), Vector3(0.05, 0.24, 0.02), Color(0.35, 0.33, 0.33))
		k.xf = xf0
	# окна и двери — обе стороны
	for side in [-1.0, 1.0]:
		var zf: float = 1.82 * side
		for wx in [-3.3, -2.2, 2.2, 3.3]:
			k.box(Vector3(wx, 1.35, zf), Vector3(0.72, 0.95, 0.06), WARM, "glow")
			k.box(Vector3(wx, 1.9, zf + 0.02 * side), Vector3(0.84, 0.08, 0.06), trim)
			k.box(Vector3(wx, 0.86, zf + 0.02 * side), Vector3(0.84, 0.08, 0.06), trim)
		k.box(Vector3(0, 0.95, zf + 0.02 * side), Vector3(1.0, 1.6, 0.08), Color(0.46, 0.30, 0.24))
		k.box(Vector3(0, 1.9, zf + 0.03 * side), Vector3(1.2, 0.14, 0.1), trim)
	# навес над перроном (север, z<0)
	var xf1: Transform3D = k.xf
	k.xf = xf1 * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 2.6, -2.45))
	k.box(Vector3.ZERO, Vector3(8.6, 0.12, 1.6), Color(0.52, 0.42, 0.40))
	k.xf = xf1
	for px in [-4.0, -2.0, 2.0, 4.0]:
		k.cyl(Vector3(px, 0.0, -3.1), 0.07, 0.07, 2.45, trim, 5)
	# скамейка и ящики у стены — для уюта
	k.box(Vector3(3.6, 0.3, 2.15), Vector3(1.0, 0.6, 0.5), WOOD)
	k.box(Vector3(-3.7, 0.3, 2.1), Vector3(0.7, 0.6, 0.6), WOOD_L)
	k.box(Vector3(-3.6, 0.8, 2.1), Vector3(0.5, 0.4, 0.5), Color(0.8, 0.6, 0.4))


static func _kiosk(k: MeshKit) -> void:
	k.box(Vector3(0, 0.55, 0), Vector3(1.8, 1.1, 0.8), Color(0.88, 0.70, 0.45))
	k.box(Vector3(0, 1.15, 0.12), Vector3(1.95, 0.1, 1.0), WOOD)
	for i in 6:
		var cx: float = -0.85 + 0.34 * float(i)
		var col: Color = Color(0.30, 0.58, 0.60) if i % 2 == 0 else Color(0.99, 0.96, 0.92)
		var xf0: Transform3D = k.xf
		k.xf = xf0 * Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(cx + 0.1, 1.9, 0.38))
		k.box(Vector3.ZERO, Vector3(0.34, 0.05, 0.95), col)
		k.xf = xf0
	k.cyl(Vector3(-0.9, 0, 0.45), 0.04, 0.04, 1.85, WOOD, 4)
	k.cyl(Vector3(0.9, 0, 0.45), 0.04, 0.04, 1.85, WOOD, 4)
	k.box(Vector3(0.4, 1.28, 0.2), Vector3(0.3, 0.16, 0.3), Color(0.9, 0.35, 0.3))
	k.ball(Vector3(-0.4, 1.3, 0.2), Vector3(0.14, 0.14, 0.14), Color(0.85, 0.25, 0.22), 6, 4)
	k.box(Vector3(0, 2.1, 0.35), Vector3(0.9, 0.3, 0.06), Color(0.99, 0.96, 0.92))
	k.box(Vector3(0, 2.1, 0.39), Vector3(0.7, 0.14, 0.03), Color(0.30, 0.58, 0.60))


static func _board(k: MeshKit) -> void:
	k.cyl(Vector3(-0.8, 0, 0), 0.07, 0.07, 1.9, WOOD, 5)
	k.cyl(Vector3(0.8, 0, 0), 0.07, 0.07, 1.9, WOOD, 5)
	k.box(Vector3(0, 1.3, 0), Vector3(1.9, 1.1, 0.08), Color(0.62, 0.45, 0.30))
	k.box(Vector3(0, 1.3, 0.05), Vector3(1.7, 0.9, 0.03), Color(0.85, 0.72, 0.52))
	var notes: Array = [Color(0.98, 0.95, 0.85), Color(0.95, 0.80, 0.80), Color(0.82, 0.92, 0.95), Color(0.98, 0.92, 0.6)]
	for i in 4:
		k.box(Vector3(-0.6 + 0.4 * float(i), 1.35 + 0.08 * float(i % 2), 0.08), Vector3(0.3, 0.38, 0.015), notes[i])
	k.box(Vector3(0, 1.95, 0), Vector3(2.1, 0.1, 0.4), Color(0.50, 0.35, 0.28))
	k.gable(Vector3(0, 1.98, 0), 2.1, 0.4, 0.3, Color(0.70, 0.40, 0.32), 0.05)


static func _bench(k: MeshKit) -> void:
	k.box(Vector3(0, 0.48, 0), Vector3(1.8, 0.1, 0.5), WOOD_L)
	k.box(Vector3(0, 0.85, -0.22), Vector3(1.8, 0.4, 0.07), WOOD_L)
	for x in [-0.75, 0.75]:
		k.box(Vector3(x, 0.24, 0), Vector3(0.1, 0.48, 0.44), Color(0.32, 0.30, 0.34))
		k.box(Vector3(x, 0.7, -0.22), Vector3(0.1, 0.5, 0.08), Color(0.32, 0.30, 0.34))


static func _lamp(k: MeshKit) -> void:
	var iron: Color = Color(0.26, 0.27, 0.32)
	k.cyl(Vector3(0, 0, 0), 0.16, 0.12, 0.2, iron, 6)
	k.cyl(Vector3(0, 0.2, 0), 0.06, 0.05, 1.9, iron, 6)
	k.box(Vector3(0, 2.2, 0), Vector3(0.36, 0.4, 0.36), Color(1.0, 0.9, 0.65), "glow")
	k.box(Vector3(0, 2.46, 0), Vector3(0.5, 0.08, 0.5), iron)
	k.pyramid(Vector3(0, 2.5, 0), 0.5, 0.5, 0.25, iron)


static func _fountain(k: MeshKit) -> void:
	k.cyl(Vector3(0, 0, 0), 1.45, 1.45, 0.55, STONE, 14)
	k.cyl(Vector3(0, 0.5, 0), 1.25, 1.25, 0.04, Color(0.45, 0.78, 0.88), 14)
	k.cyl(Vector3(0, 0.5, 0), 0.22, 0.18, 0.9, STONE, 8)
	k.cyl(Vector3(0, 1.3, 0), 0.7, 0.28, 0.2, STONE, 10)
	k.cyl(Vector3(0, 1.48, 0), 0.6, 0.6, 0.04, Color(0.45, 0.78, 0.88), 10)
	k.ball(Vector3(0, 1.58, 0), Vector3(0.15, 0.15, 0.15), STONE, 6, 4)


static func _bridge_rails(k: MeshKit) -> void:
	# локально: x = мировой x - 38, z = мировой z - 32; мост 5×4 клеток
	var wood: Color = Color(0.62, 0.44, 0.30)
	for xr in [0.1, 4.9]:
		for i in 5:
			k.cyl(Vector3(xr, 0, 0.3 + 0.85 * float(i)), 0.06, 0.06, 0.85, wood, 5)
		k.box(Vector3(xr, 0.82, 2.0), Vector3(0.1, 0.08, 4.0), WOOD_L)
		k.box(Vector3(xr, 0.5, 2.0), Vector3(0.06, 0.05, 4.0), WOOD_L)
	# планки настила — поперечные полоски поверх земли
	for i in 8:
		k.box(Vector3(2.5, 0.01, 0.25 + 0.5 * float(i)), Vector3(4.8, 0.03, 0.04), Color(0.45, 0.30, 0.20))


static func _clock_face(k: MeshKit) -> void:
	# яркие золотые циферблаты поверх «мёртвых»
	for side in [-1.0, 1.0]:
		var xf0: Transform3D = k.xf
		if side < 0:
			k.xf = xf0 * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		k.disc(Vector3(0, 3.9, 1.2), 0.64, Color(0.92, 0.72, 0.30))
		k.disc(Vector3(0, 3.9, 1.21), 0.52, Color(0.99, 0.96, 0.88))
		for i in 12:
			var a: float = TAU * float(i) / 12.0
			k.box(Vector3(sin(a) * 0.44, 3.9 + cos(a) * 0.44, 1.22), Vector3(0.04, 0.07, 0.01), Color(0.3, 0.25, 0.25))
		k.xf = xf0
