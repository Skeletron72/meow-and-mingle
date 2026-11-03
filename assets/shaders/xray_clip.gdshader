// Всё, что стоит внутри здания (мебель, гости), видно только внутри того же пиксельного круга, что вырезает фасад.
shader_type canvas_item;

uniform vec2 center = vec2(0.0);
uniform float radius = 0.0;
uniform vec4 region = vec4(0.0);        // x, y, ширина, высота: внутри неё действует обрезка
uniform float art_pixel = 2.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = (floor(world / art_pixel) + 0.5) * art_pixel;
	vec2 c = (floor(center / art_pixel) + 0.5) * art_pixel;
	bool inside = p.x >= region.x && p.x < region.x + region.z && p.y >= region.y && p.y < region.y + region.w;
	if (inside && distance(p, c) >= radius) {
		discard;
	}
}
