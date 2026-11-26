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

	ALBEDO = col;
	AO = mix(arm.r, 1.0, marked * 0.7);
	AO_LIGHT_AFFECT = 0.4;
	float rough = arm.g * (1.0 - 0.18 * tracks) * (1.0 - 0.1 * drip);
	rough = mix(rough, 0.55, marked);
	ROUGHNESS = mix(rough, 0.12, wetness);
	SPECULAR = 0.18;
	// Painted lines flatten the bumps a little.
	NORMAL_MAP = mix(nrm, vec3(0.5, 0.5, 1.0), marked * 0.5);
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - wetness * 0.6);
}
