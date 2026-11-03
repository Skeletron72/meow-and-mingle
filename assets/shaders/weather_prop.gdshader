// Деревья, кусты, предметы и здания: снег ложится на верхний край силуэта, на крышу (mode 1) и на крону (mode 2); в дождь — темнеют.
shader_type canvas_item;
#include "res://assets/shaders/weather_surface.gdshaderinc"

uniform int mode = 0;               // 0 предмет, 1 здание (крыша), 2 дерево/куст
uniform float roof_frac = 0.42;     // доля высоты здания, занятая крышей

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 cell = floor(world / 2.0);
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
	COLOR = weather_prop(COLOR, cell, UV.y, exposed, below_open, mode, roof_frac);
}
