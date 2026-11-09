extends Node
## Игровое время = системное время устройства (+ тестовое смещение).
## Отвечает за: час/день/месяц, сезон с учётом полушария, фазу суток.

signal hour_changed(hour: int)
signal day_changed(day_index: int)

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const SEASON_NAMES: Array[String] = ["Весна", "Лето", "Осень", "Зима"]
const MONTH_GEN: Array[String] = [
	"января", "февраля", "марта", "апреля", "мая", "июня",
	"июля", "августа", "сентября", "октября", "ноября", "декабря",
]
const WEEKDAYS: Array[String] = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]

## Тестовое смещение (секунды). Сохраняется в профиль только как «читерский» флаг.
var debug_offset_sec: float = 0.0
var hemisphere: int = 0 # 0 — Северное, 1 — Южное

var _last_hour: int = -1
var _last_day: int = -1


func _process(_delta: float) -> void:
	var h: int = hour()
	var d: int = day_index()
	if _last_hour == -1:
		_last_hour = h
		_last_day = d
		return
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
	if d != _last_day:
		_last_day = d
		day_changed.emit(d)


func local_unix() -> float:
	var tz: Dictionary = Time.get_time_zone_from_system()
	return Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0 + debug_offset_sec


func now() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(local_unix()))


func hour() -> int:
	return int(now().hour)


func hour_float() -> float:
	var n: Dictionary = now()
	return float(n.hour) + float(n.minute) / 60.0 + float(n.second) / 3600.0


func day_index() -> int:
	return int(floor(local_unix() / 86400.0))


func month() -> int:
	return int(now().month)


func day_of_month() -> int:
	return int(now().day)


func weekday_name() -> String:
	return WEEKDAYS[int(now().weekday)]


func time_string() -> String:
	var n: Dictionary = now()
	return "%02d:%02d" % [n.hour, n.minute]


func date_string() -> String:
	var n: Dictionary = now()
	return "%d %s, %s" % [n.day, MONTH_GEN[int(n.month) - 1], weekday_name()]


## Сезон по месяцу с учётом полушария.
func season_for(month_1_12: int, hemi: int = -1) -> int:
	if hemi < 0:
		hemi = hemisphere
	var m: int = month_1_12 if hemi == 0 else ((month_1_12 + 5) % 12) + 1
	# 1..12 -> зима, зима, весна, весна, весна, лето, лето, лето, осень, осень, осень, зима
	var table: Array[int] = [3, 3, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3]
	return table[m - 1]


func season() -> int:
	return season_for(month())


func season_name() -> String:
	return SEASON_NAMES[season()]


## Непрерывная «фаза года» в месяцах (0..12), сдвинутая под полушарие.
func year_phase() -> float:
	var n: Dictionary = now()
	var dim: float = 30.0
	var p: float = float(int(n.month) - 1) + float(int(n.day) - 1) / dim
	if hemisphere == 1:
		p = fposmod(p + 6.0, 12.0)
	return p


func is_night() -> bool:
	var h: float = hour_float()
	return h < 5.5 or h >= 20.5


func part_of_day() -> String:
	var h: float = hour_float()
	if h < 5.0 or h >= 22.0:
		return "ночь"
	if h < 11.0:
		return "утро"
	if h < 17.0:
		return "день"
	return "вечер"


func add_debug_hours(hours: float) -> void:
	debug_offset_sec += hours * 3600.0


static func plural(n: int, one: String, few: String, many: String) -> String:
	var a: int = absi(n) % 100
	var b: int = a % 10
	if a > 10 and a < 20:
		return many
	if b == 1:
		return one
	if b >= 2 and b <= 4:
		return few
	return many
