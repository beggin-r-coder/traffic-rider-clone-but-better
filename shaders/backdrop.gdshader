shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec3 far_color : source_color = vec3(0.55, 0.64, 0.74);
uniform vec3 near_color : source_color = vec3(0.36, 0.45, 0.5);
uniform vec3 haze_color : source_color = vec3(0.7, 0.79, 0.88);

varying vec3 lpos;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float vnoise(float x, float period, float seed) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(mod(i, period) + seed), hash(mod(i + 1.0, period) + seed), f);
}
float ridge(float a, float seed, float freq) {
	float h = 0.0;
	float amp = 0.5;
	float fr = freq;
	for (int i = 0; i < 5; i++) {
		// wrap around the ring seamlessly by using the angle * integer frequency
		float n = vnoise(a * fr, 64.0 * fr, seed * 17.0);
		h += (1.0 - abs(n * 2.0 - 1.0)) * amp;
		amp *= 0.5;
		fr *= 2.0;
	}
	return h;
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float ang = atan(lpos.z, lpos.x) / 6.2831853 + 0.5; // 0..1
	float a = ang * 64.0;
	float y = (lpos.y + 200.0) / 400.0; // 0 bottom .. 1 top
	// Two mountain layers.
	float h_far = 0.30 + ridge(a, 1.0, 1.0) * 0.32;
	float h_near = 0.22 + ridge(a, 4.0, 2.0) * 0.22;
	vec3 col;
	float alpha = 0.0;
	if (y < h_near) {
		col = mix(near_color * 0.8, near_color, y / h_near);
		alpha = 1.0;
	} else if (y < h_far) {
		col = mix(far_color * 0.92, far_color, (y - h_near) / max(h_far - h_near, 0.01));
		alpha = 1.0;
	}
	if (alpha < 0.5) discard;
	// Fade the base into the horizon haze.
	ALBEDO = col;
}
