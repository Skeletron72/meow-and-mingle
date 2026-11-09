class_name ItemIcon
extends Control
## Рисует значок предмета кодом (без картинок).

var item_id: String = ""
var count: int = 0
var selected: bool = false
var show_bg: bool = true


func _init(id: String = "", cnt: int = 0) -> void:
	item_id = id
	count = cnt
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_item(id: String, cnt: int = 0) -> void:
	item_id = id
	count = cnt
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	var c: Vector2 = s * 0.5
	var r: float = minf(s.x, s.y) * 0.5
	if show_bg:
		draw_circle(c, r * 0.96, Color(0.96, 0.90, 0.76) if not selected else Color(1.0, 0.88, 0.5))
		draw_arc(c, r * 0.96, 0, TAU, 32, UiKit.BROWN_L if not selected else UiKit.CORAL, 3.0, true)
	if item_id == "":
		return
	var d: Dictionary = Data.item(item_id)
	var ca: Array = d.get("color", [0.6, 0.6, 0.6])
	var col := Color(ca[0], ca[1], ca[2])
	var dark: Color = col.darkened(0.35)
	var u: float = r * 0.62
	match str(d.get("shape", "junk")):
		"fruit":
			draw_circle(c + Vector2(0, u * 0.1), u * 0.72, col)
			draw_circle(c + Vector2(-u * 0.25, -u * 0.1), u * 0.18, col.lightened(0.4))
			draw_line(c + Vector2(0, -u * 0.5), c + Vector2(u * 0.08, -u * 0.85), Color(0.4, 0.28, 0.2), 3.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(u * 0.1, -u * 0.7), c + Vector2(u * 0.55, -u * 0.9), c + Vector2(u * 0.35, -u * 0.5)]), Color(0.4, 0.7, 0.3))
		"flower":
			for i in 5:
				var a: float = TAU * float(i) / 5.0 - PI * 0.5
				draw_circle(c + Vector2(cos(a), sin(a)) * u * 0.42, u * 0.3, col)
			draw_circle(c, u * 0.22, Color(1, 0.85, 0.3))
		"fish":
			draw_colored_polygon(_ellipse(c + Vector2(-u * 0.1, 0), u * 0.75, u * 0.42), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(u * 0.55, 0), c + Vector2(u * 0.95, -u * 0.4), c + Vector2(u * 0.95, u * 0.4)]), dark)
			draw_circle(c + Vector2(-u * 0.45, -u * 0.08), u * 0.08, Color(0.1, 0.1, 0.12))
			draw_colored_polygon(_ellipse(c + Vector2(-u * 0.05, u * 0.12), u * 0.4, u * 0.14), col.lightened(0.3))
		"bug":
			draw_colored_polygon(_ellipse(c + Vector2(-u * 0.4, -u * 0.2), u * 0.5, u * 0.34), col)
			draw_colored_polygon(_ellipse(c + Vector2(u * 0.4, -u * 0.2), u * 0.5, u * 0.34), col.lightened(0.15))
			draw_colored_polygon(_ellipse(c + Vector2(0, u * 0.2), u * 0.14, u * 0.5), dark)
		"net":
			draw_line(c + Vector2(u * 0.7, u * 0.8), c + Vector2(-u * 0.15, -u * 0.1), Color(0.55, 0.38, 0.26), 5.0)
			draw_arc(c + Vector2(-u * 0.35, -u * 0.4), u * 0.55, 0, TAU, 20, col, 4.0)
			draw_circle(c + Vector2(-u * 0.35, -u * 0.4), u * 0.45, Color(col.r, col.g, col.b, 0.35))
		"rod":
			draw_line(c + Vector2(-u * 0.8, u * 0.8), c + Vector2(u * 0.75, -u * 0.8), col, 5.0)
			draw_line(c + Vector2(u * 0.75, -u * 0.8), c + Vector2(u * 0.75, u * 0.2), Color(0.3, 0.3, 0.3), 2.0)
			draw_circle(c + Vector2(u * 0.75, u * 0.3), u * 0.12, Color(0.9, 0.3, 0.3))
		"shovel":
			draw_line(c + Vector2(u * 0.6, -u * 0.8), c + Vector2(-u * 0.1, u * 0.1), Color(0.55, 0.38, 0.26), 5.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.5, u * 0.0), c + Vector2(u * 0.05, u * 0.05), c + Vector2(-u * 0.1, u * 0.8), c + Vector2(-u * 0.7, u * 0.5)]), col)
		"seed":
			for p in [Vector2(-0.35, 0.1), Vector2(0.1, -0.25), Vector2(0.35, 0.3)]:
				draw_colored_polygon(_ellipse(c + p * u, u * 0.22, u * 0.32), col)
			draw_circle(c + Vector2(0, u * 0.7), u * 0.1, Color(0.5, 0.36, 0.25))
		"sapling":
			draw_line(c + Vector2(0, u * 0.8), c + Vector2(0, -u * 0.1), Color(0.5, 0.36, 0.25), 4.0)
			draw_circle(c + Vector2(-u * 0.3, -u * 0.2), u * 0.35, Color(0.45, 0.72, 0.35))
			draw_circle(c + Vector2(u * 0.3, -u * 0.4), u * 0.4, Color(0.5, 0.78, 0.38))
			draw_circle(c + Vector2(0.0, -u * 0.6), u * 0.1, col)
			draw_colored_polygon(_ellipse(c + Vector2(0, u * 0.85), u * 0.5, u * 0.15), Color(0.5, 0.36, 0.25))
		"key":
			draw_arc(c + Vector2(-u * 0.4, -u * 0.3), u * 0.35, 0, TAU, 16, col, 5.0)
			draw_line(c + Vector2(-u * 0.2, -u * 0.1), c + Vector2(u * 0.7, u * 0.7), col, 5.0)
			draw_line(c + Vector2(u * 0.4, u * 0.4), c + Vector2(u * 0.15, u * 0.65), col, 4.0)
		"button":
			draw_circle(c, u * 0.8, col)
			draw_circle(c, u * 0.58, col.darkened(0.15))
			for p in [Vector2(-0.18, -0.18), Vector2(0.18, -0.18), Vector2(-0.18, 0.18), Vector2(0.18, 0.18)]:
				draw_circle(c + p * u, u * 0.07, col.lightened(0.5))
		_:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.5, -u * 0.6), c + Vector2(u * 0.1, -u * 0.6), c + Vector2(u * 0.15, u * 0.1), c + Vector2(u * 0.7, u * 0.3), c + Vector2(u * 0.7, u * 0.6), c + Vector2(-u * 0.5, u * 0.6)]), col)
	if count > 1:
		var f: Font = ThemeDB.fallback_font
		var txt: String = str(count)
		var fs: int = int(r * 0.55)
		var tp: Vector2 = Vector2(s.x - r * 0.15 - f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, s.y - r * 0.12)
		draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.99, 0.95, 0.86))
		draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.BROWN)


func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
