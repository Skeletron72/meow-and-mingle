class_name BagPanel
extends UiPanel
## Рюкзак: сетка предметов, описание, «Подарить/Использовать/Выбросить».

signal use_item(id: String)

var _grid: GridContainer
var _info: Label
var _name: Label
var _icon: ItemIcon
var _btn_use: Button
var _btn_drop: Button
var _sel: String = ""


func _init() -> void:
	super._init()
	build("Рюкзак", 1000, 620)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 18)
	body.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_constant_override("separation", 8)
	h.add_child(side)
	_icon = ItemIcon.new("")
	_icon.custom_minimum_size = Vector2(120, 120)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	side.add_child(_icon)
	_name = UiKit.label("", 30)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(_name)
	_info = UiKit.label("Выберите предмет.", 22, UiKit.BROWN_L)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_info)
	_btn_use = UiKit.button("Использовать")
	_btn_use.pressed.connect(func() -> void:
		if _sel != "":
			use_item.emit(_sel)
			close_panel())
	side.add_child(_btn_use)
	_btn_drop = UiKit.warm_button("Выбросить 1")
	_btn_drop.pressed.connect(func() -> void:
		if _sel != "" and Game.remove_item(_sel, 1):
			Sfx.play("nope")
			refresh())
	side.add_child(_btn_drop)
	Game.inventory_changed.connect(func() -> void:
		if is_open():
			refresh())


func refresh() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var items: Array = Game.profile.get("items", [])
	title_label.text = "Рюкзак  (%d/%d)" % [items.size(), Game.MAX_SLOTS]
	for s in items:
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 96)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiKit.box(UiKit.CREAM_D, 14, UiKit.BROWN_L, 2, 4))
		b.add_theme_stylebox_override("hover", UiKit.box(Color(1, 0.92, 0.7), 14, UiKit.CORAL, 3, 4))
		b.add_theme_stylebox_override("pressed", UiKit.box(Color(1, 0.88, 0.6), 14, UiKit.CORAL, 3, 4))
		var ic := ItemIcon.new(str(s.id), int(s.count))
		ic.show_bg = false
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(ic)
		var id: String = str(s.id)
		b.pressed.connect(func() -> void:
			_select(id)
			Sfx.play("click"))
		_grid.add_child(b)
	if _sel != "" and Game.item_count(_sel) == 0:
		_sel = ""
	_select(_sel)


func _select(id: String) -> void:
	_sel = id
	if id == "":
		_icon.set_item("")
		_name.text = ""
		_info.text = "Выберите предмет."
		_btn_use.visible = false
		_btn_drop.visible = false
		return
	var d: Dictionary = Data.item(id)
	_icon.set_item(id)
	_name.text = str(d.name)
	var txt: String = str(d.get("desc", ""))
	if int(d.get("price", 0)) > 0:
		txt += "\nЦена продажи: %d" % int(d.price)
	_info.text = txt
	var plant: String = str(d.get("plant", ""))
	var cat: String = str(d.get("category", ""))
	_btn_use.visible = plant != "" or cat == "fruit"
	_btn_use.text = "Посадить" if plant != "" else "Съесть"
	_btn_drop.visible = true
