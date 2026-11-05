extends Node
## Autoload "Platform": единая точка входа во всё, что зависит от площадки. Выбирает бэкенд (PlatformBackend) и добавляет к
## событиям общие поля. Остальной код про магазины ничего не знает: `Platform.track("level_end", {...})`,
## `Platform.show_rewarded("double_coins", cb)`, `Platform.purchase("no_ads", cb)`.

signal purchase_done(sku: String)

var backend: PlatformBackend = DummyBackend.new()
var session_id := 0
var session_started_msec := 0
var analytics_enabled := true
var _last_interstitial_msec := -1000000


func _ready() -> void:
	# Каналы: сюда подключаются RuStoreBackend / YandexBackend (см. docs/release/04-technical-export.md); пока везде заглушка.
	if OS.has_feature("web"):
		backend = DummyBackend.new()
	session_id = randi()
	session_started_msec = Time.get_ticks_msec()
	track("session_start", {"channel": backend.id(), "lang": TranslationServer.get_locale()})


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		track("session_pause", {"len": session_seconds()})
		if GameState != null and is_instance_valid(GameState):
			GameState.save_game()
			Daily.plan_notifications()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		Daily.on_resume()


## Тестовая сборка (пресеты «… (TEST)» ставят признак `playtest`): панель FPS, лог событий на устройстве, страница «Для тестов» в настройках.
func is_playtest() -> bool:
	return OS.has_feature("playtest") or OS.get_environment("WARMPAW_PLAYTEST") == "1"   # переменная — для проверки на ПК без экспорта


func session_seconds() -> int:
	return int((Time.get_ticks_msec() - session_started_msec) / 1000)


## Событие аналитики. Пока игрок не согласился (или выключил аналитику) — события не уходят.
func track(event: String, params := {}) -> void:
	if not analytics_enabled:
		return
	var p: Dictionary = params.duplicate()
	p["s"] = session_id
	backend.track(event, p)


func ads_ready(placement: String) -> bool:
	return backend.ads_ready(placement)


## Реклама за награду; cb(rewarded: bool). Событие просмотра пишется сразу.
func show_rewarded(placement: String, cb: Callable) -> void:
	track("ad_request", {"placement": placement})
	backend.show_rewarded(placement, func(ok: bool) -> void:
		track("ad_reward" if ok else "ad_fail", {"placement": placement})
		cb.call(ok))


## Межстраничная реклама не чаще, чем раз в 4 минуты; иначе сразу вызывает cb.
func show_interstitial(placement: String, cb: Callable) -> void:
	if Shop.ads_removed() or Time.get_ticks_msec() - _last_interstitial_msec < 240000:
		cb.call()
		return
	_last_interstitial_msec = Time.get_ticks_msec()
	track("ad_show", {"placement": placement, "kind": "interstitial"})
	backend.show_interstitial(placement, cb)


func products() -> Array[Dictionary]:
	return backend.products()


func purchase(sku: String, cb: Callable) -> void:
	track("iap_start", {"sku": sku})
	backend.purchase(sku, func(ok: bool, bought: String) -> void:
		track("iap_ok" if ok else "iap_fail", {"sku": bought})
		if ok:
			purchase_done.emit(bought)
		cb.call(ok, bought))


func restore_purchases(cb: Callable) -> void:
	backend.restore_purchases(cb)


func request_review() -> void:
	backend.request_review()


func request_notification_permission(cb: Callable) -> void:
	backend.request_notification_permission(cb)


func schedule_notification(nid: String, seconds: float, title: String, body: String) -> void:
	backend.schedule_notification(nid, seconds, title, body)


func cancel_notification(nid: String) -> void:
	backend.cancel_notification(nid)


func safe_insets() -> Rect2:
	return backend.safe_insets()
