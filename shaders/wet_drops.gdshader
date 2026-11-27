shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
// Overlay pass (next_pass) for the bike and rider in the rain: fine water beads on every surface,
// plus drops that run down in a stick-slip motion leaving thin wet trails, and get blown
// backwards faster as speed rises. Placed in the object's own space so drops stick to the bike.
uniform float speed = 0.0;      // 0..1
uniform float amount = 1.0;
uniform float cell = 0.009;     // metres between beads (small drops)

varying vec3 v_obj_pos;
varying vec3 v_obj_n;

float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

// Static beads on one projection plane: (gradient.xy, mask).
vec3 beads(vec2 p, float sz) {
	vec2 g = p / sz;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float r0 = h21(id);
	if (r0 > 0.62 * amount + 0.1) return vec3(0.0);
	vec2 o = (vec2(h21(id + 3.1), h21(id + 7.7)) - 0.5) * 0.6;
	float rad = mix(0.12, 0.34, pow(h21(id + 1.9), 2.0));
	vec2 d = (f - o) / rad;
	float m = smoothstep(1.0, 0.75, length(d));
	return vec3(d * m, m);
}

// Running drops on one plane, flowing along `flow` (unit, plane space). (gradient.xy, mask)
vec3 runners(vec2 p, vec2 flow) {
	// Work in a frame where the flow is +y.
	vec2 side = vec2(flow.y, -flow.x);
	vec2 q = vec2(dot(p, side), dot(p, flow)) / (cell * 4.0);
	float col = floor(q.x);
	float r = h21(vec2(col, 2.0));
	if (r > 0.35 * amount) return vec3(0.0);
	float fx = fract(q.x) - 0.5;
	float rate = 0.18 + r * 0.25 + speed * 1.4;
	float tt = TIME * rate + h21(vec2(col, 5.0)) * 20.0;
	float prog = fract(tt);
	float slip = prog + sin(prog * 6.2831) * 0.13;           // stick-slip
	float seg = 6.0;                                          // cell length (in cells along flow)
	float y = fract(q.y / seg) * seg;
	float dy = slip * seg;
	float wig = sin(q.y * 2.3 + r * 9.0) * 0.08;
	vec2 d = vec2(fx - wig, (y - dy) * 0.6) / 0.22;
	float m = smoothstep(1.0, 0.7, length(d));
	// Thin wet trail behind the drop.
	float behind = smoothstep(0.0, 0.3, dy - y) * smoothstep(seg * 0.6, 0.0, dy - y);
	float trail = smoothstep(0.09, 0.02, abs(fx - wig)) * behind * 0.6;
	vec2 grad = side * d.x + flow * d.y;
	return vec3(grad * m + side * (fx - wig) * trail * 3.0, max(m, trail));
}

void vertex() {
	v_obj_pos = VERTEX;
	v_obj_n = NORMAL;
}

void fragment() {
	vec3 n = normalize(v_obj_n);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	// Object space: -Z forward, +Y up. Flow on side planes: down, and backwards (+Z) with speed.
	vec2 side_flow = normalize(vec2(speed * 2.2, -1.0));      // plane (z, y)
	vec2 top_flow = vec2(0.0, 1.0);                           // plane (x, z): backwards
	vec3 bx = beads(v_obj_pos.zy, cell) ; vec3 rx = runners(v_obj_pos.zy, side_flow);
	vec3 by = beads(v_obj_pos.xz, cell) ; vec3 ry = runners(v_obj_pos.xz, top_flow) * step(0.15, speed);
	vec3 bz = beads(v_obj_pos.xy, cell) ; vec3 rz = runners(v_obj_pos.xy, vec2(0.0, -1.0));
	vec3 dx = vec3(bx.xy + rx.xy, max(bx.z, rx.z));
	vec3 dy = vec3(by.xy + ry.xy, max(by.z, ry.z));
	vec3 dz = vec3(bz.xy + rz.xy, max(bz.z, rz.z));
	float mask = dx.z * w.x + dy.z * w.y + dz.z * w.z;
	if (mask < 0.02) discard;
	vec3 grad = vec3(0.0, dx.y, dx.x) * w.x + vec3(dy.x, 0.0, dy.y) * w.y + vec3(dz.x, dz.y, 0.0) * w.z;
	vec3 on = normalize(n + grad * 0.7);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(on, 0.0)).xyz);
	ALBEDO = vec3(0.015, 0.017, 0.02);
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ALPHA = clamp(mask * 0.8, 0.0, 0.75);
}
