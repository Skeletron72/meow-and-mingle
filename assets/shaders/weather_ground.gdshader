// Земля улицы (TileMapLayer): снег ложится пятнами с дизерингом на траву, тротуар и дорогу; в дождь земля темнеет, появляются лужи.
shader_type canvas_item;
#include "res://assets/shaders/weather_surface.gdshaderinc"

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 cell = floor(world / 2.0);
	COLOR = weather_ground(COLOR, cell, TIME);
}
