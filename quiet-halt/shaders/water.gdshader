shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

global uniform vec3 world_focus;
global uniform float world_curve;
global uniform float night_amount;
global uniform vec3 sky_horizon;
global uniform float snow_amount;

uniform vec3 shallow_color : source_color = vec3(0.35, 0.72, 0.80);
uniform vec3 deep_color : source_color = vec3(0.12, 0.38, 0.55);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 d = wpos.xz - world_focus.xz;
	VERTEX.y -= dot(d, d) * world_curve;
	VERTEX.y += sin(wpos.x * 1.3 + TIME * 1.2) * cos(wpos.z * 1.1 + TIME * 0.9) * 0.025;
}

void fragment() {
	float r1 = sin(wpos.x * 2.1 + TIME * 1.1) * sin(wpos.z * 1.7 - TIME * 0.8);
	float r2 = sin((wpos.x + wpos.z) * 1.3 + TIME * 0.6);
	float ripple = r1 * 0.5 + r2 * 0.5;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 col = mix(deep_color, shallow_color, 0.5 + ripple * 0.25);
	col = mix(col, vec3(0.8, 0.9, 0.95), snow_amount * 0.35);
	ALBEDO = col;
	ROUGHNESS = 0.25;
	SPECULAR = 0.5;
	float spark = step(0.965, 0.5 + 0.5 * sin(wpos.x * 7.0 + TIME * 2.0) * sin(wpos.z * 9.0 - TIME * 1.7));
	EMISSION = sky_horizon * fres * 0.25 + vec3(spark) * 0.3 * (1.0 - night_amount * 0.7);
	ALPHA = clamp(0.78 + fres * 0.2, 0.0, 1.0);
}
