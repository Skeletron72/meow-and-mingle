class_name PerfOverlay
extends CanvasLayer
## Отладочная панель производительности (F2; только отладочные сборки): FPS, вызовы отрисовки, объекты, память, уровень качества.
## Нужна, чтобы на слабом телефоне сразу видеть, что тормозит: профиль и пороги — docs/release/04-technical-export.md.

var _label: Label
var _t := 0.0


func _init() -> void:
	layer = 100
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(4, 44)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("b6ff8a"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F2:
		visible = not visible


func _process(delta: float) -> void:
	_t += delta
	if not visible or _t < 0.5:
		return
	_t = 0.0
	_label.text = "FPS %d  кадр %.1f мс\nвызовов %d  объектов %d\nпамять %.0f МБ  видео %.0f МБ\nкачество: %s (%s)" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"низкое" if Quality.low() else "высокое", Quality.setting()]
