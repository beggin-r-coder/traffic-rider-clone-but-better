shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
// Overlay pass (next_pass) for the bike and rider in the rain: water droplets beading on every
// surface, plus drops that run down and get blown backwards as speed rises. Placement is in the
// object's own space so drops stick to the bike.
uniform float speed = 0.0;      // 0..1
uniform float amount = 1.0;
uniform float cell = 0.022;     // metres between drops

varying vec3 v_obj_pos;
varying vec3 v_obj_n;

float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }

// Drops on one projection plane; returns (gradient.xy, mask).
vec3 plane_drops(vec2 p, float run_dir_sign) {
	vec3 acc = vec3(0.0);
	vec2 g = p / cell;
	vec2 c0 = floor(g);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = c0 + vec2(float(x), float(y));
			float r = h21(c);
			if (r > 0.55 * amount + 0.1) continue;
			float r2 = h21(c + 3.1);
			float r3 = h21(c + 7.7);
			vec2 pos = c + 0.15 + 0.7 * vec2(r2, r3);
			// ~30% of drops run: down at low speed, backwards (and down) at speed.
			float running = step(0.7, r2);
			float t = fract(TIME * (0.25 + r3 * 0.4 + speed * 1.5) + r);
			vec2 flow = vec2(speed * 3.0 * run_dir_sign, -1.0 - speed);
			pos += running * flow * t * 2.5;
			float rad = (0.18 + 0.22 * r3) * (running > 0.5 ? 0.8 : 1.0);
			vec2 d = g - pos;
			// Running drops leave an elongated trail.
			if (running > 0.5) {
				vec2 fd = normalize(flow);
				float al = dot(d, fd);
				d = vec2(al < 0.0 ? al * 0.25 : al, dot(d, vec2(-fd.y, fd.x)));
			}
			float dist = length(d) / rad;
			float m = smoothstep(1.0, 0.8, dist);
			float fade = running > 0.5 ? (1.0 - smoothstep(0.7, 1.0, t)) : 1.0;
			acc.xy += d / rad * m * fade;
			acc.z = max(acc.z, m * fade);
		}
	}
	return acc;
}

void vertex() {
	v_obj_pos = VERTEX;
	v_obj_n = NORMAL;
}

void fragment() {
	vec3 n = normalize(v_obj_n);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	// Object space: -Z forward, +Y up. "Backwards" on side planes is +Z.
	vec3 dx = plane_drops(v_obj_pos.zy, 1.0);   // side faces (normal ~X)
	vec3 dy = plane_drops(v_obj_pos.xz, 0.0);   // top faces (normal ~Y): no gravity run
	vec3 dz = plane_drops(v_obj_pos.xy, 0.0);   // front/back faces
	float mask = dx.z * w.x + dy.z * w.y + dz.z * w.z;
	if (mask < 0.02) discard;
	// Bend the surface normal like a water cap.
	vec3 grad = vec3(0.0, dx.y, dx.x) * w.x + vec3(dy.x, 0.0, dy.y) * w.y + vec3(dz.x, dz.y, 0.0) * w.z;
	vec3 on = normalize(n + grad * 0.9);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(on, 0.0)).xyz);
	ALBEDO = vec3(0.015, 0.017, 0.02);
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ALPHA = clamp(mask * 0.9, 0.0, 0.85);
}
