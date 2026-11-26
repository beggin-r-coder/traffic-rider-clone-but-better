shader_type canvas_item;
// Raindrops on the helmet visor (first person). Drops bead on the glass, refract the view, and
// get blown outwards/upwards by the airflow as speed rises; at low speed they slide down.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float speed = 0.0;       // 0..1 (normalised bike speed)
uniform float amount = 1.0;
uniform float aspect = 1.777;

float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
vec2 h22(vec2 p) { float n = h21(p); return vec2(n, h21(p + n)); }

// One layer of drops. Returns (normal.xy, mask).
vec3 layer(vec2 uv, float scale, float t, float seed) {
	vec2 centre = vec2(0.5 * aspect, 0.58);
	vec2 g = uv * scale;
	vec2 cell = floor(g);
	vec3 acc = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 r = h22(c + seed);
			if (r.x > 0.62 * amount + 0.25) continue;
			float life_rate = 0.35 + r.y * 0.5;
			float ph = fract(t * life_rate + r.x * 7.0);
			// Drop spawn position inside its cell.
			vec2 p0 = c + 0.2 + 0.6 * h22(c * 1.7 + seed);
			// Airflow pushes drops outwards from the screen centre and up; gravity pulls them down.
			vec2 world_p = p0 / scale;
			vec2 out_dir = normalize(world_p - centre + 1e-4);
			vec2 flow = out_dir * speed * 1.8 + vec2(0.0, -1.2) * speed + vec2(0.0, 0.25) * (1.0 - speed);
			vec2 p = p0 + flow * ph * ph * scale * 0.35;
			float rad = (0.12 + 0.2 * r.y) * mix(1.0, 0.6, speed);
			// Elongate along the flow when moving fast.
			vec2 d = g - p;
			vec2 fd = normalize(flow + 1e-4);
			float along = dot(d, fd);
			float across = dot(d, vec2(-fd.y, fd.x));
			float stretch = 1.0 + speed * 2.5 * ph;
			vec2 q = vec2(along / stretch, across);
			float dist = length(q) / rad;
			float fade = smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.75, 1.0, ph));
			float m = smoothstep(1.0, 0.75, dist) * fade;
			acc.xy += (q / rad) * m;
			acc.z = max(acc.z, m);
		}
	}
	return acc;
}

void fragment() {
	vec2 uv = vec2(SCREEN_UV.x * aspect, SCREEN_UV.y);
	vec3 a = layer(uv, 9.0, TIME, 1.0);
	vec3 b = layer(uv, 17.0, TIME * 1.2, 7.0);
	vec2 n = a.xy * 0.03 + b.xy * 0.018;
	float mask = max(a.z, b.z);
	vec2 suv = SCREEN_UV - n;
	vec3 refr = textureLod(screen_tex, suv, 0.0).rgb;
	// Darker rim, bright specular glint at the top of each drop.
	float rim = smoothstep(0.35, 1.0, length(n) * 30.0);
	vec3 col = refr * (1.0 - 0.25 * rim) + vec3(0.9) * smoothstep(0.012, 0.03, -n.y) * 0.25;
	// Slight overall wet blur/haze on the visor.
	COLOR = vec4(col, mask * 0.95);
}
