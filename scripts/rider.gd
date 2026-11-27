extends Node3D
class_name Rider
## Player motorcycle: engine/gearbox, lean-based steering dynamics in road coordinates,
## first-person / chase camera, and crash behaviour.

signal crashed(reason: String)
signal gear_changed(gear: int)

const G := 9.81
const MASS := 285.0               # bike + rider (kg)
const POWER := 128000.0           # peak power at the wheel (W)
const CDA := 0.29                 # drag area, tucked
const REDLINE := 14000.0
const IDLE_RPM := 1300.0
# Speed (m/s) at redline in each gear.
const GEAR_TOP := [41.0, 53.0, 62.0, 70.0, 77.5, 84.5]
const MAX_LEAN := deg_to_rad(54.0)
const BIKE_HALF_LEN := 1.02
const BIKE_HALF_W := 0.36

var road: Road
var bike: BikeVisual
var camera: Camera3D

# --- state in road coordinates ---
var s := 2.0
var d := Road.LANE_W * 0.5
var psi := 0.0            # heading relative to the road (rad, + = towards the right)
var v := 0.0              # forward speed (m/s)
var lean := 0.0           # roll angle (rad, + = right)
var lean_rate := 0.0
var rpm := IDLE_RPM
var gear := 1
var shift_timer := 0.0
var curvature := 0.0
var accel := 0.0
var distance := 0.0
var odo_yaw := 0.0

# --- inputs ---
var steer := 0.0          # -1..1
var throttle := 0.0       # 0..1
var brake := 0.0          # 0..1
var assist := true
# Garage upgrades (multipliers set by the game from Game.upgrades).
var power_mult := 1.0
var top_mult := 1.0
var brake_mult := 1.0
var handling_mult := 1.0
var grip := 1.0            # < 1 in the rain
var controls_enabled := true

# --- crash ---
var is_crashed := false
var crash_time := 0.0
var _crash_pos := Vector3.ZERO
var _crash_vel := Vector3.ZERO
var _crash_basis := Basis()
var _crash_spin := 0.0
var _crash_roll := 0.0
var _crash_cam_from := Transform3D()

# --- camera ---
var view := 0             # Game.View
var _cam_shake := 0.0
var _cam_t := 0.0
var _chase_xf := Transform3D()
var _chase_prev_bike := Vector3.ZERO
var _chase_init := false
var _head_offset := Vector3(0, 1.38, 0.3)
var _fov := 60.0
var scrape := 0.0         # >0 while grinding a guard rail (for sparks/sound)
var wheelie := 0.0

## The rider avatar, posed by IK onto the grips/pegs every frame (scripts/rider_model.gd).
const SHOW_RIDER := true
var model: RiderModel
var _clutch_t := 0.0
var _thrown: Node3D
var _thrown_vel := Vector3.ZERO
var _thrown_spin := Vector3.ZERO

func _ready() -> void:
	bike = BikeVisual.new()
	bike.name = "Bike"
	add_child(bike)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.05
	camera.far = 1600.0
	camera.fov = 72.0
	add_child(camera)
	camera.current = true
	_add_reflection_probe()
	bike.enable_mirrors.call_deferred(Game.quality > 0)
	if SHOW_RIDER:
		model = RiderModel.new()
		model.name = "RiderModel"
		bike.lean_node.add_child(model)

## A reflection probe riding with the bike captures the road, scenery and traffic every frame,
## so the paint, chrome and mirrors reflect the actual world (not just the sky).
var probe: ReflectionProbe

func _add_reflection_probe() -> void:
	if Game.quality <= 0:
		return
	probe = ReflectionProbe.new()
	probe.name = "BikeReflections"
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	probe.size = Vector3(40, 20, 40)
	probe.origin_offset = Vector3(0, 0.8, 0)
	probe.max_distance = 300.0
	probe.box_projection = false
	probe.interior = false
	probe.enable_shadows = false
	probe.cull_mask = 1 << 0          # world only; the bike lives on layer 2
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	probe.mesh_lod_threshold = 4.0
	bike.add_child(probe)

