extends Node3D
class_name Traffic
## Spawns and drives traffic in road coordinates. Detects crashes and near misses
## against the player.

signal near_miss(clearance: float, oncoming: bool)
## Any car passed at speed within a few metres (for the pass whoosh / keeping a combo alive).
signal passed(clearance: float, rel_speed: float, oncoming: bool)
## A car sounds its horn (cut up by the player, or the player is in an oncoming car's lane).
signal honk(distance: float)

const NEAR_MISS_CLEAR := 1.3      # lateral gap (m) that counts as a near miss
const PASS_CLEAR := 2.8           # lateral gap (m) for an ordinary close pass

const KINDS := ["sedan", "sedan", "sedan", "hatch", "hatch", "suv", "suv", "van", "truck"]

class Car:
	var node: Node3D
	var mesh: MeshInstance3D
	var s := 0.0
	var d := 0.0
	var target_d := 0.0
	var lane := 0
	var speed := 20.0
	var cruise := 20.0
	var dir := 1               # +1 same direction as player, -1 oncoming
	var length := 4.5
	var width := 1.8
	var kind := ""
	var braking := false
	var blink := 0             # -1 left, +1 right
	var blink_t := 0.0
	var lc_timer := 0.0
	var tail_surface := 4
	var min_clear := 99.0
	var tracking := false
	var horn_cd := 0.0
	var glow: Node3D
	var tail_flares: Array[MeshInstance3D] = []
	var braking_shown := false

var road: Road
var cars: Array[Car] = []
var rng := RandomNumberGenerator.new()
var two_way := false
var night := false
var lights_on := false
var _flare_head: ShaderMaterial
var _flare_tail: ShaderMaterial
var _flare_brake: ShaderMaterial
var _flare_quad: QuadMesh
var spawn_enabled := true
var density_mult := 1.0
var _spawn_cd := 0.0
var _glow_mat: StandardMaterial3D
var _glow_tail_mat: StandardMaterial3D
var _glow_mesh: QuadMesh

func setup(r: Road, seed_value: int, is_two_way: bool, is_night: bool) -> void:
	road = r
	rng.seed = seed_value + 17
	two_way = is_two_way
	night = is_night
	CarFactory.set_night(night)
	if night:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_glow_mat.albedo_texture = t
		_glow_mat.albedo_color = Color(1.0, 0.92, 0.75, 0.5)
		_glow_mesh = QuadMesh.new()
		_glow_mesh.size = Vector2(5.0, 11.0)
		_glow_mesh.orientation = PlaneMesh.FACE_Y

## Lane centres (d) for traffic in the given direction.
func lanes_for(dir: int) -> Array:
	var all := [-1.5, -0.5, 0.5, 1.5]
	var out := []
	for l in all:
		var d: float = l * Road.LANE_W
		if not two_way or (dir > 0 and d > 0) or (dir < 0 and d < 0):
			out.append(d)
	return out

func _density(player_s: float) -> float:
	# cars per 100 m of road, ramps with distance travelled
	return (2.0 + clampf(player_s / 6000.0, 0.0, 1.0) * 2.0) * density_mult

func update(dt: float, player_s: float, player_d: float, player_v: float) -> void:
	# --- spawn / despawn ---
	for i in range(cars.size() - 1, -1, -1):
		var c := cars[i]
		if c.s < player_s - 70.0 or c.s > player_s + 760.0:
			c.node.queue_free()
			cars.remove_at(i)
	_spawn_cd -= dt
	if spawn_enabled and _spawn_cd <= 0.0:
		_spawn_cd = 0.15
		var target := int(_density(player_s) * 5.2)
		if cars.size() < target:
			_try_spawn(player_s, player_v)
	# --- drive ---
	for c in cars:
		_drive(c, dt, player_s, player_d, player_v)

func _try_spawn(player_s: float, player_v: float) -> void:
	var dir := 1
	if two_way and rng.randf() < 0.45:
		dir = -1
	var s: float
	if dir > 0:
		if player_v < 15.0 and rng.randf() < 0.3:
			s = player_s - rng.randf_range(55.0, 65.0)
		else:
			s = player_s + rng.randf_range(220.0, 480.0)
	else:
		s = player_s + rng.randf_range(450.0, 740.0)
	var lanes := lanes_for(dir)
	var d: float = lanes[rng.randi() % lanes.size()]
	for o in cars:
		if absf(o.d - d) < 2.0 and absf(o.s - s) < 22.0 + o.length:
			return
	var kind: String = KINDS[rng.randi() % KINDS.size()]
	_spawn(kind, s, d, dir, player_s)

