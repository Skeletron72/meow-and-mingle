class_name Ui
extends RefCounted
## Общие помощники интерфейса: кнопки и панели на деревянных текстурах, иконки, всплывающий текст.

const INK := Color("4a2e1a")
const CREAM := Color("fff1d6")

const ICONS: Texture2D = preload("res://IconsEssential.png")
const UI_BTN: Texture2D = preload("res://assets/ui/SquareButton1_wood.png")
const UI_WOOD: Texture2D = preload("res://assets/ui/WoodenContainer5.png")
const UI_CREAM: Texture2D = preload("res://assets/ui/SimpleColorContainer1_cream.png")

## Область иконки в IconsEssential.png (x, y, w, h).
const ICON_RECTS := {
	"home": Rect2(113, 17, 14, 15),
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
}


static func atlas(tex: Texture2D, region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = region
	return a


static func icon(icon_name: String) -> AtlasTexture:
	return atlas(ICONS, ICON_RECTS[icon_name])


static func stylebox(tex: Texture2D, margin: int, tint := Color.WHITE) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.modulate_color = tint
	return sb


static func panel(r: Rect2, tex: Texture2D, margin: int, parent: Node) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", stylebox(tex, margin))
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


static func label(text: String, r: Rect2, font_size: int, color: Color, parent: Node, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Деревянная кнопка. Без текста — квадратная кнопка-иконка.
static func button(text: String, r: Rect2, icon_name: String, parent: Node, font_size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	# у кнопки с иконкой и текстом слева остаётся место под иконку
	var pad := 0.0
	if icon_name != "" and text != "":
		pad = (ICON_RECTS[icon_name] as Rect2).size.x * 2.0 + 12.0
	var tints := {"normal": Color.WHITE, "hover": Color(1.12, 1.12, 1.12), "pressed": Color(0.82, 0.82, 0.82), "disabled": Color(0.6, 0.6, 0.6, 0.8)}
	for state in tints:
		var sb := stylebox(UI_BTN, 7, tints[state])
		sb.content_margin_left = 7.0 + pad
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, CREAM)
	b.add_theme_color_override("font_disabled_color", Color(CREAM, 0.6))
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_font_size_override("font_size", font_size)
	parent.add_child(b)
	if icon_name != "":
		var region: Rect2 = ICON_RECTS[icon_name]
		var tr_ := TextureRect.new()
		tr_.texture = icon(icon_name)
		tr_.stretch_mode = TextureRect.STRETCH_SCALE
		tr_.size = region.size * 2.0
		tr_.position = Vector2(10.0 if text != "" else (r.size.x - tr_.size.x) / 2.0, (r.size.y - tr_.size.y) / 2.0 - 1.0)
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr_)
	return b


## Всплывающая подпись, которая поднимается и гаснет. pos — центр по x и верх по y.
static func toast(parent: Node, text: String, pos: Vector2) -> void:
	var l := label(text, Rect2(pos - Vector2(150, 0), Vector2(300, 20)), 13, INK, parent)
	l.add_theme_color_override("font_outline_color", CREAM)
	l.add_theme_constant_override("outline_size", 5)
	l.z_index = 100
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position:y", pos.y - 30.0, 1.5)
	t.tween_property(l, "modulate:a", 0.0, 1.5).set_delay(0.7)
	t.chain().tween_callback(l.queue_free)
