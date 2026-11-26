// Depth impostors baked from Poly Haven trees (see scripts/tools/impostor_baker.gd).
// Each plant: N views around it; colour atlas + (normal.xyz, depth) atlas.
// Per pixel: blends the two nearest views, parallax-shifts each by its baked depth,
// places lighting/shadows at the true leaf depth, and (DEPTH_WRITE) writes real depth so
// trees intersect each other and the ground properly.
// INSTANCE_CUSTOM = (row_y, row_h, kind + random, depth_range / world_w).
uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
uniform float frames = 16.0;
uniform vec2 atlas_px = vec2(4096.0, 3584.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind = 1.0;

varying vec2 v_uv0;
varying vec2 v_uv1;
varying vec4 v_frame;      // x: blend, y: sin(delta0), z: sin(delta1), w: depth_range/world_w
varying vec3 v_misc;       // x: random, y: kind, z: billboard width (world)
varying vec2 v_bounds;     // frame 0 u-start, frame 1 u-start

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
	float ph = fract(ip.x * 0.137 + ip.z * 0.171) * 6.2831853;
	wp.xz += vec2(sin(TIME * 1.1 + ph), cos(TIME * 0.8 + ph * 1.3)) * (0.02 * h * h * sy) * wind;
	// View angle around the plant -> two nearest baked views and the blend between them.
	float a = atan(dot(tc, normalize(ax)), dot(tc, normalize(az)));
	float stp = 6.2831853 / frames;
	float fa = a / stp;
	float f0 = floor(fa);
	float t = fa - f0;
	float k0 = mod(f0 + frames, frames);
	float k1 = mod(f0 + 1.0 + frames, frames);
	v_uv0 = vec2((k0 + UV.x) / frames, INSTANCE_CUSTOM.x + UV.y * INSTANCE_CUSTOM.y);
	v_uv1 = vec2((k1 + UV.x) / frames, v_uv0.y);
	v_bounds = vec2(k0 / frames, k1 / frames);
	v_frame = vec4(t, sin(t * stp), sin((t - 1.0) * stp), INSTANCE_CUSTOM.w);
	v_misc = vec3(fract(INSTANCE_CUSTOM.z), floor(INSTANCE_CUSTOM.z), sx);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(tc, 0.0)).xyz);
	TANGENT = normalize((VIEW_MATRIX * vec4(right, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

// Parallax-corrected lookup into one baked view.
void sample_view(vec2 uv, float start, float sin_d, float drange, out vec4 col, out vec4 nd) {
	float d = texture(normal_atlas, uv).a;
	float lo = start + 0.5 / atlas_px.x;
	float hi = start + 1.0 / frames - 0.5 / atlas_px.x;
	vec2 p = vec2(clamp(uv.x + (0.5 - d) * drange * sin_d / frames, lo, hi), uv.y);
	col = texture(albedo_atlas, p);
	nd = texture(normal_atlas, p);
}

void fragment() {
	vec4 c0; vec4 n0; vec4 c1; vec4 n1;
	sample_view(v_uv0, v_bounds.x, v_frame.y, v_frame.w, c0, n0);
	sample_view(v_uv1, v_bounds.y, v_frame.z, v_frame.w, c1, n1);
	float t = v_frame.x;
	float w0 = c0.a * (1.0 - t);
	float w1 = c1.a * t;
	float ws = max(w0 + w1, 1e-4);
	vec3 rgb = (c0.rgb * w0 + c1.rgb * w1) / ws;
	vec4 nd = (n0 * w0 + n1 * w1) / ws;
	float a = c0.a * (1.0 - t) + c1.a * t;
	vec2 px = v_uv0 * atlas_px;
	float lod = max(log2(max(length(dFdx(px)), length(dFdy(px)))), 0.0);
	ALPHA = a * (1.0 + lod * 0.4);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Species / per-tree colour variation: conifers cooler and darker, broadleaves warmer.
	vec3 kind_tint = v_misc.y < 0.5 ? vec3(0.82, 0.97, 0.86) : vec3(1.02, 1.05, 0.84);
	float r = v_misc.x;
	vec3 var_tint = mix(vec3(0.85, 0.9, 0.8), vec3(1.12, 1.1, 0.95), r);
	ALBEDO = rgb * tint * kind_tint * var_tint;
	NORMAL_MAP = mix(nd.rgb, vec3(0.5, 0.5, 1.0), 0.12);
	ROUGHNESS = 0.72;
	SPECULAR = 0.35;
	BACKLIGHT = vec3(0.3, 0.36, 0.12);
	AO = mix(1.0, 0.55, nd.a);
	AO_LIGHT_AFFECT = 0.35;
	// Put the pixel at its real depth for lighting, shadow lookups and (optionally) the z-buffer.
	float z_w = (0.5 - nd.a) * v_frame.w * v_misc.z;
	vec3 p = VERTEX - normalize(VERTEX) * z_w;
	LIGHT_VERTEX = p;
#ifdef DEPTH_WRITE
	vec4 clip = PROJECTION_MATRIX * vec4(p, 1.0);
	DEPTH = clip.z / clip.w;
#endif
}
