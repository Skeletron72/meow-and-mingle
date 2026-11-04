extends Node2D
## Игра: улица с кафе. Игра начинается внутри кафе: можно ходить по залу, встать у стойки и отработать смену
## (готовка идёт поверх города, без смены сцены), выйти на улицу и вернуться.
##
## Всё бесшовно: у кота один узел и один мир. Дверей нет — из проёма входа сразу тротуар, путь с улицы в зал
## и обратно строится обычным поиском пути (WorldNav). Кафе — «рентген»: как только кот заходит в здание, вокруг него
## расходится пиксельный круг (диафрагма) и вырезает фасад, открывая интерьер; вышел — круг сжимается, видно здание.
## Мебель и гости внутри обрезаются тем же кругом (шейдеры assets/shaders). Так же заходят и выходят гуляющие коты.
##
## Улица (земля тайлами, здания, предметы, зоны ходьбы, полосы машин, место интерьера) лежит в scenes/street.tscn —
## её правят в редакторе. Слои мира: Ground, Room (интерьер: пол, стена, коврики — лежит под фасадом, виден через дыру),
## Buildings, Actors (всё, что сортируется по y: мебель, коты, машины, предметы), Glow (свечение: окна, фонари, фары —
## не затемняется ночью). Небо — отдельный слой под миром.

const STREET_SCENE := "res://scenes/street.tscn"
const SPACE_CAFE := 0
const SPACE_UP := 2   # второй этаж — верхняя часть самого фасада; служебка — часть зала (CafeRoom)
## Второй этаж берётся из спрайта дома: крыша (верх 69 px арта) и стена со вторым рядом окон до карниза (до 116) — это 224 px мира,
## то есть 3 клетки стены и 4 клетки пола; нижняя часть фасада (навес и витрина) принадлежит первому этажу и остаётся целой.
const UPPER_SIZE := Vector2(320, 224)
const PX := 2
const T := 32
const WAITER_DEF := {"sprite": "cat-waiter-front.png", "tint": "#ffffff"}
const DEPTH_ZONE := 44.0   # на сколько пикселей вглубь здания считается «внутри»
const IRIS_OPEN_SPEED := 620.0    # px/с: круг расходится
const IRIS_CLOSE_SPEED := 900.0   # px/с: круг сжимается
const HOLE_SHADER := preload("res://assets/shaders/xray_hole.gdshader")
const CLIP_SHADER := preload("res://assets/shaders/xray_clip.gdshader")
const SHADOW_SHADER := preload("res://assets/shaders/dither_shadow.gdshader")
const SKY_SHADER := preload("res://assets/shaders/sky_gradient.gdshader")
const GROUND_WEATHER_SHADER := preload("res://assets/shaders/weather_ground.gdshader")
const PROP_WEATHER_SHADER := preload("res://assets/shaders/weather_prop.gdshader")
const ROOF_FRAC := {"building1": 0.27, "building2": 0.40, "building3": 0.30, "building4": 0.42, "building7": 0.25}   # какая часть спрайта — крыша
const SHOP_PER_PAGE := 4   # карточек улучшений на странице магазина (и уровней в выборе смены)
const CARD_H := 84.0        # свободно 74 px (контур 2 сверху, 8 снизу): две строки шрифта 56 + по 9 воздуха
const CARD_GAP := 4.0
const PRICE_W := 88.0   # кнопка цены в карточке: монета и до 3 цифр
const CAMERA_FEET_OFFSET := 90.0   # лапки кота на улице — ниже центра экрана на столько

var _level: StreetLevel
var _world_size := Vector2(1440, 640)
var _world: Node2D
var _ground: Node2D
var _buildings: Node2D
var _room: CafeRoom
var _actors: Node2D
var _glow: Node2D
var _camera: Camera2D
var _sky_layer: CanvasLayer
var _sky: CitySky
var _sky_bg: ColorRect
var _nav: WorldNav
var _cafe: StreetBuilding
var _building_nodes: Array[StreetBuilding] = []
var _interior_rect := Rect2()           # габарит интерьера в мире
var _iris_r := 0.0                      # радиус пиксельного круга рентгена, px (0 — фасад целый)
var _iris_max := 1.0                    # радиус, при котором круг накрывает весь интерьер
var _xray := 0.0                        # _iris_r / _iris_max: 0 — закрыт, 1 — интерьер раскрыт целиком
var _hole_mat: ShaderMaterial           # вырез в фасаде кафе
var _clip_mat: ShaderMaterial           # обрезка мебели и гостей внутри здания
var _player: CatWalker
var _npcs: Array[Dictionary] = []       # {"cat": CatWalker, "timer": float}
var _traffic: Traffic
var _glows: Array[Dictionary] = []      # {"node", "base", "cafe"}: свечение, зависящее от ночи
var _shadow_mats: Array[ShaderMaterial] = []   # косые тени зданий на тротуаре (длина и наклон — от солнца)
var _cafe_overlays: Array[CanvasItem] = []     # затенение фасада кафе (гаснет, когда фасад вырезан)
var _add_mat: CanvasItemMaterial
var _ground_mat: ShaderMaterial           # снег и лужи на земле
var _prop_mats: Dictionary = {}            # режим → материал снега для зданий (1), деревьев (2) и предметов (0)
var _weather_fx: WeatherFx
var _snow: SnowField                       # снегопад частицами в мире
var _door: AutoDoor                        # раздвижная дверь кафе
var _glass: Array[WindowGlass] = []        # стёкла окон фасадов
var _door_beam: Sprite2D                   # свет из открытой двери на тротуар
var _lit := 0.0                            # насколько горит искусственный свет (ночь, пасмурно)
var _space := SPACE_CAFE                   # где сейчас кот: зал кафе, коморка или жилая зона (все стоят в одном месте здания)
var _spaces: Dictionary = {}               # SPACE_UP → InteriorSpace (жилая зона)
var _pending_portal: Dictionary = {}       # дверь или лестница, к которой кот идёт
var _fade: ColorRect                       # затемнение (сон)
var _upper_rect := Rect2()                 # габарит второго этажа в мире
var _clip_mat_up: ShaderMaterial           # обрезка мебели второго этажа
var _floor_nav := FloorNav.new()           # сетка ходьбы второго этажа
var _fading := false
var _pending := ""                      # действие по прибытии: "shift"
var _pressing := false
var _last_cell := Vector2i(-1, -1)

var _ui: CanvasLayer
var _coins_label: Label
var _clock_btn: Button
var _btn_shift: Button
var _menu: CanvasLayer
var _menu_pages: Dictionary = {}
var _shop_page: Control
var _weather_btn: Button
var _shop_idx := 0
var _levels_idx := 0
var _account_stats: Label
var _shift_layer: CanvasLayer
var _levels_layer: CanvasLayer             # выбор уровня-смены
var _lang_btn: Button
var _music_btn: Button
var _sfx_btn: Button
var _quality_btn: Button
var _privacy_btn: Button
var _credits_text: Label
var _credits_idx := 0
var _diary_page: Control
var _intro: Intro                       # интро (ставни и расчистка), пока intro_stage < 5
var _repair_card: RepairCard
var _door_wanted := false
var _star_btn: Button
var _story_playing := false
var _badge: ColorRect
var _popup_queue: Array[Callable] = []
var _popup_busy := false
var _repair_board: RepairBoard


func _ready() -> void:
	if GameState.intro_stage == 0:   # новая игра начинается с комикса
		Nav.go(self, Nav.COMIC)
		return
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_hole_mat = ShaderMaterial.new()
	_hole_mat.shader = HOLE_SHADER
	_clip_mat = ShaderMaterial.new()
	_clip_mat.shader = CLIP_SHADER
	_clip_mat_up = ShaderMaterial.new()
	_clip_mat_up.shader = CLIP_SHADER
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GROUND_WEATHER_SHADER
	for mode in [0, 1, 2]:
		var pm := ShaderMaterial.new()
		pm.shader = PROP_WEATHER_SHADER
		pm.set_shader_parameter("mode", mode)
		_prop_mats[mode] = pm
	_build_sky()
	_build_world()
	_build_shading()
	_build_cats()
	_apply_clip_materials()
	_set_space(SPACE_CAFE, Vector2i(-1, -1))
	_build_camera()
	_weather_fx = WeatherFx.new()
	add_child(_weather_fx)
	_snow = SnowField.new()
	_snow.camera = _camera
	_world.add_child(_snow)
	_build_ui()
	if OS.is_debug_build():
		add_child(PerfOverlay.new())   # F2
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	Audio.music("city")
	_start_session_popups.call_deferred()
	_build_fade()
	_build_menu()
	_start_intro_if_needed()
	_update_xray(10.0)
	_apply_daylight()


# ---------------------------------------------------------------- построение

func _build_sky() -> void:
	_sky_layer = CanvasLayer.new()
	_sky_layer.layer = -10
	add_child(_sky_layer)
	_sky_bg = ColorRect.new()   # градиент неба: шейдер со ступенями и дизерингом
	_sky_bg.size = Vector2(360, 640)
	_sky_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	_sky_bg.material = sky_mat
	_sky_layer.add_child(_sky_bg)
	_sky = CitySky.new()
	_sky_layer.add_child(_sky)


