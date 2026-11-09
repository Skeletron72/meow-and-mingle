class_name EnvCtl
extends Node3D
## Небо, свет, сезонные цвета, погода. Всё считается из Clock и Weather.

const KEYS: Array = [
	# hour, sky_top, sky_horizon, sun_color, sun_energy, ambient_color, ambient_energy, night
	[0.0,  Color(0.04, 0.06, 0.17), Color(0.10, 0.13, 0.28), Color(0.60, 0.70, 1.0), 0.8, Color(0.42, 0.48, 0.78), 1.35, 1.0],
	[5.0,  Color(0.05, 0.07, 0.19), Color(0.12, 0.15, 0.30), Color(0.60, 0.70, 1.0), 0.8, Color(0.42, 0.48, 0.78), 1.35, 1.0],
	[6.4,  Color(0.40, 0.48, 0.80), Color(1.00, 0.70, 0.52), Color(1.0, 0.76, 0.52), 0.85, Color(0.78, 0.68, 0.74), 0.9, 0.25],
	[8.0,  Color(0.40, 0.68, 0.95), Color(0.86, 0.91, 0.96), Color(1.0, 0.95, 0.84), 1.05, Color(0.82, 0.86, 0.95), 0.95, 0.0],
	[12.0, Color(0.30, 0.62, 0.95), Color(0.80, 0.90, 0.97), Color(1.0, 0.97, 0.90), 1.15, Color(0.86, 0.91, 1.00), 1.0, 0.0],
	[16.5, Color(0.38, 0.64, 0.92), Color(0.94, 0.90, 0.80), Color(1.0, 0.90, 0.72), 1.05, Color(0.88, 0.86, 0.95), 0.95, 0.0],
	[18.0, Color(0.36, 0.36, 0.68), Color(1.00, 0.56, 0.40), Color(1.0, 0.66, 0.42), 0.8, Color(0.80, 0.66, 0.78), 0.85, 0.2],
	[19.2, Color(0.20, 0.20, 0.46), Color(0.82, 0.44, 0.50), Color(0.8, 0.5, 0.6), 0.5, Color(0.55, 0.50, 0.75), 0.85, 0.6],
	[20.6, Color(0.07, 0.09, 0.25), Color(0.20, 0.20, 0.40), Color(0.60, 0.70, 1.0), 0.8, Color(0.42, 0.48, 0.78), 1.35, 0.97],
	[24.0, Color(0.04, 0.06, 0.17), Color(0.10, 0.13, 0.28), Color(0.60, 0.70, 1.0), 0.8, Color(0.42, 0.48, 0.78), 1.35, 1.0],
]

# фаза года (месяцы), листва, цветение, трава, снег
const SEASON_KEYS: Array = [
	[0.5,  Vector3(0.80, 0.86, 0.84), Vector3(0.86, 0.89, 0.92), Vector3(0.80, 0.87, 0.84), 0.95],
	[3.8,  Vector3(0.52, 0.82, 0.38), Vector3(1.00, 0.74, 0.82), Vector3(0.48, 0.80, 0.34), 0.0],
	[6.8,  Vector3(0.34, 0.70, 0.27), Vector3(0.44, 0.76, 0.33), Vector3(0.40, 0.74, 0.29), 0.0],
	[9.8,  Vector3(0.96, 0.60, 0.20), Vector3(0.92, 0.38, 0.22), Vector3(0.74, 0.66, 0.30), 0.0],
	[12.5, Vector3(0.80, 0.86, 0.84), Vector3(0.86, 0.89, 0.92), Vector3(0.80, 0.87, 0.84), 0.95],
]

static var night_value: float = 0.0

var world_env: WorldEnvironment
var sun: DirectionalLight3D
var env: Environment
var focus: Vector3 = Vector3.ZERO
var weather: int = Weather.Type.CLEAR
var force_hour: float = -1.0 ## для тестов/кат-сцен
var force_weather: int = -1

var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _clouds: Array = []
var _cloud_root: Node3D
var _rain_i: float = 0.0
var _snow_i: float = 0.0
var _fog_i: float = 0.0
var _cloud_i: float = 0.2
var _wet_gloom: float = 0.0
var _last_hour: int = -1
var _sky_mat: ShaderMaterial


func _ready() -> void:
	env = Environment.new()
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/sky.gdshader") as Shader
	sky.sky_material = _sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.03
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.6
	add_child(sun)

	_make_particles()
	_make_clouds()
	update_now(true)


