class_name Intro
extends Node
## Интро в городе. Стадия 1 — катсцена: Мяу открывает заклинившие ставни (2 тапа, «Ставни — пяткой!»).
## Стадия 2 — расчистка тёмного кафе: 21 тап по 15 объектам (паутина, пыль, шторка на окне, 3 коробки, покрывало на стойке,
## кофемашина, стол, стул); шкала «Кофейня N% готова», свет в зале растёт. Дальше город запускает обучающую смену.
## Прогресс хранится в GameState.intro_cleaned (по объектам), поэтому выход из игры посреди расчистки безопасен.

signal cleanup_finished

const SHUTTER_RECT := Rect2(440, 632, 208, 72)   # витрина кафе в мире: заслонка закрывает проём и окна
const DARK := Color(0.40, 0.40, 0.52)            # свет в зале до расчистки
const TOTAL_TAPS := 21

## Объекты расчистки (координаты в системе комнаты, 320×320).
const OBJECTS := [
	{"id": "web_0", "kind": "web", "pos": Vector2(14, 14), "dir": Vector2i(1, 1), "radius": 46.0, "taps": 1, "line": "Апчхи! Пыль со стажем."},
	{"id": "web_1", "kind": "web", "pos": Vector2(306, 14), "dir": Vector2i(-1, 1), "radius": 46.0, "taps": 1, "line": "Паутина без договора аренды."},
	{"id": "web_2", "kind": "web", "pos": Vector2(160, 6), "dir": Vector2i(1, 1), "radius": 38.0, "taps": 1, "line": "Ещё одна… ап-чхи!"},
	{"id": "web_3", "kind": "web", "pos": Vector2(112, 38), "dir": Vector2i(1, 1), "radius": 34.0, "taps": 1, "line": "Последняя паутина. Победа!"},
	{"id": "dust_0", "kind": "dust", "pos": Vector2(70, 196), "radius": 34.0, "taps": 2, "line": "Пф! Уже лучше."},
	{"id": "dust_1", "kind": "dust", "pos": Vector2(150, 140), "radius": 34.0, "taps": 2, "line": "Пыль со стажем… уходит!"},
	{"id": "dust_2", "kind": "dust", "pos": Vector2(262, 268), "radius": 34.0, "taps": 2, "line": "Пол помнит родителей."},
	{"id": "curtain", "kind": "curtain", "pos": Vector2(192, 50), "radius": 36.0, "taps": 1, "line": "Лучи. И пыль в них. Красиво!"},
	{"id": "box_0", "kind": "box", "pos": Vector2(56, 276), "radius": 28.0, "taps": 1, "line": "Ложек — как на свадьбу. И 20 монет!"},
	{"id": "box_1", "kind": "box", "pos": Vector2(132, 252), "radius": 28.0, "taps": 1, "line": "«Папино, не трогать». Потрогаю. Чуть-чуть."},
	{"id": "box_2", "kind": "box", "pos": Vector2(112, 176), "radius": 28.0, "taps": 1, "line": "«Мамино». Мам…"},
	{"id": "cover", "kind": "cover", "pos": Vector2(44, 84), "radius": 38.0, "taps": 1, "line": "Тут папа держал круассаны. И нервы."},
	{"id": "machine", "kind": "machine", "pos": Vector2(80, 62), "radius": 24.0, "taps": 3, "line": "Жива!"},
	{"id": "table", "kind": "table", "pos": Vector2(240, 240), "radius": 22.0, "taps": 2, "line": "Стол как новый. Почти."},
	{"id": "stool", "kind": "stool", "pos": Vector2(208, 240), "radius": 20.0, "taps": 1, "line": "Одного стула хватит. Пока."},
]

## Обучающая смена: заказы по порядку (+46 монет).
const TUTORIAL_ORDERS: Array[Dictionary] = [
	{"cat": "tucha", "drink": "espresso", "pastry": ""},
	{"cat": "ryzhik", "drink": "tea", "pastry": ""},
	{"cat": "pryanik", "drink": "espresso", "pastry": ""},
	{"cat": "tucha", "drink": "tea", "pastry": ""},
	{"cat": "ryzhik", "drink": "espresso", "pastry": ""},
]

