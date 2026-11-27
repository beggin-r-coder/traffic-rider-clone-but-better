shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform;
// Camera-facing light glow: bright core + soft halo, like a lamp seen through wet, misty air.
// Works on single meshes and MultiMeshes (per-instance COLOR tints the light).
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.3, 1.0);
uniform float intensity = 3.0;
uniform float size = 1.0;
uniform float halo = 0.35;     // strength of the wide misty halo
uniform bool per_instance = false;   // MultiMesh: colour comes from INSTANCE_CUSTOM.rgb

varying vec3 v_col;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 cr = INV_VIEW_MATRIX[0].xyz;
	vec3 cu = INV_VIEW_MATRIX[1].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - o);
	vec3 wp = o + (cr * VERTEX.x + cu * VERTEX.y) * size * sc * 2.0 + to_cam * 0.35;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	v_col = per_instance ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	// Fade out flares right next to the camera (no screen-filling blobs from passing cars).
	float d = length(CAMERA_POSITION_WORLD - o);
	v_col *= smoothstep(2.0, 7.0, d);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	float core = exp(-r2 * 90.0) * 2.0;
	float glow = exp(-r2 * 22.0) * 0.45;
	float mist = exp(-r2 * 4.0) * halo;
	ALBEDO = color.rgb * v_col * intensity * (core + glow + mist) * (1.0 - smoothstep(0.85, 1.0, sqrt(r2)));
}
