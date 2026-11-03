// Общие функции погодных поверхностей: снег и лужи считаются по клеткам арта (2 px мира), поэтому края ступенчатые, с дизерингом.
// Параметры приходят глобальными uniform-ами из Weather (project.godot → shader_globals).
global uniform float weather_snow;   // снежный покров 0..1
global uniform float weather_wet;    // мокрая земля 0..1
global uniform float weather_rain;   // сила дождя 0..1 (кольца на лужах)

float w_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float w_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(w_hash(i), w_hash(i + vec2(1.0, 0.0)), f.x), mix(w_hash(i + vec2(0.0, 1.0)), w_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float w_bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = y * 4 + x;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

vec3 w_snow_color(vec2 cell) {
	return w_hash(cell * 1.7 + 11.0) < 0.2 ? vec3(0.80, 0.87, 0.97) : (w_hash(cell + 3.0) < 0.5 ? vec3(0.95, 0.97, 1.0) : vec3(0.90, 0.94, 0.99));
}

float w_snow_height(vec2 cell) {
	return w_vnoise(cell * 0.20 + 9.0) * 0.7 + w_vnoise(cell * 0.55) * 0.3;
}

// Лежит ли на клетке снег при покрове snow (дорога заметается слабее и клочьями).
bool w_snow_covers(vec2 cell, bool road, float snow) {
	float n = road ? w_vnoise(cell * 0.12) * 0.80 + w_bayer(cell) * 0.20 : w_vnoise(cell * 0.15) * 0.45 + w_hash(cell) * 0.25 + w_bayer(cell) * 0.30;
	float thr = snow * (road ? 0.85 : 1.12);
	return n < thr;
}

// Земля: тайлы тротуара, травы и дороги. Дорога (тёмная, серая) мокнет сильнее и заметается слабее.
vec4 weather_ground(vec4 col, vec2 cell, float t) {
	float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
	bool road = lum < 0.40 && sat < 0.12;
	float wet = weather_wet;
	float snow = weather_snow;
	if (wet > 0.01) {
		col.rgb *= 1.0 - 0.24 * wet;
		float pn = w_vnoise(cell * 0.11 + 3.0) * 0.65 + w_vnoise(cell * 0.29) * 0.35;
		float thr = (road ? 0.63 : 0.74) - 0.05 * wet;
		if (wet > 0.35 && pn > thr) {
			vec3 water = road ? vec3(0.36, 0.44, 0.58) : vec3(0.58, 0.66, 0.76);
			float deep = pn > thr + 0.07 ? 0.50 : 0.32;   // два тона воды: глубже в середине лужи
			col.rgb = mix(col.rgb, water, deep);
			if (w_bayer(cell) < 0.07 && pn > thr + 0.05) {
				col.rgb += 0.10;   // редкий дизеринговый блик отражения
			}
			vec2 id = floor(cell / 6.0);
			float h = w_hash(id);
			if (h > 0.72 && weather_rain > 0.2) {   // кольца от капель
				float r = fract(t * 0.6 + h * 5.0) * 3.4;
				float d = distance(cell + 0.5, (id + 0.5) * 6.0);
				if (abs(d - r) < 0.6) {
					col.rgb = mix(col.rgb, vec3(0.88, 0.94, 1.0), (1.0 - r / 3.4) * 0.75);
				}
			}
		}
	}
	if (snow > 0.01) {
		if (w_snow_covers(cell, road, snow)) {
			// рельеф сугробов: высота шумом, свет слева-сверху — склоны по свету светлые, по тени синие; край покрова — тень-толщина
			float h0 = w_snow_height(cell);
			float slope = (h0 - w_snow_height(cell + vec2(1.0, 1.0))) * 7.0 + (w_bayer(cell) - 0.5) * 0.18;
			vec3 c = vec3(0.89, 0.93, 0.99);                 // основной тон
			if (slope > 0.16) {
				c = vec3(0.99, 0.995, 1.0);                   // освещённый склон
			} else if (slope < -0.16) {
				c = vec3(0.70, 0.79, 0.93);                   // тень сугроба
			}
			if (!w_snow_covers(cell + vec2(0.0, 1.0), road, snow) || !w_snow_covers(cell + vec2(1.0, 0.0), road, snow)) {
				c = vec3(0.64, 0.74, 0.90);                   // нижний и правый край пятна: тень от толщины снега
			}
			if (w_hash(cell * 2.3 + 5.0) < 0.05) {
				c = vec3(0.80, 0.88, 0.98);                   // редкие искры-вмятины
			}
			col.rgb = c;
		}
	}
	return col;
}

// Предметы и здания. exposed — пиксель с «открытым небом» сверху (верхний край силуэта: снег ложится на него).
// mode: 0 — только верхний край, 1 — крыша здания (верхние roof долей спрайта), 2 — крона дерева/куст.
vec4 weather_prop(vec4 col, vec2 cell, float uy, bool exposed, bool below_open, int mode, float roof) {
	if (col.a < 0.05) {
		return col;
	}
	col.rgb *= 1.0 - 0.16 * weather_wet;
	float snow = weather_snow;
	if (snow < 0.01) {
		return col;
	}
	float n = w_hash(cell) * 0.40 + w_bayer(cell) * 0.30 + w_vnoise(cell * 0.2) * 0.30;
	bool cover = exposed && n < snow * 1.2 + 0.05;
	if (mode == 1 && uy < roof && n < snow * 1.15) {
		cover = true;
	}
	if (mode == 2 && uy < 0.8 && col.g > col.r * 1.02 && n < snow * 0.9 * (1.0 - uy * 0.7)) {
		cover = true;
	}
	if (cover) {
		vec3 c = w_snow_color(cell);
		if (exposed) {
			c = vec3(0.99, 0.995, 1.0);            // верхний край: свет
		} else if (below_open) {
			c = vec3(0.66, 0.76, 0.91);            // нижний край: тень-толщина
		} else if (mode == 1 && uy > roof * 0.82) {
			c = vec3(0.74, 0.82, 0.94);            // у свеса крыши снег в тени
		} else if (mode == 2 && uy > 0.45) {
			c = mix(c, vec3(0.72, 0.8, 0.93), 0.6); // под кроной темнее
		}
		col.rgb = c;
	}
	return col;
}
