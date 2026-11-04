class_name Card
extends RefCounted
## Общая карточка списков (магазин, задания, ремонт, коты, смены): слева значок в светлой рамке, посередине название и описание
## (описание переносится на две строки), справа — кнопка действия с ценой/наградой или значки (звёзды, сердечки).
## Всё на сетке арта (чётные пиксели). Один компонент вместо шести разных раскладок — чтобы везде одинаково и всё влезало.
##
## Card.make(parent, Rect2(x, y, w, Card.H), {
##   "title": "Название", "sub": "Описание",
##   "icon": "fish" | Texture2D, "icon_tint": Color,
##   "action": {"text": "8", "icon": "fish", "enabled": true, "press": Callable},     # кнопка справа
##   "stars": 0..7 (маска звёзд уровня) | "hearts": 0..3 | "progress": [3, 8],
##   "enabled": true, "tint": Color, "press": Callable (нажатие на всю карточку), "badge": "12" (число на значке)
## })

const H := 96.0            # высота карточки
const WELL := 48.0         # светлая рамка значка
const PAD := 6.0
const ACTION_H := 48.0
const MIN_ACTION_W := 72.0


## Ширина кнопки действия под её текст и значок.
static func action_width(a: Dictionary) -> float:
	var text := Loc.t(String(a.get("text", "")))
	var w := Ui.FONT_NARROW.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x + 16.0
	if String(a.get("icon", "")) != "":
		w += 32.0 + (6.0 if text != "" else 0.0)
	return clampf(Ui.snap(w), 64.0 if text != "" else 56.0, 112.0)


