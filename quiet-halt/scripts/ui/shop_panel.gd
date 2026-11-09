class_name ShopPanel
extends UiPanel
## Лавка: вкладки «Купить» и «Продать».

var stock: Array = []
var _tab: int = 0
var _list: VBoxContainer
var _money: Label
var _tab_buy: Button
var _tab_sell: Button


func _init() -> void:
	super._init()
	build("Лавка", 940, 620)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	_tab_buy = UiKit.button("Купить", Vector2(180, 52))
	_tab_buy.pressed.connect(func() -> void: _set_tab(0))
	top.add_child(_tab_buy)
	_tab_sell = UiKit.button("Продать", Vector2(180, 52))
	_tab_sell.pressed.connect(func() -> void: _set_tab(1))
	top.add_child(_tab_sell)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var mh := HBoxContainer.new()
	var mi := ItemIcon.new("_button")
	mi.show_bg = false
	mi.custom_minimum_size = Vector2(40, 40)
	mh.add_child(mi)
	_money = UiKit.label("", 30)
	mh.add_child(_money)
	top.add_child(mh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	Game.money_changed.connect(func(_m: int) -> void:
		if is_open():
			refresh())


func open_shop(title: String, stock_ids: Array) -> void:
	title_label.text = title
	stock = stock_ids
	_tab = 0
	open_panel()


func _set_tab(t: int) -> void:
	_tab = t
	Sfx.play("click")
	refresh()


func refresh() -> void:
	_money.text = str(Game.money())
	_tab_buy.disabled = _tab == 0
	_tab_sell.disabled = _tab == 1
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _tab == 0:
		for id in stock:
			_row(str(id), true)
	else:
		var seen: Dictionary = {}
		for s in Game.profile.get("items", []):
			var id: String = str(s.id)
			if seen.has(id):
				continue
			seen[id] = true
			if int(Data.item(id).get("price", 0)) > 0:
				_row(id, false)
		if seen.is_empty():
			_list.add_child(UiKit.label("Рюкзак пуст — ловите рыбу, трясите деревья и собирайте цветы!", 24, UiKit.BROWN_L))


func _row(id: String, buy: bool) -> void:
	var d: Dictionary = Data.item(id)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiKit.box(UiKit.CREAM_D, 14, UiKit.BROWN_L, 2, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var cnt: int = Game.item_count(id)
	h.add_child(ItemIcon.new(id, 0))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_txt: String = str(d.name) + ("   (у вас: %d)" % cnt if buy else "   ×%d" % cnt)
	v.add_child(UiKit.label(name_txt, 26))
	v.add_child(UiKit.label(str(d.get("desc", "")), 18, UiKit.BROWN_L))
	h.add_child(v)
	if buy:
		var price: int = int(d.get("buy", 0))
		var b := UiKit.warm_button("Купить за %d" % price, Vector2(220, 52))
		b.disabled = Game.money() < price
		b.pressed.connect(func() -> void:
			if not Game.can_add(id, 1):
				Game.say_toast("Рюкзак полон!", "bad")
				Sfx.play("nope")
				return
			if Game.spend_money(price):
				Game.add_item(id, 1)
				Sfx.play("pickup")
				Game.say_toast("Куплено: " + str(d.name), "good")
				refresh())
		h.add_child(b)
	else:
		var price2: int = int(d.get("price", 0))
		var b1 := UiKit.warm_button("Продать 1 · %d" % price2, Vector2(200, 52))
		b1.pressed.connect(func() -> void:
			if Game.remove_item(id, 1):
				Game.add_money(price2)
				refresh())
		h.add_child(b1)
		if cnt > 1:
			var b2 := UiKit.button("Все · %d" % (price2 * cnt), Vector2(190, 52))
			b2.pressed.connect(func() -> void:
				var n: int = Game.item_count(id)
				if Game.remove_item(id, n):
					Game.add_money(price2 * n)
					refresh())
			h.add_child(b2)
	_list.add_child(row)
