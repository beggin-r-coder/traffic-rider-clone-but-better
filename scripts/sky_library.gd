extends RefCounted
class_name SkyLibrary
## Cloudy sky panoramas (Screaming Brain Studios, CC0) grouped by time of day,
## plus image analysis so the sun light, fog and ambient colours match the picture.

const SETS := {
	0: [4, 5, 6, 8, 16],          # Day
	1: [2, 3, 7, 17, 21, 22],     # Sunset / golden hour
	2: [11, 12, 25],              # Night / dusk
	3: [1, 9, 10, 18, 20, 24],    # Cloudy
}

static func path(n: int) -> String:
	return "res://assets/skies/sky_%02d.png" % n

static func pick(tod: int, rng_seed: int) -> int:
	var list: Array = SETS.get(tod, SETS[0])
	return int(list[absi(rng_seed) % list.size()])

## Direction (world, -Z forward) of panorama pixel (u, v) for a given rotation.
static func uv_to_dir(u: float, v: float, rotation: float) -> Vector3:
	var az := (u - 0.5) * TAU + rotation
	var r := sin(v * PI)
	return Vector3(sin(az) * r, cos(v * PI), -cos(az) * r).normalized()

## Returns {sun_u, sun_v, sun_color, horizon, zenith, brightness}.
static func analyze(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img = img.duplicate()
	img.resize(256, 128, Image.INTERPOLATE_BILINEAR)
	var best := -1.0
	var bx := 0
	var by := 0
	for y in range(1, 63):            # upper hemisphere only
		for x in 256:
			var c := img.get_pixel(x, y)
			var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			if l > best:
				best = l
				bx = x
				by = y
	# Centroid of the clipped sun disc around the maximum (wrapping horizontally).
	var sx := 0.0
	var sy := 0.0
	var sw := 0.0
	var glow := Color(0, 0, 0)
	var gw := 0.0
	for dy in range(-10, 11):
		for dx in range(-14, 15):
			var y := clampi(by + dy, 0, 127)
			var x := posmod(bx + dx, 256)
			var c := img.get_pixel(x, y)
			var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			if l >= best - 0.03:
				sx += bx + dx
				sy += y
				sw += 1.0
			elif l > best * 0.55:
				glow += c
				gw += 1.0
	var horizon := Color(0, 0, 0)
	var zenith := Color(0, 0, 0)
	var avg := 0.0
	for x in 256:
		horizon += img.get_pixel(x, 61)
		zenith += img.get_pixel(x, 12)
	horizon /= 256.0
	zenith /= 256.0
	for y in range(0, 64, 4):
		for x in range(0, 256, 4):
			var c := img.get_pixel(x, y)
			avg += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	avg /= 64.0 * 16.0
	var sun_col := glow / maxf(gw, 1.0) if gw > 0.0 else Color(1, 1, 1)
	return {
		"sun_u": (sx / maxf(sw, 1.0)) / 256.0,
		"sun_v": (sy / maxf(sw, 1.0) + 0.5) / 128.0,
		"sun_color": sun_col,
		"horizon": horizon,
		"zenith": zenith,
		"brightness": avg,
	}
