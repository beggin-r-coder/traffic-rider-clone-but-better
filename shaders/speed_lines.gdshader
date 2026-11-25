shader_type canvas_item;
// Subtle radial speed streaks around the screen edges.
uniform float amount = 0.0;
uniform float aspect = 1.777;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 p = (UV - vec2(0.5, 0.46)) * vec2(aspect, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x);
	float cell = floor(a * 70.0);
	float h = hash(cell);
	float speed = 2.5 + h * 3.0;
	float t = fract(h * 7.0 + TIME * speed);
	// one dash per angular cell sliding outwards
	float pos = mix(0.35, 1.2, t);
	float dash = smoothstep(0.12, 0.0, abs(r - pos)) * step(0.55, h);
	float edge = fract(a * 70.0);
	dash *= smoothstep(0.0, 0.3, edge) * smoothstep(1.0, 0.7, edge);
	float mask = smoothstep(0.38, 0.75, r);
	COLOR = vec4(1.0, 1.0, 1.0, dash * mask * amount * 0.22);
}