var city: Node2D
var _room: CafeRoom
var _grime: Node2D
var _layer: Node2D            # слой поверх фасада (ставни)
var _shutter: Shutter
var _shutter_hint: Label
var _nodes := {}              # id -> визуал объекта
var _knocks := 0
var _target := ""
var _target_stand := Vector2.ZERO   # куда встаёт кот, чтобы убрать цель (клетка на полу зала)
var _echo_said := false
var _finished := false
var _progress_panel: Control
var _progress_fill: ColorRect
var _progress_label: Label
var _window_item := false


func setup(c: Node2D) -> void:
	city = c
	_room = c._room
	if GameState.intro_stage == 1:
		_setup_shutter()
	elif GameState.intro_stage == 2:
		_setup_cleanup()


func active() -> bool:
	return GameState.intro_stage in [1, 2]


# ---------------------------------------------------------------- катсцена: ставни

func _setup_shutter() -> void:
	city._nav.set_entrance_open(false)
	_layer = Node2D.new()
	_layer.z_index = 4
	city._world.add_child(_layer)
	_shutter = Shutter.new()
	_shutter.position = SHUTTER_RECT.position
	_shutter.size = SHUTTER_RECT.size
	_layer.add_child(_shutter)
	_shutter_hint = Ui.label("Тап: толкнуть", Rect2(SHUTTER_RECT.position.x, SHUTTER_RECT.end.y + 6, SHUTTER_RECT.size.x, 32), Ui.FONT_SIZE, Color("fff1d6"), _layer, HORIZONTAL_ALIGNMENT_CENTER, true)
	_shutter_hint.add_theme_color_override("font_outline_color", Ui.INK)
	_shutter_hint.add_theme_constant_override("outline_size", Ui.PX * 2)
	var bob := _shutter_hint.create_tween().set_loops()
	bob.tween_property(_shutter_hint, "position:y", _shutter_hint.position.y + 6.0, 0.5).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_shutter_hint, "position:y", _shutter_hint.position.y, 0.5).set_trans(Tween.TRANS_SINE)


func _knock() -> void:
	_knocks += 1
	var base := _shutter.position
	if _knocks == 1:
		Fx.shake(_shutter, 8.0, 0.4, 8)
		Fx.burst(_layer, SHUTTER_RECT.position + Vector2(SHUTTER_RECT.size.x / 2.0, 20), "puff", Color(0.8, 0.78, 0.72), 8, 70.0, 10.0, 0.9, 1.2, 180.0)
		city._player.hop()
		_say("Заело…")
		_shutter_hint.text = "Ещё разок!"
	elif _knocks == 2 and _shutter != null:
		_shutter.position = base
		_say("Пяткой!")
		city._player.hop()
		_shutter_hint.queue_free()
		_open_shutter()


func _open_shutter() -> void:
	var t := create_tween()
	t.tween_property(_shutter, "lift", 1.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_method(_rattle, 0.0, 1.0, 1.1)
	t.tween_callback(_on_shutter_open)
	for i in 6:
		get_tree().create_timer(0.15 * i).timeout.connect(func() -> void:
			Fx.burst(_layer, SHUTTER_RECT.position + Vector2(randf_range(10.0, SHUTTER_RECT.size.x - 10.0), SHUTTER_RECT.size.y - 10), "puff", Color(0.82, 0.8, 0.74), 5, 80.0, -10.0, 1.0, 1.3, 120.0))


func _rattle(u: float) -> void:
	city._camera.offset = Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)) * (1.0 - u)


func _on_shutter_open() -> void:
	city._camera.offset = Vector2.ZERO
	_shutter.queue_free()
	_shutter = null
	city._nav.set_entrance_open(true)
	Fx.banner(city._ui, "Открыто!", Vector2(180, 200), Color("ffd640"))
	GameState.intro_stage = 2
	GameState.save_game()
	_setup_cleanup()
	# кот входит; внутри темно — диафрагма освещает только круг вокруг него
	var rc: Vector2i = city._nav.interior_cells().position
	city._player.walk_to(WorldNav.feet_at(rc + Vector2i(4, 4)))


# ---------------------------------------------------------------- расчистка

func _setup_cleanup() -> void:
	_grime = Node2D.new()
	_room.add_child(_grime)
	for def in OBJECTS:
		_build_object(def)
	_build_progress_ui()
	_update_progress()
	Fx.motes(_grime, Rect2(40, 60, 240, 200), 14)


func _done_taps(id: String) -> int:
	return int(GameState.intro_cleaned.get(id, 0))


