shader_type sky;
// Night sky: gradient, stars and a moon.
uniform vec3 top_color : source_color = vec3(0.01, 0.015, 0.045);
uniform vec3 horizon_color : source_color = vec3(0.07, 0.09, 0.16);
uniform vec3 moon_dir = vec3(0.4, 0.45, 0.8);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(h, 0.45));
	if (d.y < 0.0) {
		col = horizon_color * 0.6;
	}
	// Stars: hash a 3D grid on the sky sphere.
	vec3 g = d * 160.0;
	vec3 cell = floor(g);
	float r = hash(cell);
	if (r > 0.985 && d.y > 0.04) {
		vec3 c = cell + vec3(hash(cell + 1.3), hash(cell + 2.7), hash(cell + 5.1));
		float dist = length(g - c);
		float tw = 0.6 + 0.4 * sin(TIME * (2.0 + r * 5.0) + r * 40.0);
		col += vec3(0.9, 0.95, 1.0) * smoothstep(0.35, 0.0, dist) * (r - 0.985) * 60.0 * tw * smoothstep(0.04, 0.25, d.y);
	}
	// Moon + halo.
	vec3 md = normalize(moon_dir);
	float m = dot(d, md);
	col += vec3(0.95, 0.95, 0.85) * smoothstep(0.9993, 0.9996, m) * 2.5;
	col += vec3(0.25, 0.3, 0.45) * pow(max(m, 0.0), 300.0) * 0.6;
	COLOR = col;
}
