class_name DummyBackend
extends PlatformBackend
## Заглушка для разработки: события пишутся в user://analytics.log (и в память — для тестов), реклама «смотрится» сразу,
## покупки проходят только в отладочной сборке (в релизной сборке без настоящего магазина денег не берём).

const LOG_PATH := "user://analytics.log"
const LOG_LIMIT := 256 * 1024   # больше — файл начинаем заново

var events: Array[Dictionary] = []
var scheduled: Dictionary = {}   # id -> {"seconds", "title", "body"}
var reviews_requested := 0
var cloud_text := ""
var simulate_ads := true
var simulate_purchases := OS.is_debug_build()


func id() -> String:
	return "dummy"


func store_name() -> String:
	return "dev"


func track(event: String, params: Dictionary) -> void:
	var row := {"t": Time.get_unix_time_from_system(), "e": event, "p": params}
	events.append(row)
	if events.size() > 500:
		events.pop_front()
	if OS.is_debug_build():
		var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
		if f != null:
			if f.get_length() > LOG_LIMIT:
				f.resize(0)
			f.seek_end()
			f.store_line(JSON.stringify(row))


func ads_ready(_placement: String) -> bool:
	return simulate_ads


func show_rewarded(_placement: String, cb: Callable) -> void:
	cb.call(simulate_ads)


func show_interstitial(_placement: String, cb: Callable) -> void:
	cb.call()


func products() -> Array[Dictionary]:
	return [
		{"sku": "no_ads", "price": "199 ₽"},
		{"sku": "starter_pack", "price": "149 ₽"},
	] as Array[Dictionary]


func purchase(sku: String, cb: Callable) -> void:
	cb.call(simulate_purchases, sku)


func cloud_save(text: String) -> void:
	cloud_text = text


func cloud_load() -> String:
	return cloud_text


func request_review() -> void:
	reviews_requested += 1


func schedule_notification(nid: String, seconds: float, title: String, body: String) -> void:
	scheduled[nid] = {"seconds": seconds, "title": title, "body": body}


func cancel_notification(nid: String) -> void:
	scheduled.erase(nid)