func _make_particles() -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = 900
	_rain.lifetime = 0.8
	_rain.emitting = false
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(18, 0.5, 18)
	_rain.direction = Vector3(0.1, -1, 0.05)
	_rain.spread = 2.0
	_rain.gravity = Vector3(0, -30, 0)
	_rain.initial_velocity_min = 12.0
	_rain.initial_velocity_max = 14.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.55, 0.012)
	bm.material = Mats.unlit(Color(0.78, 0.88, 1.0, 0.55))
	_rain.mesh = bm
	add_child(_rain)

	_snow = CPUParticles3D.new()
	_snow.amount = 700
	_snow.lifetime = 7.0
	_snow.emitting = false
	_snow.local_coords = false
	_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snow.emission_box_extents = Vector3(20, 0.5, 20)
	_snow.direction = Vector3(0.2, -1, 0.1)
	_snow.spread = 25.0
	_snow.gravity = Vector3(0, -1.0, 0)
	_snow.initial_velocity_min = 0.6
	_snow.initial_velocity_max = 1.4
	_snow.scale_amount_min = 0.7
	_snow.scale_amount_max = 1.5
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 4
	sm.rings = 2
	sm.material = Mats.unlit(Color(1, 1, 1, 0.95))
	_snow.mesh = sm
	add_child(_snow)