func reset_at(start_s: float, start_d: float) -> void:
	s = start_s
	d = start_d
	psi = 0.0
	v = 0.0
	lean = 0.0
	lean_rate = 0.0
	gear = 1
	rpm = IDLE_RPM
	is_crashed = false
	_chase_init = false

func kmh() -> float:
	return v * 3.6

func set_view(vw: int) -> void:
	view = vw
	_chase_init = false
	if model:
		model.set_first_person(vw == Game.View.FIRST_PERSON and not Game.has_flag("photo"))

# ------------------------------------------------------------------ simulation

func simulate(dt: float) -> void:
	if is_crashed:
		_simulate_crash(dt)
		return
	var k_road := road.curvature_at(s)
	_engine(dt)
	_steering(dt, k_road)
	# Frenet integration.
	var sdot := v * cos(psi) / maxf(1.0 - d * k_road, 0.2)
	var ddot := v * sin(psi)
	s += sdot * dt
	d += ddot * dt
	psi += (v * curvature - k_road * sdot) * dt
	distance += v * dt
	# Guard rails.
	var lim := Road.RAIL_D - 0.42
	scrape = maxf(scrape - dt * 3.0, 0.0)
	if absf(d) > lim:
		var into := signf(d)
		if absf(psi) > 0.22 and v > 14.0 and signf(psi) == into:
			crash("rail")
			return
		d = into * lim
		if signf(psi) == into:
			psi = -psi * 0.3
		v = maxf(v - 9.0 * dt, 0.0)
		scrape = 1.0
		_cam_shake = maxf(_cam_shake, 0.5)

func _engine(dt: float) -> void:
	var top: float = GEAR_TOP[gear - 1] * top_mult
	var wheel_rpm := v / top * REDLINE
	# Clutch slip keeps revs up when pulling away in first.
	var slip_rpm := 0.0
	if gear == 1:
		slip_rpm = lerpf(IDLE_RPM, 6500.0, throttle) * clampf(1.0 - v / 14.0, 0.0, 1.0)
	var target_rpm := maxf(wheel_rpm, maxf(slip_rpm, IDLE_RPM))
	rpm = lerpf(rpm, target_rpm, 1.0 - exp(-18.0 * dt))
	# Auto gearbox.
	if shift_timer > 0.0:
		shift_timer -= dt
	elif gear < 6 and rpm > 13300.0 and throttle > 0.1:
		gear += 1
		shift_timer = 0.16
		_clutch_t = 0.25
		gear_changed.emit(gear)
		_cam_shake = maxf(_cam_shake, 0.25)
	elif gear > 1 and rpm < (6200.0 if throttle > 0.5 else 4800.0):
		gear -= 1
		shift_timer = 0.12
		_clutch_t = 0.25
		gear_changed.emit(gear)
	var x := clampf(rpm / REDLINE, 0.0, 1.0)
	var power_curve := 0.32 + 0.68 * smoothstep(0.18, 0.88, x) - 0.15 * smoothstep(0.96, 1.02, x)
	var thr := throttle if shift_timer <= 0.0 else throttle * 0.15
	var traction := cos(lean) * 0.9 + 0.1
	var a_drive := thr * minf(POWER * power_mult * power_curve / (MASS * maxf(v, 4.0)), 8.8 * traction * grip)
	if gear == 1 and v < 14.0:
		a_drive = thr * 8.8 * traction
	var a_drag := 0.5 * 1.2 * CDA * v * v / MASS + 0.18
	var a_engine_brake := (1.0 - throttle) * (0.6 + 0.08 * (7 - gear)) if v > 1.0 else 0.0
	var a_brake := brake * 10.5 * brake_mult * grip * (cos(lean) * 0.75 + 0.25)
	var a_grade := -G * road.grade_at(s)
	accel = a_drive - a_drag - a_engine_brake - a_brake + a_grade
	v = maxf(v + accel * dt, 0.0)
	# Visual wheelie/pitch from acceleration.
	wheelie = lerpf(wheelie, clampf(accel / 9.0, -1.0, 1.0), 1.0 - exp(-6.0 * dt))

