extends Node
## Профиль игрока, инвентарь, сохранения, переходы между сценами.
## Профиль хранится отдельно от мира (WorldState): мир принадлежит хосту,
## а профиль «путешествует» вместе с игроком (задел под визиты друзей).

signal inventory_changed
signal money_changed(money: int)
signal toast(text: String, kind: String)
signal objective_changed

const SAVE_PATH: String = "user://save_v1.json"
const MAX_SLOTS: int = 30
const STACK: int = 99
const TOOLS: Array[String] = ["net", "rod", "shovel"]

var profile: Dictionary = {}
var settings: Dictionary = {"music": 0.6, "sfx": 0.8, "touch": false, "debug": false}
var in_game: bool = false
var ui_lock: int = 0 ## >0 — открыто окно/диалог, управление игроком отключено

var _fade: ColorRect
var _fade_layer: CanvasLayer
var _changing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load_settings()
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.1, 0.07, 0.1, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade_layer.add_child(_fade)
	Clock.day_changed.connect(_on_day_changed)
	Clock.hour_changed.connect(_on_hour_changed)


# ---------- ввод ----------

func _setup_input() -> void:
	_action("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("move_up", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_down", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("act", [KEY_SPACE, KEY_F, KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A])
	_action("cancel", [KEY_ESCAPE], [JOY_BUTTON_B])
	_action("cam_left", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_action("cam_right", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])
	_action("tool_next", [KEY_TAB, KEY_R], [JOY_BUTTON_Y])
	_action("bag", [KEY_B, KEY_I], [JOY_BUTTON_X])
	_action("menu", [KEY_P, KEY_M], [JOY_BUTTON_START])
	_action("run", [KEY_SHIFT], [])


func _action(name: String, keys: Array, buttons: Array, axes: Array = []) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k as Key
		InputMap.action_add_event(name, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b as JoyButton
		InputMap.action_add_event(name, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0] as JoyAxis
		e.axis_value = a[1]
		InputMap.action_add_event(name, e)


# ---------- профиль ----------

func new_profile(player_name: String, look: Dictionary) -> void:
	profile = {
		"name": player_name,
		"look": look,
		"money": 500,
		"items": [],
		"tool": "net",
		"caught": {},
		"started_real": Time.get_unix_time_from_system(),
	}
	in_game = true
	inventory_changed.emit()
	money_changed.emit(500)


func money() -> int:
	return int(profile.get("money", 0))


func add_money(n: int) -> void:
	profile.money = money() + n
	money_changed.emit(money())
	if n > 0:
		Sfx.play("coin")


func spend_money(n: int) -> bool:
	if money() < n:
		return false
	profile.money = money() - n
	money_changed.emit(money())
	return true


func item_count(id: String) -> int:
	var total: int = 0
	for s in profile.get("items", []):
		if s.id == id:
			total += int(s.count)
	return total


func free_slots() -> int:
	return MAX_SLOTS - (profile.get("items", []) as Array).size()


func can_add(id: String, n: int = 1) -> bool:
	var left: int = n
	for s in profile.items:
		if s.id == id:
			left -= STACK - int(s.count)
	if left <= 0:
		return true
	var need_slots: int = int(ceil(float(left) / float(STACK)))
	return free_slots() >= need_slots


func add_item(id: String, n: int = 1) -> bool:
	if not can_add(id, n):
		return false
	var left: int = n
	for s in profile.items:
		if s.id == id and left > 0:
			var room: int = STACK - int(s.count)
			var put: int = mini(room, left)
			s.count = int(s.count) + put
			left -= put
	while left > 0:
		var put: int = mini(STACK, left)
		(profile.items as Array).append({"id": id, "count": put})
		left -= put
	var cat: String = str(Data.item(id).get("category", ""))
	if cat in ["fish", "bug"]:
		profile.caught[id] = int(profile.caught.get(id, 0)) + n
	inventory_changed.emit()
	return true


func remove_item(id: String, n: int = 1) -> bool:
	if item_count(id) < n:
		return false
	var left: int = n
	var arr: Array = profile.items
	var i: int = arr.size() - 1
	while i >= 0 and left > 0:
		if arr[i].id == id:
			var take: int = mini(int(arr[i].count), left)
			arr[i].count = int(arr[i].count) - take
			left -= take
			if int(arr[i].count) <= 0:
				arr.remove_at(i)
		i -= 1
	inventory_changed.emit()
	return true


func lock_ui() -> void:
	ui_lock += 1


func unlock_ui() -> void:
	ui_lock = maxi(ui_lock - 1, 0)


func say_toast(text: String, kind: String = "info") -> void:
	toast.emit(text, kind)


# ---------- сцены ----------

func change_scene(path: String, fade_time: float = 0.45) -> void:
	if _changing:
		return
	_changing = true
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 1.0, fade_time)
	await t.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var t2 := create_tween()
	t2.tween_property(_fade, "modulate:a", 0.0, fade_time)
	await t2.finished
	_changing = false


func fade_out(time: float = 0.5) -> void:
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 1.0, time)
	await t.finished


