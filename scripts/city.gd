extends Node2D
## Игра: улица с кафе. Игра начинается внутри кафе: можно ходить по залу, встать у стойки и отработать смену
## (готовка идёт поверх города, без смены сцены), выйти на улицу и вернуться.
## Кафе — «рентген»: пока игрок внутри, фасад становится прозрачным и виден интерьер; вышел — интерьер
## не рисуется, и мы видим обычное здание. Меню — внутри игры (кнопка-шестерёнка).
##
## Слои мира (все в одной канве, камера едет за котом):
##   Outdoor  — земля, здания, машины, прохожие; окрашивается светом суток (TimeOfDay.ambient)
##   Indoor   — интерьер кафе; свой, более тёплый свет (ночью внутри горят лампы)
##   Glow     — свечение (окна, фонари, фары): складывается поверх и не затемняется ночью
## Небо рисуется отдельным слоем под миром.

const BASE_Y := 388.0                 # низ зданий (линия, где фасады встают на тротуар)
const WORLD_W := 1440.0
const WALK_BAND := Rect2(24, 410, WORLD_W - 48, 34)   # где ходят лапки на тротуаре
const ROAD_TOP := 460.0
const ROAD_BOTTOM := 632.0
const LANE_WEST_Y := 540.0            # низ колёс машин, едущих на запад (верхняя полоса)
const LANE_EAST_Y := 616.0            # ...на восток (нижняя)
const PX := 2

const CAFE := "building4"
const LOTS := [["building3", 24.0], ["building4", 252.0], ["building1", 616.0], ["building2", 836.0], ["building7", 1182.0]]
# id, x, y лапок. Фонари стоят в просветах между домами.
const PROPS := [
	["tree3", 8.0, 428.0], ["vending_beige", 196.0, 404.0], ["lamp", 240.0, 448.0], ["lamp", 604.0, 448.0],
	["hydrant", 646.0, 444.0], ["bush1", 700.0, 404.0], ["bush2", 764.0, 404.0], ["trashbin", 796.0, 412.0],
	["lamp", 824.0, 448.0], ["vending_red", 884.0, 404.0], ["plant3", 1010.0, 404.0], ["lamp", 1170.0, 448.0],
	["tree2", 1214.0, 436.0], ["vending_green", 1340.0, 404.0], ["tree1", 1412.0, 432.0],
]
const WAITER_DEF := {"sprite": "cat-waiter-front.png", "tint": "#ffffff"}

const SIDEWALK := Color("b9b2aa")
const SIDEWALK_LINE := Color("a39c95")
const CURB := Color("d6cfc7")
const ASPHALT := Color("464a55")
const ASPHALT_LINE := Color("e8e2c8")

var _cafe_pos := Vector2.ZERO           # левый верх фасада кафе в мире
var _door_x := 0.0
var _inside := true
var _xray := 1.0                        # 0 — фасад закрыт, 1 — прозрачный, виден интерьер
var _xray_tween: Tween
var _pending := ""                      # действие, которое выполнится, когда кот дойдёт: "shift" | "exit" | "enter"
var _pressing := false
var _last_cell := Vector2i(-1, -1)

var _sky_layer: CanvasLayer
var _sky: CitySky
var _world: Node2D
var _outdoor: Node2D
var _buildings: Node2D
var _actors: Node2D                     # прохожие, машины, реквизит, игрок снаружи — сортируются по y
var _indoor: Node2D
var _room: CafeRoom
var _glow: Node2D
var _camera: Camera2D
var _player: CatWalker
var _street_nav: StreetNav
var _shells: Dictionary = {}            # id здания -> Sprite2D
var _visitors: Array[CatWalker] = []    # гости внутри кафе
var _walkers: Array[CatWalker] = []     # прохожие снаружи
var _cars: Array[Car] = []
var _lane_timer := [1.0, 3.0]
var _glows: Array[Dictionary] = []      # {"node", "base", "cafe"}: свечение, зависящее от ночи
var _halo_tex: GradientTexture2D
var _add_mat: CanvasItemMaterial

