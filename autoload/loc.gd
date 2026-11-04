extends Node
## Autoload "Loc": локализация. Исходные тексты в коде — русские; английский — таблица data/loc/en.json (русская строка → английская).
## Таблица регистрируется как Translation, поэтому работают и `tr("…")`, и автоперевод подписей Control (Label, Button).
## Для строк с форматом переводить нужно шаблон: `tr("Подано: %d") % n`. Из статических классов — `Loc.t("…")`.
## Что ещё не переведено, показывает `python3 tools/loc_check.py`.

signal language_changed(code: String)

const LANGS := ["ru", "en"]
const SOURCE := "res://data/loc/%s.json"

var language := "ru"   # применённый язык
var override := ""     # принудительный язык (тесты и скриншоты); пусто — по настройке и языку системы


func _ready() -> void:
	for code in LANGS:
		if code == "ru":
			continue   # русский — язык исходных строк
		var tr_res := Translation.new()
		tr_res.locale = code
		var table := _read(SOURCE % code)
		for k in table:
			tr_res.add_message(StringName(k), String(table[k]))
		TranslationServer.add_translation(tr_res)
	apply("auto")


## "auto" — по языку системы: русскоязычные страны → ru, остальные → en.
func apply(code: String) -> void:
	var c := override if override != "" else code
	if c == "auto" or c not in LANGS:
		var sys := OS.get_locale_language()
		c = "ru" if sys in ["ru", "uk", "be", "kk", "ky", "uz", "tg", "hy", "az", "ka", "mo"] else "en"
	language = c
	TranslationServer.set_locale(c)
	language_changed.emit(c)


## Склонение по числу: forms — [1 монета, 2 монеты, 5 монет] по-русски. В английском — единственное при n = 1, иначе множественное.
func plural(n: int, forms: Array) -> String:
	if language == "en":
		return t(String(forms[0])) if n == 1 else t(String(forms[2]))
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return String(forms[0])
	if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20):
		return String(forms[1])
	return String(forms[2])


## Перевод строки для кода без доступа к Node.tr() (статические классы).
func t(text: String) -> String:
	return TranslationServer.translate(text)


func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
