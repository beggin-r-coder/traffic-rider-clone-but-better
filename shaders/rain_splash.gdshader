shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Splash crown / mist puff: soft radial blob that grows and fades over the particle's life.
uniform vec4 tint : source_color = vec4(0.8, 0.84, 0.88, 0.5);
varying float v_life;
void vertex() {
	v_life = INSTANCE_CUSTOM.y;   // 0..1 age
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float blob = smoothstep(1.0, 0.2, r);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * blob * (1.0 - v_life) * COLOR.a;
}
