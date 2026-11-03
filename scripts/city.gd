extends Node2D
## Игра: улица с кафе. Игра начинается внутри кафе: можно ходить по залу, встать у стойки и отработать смену
## (готовка идёт поверх города, без смены сцены), выйти на улицу и вернуться.
##
## Всё бесшовно: у кота один узел и один мир. Дверей нет — из проёма входа сразу тротуар, путь с улицы в зал
## и обратно строится обычным поиском пути (WorldNav). Кафе — «рентген»: чем глубже кот в здании, тем прозрачнее фасад
## и виднее интерьер; вышел — интерьер не рисуется. Так же заходят и выходят гуляющие коты.
##
## Улица (здания, предметы, зоны ходьбы, полосы машин, место интерьера) лежит в scenes/street.tscn — её правят в редакторе.
## Слои мира: Ground, Buildings, Room (интерьер: пол, стена, коврики), Actors (всё, что сортируется по y: мебель,
## коты, машины, предметы), Glow (свечение: окна, фонари, фары — не затемняется ночью). Небо — отдельный слой под миром.

const STREET_SCENE := "res://scenes/street.tscn"
const PX := 2
const T := 32
const WAITER_DEF := {"sprite": "cat-waiter-front.png", "tint": "#ffffff"}
const DEPTH_ZONE := 44.0   # на сколько пикселей вглубь здания фасад прозрачнеет полностью

const SIDEWALK := Color("b9b2aa")
const SIDEWALK_LINE := Color("a39c95")
const CURB := Color("d6cfc7")
const ASPHALT := Color("464a55")
const ASPHALT_LINE := Color("e8e2c8")

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
var _nav: WorldNav
var _cafe: StreetBuilding
var _building_nodes: Array[StreetBuilding] = []
var _interior_rect := Rect2()           # габарит интерьера в мире
var _xray := 0.0                        # 0 — фасад закрыт, 1 — прозрачный, виден интерьер
var _player: CatWalker
var _npcs: Array[Dictionary] = []       # {"cat": CatWalker, "timer": float}
var _traffic: Traffic
var _glows: Array[Dictionary] = []      # {"node", "base", "cafe"}: свечение, зависящее от ночи
var _halo_tex: GradientTexture2D
var _add_mat: CanvasItemMaterial
var _pending := ""                      # действие по прибытии: "shift"
var _pressing := false
var _last_cell := Vector2i(-1, -1)

var _ui: CanvasLayer
var _coins_label: Label
var _clock_btn: Button
var _btn_shift: Button
var _menu: CanvasLayer
var _shift_layer: CanvasLayer


func _ready() -> void:
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo_tex = _make_halo()
	_build_sky()
	_build_world()
	_build_cats()
	_build_camera()
	_build_ui()
	_build_menu()
	_update_xray(10.0)
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