func _spawn(kind: String, s: float, d: float, dir: int, player_s: float = 0.0) -> Car:
	var spec := CarFactory.get_vehicle(kind)
	var c := Car.new()
	c.kind = kind
	c.s = s
	c.d = d
	c.target_d = d
	c.dir = dir
	c.length = spec["length"]
	c.width = spec["width"]
	c.tail_surface = spec["tail_surface"]
	# Slower in the outer (right) lanes, faster near the centre.
	var lane_factor := 1.0 - absf(d) / (Road.LANE_W * 2.0) * 0.25
	var base := rng.randf_range(19.0, 28.0) * lane_factor
	if kind == "truck":
		base *= 0.82
	c.cruise = base
	c.speed = base
	c.lc_timer = rng.randf_range(3.0, 12.0)
	c.node = Node3D.new()
	c.mesh = MeshInstance3D.new()
	c.mesh.mesh = spec["mesh"]
	var paint: StandardMaterial3D = CarFactory.paint_mats[rng.randi() % CarFactory.paint_mats.size()]
	if kind == "truck":
		paint = CarFactory.paint_mats[[0, 4, 7, 8, 12][rng.randi() % 5]]
	c.mesh.set_surface_override_material(0, paint)
	c.node.add_child(c.mesh)
	if lights_on:
		_add_light_flares(c, kind)
	if false and night and _glow_mesh:   # flat headlight 'beam' decals removed (looked like rectangles)
		var gl := MeshInstance3D.new()
		gl.mesh = _glow_mesh
		gl.material_override = _glow_mat
		gl.position = Vector3(0, 0.04, -c.length * 0.5 - 5.5)
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(gl)
		c.glow = gl
	add_child(c.node)
	cars.append(c)
	_place(c)
	return c

