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
const FONT_MAIN: Font = preload("res://assets/fonts/Galmuri11.ttf")

## Замеры по пикселям (скриншот 720×1280, 1 px логики = 2 px экрана):
## - кремовая плашка и кнопка: тёмный контур сверху 2 px, внизу «бортик» 8 px (с контуром); по бокам контур 2 px;
## - деревянная рамка: контур и орнамент сверху и по бокам 8 px, снизу 14 px.
## Текст и кнопки внутри рамок держим по центру свободной области, с одинаковым воздухом (PAGE_AIR) со всех сторон.
const EDGE := 2.0                 # контур кремовой плашки и кнопки сверху и по бокам
const SHADOW_CREAM := 8.0         # низ кремовой плашки
const SHADOW_BUTTON := 8.0        # низ кнопки
const WOOD_EDGE := 8.0            # деревянная рамка: сверху и по бокам
const WOOD_BOTTOM := 14.0         # деревянная рамка: снизу
const PAGE_AIR := 16.0            # воздух от свободной области рамки до содержимого

## Раскладка страниц на деревянной рамке: содержимое отступает от края рамки на WOOD_EDGE + PAGE_AIR со всех сторон (снизу — WOOD_BOTTOM + PAGE_AIR),
## между заголовком, кнопками и низом — ровные промежутки.
const PAGE_PAD_TOP := 20.0        # метка заголовка: её цифры/заглавные начинаются на 4 px ниже верха строки, итого 8 + 16 до глифа
const PAGE_PAD_BOTTOM := 30.0     # 14 + 16
const PAGE_PAD_X := 24.0          # 8 + 16
const PAGE_TITLE_H := 28.0        # строка шрифта 28 px (глиф ~22–26)
const PAGE_GAP := 12.0
const BTN_H := 48.0
const BTN_GAP := 8.0

## Шрифт 24: строка 28 px, пиксели глифов — со 2-го по 27-й ряд (кириллица с «Ё»/«й» и хвостами «р, у, д»).
const LINE_H := 28.0
const GLYPH_TOP := 2.0
const GLYPH_BOTTOM := 28.0   # с хвостами; у цифр и заглавных без выносных — до 24
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
	"cloud": Rect2(272, 82, 16, 11),
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
	n.set_meta("outer", Rect2(r.position, (r.size / float(PX)).floor() * float(PX)))
	var sz := (r.size / float(PX)).floor() * float(PX)
	if tex == UI_WOOD:
		n.set_meta("inner", Rect2(r.position + Vector2(WOOD_EDGE, WOOD_EDGE), sz - Vector2(WOOD_EDGE * 2.0, WOOD_EDGE + WOOD_BOTTOM)))
	else:
		n.set_meta("inner", Rect2(r.position + Vector2(EDGE, EDGE), sz - Vector2(EDGE * 2.0, EDGE + SHADOW_CREAM)))
	parent.add_child(n)
	return n


## Подпись. Не прыгает и не лезет за рамку:
## - вертикально ставится на чётные пиксели (иначе строки шрифта съезжают на пол-пикселя сетки), всегда сверху вниз от рассчитанной точки;
## - если текст шире рамки, берётся узкий шрифт, а если и он не влезает — обрезается многоточием.
static func label(text: String, r: Rect2, font_size: int, color: Color, parent: Node, align := HORIZONTAL_ALIGNMENT_CENTER, narrow := false) -> Label:
	var l := Label.new()
	var font: Font = FONT_NARROW if narrow else FONT_MAIN
	var lines := text.split("\n")
	if not narrow and _text_width(font, lines, font_size) > r.size.x:   # автоподбор: длинная строка — узкий шрифт
		font = FONT_NARROW
		narrow = true
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if narrow:
		l.add_theme_font_override("font", FONT_NARROW)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var lh := font.get_height(font_size) * float(maxi(1, lines.size()))
	var top := floorf(maxf(0.0, r.size.y - lh) / 2.0 / float(PX)) * float(PX)   # чётный сдвиг от верха рамки
	l.position = Vector2(r.position.x, r.position.y + top)
	l.size = Vector2(r.size.x, maxf(lh, r.size.y - top))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func _text_width(font: Font, lines: PackedStringArray, font_size: int) -> float:
	var w := 0.0
	for line in lines:
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + float(PX) * 2.0)   # + обводка
	return w


## Область рамки без нижней тени: сюда ставим текст и кнопки.
static func page_height(content_h: float) -> float:
	return PAGE_PAD_TOP + PAGE_TITLE_H + PAGE_GAP + content_h + PAGE_PAD_BOTTOM


static func column_h(n: int) -> float:
	return n * BTN_H + maxi(0, n - 1) * BTN_GAP


static func inner(r: Rect2, shadow: float) -> Rect2:
	return Rect2(r.position, Vector2(r.size.x, r.size.y - shadow))


## Меняет подпись кнопки с проверкой «влезает»: длинная — узким шрифтом (иконка слева учитывается).
static func set_button_icon(b: Button, tex: Texture2D) -> void:
	var tr_: TextureRect = b.get_meta("icon_node", null)
	if tr_ == null:
		return
	tr_.texture = tex
	tr_.size = tex.get_size() * PX
	var x := 8.0
	tr_.position = Vector2(x, EDGE + floorf((b.size.y - EDGE - SHADOW_BUTTON - tr_.size.y) / (2.0 * PX)) * PX)


static func set_button_text(b: Button, text: String) -> void:
	var pad := 4.0 + (b.get_meta("icon_pad", 0.0) as float)
	var wide := FONT_MAIN.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + PX * 2.0 + pad + 4.0 > b.size.x - 8.0
	if wide:
		b.add_theme_font_override("font", FONT_NARROW)
	else:
		b.remove_theme_font_override("font")
	var keep := b.size
	b.text = text
	b.size = keep


## Кнопка на nine-patch. Без текста — кнопка-иконка. Размер округляется до чётного.
static func button(text: String, r: Rect2, icon_name: String, parent: Node, narrow := false, tex: Texture2D = null, danger := false) -> Button:
	var b := Button.new()
	var target := (r.size / float(PX)).floor() * float(PX)
	b.position = r.position
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	# у кнопки с иконкой и текстом слева остаётся место под иконку
	var pad := 0.0
	if icon_name != "" and text != "":
		pad = (ICON_RECTS[icon_name] as Rect2).size.x * PX + 8.0
	if not narrow and text != "" and FONT_MAIN.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 8.0 + PX * 2.0 + pad > target.x - 8.0:
		narrow = true   # длинная подпись на кнопке — узкий шрифт
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 4.0 + pad
		sb.content_margin_right = 4.0
		sb.content_margin_top = EDGE
		sb.content_margin_bottom = SHADOW_BUTTON   # текст по центру грани кнопки: между верхним контуром и нижним бортиком
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, CREAM)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", PX)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	if narrow:
		b.add_theme_font_override("font", FONT_NARROW)
	b.set_meta("icon_pad", pad)
	b.text = text   # текст — после шрифта: иначе кнопка успевает раздуться под широкий шрифт
	b.size = target
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
		tr_.position = Vector2(x, EDGE + floorf((b.size.y - EDGE - SHADOW_BUTTON - tr_.size.y) / (2.0 * PX)) * PX)
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr_)
		b.set_meta("icon_node", tr_)
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
