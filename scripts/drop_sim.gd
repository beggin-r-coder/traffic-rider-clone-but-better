extends Node2D
class_name DropSim
## Particle simulation of raindrops on a surface (visor glass, bike bodywork), rendered into a
## SubViewport as a "water map": RG = drop surface normal, B = water thickness, A = coverage.
## Shaders sample the map to refract / reflect through the drops.
##
## Behaviour (the classic rain-on-glass model):
##  - rain lands as small beads of random size
##  - touching drops merge (area is conserved), so drops grow
##  - small drops cling; once a drop is heavy enough it starts to run, faster the heavier it is,
##    with stick-slip pauses and a little sideways wander
##  - running drops shed a trail of tiny droplets, lose a little water doing it, and sweep up the
##    beads in their path
##  - "flow" (gravity + wind, in px/s^2 direction*strength) can change at runtime: down when still,
##    up/outwards across a visor or backwards along a bike at speed

var size := Vector2(640, 360)
var max_drops := 700
var spawn_rate := 120.0            # new beads per second
var r_min := 1.0                   # bead radius range (px)
var r_max := 4.5
var run_radius := 5.0              # drops bigger than this start running
var flow := Vector2(0, 60)         # acceleration for running drops (px/s^2)
var radial_wind := 0.0             # visor: extra push away from the screen centre (px/s^2)
var trail_spacing := 7.0           # px between shed droplets
var max_speed := 900.0
var drop_tex: Texture2D

# drop arrays (structure of arrays for speed)
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var pr := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var trail := PackedFloat32Array()    # distance since last shed droplet
var stuck := PackedFloat32Array()    # stick-slip timer
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	if drop_tex == null:
		drop_tex = make_drop_texture()

static func make_drop_texture(res: int = 64) -> ImageTexture:
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for y in res:
		for x in res:
			var u := (x + 0.5) / res * 2.0 - 1.0
			var v := (y + 0.5) / res * 2.0 - 1.0
			var r2 := u * u + v * v
			if r2 >= 1.0:
				img.set_pixel(x, y, Color(0.5, 0.5, 0.0, 0.0))
				continue
			var h := sqrt(1.0 - r2)                     # spherical cap height
			var a := clampf((1.0 - sqrt(r2)) * 6.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(u * 0.5 + 0.5, v * 0.5 + 0.5, h, a))
	return ImageTexture.create_from_image(img)

func count() -> int:
	return px.size()

func _add(x: float, y: float, r: float, ax := 0.0, ay := 0.0) -> void:
	if px.size() >= max_drops:
		# Full: the new drop takes the place of a tiny (stationary) droplet, as if it evaporated.
		for attempt in 10:
			var k := rng.randi() % px.size()
			if pr[k] < r_min * 1.7 and absf(vx[k]) + absf(vy[k]) < 1.0:
				px[k] = x; py[k] = y; pr[k] = r; vx[k] = ax; vy[k] = ay
				trail[k] = 0.0; stuck[k] = rng.randf() * 0.5
				return
		return
	px.append(x); py.append(y); pr.append(r)
	vx.append(ax); vy.append(ay)
	trail.append(0.0); stuck.append(rng.randf() * 0.5)

func _remove(i: int) -> void:
	var last := px.size() - 1
	px[i] = px[last]; py[i] = py[last]; pr[i] = pr[last]
	vx[i] = vx[last]; vy[i] = vy[last]; trail[i] = trail[last]; stuck[i] = stuck[last]
	px.resize(last); py.resize(last); pr.resize(last)
	vx.resize(last); vy.resize(last); trail.resize(last); stuck.resize(last)

func step(dt: float, rain_amount: float = 1.0) -> void:
	dt = minf(dt, 0.05)
	# --- new rain ---
	var n_new := spawn_rate * rain_amount * dt
	var whole := int(n_new)
	if rng.randf() < n_new - whole:
		whole += 1
	for k in whole:
		var r := lerpf(r_min, r_max, pow(rng.randf(), 2.2))
		_add(rng.randf() * size.x, rng.randf() * size.y, r)
	var centre := size * 0.5
	var flow_len := flow.length()
	# --- move ---
	var i := 0
	while i < px.size():
		var r := pr[i]
		var moving := r > run_radius or absf(vx[i]) + absf(vy[i]) > 5.0
		if moving:
			# Heavier drops accelerate harder; wind overcomes surface tension even for mid drops.
			var mass_f := clampf((r - run_radius * 0.7) / run_radius, 0.15, 2.0)
			var ax := flow.x * mass_f
			var ay := flow.y * mass_f
			if radial_wind != 0.0:
				var d := Vector2(px[i], py[i]) - centre
				var dl := maxf(d.length(), 1.0)
				ax += d.x / dl * radial_wind * mass_f
				ay += d.y / dl * radial_wind * mass_f
			# Stick-slip: small/medium drops occasionally catch on the surface.
			stuck[i] -= dt
			if stuck[i] < 0.0:
				if rng.randf() < 0.35 and r < run_radius * 1.6 and flow_len < 400.0:
					vx[i] *= 0.1
					vy[i] *= 0.1
					stuck[i] = rng.randf_range(0.15, 0.6)
				else:
					stuck[i] = rng.randf_range(0.1, 0.4)
			vx[i] += ax * dt + rng.randf_range(-1.0, 1.0) * 30.0 * dt
			vy[i] += ay * dt
			# Friction / drag.
			var damp := exp(-1.8 * dt)
			vx[i] *= damp
			vy[i] *= damp
			var sp := sqrt(vx[i] * vx[i] + vy[i] * vy[i])
			if sp > max_speed:
				vx[i] *= max_speed / sp
				vy[i] *= max_speed / sp
				sp = max_speed
			px[i] += vx[i] * dt
			py[i] += vy[i] * dt
			# Shed a trail of tiny droplets.
			trail[i] += sp * dt
			if trail[i] > trail_spacing and r > r_min * 1.5:
				trail[i] = 0.0
				var tr := r * rng.randf_range(0.18, 0.35)
				if rng.randf() < 0.75:
					var bx := px[i] - vx[i] / maxf(sp, 1.0) * r * 1.4
					var by := py[i] - vy[i] / maxf(sp, 1.0) * r * 1.4
					_add(bx + rng.randf_range(-0.5, 0.5), by, tr)
					pr[i] = sqrt(maxf(r * r - tr * tr, r_min * r_min))
			# Slowed-down small drops stop and become beads again.
			if sp < 4.0 and pr[i] < run_radius:
				vx[i] = 0.0
				vy[i] = 0.0
		# Off the surface: remove.
		if px[i] < -10.0 or py[i] < -10.0 or px[i] > size.x + 10.0 or py[i] > size.y + 10.0:
			_remove(i)
			continue
		i += 1
	# Merging every other frame is plenty (drops move a few px per frame).
	_frame += 1
	if _frame % 2 == 0:
		_merge()
	queue_redraw()