func _def(id: String) -> Dictionary:
	for d in OBJECTS:
		if String(d["id"]) == id:
			return d
	return {}


func _is_done(def: Dictionary) -> bool:
	return _done_taps(String(def["id"])) >= int(def["taps"])


func progress() -> float:
	var sum := 0
	for d in OBJECTS:
		sum += mini(_done_taps(String(d["id"])), int(d["taps"]))
	return float(sum) / float(TOTAL_TAPS)


## Свет в зале: тёмно-синий до расчистки, нормальный после.
func light() -> Color:
	if GameState.intro_stage >= 3:
		return Color.WHITE
	if GameState.intro_stage < 2:
		return DARK
	var t := progress() + (0.08 if _done_taps("curtain") >= 1 else 0.0)
	return DARK.lerp(Color.WHITE, clampf(t, 0.0, 1.0))


func _build_object(def: Dictionary) -> void:
	var id := String(def["id"])
	var left := int(def["taps"]) - _done_taps(id)
	var pos: Vector2 = def["pos"]
	match String(def["kind"]):
		"web":
			if left > 0:
				var size_art := 24 if float(def["radius"]) >= 36.0 else 16
				var dir: Vector2i = def["dir"]
				var w := PixelArt.sprite(PixelArt.web(size_art), pos, false)
				w.flip_h = dir.x < 0
				w.flip_v = dir.y < 0
				w.position = Vector2(pos.x - (size_art * 2.0 if dir.x < 0 else 0.0), pos.y - (size_art * 2.0 if dir.y < 0 else 0.0))
				w.modulate = Color(1, 1, 1, 0.92)
				_grime.add_child(w)
				_nodes[id] = w
		"dust":
			if left > 0:
				var d := Dust.new()
				d.setup(int(float(def["radius"])), id.hash(), int(def["taps"]))
				d.position = pos
				d.level = left
				_grime.add_child(d)
				_nodes[id] = d
		"curtain":
			if left > 0:
				var cur := PixelArt.sprite(PixelArt.curtain(32, 17), Vector2(160, 32), false)
				_grime.add_child(cur)
				_nodes[id] = cur
			else:
				_add_window()
		"box":
			if left > 0:
				var b := Sprite2D.new()
				b.texture = load("res://assets/street/props/box.png") as Texture2D
				b.scale = Vector2(2, 2)
				b.position = pos
				b.offset = Vector2(0, -float(b.texture.get_height()) / 2.0)
				_grime.add_child(b)
				_nodes[id] = b
				city._nav.set_extra_solid(WorldNav.cell_at(_room.to_global(pos)), true)   # коробка — преграда, пока не открыта
		"cover":
			if left > 0:
				var c := PixelArt.sprite(PixelArt.cover(48, 21), Vector2(2, 54), false)
				_grime.add_child(c)
				_nodes[id] = c
		"machine":
			var m := PixelArt.sprite(PixelArt.noise(13, 15, Color(0.30, 0.27, 0.24), 0.62 * float(left) / 3.0, 5), Vector2(66, 48), false)
			m.visible = left > 0
			_grime.add_child(m)
			_nodes[id] = m
		"table":
			var tn := _furniture_node("table_small")
			if tn != null and left > 0:
				var d2 := Dust.new()
				d2.setup(26, 77, int(def["taps"]))
				d2.position = Vector2(0, -22)
				d2.level = left
				tn.add_child(d2)
				_nodes[id] = d2
		"stool":
			var sn := _furniture_node("stool")
			if sn != null and left > 0:
				sn.rotation = -1.35
				_nodes[id] = sn


func _furniture_node(item_id: String) -> Node2D:
	for i in _room.layout.size():
		if String(_room.layout[i]["id"]) == item_id:
			return _room.node_for(i)
	return null


func _add_window() -> void:
	if _window_item:
		return
	_window_item = true
	for it in _room.layout:
		if String(it["id"]) == "window":
			return
	_room.add_item({"id": "window", "c": 5, "r": 1, "flip": false})
	city._apply_clip_materials()


# ---------------------------------------------------------------- ввод

