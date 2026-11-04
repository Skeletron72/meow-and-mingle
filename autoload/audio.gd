extends Node
## Autoload "Audio": звуки и музыка. Две шины — Music и SFX; громкость берётся из настроек (GameState.settings["music"/"sfx"]).
## Звуки: `Audio.sfx("coin")` (небольшой разброс высоты, чтобы повторы не «жужжали»). Музыка: `Audio.music("city")` / `Audio.music("shift")`
## плавно переходит из одной петли в другую. Файлы — assets/audio/*.ogg, их делает tools/generators/make_audio.py.
## При выключенном звуке (громкость 0) и в безголовом режиме файлы не воспроизводятся.

const SFX := ["click", "back", "coin", "pour", "success", "fail", "angry", "bell", "shutter", "box", "tap", "star", "pop", "whoosh", "meow1", "meow2"]
const MUSIC := {"city": "music_city", "shift": "music_shift"}
const POOL := 8
const MIN_GAP_MSEC := 40   # один и тот же звук чаще раза в 40 мс не играем

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []   # два плеера для перекрёстного затухания
var _music_name := ""
var _last_play := {}
var muted_in_background := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		add_child(m)
		_music.append(m)
	GameState.setting_changed.connect(_on_setting_changed)
	apply_volumes()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func apply_volumes() -> void:
	_set_bus("Music", float(GameState.get_setting("music")))
	_set_bus("SFX", float(GameState.get_setting("sfx")))


func _set_bus(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))


func _on_setting_changed(key: String) -> void:
	if key == "music" or key == "sfx":
		apply_volumes()


func _load(file: String) -> AudioStream:
	if not _streams.has(file):
		var path := "res://assets/audio/%s.ogg" % file
		_streams[file] = load(path) if ResourceLoader.exists(path) else null
	return _streams[file]


func _active() -> bool:
	return DisplayServer.get_name() != "headless"


## Короткий звук. pitch — разброс высоты (0.06 = ±6%), vol_db — тише/громче.
func sfx(sound: String, pitch := 0.05, vol_db := 0.0) -> void:
	if not _active() or AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(sound, -10000)) < MIN_GAP_MSEC:
		return
	_last_play[sound] = now
	var stream := _load(sound)
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = 1.0 + randf_range(-pitch, pitch)
			p.volume_db = vol_db
			p.play()
			return


## Музыкальная петля по имени ("city", "shift", "" — тишина). Та же — ничего не делает.
func music(track: String) -> void:
	if track == _music_name:
		return
	_music_name = track
	if not _active():
		return
	var old := _music[0]
	var new := _music[1]
	_music.reverse()   # [новый, старый]
	var tw := create_tween().set_parallel(true)
	if old.playing:
		tw.tween_property(old, "volume_db", -40.0, 1.0)
		tw.chain().tween_callback(old.stop)
	if track == "" or not MUSIC.has(track):
		return
	var stream := _load(String(MUSIC[track]))
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	tw.tween_property(new, "volume_db", -6.0, 1.2)


func current_music() -> String:
	return _music_name


## Приложение в фоне — музыка на паузе (требование площадок); вернулись — продолжаем.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			for m in _music:
				m.stream_paused = true
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			for m in _music:
				m.stream_paused = false
