shader_type spatial;
render_mode cull_back;

// Poly Haven "Asphalt 02" (CC0, 3 m x 3 m) + procedural lane markings.
// UV.x = lateral offset d (m), UV.y = distance along the road s (m, wrapped every 240 m).
uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable; // R=AO G=rough B=metal
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform bool two_way = false;
uniform float lane_w = 3.6;
uniform float half_w = 7.2;
uniform float tex_size = 3.0;        // metres covered by one texture tile
uniform float normal_strength = 1.0;
uniform float wetness = 0.0;
uniform float puddles = 0.0;
uniform sampler2D reflection_tex : source_color, filter_linear, repeat_disable;
uniform bool has_reflection = false;
uniform float rain_rate = 1.0;
uniform int streak_taps = 10;

// Rain ripples: expanding rings in a grid of cells (each cell a drop impact on a random timer).
vec2 ripples(vec2 p, float t) {
	vec2 g = p * 3.0;
	vec2 c0 = floor(g);
	vec2 acc = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = c0 + vec2(float(x), float(y));
			float h = fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
			float h2 = fract(h * 91.7);
			vec2 ctr = c + 0.15 + 0.7 * vec2(h, h2);
			float ph = fract(t * (0.9 + h2) * rain_rate + h * 5.0);
			vec2 d = g - ctr;
			float r = length(d);
			float rad = ph * 0.9;
			float ring = exp(-pow((r - rad) * 18.0, 2.0)) * (1.0 - ph) * (1.0 - ph);
			acc += normalize(d + 1e-4) * ring * sin((r - rad) * 40.0);
		}
	}
	return acc;
}

// Anti-aliased band: 1 inside |x - c| < w/2.
float band(float x, float c, float w) {
	float dist = abs(x - c) - w * 0.5;
	float aa = fwidth(x) * 0.75 + 0.002;
	return 1.0 - smoothstep(-aa, aa, dist);
}

