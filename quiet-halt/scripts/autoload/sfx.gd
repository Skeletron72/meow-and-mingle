extends Node
## Процедурный звук: все эффекты и «музыкальная шкатулка» синтезируются в коде.

const RATE: int = 22050

var _sounds: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _music_timer: float = 3.0
var _music_player: Array[AudioStreamPlayer] = []
var _rain_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _rain_level: float = 0.0
var _wind_level: float = 0.0
var music_on: bool = false
var _rng := RandomNumberGenerator.new()

const PENTA_DAY: Array[int] = [0, 2, 4, 7, 9, 12, 14, 16]
const PENTA_NIGHT: Array[int] = [-3, 0, 2, 4, 7, 9, 12]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_build_sounds()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 3:
		var m := AudioStreamPlayer.new()
		add_child(m)
		_music_player.append(m)
	_rain_player = AudioStreamPlayer.new()
	_rain_player.stream = _sounds["rain_loop"]
	_rain_player.volume_db = -80.0
	add_child(_rain_player)
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = _sounds["wind_loop"]
	_wind_player.volume_db = -80.0
	add_child(_wind_player)
	_rain_player.play()
	_wind_player.play()


func play(name: String, pitch: float = 1.0) -> void:
	if not _sounds.has(name):
		return
	var vol: float = float(Game.settings.get("sfx", 0.8))
	if vol <= 0.01:
		return
	for p in _pool:
		if not p.playing:
			p.stream = _sounds[name]
			p.pitch_scale = pitch
			p.volume_db = linear_to_db(vol) - 4.0
			p.play()
			return


## Громкость фоновых звуков (0..1).
func set_ambient(rain: float, wind: float) -> void:
	_rain_level = rain
	_wind_level = wind


func _process(delta: float) -> void:
	var sv: float = float(Game.settings.get("sfx", 0.8))
	var rdb: float = -80.0 if _rain_level < 0.02 else linear_to_db(_rain_level * 0.5 * sv + 0.0001)
	var wdb: float = -80.0 if _wind_level < 0.02 else linear_to_db(_wind_level * 0.25 * sv + 0.0001)
	_rain_player.volume_db = lerpf(_rain_player.volume_db, rdb, minf(delta * 2.0, 1.0))
	_wind_player.volume_db = lerpf(_wind_player.volume_db, wdb, minf(delta * 2.0, 1.0))
	if music_on:
		_music_timer -= delta
		if _music_timer <= 0.0:
			_music_step()


func _music_step() -> void:
	var vol: float = float(Game.settings.get("music", 0.6))
	var night: bool = Clock.is_night()
	var scale: Array[int] = PENTA_NIGHT if night else PENTA_DAY
	_music_timer = _rng.randf_range(0.9, 2.4) * (1.5 if night else 1.0)
	if vol <= 0.01:
		return
	var count: int = 1 if _rng.randf() < 0.55 else _rng.randi_range(2, 4)
	var base: int = scale[_rng.randi() % scale.size()]
	for i in count:
		var semis: int = base
		if i > 0:
			var step: int = scale[_rng.randi() % scale.size()]
			semis = step
		_play_note(semis, vol, float(i) * 0.22)


func _play_note(semitones: int, vol: float, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	for p in _music_player:
		if not p.playing:
			p.stream = _sounds["bell"]
			p.pitch_scale = pow(2.0, float(semitones) / 12.0)
			p.volume_db = linear_to_db(vol) - 13.0
			p.play()
			return


# ---------- синтез ----------

func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _tone(freq: float, dur: float, decay: float = 6.0, wave: int = 0, vib: float = 0.0) -> PackedFloat32Array:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var f: float = freq * (1.0 + vib * sin(t * 30.0))
		var ph: float = TAU * f * t
		var s: float = sin(ph)
		if wave == 1:
			s = signf(sin(ph)) * 0.4 + sin(ph) * 0.3
		elif wave == 2:
			s = asin(sin(ph)) * 0.64
		var env: float = exp(-t * decay) * minf(t * 400.0, 1.0)
		out[i] = s * env * 0.5
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset: int = 0) -> PackedFloat32Array:
	var n: int = maxi(a.size(), b.size() + offset)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in a.size():
		out[i] += a[i]
	for i in b.size():
		out[i + offset] += b[i]
	return out


