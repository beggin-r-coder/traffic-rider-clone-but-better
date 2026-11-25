shader_type spatial;

varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float r = length(wpos.xz);
	float pool = exp(-r * r * 0.06);
	vec2 g = abs(fract(wpos.xz * 0.5) - 0.5);
	float grid = 1.0 - smoothstep(0.0, 0.02, min(g.x, g.y));
	vec3 col = vec3(0.025, 0.027, 0.032) + vec3(0.05, 0.05, 0.06) * pool;
	col += vec3(0.04, 0.05, 0.07) * grid * pool;
	ALBEDO = col;
	ROUGHNESS = 0.18;
	METALLIC = 0.2;
}
