extends Node
## Autoload "TimeOfDay": игровые часы и палитра суток (освещение мира, цвета неба).
## Сутки идут DAY_SECONDS реальных секунд. Час хранится в сохранении (GameState).

const DAY_SECONDS := 360.0   # 15 реальных секунд на игровой час

## Ключевые точки суток: час, свет мира (множитель цвета), верх неба, низ неба, «ночь» 0..1.
## Между точками значения плавно смешиваются; 24 ч замыкается на 0 ч.
const KEYS := [
	[0.0, Color(0.30, 0.35, 0.62), Color(0.04, 0.06, 0.16), Color(0.10, 0.13, 0.28), 1.0],
	[5.0, Color(0.38, 0.40, 0.66), Color(0.10, 0.12, 0.28), Color(0.35, 0.28, 0.45), 0.9],
	[6.5, Color(1.00, 0.78, 0.70), Color(0.45, 0.55, 0.85), Color(1.00, 0.72, 0.55), 0.35],
	[8.5, Color(1.00, 0.97, 0.92), Color(0.38, 0.65, 0.95), Color(0.70, 0.86, 0.98), 0.0],
	[16.0, Color(1.00, 1.00, 1.00), Color(0.38, 0.65, 0.95), Color(0.70, 0.86, 0.98), 0.0],
	[17.8, Color(1.00, 0.88, 0.72), Color(0.40, 0.58, 0.88), Color(0.98, 0.78, 0.55), 0.1],
	[19.0, Color(0.95, 0.62, 0.55), Color(0.32, 0.28, 0.55), Color(0.98, 0.50, 0.38), 0.5],
	[20.5, Color(0.50, 0.45, 0.70), Color(0.10, 0.10, 0.28), Color(0.38, 0.28, 0.50), 0.85],
	[22.0, Color(0.32, 0.36, 0.62), Color(0.05, 0.07, 0.18), Color(0.12, 0.15, 0.30), 1.0],
	[24.0, Color(0.30, 0.35, 0.62), Color(0.04, 0.06, 0.16), Color(0.10, 0.13, 0.28), 1.0],
]

var hour: float = 9.0   # 0..24


func _process(delta: float) -> void:
	hour = fposmod(hour + delta * 24.0 / DAY_SECONDS, 24.0)


## Перемотать время вперёд на `hours` часов.
func skip(hours: float) -> void:
	hour = fposmod(hour + hours, 24.0)


func clock_text() -> String:
	var h := int(hour)
	return "%02d:%02d" % [h, int((hour - h) * 6.0) * 10]


## Свет, которым окрашивается улица (умножается на цвета спрайтов).
func ambient() -> Color:
	return _sample(1)


func sky_top() -> Color:
	return _sample(2)


func sky_bottom() -> Color:
	return _sample(3)


## 0 — день, 1 — глубокая ночь. Определяет, насколько горят окна и фонари.
func night() -> float:
	return _sample_float(4)


## Цвет света внутри кафе: ночью там горят лампы, поэтому он теплее и ярче улицы.
func indoor() -> Color:
	return ambient().lerp(Color(1.0, 0.86, 0.66), night() * 0.8)


## Положение дневного светила 0..1 по дуге (6:00..19:00 — солнце), иначе -1.
func sun_progress() -> float:
	return (hour - 6.0) / 13.0 if hour >= 6.0 and hour <= 19.0 else -1.0


## Положение луны 0..1 по дуге (19:00..6:00), иначе -1.
func moon_progress() -> float:
	if hour >= 19.0:
		return (hour - 19.0) / 11.0
	if hour <= 6.0:
		return (hour + 5.0) / 11.0
	return -1.0


func _segment() -> Array:
	for i in KEYS.size() - 1:
		if hour >= float(KEYS[i][0]) and hour <= float(KEYS[i + 1][0]):
			var a: float = KEYS[i][0]
			var b: float = KEYS[i + 1][0]
			return [i, (hour - a) / (b - a)]
	return [0, 0.0]


func _sample(idx: int) -> Color:
	var seg := _segment()
	return (KEYS[seg[0]][idx] as Color).lerp(KEYS[seg[0] + 1][idx] as Color, seg[1])


func _sample_float(idx: int) -> float:
	var seg := _segment()
	return lerpf(float(KEYS[seg[0]][idx]), float(KEYS[seg[0] + 1][idx]), seg[1])