func fade_in(time: float = 0.5) -> void:
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 0.0, time)
	await t.finished


# ---------- новая игра / сохранение ----------

func start_new_game(player_name: String, look: Dictionary, town: String, hemi: int) -> void:
	new_profile(player_name, look)
	var seed_value: int = int(Time.get_unix_time_from_system()) % 1000003
	World.new_world(seed_value, town, hemi)
	World.state.flags["arrival_pending"] = true
	World.state.start_day = Clock.day_index()
	World.state.last_day = Clock.day_index()
	save_game()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	if not in_game:
		return false
	var data: Dictionary = {
		"version": 1,
		"saved_at": Time.get_unix_time_from_system(),
		"profile": profile,
		"world": World.state.to_dict(),
		"debug_offset": Clock.debug_offset_sec,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Не удалось сохранить игру")
		return false
	f.store_string(JSON.stringify(data))
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var txt: String = FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	profile = d.get("profile", {})
	profile.money = int(profile.get("money", 0))
	Clock.debug_offset_sec = float(d.get("debug_offset", 0.0))
	World.load_dict(d.get("world", {}))
	in_game = true
	inventory_changed.emit()
	money_changed.emit(money())
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _save_settings() -> void:
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


func _load_settings() -> void:
	if FileAccess.file_exists("user://settings.json"):
		var p: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
		if p is Dictionary:
			for k in p:
				settings[k] = p[k]
	if DisplayServer.is_touchscreen_available():
		settings["touch"] = true


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	_save_settings()


func _on_day_changed(_day: int) -> void:
	if in_game:
		World.process_days(Clock.day_index())
		save_game()


func _on_hour_changed(_h: int) -> void:
	if in_game:
		World.tick_projects()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


# ---------- цель (подсказка в HUD) ----------

func objective() -> String:
	var ws: WorldState = World.state
	if World.flag("arrival_pending"):
		return ""
	var talked: int = 0
	for id in ["barkhat", "pukh", "ugolek"]:
		if int(ws.villagers.get(id, {}).get("friend", 0)) > 0:
			talked += 1
	var any_funded: bool = false
	for id in ws.projects:
		if int(ws.projects[id].get("funded", 0)) > 0:
			any_funded = true
	if talked < 3:
		return "Познакомьтесь с жителями (%d/3). Подойдите и нажмите кнопку действия." % talked
	if not any_funded:
		return "Загляните к доске заявок на перроне и вложитесь в первый «Путевой лист»."
	if World.project_state("clock") != 3 and World.project_state("clock") != 0:
		return "Заработайте пуговицы: потрясите деревья, поймайте рыбу или бабочку."
	if ws.notes_found.size() < 1:
		return "Уголёк говорил про блеск в земле. Возьмите лопату и поищите у западного края вокзала."
	if World.project_state("bridge") != 3:
		return "Стройте дальше: мост откроет путь за реку."
	if ws.notes_found.size() < 6:
		return "Найдите все страницы журнала Лидии (%d/6)." % ws.notes_found.size()
	if not World.flag("finale_done"):
		return "Зажгите все огни и ждите на перроне в полночь."
	return "Тихая Заводь оживает. Продолжайте строить Променад!"