func _steering(dt: float, k_road: float) -> void:
	var vv := maxf(v, 0.5)
	var lean_target: float
	var kappa_des: float
	if assist:
		# Steering assist: input selects a heading relative to the road (i.e. a lateral speed);
		# road curvature is fed forward so the bike leans through bends by itself.
		var lat_max := lerpf(3.0, 7.0, clampf(v / 30.0, 0.0, 1.0))
		var psi_max := asin(clampf(lat_max / vv, 0.0, 0.6))
		var psi_t := steer * psi_max
		# Gentle centring keeps the bike off the rails when the player lets go near the edge.
		var a_lat_max := 7.0 * handling_mult * grip
		var k_corr := clampf((psi_t - psi) * 2.7 / vv, -a_lat_max / (vv * vv), a_lat_max / (vv * vv))
		kappa_des = k_road + k_corr
		lean_target = atan(vv * vv * kappa_des / G)
	else:
		lean_target = steer * MAX_LEAN
		kappa_des = G * tan(lean_target) / (vv * vv)
	# Less lean at walking pace.
	var low := smoothstep(2.0, 9.0, v)
	lean_target = clampf(lean_target, -MAX_LEAN, MAX_LEAN) * low
	# Roll dynamics: damped spring with a roll-rate limit (bikes can't flick instantly).
	var w := 9.5 * handling_mult
	var z := 0.95
	var acc := w * w * (lean_target - lean) - 2.0 * z * w * lean_rate
	lean_rate = clampf(lean_rate + acc * dt, -2.4 * handling_mult, 2.4 * handling_mult)
	lean += lean_rate * dt
	lean = clampf(lean, -MAX_LEAN, MAX_LEAN)
	# Path curvature from lean (dynamic) blended with direct steering at low speed (kinematic).
	var kappa_dyn := G * tan(lean) / (vv * vv)
	var kappa_kin := clampf(kappa_des, -0.25, 0.25)
	curvature = lerpf(kappa_kin, kappa_dyn, low)

func crash(reason: String) -> void:
	if is_crashed:
		return
	is_crashed = true
	crash_time = 0.0
	var t := bike_transform()
	_crash_pos = t.origin
	_crash_basis = t.basis
	_crash_vel = -t.basis.z * v * 0.85 + Vector3.UP * minf(v * 0.08, 3.0)
	_crash_spin = (randf() - 0.5) * 4.0 + signf(lean + 0.01) * 1.5
	_crash_roll = lean
	_crash_cam_from = camera.global_transform
	_cam_shake = 1.0
	# Throw the rider off the bike.
	if SHOW_RIDER:
		_throw_rider(t)
	crashed.emit(reason)

func _throw_rider(t: Transform3D) -> void:
	_thrown = Node3D.new()
	get_parent().add_child(_thrown)
	var lt := bike.lean_node.global_transform
	_thrown.global_transform = Transform3D(lt.basis, lt * Vector3(0, 1.0, 0.15))
	if model:
		var g := model.global_transform
		model.get_parent().remove_child(model)
		_thrown.add_child(model)
		model.global_transform = g
		model.set_first_person(false)
		model.frozen = true
	_thrown_vel = -t.basis.z * v * 0.95 + Vector3.UP * (2.5 + v * 0.04) + t.basis.x * (randf() - 0.5) * 3.0
	_thrown_spin = Vector3(randf_range(-6, -3), randf_range(-2, 2), randf_range(-3, 3))

