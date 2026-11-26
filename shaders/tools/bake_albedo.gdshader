shader_type spatial;
render_mode unshaded, cull_disabled;
// Impostor bake pass: albedo with a depth-based darkening so canopy gaps read as deep shade.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint = vec4(1.0);
uniform bool has_tex = false;
uniform float depth_near = 1.0;
uniform float depth_far = 10.0;
uniform float alpha_cut = 0.45;

void fragment() {
	vec4 c = tint;
	if (has_tex) { c *= texture(tex, UV); }
	if (c.a < alpha_cut) { discard; }
	float t = clamp((-VERTEX.z - depth_near) / max(depth_far - depth_near, 0.01), 0.0, 1.0);
	ALBEDO = c.rgb * mix(1.0, 0.38, t * t);
}