static func make(parent: Node, r: Rect2, o: Dictionary) -> Control:
	var root := Control.new()
	root.position = Ui.snap_v(r.position)
	root.size = Vector2(Ui.snap(r.size.x), H)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var enabled := bool(o.get("enabled", true))
	var w := root.size.x
	# фон: деревянная плашка; нажимается вся, если задан press
	var skin := Ui.UI_BTN
	var body: Control
	if o.has("press"):
		var b := Ui.button("", Rect2(0, 0, w, H), "", root)
		b.pressed.connect(o["press"])
		b.disabled = not enabled
		body = b
	else:
		body = Ui.panel(Rect2(0, 0, w, H), skin, root)
	body.modulate = Color(o.get("tint", Color.WHITE)) if enabled else Color(0.66, 0.66, 0.66)
	# значок в светлой рамке
	var well := Ui.panel(Rect2(PAD, PAD - 2.0, WELL, WELL), Ui.UI_CREAM, root)
	well.modulate = body.modulate
	var icon: Variant = o.get("icon", null)
	if icon != null:
		var tex: Texture2D = Ui.icon(String(icon)) if icon is String else icon
		var tr_ := TextureRect.new()
		tr_.texture = tex
		tr_.stretch_mode = TextureRect.STRETCH_SCALE
		var sz := tex.get_size() * float(Ui.PX)
		if sz.x > WELL - 8.0:   # крупные картинки (мордочки котов) вписываем
			sz = tex.get_size() * float(Ui.PX) * ((WELL - 12.0) / sz.x)
			sz = Vector2(Ui.snap(sz.x), Ui.snap(sz.y))
		tr_.size = sz
		tr_.position = Ui.snap_v(Vector2(PAD + (WELL - sz.x) / 2.0, PAD - 2.0 + (WELL - Ui.SHADOW_CREAM - sz.y) / 2.0 + 2.0))
		tr_.modulate = Color(o.get("icon_tint", Color.WHITE)) if enabled else Color(0.7, 0.7, 0.7)
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr_)
	if o.has("badge"):
		var bd := Ui.label(String(o["badge"]), Rect2(PAD, PAD - 2.0, WELL, WELL - Ui.SHADOW_CREAM), Ui.FONT_SIZE, Ui.INK, root, HORIZONTAL_ALIGNMENT_CENTER, true)
		bd.add_theme_color_override("font_outline_color", Ui.CREAM)
		bd.add_theme_constant_override("outline_size", Ui.PX)
	# правая часть: кнопка действия (внизу справа, на всю высоту текста) или сердечки
	var right_w := 0.0
	var action: Dictionary = o.get("action", {})
	var title := Loc.t(String(o.get("title", "")))
	var sub := String(o.get("sub", ""))
	if not action.is_empty():
		right_w = action_width(action)
		var ab := Ui.button(Loc.t(String(action.get("text", ""))), Rect2(w - PAD - right_w, Ui.snap((H - ACTION_H) / 2.0) - 2.0, right_w, ACTION_H), String(action.get("icon", "")), root, true, Ui.UI_CREAM)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			ab.add_theme_color_override(c, Ui.INK)
		ab.add_theme_color_override("font_disabled_color", Ui.INK.lightened(0.45))
		ab.add_theme_color_override("font_outline_color", Ui.CREAM)
		ab.disabled = not bool(action.get("enabled", true)) or not enabled
		if action.has("press"):
			ab.pressed.connect(action["press"])
		if String(action.get("text", "")) == "" and String(action.get("icon", "")) != "":
			Ui.set_button_icon(ab, Ui.icon(String(action["icon"])))
	elif o.has("hearts"):
		right_w = 3.0 * 32.0
		for k in 3:
			var ht := TextureRect.new()
			ht.texture = Ui.icon("heart" if k < int(o["hearts"]) else "heart_off")
			ht.stretch_mode = TextureRect.STRETCH_SCALE
			ht.size = Vector2(32, 32)
			ht.position = Vector2(w - PAD - right_w + k * 32.0, Ui.snap((H - Ui.SHADOW_BUTTON - 32.0) / 2.0))
			ht.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(ht)
	# текст
	var tx := PAD + WELL + PAD
	var tw := w - tx - PAD - (right_w + PAD if right_w > 0.0 else 0.0)
	var title_color: Color = Color(o.get("title_color", Ui.CREAM))
	var title_w := Ui.FONT_NARROW.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x + 4.0
	if o.has("progress"):
		Ui.label(title, Rect2(tx, 4.0, tw, Ui.LINE_H), Ui.FONT_SIZE, title_color, root, HORIZONTAL_ALIGNMENT_LEFT, true) if title_w <= tw else _wrap_label(title, Rect2(tx, 4.0, tw, Ui.LINE_H * 2.0), title_color, root, false)
		var by := 4.0 + (Ui.LINE_H if title_w <= tw else Ui.LINE_H * 2.0) + 4.0
		_progress(root, Rect2(tx, by, tw - 60.0, 16.0), o["progress"] as Array)
		Ui.label("%d/%d" % [int(o["progress"][0]), int(o["progress"][1])], Rect2(tx + tw - 56.0, by - 6.0, 56.0, Ui.LINE_H), Ui.FONT_SIZE, Ui.CREAM.darkened(0.1), root, HORIZONTAL_ALIGNMENT_RIGHT, true)
		return root
	if title_w > tw:
		# длинное название: две строки, описание уступает место
		_wrap_label(title, Rect2(tx, 4.0, tw, H - 14.0), title_color, root, true)
		return root
	Ui.label(title, Rect2(tx, 4.0, tw, Ui.LINE_H), Ui.FONT_SIZE, title_color, root, HORIZONTAL_ALIGNMENT_LEFT, true)
	if o.has("stars"):
		# звёзды уровня во второй строке слева, рядом короткая подпись
		var mask := int(o["stars"])
		for k in 3:
			var st := TextureRect.new()
			st.texture = Ui.icon("star" if (mask >> k) & 1 == 1 else "star_off")
			st.stretch_mode = TextureRect.STRETCH_SCALE
			st.size = Vector2(32, 32)
			st.position = Vector2(tx + k * 32.0, 4.0 + Ui.LINE_H + 2.0)
			st.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(st)
		if sub != "":
			_wrap_label(sub, Rect2(tx + 104.0, 4.0 + Ui.LINE_H, maxf(tw - 104.0, 40.0), 36.0), Ui.CREAM.darkened(0.12), root, true)
		return root
	if sub != "":
		_wrap_label(sub, Rect2(tx, 4.0 + Ui.LINE_H, tw, Ui.LINE_H * 2.0), Ui.CREAM.darkened(0.12), root, false)
	return root


## Подпись с переносом по словам (до высоты прямоугольника), узкий шрифт. center — по вертикали.
static func _wrap_label(text: String, r: Rect2, color: Color, parent: Node, center: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Ui.FONT_NARROW)
	l.add_theme_font_size_override("font_size", Ui.FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if center else VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Ui.snap_v(r.position)
	l.size = Ui.snap_v(r.size)
	l.set_meta("max_h", r.size.y)   # проверка tools/ui_lint.gd: у Label с переносом размер сам растёт под текст
	parent.add_child(l)
	return l


## Полоска прогресса: тёмная подложка, зелёная заливка по целым пикселям сетки.
static func _progress(parent: Node, r: Rect2, p: Array) -> void:
	var back := ColorRect.new()
	back.position = Ui.snap_v(r.position)
	back.size = Ui.snap_v(r.size)
	back.color = Ui.INK
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(back)
	var frac := clampf(float(p[0]) / maxf(1.0, float(p[1])), 0.0, 1.0)
	var fill := ColorRect.new()
	fill.position = back.position + Vector2(2, 2)
	fill.size = Vector2(Ui.snap((back.size.x - 4.0) * frac), back.size.y - 4.0)
	fill.color = Color("8dff7a") if frac >= 1.0 else Color("ffd640")
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fill)
