class_name PixelSlider
extends Control
## Ползунок в пиксельном стиле (сетка 2 px): шкала с обводкой, жёлтая заливка, квадратная ручка. Тянется пальцем или мышью по всей полосе;
## значение 0…1 с шагом STEP. value_changed — во время перетаскивания, released — когда палец отпущен (там сохраняем и играем пример звука).

signal value_changed(v: float)
signal released(v: float)

const STEP := 0.05
const TRACK_H := 16.0
const KNOB_W := 20.0
const KNOB_H := 32.0
const INK := Color("3b2a3d")
const EMPTY := Color("6b5640")
const FILL := Color("ffd640")
const FILL_D := Color("c2891a")
const KNOB := Color("fff1d6")
const KNOB_D := Color("d8c39a")

var value := 0.8:
	set(v):
		value = clampf(snappedf(v, STEP), 0.0, 1.0)
		queue_redraw()
var _drag := false


func _init(p_size := Vector2(160, 40)) -> void:
	custom_minimum_size = p_size
	size = p_size
	mouse_filter = Control.MOUSE_FILTER_STOP


func _span() -> Vector2:   # x0 и x1 центра ручки
	return Vector2(KNOB_W / 2.0, size.x - KNOB_W / 2.0)


func _knob_x() -> float:
	var s := _span()
	return snappedf(lerpf(s.x, s.y, value), 2.0)


func _gui_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.button_index == MOUSE_BUTTON_LEFT:
		_drag = press.pressed
		if press.pressed:
			_set_from_x(press.position.x)
		else:
			released.emit(value)
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		_set_from_x((event as InputEventMouseMotion).position.x)
		accept_event()


func _set_from_x(x: float) -> void:
	var s := _span()
	var old := value
	value = inverse_lerp(s.x, s.y, x)
	if not is_equal_approx(old, value):
		value_changed.emit(value)


func _draw() -> void:
	var ty := snappedf((size.y - TRACK_H) / 2.0, 2.0)
	var kx := _knob_x()
	draw_rect(Rect2(0, ty, size.x, TRACK_H), INK)
	draw_rect(Rect2(4, ty + 4, size.x - 8, TRACK_H - 8), EMPTY)
	if value > 0.0:
		var w := maxf(0.0, kx - 4.0)
		draw_rect(Rect2(4, ty + 4, w, TRACK_H - 8), FILL)
		draw_rect(Rect2(4, ty + 4, w, 4), FILL.lightened(0.25))
		draw_rect(Rect2(4, ty + TRACK_H - 8, w, 4), FILL_D)
	var ky := snappedf((size.y - KNOB_H) / 2.0, 2.0)
	draw_rect(Rect2(kx - KNOB_W / 2.0, ky, KNOB_W, KNOB_H), INK)
	draw_rect(Rect2(kx - KNOB_W / 2.0 + 4, ky + 4, KNOB_W - 8, KNOB_H - 8), KNOB)
	draw_rect(Rect2(kx - KNOB_W / 2.0 + 4, ky + KNOB_H - 12, KNOB_W - 8, 8), KNOB_D)
	draw_rect(Rect2(kx - 2, ky + 10, 4, KNOB_H - 20), INK.lightened(0.5))   # риска на ручке
