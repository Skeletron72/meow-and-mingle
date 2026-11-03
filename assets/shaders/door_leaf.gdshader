// Створка двери: кусок текстуры фасада, который уезжает в стену. Обрезается проёмом (clip), стекло прозрачно (сквозь дверь виден зал),
// и режется тем же пиксельным кругом рентгена, что и фасад.
shader_type canvas_item;
#include "res://assets/shaders/glass.gdshaderinc"

uniform vec4 clip = vec4(0.0);
uniform vec2 center = vec2(0.0);
uniform float radius = 0.0;
uniform vec4 region = vec4(0.0);
uniform float ring = 6.0;
uniform vec4 ring_color : source_color = vec4(0.10, 0.08, 0.16, 1.0);
uniform float art_pixel = 2.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = (floor(world / art_pixel) + 0.5) * art_pixel;
	if (!in_rect(p, clip)) {
		discard;
	}
	float ga = glass_alpha(texture(TEXTURE, UV).rgb);
	if (ga == 0.0) {
		discard;
	} else if (ga > 0.0) {
		COLOR.a *= ga;
	}
	vec2 c = (floor(center / art_pixel) + 0.5) * art_pixel;
	if (in_rect(p, region) && radius > 0.0) {
		float d = distance(p, c);
		if (d < radius - ring) {
			discard;
		} else if (d < radius) {
			COLOR.rgb = ring_color.rgb;
		}
	}
}
