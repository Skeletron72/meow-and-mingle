extends Node
## Скриншоты всех экранов интерфейса + JSON с прямоугольниками подписей, кнопок и плашек (для tools/measure_ui.py).
## Запуск (масштаб 2×, 1 px логики = 2 px экрана): xvfb-run -s "-screen 0 720x1280x24" godot --path . --rendering-driver opengl3 --resolution 720x1280 res://tools/ui_shots.tscn -- <папка>
var _root_for_dump: Node
func _collect(n: Node, out: Array) -> void:
	if n is NinePatchRect and n.has_meta("inner") and n.is_visible_in_tree():
		out.append({"t": "panel", "outer": _r(n.get_meta("outer")), "inner": _r(n.get_meta("inner"))})
	elif n is Button and n.is_visible_in_tree() and (n as Button).text != "":
		out.append({"t": "button", "text": (n as Button).text, "rect": _r((n as Button).get_global_rect()), "color": (n as Button).get_theme_color("font_color").to_html(false), "outline": (n as Button).get_theme_color("font_outline_color").to_html(false), "dim": (n as Button).modulate.r < 0.99 or (n as Button).disabled})
	elif n is Label and n.is_visible_in_tree() and (n as Label).text != "":
		var l := n as Label
		out.append({"t": "label", "text": l.text, "rect": _r(l.get_global_rect()), "color": l.get_theme_color("font_color").to_html(false), "align": l.horizontal_alignment})
	for c in n.get_children():
		_collect(c, out)
func _r(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]
func _snap(path: String, wait := 0.5, root: Node = null) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png(path)
	var out := []
	_collect(root if root != null else get_tree().root, out)
	var f := FileAccess.open(path.replace(".png", ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
func _ready() -> void:
	var S: String = OS.get_cmdline_user_args()[0]
	TimeOfDay.set_process(false); Weather.set_process(false); Weather.force(0)
	GameState.new_game(); GameState.intro_stage = 5
	GameState.layout = Data.default_layout.duplicate(true)
	GameState.coins = 1234
	GameState.level_stars = {"l1": 7, "l2": 3}
	var city: Node2D = load(Nav.CITY).instantiate()
	add_child(city)
	for n in city._npcs: n["cat"].position = WorldNav.feet_at(Vector2i(60, 23))
	TimeOfDay.hour = 12.0
	await _snap(S + "/m_city.png", 0.8, city._ui)
	city._open_menu(); await _snap(S + "/m_menu.png", 0.4, city._menu)
	city._menu_page("settings"); await _snap(S + "/m_settings.png", 0.3, city._menu)
	for k in range(1, 6):
		city._cycle_weather()
		await _snap(S + "/m_weather_%d.png" % k, 0.2)
	city._cycle_weather()
	city._menu_page("account"); await _snap(S + "/m_account.png", 0.3, city._menu)
	city._menu_page("confirm"); await _snap(S + "/m_confirm.png", 0.3, city._menu)
	city._open_shop(); await _snap(S + "/m_shop.png", 0.3, city._menu)
	city._shop_turn(); await _snap(S + "/m_shop2.png", 0.3, city._menu)
	city._close_menu()
	city._open_levels(); await _snap(S + "/m_levels.png", 0.3, city._levels_layer)
	city._levels_turn(); await _snap(S + "/m_levels2.png", 0.3, city._levels_layer)
	city._close_levels()
	city.queue_free()
	await get_tree().process_frame
	GameState.coins = 1234
	var d: Node2D = load(Nav.DECORATE).instantiate()
	add_child(d)
	await _snap(S + "/m_decor.png", 0.8, d)
	d.queue_free()
	await get_tree().process_frame
	GameState.intro_stage = 2
	GameState.intro_cleaned = {"web_0": 1, "dust_0": 1}
	var c2: Node2D = load(Nav.CITY).instantiate()
	add_child(c2)
	await _snap(S + "/m_intro.png", 1.0, c2._ui)
	c2.queue_free()
	await get_tree().process_frame
	var m: Node2D = load(Nav.BREW).instantiate()
	m.level = {"id": "t1", "name": "Час пик", "customers": 5, "interval": [0.4, 0.4], "patience": 12.0, "queue": 3, "speed": 10.0, "accuracy": 0.8, "pool": [], "pastry": 0.5}
	add_child(m)
	await _snap(S + "/m_brew.png", 2.6, m)
	m._finish_run(); await _snap(S + "/m_result.png", 1.4, m._result)
	get_tree().quit()
