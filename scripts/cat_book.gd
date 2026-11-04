class_name CatBook
extends CanvasLayer
## «Книга котов»: все коты кафе. Открытые показаны с мордочкой, любимым напитком и сердечками (симпатия растёт с каждым заказом;
## на 5-м, 15-м и 30-м заказе открывается запись — реплика кота — и дают монеты). Закрытые — «???» и подсказка, как их позвать.
## Тап по открытому коту показывает последнюю открытую реплику.

signal closed

const PER_PAGE := 4
const CARD_H := 84.0
const CARD_GAP := 4.0
const X := 12.0
const W := 336.0
const FRAME := Rect2(0, 16, 16, 16)

var _page := 0
var _root: Control


func _init() -> void:
	layer = 7


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()


func page_count() -> int:
	return maxi(1, int(ceil(float(Data.cats.size()) / float(PER_PAGE))))


func _build() -> void:
	for ch in _root.get_children():
		ch.queue_free()
	var dim := ColorRect.new()
	dim.size = Vector2(360, 640)
	dim.color = Color(0, 0, 0, 0.55)
	_root.add_child(dim)
	var content_h := PER_PAGE * CARD_H + (PER_PAGE - 1) * CARD_GAP + Ui.BTN_GAP + Ui.BTN_H
	var h := Ui.page_height(content_h)
	var top := floorf((640.0 - h) / 2.0 / 2.0) * 2.0
	Ui.panel(Rect2(X, top, W, h), Ui.UI_WOOD, _root)
	Ui.label(tr("Коты"), Rect2(X, top + Ui.PAGE_PAD_TOP, W, Ui.PAGE_TITLE_H), Ui.FONT_SIZE, Ui.INK, _root, HORIZONTAL_ALIGNMENT_CENTER)
	var cx := X + Ui.PAGE_PAD_X
	var cw := W - 2.0 * Ui.PAGE_PAD_X
	var y := top + Ui.PAGE_PAD_TOP + Ui.PAGE_TITLE_H + Ui.PAGE_GAP
	_page = clampi(_page, 0, page_count() - 1)
	var first := _page * PER_PAGE
	for i in range(first, mini(Data.cats.size(), first + PER_PAGE)):
		_card(Data.cats[i], cx, y, cw)
		y += CARD_H + CARD_GAP
	var by := top + h - Ui.PAGE_PAD_BOTTOM - Ui.BTN_H
	var half := (cw - Ui.BTN_GAP) / 2.0
	Ui.button(tr("Назад"), Rect2(cx, by, half, Ui.BTN_H), "undo", _root).pressed.connect(_close)
	Ui.button(tr("Дальше") if _page < page_count() - 1 else tr("Раньше"), Rect2(cx + half + Ui.BTN_GAP, by, half, Ui.BTN_H), "", _root).pressed.connect(_turn)


func is_known(def: Dictionary) -> bool:
	return bool(def.get("starter", false)) or GameState.has_unlock("cat:%s" % String(def["id"]))


## Как позвать закрытого кота: задача ремонта, которая его открывает.
func hint_for(cat_id: String) -> String:
	for r in Data.repairs:
		for e in r.get("effects", []):
			if String(e["kind"]) == "unlock" and String(e["key"]) == "cat:%s" % cat_id:
				return tr("Ремонт: %s") % tr(String(r["name"]))
	return ""


func _card(def: Dictionary, cx: float, y: float, cw: float) -> void:
	var known := is_known(def)
	var b := Ui.button("", Rect2(cx, y, cw, CARD_H), "", _root)
	b.modulate = Color.WHITE if known else Color(0.62, 0.62, 0.62)
	b.pressed.connect(_say.bind(String(def["id"])))
	var face := Sprite2D.new()
	face.texture = load("res://assets/cats/%s" % String(def["sprite"])) as Texture2D
	face.region_enabled = true
	face.region_rect = FRAME
	face.scale = Vector2(3, 3)
	face.position = Vector2(cx + 12.0 + 24.0, y + Ui.EDGE + (CARD_H - Ui.EDGE - Ui.SHADOW_BUTTON) / 2.0)
	face.modulate = Color(String(def.get("tint", "#ffffff"))) if known else Color(0.1, 0.08, 0.12)
	_root.add_child(face)
	var tx := cx + 12.0 + 48.0 + 8.0
	var tw := cw - (tx - cx) - 12.0
	var name_text := tr(String(def["name"])) if known else "???"
	Ui.label(name_text, Rect2(tx, y + 12.0, tw - 70.0, Ui.LINE_H), Ui.FONT_SIZE, Ui.CREAM, _root, HORIZONTAL_ALIGNMENT_LEFT, true)
	var sub := ""
	if known:
		sub = tr("Любит: %s") % tr(String(Data.drinks[String(def["fav_drink"])]["name"])).to_lower()
		var n := GameState.cat_entries(String(def["id"]))
		var hearts := Ui.label("♥".repeat(n) + "♡".repeat(3 - n), Rect2(tx + tw - 66.0, y + 12.0, 66.0, Ui.LINE_H), Ui.FONT_SIZE, Color("ff7a8a"), _root, HORIZONTAL_ALIGNMENT_RIGHT)
		hearts.add_theme_color_override("font_outline_color", Ui.INK)
		hearts.add_theme_constant_override("outline_size", Ui.PX)
	else:
		sub = hint_for(String(def["id"]))
	Ui.label(sub, Rect2(tx, y + 12.0 + Ui.LINE_H, tw, Ui.LINE_H), Ui.FONT_SIZE, Ui.CREAM.darkened(0.15), _root, HORIZONTAL_ALIGNMENT_LEFT, true)


## Последняя открытая реплика кота (тап по карточке).
func _say(cat_id: String) -> void:
	for c in Data.cats:
		if String(c["id"]) != cat_id or not is_known(c):
			continue
		var n := GameState.cat_entries(cat_id)
		var text := tr("Ещё %d заказов — и расскажу.") % (int(GameState.LIKE_STEPS[0]) - GameState.cat_likes(cat_id)) if n == 0 else tr(String(c["lines"][n - 1]))
		Ui.toast(_root, text, Vector2(180, 560))
		Audio.sfx("meow1" if randf() < 0.5 else "meow2", 0.08, -4.0)


func _turn() -> void:
	_page = (_page + 1) % page_count()
	_build()


func _close() -> void:
	closed.emit()
	queue_free()
