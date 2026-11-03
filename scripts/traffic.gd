class_name Traffic
extends Node
## Движение машин по полосам (зоны LANE_EAST / LANE_WEST). Машины не проезжают друг сквозь друга:
## каждая держит дистанцию до идущей впереди и тормозит так, чтобы успеть остановиться в зазоре.
## Спавн — за краем полосы, и только если там свободно.

signal car_spawned(car: Car)
signal car_removed(car: Car)

const MIN_GAP := 24.0         # зазор, на котором машина стоит за впереди идущей
const SPAWN_GAP := 70.0       # свободное место у края, нужное для нового авто
const MARGIN := 40.0          # насколько за край полосы машина уезжает до удаления

var _parent: Node2D
var _vehicles: Array = []
var _lanes: Array[Dictionary] = []   # {"rect": Rect2, "dir": int, "cars": Array[Car], "timer": float}


## lanes: [{"rect": Rect2, "dir": 1|-1}]. Колёса едут по нижнему краю рамки.
func setup(parent: Node2D, vehicles: Array, lanes: Array) -> void:
	_parent = parent
	_vehicles = vehicles
	for l in lanes:
		_lanes.append({"rect": l["rect"], "dir": int(l["dir"]), "cars": [] as Array[Car], "timer": randf_range(1.0, 4.0)})


## Расставляет машины по полосам при старте (с соблюдением дистанции).
func seed_cars(per_lane: int) -> void:
	for lane in _lanes:
		var rect: Rect2 = lane["rect"]
		var x := rect.position.x + randf_range(80.0, 240.0)
		for _i in per_lane:
			var car := _make_car(lane)
			car.position.x = x
			x += car.width() + randf_range(160.0, 360.0)
			if x > rect.end.x:
				car.queue_free()
				break
			_add(lane, car)


func cars() -> Array[Car]:
	var out: Array[Car] = []
	for lane in _lanes:
		out.append_array(lane["cars"])
	return out


func update(delta: float) -> void:
	for lane in _lanes:
		_update_lane(lane, delta)


func _update_lane(lane: Dictionary, delta: float) -> void:
	var rect: Rect2 = lane["rect"]
	var dir: int = lane["dir"]
	var cars: Array = lane["cars"]
	lane["timer"] = float(lane["timer"]) - delta
	if float(lane["timer"]) <= 0.0:
		lane["timer"] = randf_range(2.5, 6.0)
		_try_spawn(lane)
	cars.sort_custom(func(a: Car, b: Car) -> bool: return a.position.x * dir > b.position.x * dir)   # первым — ведущий
	for i in cars.size():
		var car: Car = cars[i]
		var gap := INF
		var lead_speed := INF
		if i > 0:
			var lead: Car = cars[i - 1]
			gap = (lead.position.x - car.position.x) * dir - (lead.width() + car.width()) / 2.0
			lead_speed = lead.speed
		car.drive(delta, gap, lead_speed, MIN_GAP)
		if gap < INF:   # страховка: не наезжать, даже если ведущий резко встал
			var lead2: Car = cars[i - 1]
			var overlap := (lead2.width() + car.width()) / 2.0 - (lead2.position.x - car.position.x) * dir
			if overlap > -MIN_GAP * 0.25:
				car.position.x -= dir * (overlap + MIN_GAP * 0.25)
				car.speed = minf(car.speed, lead2.speed)
	for car: Car in cars.duplicate():
		var gone: bool = car.position.x > rect.end.x + car.width() + MARGIN if dir > 0 else car.position.x < rect.position.x - car.width() - MARGIN
		if gone:
			cars.erase(car)
			car_removed.emit(car)
			car.queue_free()


func _try_spawn(lane: Dictionary) -> void:
	var rect: Rect2 = lane["rect"]
	var dir: int = lane["dir"]
	var cars: Array = lane["cars"]
	var car := _make_car(lane)
	var start_x := rect.position.x - car.width() / 2.0 if dir > 0 else rect.end.x + car.width() / 2.0
	car.position.x = start_x
	for other in cars:   # на въезде занято — ждём
		if absf(other.position.x - start_x) < (other.width() + car.width()) / 2.0 + SPAWN_GAP:
			car.queue_free()
			lane["timer"] = 0.6
			return
	_add(lane, car)


func _make_car(lane: Dictionary) -> Car:
	var def: Dictionary = _vehicles.pick_random()
	var car := Car.new()
	car.setup(def, int(lane["dir"]))
	car.position.y = (lane["rect"] as Rect2).end.y
	car.desired = 55.0 if String(def["id"]).begins_with("bus") else randf_range(80.0, 120.0)
	car.speed = car.desired
	_parent.add_child(car)
	return car


func _add(lane: Dictionary, car: Car) -> void:
	(lane["cars"] as Array).append(car)
	car_spawned.emit(car)
