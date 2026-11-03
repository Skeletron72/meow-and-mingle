class_name Ui
extends RefCounted
## Общие помощники интерфейса: панели и кнопки из nine-patch, иконки, подписи, всплывающий текст.
##
## Правило сетки: один пиксель арта = PX (2) логических пикселя — и у спрайтов, и у рамок интерфейса,
## и у шрифта (Galmuri11 рисуется размером 24 = 12 px шрифта × 2). Тогда пиксели везде одного размера.

const PX := 2

const INK := Color("4a2e1a")
const CREAM := Color("fff1d6")

const ICONS: Texture2D = preload("res://assets/ui/icons-essential.png")
const UI_BTN: Texture2D = preload("res://assets/ui/SquareButton1_wood.png")
const UI_WOOD: Texture2D = preload("res://assets/ui/WoodenContainer5.png")
const UI_CREAM: Texture2D = preload("res://assets/ui/SimpleColorContainer1_cream.png")

## Основной шрифт — Galmuri11 (через тему проекта). Узкий — для длинных подписей.
const FONT_NARROW: Font = preload("res://assets/fonts/Galmuri11-Condensed.ttf")
const FONT_SIZE := 24   # 12 px шрифта × PX
const FONT_SIZE_BIG := 48

## Область иконки в IconsEssential.png (x, y, w, h).
const ICON_RECTS := {
	"home": Rect2(113, 17, 14, 15),
	"gear": Rect2(16, 16, 16, 16),
	"cat": Rect2(145, 82, 13, 12),
	"play": Rect2(212, 177, 9, 13),
	"brush": Rect2(308, 114, 7, 13),
	"trash": Rect2(80, 208, 15, 17),
	"coin": Rect2(210, 209, 11, 14),
	"undo": Rect2(17, 209, 14, 13),
	"check": Rect2(305, 18, 14, 12),
	"cart": Rect2(113, 114, 14, 12),
	"exit": Rect2(272, 48, 16, 15),
	"flower": Rect2(308, 176, 9, 16),
	"forks": Rect2(273, 210, 14, 13),
	"hand": Rect2(82, 144, 12, 15),
}


static func atlas(tex: Texture2D, region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = region
	return a


static func icon(icon_name: String) -> AtlasTexture:
	return atlas(ICONS, ICON_RECTS[icon_name])


## Неделимые края рамки в пикселях текстуры: левый, верхний, правый, нижний.
## Подобраны по самим текстурам: угловые орнаменты и нижний «бортик» не должны попадать в растягиваемую часть.
static func patch_margins(tex: Texture2D) -> Array[int]:
	if tex == UI_WOOD:
		return [10, 10, 10, 11]   # орнаменты по углам 10×10, снизу бортик
	if tex == UI_CREAM:
		return [5, 6, 5, 6]       # скошенные углы 5 px, снизу тень
	return [4, 4, 4, 7]           # кнопка: скруглённые углы 4 px, снизу бортик 7 px


## Рамка из nine-patch, нарисованная в масштабе PX. Размер округляется до чётного.
static func panel(r: Rect2, tex: Texture2D, parent: Node) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = tex
	var m := patch_margins(tex)
	n.patch_margin_left = m[0]
	n.patch_margin_top = m[1]
	n.patch_margin_right = m[2]
	n.patch_margin_bottom = m[3]
	n.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	n.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	n.size = (r.size / float(PX)).floor()
	n.scale = Vector2(PX, PX)
	n.position = r.position
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(n)
	return n


static func label(text: String, r: Rect2, font_size: int, color: Color, parent: Node, align := HORIZONTAL_ALIGNMENT_CENTER, narrow := false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if narrow:
		l.add_theme_font_override("font", FONT_NARROW)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Кнопка на nine-patch. Без текста — кнопка-иконка. Размер округляется до чётного.
static func button(text: String, r: Rect2, icon_name: String, parent: Node, narrow := false, tex: Texture2D = null, danger := false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = r.position
	b.size = (r.size / float(PX)).floor() * float(PX)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	# у кнопки с иконкой и текстом слева остаётся место под иконку
	var pad := 0.0
	if icon_name != "" and text != "":
		pad = (ICON_RECTS[icon_name] as Rect2).size.x * PX + 8.0
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 4.0 + pad
		sb.content_margin_right = 4.0
		sb.content_margin_bottom = 6.0   # текст чуть выше нижнего бортика
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, CREAM)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", PX)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	if narrow:
		b.add_theme_font_override("font", FONT_NARROW)
	var skin := panel(Rect2(Vector2.ZERO, b.size), tex if tex else UI_BTN, b)
	skin.show_behind_parent = true
	if danger:
		skin.self_modulate = Color(1.0, 0.55, 0.5)   # красноватая кнопка для опасных действий
	b.mouse_entered.connect(func() -> void: skin.modulate = Color(1.1, 1.1, 1.1))
	b.mouse_exited.connect(func() -> void: skin.modulate = Color.WHITE)
	b.button_down.connect(func() -> void: skin.modulate = Color(0.8, 0.8, 0.8))
	b.button_up.connect(func() -> void: skin.modulate = Color.WHITE)
	parent.add_child(b)
	if icon_name != "":
		var region: Rect2 = ICON_RECTS[icon_name]
		var tr_ := TextureRect.new()
		tr_.texture = icon(icon_name)
		tr_.stretch_mode = TextureRect.STRETCH_SCALE
		tr_.size = region.size * PX
		var x := 8.0 if text != "" else floorf((b.size.x - tr_.size.x) / (2.0 * PX)) * PX
		tr_.position = Vector2(x, floorf((b.size.y - tr_.size.y) / (2.0 * PX)) * PX - 2.0)
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr_)
	return b


## Всплывающая подпись, которая поднимается и гаснет. pos — центр по x и верх по y.
static func toast(parent: Node, text: String, pos: Vector2) -> void:
	var l := label(text, Rect2(pos - Vector2(170, 0), Vector2(340, 32)), FONT_SIZE, INK, parent, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.add_theme_color_override("font_outline_color", CREAM)
	l.add_theme_constant_override("outline_size", PX * 2)
	l.z_index = 100
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position:y", pos.y - 30.0, 1.5)
	t.tween_property(l, "modulate:a", 0.0, 1.5).set_delay(0.7)
	t.chain().tween_callback(l.queue_free)
