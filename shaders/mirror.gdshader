shader_type spatial;
render_mode unshaded, cull_disabled;
// Rear-view mirror glass: shows its half of the rear camera image, horizontally flipped like a
// real mirror, with a slight tint and vignette from the glass.
uniform sampler2D rear_view : source_color, filter_linear;
uniform float u_start = 0.0;   // which half of the rear image this mirror shows
uniform float u_dir = 1.0;
uniform bool live = true;

void fragment() {
	vec2 uv = vec2(u_start + u_dir * UV.x * 0.5, UV.y);
	vec3 c = live ? texture(rear_view, uv).rgb : vec3(0.35, 0.4, 0.45) * (1.2 - UV.y);
	vec2 e = abs(UV - 0.5) * 2.0;
	float vig = 1.0 - 0.35 * pow(max(e.x, e.y), 4.0);
	ALBEDO = c * vec3(0.9, 0.93, 0.96) * vig;
}