## Merge overlapping drops (uniform grid via counting sort; flat packed arrays, no dictionaries).
## The bigger drop absorbs the smaller; area (volume) and momentum are conserved.
var _cell_start := PackedInt32Array()
var _cell_items := PackedInt32Array()
var _cell_of := PackedInt32Array()
var _frame := 0

func _merge() -> void:
	var n := px.size()
	if n < 2:
		return
	var cell := maxf(r_max * 2.6 * 2.0, 10.0)
	var gw := int(size.x / cell) + 3
	var gh := int(size.y / cell) + 3
	var nc := gw * gh
	_cell_start.resize(nc + 1)
	_cell_start.fill(0)
	_cell_of.resize(n)
	_cell_items.resize(n)
	for i in n:
		var cx := clampi(int(px[i] / cell) + 1, 0, gw - 1)
		var cy := clampi(int(py[i] / cell) + 1, 0, gh - 1)
		var c := cy * gw + cx
		_cell_of[i] = c
		_cell_start[c + 1] += 1
	for c in nc:
		_cell_start[c + 1] += _cell_start[c]
	var fill := _cell_start.duplicate()
	for i in n:
		var c := _cell_of[i]
		_cell_items[fill[c]] = i
		fill[c] += 1
	var dead := PackedByteArray()
	dead.resize(n)
	for i in n:
		if dead[i]:
			continue
		var c0 := _cell_of[i]
		var cx := c0 % gw
		var cy := c0 / gw
		for oy in range(maxi(cy - 1, 0), mini(cy + 2, gh)):
			for ox in range(maxi(cx - 1, 0), mini(cx + 2, gw)):
				var c := oy * gw + ox
				for k in range(_cell_start[c], _cell_start[c + 1]):
					var j := _cell_items[k]
					if j <= i or dead[j]:
						continue
					var dx := px[j] - px[i]
					var dy := py[j] - py[i]
					var rr := (pr[i] + pr[j]) * 0.8
					if dx * dx + dy * dy >= rr * rr:
						continue
					var a := i
					var b := j
					if pr[b] > pr[a]:
						a = j
						b = i
					var ra2 := pr[a] * pr[a]
					var rb2 := pr[b] * pr[b]
					var na := ra2 + rb2
					vx[a] = (vx[a] * ra2 + vx[b] * rb2) / na
					vy[a] = (vy[a] * ra2 + vy[b] * rb2) / na
					px[a] += (px[b] - px[a]) * rb2 / na * 0.5
					py[a] += (py[b] - py[a]) * rb2 / na * 0.5
					pr[a] = minf(sqrt(na), r_max * 2.6)
					dead[b] = 1
					if b == i:
						break
				if dead[i]:
					break
			if dead[i]:
				break
	for i in range(n - 1, -1, -1):
		if dead[i]:
			_remove(i)

func _draw() -> void:
	var tex := drop_tex
	for i in px.size():
		var r := pr[i]
		var sp2 := vx[i] * vx[i] + vy[i] * vy[i]
		if sp2 > 400.0:
			# Running drop: teardrop stretched along its motion.
			var ang := atan2(vy[i], vx[i]) - PI * 0.5
			var stretch := clampf(1.0 + sqrt(sp2) / 400.0, 1.0, 1.9)
			draw_set_transform(Vector2(px[i], py[i]), ang, Vector2(1.0 / sqrt(stretch), stretch))
			draw_texture_rect(tex, Rect2(-r, -r, r * 2.0, r * 2.0), false)
		else:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_texture_rect(tex, Rect2(px[i] - r, py[i] - r, r * 2.0, r * 2.0), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Convenience: wrap a DropSim in its own transparent SubViewport. Returns [viewport, sim].
static func create(map_size: Vector2i) -> Array:
	var vp := SubViewport.new()
	vp.size = map_size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var sim := DropSim.new()
	sim.size = Vector2(map_size)
	vp.add_child(sim)
	return [vp, sim]
