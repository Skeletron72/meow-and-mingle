shader_type sky;

global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform float night_amount;
global uniform vec3 sun_dir;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 top = pow(sky_top, vec3(2.2));
	vec3 hor = pow(sky_horizon, vec3(2.2));
	float t = pow(clamp(h, 0.0, 1.0), 0.5);
	vec3 col = mix(hor, top, t);
	if (h < 0.0) {
		col = mix(hor, hor * 0.85, clamp(-h * 5.0, 0.0, 1.0));
	}
	// звёзды
	float vis = smoothstep(0.0, 0.35, h) * night_amount;
	vec3 cell = floor(dir * 140.0);
	float st = step(0.9972, hash13(cell));
	float tw = 0.6 + 0.4 * sin(TIME * 2.0 + hash13(cell + 7.0) * 30.0);
	col += vec3(1.0, 0.97, 0.9) * st * tw * vis * 1.2;
	// солнце / луна
	float sd = dot(dir, normalize(sun_dir));
	vec3 sun_col = mix(vec3(1.0, 0.93, 0.7), vec3(0.85, 0.9, 1.0), night_amount);
	float disc = smoothstep(0.9985, 0.9992, sd);
	float halo = pow(max(sd, 0.0), 40.0) * mix(0.6, 0.18, night_amount);
	col += sun_col * (disc * 1.6 + halo);
	COLOR = col;
}
