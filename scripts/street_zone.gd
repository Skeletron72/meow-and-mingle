@tool
class_name StreetZone
extends ReferenceRect
## Зона улицы. Двигайте и тяните рамку в редакторе (у неё есть ручки размера), тип выбирается в инспекторе.
## В игре зоны не видны; клавиша F3 показывает их поверх города.
##
##  WALK          — где можно ходить (тротуар); клетки по 32 px, в которые попадает центр клетки
##  BLOCK         — запрет ходьбы поверх WALK (лужа, ограда)
##  LANE_EAST/WEST— полоса движения машин вправо / влево. НИЗ рамки — линия колёс; ширина рамки — длина дороги
##  CAFE_INTERIOR — где стоит интерьер кафе (320×320). Верх-левый угол: x кратен 32, (y + 96) кратен 32
##  SIDEWALK/ROAD — только рисуются: плитка тротуара, асфальт
##  CROSSWALK     — зебра на дороге

enum Kind { WALK, BLOCK, LANE_EAST, LANE_WEST, CAFE_INTERIOR, SIDEWALK, ROAD, CROSSWALK }

const COLORS := {
	Kind.WALK: Color("4cc36e"), Kind.BLOCK: Color("e04b4b"), Kind.LANE_EAST: Color("4aa3ff"), Kind.LANE_WEST: Color("ffb347"),
	Kind.CAFE_INTERIOR: Color("c86bff"), Kind.SIDEWALK: Color("b9b2aa"), Kind.ROAD: Color("8a8fa0"), Kind.CROSSWALK: Color("f5f5f5"),
}
const LABELS := {
	Kind.WALK: "ходьба", Kind.BLOCK: "запрет", Kind.LANE_EAST: "машины →", Kind.LANE_WEST: "← машины",
	Kind.CAFE_INTERIOR: "интерьер кафе", Kind.SIDEWALK: "тротуар", Kind.ROAD: "дорога", Kind.CROSSWALK: "зебра",
}

static var show_in_game := false   # F3 в игре

@export var kind: Kind = Kind.WALK:
	set(value):
		kind = value
		_refresh()


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	border_color = COLORS[kind]
	border_width = 2.0
	editor_only = not show_in_game
	queue_redraw()
	update_configuration_warnings()


## Рамка зоны в мировых координатах.
func world_rect() -> Rect2:
	return Rect2(global_position, size)


func _draw() -> void:
	if not Engine.is_editor_hint() and not show_in_game:
		return
	var c: Color = COLORS[kind]
	draw_rect(Rect2(Vector2.ZERO, size), Color(c, 0.22))
	draw_string(ThemeDB.fallback_font, Vector2(6, 18), LABELS[kind], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(c, 1.0).lightened(0.3))


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if kind == Kind.CAFE_INTERIOR:
		if not is_zero_approx(fposmod(position.x, 32.0)) or not is_zero_approx(fposmod(position.y + 96.0, 32.0)):
			w.append("Угол интерьера: x кратен 32, (y + 96) кратен 32 — иначе пол кафе не попадёт в сетку ходьбы.")
		if not size.is_equal_approx(Vector2(320, 320)):
			w.append("Интерьер кафе — ровно 320×320.")
	if (kind == Kind.LANE_EAST or kind == Kind.LANE_WEST) and size.y < 80.0:
		w.append("Полоса ниже 80 px — машины будут вылезать за рамку (они ~80 px высотой).")
	return w
