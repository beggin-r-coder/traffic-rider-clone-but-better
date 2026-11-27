shader_type canvas_item;
// Raindrops on the helmet visor (first person), modelled on rain on a window pane:
//  - static beads of many sizes, each a tiny lens (refracts a flipped, magnified bit of the scene)
//  - larger drops that run in a stick-slip motion with a slight wiggle, leaving a wet trail and a
//    string of tiny droplets behind them, and wiping beads away as they pass
//  - at low speed drops run down; at speed the airflow drives them up and outwards across the visor
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float speed = 0.0;       // 0..1 (normalised bike speed)
uniform float amount = 1.0;
uniform float aspect = 1.777;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec3 h31(float p) { vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xxy + p3.yzz) * p3.zyx); }

// Small static beads. Returns (normal.xy, mask).
vec3 beads(vec2 uv, float scale, float t, float seed) {
	vec2 g = uv * scale;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	vec3 n = h31(h21(id + seed) * 1000.0 + seed);
	vec2 p = (n.xy - 0.5) * 0.7;
	float d = length(f - p);
	float life = fract(t * (0.08 + n.z * 0.1) + n.x);
	float fade = smoothstep(0.0, 0.05, life) * smoothstep(1.0, 0.75, life);
	float r = mix(0.1, 0.36, n.z * n.z);
	float m = smoothstep(r, r * 0.8, d) * fade * step(n.y, 0.6 + 0.35 * amount);
	vec2 nrm = (f - p) / r;
	return vec3(nrm * m, m);
}

// Running drops with trails, in a frame where "down" is +y. `cols` columns across, each column
// `rows_h` screen-heights tall per drop cycle. All shapes measured in screen units (round drops).
// Returns (normal.xy, mask, trail).
vec4 runners(vec2 uv, float t, float cols, float rows_h, float seed) {
	float cw = 1.0 / cols;                       // column width (screen units)
	float col = floor(uv.x / cw);
	vec3 n = h31(col * 13.17 + seed);
	float y = uv.y + n.y * rows_h;               // stagger columns
	float cell = floor(y / rows_h);
	vec3 n2 = h31(col * 7.1 + cell * 3.3 + seed);
	if (n2.x > 0.3 * amount + 0.08) return vec4(0.0);
	float fy = y - cell * rows_h;               // 0..rows_h, distance down the cell
	float fx = uv.x - (col + 0.5) * cw;         // -cw/2..cw/2
	// Stick-slip progress down the cell.
	float tt = t * (0.1 + n.z * 0.12) + n2.y * 10.0;
	float prog = fract(tt);
	float slip = prog + sin(prog * 6.2831) * 0.11;
	float dy = mix(-0.04, rows_h + 0.04, slip);
	// Path wiggles sideways (same path for the drop and its trail).
	float wig = (sin(fy * 38.0 + n2.z * 6.0) * 0.006 + sin(fy * 97.0 + n.x * 4.0) * 0.0015);
	float x0 = (n2.z - 0.5) * cw * 0.5 + wig;
	float r = 0.011 + n2.x * 0.008;
	vec2 d = vec2(fx - x0, fy - dy);
	d.y *= (d.y > 0.0) ? 0.8 : 1.15;             // teardrop: fuller at the bottom
	float m = smoothstep(r, r * 0.82, length(d));
	// Wet trail above the drop, fading with age.
	float behind = dy - fy;
	float above = smoothstep(0.0, 0.01, behind) * (1.0 - smoothstep(0.08, rows_h * 0.7, behind));
	float tw = r * 0.38;
	float trail = smoothstep(tw, tw * 0.35, abs(fx - x0)) * above;
	// String of tiny droplets left behind in the trail.
	float step_y = 0.022;
	float k = floor(fy / step_y);
	float sy = fy - (k + 0.5) * step_y;
	vec2 sd = vec2(fx - x0, sy);
	float sr = r * mix(0.22, 0.42, h11(k + col * 3.0));
	float small = smoothstep(sr, sr * 0.7, length(sd)) * above * step(0.45, h11(k * 1.7 + col));
	vec2 nrm = d / r * m + sd / sr * small * 0.7;
	return vec4(nrm, max(m, small), trail);
}

void fragment() {
	vec2 suv = SCREEN_UV;
	vec2 uv = vec2(suv.x * aspect, suv.y);
	// Flow frame: rotate so drops run down at rest, up and outwards with speed.
	vec2 c = vec2(0.5 * aspect, 0.5);
	float s = clamp((suv.x - 0.5) * 2.5, -1.0, 1.0);
	float ang = speed * (3.14159 * 0.92) - speed * 0.45 * s;
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 fuv = rot * (uv - c) + c;
	float t = TIME * (1.0 + speed * 5.0);

	vec4 r1 = runners(fuv, t, 14.0, 0.75, 1.0);
	vec4 r2 = runners(fuv + vec2(0.031, 0.0), t * 1.13, 19.0, 0.6, 5.0);
	float trail = max(r1.w, r2.w);
	// Beads: many tiny ones + some medium, wiped away inside trails.
	vec3 b1 = beads(uv, 22.0, TIME, 1.0);
	vec3 b2 = beads(uv, 12.0, TIME * 0.8, 7.0);
	vec3 b3 = beads(uv, 40.0, TIME * 1.3, 3.0);
	float wipe = 1.0 - clamp(trail * 1.5, 0.0, 1.0);
	vec2 nrm = (b1.xy * 0.8 + b2.xy + b3.xy * 0.6) * wipe;
	float mask = max(max(b1.z, b2.z), b3.z) * wipe;
	// Rotate runner normals back to screen space.
	vec2 rn = transpose(rot) * (r1.xy + r2.xy);
	nrm += rn;
	mask = max(mask, max(r1.z, r2.z));
	if (mask < 0.003 && trail < 0.01) {
		discard;
	}
	// Lens refraction: each drop shows a flipped, magnified patch of the scene behind it.
	vec2 off = -nrm * 0.05;
	vec3 refr = textureLod(screen_tex, suv + off, 1.0).rgb;
	vec3 base = textureLod(screen_tex, suv, 0.0).rgb;
	float l = length(nrm);
	// Dark rim + bright glint on the upper side (light from above).
	float rim = smoothstep(0.6, 1.0, l);
	vec3 col = refr * (1.12 - 0.6 * rim) + vec3(1.0) * smoothstep(0.45, 0.85, -nrm.y) * smoothstep(1.0, 0.5, l) * 0.45;
	// The wet trail is a thin water film: it refracts and slightly darkens, with a bright edge.
	vec3 film = textureLod(screen_tex, suv + vec2(0.003, 0.004), 2.0).rgb * 0.82 + vec3(0.05);
	col = mix(mix(base, film, trail * 0.85), col, clamp(mask * 1.6, 0.0, 1.0));
	COLOR = vec4(col, clamp(max(mask * 1.6, trail * 0.9), 0.0, 1.0));
}
