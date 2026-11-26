shader_type spatial;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.11).r;
	float n2 = texture(noise_tex, wpos.xz * 0.013).r;
	float n3 = texture(noise_tex, wpos.xz * 0.9).r;
	vec3 col = COLOR.rgb;
	col *= 0.75 + 0.5 * n2;
	col *= 0.85 + 0.3 * n1;
	col = mix(col, col * vec3(1.15, 1.05, 0.7), smoothstep(0.55, 0.75, n2) * 0.6);
	col *= 0.9 + 0.2 * n3;
	ALBEDO = col * tint;
	ROUGHNESS = 0.95;
	SPECULAR = 0.04;
}
