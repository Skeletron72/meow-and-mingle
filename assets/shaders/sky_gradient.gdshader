// Небо: вертикальный градиент ступенями (bands) с дизерингом между ступенями — пиксельный закат без плавных переходов.
shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.38, 0.65, 0.95, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.70, 0.86, 0.98, 1.0);
uniform float bands = 14.0;
uniform float art_px = 2.0;
uniform vec2 size = vec2(360.0, 640.0);

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = y * 4 + x;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	vec2 local = UV * size;
	vec2 cell = floor(local / art_px);
	float t = clamp(UV.y, 0.0, 1.0) * bands;
	float q = floor(t + bayer4(cell)) / bands;
	COLOR = mix(top_color, bottom_color, clamp(q, 0.0, 1.0));
}