var _ui: CanvasLayer
var _coins_label: Label
var _clock_btn: Button
var _btn_shift: Button
var _btn_exit: Button
var _btn_enter: Button
var _menu: CanvasLayer
var _shift_layer: CanvasLayer


func _ready() -> void:
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo_tex = _make_halo()
	_build_sky()
	_build_world()
	_build_cafe()
	_build_street()
	_build_cats()
	_build_camera()
	_build_ui()
	_build_menu()
	for _i in 3:
		_spawn_car(1 if randf() < 0.5 else -1, randf_range(100.0, WORLD_W - 100.0))
	_set_inside(GameState.city_inside, true)
	_apply_daylight()


# ---------------------------------------------------------------- построение

func _make_halo() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


func _build_sky() -> void:
	_sky_layer = CanvasLayer.new()
	_sky_layer.layer = -10
	add_child(_sky_layer)
	_sky = CitySky.new()
	_sky_layer.add_child(_sky)


func _build_world() -> void:
	_world = Node2D.new()
	add_child(_world)
	_outdoor = Node2D.new()
	_outdoor.draw.connect(_draw_ground)
	_world.add_child(_outdoor)
	_buildings = Node2D.new()
	_outdoor.add_child(_buildings)
	_actors = Node2D.new()
	_actors.y_sort_enabled = true
	_outdoor.add_child(_actors)
	_indoor = Node2D.new()
	_world.add_child(_indoor)
	_glow = Node2D.new()
	_world.add_child(_glow)
	_street_nav = StreetNav.new(WALK_BAND)


## Тротуар, бордюр, дорога с разметкой, зебра. Плитка тротуара совпадает с сеткой 32 px.
func _draw_ground() -> void:
	var sw_h := ROAD_TOP - BASE_Y
	_outdoor.draw_rect(Rect2(0, BASE_Y, WORLD_W, sw_h), SIDEWALK)
	for x in range(0, int(WORLD_W), 32):
		_outdoor.draw_rect(Rect2(x, BASE_Y, 2, sw_h), SIDEWALK_LINE)
	for y in range(int(BASE_Y), int(ROAD_TOP) - 8, 32):
		_outdoor.draw_rect(Rect2(0, y, WORLD_W, 2), SIDEWALK_LINE)
	_outdoor.draw_rect(Rect2(0, BASE_Y, WORLD_W, 6), SIDEWALK_LINE.darkened(0.25))   # тень под фасадами
	_outdoor.draw_rect(Rect2(0, ROAD_TOP - 8, WORLD_W, 8), CURB)
	_outdoor.draw_rect(Rect2(0, ROAD_TOP - 2, WORLD_W, 2), CURB.darkened(0.35))
	_outdoor.draw_rect(Rect2(0, ROAD_TOP, WORLD_W, ROAD_BOTTOM - ROAD_TOP), ASPHALT)
	for x in range(0, int(WORLD_W), 64):
		_outdoor.draw_rect(Rect2(x, (LANE_WEST_Y + LANE_EAST_Y) / 2.0 - 44.0, 32, 4), ASPHALT_LINE)
	_outdoor.draw_rect(Rect2(0, ROAD_BOTTOM, WORLD_W, 8), CURB)
	for i in 6:   # пешеходный переход
		_outdoor.draw_rect(Rect2(700 + i * 20, ROAD_TOP + 4, 12, ROAD_BOTTOM - ROAD_TOP - 8), Color(ASPHALT_LINE, 0.8))


