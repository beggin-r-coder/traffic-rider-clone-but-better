shader_type canvas_item;
// Visor rain: renders the simulated water map (scripts/drop_sim.gd) as real water on glass.
// Each drop acts as a lens: it shows an inverted, magnified, slightly blurred view of the scene
// behind it, with a dark refractive rim and a bright specular glint. Trails of tiny droplets come
// straight from the simulation.
uniform sampler2D water : filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float refraction = 0.055;
uniform float aspect = 1.777;

void fragment() {
	vec4 w = texture(water, SCREEN_UV);
	if (w.a < 0.03) {
		discard;
	}
	vec3 d = w.rgb / w.a;                        // un-premultiply
	vec2 n = d.xy * 2.0 - 1.0;                   // drop surface slope (screen space, y down)
	float th = clamp(d.z, 0.0, 1.0);             // water thickness (cap height)
	// Lens: a convex drop flips and magnifies what's behind it.
	vec2 off = -n * refraction * vec2(1.0 / aspect, 1.0) * (0.35 + 0.65 * th);
	vec3 c = textureLod(screen_tex, SCREEN_UV + off, 1.0).rgb;
	// Thin edges bend light away (dark rim); the body of the drop is slightly brighter.
	float edge = 1.0 - th;
	c *= mix(1.12, 0.35, pow(edge, 2.5));
	// Specular glint from the sky (light from above, slightly left).
	vec3 N = normalize(vec3(n.x, n.y, 0.6 + th));
	vec3 L = normalize(vec3(-0.35, -0.8, 0.5));
	float spec = pow(max(dot(N, L), 0.0), 60.0);
	c += vec3(1.0) * spec * 0.9;
	COLOR = vec4(c, smoothstep(0.03, 0.35, w.a));
}
