shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
// Overlay pass (next_pass) for the bike and rider in the rain.
// Drops come from particle simulations (scripts/drop_sim.gd) running in bike space: one water map
// for the sides (z/y plane: drops run down, and backwards with speed) and one for the top surfaces
// (x/z plane: drops sit still until the wind sweeps them back). Each texel stores the drop normal
// and thickness, so drops are lit as real water caps on the paint.
uniform bool use_sim = false;
uniform sampler2D side_map : filter_linear;
uniform sampler2D top_map : filter_linear;
uniform vec4 side_domain;          // z0, y0, z_size, y_size
uniform vec4 top_domain;           // x0, z0, x_size, z_size
uniform mat4 world_to_bike;
uniform float speed = 0.0;

varying vec3 v_bpos;
varying vec3 v_bn;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_bpos = (world_to_bike * vec4(wp, 1.0)).xyz;
	v_bn = normalize((world_to_bike * vec4(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz), 0.0)).xyz);
}

uniform float bead_cell = 0.0055;   // metres between micro-beads

float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

// Dense static micro-beads (too many to simulate): (slope.xy, mask).
vec3 beads(vec2 p) {
	vec2 g = p / bead_cell;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	if (h21(id) > 0.7) return vec3(0.0);
	vec2 o = (vec2(h21(id + 3.1), h21(id + 7.7)) - 0.5) * 0.55;
	float rad = mix(0.12, 0.34, pow(h21(id + 1.9), 2.0));
	vec2 d = (f - o) / rad;
	float m = smoothstep(1.0, 0.7, length(d));
	return vec3(d * m, m);
}

// Returns (slope.xy, thickness, coverage) from a water map at uv.
vec4 sample_map(sampler2D m, vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
	vec4 w = texture(m, uv);
	if (w.a < 0.02) return vec4(0.0);
	vec3 d = w.rgb / w.a;
	return vec4(d.xy * 2.0 - 1.0, d.z, w.a);
}

void fragment() {
	if (!use_sim) discard;
	vec3 n = normalize(v_bn);
	vec3 aw = abs(n);
	// Side plane: map x = bike z (backwards), map y = down.
	vec2 suv = vec2((v_bpos.z - side_domain.x) / side_domain.z, 1.0 - (v_bpos.y - side_domain.y) / side_domain.w);
	// Mirror the left side so its drops differ from the right side's.
	if (n.x < 0.0) suv.y = 1.0 - suv.y * 0.97 - 0.013;
	vec2 tuv = vec2((v_bpos.x - top_domain.x) / top_domain.z, (v_bpos.z - top_domain.y) / top_domain.w);
	vec4 ds = sample_map(side_map, suv);
	vec4 dt = sample_map(top_map, tuv);
	// Front/back faces reuse the side map (drops running down).
	vec4 df = sample_map(side_map, vec2((v_bpos.x + 0.6) / 1.2 * 0.5 + 0.25, suv.y));
	float ws = smoothstep(0.35, 0.75, aw.x);
	float wt = smoothstep(0.45, 0.8, aw.y) * step(0.0, n.y);
	float wf = smoothstep(0.55, 0.85, aw.z);
	float tot = max(ws + wt + wf, 1e-3);
	float cover = (ds.w * ws + dt.w * wt + df.w * wf) / tot;
	vec3 grad = (vec3(0.0, -ds.y, ds.x) * ws + vec3(dt.x, 0.0, dt.y) * wt + vec3(df.x, -df.y, 0.0) * wf) / tot;
	float th = (ds.z * ws + dt.z * wt + df.z * wf) / tot;
	// Micro-beads (triplanar), swept away where a simulated drop has passed (its trail leaves the
	// surface wetter but bead-free) — approximated by suppressing beads under any simulated water.
	vec3 bx = beads(v_bpos.zy);
	vec3 by = beads(v_bpos.xz);
	vec3 bz = beads(v_bpos.xy);
	float bw = (bx.z * ws + by.z * wt + bz.z * wf) / tot * (1.0 - smoothstep(0.05, 0.3, cover));
	vec3 bgrad = (vec3(0.0, -bx.y, bx.x) * ws + vec3(by.x, 0.0, by.y) * wt + vec3(bz.x, -bz.y, 0.0) * wf) / tot;
	grad += bgrad * (1.0 - smoothstep(0.05, 0.3, cover));
	th = max(th, bw * 0.6);
	cover = max(cover, bw * 0.8);
	if (cover < 0.05) discard;
	vec3 on_bike = normalize(n + grad * 0.9);
	// Back to view space (bike -> world -> view).
	mat3 bike_to_world = inverse(mat3(world_to_bike));
	NORMAL = normalize((VIEW_MATRIX * vec4(bike_to_world * on_bike, 0.0)).xyz);
	ALBEDO = vec3(0.012, 0.014, 0.017);
	ROUGHNESS = 0.02;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	// Thin edges are nearly invisible; the body of a drop darkens/reflects.
	ALPHA = clamp(cover * (0.5 + 0.5 * th), 0.0, 0.9);
}
