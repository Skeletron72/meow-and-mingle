extends OmniLight3D
## Свет фонаря: включается по мере наступления ночи.
func _process(delta: float) -> void:
	light_energy = lerpf(light_energy, EnvCtl.night_value * 1.6, minf(delta * 3.0, 1.0))
	visible = light_energy > 0.02