void fragment() {
	float d = UV.x;
	float s = UV.y;
	float ad = abs(d);
	// Large-scale variation (patching, wear) from low-frequency noise.
	float n_big = texture(noise_tex, vec2(d, s) * 0.025).r;
	float n_mid = texture(noise_tex, vec2(d, s) * 0.11 + 0.37).r;

	// Two samples of the asphalt at different scales/offsets, blended by noise to hide tiling.
	// 240 m wrap / 3 m and / 7.5 m are both whole numbers, so the wrap stays seamless.
	vec2 uv_a = vec2(d, s) / tex_size;
	vec2 uv_b = vec2(-s, d) / (tex_size * 2.5) + vec2(0.31, 0.17);
	float mix_ab = smoothstep(0.35, 0.65, n_mid);
	vec3 alb = mix(texture(asphalt_albedo, uv_a).rgb, texture(asphalt_albedo, uv_b).rgb, mix_ab);
	vec3 arm = mix(texture(asphalt_arm, uv_a).rgb, texture(asphalt_arm, uv_b).rgb, mix_ab);
	vec3 nrm_a = texture(asphalt_normal, uv_a).rgb;
	vec3 nrm_b = texture(asphalt_normal, uv_b).rgb;
	// uv_b is rotated 90 degrees: rotate its tangent-space normal back.
	nrm_b = vec3(1.0 - nrm_b.g, nrm_b.r, nrm_b.b);
	vec3 nrm = mix(nrm_a, nrm_b, mix_ab);

	// Freshly-laid highway asphalt is darker than the scanned sample.
	vec3 col = alb * vec3(0.55, 0.55, 0.57);
	// Patchy tone shifts (older/newer asphalt) and a slightly darker centre of each lane.
	col *= 0.82 + 0.36 * n_big;
	float lane_pos = fract((d + half_w) / lane_w);
	// Worn tyre tracks: darker, smoother and polished.
	float tracks = band(lane_pos, 0.3, 0.16) + band(lane_pos, 0.7, 0.16);
	tracks *= step(ad, half_w);
	col *= 1.0 - 0.14 * tracks;
	// Oil drip line in the middle of each lane.
	float drip = band(lane_pos, 0.5, 0.5) * step(ad, half_w) * smoothstep(0.45, 0.8, n_mid);
	col *= 1.0 - 0.12 * drip;
	// Shoulder outside the edge lines: lighter, dustier.
	float shoulder = smoothstep(half_w + 0.05, half_w + 0.25, ad);
	col = mix(col, col * vec3(1.35, 1.32, 1.25) + 0.02, shoulder);
	// Concrete gutter at the very edge.
	float gutter = smoothstep(half_w + 1.75, half_w + 1.85, ad);
	col = mix(col, vec3(0.42, 0.41, 0.38) * (0.8 + 0.4 * alb.r * 2.0), gutter);

	// --- markings ---
	float paint = 0.0;
	paint += band(ad, half_w - 0.12, 0.16);                       // solid edge lines
	float f = fract(s / 12.0);                                      // dashes: 4 m on, 8 m off
	float aa_s = fwidth(s / 12.0);
	float dash = smoothstep(0.0, aa_s * 2.0 + 0.001, f) * (1.0 - smoothstep(0.333 - aa_s * 2.0, 0.333, f));
	paint += band(ad, lane_w, 0.13) * dash;
	float yellow = 0.0;
	if (two_way) {
		yellow = band(ad, 0.14, 0.11);                              // double solid centre line
	} else {
		paint += band(d, 0.0, 0.13) * dash;
	}
	paint = clamp(paint, 0.0, 1.0);
	// Paint sits on the aggregate: it wears off on the high stones and in the cracks.
	float wear = smoothstep(0.04, 0.16, alb.r * (0.7 + 0.6 * n_mid));
	float paint_cov = paint * mix(0.78, 1.0, wear);
	float yellow_cov = yellow * mix(0.8, 1.0, wear);
	col = mix(col, vec3(0.92, 0.92, 0.88), paint_cov);
	col = mix(col, vec3(0.9, 0.64, 0.1), yellow_cov);
	float marked = max(paint_cov, yellow_cov);

	float rough = arm.g * (1.0 - 0.18 * tracks) * (1.0 - 0.1 * drip);
	rough = mix(rough, 0.55, marked);
	vec3 nmap = mix(nrm, vec3(0.5, 0.5, 1.0), marked * 0.5);
	float spec = 0.18;

	if (wetness > 0.001) {
		// --- wet road ---
		// Puddles: organic shapes from domain-warped noise, soft edges, slightly more likely in the
		// worn wheel paths (smooth, noise-broken, so they never form straight bands).
		vec2 pp = vec2(d, s);
		vec2 warp = vec2(texture(noise_tex, pp * 0.021 + 0.31).r, texture(noise_tex, pp * 0.021 + 0.73).r) - 0.5;
		float pn = texture(noise_tex, pp * 0.045 + warp * 0.9).r;
		float pn2 = texture(noise_tex, pp * 0.13 + warp * 0.4 + 0.5).r;
		float lane_c = fract((d + half_w) / lane_w);
		float ruts = exp(-pow((lane_c - 0.3) * 9.0, 2.0)) + exp(-pow((lane_c - 0.7) * 9.0, 2.0));
		float pud_field = pn * 0.75 + pn2 * 0.25 + ruts * 0.08 * pn2 + shoulder * 0.08;
		float pud = smoothstep(0.6, 0.7, pud_field) * puddles * step(ad, half_w + 1.6);
		// Water film: soaked asphalt is darker and smoother but still rough enough to blur
		// reflections (that's what makes wet roads look wet, not mirrored).
		float film = texture(noise_tex, pp * 0.35 + 0.17).r;
		col *= mix(1.0, mix(0.5, 0.8, marked), wetness);
		col = mix(col, col * 0.55, pud);
		float wet_rough = mix(0.32, 0.18, smoothstep(0.3, 0.8, film));
		rough = mix(rough, mix(wet_rough, 0.22, marked), wetness);
		rough = mix(rough, 0.04, pud);
		// Rain ripples: faint on the film, clear in puddles. The aggregate drowns in puddles only.
		vec2 rip = ripples(pp, TIME) * mix(0.15, 1.0, pud) * wetness;
		nmap = mix(nmap, vec3(0.5, 0.5, 1.0), mix(0.35, 0.95, pud));
		nmap.xy += rip * 0.45;
		spec = mix(0.5, 0.5, pud);
		if (has_reflection) {
			// Planar reflection (mirrored camera, flipped horizontally) — only where it physically
			// belongs: sharp-ish in puddles (water Fresnel), and on the rough film only the bright
			// light sources come through, as soft streaks towards the viewer.
			float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
			vec2 ruv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + rip * 0.01;
			ruv = clamp(ruv, vec2(0.002), vec2(0.998));
			vec3 refl = texture(reflection_tex, ruv).rgb;
			float slen = mix(0.05, 0.28, pow(1.0 - ndv, 1.3));
			vec3 acc = vec3(0.0);
			float wsum = 0.0;
			for (int i = 0; i < streak_taps; i++) {
				float t = float(i) / float(max(streak_taps - 1, 1));
				vec2 o = vec2((film - 0.5) * 0.01 * t, -t * slen);
				float w = 1.0 - t * 0.6;
				acc += texture(reflection_tex, clamp(ruv + o, vec2(0.002), vec2(0.998))).rgb * w;
				wsum += w;
			}
			vec3 streak = acc / wsum;
			// Only bright light sources survive the rough film (soft knee, no hard threshold).
			float lum = dot(streak, vec3(0.3, 0.55, 0.15));
			vec3 lights_only = streak * smoothstep(0.35, 0.9, lum) * 1.6;
			float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
			// Fade reflections out with distance (the mirror plane is only exact near the bike).
			float dist_fade = 1.0 - smoothstep(60.0, 160.0, length(VERTEX));
			vec3 puddle_refl = refl * fres * 1.2;
			EMISSION = (puddle_refl * pud + lights_only * (0.25 + 0.75 * fres) * (1.0 - pud * 0.5)) * wetness * dist_fade;
			col *= 1.0 - pud * fres * 0.8;
			spec = mix(spec, 0.15, pud);   // puddles: the planar reflection takes over from sky specular
		}
	}

	ALBEDO = col;
	AO = mix(arm.r, 1.0, marked * 0.7);
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = rough;
	SPECULAR = spec;
	NORMAL_MAP = clamp(nmap, 0.0, 1.0);
	NORMAL_MAP_DEPTH = normal_strength;
}
