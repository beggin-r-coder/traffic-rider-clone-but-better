shader_type canvas_item;
// Helmet view: the visor opening of a race helmet framing the screen. A dark padded edge at the top
// (brow), a thicker chin bar at the bottom and narrow cheek pads at the sides, all soft-edged, with
// a faint tint and a slow sheen on the visor itself.
uniform float aspect = 1.777;
uniform float speed = 0.0;         // 0..1, the edge darkens a touch with speed (tunnel vision)

float sdRoundBox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5, 0.47)) * vec2(aspect, 1.0);
	// Visor opening: a wide rounded window, slightly narrower at the bottom (chin bar).
	float w = aspect * 0.5 * (0.985 - 0.06 * smoothstep(-0.1, 0.5, p.y));
	float d = sdRoundBox(p, vec2(w, 0.47), 0.22);
	float edge = smoothstep(-0.05, 0.03, d);
	vec3 pad = vec3(0.015, 0.016, 0.018) + 0.03 * smoothstep(0.08, 0.0, d);
	// Visor tint + sheen inside the opening.
	float sheen = 0.035 * smoothstep(0.35, 0.0, abs(p.x * 0.6 + p.y + 0.35 - 0.1 * sin(TIME * 0.2)));
	float vign = smoothstep(0.25, -0.12, d) * 0.0;
	float tunnel = smoothstep(-0.28, 0.0, d) * (0.18 + 0.25 * speed);
	vec4 inside = vec4(vec3(0.0), tunnel) + vec4(vec3(1.0), sheen);
	COLOR = mix(inside, vec4(pad, 1.0), edge);
}
