// Рентген фасада: пиксельный круг вырезает дыру в здании, через которую виден интерьер.
// Круг считается по сетке пикселей арта (2 px мира), поэтому край ступенчатый. Вокруг дыры — кольцо.
// Работает только внутри region (интерьер кафе): внешние стены здания остаются.
shader_type canvas_item;
#include "res://assets/shaders/weather_surface.gdshaderinc"
#include "res://assets/shaders/glass.gdshaderinc"

uniform vec2 center = vec2(0.0);        // центр круга в мире (лапки кота)
uniform float radius = 0.0;             // радиус в мире; 0 — фасад целый
uniform vec4 region = vec4(0.0);        // x, y, ширина, высота области, где можно вырезать
uniform float ring = 6.0;               // толщина кольца
uniform vec4 ring_color : source_color = vec4(0.10, 0.08, 0.16, 1.0);
uniform float art_pixel = 2.0;
uniform vec4 glass0 = vec4(0.0);    // стёкла витрины (мир): тёмные пиксели прозрачны
uniform vec4 glass1 = vec4(0.0);
uniform vec4 door = vec4(0.0);      // проём двери: фасад вырезан целиком, створки рисуются отдельно (auto_door.gd)
uniform float roof_frac = 0.42;     // доля высоты фасада, занятая крышей (для снега)

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = (floor(world / art_pixel) + 0.5) * art_pixel;
	vec2 c = (floor(center / art_pixel) + 0.5) * art_pixel;
	if (in_rect(p, door)) {
		discard;
	}
	if (in_rect(p, glass0) || in_rect(p, glass1)) {
		float ga = glass_alpha(texture(TEXTURE, UV).rgb);
		if (ga == 0.0) {
			discard;
		} else if (ga > 0.0) {
			COLOR.a *= ga;
		}
	}
	bool inside = p.x >= region.x && p.x < region.x + region.z && p.y >= region.y && p.y < region.y + region.w;
	if (inside && radius > 0.0) {
		float d = distance(p, c);
		if (d < radius - ring) {
			discard;
		} else if (d < radius) {
			COLOR.rgb = ring_color.rgb;
		}
	}
	// погода: снег на крыше и верхнем крае, мокрый фасад
	bool exposed = false;
	int depth = 1 + int(weather_snow * 5.0);
	for (int i = 1; i <= 6; i++) {
		if (i > depth) {
			break;
		}
		float y = UV.y - float(i) * TEXTURE_PIXEL_SIZE.y;
		if (y < 0.0 || texture(TEXTURE, vec2(UV.x, y)).a < 0.5) {
			exposed = true;
			break;
		}
	}
	bool below_open = texture(TEXTURE, vec2(UV.x, UV.y + TEXTURE_PIXEL_SIZE.y)).a < 0.5;
	COLOR = weather_prop(COLOR, floor(world / 2.0), UV.y, exposed, below_open, 1, roof_frac);
}