## Собирает мир из уровня scenes/street.tscn: здания и предметы переезжают в свои слои, зоны остаются в _level.
func _build_world() -> void:
	_level = (load(STREET_SCENE) as PackedScene).instantiate() as StreetLevel
	_world_size = _level.world_size
	_world = Node2D.new()
	add_child(_world)
	_ground = Node2D.new()
	_world.add_child(_ground)
	_room = CafeRoom.new()
	_world.add_child(_room)      # интерьер под фасадом: виден только через дыру рентгена
	_buildings = Node2D.new()
	_world.add_child(_buildings)
	_actors = Node2D.new()
	_actors.y_sort_enabled = true
	_world.add_child(_actors)
	_glow = Node2D.new()
	_world.add_child(_glow)
	add_child(_level)
	_level.visible = false   # зоны не рисуются (F3 включает показ)
	_level.z_index = 100
	var ground := _level.get_node_or_null("Ground")   # земля — тайлы из сцены улицы
	if ground != null:
		ground.reparent(_ground)
		(ground as CanvasItem).material = _ground_mat

	for node in _level.get_node("Buildings").get_children():
		var b := node as StreetBuilding
		if b == null:
			continue
		b.reparent(_buildings)
		_building_nodes.append(b)
		_add_window_glows(b)
		if b.is_cafe:
			_cafe = b
			_cafe.material = _hole_mat
		else:   # снег на крышу: у каждого дома своя доля высоты
			var rm := ShaderMaterial.new()
			rm.shader = PROP_WEATHER_SHADER
			rm.set_shader_parameter("mode", 1)
			rm.set_shader_parameter("roof_frac", float(ROOF_FRAC.get(b.building_id(), 0.3)))
			b.material = rm

	_build_storefront()
	var interior := _level.zones(StreetZone.Kind.CAFE_INTERIOR)
	var at := (interior[0] as StreetZone).global_position if not interior.is_empty() else Vector2(256, 64)
	# пол кафе обязан лечь в сетку мира: иначе клетки зала и тротуара не совпадут
	_room.position = Vector2(snappedf(at.x, T), snappedf(at.y + CafeRoom.ORIGIN.y, T) - CafeRoom.ORIGIN.y)
	_interior_rect = Rect2(_room.position, CafeRoom.ROOM_SIZE)
	_room.external_actors = _actors
	_room.set_layout(GameState.layout)
	_build_spaces()

	var block_cells: Array[Vector2i] = []
	for node in _level.get_node("Props").get_children():
		var prop := node as StreetProp
		if prop == null:
			continue
		prop.reparent(_actors)
		var pid := prop.texture.resource_path.get_file()
		prop.material = _prop_mats[2] if (pid.begins_with("tree") or pid.begins_with("bush") or pid.begins_with("plant")) else _prop_mats[0]
		var wa := prop.texture.get_width()   # контактная тень под предметом
		var blob := PixelArt.sprite(PixelArt.blob(maxi(5, wa / 2 + 2), maxi(3, wa / 6 + 1)), Vector2.ZERO)
		blob.scale = Vector2.ONE            # родитель уже в масштабе 2
		blob.modulate = Color(1, 1, 1, 0.55)
		blob.show_behind_parent = true
		prop.add_child(blob)
		if prop.blocks:
			block_cells.append(prop.blocked_cell())
		if prop.emits_light:
			var head: Vector2 = prop.global_position + Vector2(0, -prop.texture.get_height() * PX + 14.0)
			_add_halo(head, 2.6, 0.75, Color(1.0, 0.8, 0.45))
			_add_halo(prop.global_position + Vector2(0, -8.0), 3.2, 0.35, Color(1.0, 0.8, 0.45), 0.35)

	var walk: Array[Rect2] = []
	for z in _level.zones(StreetZone.Kind.WALK):
		walk.append(z.world_rect())
	var blocks: Array[Rect2] = []
	for z in _level.zones(StreetZone.Kind.BLOCK):
		blocks.append(z.world_rect())
	_nav = WorldNav.new()
	_nav.build(_world_size, walk, blocks, block_cells, _room)

	var lanes: Array = []
	for z in _level.zones(StreetZone.Kind.LANE_EAST):
		lanes.append({"rect": z.world_rect(), "dir": 1})
	for z in _level.zones(StreetZone.Kind.LANE_WEST):
		lanes.append({"rect": z.world_rect(), "dir": -1})
	_traffic = Traffic.new()
	add_child(_traffic)
	_traffic.setup(_actors, Data.street["vehicles"], lanes)
	_traffic.car_spawned.connect(_on_car_spawned)
	_traffic.car_removed.connect(_on_car_removed)
	_traffic.seed_cars(3)

	# чашка над стойкой: здесь начинается смена
	var cup := Sprite2D.new()
	cup.texture = Ui.atlas(preload("res://assets/cafe/drinks-and-pastries.png"), Rect2(32, 16, 16, 16))
	cup.position = Vector2(48, 28)
	cup.scale = Vector2(PX, PX)
	_room.add_child(cup)
	var t := create_tween().set_loops()
	t.tween_property(cup, "position:y", 20.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(cup, "position:y", 28.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Второй этаж — верхняя часть того же дома (у спрайта кафе уже есть второй этаж: крыша и стена с окнами над навесом).
## Его комната занимает верх фасада (3 клетки стены + 4 клетки пола), нижняя часть фасада остаётся целой. Поднявшись по лестнице,
## кот попадает туда без перехода в другое место: круг рентгена вырезает верх фасада, у кота своя сетка ходьбы (FloorNav),
## гости первого этажа остаются внизу.
func _build_spaces() -> void:
	_upper_rect = Rect2(_room.position, UPPER_SIZE)
	var sp := InteriorSpace.new()
	sp.position = _room.position
	_world.add_child(sp)
	_world.move_child(sp, _room.get_index() + 1)   # над залом, под фасадом
	sp.setup(InteriorSpace.Kind.UP, _actors)
	_spaces[SPACE_UP] = sp
	_floor_nav.setup(_room.position + InteriorSpace.ORIGIN, sp.walk_mask())
	_room.refresh_staff()
	_refresh_upper()


## Второй этаж доступен, когда куплен: комната и мебель наверху видны только через вырез в фасаде.
func _refresh_upper() -> void:
	(_spaces[SPACE_UP] as InteriorSpace).set_active(GameState.has_upgrade("upstairs"))


## Витрина кафе: боковые окна прозрачны (сквозь них виден зал), в проёме — раздвижная стеклянная дверь.
## Прямоугольники берутся из data/street.json (окна здания): нижние три — левое окно, дверь, правое окно.
func _build_storefront() -> void:
	if _cafe == null:
		return
	var wins: Array = Data.street["buildings"][_cafe.building_id()]["windows"]
	var origin := _cafe.world_rect().position
	var rects: Array[Vector4] = []
	for i in [2, 3, 4]:
		var w: Array = wins[i]
		rects.append(Vector4(origin.x + float(w[0]) * PX, origin.y + float(w[1]) * PX, float(w[2]) * PX, float(w[3]) * PX))
	for m in [_hole_mat, _clip_mat]:
		(m as ShaderMaterial).set_shader_parameter("glass0", rects[0])
		(m as ShaderMaterial).set_shader_parameter("glass1", rects[2])
		(m as ShaderMaterial).set_shader_parameter("door", rects[1])
	# вывеска: на серой доске фасада (art x 33..136, y 101..108) — название кафе
	var sign_sprite := Sprite2D.new()
	sign_sprite.texture = PixelArt.sign_texture("ТЁПЛАЯ ЛАПКА")
	sign_sprite.centered = false
	sign_sprite.position = Vector2(33, 101 - _cafe.texture.get_height())   # в пикселях арта: родитель масштаба 2, низ спрайта — начало координат
	_cafe.add_child(sign_sprite)
	_cafe_overlays.append(sign_sprite)
	# свет из кафе на улицу: широкое тёплое пятно перед витриной и луч из двери (когда она открыта)
	var base := _cafe.world_rect()
	var spill := Fx.pixel_light(Vector2(base.position.x + base.size.x / 2.0, base.end.y + 64.0), Vector2(base.size.x + 140.0, 190.0), Color(1.0, 0.78, 0.42, 0.0))
	_glow.add_child(spill)
	_glows.append({"node": spill, "base": 0.5, "cafe": false, "street": true})
	_door_beam = Sprite2D.new()
	_door_beam.texture = PixelArt.cone(44, 18)
	_door_beam.rotation = PI / 2.0   # конус идёт вниз от двери
	_door_beam.scale = Vector2(2, 2)
	_door_beam.position = Vector2(rects[1].x + rects[1].z / 2.0, rects[1].y + rects[1].w + 44.0)
	_door_beam.modulate = Color(1.0, 0.85, 0.5, 0.0)
	_door_beam.material = _add_mat
	_glow.add_child(_door_beam)
	var d: Array = wins[3]
	_door = AutoDoor.new()
	_buildings.add_child(_door)
	_door.setup(_cafe.texture, Rect2i(int(d[0]), int(d[1]), int(d[2]), int(d[3])), Vector2(rects[1].x, rects[1].y))


## Двери открываются, когда рядом кот (и закрыты, пока проём заперт ставнями).
func _update_door() -> void:
	if _door == null:
		return
	var open := false
	if _nav.is_entrance_open():
		var c := _door.rect.get_center()
		var cats: Array[Node2D] = []
		if _space == SPACE_CAFE:   # наверху кот дверь не открывает
			cats.append(_player)
		for n in _npcs:
			cats.append(n["cat"])
		for cat in cats:
			var dy := cat.position.y - _door.rect.end.y
			if absf(cat.position.x - c.x) < 64.0 and dy > -110.0 and dy < 96.0:
				open = true
				break
	if open != _door_wanted:
		_door_wanted = open
		if open and _door.open_amount < 0.2:
			Audio.sfx("bell", 0.0, -6.0)   # колокольчик над дверью, когда кто-то подошёл
	_door.set_open(open)
	if _door_beam != null:
		_door_beam.modulate.a = _door.open_amount * _lit * 0.7 * (1.0 - (_xray if _space == SPACE_CAFE else 0.0))


## Свет в окнах фасада ночью: часть окон горит, у кафе — все витрины.
func _add_window_glows(b: StreetBuilding) -> void:
	var id := b.building_id()
	if not Data.street["buildings"].has(id):
		return
	var wins: Array = Data.street["buildings"][id]["windows"]
	var origin := b.world_rect().position
	for i in wins.size():
		var w: Array = wins[i]
		if not (b.is_cafe and i == 3):   # дверь кафе — отдельная раздвижная, без стекла-оверлея
			var gl := WindowGlass.new()
			gl.size = Vector2i(int(w[2]), int(w[3]))
			gl.position = Vector2(float(w[0]), float(w[1]) - b.texture.get_height())
			gl.seed_id = hash("%s%d" % [id, i])
			gl.transparent = b.is_cafe and i >= 2
			b.add_child(gl)
			_glass.append(gl)
			if b.is_cafe:
				_cafe_overlays.append(gl)
		if not (b.is_cafe or hash("%s%d" % [id, i]) % 10 < 7):
			continue
		var r := ColorRect.new()
		r.position = origin + Vector2(float(w[0]), float(w[1])) * PX
		r.size = Vector2(float(w[2]), float(w[3])) * PX
		r.color = Color(1.0, 0.78, 0.36)
		r.material = _add_mat
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.add_child(r)
		var upper_window := b.is_cafe and float(w[1]) < 117.0   # у кафе окна выше навеса — второй этаж
		_glows.append({"node": r, "base": 0.55, "cafe": b.is_cafe, "upper": upper_window} if upper_window else {"node": r, "base": 0.55, "cafe": b.is_cafe})
		var center := r.position + r.size / 2.0
		var spill := Fx.pixel_light(center, r.size * 2.0 + Vector2(36, 36), Color(1.0, 0.75, 0.35, 0.0))   # свет вокруг окна
		_glow.add_child(spill)
		_glows.append({"node": spill, "base": 0.30, "cafe": b.is_cafe, "upper": true} if upper_window else {"node": spill, "base": 0.30, "cafe": b.is_cafe})
		var wall_bottom := b.world_rect().end.y
		if center.y > wall_bottom - 90.0:   # окно первого этажа бросает пятно света на тротуар
			var pool := Fx.pixel_light(Vector2(center.x, wall_bottom + 30.0), Vector2(r.size.x + 110.0, 90.0), Color(1.0, 0.75, 0.35, 0.0))
			_glow.add_child(pool)
			_glows.append({"node": pool, "base": 0.4, "cafe": b.is_cafe, "street": true})


## Пиксельное свечение (additive): size — множитель диаметра 128 px, flatten < 1 сплющивает в эллипс (пятно на земле).
func _add_halo(pos: Vector2, size: float, base: float, color: Color, flatten := 1.0) -> Sprite2D:
	var h := Fx.pixel_light(pos, Vector2(128.0 * size, 128.0 * size * flatten), Color(color, 0.0))
	_glow.add_child(h)
	_glows.append({"node": h, "base": base, "cafe": false})
	return h


## Объём зданий: косая тень на тротуаре (длина/наклон от солнца), контактное затенение у стены и дизеринг-затенение фасада.
func _build_shading() -> void:
	for b in _building_nodes:
		var r := b.world_rect()
		var strip := ColorRect.new()
		strip.position = Vector2(r.position.x - 80.0, r.end.y)
		strip.size = Vector2(r.size.x + 160.0, 100.0)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = SHADOW_SHADER
		mat.set_shader_parameter("size", strip.size)
		mat.set_shader_parameter("span", r.size.x)
		mat.set_shader_parameter("margin", 80.0)
		strip.material = mat
		_ground.add_child(strip)
		_shadow_mats.append(mat)
		var ao := PixelArt.sprite(PixelArt.dither_gradient(int(r.size.x / 2.0), 6, false, false), r.position + Vector2(0, r.size.y), false)
		ao.modulate = Color(1, 1, 1, 0.42)
		_ground.add_child(ao)
		var w_art := b.texture.get_width()
		var h_art := b.texture.get_height()
		var down := Sprite2D.new()   # фасад темнее к земле
		down.texture = PixelArt.dither_gradient(w_art, h_art, false, true, 4)
		down.centered = false
		down.position = Vector2(0, -h_art)
		down.modulate = Color(1, 1, 1, 0.22)
		b.add_child(down)
		var side := Sprite2D.new()   # и к правому краю: свет слева
		side.texture = PixelArt.dither_gradient(w_art, h_art, true, true, 4)
		side.centered = false
		side.position = Vector2(0, -h_art)
		side.modulate = Color(1, 1, 1, 0.16)
		b.add_child(side)
		if b.is_cafe:
			_cafe_overlays.append(down)
			_cafe_overlays.append(side)


func _build_cats() -> void:
	_player = CatWalker.new()
	_player.arrived.connect(_on_player_arrived)
	_actors.add_child(_player)
	_player.setup(_nav, WAITER_DEF)
	var room_cell := _nav.interior_cells().position
	if GameState.city_inside:
		_player.position = WorldNav.feet_at(room_cell + Vector2i(5, 4))
	else:   # на тротуаре у проёма входа
		_player.position = WorldNav.feet_at(room_cell + Vector2i(CafeRoom.ENTRANCE_CELLS.position.x, CafeRoom.ROWS))
	if GameState.intro_stage >= GameState.INTRO_DONE:
		_spawn_npcs()


## Коты-посетители: половина в зале, половина на улице; дальше сами заходят и выходят. (Во время интро кафе пустое.)
func _spawn_npcs() -> void:
	for i in (2 if Quality.low() else 4):
		var cat := CatWalker.new()
		_actors.add_child(cat)
		var avail := GameState.cats_available()
		cat.setup(_nav, avail[i % avail.size()])
		cat.position = WorldNav.feet_at(_nav.random_cell(i % 2 == 0))
		_npcs.append({"cat": cat, "timer": randf_range(0.5, 4.0)})


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.limit_left = 0
	_camera.limit_right = int(_world_size.x)
	_camera.limit_top = 0
	_camera.limit_bottom = int(_world_size.y)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 6.0
	_camera.position = _camera_target()
	add_child(_camera)
	_camera.make_current()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 2
	add_child(_ui)
	Ui.panel(Rect2(8, 8, 108, 48), Ui.UI_CREAM, _ui)   # 48: рамка 4 сверху + 12 тени снизу оставляют 32 px под строку 28
	var coin := Sprite2D.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(28, 28)   # центр области рамки над нижней тенью
	coin.scale = Vector2(2, 2)
	_ui.add_child(coin)
	_coins_label = Ui.label(str(GameState.coins), Rect2(44, 14, 68, 32), Ui.FONT_SIZE, Ui.INK, _ui, HORIZONTAL_ALIGNMENT_LEFT)
	GameState.coins_changed.connect(_on_coins_changed)  # метод, а не лямбда: отпишется вместе со сценой
	# часы: нажатие перематывает время на час
	_clock_btn = Ui.button("12:00", Rect2(120, 8, 108, 48), "", _ui, false, Ui.UI_CREAM)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_clock_btn.add_theme_color_override(c, Ui.INK)
	_clock_btn.add_theme_color_override("font_outline_color", Ui.CREAM)
	_clock_btn.pressed.connect(_skip_hour)
	var gear := Ui.button("", Rect2(296, 8, 56, 48), "gear", _ui)
	gear.pressed.connect(_open_menu)
	_badge = ColorRect.new()   # красная точка на шестерёнке: есть что забрать (задания, пропуск, подарок)
	_badge.color = Color("e0432f")
	_badge.position = Vector2(338, 10)
	_badge.size = Vector2(12, 12)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	_ui.add_child(_badge)
	_star_btn = Ui.button("★0", Rect2(232, 8, 60, 48), "", _ui, false, Ui.UI_CREAM)   # доска ремонта: сколько звёзд свободно
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_star_btn.add_theme_color_override(c, Color("b87a10"))
	_star_btn.add_theme_color_override("font_outline_color", Ui.CREAM)
	_star_btn.pressed.connect(_open_repairs)
	GameState.repair_done.connect(_on_repair_done)
	_refresh_star_button()
	_btn_shift = Ui.button("Смена", Rect2(88, 568, 184, 56), "play", _ui)
	_btn_shift.visible = false   # появляется, только когда кот у стойки
	_btn_shift.pressed.connect(_start_shift)


## Меню внутри игры (пауза). Страницы: главная → «Улучшения» (магазин), «Настройки» → «Аккаунт» → «Сбросить прогресс»
## (спрятан глубоко и требует подтверждения).
func _build_menu() -> void:
	_menu = CanvasLayer.new()
	_menu.layer = 10
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu.visible = false
	add_child(_menu)
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.5)
	_menu.add_child(dim)
	var pc := OS.has_feature("pc")
	# главная
	var main := _page("main", Ui.column_h(9 if pc else 8), "Меню")
	_page_button(main, 0, "Продолжить", "play").pressed.connect(_close_menu)
	_page_button(main, 1, "Ремонт", "brush").pressed.connect(_open_repairs_from_menu)
	_page_button(main, 2, "Задания", "check").pressed.connect(_open_meta.bind("quests"))
	_page_button(main, 3, "Магазин", "coin").pressed.connect(_open_meta.bind("shop"))
	_page_button(main, 4, "Украшение", "flower").pressed.connect(_open_decorate)
	_page_button(main, 5, "Улучшения", "cart").pressed.connect(_open_shop)
	_page_button(main, 6, "Ещё", "home").pressed.connect(_menu_page.bind("more"))
	_page_button(main, 7, "Настройки", "gear").pressed.connect(_menu_page.bind("settings"))
	if pc:
		_page_button(main, 8, "Выход", "exit").pressed.connect(get_tree().quit)
	# «Ещё»: коты, дневник, сезонный пропуск
	var more := _page("more", Ui.column_h(4), "Ещё")
	_page_button(more, 0, "Коты", "cat").pressed.connect(_open_cat_book)
	_page_button(more, 1, "Дневник", "home").pressed.connect(_open_diary)
	_page_button(more, 2, "Мурлык-пасс", "flower").pressed.connect(_open_meta.bind("season"))
	_page_button(more, 3, "Назад", "undo").pressed.connect(_menu_page.bind("main"))
	# настройки
	var settings := _page("settings", Ui.column_h(7), "Настройки")
	_weather_btn = _page_button(settings, 0, "Погода: Авто", "cloud")   # с текстом: иконка встаёт слева
	_weather_btn.pressed.connect(_cycle_weather)
	_lang_btn = _page_button(settings, 1, "Язык: Авто", "flower")
	_lang_btn.pressed.connect(_cycle_setting.bind("lang"))
	_music_btn = _page_button(settings, 2, "Музыка: 80%", "play")
	_music_btn.pressed.connect(_cycle_setting.bind("music"))
	_sfx_btn = _page_button(settings, 3, "Звуки: 100%", "forks")
	_sfx_btn.pressed.connect(_cycle_setting.bind("sfx"))
	_quality_btn = _page_button(settings, 4, "Качество: Авто", "gear")
	_quality_btn.pressed.connect(_cycle_setting.bind("quality"))
	_page_button(settings, 5, "Аккаунт", "home").pressed.connect(_menu_page.bind("account"))
	_page_button(settings, 6, "Назад", "undo").pressed.connect(_menu_page.bind("main"))
	# аккаунт: статистика, конфиденциальность, титры и спрятанный сброс
	var account := _page("account", 84.0 + Ui.BTN_GAP + Ui.column_h(5), "Аккаунт")
	var ac: Rect2 = account.get_meta("content")
	_account_stats = Ui.label("\n\n", Rect2(ac.position, Vector2(ac.size.x, 84)), Ui.FONT_SIZE, Ui.INK, account, HORIZONTAL_ALIGNMENT_CENTER, true)
	_privacy_btn = _page_button(account, 0, "Аналитика: вкл", "check", false, 92.0)
	_privacy_btn.pressed.connect(_cycle_setting.bind("analytics"))
	_page_button(account, 1, "Титры", "cat", false, 92.0).pressed.connect(_open_credits)
	_page_button(account, 2, "Документы", "home", false, 92.0).pressed.connect(_menu_page.bind("docs"))
	_page_button(account, 3, "Сбросить прогресс", "trash", true, 92.0).pressed.connect(_menu_page.bind("confirm"))
	_page_button(account, 4, "Назад", "undo", false, 92.0).pressed.connect(_menu_page.bind("settings"))
	# документы: политика конфиденциальности, соглашение, поддержка (адреса — data/legal.json; площадкам нужна ссылка внутри игры)
	var docs := _page("docs", Ui.column_h(4), "Документы")
	_page_button(docs, 0, "Конфиденциальность", "check").pressed.connect(func() -> void: OS.shell_open(String(Data.legal["privacy_url"])))
	_page_button(docs, 1, "Соглашение", "check").pressed.connect(func() -> void: OS.shell_open(String(Data.legal["terms_url"])))
	_page_button(docs, 2, "Поддержка", "cat").pressed.connect(func() -> void: OS.shell_open("mailto:" + String(Data.legal["support_email"])))
	_page_button(docs, 3, "Назад", "undo").pressed.connect(_menu_page.bind("account"))
	# подтверждение сброса
	var confirm := _page("confirm", 56.0 + Ui.BTN_GAP + Ui.column_h(2), "Сбросить прогресс?")
	var cc: Rect2 = confirm.get_meta("content")
	Ui.label("Игра начнётся заново.\nОтменить нельзя.", Rect2(cc.position, Vector2(cc.size.x, 56)), Ui.FONT_SIZE, Ui.INK, confirm, HORIZONTAL_ALIGNMENT_CENTER, true)
	_page_button(confirm, 0, "Отмена", "undo", false, 64.0).pressed.connect(_menu_page.bind("account"))
	_page_button(confirm, 1, "Сбросить", "trash", true, 64.0).pressed.connect(_confirm_reset)
	# титры: по одному разделу на страницу, листаются кнопкой
	var credits := _page("credits", 140.0 + Ui.BTN_GAP + Ui.column_h(2), "Титры")
	var kc: Rect2 = credits.get_meta("content")
	_credits_text = Ui.label("", Rect2(kc.position, Vector2(kc.size.x, 140)), Ui.FONT_SIZE, Ui.INK, credits, HORIZONTAL_ALIGNMENT_CENTER, true)
	_credits_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_credits_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_credits_text.position = kc.position
	_credits_text.size.y = 140.0
	_page_button(credits, 0, "Дальше", "play", false, 148.0).pressed.connect(_credits_turn)
	_page_button(credits, 1, "Назад", "undo", false, 148.0).pressed.connect(_menu_page.bind("account"))
	# дневник: записи комикса, открываются за смены
	_diary_page = _page("diary", Ui.column_h(IntroComic.PANELS.size() + 1), "Дневник")
	# магазин улучшений (карточки строятся при открытии, по 4 на страницу)
	_shop_page = _page("shop", SHOP_PER_PAGE * CARD_H + (SHOP_PER_PAGE - 1) * CARD_GAP + Ui.BTN_GAP + Ui.BTN_H, "Улучшения", true)
	_menu_page("main")


## Кнопка в столбце страницы: i — номер, dy — сдвиг вниз от начала области (под текстом выше).
func _page_button(page: Control, i: int, text: String, icon: String, danger := false, dy := 0.0) -> Button:
	var c: Rect2 = page.get_meta("content")
	var b := Ui.button(text, Rect2(c.position.x, c.position.y + dy + i * (Ui.BTN_H + Ui.BTN_GAP), c.size.x, Ui.BTN_H), icon, page, false, null, danger)
	return b


## Страница меню: рамка и заголовок по центру экрана.
func _page(page_name: String, content_h: float, title: String, wide := false) -> Control:
	var page := Control.new()
	page.visible = false
	_menu.add_child(page)
	var height := Ui.page_height(content_h)
	var w := 336.0 if wide else 300.0
	var x := (360.0 - w) / 2.0
	var top := floorf((640.0 - height) / 2.0 / 2.0) * 2.0
	Ui.panel(Rect2(x, top, w, height), Ui.UI_WOOD, page)
	Ui.label(title, Rect2(x, top + Ui.PAGE_PAD_TOP, w, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, page, HORIZONTAL_ALIGNMENT_CENTER)
	page.set_meta("content", Rect2(x + Ui.PAGE_PAD_X, top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + Ui.PAGE_GAP, w - 2.0 * Ui.PAGE_PAD_X, content_h))
	_menu_pages[page_name] = page
	return page


func _cycle_weather() -> void:
	Weather.cycle_mode()
	_refresh_weather_btn()
	GameState.save_game()


## Кнопка погоды: подпись режима и значок, соответствующий ему (облако+солнце — авто, солнце, дождь, туман, жара, снег).
func _refresh_weather_btn() -> void:
	if _weather_btn == null:
		return
	Ui.set_button_text(_weather_btn, tr("Погода: %s") % tr(Weather.mode_text()))
	Ui.set_button_icon(_weather_btn, WeatherIcons.icon(Weather.mode))


func _menu_page(page_name: String) -> void:
	_refresh_weather_btn()
	_refresh_setting_buttons()
	for k in _menu_pages:
		(_menu_pages[k] as Control).visible = k == page_name
	if page_name == "account":
		_account_stats.text = tr("Подано за всё время: %d\nМонет в кассе: %d\nУлучшений куплено: %d") % [GameState.served_total, GameState.coins, GameState.upgrades.size()]


const VOLUME_STEPS := [0.0, 0.4, 0.8, 1.0]
const LANG_STEPS := ["auto", "ru", "en"]
const QUALITY_STEPS := ["auto", "low", "high"]


## Подписи кнопок настроек по текущим значениям (язык, громкость, качество, аналитика).
func _refresh_setting_buttons() -> void:
	if _lang_btn == null:
		return
	var lang_names := {"auto": tr("Авто"), "ru": "Русский", "en": "English"}
	Ui.set_button_text(_lang_btn, tr("Язык: %s") % lang_names[String(GameState.get_setting("lang"))])
	Ui.set_button_text(_music_btn, tr("Музыка: %d%%") % int(round(float(GameState.get_setting("music")) * 100.0)))
	Ui.set_button_text(_sfx_btn, tr("Звуки: %d%%") % int(round(float(GameState.get_setting("sfx")) * 100.0)))
	var q_names := {"auto": tr("Авто"), "low": tr("Низкое"), "high": tr("Высокое")}
	Ui.set_button_text(_quality_btn, tr("Качество: %s") % q_names[String(GameState.get_setting("quality"))])
	Ui.set_button_text(_privacy_btn, tr("Аналитика: вкл") if bool(GameState.get_setting("analytics")) else tr("Аналитика: выкл"))


## Следующее значение настройки по кругу; язык применяется перезагрузкой города (все подписи строятся заново).
func _cycle_setting(key: String) -> void:
	var cur: Variant = GameState.get_setting(key)
	match key:
		"music", "sfx":
			var i := 0
			for k in VOLUME_STEPS.size():
				if absf(float(VOLUME_STEPS[k]) - float(cur)) < 0.05:
					i = k
			GameState.set_setting(key, VOLUME_STEPS[(i + 1) % VOLUME_STEPS.size()])
		"lang":
			GameState.set_setting(key, LANG_STEPS[(LANG_STEPS.find(String(cur)) + 1) % LANG_STEPS.size()])
			get_tree().paused = false
			Nav.go(self, Nav.CITY)
			return
		"quality":
			GameState.set_setting(key, QUALITY_STEPS[(QUALITY_STEPS.find(String(cur)) + 1) % QUALITY_STEPS.size()])
		"analytics":
			GameState.set_setting(key, not bool(cur))
	_refresh_setting_buttons()


# ---------------------------------------------------------------- титры и дневник

func _open_credits() -> void:
	_credits_idx = 0
	_refresh_credits()
	_menu_page("credits")


func _credits_turn() -> void:
	_credits_idx = (_credits_idx + 1) % Data.credits.size()
	_refresh_credits()


func _refresh_credits() -> void:
	var sec: Dictionary = Data.credits[_credits_idx]
	var lines: Array[String] = [tr(String(sec["title"])).to_upper()]
	for ln in sec["lines"]:
		lines.append(tr(String(ln)))
	_credits_text.text = "\n".join(lines)


## Дневник: записи комикса. Открыта запись, когда сыграно нужное число смен; тап открывает комикс поверх города.
func _open_diary() -> void:
	for ch in _diary_page.get_children():
		if ch.has_meta("diary"):
			ch.queue_free()
	var c: Rect2 = _diary_page.get_meta("content")
	for i in IntroComic.PANELS.size():
		var need: int = IntroComic.DIARY_UNLOCK[i]
		var open: bool = GameState.shifts_played >= need
		var label := tr(IntroComic.DIARY_TITLES[i]) if open else tr("Закрыто: смена %d") % need
		var b := Ui.button(label, Rect2(c.position.x, c.position.y + i * (Ui.BTN_H + Ui.BTN_GAP), c.size.x, Ui.BTN_H), "home" if open else "", _diary_page)
		b.set_meta("diary", true)
		b.disabled = not open
		b.pressed.connect(_show_diary_entry.bind(i))
	var back := Ui.button(tr("Назад"), Rect2(c.position.x, c.position.y + IntroComic.PANELS.size() * (Ui.BTN_H + Ui.BTN_GAP), c.size.x, Ui.BTN_H), "undo", _diary_page)
	back.set_meta("diary", true)
	back.pressed.connect(_menu_page.bind("main"))
	_menu_page("diary")


func _show_diary_entry(i: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var comic := IntroComic.new()
	comic.panels = [IntroComic.PANELS[i]]
	comic.overlay = true
	layer.add_child(comic)
	comic.tree_exited.connect(layer.queue_free)


func _confirm_reset() -> void:
	GameState.reset_progress()
	get_tree().paused = false
	Nav.go(self, Nav.CITY)


# ---------------------------------------------------------------- магазин улучшений

func _open_shop() -> void:
	_refresh_shop()
	_menu_page("shop")


## Карточки улучшений: название, что даёт, цена-кнопка. Недоступные (не хватает монет / нет условия) — серые.
func _refresh_shop() -> void:
	for ch in _shop_page.get_children().slice(2):   # рамка и заголовок остаются
		ch.queue_free()
	var c: Rect2 = _shop_page.get_meta("content")
	var pages := int(ceil(float(Data.upgrades.size()) / float(SHOP_PER_PAGE)))
	_shop_idx = clampi(_shop_idx, 0, pages - 1)
	var first := _shop_idx * SHOP_PER_PAGE
	var y := c.position.y
	for i in range(first, mini(Data.upgrades.size(), first + SHOP_PER_PAGE)):
		var u: Dictionary = Data.upgrades[i]
		var id := String(u["id"])
		var owned := GameState.has_upgrade(id)
		var req := String(u["requires"])
		var locked := req != "" and not GameState.has_upgrade(req)
		Ui.panel(Rect2(c.position.x, y, c.size.x, CARD_H), Ui.UI_CREAM, _shop_page)
		var text_w := c.size.x - 12.0 - PRICE_W - 12.0 - 8.0   # слева 12, справа кнопка цены 104 с отступом 12
		Ui.label(String(u["name"]), Rect2(c.position.x + 12.0, y + 12.0, text_w, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK, _shop_page, HORIZONTAL_ALIGNMENT_LEFT, true)
		var sub := String(u["unlocks"])
		if locked:
			for r in Data.upgrades:
				if String(r["id"]) == req:
					sub = "Нужен: " + String(r["name"]).to_lower()
		Ui.label(sub, Rect2(c.position.x + 12.0, y + 12.0 + Ui.LINE_H, text_w, Ui.LINE_H), Ui.FONT_SIZE, Ui.INK.lightened(0.25), _shop_page, HORIZONTAL_ALIGNMENT_LEFT, true)
		var bx := c.position.x + c.size.x - 12.0 - PRICE_W
		if owned:
			Ui.label("Куплено", Rect2(bx, y + Ui.EDGE, PRICE_W, CARD_H - Ui.EDGE - Ui.SHADOW_CREAM), Ui.FONT_SIZE, Color("3c8c4a"), _shop_page, HORIZONTAL_ALIGNMENT_CENTER, true)
		else:
			var b := Ui.button(str(int(u["price"])), Rect2(bx, y + 14.0, PRICE_W, Ui.BTN_H), "coin", _shop_page)
			b.disabled = locked or GameState.coins < int(u["price"])
			b.modulate = Color(0.65, 0.65, 0.65) if b.disabled else Color.WHITE
			b.pressed.connect(_buy_upgrade.bind(id))
		y += CARD_H + CARD_GAP
	var by := c.position.y + c.size.y - Ui.BTN_H
	if pages > 1:
		var half := (c.size.x - Ui.BTN_GAP) / 2.0
		Ui.button("Назад", Rect2(c.position.x, by, half, Ui.BTN_H), "undo", _shop_page).pressed.connect(_shop_back)
		var more := Ui.button("Дальше" if _shop_idx < pages - 1 else "Раньше", Rect2(c.position.x + half + Ui.BTN_GAP, by, half, Ui.BTN_H), "", _shop_page)
		more.pressed.connect(_shop_turn)
	else:
		Ui.button("Назад", Rect2(c.position.x, by, c.size.x, Ui.BTN_H), "undo", _shop_page).pressed.connect(_shop_back)


func _shop_turn() -> void:
	var pages := int(ceil(float(Data.upgrades.size()) / float(SHOP_PER_PAGE)))
	_shop_idx = (_shop_idx + 1) % pages
	_refresh_shop()


func _shop_back() -> void:
	_menu_page("main")


func _buy_upgrade(id: String) -> void:
	if not GameState.buy_upgrade(id):
		return
	for u in Data.upgrades:
		if String(u["id"]) == id:
			Fx.burst(_menu, Vector2(180, 300), "star", Color("ffe08a"), 14, 260.0, 200.0, 1.0, 1.2)
			Ui.toast(_menu, String(u["flavor"]), Vector2(180, 560))
	_on_upgrade_bought(id)
	_refresh_shop()
	_coins_label.text = str(GameState.coins)


# ---------------------------------------------------------------- интро

func _skip_hour() -> void:
	if GameState.intro_stage >= GameState.INTRO_DONE:
		TimeOfDay.skip(1.0)


## Запускает нужную часть вступления по стадии (1 обучающая смена, 2 ставни за звезду, 3 расчистка); время стоит на 9:00.
func _start_intro_if_needed() -> void:
	var stage := GameState.intro_stage
	if stage >= GameState.INTRO_DONE:
		return
	TimeOfDay.hour = 9.0
	TimeOfDay.set_process(false)
	_intro = Intro.new()
	add_child(_intro)
	_intro.setup(self)
	_intro.cleanup_finished.connect(_on_cleanup_finished)
	if stage == 1:
		Platform.track("ftue_step", {"step": "tutorial_start", "t": Platform.session_seconds()})
		get_tree().create_timer(0.5).timeout.connect(_start_tutorial)
	elif stage == 2:
		_offer_shutter_repair(0.8)


func _on_cleanup_finished() -> void:
	get_tree().create_timer(2.0).timeout.connect(_finish_intro)


func _on_tutorial_finished(served: int, earned: int) -> void:
	if _shift_layer != null:
		_shift_layer.queue_free()
		_shift_layer = null
	Audio.music("city")
	_world.visible = true
	_sky_layer.visible = true
	_ui.visible = true
	GameState.tutorial_served = served
	GameState.stars_bonus += GameState.TUTORIAL_STARS   # обучение нельзя провалить: три звезды всегда
	GameState.intro_stage = GameState.stage_after_tutorial()
	GameState.save_game()
	Platform.track("ftue_step", {"step": "tutorial_done", "t": Platform.session_seconds(), "earned": earned})
	Fx.banner(_ui, tr("Первая смена!"), Vector2(180, 200), Color("ffd640"))
	Fx.confetti(_ui, Vector2(180, 180), 36)
	Ui.toast(_ui, tr("Заработано звёзд: %d") % GameState.TUTORIAL_STARS, Vector2(180, 260))
	if GameState.intro_stage == 2:
		_offer_shutter_repair(2.2)
	elif GameState.intro_stage >= GameState.INTRO_DONE:
		_finish_intro()


## Карточка «Ремонт»: тап по кнопке тратит звезду и дальше игрок толкает ставни.
func _offer_shutter_repair(delay: float) -> void:
	if GameState.has_repair("shutters"):
		if _intro != null:
			_intro.enable_knock()
		return
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if _repair_card != null or GameState.intro_stage != 2 or _intro == null:
			return
		_repair_card = RepairCard.new()
		_ui.add_child(_repair_card)
		_repair_card.setup("shutters")
		_repair_card.chosen.connect(_on_repair_chosen))


func _on_repair_chosen(id: String) -> void:
	if not GameState.do_repair(id):
		return
	if _repair_card != null:
		_repair_card.queue_free()
		_repair_card = null
	Audio.sfx("star", 0.0)
	if id == "shutters" and _intro != null:
		_intro.enable_knock()
		Fx.burst(_ui, Vector2(180, 360), "star", Color("ffe08a"), 10, 200.0, 160.0, 0.9, 1.1)


func _finish_intro() -> void:
	GameState.intro_stage = GameState.INTRO_DONE
	GameState.save_game()
	Platform.track("ftue_step", {"step": "intro_done", "t": Platform.session_seconds()})
	_refresh_star_button()
	Ui.toast(_ui, tr("Иди к стойке — там смена!"), Vector2(180, 150))
	TimeOfDay.set_process(true)
	if _intro != null:
		_intro.queue_free()
		_intro = null
	_spawn_npcs()
	_apply_clip_materials()


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	if Quality.sample(delta):
		_on_quality_dropped()
	_traffic.update(delta)
	_npc_tick(delta)
	_update_xray(delta)
	_update_door()
	_apply_daylight()
	_update_camera()
	_clock_btn.text = TimeOfDay.clock_text()
	GameState.city_inside = _depth(_player.position) > 0.5
	if _shift_layer != null:
		return
	var dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) \
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) \
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if dir != Vector2.ZERO:
		_pending = ""
		_player.nudge(dir, delta)
	_btn_shift.visible = _in_counter_zone() and GameState.intro_stage >= GameState.INTRO_DONE


## Насколько глубоко в здание зашли лапки: 0 — снаружи (у фасада и дальше), 1 — полностью внутри.
func _depth(feet: Vector2) -> float:
	for rect in [_interior_rect, _upper_rect]:
		if rect == _upper_rect and not GameState.has_upgrade("upstairs"):
			continue
		if feet.x >= rect.position.x and feet.x <= rect.end.x and feet.y <= rect.end.y + 6.0 and feet.y >= rect.position.y:
			return clampf((rect.end.y - feet.y + 6.0) / DEPTH_ZONE, 0.0, 1.0)
	return 0.0


## Рентген — пиксельная диафрагма: пока игрок внутри здания, круг вокруг него расходится и вырезает фасад;
## вышел — круг сжимается к нему. Радиус считается от лапок игрока.
func _update_xray(delta: float) -> void:
	var center := _player.position
	var rect := _floor_rect()
	_iris_max = _farthest_corner(center, rect) + 8.0   # с запасом, чтобы круг гарантированно накрыл весь интерьер
	var target := _iris_max if _depth(center) > 0.05 else 0.0
	_iris_r = move_toward(_iris_r, target, (IRIS_OPEN_SPEED if target > _iris_r else IRIS_CLOSE_SPEED) * delta)
	_iris_r = minf(_iris_r, _iris_max)
	_xray = clampf(_iris_r / _iris_max, 0.0, 1.0)
	var lower := _space == SPACE_CAFE
	var hole := Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)   # вырез в фасаде — в области этажа кота
	var lower_hole := Vector4(_interior_rect.position.x, _interior_rect.position.y, _interior_rect.size.x, _interior_rect.size.y)
	var inner := Vector4(lower_hole.x, lower_hole.y, lower_hole.z, lower_hole.w - T)   # без переднего ряда (витрины): гости на тротуаре не режутся
	var r_low := _iris_r if lower else 0.0
	_hole_mat.set_shader_parameter("center", center)
	_hole_mat.set_shader_parameter("radius", _iris_r)
	_hole_mat.set_shader_parameter("region", hole)
	if _door != null:
		_door.set_iris(center, r_low, lower_hole)
	_clip_mat.set_shader_parameter("center", center)
	_clip_mat.set_shader_parameter("radius", r_low)
	_clip_mat.set_shader_parameter("region", inner)
	var r_up := 0.0 if lower else _iris_r
	_clip_mat_up.set_shader_parameter("center", center)
	_clip_mat_up.set_shader_parameter("radius", r_up)
	_clip_mat_up.set_shader_parameter("region", hole)
	_update_weather_mask()


