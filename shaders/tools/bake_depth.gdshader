shader_type spatial;
render_mode unshaded, cull_disabled;
// Impostor bake pass: depth through the plant (0 = front of bounding volume, 1 = back),
// pre-linearised so the stored value is exact.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint = vec4(1.0);
uniform bool has_tex = false;
uniform float alpha_cut = 0.45;
uniform float depth_near = 1.0;
uniform float depth_far = 10.0;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec4 c = tint;
	if (has_tex) { c *= texture(tex, UV); }
	if (c.a < alpha_cut) { discard; }
	float t = clamp((-VERTEX.z - depth_near) / max(depth_far - depth_near, 0.01), 0.0, 1.0);
	ALBEDO = to_linear(vec3(t));
}
