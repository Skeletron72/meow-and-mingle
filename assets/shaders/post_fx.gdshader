// Общий пост-эффект в стиле пиксель-арта: блум ярких мест (окна, лампы, солнце) квантованными ступенями с дизерингом
// и пиксельная виньетка. Всё считается по сетке пикселей арта (art_px экранных пикселей), поэтому края ступенчатые.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float art_px = 3.0;        // экранных пикселей в одном пикселе арта
uniform float bloom = 0.45;        // сила блума
uniform float threshold = 0.74;    // с какой яркости начинается свечение
uniform float vignette = 0.5;      // сила виньетки
uniform vec3 grade = vec3(1.0);    // цветокоррекция (множитель)

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = y * 4 + x;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

vec3 excess(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	return max(c - vec3(threshold), vec3(0.0));
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(FRAGCOORD.xy / art_px);
	vec2 uv = (cell + 0.5) * art_px / res;
	vec3 col = texture(screen_tex, uv).rgb;
	float d = bayer4(cell);

	// блум: два кольца по 8 проб с шагом в пикселях арта
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec2 dir = vec2(cos(a), sin(a)) * art_px / res;
		acc += excess(uv + dir * 2.0) + excess(uv + dir * 5.0) * 0.8;
	}
	acc /= 14.0;
	float l = max(max(acc.r, acc.g), acc.b);
	if (l > 0.0) {
		float q = floor(l * bloom * 14.0 + d) / 14.0;   // ступени + дизеринг
		acc *= q / l;
	}
	col += acc;

	// виньетка по краям ступенями
	vec2 p = (uv - 0.5) * 2.0;
	float v = dot(p * vec2(0.9, 0.78), p * vec2(0.9, 0.78));
	float vq = floor(v * vignette * 5.0 + d) / 5.0;
	col *= 1.0 - clamp(vq, 0.0, 1.0) * 0.55;
	col *= grade;
	COLOR = vec4(col, 1.0);
}