## Внутри раскрытого интерьера дождь и снег не идут: передаём шейдеру прямоугольник зала в экранных координатах.
func _update_weather_mask() -> void:
	if _weather_fx == null or _camera == null:
		return
	var xf := _world.get_global_transform_with_canvas()
	var rect := _floor_rect()
	var a := xf * rect.position
	var b := xf * rect.end
	_weather_fx.set_mask(Rect2(a, b - a), _xray)
	if _snow != null:
		_snow.mask = rect
		_snow.mask_amount = _xray


func _farthest_corner(from: Vector2, rect: Rect2) -> float:
	var far := 0.0
	for c in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		far = maxf(far, from.distance_to(c))
	return far


## Виден ли предмет в точке: снаружи здания — всегда, внутри — если его накрывает круг рентгена.
func is_revealed(p: Vector2) -> bool:
	if _depth(p) < 0.05:
		return true
	return _space == SPACE_CAFE and _interior_rect.has_point(p) and p.distance_to(_player.position) < _iris_r   # гости зала — только когда кот на первом этаже


## Мебель и гости внутри здания рисуются поверх фасада, поэтому им нужен материал обрезки по кругу.
func _apply_clip_materials() -> void:
	for ch in _actors.get_children():
		if ch is CatWalker and ch != _player:
			(ch as CatWalker).use_clip_material(_clip_mat)
		elif ch.has_meta("interior"):
			(ch as Node2D).material = _clip_mat_up if ch.has_meta("upper") else _clip_mat
			for sub in ch.get_children():
				(sub as CanvasItem).use_parent_material = true


