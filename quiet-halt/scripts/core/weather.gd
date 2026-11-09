class_name Weather
extends RefCounted
## Детерминированный генератор погоды: одно и то же семя+дата дают одну погоду
## у всех игроков (пригодится для мультиплеера без синхронизации).

enum Type { CLEAR, CLOUDY, RAIN, FOG, SNOW }

const NAMES: Array[String] = ["Ясно", "Облачно", "Дождь", "Туман", "Снег"]

# Веса по сезонам: ясно, облачно, дождь, туман, снег
const WEIGHTS: Array = [
	[0.40, 0.25, 0.28, 0.07, 0.00], # весна
	[0.60, 0.20, 0.17, 0.03, 0.00], # лето
	[0.30, 0.30, 0.27, 0.13, 0.00], # осень
	[0.28, 0.28, 0.00, 0.10, 0.34], # зима
]


static func _rand01(world_seed: int, day: int, block: int, salt: int) -> float:
	var h: int = hash("%d|%d|%d|%d" % [world_seed, day, block, salt])
	return float(h & 0xFFFFFF) / 16777216.0


static func _base(world_seed: int, day: int, block: int, season: int) -> int:
	var r: float = _rand01(world_seed, day, block, 1)
	var w: Array = WEIGHTS[season]
	var acc: float = 0.0
	for i in w.size():
		acc += float(w[i])
		if r < acc:
			return i
	return Type.CLEAR


## Погода на 3-часовой блок суток.
static func type_at(world_seed: int, day: int, hour: int, season: int) -> int:
	var block: int = hour / 3
	var t: int = _base(world_seed, day, block, season)
	if _rand01(world_seed, day, block, 2) < 0.45:
		var pd: int = day
		var pb: int = block - 1
		if pb < 0:
			pb = 7
			pd -= 1
		t = _base(world_seed, pd, pb, season)
	return t


static func name_of(t: int) -> String:
	return NAMES[t]
