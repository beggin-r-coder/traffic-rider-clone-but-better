shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;
// Rain streaks. Each particle is stretched along the rain's velocity *relative to the camera*,
// so at speed the streaks rake towards you like real motion-blurred rain.
uniform vec3 rain_velocity = vec3(0.0, -9.0, 0.0);
uniform vec3 viewer_velocity = vec3(0.0);
uniform float exposure = 0.03;      // "shutter" time for the streak length
uniform float width = 0.008;
uniform vec4 tint : source_color = vec4(0.7, 0.75, 0.8, 0.22);

varying float v_fade;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 rel = rain_velocity - viewer_velocity;
	float len = clamp(length(rel) * exposure, 0.25, 2.2);
	vec3 axis = normalize(rel);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - o);
	vec3 right = normalize(cross(axis, to_cam));
	vec3 wp = o + right * VERTEX.x * width * 2.0 + axis * VERTEX.y * len;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	float d = length(CAMERA_POSITION_WORLD - o);
	v_fade = smoothstep(0.4, 1.5, d) * (1.0 - smoothstep(18.0, 30.0, d));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * 3.14159);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * across * across * along * v_fade;
}