## Свет суток по узлам: улица — ambient, интерьер — тёплый свет кафе; кот, зашедший в здание, плавно меняет свет.
func _apply_daylight() -> void:
	var amb := TimeOfDay.ambient() * Weather.tint()   # погода гасит или подкрашивает свет улицы
	var ind := TimeOfDay.indoor()
	if _intro != null:
		ind *= _intro.light()   # пока зал не расчищен, в нём темно
	var night := TimeOfDay.night()
	var lit := clampf(night + Weather.overcast() * 0.3, 0.0, 1.0)
	_lit = lit   # в пасмурную погоду окна и фонари зажигаются раньше
	_ground.modulate = amb
	_buildings.modulate = amb
	_room.visible = true   # зал виден сквозь прозрачные окна и дверь
	for k in _spaces:
		(_spaces[k] as CanvasItem).modulate = ind
	_room.modulate = ind
	for ch in _actors.get_children():
		if ch is CatWalker:
			ch.modulate = amb.lerp(ind, _depth(ch.position))

		elif ch.has_meta("interior"):
			ch.modulate = ind
		else:
			ch.modulate = amb
	for g in _glows:
		var f := 1.0
		if g.has("upper"):   # окна второго этажа гаснут, когда фасад вырезан наверху
			f = 1.0 - (_xray if _space == SPACE_UP else 0.0)
		elif g["cafe"]:
			f = 1.0 - (_xray if _space == SPACE_CAFE else 0.0)
		if g.has("street"):   # свет на снегу не выжигаем добела
			f *= 1.0 - Weather.snow_cover * 0.6
		(g["node"] as CanvasItem).modulate.a = float(g["base"]) * lit * f
	for car in _traffic.cars():
		if car.halo != null:
			var p := car.position + car.headlight_offset() + Vector2(car.dir * 72.0, 6.0)
			car.halo.position = Vector2(roundf(p.x / 2.0) * 2.0, roundf(p.y / 2.0) * 2.0)
	_update_light_volume(night)
	var sky := Weather.sky(TimeOfDay.sky_bottom()).lightened(0.15)
	var day := (1.0 - night) * (1.0 - Weather.overcast() * 0.5)
	for gl in _glass:
		gl.apply(sky, day, Weather.rain, Weather.fog, Weather.snow_cover)


