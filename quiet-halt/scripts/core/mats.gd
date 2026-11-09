class_name Mats
extends RefCounted
## Фабрика материалов (общие экземпляры — меньше draw-call'ов).

static var _main: ShaderMaterial
static var _glow: ShaderMaterial
static var _fuzzy: ShaderMaterial
static var _water: ShaderMaterial
static var _toon: Shader
static var _unlit: Dictionary = {}


static func _shader() -> Shader:
	if _toon == null:
		_toon = load("res://shaders/toon.gdshader") as Shader
	return _toon


static func main() -> ShaderMaterial:
	if _main == null:
		_main = ShaderMaterial.new()
		_main.shader = _shader()
	return _main


static func glow() -> ShaderMaterial:
	if _glow == null:
		_glow = ShaderMaterial.new()
		_glow.shader = _shader()
		_glow.set_shader_parameter("emission_energy", 1.6)
		_glow.set_shader_parameter("night_only", 1.0)
		_glow.set_shader_parameter("snow_catch", 0.0)
	return _glow


## Всегда светящийся (фонарики, светлячки).
static func always_glow() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader()
	m.set_shader_parameter("emission_energy", 2.2)
	m.set_shader_parameter("night_only", 0.0)
	m.set_shader_parameter("snow_catch", 0.0)
	return m


## Пушистый материал жителей (мягкий контур света).
static func fuzzy() -> ShaderMaterial:
	if _fuzzy == null:
		_fuzzy = ShaderMaterial.new()
		_fuzzy.shader = _shader()
		_fuzzy.set_shader_parameter("rim", 0.35)
		_fuzzy.set_shader_parameter("snow_catch", 0.4)
	return _fuzzy


static func water() -> ShaderMaterial:
	if _water == null:
		_water = ShaderMaterial.new()
		_water.shader = load("res://shaders/water.gdshader") as Shader
	return _water


static func unlit(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if _unlit.has(key):
		return _unlit[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_unlit[key] = m
	return m


static func mesh_instance(mesh: Mesh, fuzzy: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if fuzzy:
		mi.material_override = Mats.fuzzy()
	return mi
