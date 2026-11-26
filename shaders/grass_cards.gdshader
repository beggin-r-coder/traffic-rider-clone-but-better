shader_type spatial;
render_mode cull_disabled;
// Verge grass: crossed cards showing a baked strip of real Poly Haven grass tufts.
// INSTANCE_CUSTOM = (u offset into the strip, random, -, -).
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_normal : filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec2 tex_px = vec2(2048.0, 512.0);

varying float v_rnd;

void vertex() {
	vec3 ip = MODEL_MATRIX[3].xyz;
	float ph = fract(ip.x * 0.31 + ip.z * 0.27) * 6.2831853;
	float top = 1.0 - UV.y;
	VERTEX.x += sin(TIME * 2.1 + ph) * 0.07 * top * top;
	VERTEX.z += cos(TIME * 1.7 + ph) * 0.05 * top * top;
	UV.x = INSTANCE_CUSTOM.x + UV.x * 0.5;
	v_rnd = INSTANCE_CUSTOM.y;
	// Bend normals upward so the grass is lit like a soft canopy rather than a flat card.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.55));
}

void fragment() {
	vec4 c = texture(grass_albedo, UV);
	vec2 px = UV * tex_px;
	float lod = max(log2(max(length(dFdx(px)), length(dFdy(px)))), 0.0);
	ALPHA = c.a * (1.0 + lod * 0.5);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 var_tint = mix(vec3(0.85, 0.92, 0.75), vec3(1.1, 1.08, 0.9), v_rnd);
	ALBEDO = c.rgb * tint * var_tint * mix(0.5, 1.0, 1.0 - UV.y);
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.35, 0.4, 0.15);
}
