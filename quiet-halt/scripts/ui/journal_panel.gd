class_name JournalPanel
extends UiPanel
## Дневник смотрителя: страницы журнала Лидии, жители, коллекция.

var _tab: int = 0
var _content: VBoxContainer
var _tabs: Array[Button] = []


func _init() -> void:
	super._init()
	build("Дневник смотрителя", 1000, 640)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	var names: Array[String] = ["Журнал Лидии", "Жители", "Коллекция"]
	for i in names.size():
		var b := UiKit.button(names[i], Vector2(220, 50))
		var idx: int = i
		b.pressed.connect(func() -> void:
			_tab = idx
			Sfx.play("click")
			refresh())
		top.add_child(b)
		_tabs.append(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)


func open_tab(t: int) -> void:
	_tab = t
	if is_open():
		refresh()
	else:
		open_panel()


func refresh() -> void:
	for i in _tabs.size():
		_tabs[i].disabled = i == _tab
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	match _tab:
		0:
			_notes()
		1:
			_villagers()
		_:
			_collection()


func _card(inner: Control, bg: Color = UiKit.CREAM_D) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(bg, 14, UiKit.BROWN_L, 2, 12))
	p.add_child(inner)
	return p


func _notes() -> void:
	var found: Array = World.state.notes_found
	_content.add_child(UiKit.label("Найдено страниц: %d из %d" % [found.size(), Data.notes.size()], 26))
	for n in Data.notes:
		var v := VBoxContainer.new()
		if found.has(n.id):
			v.add_child(UiKit.label(str(n.title), 26, UiKit.BROWN))
			var t := UiKit.label(str(n.text), 22)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(t)
			_content.add_child(_card(v, Color(0.99, 0.96, 0.82)))
		elif found.size() + 1 == int(str(n.id).substr(1)):
			v.add_child(UiKit.label("Страница %s — ???" % str(n.id).substr(1), 26, UiKit.BROWN_L))
			var h := UiKit.label("Подсказка: " + str(n.hint), 20, UiKit.CORAL)
			h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(h)
			_content.add_child(_card(v))
		else:
			v.add_child(UiKit.label("Страница %s — ещё не найдена" % str(n.id).substr(1), 24, UiKit.BROWN_L))
			_content.add_child(_card(v, Color(0.88, 0.84, 0.78)))


func _villagers() -> void:
	for vd in Data.villagers:
		var st: Dictionary = World.state.villagers.get(vd.id, {})
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var present: bool = bool(st.get("present", false))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm: String = str(vd.name) + "  —  " + str(vd.personality) if present else "??? (ещё не приехал)"
		v.add_child(UiKit.label(nm, 26))
		if present:
			var f: int = int(st.get("friend", 0))
			var hearts: int = mini(f / 10, 10)
			v.add_child(UiKit.label("Дружба: " + "♥".repeat(hearts) + "♡".repeat(10 - hearts), 22, UiKit.CORAL))
			var likes: Array[String] = []
			for l in vd.get("likes", []):
				likes.append(Data.item_name(str(l)))
			v.add_child(UiKit.label("Любит: " + ", ".join(likes), 18, UiKit.BROWN_L))
		h.add_child(v)
		_content.add_child(_card(h))


func _collection() -> void:
	var caught: Dictionary = Game.profile.get("caught", {})
	var total: int = 0
	var have: int = 0
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for id in Data.items:
		var d: Dictionary = Data.items[id]
		if str(d.category) not in ["fish", "bug"]:
			continue
		total += 1
		var got: bool = caught.has(id)
		if got:
			have += 1
		var ic := ItemIcon.new(id if got else "", 0)
		ic.custom_minimum_size = Vector2(90, 90)
		ic.tooltip_text = str(d.name) if got else "???"
		grid.add_child(ic)
	_content.add_child(UiKit.label("Рыбы и насекомые: %d из %d" % [have, total], 26))
	_content.add_child(grid)
	_content.add_child(UiKit.label("Найдено рыб и насекомых отображается здесь. Золотая рыбка — редчайшая!", 20, UiKit.BROWN_L))
