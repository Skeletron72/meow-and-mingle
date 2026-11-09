class_name ProjectsPanel
extends UiPanel
## Доска «Путевых листов»: проекты развития станции.

var _list: VBoxContainer
var _money: Label


func _init() -> void:
	super._init()
	build("Путевые листы", 1000, 640)
	var top := HBoxContainer.new()
	body.add_child(top)
	var hint := UiKit.label("Вложите пуговицы — на следующее утро рабочие всё построят.", 22, UiKit.BROWN_L)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(hint)
	var mi := ItemIcon.new("_button")
	mi.show_bg = false
	mi.custom_minimum_size = Vector2(40, 40)
	top.add_child(mi)
	_money = UiKit.label("", 30)
	top.add_child(_money)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	World.project_changed.connect(func(_id: String) -> void:
		if is_open():
			refresh())
	Game.money_changed.connect(func(_m: int) -> void:
		if is_open():
			refresh())


func refresh() -> void:
	_money.text = str(Game.money())
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for p in Data.projects:
		_row(p)


func _row(p: Dictionary) -> void:
	var id: String = p.id
	var state: int = World.project_state(id)
	var funded: int = int(World.state.projects.get(id, {}).get("funded", 0))
	var cost: int = int(p.cost)
	var avail: bool = World.project_available(id)
	var row := PanelContainer.new()
	var bg: Color = UiKit.CREAM_D if avail or state == 3 else Color(0.88, 0.84, 0.78)
	row.add_theme_stylebox_override("panel", UiKit.box(bg, 14, UiKit.BROWN_L, 2, 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_color: Color = UiKit.BROWN if avail or state == 3 else UiKit.BROWN_L
	v.add_child(UiKit.label(str(p.name) + ("  ✔" if state == 3 else ""), 26, name_color))
	var desc := UiKit.label(str(p.desc), 18, UiKit.BROWN_L)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	if not avail and state != 3:
		var need: Array[String] = []
		for r in p.get("requires", []):
			if World.project_state(str(r)) != 3:
				need.append(str(Data.project(str(r)).get("name", r)))
		v.add_child(UiKit.label("Сначала: " + ", ".join(need), 18, UiKit.CORAL))
	elif state == 2:
		v.add_child(UiKit.label("Рабочие трудятся… Будет готово утром!", 20, Color(0.25, 0.55, 0.3)))
	elif state == 1 or (state == 0 and avail):
		var bar := ProgressBar.new()
		bar.max_value = cost
		bar.value = funded
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 18)
		v.add_child(bar)
		v.add_child(UiKit.label("%d / %d" % [funded, cost], 20))
	if avail and state < 2:
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 6)
		h.add_child(bv)
		for amount in [100, 500]:
			var b := UiKit.button("Вложить %d" % amount, Vector2(190, 46))
			b.disabled = Game.money() < mini(amount, cost - funded) or Game.money() <= 0
			var amt: int = amount
			b.pressed.connect(func() -> void: _fund(id, amt))
			bv.add_child(b)
		var rest: int = cost - funded
		var ba := UiKit.warm_button("Всё (%d)" % rest, Vector2(190, 46))
		ba.disabled = Game.money() < 1
		ba.pressed.connect(func() -> void: _fund(id, rest))
		bv.add_child(ba)
	_list.add_child(row)


func _fund(id: String, amount: int) -> void:
	var give: int = mini(amount, Game.money())
	if give <= 0:
		Sfx.play("nope")
		return
	var taken: int = World.fund_project(id, give)
	if taken > 0:
		Game.spend_money(taken)
		Sfx.play("coin")
		if World.project_state(id) == 2:
			Sfx.play("chime")
			Game.say_toast("Заявка оплачена! Рабочие начнут утром.", "good")
	refresh()
