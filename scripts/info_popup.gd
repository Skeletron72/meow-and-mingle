class_name InfoPopup
extends CanvasLayer
## Окно с заголовком, текстом и до трёх кнопок (подтверждения, предложения, итоги). chosen(index) — номер нажатой кнопки; окно закрывается само.
## Построение: InfoPopup.open(parent, "Заголовок", "Текст", ["Кнопка 1", "Кнопка 2"]).

signal chosen(index: int)

const W := 312.0
const BODY_LINE := 28.0

var title := ""
var body := ""
var buttons: Array[String] = []
var icons: Array[String] = []
var danger_last := false


static func open(parent: Node, p_title: String, p_body: String, p_buttons: Array[String], p_icons: Array[String] = []) -> InfoPopup:
	var p := InfoPopup.new()
	p.title = p_title
	p.body = p_body
	p.buttons = p_buttons
	p.icons = p_icons
	parent.add_child(p)
	return p


func _init() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	var inner_w := W - 2.0 * Ui.PAGE_PAD_X
	var lines := _wrapped_lines(tr(body), inner_w)
	var body_h := BODY_LINE * lines
	var content_h := body_h + Ui.BTN_GAP + Ui.column_h(buttons.size())
	var h := Ui.page_height(content_h)
	var x := (360.0 - W) / 2.0
	var top := floorf((640.0 - h) / 2.0 / 2.0) * 2.0
	Ui.panel(Rect2(x, top, W, h), Ui.UI_WOOD, self)
	Ui.label(tr(title), Rect2(x, top + Ui.PAGE_PAD_TOP, W, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, self, HORIZONTAL_ALIGNMENT_CENTER)
	var cx := x + Ui.PAGE_PAD_X
	var y := top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + Ui.PAGE_GAP
	var l := Ui.label(tr(body), Rect2(cx, y, inner_w, body_h), Ui.FONT_SIZE, Ui.INK, self, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.position = Vector2(cx, y)
	l.size = Vector2(inner_w, body_h)
	y += body_h + Ui.BTN_GAP
	for i in buttons.size():
		var b := Ui.button(tr(buttons[i]), Rect2(cx, y + i * (Ui.BTN_H + Ui.BTN_GAP), inner_w, Ui.BTN_H), icons[i] if i < icons.size() else "", self, false, null, danger_last and i == buttons.size() - 1)
		b.pressed.connect(_pick.bind(i))


## Сколько строк займёт текст при переносе по словам в ширину w (узкий шрифт, как у подписи).
func _wrapped_lines(text: String, w: float) -> int:
	var total := 0
	for para in text.split("\n"):
		var cur := ""
		var n := 1
		for word in para.split(" "):
			var trial := word if cur == "" else cur + " " + word
			if Ui.FONT_NARROW.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.FONT_SIZE).x > w and cur != "":
				n += 1
				cur = word
			else:
				cur = trial
		total += n
	return maxi(1, total)


func _pick(i: int) -> void:
	chosen.emit(i)
	queue_free()
