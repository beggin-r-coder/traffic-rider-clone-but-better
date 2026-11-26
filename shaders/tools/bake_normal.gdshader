shader_type spatial;
render_mode unshaded, cull_disabled;
// Impostor bake pass: view-space normal encoded as colour (pre-linearised so the
// viewport's linear->sRGB output stores the exact 0..1 encoding).
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D ntex : hint_normal, filter_linear_mipmap;
uniform vec4 tint = vec4(1.0);
uniform bool has_tex = false;
uniform bool has_ntex = false;
uniform float alpha_cut = 0.45;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec4 c = tint;
	if (has_tex) { c *= texture(tex, UV); }
	if (c.a < alpha_cut) { discard; }
	vec3 n = NORMAL;
	if (has_ntex) {
		vec3 nm = texture(ntex, UV).rgb * 2.0 - 1.0;
		n = normalize(TANGENT * nm.x + BINORMAL * nm.y + NORMAL * nm.z);
	}
	ALBEDO = to_linear(clamp(n * 0.5 + 0.5, 0.0, 1.0));
}
