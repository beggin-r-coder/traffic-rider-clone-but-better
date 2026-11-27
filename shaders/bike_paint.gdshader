shader_type spatial;
render_mode cull_disabled;
// Re-colours only the blue livery pixels of the bike texture atlas.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness = 0.2;
uniform float metallic = 0.0;
uniform float hue_shift = 0.0;
uniform float sat_mul = 1.0;
uniform float val_mul = 1.0;
uniform float mask_hue = 0.66;          // hue of the livery colour that gets repainted
uniform bool solid = false;             // untextured model: the whole surface is paint
uniform vec3 solid_color : source_color = vec3(0.1);
uniform bool use_normal = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_orm = false;
uniform sampler2D orm_tex : filter_linear_mipmap, repeat_enable;   // G roughness, B metallic

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	if (solid) {
		ALBEDO = solid_color;
		ROUGHNESS = roughness;
		METALLIC = metallic;
		SPECULAR = 0.6;
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.03;
	} else {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(c);
	// Mask: saturated blues (Yamaha racing blue) only.
	float mask = (1.0 - smoothstep(0.06, 0.12, abs(fract(hsv.x - mask_hue + 0.5) - 0.5))) * smoothstep(0.2, 0.45, hsv.y);
	vec3 n = vec3(fract(hsv.x + hue_shift), clamp(hsv.y * sat_mul, 0.0, 1.0), clamp(hsv.z * val_mul, 0.0, 1.0));
	ALBEDO = mix(c, hsv2rgb(n), mask);
	// Glossy lacquer over everything; metallic flake in the coloured livery.
	ROUGHNESS = roughness;
	METALLIC = max(metallic, 0.35 * mask);
	if (use_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		ROUGHNESS = mix(orm.g, roughness, mask);
		METALLIC = mix(orm.b, max(metallic, 0.35), mask);
	}
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	SPECULAR = 0.6;
	CLEARCOAT = mix(0.7, 1.0, mask);
	CLEARCOAT_ROUGHNESS = 0.04;
	}
}
