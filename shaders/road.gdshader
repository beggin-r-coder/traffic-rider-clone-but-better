shader_type spatial;
render_mode cull_back;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform bool two_way = false;
uniform float lane_w = 3.6;
uniform float half_w = 7.2;
uniform float wetness = 0.0;

// Anti-aliased band: 1 inside |x - c| < w/2.
float band(float x, float c, float w) {
	float d = abs(x - c) - w * 0.5;
	float aa = fwidth(x) * 0.75 + 0.002;
	return 1.0 - smoothstep(-aa, aa, d);
}

void fragment() {
	float d = UV.x;
	float s = UV.y;
	float n1 = texture(noise_tex, vec2(d, s) * 0.25).r;
	float n2 = texture(noise_tex, vec2(d, s) * 0.025).r;
	float n3 = texture(noise_tex, vec2(d, s) * 1.7).r;
	float ad = abs(d);

	// Asphalt base with large-scale patches and fine grain.
	vec3 col = vec3(0.105, 0.108, 0.115);
	col *= 0.78 + 0.4 * n2;
	col *= 0.86 + 0.28 * n3;
	// Worn tyre tracks (slightly darker & smoother) in each lane.
	float lane_pos = fract((d + half_w) / lane_w);
	float tracks = band(lane_pos, 0.3, 0.12) + band(lane_pos, 0.7, 0.12);
	col *= 1.0 - 0.12 * tracks;
	// Shoulder outside the edge lines: lighter, coarser.
	float shoulder = smoothstep(half_w + 0.05, half_w + 0.2, ad);
	col = mix(col, vec3(0.16, 0.155, 0.15) * (0.8 + 0.4 * n1), shoulder);
	// Concrete gutter at the very edge.
	float gutter = smoothstep(half_w + 1.75, half_w + 1.85, ad);
	col = mix(col, vec3(0.38, 0.37, 0.35) * (0.85 + 0.25 * n3), gutter);

	float paint = 0.0;
	vec3 paint_col = vec3(0.92, 0.92, 0.88);
	// Solid edge lines.
	paint += band(ad, half_w - 0.12, 0.16);
	// Dashed lane lines (4 m on, 8 m off).
	float dash = step(fract(s / 12.0), 0.333);
	float aa_s = fwidth(s / 12.0);
	dash = smoothstep(0.0, aa_s * 2.0 + 0.001, fract(s / 12.0)) * (1.0 - smoothstep(0.333 - aa_s * 2.0, 0.333, fract(s / 12.0)));
	paint += band(ad, lane_w, 0.13) * dash;
	float yellow = 0.0;
	if (two_way) {
		yellow = band(ad, 0.14, 0.11);
	} else {
		paint += band(d, 0.0, 0.13) * dash;
	}
	paint = clamp(paint, 0.0, 1.0);
	float wear = smoothstep(0.25, 0.75, n3 * 0.6 + n1 * 0.6);
	paint *= 0.75 + 0.25 * wear;
	yellow *= 0.8 + 0.2 * wear;
	col = mix(col, paint_col, paint);
	col = mix(col, vec3(0.95, 0.68, 0.12), yellow);

	ALBEDO = col;
	float rough = mix(0.82 - 0.1 * tracks, 0.55, max(paint, yellow));
	ROUGHNESS = mix(rough, 0.18, wetness);
	SPECULAR = 0.45;
}
