// Рентген фасада: пиксельный круг вырезает дыру в здании, через которую виден интерьер.
// Круг считается по сетке пикселей арта (2 px мира), поэтому край ступенчатый. Вокруг дыры — кольцо.
// Работает только внутри region (интерьер кафе): внешние стены здания остаются.
shader_type canvas_item;

uniform vec2 center = vec2(0.0);        // центр круга в мире (лапки кота)
uniform float radius = 0.0;             // радиус в мире; 0 — фасад целый
uniform vec4 region = vec4(0.0);        // x, y, ширина, высота области, где можно вырезать
uniform float ring = 6.0;               // толщина кольца
uniform vec4 ring_color : source_color = vec4(0.10, 0.08, 0.16, 1.0);
uniform float art_pixel = 2.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = (floor(world / art_pixel) + 0.5) * art_pixel;
	vec2 c = (floor(center / art_pixel) + 0.5) * art_pixel;
	bool inside = p.x >= region.x && p.x < region.x + region.z && p.y >= region.y && p.y < region.y + region.w;
	if (inside && radius > 0.0) {
		float d = distance(p, c);
		if (d < radius - ring) {
			discard;
		} else if (d < radius) {
			COLOR.rgb = ring_color.rgb;
		}
	}
}