func _noise(dur: float, decay: float, lp: float, sweep: float = 0.0) -> PackedFloat32Array:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev: float = 0.0
	var r := RandomNumberGenerator.new()
	r.seed = 12345
	for i in n:
		var t: float = float(i) / RATE
		var a: float = clampf(lp + sweep * t, 0.02, 0.95)
		prev = prev + (r.randf_range(-1.0, 1.0) - prev) * a
		out[i] = prev * exp(-t * decay) * minf(t * 200.0, 1.0)
	return out


func _build_sounds() -> void:
	_sounds["blip"] = _wav(_tone(540.0, 0.05, 40.0, 2))
	_sounds["click"] = _wav(_tone(760.0, 0.05, 50.0, 2))
	_sounds["pickup"] = _wav(_mix(_tone(660.0, 0.12, 14.0, 2), _tone(990.0, 0.18, 10.0, 2), int(RATE * 0.07)))
	var coin: PackedFloat32Array = _mix(_tone(1318.0, 0.1, 18.0, 2), _tone(1760.0, 0.3, 8.0, 0), int(RATE * 0.06))
	_sounds["coin"] = _wav(coin)
	_sounds["bite"] = _wav(_mix(_tone(150.0, 0.2, 14.0, 0), _tone(300.0, 0.12, 20.0, 1), 0))
	_sounds["splash"] = _wav(_noise(0.4, 7.0, 0.35, -0.4))
	_sounds["cast"] = _wav(_noise(0.25, 9.0, 0.1, 1.5))
	_sounds["dig"] = _wav(_mix(_noise(0.18, 18.0, 0.12), _tone(90.0, 0.15, 20.0, 0)))
	_sounds["shake"] = _wav(_noise(0.5, 4.0, 0.5))
	_sounds["swing"] = _wav(_noise(0.18, 12.0, 0.3, 2.0))
	_sounds["nope"] = _wav(_tone(190.0, 0.14, 12.0, 1))
	var bell: PackedFloat32Array = _tone(523.25, 2.0, 2.4, 0)
	var b2: PackedFloat32Array = _tone(523.25 * 2.76, 1.2, 5.0, 0)
	var b3: PackedFloat32Array = _tone(523.25 * 4.1, 0.6, 9.0, 0)
	for i in b2.size():
		bell[i] += b2[i] * 0.35
	for i in b3.size():
		bell[i] += b3[i] * 0.2
	_sounds["bell"] = _wav(bell)
	var chime: PackedFloat32Array = _mix(_tone(659.0, 0.5, 4.0, 0), _tone(988.0, 0.8, 3.5, 0), int(RATE * 0.12))
	chime = _mix(chime, _tone(1318.0, 1.0, 3.0, 0), int(RATE * 0.26))
	_sounds["chime"] = _wav(chime)
	var fan: PackedFloat32Array = _tone(523.0, 0.2, 8.0, 2)
	fan = _mix(fan, _tone(659.0, 0.2, 8.0, 2), int(RATE * 0.12))
	fan = _mix(fan, _tone(784.0, 0.2, 8.0, 2), int(RATE * 0.24))
	fan = _mix(fan, _tone(1046.0, 0.6, 5.0, 2), int(RATE * 0.36))
	_sounds["fanfare"] = _wav(fan)
	_sounds["horn"] = _wav(_mix(_tone(220.0, 1.2, 1.6, 1), _tone(277.0, 1.2, 1.6, 1)))
	var rain: PackedFloat32Array = _noise(2.0, 0.0, 0.5)
	_sounds["rain_loop"] = _wav(_loopify(rain), true)
	var wind: PackedFloat32Array = _noise(3.0, 0.0, 0.06)
	for i in wind.size():
		wind[i] *= 3.0 * (0.6 + 0.4 * sin(float(i) / RATE * 1.3))
	_sounds["wind_loop"] = _wav(_loopify(wind), true)


func _loopify(a: PackedFloat32Array) -> PackedFloat32Array:
	var fade: int = int(RATE * 0.1)
	for i in fade:
		var k: float = float(i) / float(fade)
		a[i] = a[i] * k + a[a.size() - fade + i] * (1.0 - k)
	return a.slice(0, a.size() - fade)
