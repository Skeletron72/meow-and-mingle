class_name UiKit
extends RefCounted
## Общий стиль интерфейса: тёплая бумага, коричневый текст, скруглённые углы.

const CREAM: Color = Color(0.99, 0.95, 0.86)
const CREAM_D: Color = Color(0.94, 0.86, 0.70)
const BROWN: Color = Color(0.36, 0.24, 0.18)
const BROWN_L: Color = Color(0.60, 0.43, 0.32)
const TEAL: Color = Color(0.30, 0.62, 0.62)
const TEAL_D: Color = Color(0.22, 0.48, 0.50)
const CORAL: Color = Color(0.92, 0.50, 0.42)
const GOLD: Color = Color(0.96, 0.78, 0.30)

static var _theme: Theme


static func box(bg: Color, radius: int = 16, border: Color = BROWN_L, bw: int = 3, pad: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	s.shadow_color = Color(0, 0, 0, 0.18)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 24
	t.set_color("font_color", "Label", BROWN)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.55))
	t.set_color("font_outline_color", "Button", TEAL_D)
	t.set_constant("outline_size", "Button", 4)
	t.set_color("default_color", "RichTextLabel", BROWN)
	t.set_font_size("normal_font_size", "RichTextLabel", 26)
	t.set_stylebox("normal", "Button", box(TEAL, 14, TEAL_D, 3, 14))
	t.set_stylebox("hover", "Button", box(TEAL.lightened(0.1), 14, TEAL_D, 3, 14))
	t.set_stylebox("pressed", "Button", box(TEAL_D, 14, TEAL_D.darkened(0.2), 3, 14))
	t.set_stylebox("disabled", "Button", box(Color(0.6, 0.6, 0.6), 14, Color(0.45, 0.45, 0.45), 3, 14))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 14, GOLD, 3, 14))
	t.set_stylebox("panel", "PanelContainer", box(CREAM, 22, BROWN_L, 4, 18))
	t.set_stylebox("panel", "Panel", box(CREAM, 22, BROWN_L, 4, 18))
	var le := box(Color(1, 1, 1), 10, BROWN_L, 2, 10)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(Color(1, 1, 1), 10, TEAL, 3, 10))
	t.set_color("font_color", "LineEdit", BROWN)
	t.set_color("caret_color", "LineEdit", BROWN)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.6, 0.5, 0.45))
	_theme = t
	return t


static func button(text: String, min_size: Vector2 = Vector2(0, 56)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b


static func warm_button(text: String, min_size: Vector2 = Vector2(0, 56)) -> Button:
	var b := button(text, min_size)
	b.add_theme_stylebox_override("normal", box(CORAL, 14, CORAL.darkened(0.25), 3, 14))
	b.add_theme_stylebox_override("hover", box(CORAL.lightened(0.08), 14, CORAL.darkened(0.25), 3, 14))
	b.add_theme_stylebox_override("pressed", box(CORAL.darkened(0.12), 14, CORAL.darkened(0.3), 3, 14))
	b.add_theme_color_override("font_outline_color", CORAL.darkened(0.3))
	return b


static func label(text: String, size: int = 24, color: Color = BROWN) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func plate(inner: Control, pad: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(CREAM.r, CREAM.g, CREAM.b, 0.92), 16, BROWN_L, 3, pad))
	p.add_child(inner)
	return p