## Камера едет за котом по обеим осям (за дома — на задний двор); на улице лапки стоят ниже центра экрана.
func _camera_target() -> Vector2:
	return Vector2(clampf(_player.position.x, 180.0, _world_size.x - 180.0), clampf(_player.position.y - CAMERA_FEET_OFFSET, 320.0, _world_size.y - 320.0))


## Солнечные тени и свет в зале: длина и наклон теней от высоты солнца (ночью теней нет); лучи и лампы в кафе.
func _update_light_volume(night: float) -> void:
	var p := TimeOfDay.sun_progress()
	var strength := 0.0
	var length := 12.0
	var lean := 0.0
	if p >= 0.0:
		var elev := sin(p * PI)
		length = lerpf(70.0, 14.0, elev)
		lean = (0.5 - p) * 2.4
		strength = 0.42 * clampf(elev * 3.0, 0.0, 1.0)
	for m in _shadow_mats:
		m.set_shader_parameter("shadow_length", length)
		m.set_shader_parameter("lean", lean)
		m.set_shader_parameter("strength", strength)
	_room.set_lighting(1.0 - night, night)
	for k in _spaces:
		(_spaces[k] as InteriorSpace).set_lighting(1.0 - night, night)
	for o in _cafe_overlays:
		o.visible = _xray < 0.4


