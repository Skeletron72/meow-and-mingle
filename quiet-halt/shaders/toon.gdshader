shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_back;
// Мягкий «тёплый» тун-шейдер с изгибом мира и сезонной окраской.
// Цвет берётся из вершин: RGB — цвет (sRGB), A — тип окраски:
//   1.0 обычный, 0.5 листва, 0.25 цветущая (вишня), 0.0 трава.

global uniform vec3 world_focus;
global uniform float world_curve;
global uniform vec3 foliage_tint;
global uniform vec3 blossom_tint;
global uniform vec3 grass_tint;
global uniform float snow_amount;
global uniform float night_amount;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float emission_energy = 0.0;
uniform float night_only = 1.0;
uniform float snow_catch = 1.0;
uniform float rim = 0.0;
uniform vec3 rim_color : source_color = vec3(1.0, 0.95, 0.85);

varying vec3 w_normal;

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 d = wp.xz - world_focus.xz;
	float drop = dot(d, d) * world_curve;
	VERTEX.y -= drop / length(MODEL_MATRIX[1].xyz);
	w_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 col = lin(COLOR.rgb) * base_color.rgb;
	float a = COLOR.a;
	if (a < 0.1) {
		col *= lin(grass_tint) * 1.6;
	} else if (a < 0.4) {
		col *= lin(blossom_tint) * 1.6;
	} else if (a < 0.7) {
		col *= lin(foliage_tint) * 1.6;
	}
	float up = clamp(w_normal.y, 0.0, 1.0);
	float s = smoothstep(0.55, 0.9, up) * snow_amount * snow_catch;
	col = mix(col, lin(vec3(0.95, 0.97, 1.0)), s);
	if (emission_energy > 0.0 && night_only > 0.5) {
		// окна днём — тёмное стекло, ночью — тёплый свет
		col = mix(lin(vec3(0.30, 0.40, 0.50)), col, night_amount);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 em = rim_color * fres * rim;
	if (emission_energy > 0.0) {
		float k = mix(1.0, night_amount, night_only);
		em += lin(COLOR.rgb) * emission_energy * k;
	}
	EMISSION = em;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = ndl * 0.5 + 0.5;
	float lit = smoothstep(0.32, 0.64, wrap);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (lit * 0.8 + wrap * 0.2) / PI;
}
