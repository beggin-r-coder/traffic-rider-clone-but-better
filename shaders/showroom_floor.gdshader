shader_type spatial;

uniform vec3 bg = vec3(0.035, 0.04, 0.055);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float r = length(wpos.xz);
	float pool = exp(-r * r * 0.05);
	vec2 g = abs(fract(wpos.xz * 0.5) - 0.5);
	float grid = 1.0 - smoothstep(0.0, 0.015, min(g.x, g.y));
	vec3 col = mix(bg * 0.6, vec3(0.06, 0.065, 0.075), pool);
	col += vec3(0.025, 0.03, 0.04) * grid * pool;
	// fade into the background colour with distance so there is no visible edge
	float fade = smoothstep(6.0, 30.0, r);
	ALBEDO = mix(col, bg * 0.5, fade);
	ROUGHNESS = mix(0.38, 1.0, fade);
	SPECULAR = mix(0.35, 0.0, fade);
}