func _update_camera() -> void:
	_sky_bg.material.set_shader_parameter("top_color", Weather.sky(TimeOfDay.sky_top()))
	_sky_bg.material.set_shader_parameter("bottom_color", Weather.sky(TimeOfDay.sky_bottom()))
	_sky.overcast = Weather.overcast()
	_camera.position = _camera_target()
	_sky.camera_x = _camera.get_screen_center_position().x


func _in_counter_zone() -> bool:
	return _space == SPACE_CAFE and _interior_rect.has_point(_player.position) and _room.in_counter_zone(_room.to_local(_player.position))


func _on_player_arrived() -> void:
	if _intro != null:
		_intro.on_arrived()
	if _pending == "shift" and _in_counter_zone():
		_start_shift()
	elif _pending == "portal" and not _pending_portal.is_empty():
		if _local_cell(_player.position) in (_pending_portal["stand"] as Array):
			_use_portal(_pending_portal)
			return
	_pending = ""


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)


# ---------------------------------------------------------------- коморка, лестница, второй этаж

func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	_fade = ColorRect.new()
	_fade.size = Vector2(360, 640)
	_fade.color = Color(0.05, 0.03, 0.08, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


func _set_fade(a: float) -> void:
	_fade.color.a = ceilf(clampf(a, 0.0, 1.0) * 5.0) / 5.0   # затемнение ступенями, как всё остальное


## Затемнение → действие в темноте → проявление. Пока идёт, ввод не принимается.
func _with_fade(action: Callable) -> void:
	if _fading:
		return
	_fading = true
	_player.stop()
	var t := create_tween()
	t.tween_method(_set_fade, 0.0, 1.0, 0.24)
	t.tween_callback(action)
	t.tween_interval(0.06)
	t.tween_method(_set_fade, 1.0, 0.0, 0.24)
	t.tween_callback(func() -> void: _fading = false)


## Переход на другой этаж: кот оказывается наверху (внизу), камера плывёт к нему, круг рентгена переходит на другой фасад.
func _go_space(space: int, arrive: Vector2i) -> void:
	if _fading:
		return
	Fx.burst(_actors, _player.position + Vector2(0, -20), "puff", Color(0.85, 0.8, 0.7), 5, 60.0, -10.0, 0.7, 1.0, 120.0)
	_set_space(space, arrive)
	Fx.burst(_actors, _player.position + Vector2(0, -20), "puff", Color(0.85, 0.8, 0.7), 5, 60.0, -10.0, 0.7, 1.0, 120.0)


## Мгновенно переключает помещение: что рисуем, где ходит кот, кто виден. arrive — клетка зала (локальная), (-1,-1) — остаться на месте.
func _set_space(space: int, arrive: Vector2i) -> void:
	var changed := space != _space
	_space = space
	_pending = ""
	_pending_portal = {}
	_nav.set_interior_mask(_room.walk_mask(), true)
	_floor_nav.rebuild((_spaces[SPACE_UP] as InteriorSpace).walk_mask())
	_player.nav = _nav if space == SPACE_CAFE else _floor_nav
	if changed:
		_iris_r = 0.0   # новый этаж раскрывается заново
	if arrive.x >= 0:
		_player.stop()
		if space == SPACE_CAFE:
			var cell := _nav.nearest_free_cell(_nav.interior_cells().position + arrive)
			_player.position = WorldNav.feet_at(cell)
		else:
			_player.position = _floor_nav.feet_at(_floor_nav.nearest_free_cell(arrive))
		if not changed:
			_camera.position = _camera_target()
			_camera.reset_smoothing()


## Клетка кота на этаже, где он сейчас (локальные клетки пола 10×7).
func _local_cell(feet: Vector2) -> Vector2i:
	if _space == SPACE_UP:
		return _floor_nav.cell_of_feet(feet)
	return WorldNav.cell_of_feet(feet) - _nav.interior_cells().position


func _local_feet(cell: Vector2i) -> Vector2:
	if _space == SPACE_UP:
		return _floor_nav.feet_at(cell)
	return WorldNav.feet_at(_nav.interior_cells().position + cell)


## Габарит этажа, на котором кот.
func _floor_rect() -> Rect2:
	return _upper_rect if _space == SPACE_UP else _interior_rect


## Куда ведёт дверь или лестница и что для этого нужно.
func _portal_gate(d: Dictionary) -> String:
	match String(d["id"]):
		"staff_locked":
			return "Служебка заколочена. Нужна «Коморка» (улучшения)"
		"stairs_up":
			return "" if GameState.has_upgrade("upstairs") else "Лестница заколочена. Нужен «Второй этаж» (улучшения)"
	return ""


## Тап по двери, лестнице или кровати: кот идёт к клетке рядом и там переходит (или ложится спать).
func _tap_portal(d: Dictionary, world_p: Vector2) -> void:
	var gate := _portal_gate(d)
	if gate != "":
		_toast(gate, world_p)
		return
	var stand: Array = d["stand"]
	var here := _local_cell(_player.position)
	_pending = "portal"
	_pending_portal = d
	if here in stand:
		_use_portal(d)
		return
	var best: Vector2i = stand[0]
	for c: Vector2i in stand:
		if _local_feet(c).distance_to(_player.position) < _local_feet(best).distance_to(_player.position):
			best = c
	_player.walk_to(_local_feet(best))


func _use_portal(d: Dictionary) -> void:
	_pending = ""
	_pending_portal = {}
	match String(d["to"]):
		"cafe":   # со второго этажа вниз, в служебку
			_go_space(SPACE_CAFE, CafeRoom.STAIRS_STAND[0])
		"up":
			_go_space(SPACE_UP, InteriorSpace.STAIRS_STAND[2])
		_:
			_sleep()


## Кровать: ночью — спать до утра, днём — просто прилечь.
func _sleep() -> void:
	var night := TimeOfDay.night() > 0.3
	_with_fade(func() -> void:
		if night:
			TimeOfDay.hour = 7.0
		GameState.save_game())
	Fx.burst(_actors, _player.position + Vector2(10, -40), "zzz", Color("c9e8ff"), 4, 40.0, -10.0, 1.2, 1.0, 20.0)
	_toast("Мяу выспался. Доброе утро!" if night else "Ещё не время спать. Мяу просто полежал", _player.position + Vector2(0, -60))


## Купили улучшение: дверь и лестница оживают.
## Звёзды на кнопке; когда хватает на открытую задачу — кнопка мигает (подсказка «пора в ремонт»).
func _refresh_star_button() -> void:
	if _star_btn == null:
		return
	_star_btn.visible = GameState.intro_stage >= GameState.INTRO_DONE
	Ui.set_button_text(_star_btn, "★%d" % GameState.stars_free())
	if _star_btn.has_meta("blink"):
		(_star_btn.get_meta("blink") as Tween).kill()
		_star_btn.remove_meta("blink")
	_star_btn.modulate = Color.WHITE
	var affordable := GameState.open_repairs().any(func(r: Dictionary) -> bool: return int(r["cost"]) <= GameState.stars_free())
	if affordable and _star_btn.visible:
		var t := _star_btn.create_tween().set_loops()
		t.tween_property(_star_btn, "modulate", Color(1.25, 1.15, 0.7), 0.5)
		t.tween_property(_star_btn, "modulate", Color.WHITE, 0.5)
		_star_btn.set_meta("blink", t)


## Экраны мета-игры (магазин, задания, пропуск) поверх меню: закрыл — вернулся в меню.
func _open_meta(which: String) -> void:
	if GameState.intro_stage < GameState.INTRO_DONE:
		Ui.toast(_menu, tr("Сначала откроем кафе"), Vector2(180, 560))
		return
	var s: ListScreen
	match which:
		"shop":
			s = MetaScreens.open_shop(self)
		"quests":
			s = MetaScreens.open_quests(self)
		_:
			s = MetaScreens.open_season(self)
	s.layer = 12
	s.closed.connect(_refresh_badges)


## Красная точка на шестерёнке: подарок, задания или награды пропуска ждут.
func _refresh_badges() -> void:
	if _badge == null:
		return
	_badge.visible = GameState.intro_stage >= GameState.INTRO_DONE and (Daily.gift_ready() or Daily.claimable_count() > 0 or Shop.season_claimable() > 0)


# ---------------------------------------------------------------- окна при входе: подарок, офлайн-доход, предложения

## Ставит окно в очередь: окна идут по одному (подарок → офлайн-доход → подарок за возвращение → предложение → уведомления).
func _queue_popup(f: Callable) -> void:
	_popup_queue.append(f)
	if not _popup_busy:
		_next_popup()


func _next_popup() -> void:
	if _popup_queue.is_empty():
		_popup_busy = false
		_refresh_badges()
		return
	_popup_busy = true
	var f: Callable = _popup_queue.pop_front()
	f.call()


func _popup_done() -> void:
	_refresh_badges()
	_coins_label.text = str(GameState.coins)
	get_tree().create_timer(0.35).timeout.connect(_next_popup)


## Что показать при запуске города (только после вступления и не во время смены).
func _start_session_popups() -> void:
	if GameState.intro_stage < GameState.INTRO_DONE or GameState.suppress_popups:
		return
	Daily.start_session()
	if Daily.gift_ready():
		_queue_popup(_show_gift)
	if Daily.offline_pending() > 0:
		_queue_popup(_show_offline)
	if bool(GameState.meta["return_gift_pending"]):
		_queue_popup(_show_return_gift)
	# возврат из фона (мобильные): те же окна
	Daily.offline_ready.connect(func(_c: int) -> void: _queue_popup(_show_offline))
	Daily.return_gift_ready.connect(func() -> void: _queue_popup(_show_return_gift))
	var offer := Shop.offer_to_show()
	if offer != "":
		_queue_popup(_show_offer.bind(offer))
	if Daily.should_ask_notifications():
		_queue_popup(_show_notif_ask)
	_refresh_badges()


func _show_gift() -> void:
	var g := GiftPopup.new()
	add_child(g)
	g.finished.connect(_popup_done)


func _show_offline() -> void:
	var n := Daily.offline_pending()
	if n <= 0:
		_popup_done()
		return
	var p := InfoPopup.open(self, "С возвращением!", tr("Пока тебя не было, кафе заработало %d монет.") % n, [tr("Забрать"), tr("×2 за рекламу")] as Array[String], ["check", "play"] as Array[String])
	p.chosen.connect(func(i: int) -> void:
		if i == 1:
			Shop.show_ad("offline_double", func(ok: bool) -> void:
				Daily.claim_offline(ok)
				if not ok:
					Ui.toast(_ui, tr("Реклама недоступна — забрано без удвоения"), Vector2(180, 150))
				_popup_done())
		else:
			Daily.claim_offline(false)
			_popup_done())


func _show_return_gift() -> void:
	var p := InfoPopup.open(self, "Мы скучали!", tr("Тебя не было несколько дней. Держи подарок: 5 рыбок и два бустера."), [tr("Забрать")] as Array[String], ["check"] as Array[String])
	p.chosen.connect(func(_i: int) -> void:
		Daily.claim_return_gift()
		_popup_done())


func _show_offer(sku: String) -> void:
	Shop.mark_offer_shown(sku)
	var st: Dictionary = Data.shop["starter"]
	var p := InfoPopup.open(self, "Стартовый набор", tr("%d рыбок и 3 бустера всего за %s. Предложение действует %d ч.") % [int(st["fish"]), Shop.price_text("starter_pack"), int(ceil(float(Shop.starter_seconds_left()) / 3600.0))],
		[tr("Купить за %s") % Shop.price_text("starter_pack"), tr("Не сейчас")] as Array[String], ["cart", "undo"] as Array[String])
	p.chosen.connect(func(i: int) -> void:
		if i == 0:
			Shop.buy("starter_pack", func(ok: bool, _s: String) -> void:
				Ui.toast(_ui, tr("Спасибо за покупку!") if ok else tr("Покупка не прошла"), Vector2(180, 150))
				_popup_done())
		else:
			_popup_done())


func _show_notif_ask() -> void:
	var p := InfoPopup.open(self, "Напоминания", tr("Напоминать о подарках и заработке кафе? Не чаще раза в день."), [tr("Включить"), tr("Не нужно")] as Array[String], ["check", "undo"] as Array[String])
	p.chosen.connect(func(i: int) -> void:
		Daily.answer_notifications(i == 0)
		_popup_done())


func _open_repairs_from_menu() -> void:
	_close_menu()
	_open_repairs()


func _open_cat_book() -> void:
	if GameState.intro_stage < GameState.INTRO_DONE:
		Ui.toast(_menu, tr("Сначала откроем кафе"), Vector2(180, 560))
		return
	var book := CatBook.new()
	book.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(book)   # поверх меню (слой 7 < 10): закрыть книгу — вернуться в меню
	book.layer = 12


func _open_repairs() -> void:
	if _repair_board != null or _shift_layer != null or _levels_layer != null or GameState.intro_stage < GameState.INTRO_DONE:
		return
	_player.stop()
	_repair_board = RepairBoard.new()
	add_child(_repair_board)
	_repair_board.tree_exited.connect(func() -> void:
		_repair_board = null
		_refresh_star_button())


## Ремонт выполнен: зал перерисовывается (цвета, новая мебель), открытые улучшения применяются.
func _on_repair_done(id: String) -> void:
	var effects: Array = GameState.repair_def(id).get("effects", [])
	if effects.any(func(e: Dictionary) -> bool: return String(e["kind"]) in ["furniture", "style"]):
		_room.set_layout(GameState.layout)
		_room.queue_redraw()
		_apply_clip_materials()   # новая мебель прячется за фасадом, пока кот снаружи
		_set_space(_space, Vector2i(-1, -1))
	for e in effects:
		if String(e["kind"]) == "upgrade":
			_on_upgrade_bought(String(e["id"]))
	_refresh_star_button()
	_coins_label.text = str(GameState.coins)
	_play_stories("repair", id)


## Показывает ещё не виденные сюжетные сцены для события: по очереди, поверх всего (на время сцены игра стоит).
func _play_stories(kind: String, id: String) -> void:
	var list := GameState.story_for(kind, id)
	if list.is_empty() or _story_playing:
		return
	_story_playing = true
	get_tree().create_timer(0.7).timeout.connect(func() -> void: _play_story_queue(list))


func _play_story_queue(list: Array[Dictionary]) -> void:
	if list.is_empty():
		_story_playing = false
		get_tree().paused = false
		return
	var scene: Dictionary = list.pop_front()
	var layer := StoryScene.new()
	layer.scene = scene
	add_child(layer)
	get_tree().paused = true
	layer.finished.connect(func() -> void: _play_story_queue(list))


func _on_upgrade_bought(id: String) -> void:
	if id == "back_room" or id == "upstairs":
		_room.refresh_staff()
		_refresh_upper()
		_set_space(_space, Vector2i(-1, -1))   # проходимость служебки меняется сразу
		var at := _room.position + CafeRoom.ORIGIN + Vector2(CafeRoom.STAFF_DOOR) * CafeRoom.T + Vector2(16, 0)
		Fx.burst(_actors, at, "puff", Color(0.85, 0.8, 0.7), 8, 80.0, -10.0, 0.9, 1.0, 120.0)


# ---------------------------------------------------------------- машины

func _on_car_spawned(car: Car) -> void:
	var cone := Sprite2D.new()   # пиксельный конус света фар
	cone.texture = PixelArt.cone(36, 12)
	cone.scale = Vector2(2, 2)
	cone.flip_h = car.dir < 0
	cone.modulate = Color(1.0, 0.92, 0.62, 0.0)
	cone.material = _add_mat
	_glow.add_child(cone)
	_glows.append({"node": cone, "base": 0.75, "cafe": false})
	car.halo = cone


func _on_car_removed(car: Car) -> void:
	if car.halo != null:
		_glows = _glows.filter(func(g: Dictionary) -> bool: return g["node"] != car.halo)
		car.halo.queue_free()


# ---------------------------------------------------------------- коты: заходят и выходят сами

## Раз в несколько секунд кот выбирает новую цель: погулять там же, где он, или перейти в другое место
## (с улицы в зал или из зала на улицу) — путь проходит через проём входа.
func _npc_tick(delta: float) -> void:
	for n in _npcs:
		var cat: CatWalker = n["cat"]
		if cat.is_moving():
			continue
		n["timer"] = float(n["timer"]) - delta
		if float(n["timer"]) > 0.0:
			continue
		var inside := _nav.is_interior(WorldNav.cell_of_feet(cat.position))
		var go_inside := (not inside) if randf() < 0.3 else inside
		cat.walk_to(WorldNav.feet_at(_nav.random_cell(go_inside)))
		n["timer"] = randf_range(2.0, 6.0)


# ---------------------------------------------------------------- ввод

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_F3:
		_toggle_zones()
		return
	if _shift_layer != null or _levels_layer != null or get_tree().paused or _fading:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press((_world.make_input_local(event) as InputEventMouse).position)
		else:
			_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		var p: Vector2 = (_world.make_input_local(event) as InputEventMouse).position
		var cell := WorldNav.cell_at(p)
		if cell != _last_cell:
			_last_cell = cell
			_player.walk_to(p)


func _on_press(p: Vector2) -> void:
	_pending = ""
	if _intro != null and _intro.on_tap(p):
		return
	for n in _npcs:
		var cat: CatWalker = n["cat"]
		if cat.visible and is_revealed(cat.position) and Rect2(cat.position + Vector2(-16, -34), Vector2(32, 40)).has_point(p):
			_talk(cat, p)
			return
	for b in _building_nodes:
		if not b.is_cafe and b.world_rect().has_point(p):
			_toast("Здесь закрыто", p)
			return
	if _space == SPACE_UP and _upper_rect.has_point(p) and p.distance_to(_player.position) < _iris_r:
		var d := (_spaces[_space] as InteriorSpace).portal_at(p - _upper_rect.position)
		if not d.is_empty():
			_tap_portal(d, p)
			return
	if _space == SPACE_CAFE and _interior_rect.has_point(p) and is_revealed(p):
		var sd := _room.staff_portal_at(_room.to_local(p))   # закрытая служебка или лестница в ней
		if not sd.is_empty():
			_tap_portal(sd, p)
			return
	if _space == SPACE_CAFE and _interior_rect.has_point(p) and is_revealed(p) and _room.counter_hit(_room.to_local(p)):
		_pending = "shift"
		if _in_counter_zone():
			_start_shift()
		else:
			_player.walk_to(_nav.counter_feet(CafeRoom.cell_at(_room.to_local(p)).x))
		return
	# обычный тап: идём туда; тап по фасаду кафе ведёт кота внутрь через проём
	_pressing = true
	_last_cell = WorldNav.cell_at(p)
	_player.walk_to(p)


func _talk(cat: CatWalker, world_p: Vector2) -> void:
	cat.hop()
	var fav: Dictionary = Data.drinks.get(String(cat.def.get("fav_drink", "")), {})
	var text := String(cat.def.get("name", "Кот"))
	if not fav.is_empty():
		text += ": обожаю " + String(fav["name"]).to_lower()
	_toast(text, world_p + Vector2(0, -50))


func _toast(text: String, world_p: Vector2) -> void:
	var s := _world.get_global_transform_with_canvas() * world_p
	Ui.toast(_ui, text, Vector2(clampf(s.x, 170.0, 190.0), clampf(s.y, 60.0, 600.0)))


## F3: показать зоны уровня поверх игры (ходьба, полосы машин, интерьер...).
## Сдвигает интерфейс вниз, если вырез камеры заходит в игровую область (обычно сдвиг 0).
func _apply_safe_area() -> void:
	var ins := SafeArea.current()
	if _ui is CanvasLayer:
		(_ui as CanvasLayer).offset = Vector2(0.0, ins.y)


## «Авто» заметило низкий FPS: качество понижено, лишние гости уходят с улицы.
func _on_quality_dropped() -> void:
	while _npcs.size() > 2:
		var n: Dictionary = _npcs.pop_back()
		(n["cat"] as Node).queue_free()
	Ui.toast(_ui, tr("Включено экономное качество"), Vector2(180, 150))


func _toggle_zones() -> void:
	StreetZone.show_in_game = not StreetZone.show_in_game
	_level.visible = StreetZone.show_in_game
	for z in _level.find_children("*", "StreetZone", true, false):
		(z as StreetZone)._refresh()


# ---------------------------------------------------------------- смена (готовка поверх города)

func _start_shift() -> void:
	if GameState.intro_stage < GameState.INTRO_DONE:   # до обучения смену не начать
		Ui.toast(_ui, tr("Сначала откроем кафе"), Vector2(180, 150))
		return
	_open_levels()


## Выбор смены: уровни со звёздами (смена пройдена, точность, скорость); следующий открывается после первой звезды на предыдущем.
## Уровни листаются по 4 на странице: у карточки две строки шрифта (28+28), больше четырёх по высоте не помещается.
func _open_levels() -> void:
	if _levels_layer != null or _shift_layer != null:
		return
	_player.stop()
	_levels_layer = CanvasLayer.new()
	_levels_layer.layer = 7
	add_child(_levels_layer)
	_build_levels_page()


func _build_levels_page() -> void:
	for ch in _levels_layer.get_children():
		ch.queue_free()
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.55)
	_levels_layer.add_child(dim)
	var n := Data.levels.size()
	var pages := int(ceil(float(n) / float(SHOP_PER_PAGE)))
	_levels_idx = clampi(_levels_idx, 0, pages - 1)
	var content_h := SHOP_PER_PAGE * CARD_H + (SHOP_PER_PAGE - 1) * CARD_GAP + Ui.BTN_GAP + Ui.BTN_H
	var h := Ui.page_height(content_h)
	var top := floorf((640.0 - h) / 2.0 / 2.0) * 2.0
	var x := 12.0
	var w := 336.0
	Ui.panel(Rect2(x, top, w, h), Ui.UI_WOOD, _levels_layer)
	Ui.label("Смены", Rect2(x, top + Ui.PAGE_PAD_TOP, w, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, _levels_layer, HORIZONTAL_ALIGNMENT_CENTER)
	var cx := x + Ui.PAGE_PAD_X
	var cw := w - 2.0 * Ui.PAGE_PAD_X
	var y := top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + Ui.PAGE_GAP
	var first := _levels_idx * SHOP_PER_PAGE
	for i in range(first, mini(n, first + SHOP_PER_PAGE)):
		var lv: Dictionary = Data.levels[i]
		var open := GameState.level_unlocked(i)
		var b := Ui.button("", Rect2(cx, y, cw, CARD_H), "", _levels_layer)
		b.disabled = not open
		b.modulate = Color.WHITE if open else Color(0.6, 0.6, 0.6)
		b.pressed.connect(_start_level.bind(i))
		var tw := cw - 12.0 - 12.0 - 66.0   # слева 12, справа три звезды (3×18 + зазоры) с отступом 12
		Ui.label("%d. %s" % [i + 1, String(lv["name"])], Rect2(cx + 12.0, y + 12.0, tw, Ui.LINE_H), Ui.FONT_SIZE, Ui.CREAM, _levels_layer, HORIZONTAL_ALIGNMENT_LEFT, true)
		var sub := "Пока закрыто" if not open else "%d котов, очередь %d" % [int(lv["customers"]), int(lv["queue"])]
		Ui.label(sub, Rect2(cx + 12.0, y + 12.0 + Ui.LINE_H, tw, Ui.LINE_H), Ui.FONT_SIZE, Ui.CREAM.darkened(0.15), _levels_layer, HORIZONTAL_ALIGNMENT_LEFT, true)
		var mask := GameState.level_mask(String(lv["id"]))
		for k in 3:   # три звезды: пройдено, точность, скорость
			var star := Sprite2D.new()
			star.texture = Fx.tex("bigstar")
			star.scale = Vector2(2, 2)
			star.position = Vector2(cx + cw - 12.0 - 9.0 - 44.0 + k * 22.0, y + Ui.EDGE + (CARD_H - Ui.EDGE - Ui.SHADOW_BUTTON) / 2.0)
			star.modulate = Color("ffd640") if (mask >> k) & 1 == 1 else Color("3d2c1c")
			_levels_layer.add_child(star)
		y += CARD_H + CARD_GAP
	var by := top + h - Ui.PAGE_PAD_BOTTOM - Ui.BTN_H
	if pages > 1:
		var half := (cw - Ui.BTN_GAP) / 2.0
		Ui.button("Назад", Rect2(cx, by, half, Ui.BTN_H), "undo", _levels_layer).pressed.connect(_close_levels)
		Ui.button("Дальше" if _levels_idx < pages - 1 else "Раньше", Rect2(cx + half + Ui.BTN_GAP, by, half, Ui.BTN_H), "", _levels_layer).pressed.connect(_levels_turn)
	else:
		Ui.button("Назад", Rect2(cx, by, cw, Ui.BTN_H), "undo", _levels_layer).pressed.connect(_close_levels)


func _levels_turn() -> void:
	var pages := int(ceil(float(Data.levels.size()) / float(SHOP_PER_PAGE)))
	_levels_idx = (_levels_idx + 1) % pages
	_build_levels_page()


func _close_levels() -> void:
	if _levels_layer != null:
		_levels_layer.queue_free()
		_levels_layer = null


func _start_level(index: int) -> void:
	if not GameState.level_unlocked(index):
		return
	_close_levels()
	if Economy.boosters_total() > 0 and GameState.intro_stage >= GameState.INTRO_DONE:   # есть бустеры — сначала выбор
		var prep := ShiftPrep.new()
		prep.level = Data.levels[index]
		add_child(prep)
		prep.start.connect(func(picked: Array[String]) -> void:
			for id in picked:
				Economy.use_booster(id)
			_open_shift(false, Data.levels[index], picked))
		prep.cancelled.connect(_open_levels)
		return
	_open_shift(false, Data.levels[index])


## Обучающая смена интро: только кофе и чай, пять заказов по сценарию, кнопки выхода нет.
func _start_tutorial() -> void:
	_open_shift(true)


func _open_shift(tutorial: bool, level := {}, picked: Array[String] = []) -> void:
	if _shift_layer != null:
		return
	_player.stop()
	_pending = ""
	GameState.save_game()
	Audio.music("shift")
	_shift_layer = CanvasLayer.new()
	_shift_layer.layer = 5
	add_child(_shift_layer)
	var shift: Node2D = load(Nav.BREW).instantiate()
	shift.embedded = true
	shift.level = level
	shift.boosters = picked
	shift.modulate = TimeOfDay.indoor()
	if tutorial:
		shift.tutorial = true
		shift.tutorial_sources = ["coffee", "tea"] as Array[String]
		shift.tutorial_orders = Intro.TUTORIAL_ORDERS.duplicate(true)
		shift.tutorial_finished.connect(_on_tutorial_finished)
	shift.closed.connect(_end_shift)
	_shift_layer.add_child(shift)
	_world.visible = false
	_sky_layer.visible = false
	_ui.visible = false


func _end_shift(served: int, earned: int) -> void:
	Audio.music("city")
	var level_id := ""
	if _shift_layer.get_child_count() > 0:
		level_id = String((_shift_layer.get_child(0).level as Dictionary).get("id", ""))
	_shift_layer.queue_free()
	_shift_layer = null
	_world.visible = true
	_sky_layer.visible = true
	_ui.visible = true
	if served > 0:
		GameState.register_shift()
	GameState.save_game()
	_refresh_star_button()
	if served > 0:
		Ui.toast(_ui, tr("Смена: подано %d, +%d") % [served, earned], Vector2(180, 150))
	if level_id != "" and GameState.level_star_count(level_id) >= 1:
		_play_stories("level", level_id)   # конец главы: сюжетная сцена
	if GameState.shifts_played == 3 and served > 0 and GameState.upgrades.is_empty():   # третья смена: пора в магазин улучшений
		get_tree().create_timer(1.6).timeout.connect(func() -> void: Ui.toast(_ui, tr("Загляни в «Улучшения» в меню!"), Vector2(180, 210)))


# ---------------------------------------------------------------- меню в игре

func _open_menu() -> void:
	_menu_page("main")
	_menu.visible = true
	get_tree().paused = true


func _close_menu() -> void:
	_menu.visible = false
	get_tree().paused = false


func _open_decorate() -> void:
	if GameState.intro_stage < GameState.INTRO_DONE:
		Ui.toast(_menu, "Сначала откроем кафе", Vector2(180, 560))
		return
	get_tree().paused = false
	GameState.save_game()
	Nav.go(self, Nav.DECORATE)