## Тап в мире. true — перехвачен интро.
func on_tap(world_p: Vector2) -> bool:
	if GameState.intro_stage == 1 and _shutter != null:
		if SHUTTER_RECT.grow(14).has_point(world_p) and _knocks < 2:
			_knock()
			return true
		return false
	if GameState.intro_stage != 2 or _finished:
		return false
	if not city._interior_rect.has_point(world_p) or city._xray < 0.25:
		return false
	var local := _room.to_local(world_p)
	var best := ""
	var best_d := INF
	for d in OBJECTS:
		if _is_done(d):
			continue
		var dist := (d["pos"] as Vector2).distance_to(local)
		if dist <= float(d["radius"]) + 8.0 and dist / float(d["radius"]) < best_d:
			best = String(d["id"])
			best_d = dist / float(d["radius"])
	if best == "":
		return false
	_target = best
	_target_stand = _stand_for(_def(best))
	city._player.walk_to(_target_stand)
	return true


## Где коту встать, чтобы убрать объект: всегда на полу зала (паутина и штора висят на стене — до них «дотягиваются» от ближайшей клетки пола),
## ближайшая проходимая клетка. Раньше цель на стене выше здания вела кота на улицу.
func _stand_for(def: Dictionary) -> Vector2:
	var pos: Vector2 = def["pos"]
	var local := Vector2(clampf(pos.x, 16.0, 304.0), clampf(pos.y, CafeRoom.ORIGIN.y + 16.0, CafeRoom.ORIGIN.y + (CafeRoom.FRONT_ROW - 1) * 32.0 + 16.0))
	var room_cell: Vector2i = city._nav.interior_cells().position
	var want := Vector2i(floori(local.x / 32.0), floori((local.y - CafeRoom.ORIGIN.y) / 32.0))
	var free := room_cell + want
	var best_d := INF
	for r in CafeRoom.FRONT_ROW:   # ближайшая проходимая клетка именно в зале (поиск по миру мог выбрать клетку за стеной)
		for c in CafeRoom.COLS:
			var cell := room_cell + Vector2i(c, r)
			if city._nav.is_walkable(cell) and Vector2(cell - (room_cell + want)).length() < best_d:
				best_d = Vector2(cell - (room_cell + want)).length()
				free = cell
	return WorldNav.feet_at(free)


## Кот дошёл до цели: действие над объектом.
func on_arrived() -> void:
	if _target == "":
		return
	var def := _def(_target)
	var id := _target
	_target = ""
	if _target_stand.distance_to(city._player.position) <= 24.0 and not _is_done(def):
		_act(id)


func _process(_delta: float) -> void:
	if GameState.intro_stage == 2 and not _echo_said and city != null and city._depth(city._player.position) > 0.6:
		_echo_said = true
		_say("Тут… кто-то есть? Нет. Только эхо.")