func _build_cafe() -> void:
	for lot in LOTS:
		var id: String = lot[0]
		var tex := load("res://assets/street/buildings/%s.png" % id) as Texture2D
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.scale = Vector2(PX, PX)
		sp.position = Vector2(float(lot[1]), BASE_Y - tex.get_height() * PX)
		_buildings.add_child(sp)
		_shells[id] = sp
		_add_window_glows(id, sp.position)
		if id == CAFE:
			_cafe_pos = sp.position
			_door_x = sp.position.x + tex.get_width() * PX / 2.0
	# интерьер: ровно в габарите фасада, пол по низу здания
	_indoor.position = Vector2(_cafe_pos.x + 10.0, BASE_Y - CafeRoom.ROOM_SIZE.y)
	_room = CafeRoom.new()
	_indoor.add_child(_room)
	_room.set_layout(GameState.layout)
	# чашка над стойкой: здесь начинается смена
	var cup := Sprite2D.new()
	cup.texture = Ui.atlas(preload("res://assets/cafe/drinks-and-pastries.png"), Rect2(32, 16, 16, 16))
	cup.position = Vector2(48, 28)
	cup.scale = Vector2(PX, PX)
	cup.z_index = 5
	_room.add_child(cup)
	var t := create_tween().set_loops()
	t.tween_property(cup, "position:y", 20.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(cup, "position:y", 28.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Свет в окнах фасада ночью: часть окон горит, у кафе — все витрины.
func _add_window_glows(id: String, origin: Vector2) -> void:
	var wins: Array = Data.street["buildings"][id]["windows"]
	for i in wins.size():
		var w: Array = wins[i]
		var lit := id == CAFE or hash("%s%d" % [id, i]) % 10 < 7
		if not lit:
			continue
		var r := ColorRect.new()
		r.position = origin + Vector2(float(w[0]), float(w[1])) * PX
		r.size = Vector2(float(w[2]), float(w[3])) * PX
		r.color = Color(1.0, 0.78, 0.36)
		r.material = _add_mat
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.add_child(r)
		_glows.append({"node": r, "base": 0.55, "cafe": id == CAFE})


func _build_street() -> void:
	for p in PROPS:
		var id: String = p[0]
		var tex := load("res://assets/street/props/%s.png" % id) as Texture2D
		var n := Node2D.new()
		n.position = Vector2(float(p[1]), float(p[2]))
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.scale = Vector2(PX, PX)
		sp.position = Vector2(-tex.get_width(), -tex.get_height() * PX)
		n.add_child(sp)
		_actors.add_child(n)
		if id == "lamp":
			_add_halo(n.position + Vector2(0, -tex.get_height() * PX + 14.0), 2.6, 0.75, Color(1.0, 0.8, 0.45))
			_add_halo(n.position + Vector2(0, -8.0), 3.2, 0.35, Color(1.0, 0.8, 0.45), 0.35)


## Круглое свечение; flatten < 1 сплющивает его в эллипс (пятно на асфальте).
func _add_halo(pos: Vector2, size: float, base: float, color: Color, flatten := 1.0) -> Sprite2D:
	var h := Sprite2D.new()
	h.texture = _halo_tex
	h.position = pos
	h.scale = Vector2(size, size * flatten)
	h.modulate = Color(color, 0.0)
	h.material = _add_mat
	_glow.add_child(h)
	_glows.append({"node": h, "base": base, "cafe": false})
	return h


func _build_cats() -> void:
	_player = CatWalker.new()
	_player.arrived.connect(_on_player_arrived)
	_actors.add_child(_player)
	_player.setup(_street_nav, WAITER_DEF)
	for def in Data.cats:
		var v := CatWalker.new()   # гости кафе
		v.wander = true
		_room.actors.add_child(v)
		v.setup(_room, def)
		v.position = _room.random_free_point()
		_visitors.append(v)
		var w := CatWalker.new()   # прохожие
		w.wander = true
		_actors.add_child(w)
		w.setup(_street_nav, def)
		w.position = Vector2(randf_range(WALK_BAND.position.x, WALK_BAND.end.x), randf_range(WALK_BAND.position.y, WALK_BAND.end.y))
		_walkers.append(w)


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.limit_left = 0
	_camera.limit_right = int(WORLD_W)
	_camera.limit_top = 0
	_camera.limit_bottom = 640
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 6.0
	_camera.position = Vector2(_door_x, 320)
	add_child(_camera)
	_camera.make_current()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 1
	add_child(_ui)
	Ui.panel(Rect2(8, 8, 104, 40), Ui.UI_CREAM, _ui)
	var coin := Sprite2D.new()
	coin.texture = Ui.icon("coin")
	coin.position = Vector2(28, 28)
	coin.scale = Vector2(2, 2)
	_ui.add_child(coin)
	_coins_label = Ui.label(str(GameState.coins), Rect2(44, 10, 64, 36), Ui.FONT_SIZE, Ui.INK, _ui, HORIZONTAL_ALIGNMENT_LEFT)
	GameState.coins_changed.connect(_on_coins_changed)  # метод, а не лямбда: отпишется вместе со сценой
	# часы: нажатие перематывает время на час
	_clock_btn = Ui.button("", Rect2(116, 8, 112, 40), "", _ui, false, Ui.UI_CREAM)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_clock_btn.add_theme_color_override(c, Ui.INK)
	_clock_btn.add_theme_color_override("font_outline_color", Ui.CREAM)
	_clock_btn.pressed.connect(TimeOfDay.skip.bind(1.0))
	var gear := Ui.button("", Rect2(300, 8, 52, 40), "gear", _ui)
	gear.pressed.connect(_open_menu)
	_btn_shift = Ui.button("Смена", Rect2(88, 568, 184, 56), "play", _ui)
	_btn_shift.pressed.connect(_start_shift)
	_btn_exit = Ui.button("Выйти", Rect2(88, 568, 184, 56), "exit", _ui)
	_btn_exit.pressed.connect(_exit_cafe)
	_btn_enter = Ui.button("Войти", Rect2(88, 568, 184, 56), "home", _ui)
	_btn_enter.pressed.connect(_enter_cafe)


## Меню внутри игры: пауза, продолжить / украшение / время / выход.
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
	var h := 296.0 if pc else 240.0
	var top := 320.0 - h / 2.0
	Ui.panel(Rect2(30, top, 300, h), Ui.UI_WOOD, _menu)
	Ui.label("Меню", Rect2(30, top + 14, 300, 36), Ui.FONT_SIZE, Ui.INK, _menu)
	var resume := Ui.button("Продолжить", Rect2(54, top + 56, 252, 52), "play", _menu)
	resume.pressed.connect(_close_menu)
	var deco := Ui.button("Украшение", Rect2(54, top + 114, 252, 52), "brush", _menu)
	deco.pressed.connect(_open_decorate)
	var skip := Ui.button("Время +3 ч", Rect2(54, top + 172, 252, 52), "gear", _menu)
	skip.pressed.connect(TimeOfDay.skip.bind(3.0))
	if pc:
		var quit := Ui.button("Выход", Rect2(54, top + 230, 252, 52), "exit", _menu)
		quit.pressed.connect(get_tree().quit)


# ---------------------------------------------------------------- вход / выход, рентген

## inside — игрок в кафе. instant — без анимации (при старте сцены).
func _set_inside(inside: bool, instant := false) -> void:
	_inside = inside
	GameState.city_inside = inside
	_pending = ""
	_player.stop()
	if inside:
		_player.reparent(_room.actors, false)
		_player.nav = _room
		_player.position = CafeRoom.feet_at(Vector2i(4, 4)) if instant else CafeRoom.feet_at(CafeRoom.SPAWN_CELL)
	else:
		_player.reparent(_actors, false)
		_player.nav = _street_nav
		_player.position = Vector2(_door_x, WALK_BAND.position.y + 6.0)
	if _xray_tween:
		_xray_tween.kill()
	var target := 1.0 if inside else 0.0
	if instant:
		_xray = target
	else:
		_xray_tween = create_tween()
		_xray_tween.tween_property(self, "_xray", target, 0.4)


func _enter_cafe() -> void:
	_set_inside(true)


func _exit_cafe() -> void:
	_set_inside(false)


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	_apply_daylight()
	_update_traffic(delta)
	_update_camera()
	_clock_btn.text = TimeOfDay.clock_text()
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
	_update_actions()


## Свет суток: улица окрашивается, интерьер светит по-своему, свечение растёт к ночи; рентген прячет интерьер.
func _apply_daylight() -> void:
	var night := TimeOfDay.night()
	_outdoor.modulate = TimeOfDay.ambient()
	_indoor.visible = _xray > 0.01
	_indoor.modulate = Color(TimeOfDay.indoor(), _xray)
	(_shells[CAFE] as Sprite2D).modulate.a = 1.0 - _xray
	for g in _glows:
		var f := (1.0 - _xray) if g["cafe"] else 1.0
		(g["node"] as CanvasItem).modulate.a = float(g["base"]) * night * f


func _update_camera() -> void:
	var tx := _room_center_x() if _inside else _player.position.x
	_camera.position = Vector2(clampf(tx, 180.0, WORLD_W - 180.0), 320.0)
	_sky.camera_x = _camera.get_screen_center_position().x


func _room_center_x() -> float:
	return _indoor.position.x + CafeRoom.ROOM_SIZE.x / 2.0


## Где игрок относительно кнопок действий: у двери снаружи, у стойки или у коврика внутри.
func _update_actions() -> void:
	var near_door_out := not _inside and absf(_player.position.x - _door_x) < 40.0
	var at_counter := _inside and _room.in_counter_zone(_player.position)
	var at_door := _inside and _room.in_door_zone(_player.position)
	_btn_enter.visible = near_door_out
	_btn_shift.visible = at_counter
	_btn_exit.visible = at_door and not at_counter


func _on_player_arrived() -> void:
	match _pending:
		"shift":
			if _inside and _room.in_counter_zone(_player.position):
				_start_shift()
		"exit":
			if _inside and _room.in_door_zone(_player.position):
				_exit_cafe()
		"enter":
			if not _inside and absf(_player.position.x - _door_x) < 40.0:
				_enter_cafe()
	_pending = ""


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)


# ---------------------------------------------------------------- машины

func _update_traffic(delta: float) -> void:
	for lane in 2:
		_lane_timer[lane] -= delta
		if _lane_timer[lane] <= 0.0:
			_lane_timer[lane] = randf_range(3.0, 8.0)
			_spawn_car(1 if lane == 0 else -1)
	for car in _cars.duplicate():
		if car.position.x < -300.0 or car.position.x > WORLD_W + 300.0:
			_cars.erase(car)
			car.halo.queue_free()
			_glows = _glows.filter(func(g: Dictionary) -> bool: return g["node"] != car.halo)
			car.queue_free()
		else:
			car.halo.position = car.position + car.headlight_offset()


func _spawn_car(dir: int, x := INF) -> void:
	var def: Dictionary = (Data.street["vehicles"] as Array).pick_random()
	var car := Car.new()
	car.setup(def, dir)
	var edge := -car.width() if dir > 0 else WORLD_W + car.width()
	car.position = Vector2(edge if x == INF else x, LANE_EAST_Y if dir > 0 else LANE_WEST_Y)
	car.speed = 55.0 if String(def["id"]).begins_with("bus") else randf_range(80.0, 120.0)
	_actors.add_child(car)
	car.halo = _add_halo(car.position + car.headlight_offset(), 1.6, 0.8, Color(1.0, 0.9, 0.6), 0.6)
	_cars.append(car)


# ---------------------------------------------------------------- ввод

func _unhandled_input(event: InputEvent) -> void:
	if _shift_layer != null or get_tree().paused:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press((_world.make_input_local(event) as InputEventMouse).position)
		else:
			_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		var p: Vector2 = (_world.make_input_local(event) as InputEventMouse).position
		var cell := Vector2i(int(p.x / CafeRoom.T), int(p.y / CafeRoom.T))
		if cell != _last_cell:
			_last_cell = cell
			_player.walk_to(_room.to_local(p) if _inside else p)


func _on_press(p: Vector2) -> void:
	_pending = ""
	if _inside:
		_press_inside(_room.to_local(p), p)
	else:
		_press_outside(p)


func _press_inside(lp: Vector2, world_p: Vector2) -> void:
	if not Rect2(Vector2.ZERO, CafeRoom.ROOM_SIZE).has_point(lp):
		return
	for v in _visitors:
		if Rect2(v.position + Vector2(-16, -34), Vector2(32, 40)).has_point(lp):
			_talk(v, world_p)
			return
	if _room.counter_hit(lp):
		_pending = "shift"
		if _room.in_counter_zone(_player.position):
			_start_shift()
		else:
			_player.walk_to(CafeRoom.feet_at(Vector2i(clampi(CafeRoom.cell_at(lp).x, 0, 2), 0)))
		return
	if CafeRoom.DOOR_CELLS.has_point(CafeRoom.cell_at(lp)) and lp.y >= CafeRoom.ORIGIN.y:
		_pending = "exit"
		if _room.in_door_zone(_player.position):
			_exit_cafe()
		else:
			_player.walk_to(lp)
		return
	_pressing = true
	_last_cell = Vector2i(int(world_p.x / CafeRoom.T), int(world_p.y / CafeRoom.T))
	_player.walk_to(lp)


func _press_outside(p: Vector2) -> void:
	for w in _walkers:
		if Rect2(w.position + Vector2(-16, -34), Vector2(32, 40)).has_point(p):
			_talk(w, p)
			return
	var door := Rect2(_door_x - 48.0, BASE_Y - 110.0, 96.0, 130.0)
	if door.has_point(p):
		_pending = "enter"
		if absf(_player.position.x - _door_x) < 40.0:
			_enter_cafe()
		else:
			_player.walk_to(Vector2(_door_x, WALK_BAND.position.y + 6.0))
		return
	if p.y < BASE_Y + 4.0 and p.y > BASE_Y - 120.0:
		_toast("Здесь закрыто", p)
		return
	_pressing = true
	_last_cell = Vector2i(int(p.x / CafeRoom.T), int(p.y / CafeRoom.T))
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


# ---------------------------------------------------------------- смена (готовка поверх города)

func _start_shift() -> void:
	if _shift_layer != null:
		return
	_player.stop()
	_pending = ""
	GameState.save_game()
	_shift_layer = CanvasLayer.new()
	_shift_layer.layer = 5
	add_child(_shift_layer)
	var shift: Node2D = load(Nav.BREW).instantiate()
	shift.embedded = true
	shift.modulate = TimeOfDay.indoor()
	shift.closed.connect(_end_shift)
	_shift_layer.add_child(shift)
	_world.visible = false
	_sky_layer.visible = false
	_ui.visible = false


func _end_shift(served: int, earned: int) -> void:
	_shift_layer.queue_free()
	_shift_layer = null
	_world.visible = true
	_sky_layer.visible = true
	_ui.visible = true
	GameState.save_game()
	if served > 0:
		Ui.toast(_ui, "Смена: подано %d, +%d" % [served, earned], Vector2(180, 150))


# ---------------------------------------------------------------- меню в игре

func _open_menu() -> void:
	_menu.visible = true
	get_tree().paused = true


func _close_menu() -> void:
	_menu.visible = false
	get_tree().paused = false


func _open_decorate() -> void:
	get_tree().paused = false
	GameState.save_game()
	Nav.go(self, Nav.DECORATE)
