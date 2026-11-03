extends Node
## Погода: ясно, дождь, туман, жара, снег. Меняется сама (авто) или фиксируется в настройках.
##
## Интенсивности плавно приходят к цели; снежный покров копится, пока идёт снег, и тает без него (в жару — быстрее);
## влажность земли растёт под дождём и сохнет. Всё это отдаётся шейдерам глобальными параметрами (project.godot → shader_globals):
## surface-шейдеры (земля, деревья, здания) рисуют снег и лужи, экранный шейдер (scripts/weather_fx.gd) — капли, снежинки,
## туман и марево. Игра читает здесь же освещение (overcast, tint) и подсветку окон в пасмурную погоду.

signal changed(kind: int)

enum Kind { CLEAR, RAIN, FOG, HEAT, SNOW }

const NAMES := ["Ясно", "Дождь", "Туман", "Жара", "Снег"]
const AUTO := -1
const AUTO_WEIGHTS := [38.0, 22.0, 12.0, 14.0, 14.0]   # шансы следующей погоды в авто-режиме
const FADE_TIME := 6.0         # секунд на плавный переход
const SNOW_BUILD := 1.0 / 40.0  # покров в секунду, пока идёт снег
const SNOW_MELT := 1.0 / 90.0
const SNOW_MELT_HEAT := 1.0 / 20.0
const WET_BUILD := 1.0 / 14.0
const WET_DRY := 1.0 / 60.0

var mode := AUTO               # AUTO или конкретный Kind (меняется в настройках, хранится в сохранении)
var kind := Kind.CLEAR         # текущая погода
var rain := 0.0
var fog := 0.0
var heat := 0.0
var snowfall := 0.0
var snow_cover := 0.0
var wet := 0.0
var _timer := 45.0


func _ready() -> void:
	_push()


func _process(delta: float) -> void:
	if mode == AUTO:
		_timer -= delta
		if _timer <= 0.0:
			_set_kind(_pick(), false)
			_timer = randf_range(70.0, 150.0)
	step(delta)


## Один шаг симуляции (отдельно — чтобы тесты могли гнать время).
func step(delta: float) -> void:
	var k := delta / FADE_TIME
	rain = move_toward(rain, 1.0 if kind == Kind.RAIN else 0.0, k)
	fog = move_toward(fog, 1.0 if kind == Kind.FOG else 0.0, k)
	heat = move_toward(heat, 1.0 if kind == Kind.HEAT else 0.0, k)
	snowfall = move_toward(snowfall, 1.0 if kind == Kind.SNOW else 0.0, k)
	if snowfall > 0.3:
		snow_cover = move_toward(snow_cover, 1.0, SNOW_BUILD * delta * snowfall)
	else:
		snow_cover = move_toward(snow_cover, 0.0, (SNOW_MELT_HEAT if heat > 0.3 else SNOW_MELT) * delta)
	if rain > 0.3:
		wet = move_toward(wet, 1.0, WET_BUILD * delta * rain)
	else:
		wet = move_toward(wet, 0.0, WET_DRY * delta * (3.0 if heat > 0.3 else 1.0))
	if snow_cover > 0.2:
		wet = move_toward(wet, 0.0, 0.05 * delta)
	_push()


## Выбор режима из настроек: AUTO или Kind. Конкретная погода включается сразу.
func set_mode(m: int) -> void:
	mode = m
	if m != AUTO:
		_set_kind(m, true)
	else:
		_timer = 20.0


## Следующий пункт в настройках: Авто → Ясно → Дождь → Туман → Жара → Снег → Авто.
func cycle_mode() -> void:
	set_mode(AUTO if mode == Kind.SNOW else mode + 1)


func mode_text() -> String:
	return "Авто" if mode == AUTO else NAMES[mode]


## Мгновенно, без плавности и случайности — для тестов, скриншотов и новой сцены: kind, интенсивность, покров.
func force(k: int, cover := 0.0, wet_level := 0.0) -> void:
	mode = k
	kind = k as Kind
	rain = 1.0 if k == Kind.RAIN else 0.0
	fog = 1.0 if k == Kind.FOG else 0.0
	heat = 1.0 if k == Kind.HEAT else 0.0
	snowfall = 1.0 if k == Kind.SNOW else 0.0
	snow_cover = cover
	wet = wet_level
	_push()


## Насколько пасмурно, 0..1: рисует небо серым, зажигает окна и фары раньше.
func overcast() -> float:
	return maxf(maxf(rain * 0.75, fog * 0.6), snowfall * 0.55)


## Множитель освещения улицы (умножается на ambient времени суток).
func tint() -> Color:
	var c := Color.WHITE
	c = c.lerp(Color(0.72, 0.78, 0.9), rain)
	c = c.lerp(Color(0.9, 0.92, 0.95), fog * 0.8)
	c = c.lerp(Color(1.0, 0.95, 0.82), heat)
	c = c.lerp(Color(0.86, 0.92, 1.0), snowfall * 0.7 + snow_cover * 0.15)
	return c


## Цвет неба с учётом погоды: пасмурное небо серое.
func sky(c: Color) -> Color:
	var grey := Color(c.get_luminance() * 0.95 + 0.04, c.get_luminance() * 0.97 + 0.05, c.get_luminance() * 1.02 + 0.06)
	var out := c.lerp(grey, overcast() * 0.8)
	out = out.lerp(Color(1.0, 0.9, 0.62), heat * 0.25)   # жара: выцветшее тёплое небо
	return out


func _set_kind(k: int, instant: bool) -> void:
	if k == kind:
		return
	kind = k as Kind
	changed.emit(k)


func _pick() -> int:
	var total := 0.0
	for w in AUTO_WEIGHTS:
		total += w
	var r := randf() * total
	for i in AUTO_WEIGHTS.size():
		r -= AUTO_WEIGHTS[i]
		if r <= 0.0:
			return i
	return Kind.CLEAR


func _push() -> void:
	RenderingServer.global_shader_parameter_set("weather_snow", snow_cover)
	RenderingServer.global_shader_parameter_set("weather_wet", wet)
	RenderingServer.global_shader_parameter_set("weather_rain", rain)
	RenderingServer.global_shader_parameter_set("weather_snowfall", snowfall)
	RenderingServer.global_shader_parameter_set("weather_fog", fog)
	RenderingServer.global_shader_parameter_set("weather_heat", heat)