func _act(id: String) -> void:
	var def := _def(id)
	var done := _done_taps(id) + 1
	GameState.intro_cleaned[id] = done
	var left := int(def["taps"]) - done
	var world: Vector2 = _room.to_global(def["pos"])
	var node: Node = _nodes.get(id, null)
	Fx.burst(city._actors, world + Vector2(0, -16), "puff", Color(0.85, 0.82, 0.76), 6, 70.0, -15.0, 0.8, 1.2, 120.0)
	match String(def["kind"]):
		"web":
			_dissolve(node, 0.4)
		"dust":
			if node != null:
				node.level = left
				if left <= 0:
					_dissolve(node, 0.35)
		"curtain":
			_flash()
			if node != null:
				var t := create_tween().set_parallel(true)
				t.tween_property(node, "position:y", -40.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				t.tween_property(node, "modulate:a", 0.0, 0.5)
				t.chain().tween_callback(node.queue_free)
			_add_window()
		"box":
			_open_box(id, node, def)
		"cover":
			if node != null:
				var t2 := create_tween().set_parallel(true)
				t2.tween_property(node, "position:y", node.position.y - 50.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				t2.tween_property(node, "modulate:a", 0.0, 0.5)
				t2.chain().tween_callback(node.queue_free)
		"machine":
			if node != null:
				(node as Sprite2D).texture = PixelArt.noise(13, 15, Color(0.30, 0.27, 0.24), 0.62 * float(left) / 3.0, 5)
				if left <= 0:
					node.visible = false
			if left > 0:
				Fx.burst(city._actors, world + Vector2(0, -16), "sparkle", Color("fff3b0"), 5, 90.0, 20.0, 0.6, 1.0)
			else:
				Fx.ring(city._actors, world, Color("ffe08a"), 60.0, 0.6)
				Fx.banner(city._ui, "ПШШШ!", Vector2(180, 220), Color("ffffff"))
				Fx.confetti(city._actors, world + Vector2(0, -20), 14)
		"table":
			if node != null:
				node.level = left
				if left <= 0:
					_dissolve(node, 0.3)
		"stool":
			if node != null:
				var t3 := create_tween()
				t3.tween_property(node, "rotation", 0.0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if left <= 0 and String(def["kind"]) != "box":
		_say(String(def["line"]))
	GameState.save_game()
	_update_progress()
	if progress() >= 1.0 and not _finished:
		_finish_cleanup()


func _dissolve(node: Node, time: float) -> void:
	if node == null:
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(node, "modulate:a", 0.0, time)
	t.tween_property(node, "scale", Vector2(0.4, 0.4), time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(node.queue_free)


func _flash() -> void:
	var f := ColorRect.new()
	f.size = Vector2(360, 640)
	f.color = Color(1, 0.95, 0.75, 0.55)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	city._ui.add_child(f)
	var t := f.create_tween()
	t.tween_property(f, "color:a", 0.0, 0.6)
	t.tween_callback(f.queue_free)


func _open_box(id: String, node: Node, def: Dictionary) -> void:
	city._nav.set_extra_solid(WorldNav.cell_at(_room.to_global(def["pos"])), false)
	if node != null:
		(node as Sprite2D).texture = load("res://assets/street/props/box_open.png") as Texture2D
		Fx.pop(node as Node2D, 1.3, 0.4)
	var world: Vector2 = _room.to_global(def["pos"])
	get_tree().create_timer(0.45).timeout.connect(func() -> void:
		match id:
			"box_0":
				GameState.add_coins(20)
				var from: Vector2 = city._world.get_global_transform_with_canvas() * world
				Fx.coins_fly(city._ui, from, Vector2(28, 28), 6, func() -> void: pass)
				_say(String(def["line"]))
			"box_1":
				GameState.keepsakes.append("recipe_latte")
				Fx.burst(city._actors, world + Vector2(0, -30), "star", Color("ffe08a"), 8, 140.0, 120.0, 0.9, 1.0)
				_say(String(def["line"]))
				city._toast("Найден рецепт: папин латте", world + Vector2(0, -90))
			"box_2":
				GameState.keepsakes.append("photo")
				_room.add_item({"id": "board", "c": 3, "r": 1, "flip": false})
				city._apply_clip_materials()
				_say(String(def["line"]))
				_show_photo()
		_dissolve(node, 0.5)
		GameState.save_game())


## Находка в коробке «Мамино»: фото родителей у стойки и записка.
func _show_photo() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	city.add_child(layer)
	city.get_tree().paused = true
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.6)
	layer.add_child(dim)
	var card := Node2D.new()
	card.position = Vector2(180, 320)
	layer.add_child(card)
	Ui.panel(Rect2(-150, -210, 300, 420), Ui.UI_WOOD, card)
	var photo := ColorRect.new()
	photo.position = Vector2(-116, -178)
	photo.size = Vector2(232, 170)
	photo.color = Color("c9a878")
	card.add_child(photo)
	var inner := ColorRect.new()
	inner.position = Vector2(-108, -170)
	inner.size = Vector2(216, 154)
	inner.color = Color("e9d6b0")
	card.add_child(inner)
	var counter := ColorRect.new()
	counter.position = Vector2(-108, -76)
	counter.size = Vector2(216, 60)
	counter.color = Color("a8794a")
	card.add_child(counter)
	for who in [["res://assets/cats/cat-black-front.png", -48.0], ["res://assets/cats/cat-orange-front.png", 38.0]]:
		var s := Sprite2D.new()
		s.texture = load(who[0]) as Texture2D
		s.region_enabled = true
		s.region_rect = Rect2(0, 16, 16, 16)
		s.scale = Vector2(5, 5)
		s.position = Vector2(float(who[1]), -102)
		s.modulate = Color(1.0, 0.92, 0.8)
		card.add_child(s)
	var note := Ui.label("Мяушке. Когда всё-таки вернёшься.\\nДве ложки терпения, одна — любви.\\nСтавни — пяткой!\\n\\nМама", Rect2(-140, 0, 280, 140), Ui.FONT_SIZE, Ui.INK, card, HORIZONTAL_ALIGNMENT_CENTER, true)
	note.add_theme_color_override("font_color", Ui.CREAM)
	var hint := Ui.label("Нажми, чтобы закрыть", Rect2(-140, 150, 280, 32), Ui.FONT_SIZE, Color("ffe6b0"), card, HORIZONTAL_ALIGNMENT_CENTER, true)
	var blink := hint.create_tween().set_loops()
	blink.tween_property(hint, "modulate:a", 0.3, 0.6)
	blink.tween_property(hint, "modulate:a", 1.0, 0.6)
	Fx.pop_in(card, 0.5)
	var close := Button.new()
	close.size = Vector2(360, 640)
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	layer.add_child(close)
	close.pressed.connect(func() -> void:
		city.get_tree().paused = false
		layer.queue_free())


func _say(text: String) -> void:
	city._toast(text, city._player.position + Vector2(0, -44))


# ---------------------------------------------------------------- шкала и финал

func _build_progress_ui() -> void:
	_progress_panel = Control.new()
	city._ui.add_child(_progress_panel)
	Ui.panel(Rect2(40, 56, 280, 40), Ui.UI_CREAM, _progress_panel)
	var back := ColorRect.new()
	back.position = Vector2(52, 78)
	back.size = Vector2(256, 10)
	back.color = Color("b98c5a")
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_panel.add_child(back)
	_progress_fill = ColorRect.new()
	_progress_fill.position = Vector2(52, 78)
	_progress_fill.size = Vector2(0, 10)
	_progress_fill.color = Color("5bc26a")
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_panel.add_child(_progress_fill)
	_progress_label = Ui.label("", Rect2(40, 54, 280, 26), Ui.FONT_SIZE, Ui.INK, _progress_panel, HORIZONTAL_ALIGNMENT_CENTER, true)


func _update_progress() -> void:
	var p := progress()
	_progress_label.text = "Кофейня %d%% готова" % int(round(p * 100.0))
	var t := create_tween()
	t.tween_property(_progress_fill, "size:x", 256.0 * p, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _finish_cleanup() -> void:
	_finished = true
	GameState.intro_stage = 3
	GameState.save_game()
	Fx.banner(city._ui, "Кафе готово!", Vector2(180, 240), Color("8dff7a"))
	Fx.confetti(city._ui, Vector2(180, 200), 36)
	if _progress_panel != null:
		var t := _progress_panel.create_tween()
		t.tween_interval(1.2)
		t.tween_property(_progress_panel, "modulate:a", 0.0, 0.4)
		t.tween_callback(_progress_panel.queue_free)
	cleanup_finished.emit()


## Ставни: пиксельная заслонка (полосы, ржавчина, замок); lift 0..1 — насколько поднята (низ уезжает вверх).
class Shutter extends Node2D:
	const W := 104   # размеры в пикселях арта (208×72 px мира)
	const H := 36
	var size := Vector2(208, 72)
	var _slats: Sprite2D
	var _bar: Sprite2D
	var lift := 0.0:
		set(v):
			lift = v
			_update()

	func _ready() -> void:
		_slats = PixelArt.sprite(PixelArt.shutter(W, H), Vector2.ZERO, false)
		_slats.region_enabled = true
		add_child(_slats)
		_bar = PixelArt.sprite(PixelArt.shutter_bar(W), Vector2.ZERO, false)
		add_child(_bar)
		_update()

	func _update() -> void:
		if _slats == null:
			return
		var vis := int(round(H * (1.0 - lift)))
		_slats.region_rect = Rect2(0, 0, W, maxi(vis - 5, 0))
		_slats.visible = vis > 5
		_bar.position = Vector2(0, maxi(vis - 5, 0) * 2)
		_bar.visible = vis > 0


## Пыль на полу или столе: пиксельное пятно; level (сколько тапов осталось) задаёт густоту.
class Dust extends Sprite2D:
	var radius_art := 17
	var seed_id := 1
	var max_level := 2
	var level := 2:
		set(v):
			level = v
			_refresh()

	func setup(radius_logical: int, seed_value: int, max_taps: int) -> void:
		radius_art = radius_logical
		seed_id = seed_value
		max_level = max_taps
		scale = Vector2(2, 2)

	func _refresh() -> void:
		if level <= 0:
			visible = false
			return
		texture = PixelArt.dust(radius_art * 2 / 2, maxi(8, radius_art * 2 / 5), seed_id, float(level) / float(max_level))

	func _ready() -> void:
		_refresh()
