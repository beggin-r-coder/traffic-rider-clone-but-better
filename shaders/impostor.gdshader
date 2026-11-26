shader_type spatial;
render_mode skip_vertex_transform, cull_disabled;
// Billboard impostors baked from Poly Haven plants (8 views per plant, shared atlas).
// One MultiMesh per road chunk; INSTANCE_CUSTOM = (row_y, row_h, tint, wind phase) in atlas UV units.
uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
uniform vec2 atlas_px = vec2(2048.0, 4096.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind = 1.0;

varying vec2 v_uv;
varying float v_shade;

void vertex() {
	vec3 ip = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[0].xyz;
	vec3 az = MODEL_MATRIX[2].xyz;
	float sx = length(ax);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - ip;
	vec3 tc = normalize(vec3(to_cam.x, 0.0, to_cam.z) + vec3(1e-4, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), tc));
	float h = VERTEX.y;
	vec3 wp = ip + right * VERTEX.x * sx + vec3(0.0, 1.0, 0.0) * h * sy;
	// Gentle wind sway, more at the top.
	float ph = INSTANCE_CUSTOM.w * 6.2831853;
	wp.xz += vec2(sin(TIME * 1.1 + ph), cos(TIME * 0.8 + ph * 1.3)) * (0.025 * h * h * sy) * wind;
	// Pick the baked view closest to the current viewing direction.
	float a = atan(dot(tc, normalize(ax)), dot(tc, normalize(az)));
	float f = mod(round(a / (6.2831853 / frames)) + frames, frames);
	v_uv = vec2((f + UV.x) / frames, INSTANCE_CUSTOM.x + UV.y * INSTANCE_CUSTOM.y);
	v_shade = INSTANCE_CUSTOM.z;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(tc, 0.0)).xyz);
	TANGENT = normalize((VIEW_MATRIX * vec4(right, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec4 c = texture(albedo_atlas, v_uv);
	// Keep thin foliage from vanishing in lower mip levels.
	vec2 px = v_uv * atlas_px;
	float lod = max(log2(max(length(dFdx(px)), length(dFdy(px)))), 0.0);
	ALPHA = c.a * (1.0 + lod * 0.4);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = c.rgb * tint * mix(0.82, 1.18, v_shade);
	NORMAL_MAP = mix(texture(normal_atlas, v_uv).rgb, vec3(0.5, 0.5, 1.0), 0.25);
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.22, 0.26, 0.1);
}