func _simulate_crash(dt: float) -> void:
	crash_time += dt
	_crash_vel.y -= G * dt
	_crash_pos += _crash_vel * dt
	var ground := road.center_at(s).y
	# Track s roughly so the road keeps streaming / ground height is right.
	var t := road.xform(s, d)
	var rel := _crash_pos - t.origin
	s += rel.dot(-t.basis.z) * 0.5
	ground = road.point(s, 0).y
	if _crash_pos.y < ground:
		_crash_pos.y = ground
		_crash_vel.y = absf(_crash_vel.y) * 0.25
		var hv := Vector3(_crash_vel.x, 0, _crash_vel.z)
		hv = hv.move_toward(Vector3.ZERO, 7.5 * dt)
		_crash_vel.x = hv.x
		_crash_vel.z = hv.z
		scrape = 1.0 if hv.length() > 2.0 else 0.0
	_crash_spin = move_toward(_crash_spin, 0.0, dt * 1.2)
	# Thrown rider: ballistic tumble, then slide and roll to a stop.
	if _thrown:
		_thrown_vel.y -= G * dt
		var p := _thrown.global_position + _thrown_vel * dt
		var gy := road.point(s, 0).y + 0.22
		if p.y < gy:
			p.y = gy
			_thrown_vel.y = absf(_thrown_vel.y) * 0.3
			var hv := Vector3(_thrown_vel.x, 0, _thrown_vel.z).move_toward(Vector3.ZERO, 9.0 * dt)
			_thrown_vel.x = hv.x
			_thrown_vel.z = hv.z
			_thrown_spin = _thrown_spin.move_toward(Vector3.ZERO, 6.0 * dt)
		var b := _thrown.global_transform.basis
		if _thrown_spin.length() > 0.001:
			b = b.rotated(_thrown_spin.normalized(), _thrown_spin.length() * dt)
		_thrown.global_transform = Transform3D(b.orthonormalized(), p)
	_crash_basis = _crash_basis.rotated(Vector3.UP, _crash_spin * dt).orthonormalized()
	_crash_roll = move_toward(_crash_roll, signf(_crash_roll + 0.001) * PI * 0.47, dt * 4.0)
	v = Vector3(_crash_vel.x, 0, _crash_vel.z).length()

# ------------------------------------------------------------------ visuals

func bike_transform() -> Transform3D:
	var t := road.xform(s, d)
	t.basis = t.basis * Basis(Vector3.UP, -psi)
	return t

func update_visuals(dt: float) -> void:
	_cam_t += dt
	_cam_shake = maxf(_cam_shake - dt * 1.6, 0.0)
	if is_crashed:
		bike.global_transform = Transform3D(_crash_basis, _crash_pos)
		bike.set_lean(_crash_roll)
		bike.roll(v * dt * 0.3)
		_update_crash_camera(dt)
		return
	var t := bike_transform()
	# Pitch the bike slightly under acceleration/braking (squat & dive).
	var pitch := wheelie * 0.025
	t.basis = t.basis * Basis(Vector3.RIGHT, pitch)
	bike.global_transform = t
	bike.set_lean(lean)
	bike.roll(v * dt)
	bike.set_brake_light(brake > 0.1)
	if bike.dash:
		bike.dash.set_values(kmh(), rpm, gear)
	bike.update_mirrors()
	if model:
		_clutch_t = maxf(_clutch_t - dt, 0.0)
		model.throttle = throttle
		model.brake = brake
		model.lean = lean
		model.steer = steer
		model.speed = v
		model.clutch = clampf(_clutch_t / 0.12, 0.0, 1.0)
		model.update_pose(dt)
		bike.set_levers(model.lever_pull, model.clutch_pull)
	if Game.has_flag("photo"):
		# Dev/marketing camera: close 3/4 view riding alongside the bike.
		var eye := t.origin + t.basis.x * 2.3 + t.basis.y * 1.05 - t.basis.z * 1.6
		camera.global_transform = Transform3D(Basis(), eye).looking_at(t.origin + t.basis.y * 0.6 + t.basis.z * 0.2, t.basis.y)
		camera.fov = 45.0
	elif view == Game.View.FIRST_PERSON:
		_update_fp_camera(t, dt)
	else:
		_update_chase_camera(t, dt)

func _shake_vec(amount: float) -> Vector3:
	var tt := _cam_t
	return Vector3(sin(tt * 37.0) + sin(tt * 23.0) * 0.5, sin(tt * 41.0 + 1.0) + sin(tt * 19.0) * 0.5, 0.0) * amount

