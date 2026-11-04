class_name Quality
extends RefCounted
## Уровень качества графики: "auto" (по замеру кадров и железу), "low", "high" (GameState.settings["quality"]).
## Низкое качество: вдвое меньше частиц, снег реже, эффекты тумана/дождя/жары на весь экран выключены, меньше гостей на улице.
## «Авто» начинает с высокого (на слабом телефоне с ≤ 4 ядрами — с низкого) и один раз за сеанс понижается, если средний FPS ниже порога.

const FPS_FLOOR := 40.0       # средний FPS ниже — переходим на низкое
const SAMPLE_SECONDS := 6.0   # окно замера (после 2 с прогрева)
const WARMUP_SECONDS := 2.0

static var measured_low := false
static var _acc := 0.0
static var _frames := 0
static var _clock := 0.0
static var _done := false


static func setting() -> String:
	return String(GameState.get_setting("quality"))


static func low() -> bool:
	match setting():
		"low":
			return true
		"high":
			return false
	return measured_low or (OS.has_feature("mobile") and OS.get_processor_count() <= 4)


## Множитель количества частиц и эффектов.
static func scale() -> float:
	return 0.5 if low() else 1.0


static func count(n: int) -> int:
	return maxi(1, int(ceil(n * scale()))) if n > 0 else 0


## Города зовут каждый кадр: копит замер и при «авто» понижает качество, если кадров мало. Возвращает true в момент переключения.
static func sample(delta: float) -> bool:
	if _done or setting() != "auto":
		return false
	_clock += delta
	if _clock < WARMUP_SECONDS:
		return false
	_acc += delta
	_frames += 1
	if _acc >= SAMPLE_SECONDS:
		_done = true
		var fps := float(_frames) / _acc
		Platform.track("quality_probe", {"fps": snappedf(fps, 0.1), "low": fps < FPS_FLOOR, "cores": OS.get_processor_count()})
		if fps < FPS_FLOOR:
			measured_low = true
			return true
	return false


static func reset_probe() -> void:
	measured_low = false
	_acc = 0.0
	_frames = 0
	_clock = 0.0
	_done = false
