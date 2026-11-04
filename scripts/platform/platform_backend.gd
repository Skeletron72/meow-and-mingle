class_name PlatformBackend
extends RefCounted
## Интерфейс платформы: всё, что зависит от магазина или площадки (аналитика, реклама, покупки, облачный сейв, отзывы, push).
## Игра обращается только к автозагрузке `Platform`, а та — к подклассу этого класса. Базовые методы безопасны: ничего не делают
## или честно сообщают «недоступно», поэтому игра без SDK (ПК, редактор) не ломается.
## Подклассы по каналам: DummyBackend (разработка), позже RuStoreBackend (Android-плагин), YandexBackend (веб, JavaScriptBridge).

func id() -> String:
	return "base"


func store_name() -> String:
	return ""


# ---------------------------------------------------------------- аналитика

func track(_event: String, _params: Dictionary) -> void:
	pass


# ---------------------------------------------------------------- реклама

func ads_ready(_placement: String) -> bool:
	return false


## Реклама за награду. cb(rewarded: bool): true — просмотрена до конца, false — закрыта/нет рекламы.
func show_rewarded(_placement: String, cb: Callable) -> void:
	cb.call(false)


## Межстраничная реклама (редко, только между сменами). cb() вызывается после закрытия или сразу, если показать нечего.
func show_interstitial(_placement: String, cb: Callable) -> void:
	cb.call()


# ---------------------------------------------------------------- покупки

## [{"sku": String, "price": String}] — цены в валюте магазина; пусто, если покупок нет.
func products() -> Array[Dictionary]:
	return []


## cb(ok: bool, sku: String). Выдать награду игра обязана только при ok == true.
func purchase(sku: String, cb: Callable) -> void:
	cb.call(false, sku)


## Восстановить купленное (разовые покупки). cb(skus: Array[String]).
func restore_purchases(cb: Callable) -> void:
	cb.call([] as Array[String])


# ---------------------------------------------------------------- облако, отзывы, уведомления

func cloud_save(_text: String) -> void:
	pass


## Сохранение из облака или "" (нет/недоступно).
func cloud_load() -> String:
	return ""


func request_review() -> void:
	pass


func schedule_notification(_id: String, _seconds: float, _title: String, _body: String) -> void:
	pass


func cancel_notification(_id: String) -> void:
	pass


## Безопасная зона экрана (вырез камеры, жестовая панель): отступы в пикселях окна слева/сверху/справа/снизу.
func safe_insets() -> Rect2:
	return Rect2()
