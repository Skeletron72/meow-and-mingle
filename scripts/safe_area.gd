class_name SafeArea
extends RefCounted
## Безопасная зона экрана (вырез камеры, скруглённые углы, жестовая панель). Игра идёт в окне 360×640 с чёрными полями (stretch aspect=keep),
## поэтому на вытянутых телефонах вырез обычно попадает в чёрное поле и поправка равна нулю; на экранах 16:9 с вырезом она отодвигает интерфейс.

## Отступы в логических пикселях игры: (слева, сверху, справа, снизу). win — размер окна в пикселях, safe — безопасная область в пикселях окна.
static func logical_insets(win: Vector2, safe: Rect2) -> Vector4:
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return Vector4.ZERO
	var scale := minf(win.x / 360.0, win.y / 640.0)
	var bar := Vector2((win.x - 360.0 * scale) / 2.0, (win.y - 640.0 * scale) / 2.0)   # чёрные поля слева-справа и сверху-снизу
	var left := maxf(0.0, safe.position.x - bar.x) / scale
	var top := maxf(0.0, safe.position.y - bar.y) / scale
	var right := maxf(0.0, (win.x - safe.end.x) - bar.x) / scale
	var bottom := maxf(0.0, (win.y - safe.end.y) - bar.y) / scale
	return Vector4(left, top, right, bottom)


## Текущие отступы устройства. Округляем вверх до чётного (сетка 2 px).
static func current() -> Vector4:
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var win := Vector2(DisplayServer.window_get_size())
	var v := logical_insets(win, safe)
	return Vector4(_even(v.x), _even(v.y), _even(v.z), _even(v.w))


static func _even(x: float) -> float:
	return ceilf(x / 2.0) * 2.0
