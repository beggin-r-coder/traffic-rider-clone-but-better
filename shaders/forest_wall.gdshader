shader_type spatial;
render_mode cull_disabled;
// Dark forest interior behind the tree rows: a vertical band with a jagged fir-tip skyline.
// UV.x = distance along the road (m), UV.y = height fraction (0 bottom .. 1 top).
uniform vec3 color_low : source_color = vec3(0.07, 0.1, 0.05);
uniform vec3 color_high : source_color = vec3(0.13, 0.19, 0.09);

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float s = UV.x;
	float cell = floor(s / 3.1);
	float t = fract(s / 3.1);
	float tip = 1.0 - abs(t * 2.0 - 1.0);              // triangular fir tip
	float top = 0.62 + 0.2 * hash(cell) + tip * 0.18;
	if (1.0 - UV.y > top) discard;
	// Vertical trunk streaks.
	float trunk = smoothstep(0.08, 0.0, abs(fract(s / 1.7 + hash(cell) * 0.5) - 0.5)) * step(UV.y, 0.35 + 0.0);
	vec3 col = mix(color_low, color_high, 1.0 - UV.y);
	col *= 1.0 - trunk * 0.35;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