func _make_clouds() -> void:
	_cloud_root = Node3D.new()
	add_child(_cloud_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var k := MeshKit.new()
		var puffs: int = rng.randi_range(3, 5)
		for p in puffs:
			var r: float = rng.randf_range(3.0, 5.5)
			k.ball(Vector3(float(p) * 4.0 - float(puffs) * 2.0, rng.randf_range(-0.5, 0.8), rng.randf_range(-1.5, 1.5)), Vector3(r, r * 0.5, r * 0.8), Color(0.96, 0.96, 0.98, 1.0), 8, 5)
		var mi := MeshInstance3D.new()
		mi.mesh = k.build()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(rng.randf_range(-90, 90), rng.randf_range(34, 52), rng.randf_range(-90, 90))
		_cloud_root.add_child(mi)
		_clouds.append(mi)


func _process(delta: float) -> void:
	update_now(false, delta)
	# следование за игроком
	RenderingServer.global_shader_parameter_set("world_focus", focus)
	_rain.global_position = focus + Vector3(0, 14, 0)
	_snow.global_position = focus + Vector3(0, 12, 0)
	for c in _clouds:
		var mi: MeshInstance3D = c
		mi.position.x += delta * 0.9
		if mi.position.x - focus.x > 100.0:
			mi.position.x -= 200.0
		if mi.position.z - focus.z > 100.0:
			mi.position.z -= 200.0
		if mi.position.z - focus.z < -100.0:
			mi.position.z += 200.0
		if mi.position.x - focus.x < -100.0:
			mi.position.x += 200.0


func _hour() -> float:
	return force_hour if force_hour >= 0.0 else Clock.hour_float()


func _sample_keys(h: float) -> Array:
	for i in range(KEYS.size() - 1):
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= float(a[0]) and h <= float(b[0]):
			var t: float = (h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			t = smoothstep(0.0, 1.0, t)
			return [
				(a[1] as Color).lerp(b[1], t), (a[2] as Color).lerp(b[2], t), (a[3] as Color).lerp(b[3], t),
				lerpf(float(a[4]), float(b[4]), t), (a[5] as Color).lerp(b[5], t), lerpf(float(a[6]), float(b[6]), t),
				lerpf(float(a[7]), float(b[7]), t),
			]
	return [KEYS[0][1], KEYS[0][2], KEYS[0][3], KEYS[0][4], KEYS[0][5], KEYS[0][6], KEYS[0][7]]


func season_values() -> Dictionary:
	var p: float = Clock.year_phase()
	for i in range(SEASON_KEYS.size() - 1):
		var a: Array = SEASON_KEYS[i]
		var b: Array = SEASON_KEYS[i + 1]
		var pp: float = p
		if p < float(SEASON_KEYS[0][0]):
			pp = p + 12.0
		if pp >= float(a[0]) and pp <= float(b[0]):
			var t: float = smoothstep(0.0, 1.0, (pp - float(a[0])) / (float(b[0]) - float(a[0])))
			return {
				"foliage": (a[1] as Vector3).lerp(b[1], t),
				"blossom": (a[2] as Vector3).lerp(b[2], t),
				"grass": (a[3] as Vector3).lerp(b[3], t),
				"snow": lerpf(float(a[4]), float(b[4]), t),
			}
	return {"foliage": SEASON_KEYS[0][1], "blossom": SEASON_KEYS[0][2], "grass": SEASON_KEYS[0][3], "snow": SEASON_KEYS[0][4]}


func current_weather() -> int:
	if force_weather >= 0:
		return force_weather
	return Weather.type_at(World.state.world_seed, Clock.day_index(), Clock.hour(), Clock.season())


func update_now(instant: bool, delta: float = 0.0) -> void:
	var h: float = _hour()
	# сезонное смещение длины дня
	var phase: float = Clock.year_phase()
	var sf: float = cos((phase - 6.5) / 12.0 * TAU)
	var half: float = 6.0 + 1.6 * sf
	var hw: float = 12.0 + (h - 12.0) * 6.0 / half
	hw = clampf(hw, 0.0, 24.0)
	var s: Array = _sample_keys(hw)
	var top: Color = s[0]
	var hor: Color = s[1]
	var sun_col: Color = s[2]
	var sun_e: float = s[3]
	var amb: Color = s[4]
	var amb_e: float = s[5]
	var night: float = s[6]

	# погода
	weather = current_weather()
	var k: float = 1.0 if instant else minf(delta * 0.6, 1.0)
	_rain_i = lerpf(_rain_i, 1.0 if weather == Weather.Type.RAIN else 0.0, k)
	_snow_i = lerpf(_snow_i, 1.0 if weather == Weather.Type.SNOW else 0.0, k)
	_fog_i = lerpf(_fog_i, 1.0 if weather == Weather.Type.FOG else 0.0, k)
	var cloud_target: float = 0.2
	match weather:
		Weather.Type.CLOUDY: cloud_target = 0.8
		Weather.Type.RAIN: cloud_target = 1.0
		Weather.Type.SNOW: cloud_target = 0.9
		Weather.Type.FOG: cloud_target = 0.6
	_cloud_i = lerpf(_cloud_i, cloud_target, k)
	var gloom: float = clampf(maxf(_cloud_i - 0.2, 0.0) * 0.8 + _rain_i * 0.15 + _fog_i * 0.1, 0.0, 0.85)
	var grey: Color = Color(0.62, 0.65, 0.70)
	top = top.lerp(grey * (1.0 - night * 0.7), gloom * 0.75)
	hor = hor.lerp(Color(0.74, 0.77, 0.80) * (1.0 - night * 0.7), gloom * 0.7 + _fog_i * 0.2)
	sun_e *= (1.0 - gloom * 0.55) * 0.78
	amb_e *= (1.0 + gloom * 0.15) * 0.72

	# положение солнца/луны
	var a: float = (hw - 6.0) / 12.0 * PI
	var elev: float = sin(a)
	var pos: Vector3
	if elev >= -0.02:
		pos = Vector3(cos(a), elev * 0.95 + 0.05, 0.35)
	else:
		pos = Vector3(-cos(a), -elev * 0.9 + 0.05, -0.3)
	pos = pos.normalized()
	sun.global_position = focus + pos * 60.0
	sun.look_at(focus, Vector3.UP)
	sun.light_color = sun_col
	var horizon_fade: float = clampf(pos.y * 4.0, 0.15, 1.0)
	sun.light_energy = sun_e * horizon_fade
	sun.shadow_enabled = pos.y > 0.12 and gloom < 0.7

	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e * (0.9 + 0.2 * night)
	env.fog_light_color = hor
	env.fog_density = 0.0035 + _rain_i * 0.006 + _fog_i * 0.04 + _snow_i * 0.01 + _cloud_i * 0.002

	var sv: Dictionary = season_values()
	RenderingServer.global_shader_parameter_set("foliage_tint", sv.foliage)
	RenderingServer.global_shader_parameter_set("blossom_tint", sv.blossom)
	RenderingServer.global_shader_parameter_set("grass_tint", sv.grass)
	RenderingServer.global_shader_parameter_set("snow_amount", float(sv.snow))
	night_value = night
	RenderingServer.global_shader_parameter_set("night_amount", night)
	RenderingServer.global_shader_parameter_set("sky_top", Vector3(top.r, top.g, top.b))
	RenderingServer.global_shader_parameter_set("sky_horizon", Vector3(hor.r, hor.g, hor.b))
	RenderingServer.global_shader_parameter_set("sun_dir", pos)

	_rain.emitting = _rain_i > 0.3
	_snow.emitting = _snow_i > 0.3
	var shown: int = int(round(_cloud_i * float(_clouds.size())))
	for i in _clouds.size():
		(_clouds[i] as Node3D).visible = i < shown
