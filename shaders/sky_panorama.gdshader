shader_type sky;
// Equirectangular cloudy-sky panorama with rotation, exposure, HDR sun boost,
// a clean below-horizon fill (the source images mirror the sky) and optional stars.
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float rotation = 0.0;         // radians, added to the panorama azimuth
uniform float exposure = 1.0;
uniform float sun_boost = 2.5;        // lifts clipped highlights above 1.0 so glow picks them up
uniform vec3 ground_color : source_color = vec3(0.15, 0.15, 0.14);
uniform float star_amount = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 sample_pano(vec3 d) {
	float u = atan(d.x, -d.z) / 6.2831853 + 0.5 - rotation / 6.2831853;
	float v = acos(clamp(d.y, -1.0, 1.0)) / 3.14159265;
	return texture(panorama, vec2(u, v)).rgb;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col;
	if (d.y >= 0.0) {
		col = sample_pano(d);
	} else {
		// Below the horizon: take the horizon colour and fade to the ground colour.
		vec3 h = sample_pano(normalize(vec3(d.x, 0.002, d.z)));
		col = mix(h, ground_color, smoothstep(0.0, 0.25, -d.y));
	}
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col *= exposure;
	col += col * smoothstep(0.82, 1.0, lum) * sun_boost * exposure;
	if (star_amount > 0.0 && d.y > 0.05) {
		vec3 g = d * 170.0;
		vec3 cell = floor(g);
		float r = hash(cell);
		if (r > 0.986) {
			vec3 c = cell + vec3(hash(cell + 1.3), hash(cell + 2.7), hash(cell + 5.1));
			float star = smoothstep(0.35, 0.0, length(g - c)) * (r - 0.986) * 70.0;
			// Only show stars through the darker (clear) parts of the sky.
			col += vec3(0.9, 0.95, 1.0) * star * star_amount * (1.0 - smoothstep(0.15, 0.45, lum)) * smoothstep(0.05, 0.25, d.y);
		}
	}
	COLOR = col;
}
