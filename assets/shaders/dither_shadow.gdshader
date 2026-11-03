// Косая тень от здания на тротуаре: длина и наклон зависят от высоты солнца; край — дизеринг по сетке пикселей арта.
shader_type canvas_item;

uniform vec2 size = vec2(400.0, 80.0);     // размер прямоугольника с тенью, px
uniform float span = 340.0;                // ширина здания (тень падает от него)
uniform float margin = 40.0;               // запас слева для наклона
uniform float shadow_length = 40.0;        // длина тени вниз
uniform float lean = 0.0;                  // наклон: на сколько px вправо уезжает тень на каждый px вниз
uniform float strength = 0.4;
uniform float art_px = 2.0;

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
	float d = local.y;
	float x = local.x - margin - d * lean;
	float inside = step(0.0, x) * step(x, span);
	float fade = clamp(1.0 - d / max(shadow_length, 1.0), 0.0, 1.0);
	float lvl = floor(fade * 4.0 + bayer4(cell)) / 4.0;
	COLOR = vec4(0.04, 0.03, 0.10, lvl * strength * inside);
}
