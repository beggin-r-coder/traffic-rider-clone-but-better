shader_type spatial;
render_mode cull_disabled;
// Far forest band behind the tree rows: two staggered layers of baked fir impostor frames
// over a dark forest-interior base, so gaps never show open land.
// UV.x = distance along the road (m), UV.y = 0 top .. 1 bottom.
uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 row_y = vec3(0.0, 0.1428571, 0.2857143);
uniform float row_h = 0.1428571;
uniform float frames = 16.0;
uniform float tile = 5.5;
uniform vec3 interior : source_color = vec3(0.05, 0.075, 0.035);

float hash(float n) { return fract(sin(n) * 43758.5453); }

vec4 layer(float s, float v, float off) {
	float x = s / tile + off;
	float cell = floor(x);
	float u = fract(x);
	float h = hash(cell + off * 17.0);
	int r = int(floor(h * 3.0));
	float ry = r == 0 ? row_y.x : (r == 1 ? row_y.y : row_y.z);
	float frame = floor(hash(cell * 1.7 + 3.0) * frames);
	// Vary tree heights: squeeze v so some firs are shorter.
	float hs = mix(0.78, 1.0, hash(cell + 9.0));
	float vv = 1.0 - (1.0 - v) / hs;
	if (vv < 0.0) return vec4(0.0);
	return texture(albedo_atlas, vec2((frame + u) / frames, ry + vv * row_h));
}

void fragment() {
	vec4 a = layer(UV.x, UV.y, 0.0);
	vec4 b = layer(UV.x, UV.y, 0.5);
	vec4 c = a.a > 0.5 ? a : b;
	vec3 col;
	if (c.a > 0.5) {
		col = c.rgb * 0.55;
	} else if (UV.y > 0.55) {
		col = interior;
	} else {
		discard;
	}
	ALBEDO = col * vec3(0.85, 0.97, 0.88);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