## Собирает мир из уровня scenes/street.tscn: здания и предметы переезжают в свои слои, зоны остаются в _level.
func _build_world() -> void:
	_level = (load(STREET_SCENE) as PackedScene).instantiate() as StreetLevel
	_world_size = _level.world_size
	_world = Node2D.new()
	add_child(_world)
	_ground = Node2D.new()
	_ground.draw.connect(_draw_ground)
	_world.add_child(_ground)
	_buildings = Node2D.new()
	_world.add_child(_buildings)
	_room = CafeRoom.new()
	_world.add_child(_room)
	_actors = Node2D.new()
	_actors.y_sort_enabled = true
	_world.add_child(_actors)
	_glow = Node2D.new()
	_world.add_child(_glow)
	add_child(_level)
	_level.visible = false   # зоны не рисуются (F3 включает показ)
	_level.z_index = 100

	for node in _level.get_node("Buildings").get_children():
		var b := node as StreetBuilding
		if b == null:
			continue
		b.reparent(_buildings)
		_building_nodes.append(b)
		_add_window_glows(b)
		if b.is_cafe:
			_cafe = b

	var interior := _level.zones(StreetZone.Kind.CAFE_INTERIOR)
	var at := (interior[0] as StreetZone).global_position if not interior.is_empty() else Vector2(256, 64)
	# пол кафе обязан лечь в сетку мира: иначе клетки зала и тротуара не совпадут
	_room.position = Vector2(snappedf(at.x, T), snappedf(at.y + CafeRoom.ORIGIN.y, T) - CafeRoom.ORIGIN.y)
	_interior_rect = Rect2(_room.position, CafeRoom.ROOM_SIZE)
	_room.external_actors = _actors
	_room.set_layout(GameState.layout)

	var block_cells: Array[Vector2i] = []
	for node in _level.get_node("Props").get_children():
		var prop := node as StreetProp
		if prop == null:
			continue
		prop.reparent(_actors)
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
	cup.z_index = 5
	_room.add_child(cup)
	var t := create_tween().set_loops()
	t.tween_property(cup, "position:y", 20.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(cup, "position:y", 28.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Тротуар, бордюр, дорога с разметкой, зебра — всё по зонам уровня. Плитка тротуара совпадает с сеткой 32 px.
func _draw_ground() -> void:
	for z in _level.zones(StreetZone.Kind.SIDEWALK):
		var r := z.world_rect()
		_ground.draw_rect(r, SIDEWALK)
		for x in range(ceili(r.position.x / T) * T, int(r.end.x), T):
			_ground.draw_rect(Rect2(x, r.position.y, 2, r.size.y), SIDEWALK_LINE)
		for y in range(ceili(r.position.y / T) * T, int(r.end.y) - 8, T):
			_ground.draw_rect(Rect2(r.position.x, y, r.size.x, 2), SIDEWALK_LINE)
		_ground.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 6), SIDEWALK_LINE.darkened(0.25))   # тень под фасадами
		_ground.draw_rect(Rect2(r.position.x, r.end.y - 8, r.size.x, 8), CURB)
		_ground.draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 2), CURB.darkened(0.35))
	for z in _level.zones(StreetZone.Kind.ROAD):
		var r := z.world_rect()
		_ground.draw_rect(r, ASPHALT)
		_ground.draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 8), CURB)
	for z in _level.zones(StreetZone.Kind.LANE_WEST):   # разделительная между встречными полосами — под нижним краем верхней
		var r := z.world_rect()
		for x in range(ceili(r.position.x / 64.0) * 64, int(r.end.x), 64):
			_ground.draw_rect(Rect2(x, r.end.y + 4, 32, 4), ASPHALT_LINE)
	for z in _level.zones(StreetZone.Kind.CROSSWALK):
		var r := z.world_rect()
		for i in int(r.size.x / 20.0):
			_ground.draw_rect(Rect2(r.position.x + i * 20, r.position.y + 4, 12, r.size.y - 8), Color(ASPHALT_LINE, 0.8))


## Свет в окнах фасада ночью: часть окон горит, у кафе — все витрины.
func _add_window_glows(b: StreetBuilding) -> void:
	var id := b.building_id()
	if not Data.street["buildings"].has(id):
		return
	var wins: Array = Data.street["buildings"][id]["windows"]
	var origin := b.world_rect().position
	for i in wins.size():
		var w: Array = wins[i]
		if not (b.is_cafe or hash("%s%d" % [id, i]) % 10 < 7):
			continue
		var r := ColorRect.new()
		r.position = origin + Vector2(float(w[0]), float(w[1])) * PX
		r.size = Vector2(float(w[2]), float(w[3])) * PX
		r.color = Color(1.0, 0.78, 0.36)
		r.material = _add_mat
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.add_child(r)
		_glows.append({"node": r, "base": 0.55, "cafe": b.is_cafe})


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
	_player.setup(_nav, WAITER_DEF)
	var room_cell := _nav.interior_cells().position
	if GameState.city_inside:
		_player.position = WorldNav.feet_at(room_cell + Vector2i(5, 4))
	else:   # на тротуаре у проёма входа
		_player.position = WorldNav.feet_at(room_cell + Vector2i(CafeRoom.ENTRANCE_CELLS.position.x, CafeRoom.ROWS))
	# коты-посетители: половина в зале, половина на улице; дальше сами заходят и выходят
	for i in 4:
		var cat := CatWalker.new()
		_actors.add_child(cat)
		cat.setup(_nav, Data.cats[i % Data.cats.size()])
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
	_camera.position = Vector2(_player.position.x, _world_size.y / 2.0)
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


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	_traffic.update(delta)
	_npc_tick(delta)
	_update_xray(delta)
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
	_btn_shift.visible = _in_counter_zone()