func _update_fp_camera(t: Transform3D, dt: float) -> void:
	# Head position in the leaning frame: riders hang off slightly to the inside of a turn.
	var target_head := Vector3(lean * 0.12, 1.38 - absf(lean) * 0.06, 0.3)
	# Tuck down a bit at high speed.
	target_head.y -= clampf((v - 40.0) / 40.0, 0.0, 1.0) * 0.03
	target_head.z -= clampf((v - 40.0) / 40.0, 0.0, 1.0) * 0.04

	if model:
		target_head = model.fp_camera_position()
	# Player POV adjustment (Settings / pause menu).
	target_head += Vector3(0, Game.cam_height, -Game.cam_forward)
	_head_offset = _head_offset.lerp(target_head, 1.0 - exp(-8.0 * dt))
	var lean_b := Basis(Vector3.BACK, -lean)
	var origin := t * (Basis(Vector3.BACK, -lean) * _head_offset)
	# Head stays more upright than the bike (riders counter the lean with their neck).
	var cam_roll := -lean * 0.42
	var look_yaw := -curvature * clampf(v, 0.0, 60.0) * 0.12
	var look_pitch := deg_to_rad(Game.cam_pitch) - wheelie * 0.02
	var b := t.basis * Basis(Vector3.UP, look_yaw) * Basis(Vector3.BACK, cam_roll) * Basis(Vector3.RIGHT, look_pitch)
	# Engine & road vibration.
	var vib := 0.0015 + 0.004 * clampf(v / 80.0, 0.0, 1.0) + _cam_shake * 0.02
	var sh := _shake_vec(vib)
	origin += b.x * sh.x + b.y * sh.y
	camera.global_transform = Transform3D(b.orthonormalized(), origin)
	var target_fov := Game.cam_fov + 16.0 * clampf((v - 15.0) / 70.0, 0.0, 1.0)
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-3.0 * dt))
	camera.fov = _fov

func _update_chase_camera(t: Transform3D, dt: float) -> void:
	var back := 2.05 + clampf(v / 80.0, 0.0, 1.0) * 0.45
	var up := 1.2
	var target := Transform3D(t.basis * Basis(Vector3.BACK, -lean * 0.25), t.origin + t.basis.y * up + t.basis.z * back)
	if not _chase_init:
		_chase_xf = target
		_chase_prev_bike = t.origin
		_chase_init = true
	# Smooth the camera's offset from the bike (not its world position), so it doesn't trail
	# further behind the faster you go.
	var rel_now := _chase_xf.origin - _chase_prev_bike
	var rel_target := target.origin - t.origin
	_chase_xf.origin = t.origin + rel_now.lerp(rel_target, 1.0 - exp(-10.0 * dt))
	_chase_prev_bike = t.origin
	_chase_xf.basis = _chase_xf.basis.slerp(target.basis.orthonormalized(), 1.0 - exp(-8.0 * dt))
	var look_at_p := t.origin + t.basis.y * 0.95 - t.basis.z * 6.0
	var xf := _chase_xf.looking_at(look_at_p, _chase_xf.basis.y)
	var sh := _shake_vec(_cam_shake * 0.05)
	xf.origin += xf.basis.x * sh.x + xf.basis.y * sh.y
	camera.global_transform = xf
	var target_fov := 58.0 + 14.0 * clampf((v - 15.0) / 70.0, 0.0, 1.0)
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-3.0 * dt))
	camera.fov = _fov

func _update_crash_camera(dt: float) -> void:
	# Camera is thrown up and back, then watches the sliding bike.
	var k := clampf(crash_time / 1.1, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var rt := road.xform(s, d)
	var watch_pos := _crash_pos + rt.basis.z * 7.0 + Vector3.UP * 3.2 + rt.basis.x * 2.5
	var from := _crash_cam_from.origin
	var pos := from.lerp(watch_pos, e)
	var sh := _shake_vec(_cam_shake * 0.15)
	var xf := Transform3D(Basis(), pos + Vector3(sh.x, sh.y, 0)).looking_at(_crash_pos + Vector3.UP * 0.4, Vector3.UP)
	camera.global_transform = xf
	camera.fov = lerpf(camera.fov, 60.0, 1.0 - exp(-2.0 * dt))
