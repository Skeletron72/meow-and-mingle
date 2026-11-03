// Экранные погодные эффекты на сетке арта (180×320 клеток по 2 px): косые капли дождя, снежинки двух размеров, туман ступенями с дизерингом,
// знойное марево (сдвиг строк на целую клетку) и блик солнца. Всё считается по клеткам — никаких размытых пикселей.
shader_type canvas_item;
#include "res://assets/shaders/weather_surface.gdshaderinc"

global uniform float weather_snowfall;
global uniform float weather_fog;
global uniform float weather_heat;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 grid = vec2(180.0, 320.0);
uniform vec4 mask = vec4(0.0);       // прямоугольник интерьера в UV экрана (x, y, w, h): внутри погода гаснет
uniform float mask_amount = 0.0;     // 0..1, насколько интерьер раскрыт

vec4 over(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	if (a <= 0.0) {
		return vec4(0.0);
	}
	return vec4((src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / a, a);
}

void fragment() {
	vec2 cell = floor(UV * grid);
	vec4 o = vec4(0.0);

	// туман: три ступени плотности, дизеринг между ними, гуще внизу и в клочьях
	if (weather_fog > 0.01) {
		vec2 fp = cell / vec2(30.0, 20.0) + vec2(TIME * 0.02, 0.0);
		float nn = w_vnoise(fp) * 0.55 + w_vnoise(fp * 2.3 + 7.0) * 0.30 + 0.15;
		float q = clamp((nn + UV.y * 0.30) * weather_fog * 0.95, 0.0, 1.0);
		float level = floor(q * 4.0 + w_bayer(cell)) / 4.0;
		o = over(o, vec4(0.88, 0.91, 0.95, level * 0.62));
	}

	// знойное марево и блик
	if (weather_heat > 0.01) {
		float g = clamp(1.0 - distance(UV * vec2(1.0, 1.7), vec2(0.95, 0.0)) * 0.9, 0.0, 1.0);
		float glow = floor(g * 3.0 * weather_heat + w_bayer(cell)) / 3.0;
		o = over(o, vec4(1.0, 0.82, 0.40, glow * 0.24));
		float band = w_vnoise(vec2(cell.y * 0.07, TIME * 0.35));
		if (UV.y > 0.30 && band > 0.55) {
			float off = floor(sin(cell.y * 0.55 + TIME * 3.2) * weather_heat * 1.2 + 0.5);
			if (off != 0.0) {
				vec2 suv = SCREEN_UV + vec2(off / grid.x, 0.0);
				o = vec4(texture(screen_tex, suv).rgb, 1.0);
			}
		}
	}

	// дождь: три слоя косых капель, голова ярче хвоста
	if (weather_rain > 0.01) {
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float id = floor(cell.x + cell.y * 0.30);
			float h = w_hash(vec2(id, fi * 7.3 + 1.0));
			if (h < weather_rain * (0.22 - 0.04 * fi)) {
				float len = 5.0 + fi * 2.0;
				float speed = 60.0 + fi * 26.0;
				float span = grid.y + len * 2.0;
				float head = fract(w_hash(vec2(id, fi + 9.0)) + TIME * speed / span) * span - len;
				float d = head - cell.y;
				if (d >= 0.0 && d < len) {
					float a = d < 1.0 ? 0.85 : 0.45 - 0.05 * fi;
					o = over(o, vec4(0.78, 0.88, 1.0, a));
				}
			}
		}
	}

	// снегопад: мелкие и крупные (2×2 клетки) снежинки с покачиванием
	if (weather_snowfall > 0.01) {
		for (int j = 0; j < 2; j++) {
			float s = j == 0 ? 1.0 : 2.0;
			vec2 c = floor(cell / s);
			float spd = j == 0 ? 24.0 : 15.0;
			float sway = floor(sin(TIME * 0.8 + c.y * 0.13 + float(j) * 2.0) * 2.0);
			vec2 p = vec2(c.x + sway, c.y - floor(TIME * spd / s));
			float dens = j == 0 ? 0.030 : 0.011;
			if (w_hash(p + float(j) * 31.0) > 1.0 - weather_snowfall * dens) {
				o = over(o, vec4(1.0, 1.0, 1.0, j == 0 ? 0.85 : 0.95));
			}
		}
	}

	// внутри раскрытого интерьера погоды нет
	if (mask_amount > 0.0 && UV.x > mask.x && UV.x < mask.x + mask.z && UV.y > mask.y && UV.y < mask.y + mask.w) {
		o.a *= 1.0 - mask_amount;
	}
	COLOR = o;
}