## Насколько глубоко в здание зашли лапки: 0 — снаружи (у фасада и дальше), 1 — полностью внутри.
func _depth(feet: Vector2) -> float:
	if feet.x < _interior_rect.position.x or feet.x > _interior_rect.end.x:
		return 0.0
	return clampf((_interior_rect.end.y - feet.y + 6.0) / DEPTH_ZONE, 0.0, 1.0)


## Рентген плавно следует за глубиной игрока: вошёл — фасад прозрачнеет, вышел — закрывается.
func _update_xray(delta: float) -> void:
	_xray = lerpf(_xray, _depth(_player.position), 1.0 - exp(-12.0 * delta))


## Свет суток по узлам: улица — ambient, интерьер — тёплый свет кафе; кот, зашедший в здание, плавно меняет свет;
## чужие коты и мебель внутри не рисуются, пока интерьер скрыт (рентген).
func _apply_daylight() -> void:
	var amb := TimeOfDay.ambient()
	var ind := TimeOfDay.indoor()
	var night := TimeOfDay.night()
	_ground.modulate = amb
	_buildings.modulate = amb
	_room.visible = _xray > 0.01
	_room.modulate = Color(ind, _xray)
	_cafe.modulate.a = 1.0 - _xray
	for ch in _actors.get_children():
		if ch is CatWalker:
			var d := _depth(ch.position)
			var a := 1.0 if ch == _player else lerpf(1.0, _xray, d)
			ch.modulate = Color(amb.lerp(ind, d), a)
			ch.visible = a > 0.01
		elif ch.has_meta("interior"):
			ch.modulate = Color(ind, _xray)
			ch.visible = _xray > 0.01
		else:
			ch.modulate = amb
	for g in _glows:
		var f := (1.0 - _xray) if g["cafe"] else 1.0
		(g["node"] as CanvasItem).modulate.a = float(g["base"]) * night * f
	for car in _traffic.cars():
		if car.halo != null:
			car.halo.position = car.position + car.headlight_offset()


func _update_camera() -> void:
	_camera.position = Vector2(clampf(_player.position.x, 180.0, _world_size.x - 180.0), _world_size.y / 2.0)
	_sky.camera_x = _camera.get_screen_center_position().x


func _in_counter_zone() -> bool:
	return _interior_rect.has_point(_player.position) and _room.in_counter_zone(_room.to_local(_player.position))


func _on_player_arrived() -> void:
	if _pending == "shift" and _in_counter_zone():
		_start_shift()
	_pending = ""


func _on_coins_changed(value: int) -> void:
	_coins_label.text = str(value)


# ---------------------------------------------------------------- машины

func _on_car_spawned(car: Car) -> void:
	car.halo = _add_halo(car.position + car.headlight_offset(), 1.6, 0.8, Color(1.0, 0.9, 0.6), 0.6)


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
	if _shift_layer != null or get_tree().paused:
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
	for n in _npcs:
		var cat: CatWalker = n["cat"]
		if cat.visible and cat.modulate.a > 0.4 and Rect2(cat.position + Vector2(-16, -34), Vector2(32, 40)).has_point(p):
			_talk(cat, p)
			return
	for b in _building_nodes:
		if not b.is_cafe and b.world_rect().has_point(p):
			_toast("Здесь закрыто", p)
			return
	if _xray > 0.35 and _interior_rect.has_point(p) and _room.counter_hit(_room.to_local(p)):
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
func _toggle_zones() -> void:
	StreetZone.show_in_game = not StreetZone.show_in_game
	_level.visible = StreetZone.show_in_game
	for z in _level.find_children("*", "StreetZone", true, false):
		(z as StreetZone)._refresh()


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
