shader_type canvas_item;
// Radial speed blur: samples the frame along the line to the vanishing point, more towards the
// screen edges and with speed; the centre (where you look) stays sharp. Light chromatic fringe.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;          // 0..1
uniform vec2 focus = vec2(0.5, 0.42);
uniform int samples = 6;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - focus;
	float r = length(dir * vec2(1.6, 1.0));
	float k = amount * smoothstep(0.18, 0.75, r) * 0.045;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < samples; i++) {
		float t = float(i) / float(samples - 1);
		vec2 o = dir * k * t;
		float w = 1.0 - t * 0.5;
		acc.r += texture(screen_tex, uv - o * 1.15).r * w;
		acc.g += texture(screen_tex, uv - o).g * w;
		acc.b += texture(screen_tex, uv - o * 0.85).b * w;
		wsum += w;
	}
	COLOR = vec4(acc / wsum, smoothstep(0.0, 0.05, k));
}
