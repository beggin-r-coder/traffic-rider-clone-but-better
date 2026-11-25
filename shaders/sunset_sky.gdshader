shader_type sky;
// Sunset sky: three-stop gradient with a warm glow around the sun.
uniform vec3 top_color : source_color = vec3(0.12, 0.16, 0.38);
uniform vec3 mid_color : source_color = vec3(0.55, 0.35, 0.5);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.55, 0.28);
uniform vec3 ground_color : source_color = vec3(0.12, 0.1, 0.12);
uniform vec3 glow_color : source_color = vec3(1.0, 0.6, 0.3);

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		float a = smoothstep(0.0, 0.12, h);
		float b = smoothstep(0.08, 0.5, h);
		col = mix(horizon_color, mid_color, a);
		col = mix(col, top_color, b);
	} else {
		col = mix(horizon_color * 0.7, ground_color, smoothstep(0.0, 0.2, -h));
	}
	vec3 sd = normalize(LIGHT0_DIRECTION);
	float s = max(dot(d, sd), 0.0);
	col += glow_color * pow(s, 8.0) * 0.6 * (1.0 - smoothstep(0.0, 0.4, h));
	col += glow_color * pow(s, 64.0) * 1.2;
	col += vec3(1.0, 0.85, 0.6) * smoothstep(0.9990, 0.9995, s) * 6.0;
	COLOR = col;
}