func _flare_mat(col: Color, inten: float, size: float, halo: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/light_flare.gdshader")
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("intensity", inten)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("halo", halo)
	return m

func _add_light_flares(c: Car, kind: String) -> void:
	if _flare_quad == null:
		_flare_quad = QuadMesh.new()
		_flare_quad.size = Vector2(1, 1)
		_flare_head = _flare_mat(Color(1.0, 0.94, 0.84), 1.5, 0.32, 0.1)
		_flare_tail = _flare_mat(Color(1.0, 0.1, 0.05), 0.9, 0.2, 0.08)
		_flare_brake = _flare_mat(Color(1.0, 0.08, 0.04), 1.8, 0.3, 0.12)
	var truck := kind == "truck"
	var hx := c.width * 0.5 - (0.35 if truck else 0.28)
	var hy := 0.85 if truck else 0.7
	var ty := 0.95 if truck else 0.82
	for side: float in [-1.0, 1.0]:
		var h := MeshInstance3D.new()
		h.mesh = _flare_quad
		h.material_override = _flare_head
		h.position = Vector3(side * hx, hy, -c.length * 0.5 - 0.05)
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(h)
		var t := MeshInstance3D.new()
		t.mesh = _flare_quad
		t.material_override = _flare_tail
		t.position = Vector3(side * (c.width * 0.5 - 0.2), ty, c.length * 0.5 + 0.05)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(t)
		c.tail_flares.append(t)

func _leader_gap(c: Car, player_s: float, player_d: float, player_v: float) -> Array:
	# Returns [gap, leader_speed] for the nearest vehicle ahead in c's lane.
	var best_gap := 1e9
	var best_v := c.cruise
	for o in cars:
		if o == c or o.dir != c.dir:
			continue
		if absf(o.d - c.d) > 2.2 and absf(o.target_d - c.d) > 2.2:
			continue
		var ahead := (o.s - c.s) * c.dir
		if ahead <= 0.0:
			continue
		var gap := ahead - (o.length + c.length) * 0.5
		if gap < best_gap:
			best_gap = gap
			best_v = o.speed
	# The player counts as a leader for traffic behind them.
	if c.dir > 0 and absf(player_d - c.d) < 1.8:
		var ahead_p := player_s - c.s
		if ahead_p > 0.0:
			var gap_p := ahead_p - (c.length * 0.5 + 1.1)
			if gap_p < best_gap:
				best_gap = gap_p
				best_v = player_v
	return [best_gap, best_v]

func _lane_free(c: Car, d: float, player_s: float, player_d: float) -> bool:
	for o in cars:
		if o == c:
			continue
		if absf(o.d - d) < 2.0 or absf(o.target_d - d) < 2.0:
			if absf(o.s - c.s) < (o.length + c.length) * 0.5 + 14.0:
				return false
	if absf(player_d - d) < 2.2 and absf(player_s - c.s) < 30.0:
		return false
	return true

func _drive(c: Car, dt: float, player_s: float, player_d: float, player_v: float) -> void:
	var lg := _leader_gap(c, player_s, player_d, player_v)
	var gap: float = lg[0]
	var lv: float = lg[1]
	var safe := 6.0 + c.speed * 1.1
	var target_v := c.cruise
	if gap < safe:
		target_v = minf(c.cruise, lv - (safe - gap) * 0.25)
	var acc := clampf((target_v - c.speed) * 1.2, -7.0, 2.2)
	c.braking = acc < -1.0
	c.speed = maxf(0.0, c.speed + acc * dt)
	c.s += c.speed * c.dir * dt
	# --- lane changes ---
	c.lc_timer -= dt
	if c.lc_timer <= 0.0 and absf(c.target_d - c.d) < 0.05:
		c.lc_timer = rng.randf_range(4.0, 14.0)
		var lanes := lanes_for(c.dir)
		var options := []
		for l in lanes:
			if absf(l - c.d) > 2.0 and absf(l - c.d) < 4.5:
				options.append(l)
		# Prefer changing lanes when stuck behind someone slow.
		if not options.is_empty() and (gap < safe * 1.5 or rng.randf() < 0.35):
			var nd: float = options[rng.randi() % options.size()]
			if _lane_free(c, nd, player_s, player_d):
				c.target_d = nd
				c.blink = 1 if (nd - c.d) * c.dir > 0 else -1
				c.blink_t = 1.3
	if c.blink_t > 0.0:
		c.blink_t -= dt
	elif absf(c.target_d - c.d) > 0.01:
		c.d = move_toward(c.d, c.target_d, 1.25 * dt)
		if absf(c.target_d - c.d) <= 0.01:
			c.d = c.target_d
			c.blink = 0
	if c.horn_cd > 0.0:
		c.horn_cd -= dt
	elif player_v > 8.0:
		var rel_s := player_s - c.s
		var rel_d := absf(player_d - c.d)
		if c.dir > 0 and rel_s > 0.0 and rel_s < 9.0 + c.length * 0.5 and rel_d < 1.6 and c.speed > player_v + 1.5:
			# Player cut in just ahead and is slower: lean on the horn.
			honk.emit(rel_s)
			c.horn_cd = 4.0
		elif c.dir < 0 and -rel_s > 15.0 and -rel_s < 110.0 and rel_d < 1.5:
			# Player riding head-on in this car's lane.
			honk.emit(-rel_s)
			c.horn_cd = 5.0
	_place(c)

func _place(c: Car) -> void:
	var t := road.xform(c.s, c.d)
	var yaw := 0.0
	if c.blink_t <= 0.0 and absf(c.target_d - c.d) > 0.01:
		yaw = -signf(c.target_d - c.d) * 0.06 * c.dir
	if c.dir < 0:
		yaw += PI
	t.basis = t.basis * Basis(Vector3.UP, yaw)
	c.node.transform = t
	var tail_mat := CarFactory.mat_tail_brake if c.braking else CarFactory.mat_tail
	c.mesh.set_surface_override_material(c.tail_surface, tail_mat)
	if c.braking != c.braking_shown and not c.tail_flares.is_empty():
		c.braking_shown = c.braking
		for f in c.tail_flares:
			f.material_override = _flare_brake if c.braking else _flare_tail
	# Indicators: flash the amber surface via visibility trick (cheap): scale emission on a per-car basis is
	# costly, so blink by toggling a tiny override.
	if c.blink != 0:
		var on := fmod(Time.get_ticks_msec() / 1000.0, 0.7) < 0.35
		c.mesh.set_surface_override_material(5, CarFactory.mat_head if on else null)
	else:
		c.mesh.set_surface_override_material(5, null)

## Returns the car the player overlaps, or null. Also tracks near misses.
func check_player(player_s: float, player_d: float, player_v: float, bike_half_len: float, bike_half_w: float) -> Car:
	var hit: Car = null
	for c in cars:
		var ds := c.s - player_s
		var dd := absf(c.d - player_d)
		var lon := c.length * 0.5 + bike_half_len
		var lat := c.width * 0.5 + bike_half_w
		if absf(ds) < lon:
			if dd < lat:
				hit = c
			c.tracking = true
			c.min_clear = minf(c.min_clear, dd - lat)
		elif c.tracking:
			c.tracking = false
			var rel_v := player_v - c.speed * c.dir
			if c.min_clear < NEAR_MISS_CLEAR and player_v > 22.0:
				near_miss.emit(maxf(c.min_clear, 0.0), c.dir < 0)
				c.horn_cd = 3.0
			elif c.min_clear < PASS_CLEAR and player_v > 15.0 and absf(rel_v) > 4.0:
				passed.emit(c.min_clear, absf(rel_v), c.dir < 0)
			c.min_clear = 99.0
	return hit

## True if any vehicle overlaps the road box [s_from, s_to] x [d - half, d + half].
func occupied(s_from: float, s_to: float, d: float, half: float) -> bool:
	for c in cars:
		if absf(c.d - d) < half + c.width * 0.5:
			if c.s + c.length * 0.5 > s_from and c.s - c.length * 0.5 < s_to:
				return true
	return false

## Distance to the nearest vehicle ahead of the player within a lateral window (for the autopilot).
func gap_ahead(player_s: float, d: float, half_window: float) -> float:
	var best := 1e9
	for c in cars:
		if absf(c.d - d) < half_window + c.width * 0.5:
			var g := c.s - player_s - c.length * 0.5
			if g > -2.0 and g < best:
				best = g
	return best

func closing_speed_ahead(player_s: float, d: float, half_window: float, player_v: float) -> float:
	var best := 1e9
	var cv := 0.0
	for c in cars:
		if absf(c.d - d) < half_window + c.width * 0.5:
			var g := c.s - player_s - c.length * 0.5
			if g > -2.0 and g < best:
				best = g
				cv = player_v - c.speed * c.dir
	return cv
