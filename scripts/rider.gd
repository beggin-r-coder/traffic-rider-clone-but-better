extends Node3D
class_name Rider
## Player motorcycle: engine/gearbox, lean-based steering dynamics in road coordinates,
## first-person / chase camera, and crash behaviour.

signal crashed(reason: String)
signal gear_changed(gear: int)

const G := 9.81
# Performance comes from the selected bike (BikeDefs).
var MASS := 285.0                 # bike + rider (kg)
var POWER := 128000.0             # peak power at the wheel (W)
var CDA := 0.29                   # drag area, tucked
var REDLINE := 14000.0
var IDLE_RPM := 1300.0
# Speed (m/s) at redline in each gear.
var GEAR_TOP: Array = [41.0, 53.0, 62.0, 70.0, 77.5, 84.5]
var MAX_LEAN := deg_to_rad(54.0)
var base_handling := 1.0
var def: Dictionary = {}
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
var wheelie := 0.0        # visual squat/dive from acceleration (-1..1)
## Power wheelie: full throttle in 1st/2nd below ~100 km/h lifts the front wheel. Wheelie control
## caps the angle; roll off, brake or reach speed and it sets down. Steering is lighter on one wheel.
var wheelie_angle := 0.0  # radians, front wheel up
var _wheelie_on := false
var _thr_low_t := 9.0     # seconds since the throttle was last rolled off
const WHEELIE_MAX := deg_to_rad(30.0)
var _acc_s := 0.0         # smoothed longitudinal acceleration (camera pitch)
var _shift_kick := 0.0    # head nod on upshift
var _fov_kick := 0.0      # FOV punch (near misses)
var _cam_roll := 0.0      # head roll, lags the bike's lean
var _dive := 0.0          # rad: fork compression pitch (nose down)
var stoppie := 0.0        # rad: chassis pitched over the front tyre under hard braking (rear goes light)
var rear_slide := 0.0     # rad: rear stepping out when braking hard into a bend (+ = rear to the right)
var tyre_fx := 0.0        # 0..1 smoke / skid intensity
var fx: RaceFx

## The rider avatar, posed by IK onto the grips/pegs every frame (scripts/rider_model.gd).
const SHOW_RIDER := true
var model: RiderModel
var _clutch_t := 0.0
var _thrown: Node3D
var _thrown_vel := Vector3.ZERO
var _thrown_spin := Vector3.ZERO
var _thrown_ground := 0.0

func _ready() -> void:
	if def.is_empty():
		def = BikeDefs.current()
	MASS = def["mass"]
	POWER = def["power"]
	CDA = def["cda"]
	REDLINE = def["redline"]
	IDLE_RPM = def["idle"]
	GEAR_TOP = def["gear_top"]
	MAX_LEAN = deg_to_rad(def["max_lean"])
	base_handling = def["handling"]
	rpm = IDLE_RPM
	bike = BikeVisual.new()
	bike.def = def
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
		model.def = def
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
	wheelie_angle = 0.0
	_wheelie_on = false
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
		slip_rpm = lerpf(IDLE_RPM, 6500.0 * REDLINE / 14000.0, throttle) * clampf(1.0 - v / 14.0, 0.0, 1.0)
	var target_rpm := maxf(wheel_rpm, maxf(slip_rpm, IDLE_RPM))
	rpm = lerpf(rpm, target_rpm, 1.0 - exp(-18.0 * dt))
	# Auto gearbox.
	if shift_timer > 0.0:
		shift_timer -= dt
	elif gear < 6 and rpm > REDLINE * 0.95 and throttle > 0.1:
		gear += 1
		shift_timer = 0.16
		_clutch_t = 0.25
		gear_changed.emit(gear)
		_cam_shake = maxf(_cam_shake, 0.25)
		_shift_kick = 1.0
	elif gear > 1 and rpm < (6200.0 if throttle > 0.5 else 4800.0) * REDLINE / 14000.0:
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
	# Power wheelie.
	# Triggered by snapping the throttle open (rolled off, then wide open within 0.35 s); held up
	# by keeping it pinned.
	_thr_low_t = 0.0 if throttle < 0.4 else _thr_low_t + dt
	var can_wheelie := controls_enabled and throttle > 0.9 and brake < 0.1 and gear <= 2 and v < 28.0
	if can_wheelie and _thr_low_t < 0.35:
		_wheelie_on = true
	if not can_wheelie:
		_wheelie_on = false
	var w_target := 0.0
	if _wheelie_on and shift_timer <= 0.0:
		w_target = WHEELIE_MAX * clampf(a_drive / 7.5, 0.0, 1.0) * clampf((28.0 - v) / 6.0, 0.25, 1.0) * clampf((v - 1.5) / 3.0, 0.0, 1.0)
	if w_target > wheelie_angle:
		wheelie_angle = move_toward(wheelie_angle, w_target, 0.55 * dt)
	else:
		wheelie_angle = move_toward(wheelie_angle, w_target, (2.2 if brake > 0.1 else 1.1) * dt)
	# Visual wheelie/pitch from acceleration.
	wheelie = lerpf(wheelie, clampf(accel / 9.0, -1.0, 1.0), 1.0 - exp(-6.0 * dt))

func _steering(dt: float, k_road: float) -> void:
	var vv := maxf(v, 0.5)
	var lean_target: float
	var kappa_des: float
	if assist:
		# Steering assist: input selects a heading relative to the road (i.e. a lateral speed);
		# road curvature is fed forward so the bike leans through bends by itself.
		var lat_max := lerpf(3.0, 5.5, clampf(v / 30.0, 0.0, 1.0))
		var psi_max := asin(clampf(lat_max / vv, 0.0, 0.6))
		var psi_t := steer * psi_max
		# Lane changes / swerves: lateral acceleration capped near what a rider uses on the road
		# (~4 m/s^2 = ~22 deg of lean, a little more with Handling upgrades). Bends add their own lean
		# through the curvature feed-forward, so corners still lean as far as they need.
		var a_lat_max := 4.0 * handling_mult * grip
		var k_corr := clampf((psi_t - psi) * 2.2 / vv, -a_lat_max / (vv * vv), a_lat_max / (vv * vv))
		kappa_des = k_road + k_corr
		lean_target = atan(vv * vv * kappa_des / G)
	else:
		lean_target = steer * MAX_LEAN
		kappa_des = G * tan(lean_target) / (vv * vv)
	# Less lean at walking pace.
	var low := smoothstep(2.0, 9.0, v)
	lean_target = clampf(lean_target, -MAX_LEAN, MAX_LEAN) * low
	# Roll dynamics: damped spring with a roll-rate limit (bikes can't flick instantly).
	# On one wheel there is little steering.
	lean_target *= 1.0 - 0.7 * clampf(wheelie_angle / WHEELIE_MAX, 0.0, 1.0)
	var w := 9.5 * handling_mult
	var rate_max := 2.6 * handling_mult
	# Flicks: reversing the lean (e.g. swerving between cars) is quicker than leaning in from upright.
	if absf(lean) > 0.08 and signf(lean_target - lean) != signf(lean):
		w *= 1.3
		rate_max *= 1.25
	var z := 0.95
	var acc := w * w * (lean_target - lean) - 2.0 * z * w * lean_rate
	lean_rate = clampf(lean_rate + acc * dt, -rate_max, rate_max)
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
	wheelie_angle = 0.0
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
	_thrown_ground = 0.0
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
		if _thrown_ground > 0.4:
			# On the ground the body settles flat (head-to-feet axis horizontal, on its back or front).
			var yh := Vector3(b.y.x, 0.0, b.y.z)
			if yh.length() < 0.2:
				yh = Vector3(_thrown_vel.x, 0.0, _thrown_vel.z)
				if yh.length() < 0.01:
					yh = Vector3.FORWARD
			yh = yh.normalized()
			var zt := Vector3.UP if b.z.dot(Vector3.UP) >= 0.0 else Vector3.DOWN
			var flat := Basis(yh.cross(zt), yh, zt).orthonormalized()
			b = b.orthonormalized().slerp(flat, 1.0 - exp(-5.0 * dt))
		_thrown.global_transform = Transform3D(b.orthonormalized(), p)
		if model:
			_thrown_ground = lerpf(_thrown_ground, 1.0 if p.y <= gy + 0.05 else 0.0, 1.0 - exp(-4.0 * dt))
			model.update_crash_pose(crash_time, _thrown_ground)
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
	# Squat under acceleration (about the rear contact patch).
	var pitch := maxf(wheelie, 0.0) * 0.02
	t.basis = t.basis * Basis(Vector3.RIGHT, pitch)
	# Suspension: braking compresses the forks (nose down, pivoting about the rear contact patch)
	# while the front wheel stays on the road, i.e. the wheel rises into the fender. Only at the
	# very limit from high speed does the rear go light and lift a little (pivot at the front).
	var dive_t := deg_to_rad(2.0) * clampf(brake * 1.2, 0.0, 1.0) * clampf(v / 12.0, 0.0, 1.0)
	dive_t -= deg_to_rad(0.6) * clampf(throttle, 0.0, 1.0) * clampf(accel / 6.0, 0.0, 1.0)  # fork extends on the gas
	_dive = lerpf(_dive, dive_t, 1.0 - exp(-(9.0 if dive_t > _dive else 5.0) * dt))
	var st_t := 0.0
	if brake > 0.97 and v > 40.0:
		st_t = deg_to_rad(1.1) * clampf((v - 40.0) / 20.0, 0.0, 1.0)
	stoppie = lerpf(stoppie, st_t, 1.0 - exp(-(4.0 if st_t > stoppie else 6.0) * dt))
	# Backing it in: only braking really hard into a real bend with the bike still upright.
	var turn: float = model.turn_ahead if model else 0.0
	var sl_t := 0.0
	if brake > 0.92 and v > 30.0 and absf(turn) > 0.6 and absf(lean) < 0.3:
		sl_t = -signf(turn) * deg_to_rad(3.5)
	rear_slide = lerpf(rear_slide, sl_t, 1.0 - exp(-2.5 * dt))
	var rear := Vector3(0, 0, bike.wheelbase * 0.5)
	var front := Vector3(0, 0, -bike.wheelbase * 0.5)
	var t_cam := t
	if absf(_dive) > 0.0002:
		var db := Basis(Vector3.RIGHT, -_dive)
		t = t * Transform3D(db, rear - db * rear)
		t_cam = t
	bike.set_front_compression(bike.wheelbase * sin(_dive))
	if stoppie > 0.0005 or absf(rear_slide) > 0.0005:
		var sb := Basis(Vector3.UP, rear_slide) * Basis(Vector3.RIGHT, -stoppie)
		t = t * Transform3D(sb, front - sb * front)
		var cb := Basis(Vector3.RIGHT, -stoppie * 0.7)
		t_cam = t_cam * Transform3D(cb, front - cb * front)
	# Tyre smoke / skid marks when the rear slides or the brakes are at the limit at speed.
	tyre_fx = clampf(absf(rear_slide) / deg_to_rad(5.0), 0.0, 1.0)
	if brake > 0.95 and v > 25.0:
		tyre_fx = maxf(tyre_fx, 0.4)
	if fx == null and get_parent():
		fx = RaceFx.new()
		get_parent().add_child(fx)
	if fx:
		var rear_c: Vector3 = t * Vector3(0, 0.02, bike.wheelbase * 0.5)
		fx.update_tyre(rear_c, -t.basis.z, t.basis.y, tyre_fx)
	bike.update_race_fx(dt, brake, v)
	if wheelie_angle > 0.001:
		# Pivot about the rear tyre's contact patch.
		var wb := Basis(Vector3.RIGHT, wheelie_angle)
		t = t * Transform3D(wb, rear - wb * rear)
		# The camera follows most of it (you see sky, but can still see the road ahead).
		var wc := Basis(Vector3.RIGHT, wheelie_angle * 0.6)
		t_cam = t_cam * Transform3D(wc, rear - wc * rear)
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
		model.accel = accel
		# Upcoming bend (+ right): what the rider sets up for and looks into.
		var look_s := maxf(25.0, v * 1.8)
		model.turn_ahead = clampf(road.curvature_at(s + look_s) * 160.0, -1.0, 1.0) if road else 0.0
		model.update_pose(dt)
		_update_knee(dt)
		bike.set_levers(model.lever_pull, model.clutch_pull)
	if Game.has_flag("photo"):
		# Dev/marketing camera: close 3/4 view riding alongside the bike.
		var eye := t.origin + t.basis.x * 2.3 + t.basis.y * 1.05 - t.basis.z * 1.6
		camera.global_transform = Transform3D(Basis(), eye).looking_at(t.origin + t.basis.y * 0.6 + t.basis.z * 0.2, t.basis.y)
		camera.fov = 45.0
	elif view == Game.View.FIRST_PERSON:
		_update_fp_camera(t_cam, dt)
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
		# Helmet cam: the framed cockpit position plus the head's real movement from the animation
		# (down behind the screen in the tuck, inside when hanging off, forward on the brakes).
		var hd := model.head_delta()
		hd = Vector3(clampf(hd.x, -0.3, 0.3), clampf(hd.y, -0.25, 0.08), clampf(hd.z, -0.2, 0.12))
		target_head = model.fp_camera_position() + hd * Vector3(0.6, 0.75, 0.9)
	# Player POV adjustment (Settings / pause menu).
	target_head += Vector3(0, Game.cam_height, -Game.cam_forward)
	# Weight transfer: the head pitches down and forward under braking / engine braking, back
	# under hard acceleration; a short nod back on each upshift.
	_acc_s = lerpf(_acc_s, accel, 1.0 - exp(-5.0 * dt))
	_shift_kick = maxf(_shift_kick - dt * 6.0, 0.0)
	_fov_kick = move_toward(_fov_kick, 0.0, dt * 9.0)
	var surge := clampf(_acc_s, -11.0, 9.0)
	target_head += Vector3(0, -0.0015 * maxf(-surge, 0.0), 0.004 * surge)
	_head_offset = _head_offset.lerp(target_head, 1.0 - exp(-8.0 * dt))
	var origin := t * (Basis(Vector3.BACK, -lean) * _head_offset)
	# Head stays more upright than the bike (riders counter the lean with their neck), lagging it
	# slightly so leaning in feels like your body is doing it.
	_cam_roll = lerpf(_cam_roll, -lean * 0.42, 1.0 - exp(-7.0 * dt))
	var look_yaw := -curvature * clampf(v, 0.0, 60.0) * 0.12
	if model:
		look_yaw -= model.head_yaw() * 0.6         # eyes through the corner
	var look_pitch := deg_to_rad(Game.cam_pitch) + surge * 0.0055 + _shift_kick * 0.022
	if model:
		look_pitch += deg_to_rad(8.0) * model._tuck   # tucked: eyes up over the dash
	var b := t.basis * Basis(Vector3.UP, look_yaw) * Basis(Vector3.BACK, _cam_roll) * Basis(Vector3.RIGHT, look_pitch)
	# Vibration: road rumble growing with speed, a fine engine buzz growing with revs.
	var r01 := clampf(rpm / REDLINE, 0.0, 1.0)
	var vib := 0.0012 + 0.0045 * clampf(v / 80.0, 0.0, 1.0) + _cam_shake * 0.02
	var sh := _shake_vec(vib)
	var buzz := 0.0012 * r01 * r01 * (1.0 if throttle > 0.2 else 0.5)
	sh += Vector3(sin(_cam_t * 211.0), sin(_cam_t * 263.0 + 0.7), 0.0) * buzz
	origin += b.x * sh.x + b.y * sh.y
	camera.global_transform = Transform3D(b.orthonormalized(), origin)
	# Speed FOV (a little extra past 220 km/h), a dip on upshifts, a punch on near misses.
	var target_fov := Game.cam_fov + 16.0 * clampf((v - 15.0) / 70.0, 0.0, 1.0) + 5.0 * clampf((v - 61.0) / 25.0, 0.0, 1.0)
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-3.0 * dt))
	camera.fov = _fov - _shift_kick * 1.5 + _fov_kick

# --- knee down ---
var knee_scrape := 0.0      # 0..1, for the scrape sound
var knee_min_h := 9.0       # lowest knee height seen (test log)
var _knee_sparks: GPUParticles3D

func _update_knee(dt: float) -> void:
	knee_scrape = maxf(knee_scrape - dt * 4.0, 0.0)
	if model == null or road == null or absf(lean) < 0.6:
		if _knee_sparks:
			_knee_sparks.emitting = false
		return
	var side := signf(lean)
	var lt := bike.lean_node.global_transform
	var kp: Vector3 = lt * model.knee_point(side)
	var ground := road.point(s, d).y
	var h := kp.y - ground
	knee_min_h = minf(knee_min_h, h)
	if h < 0.10 and v > 8.0:
		knee_scrape = 1.0
		if _knee_sparks == null:
			_knee_sparks = _make_knee_sparks()
		_knee_sparks.global_position = Vector3(kp.x, ground + 0.02, kp.z)
		_knee_sparks.amount_ratio = clampf((0.10 - h) / 0.06, 0.25, 1.0)
		_knee_sparks.emitting = true
	elif _knee_sparks:
		_knee_sparks.emitting = false

func _make_knee_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.35
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.35, 1)
	pm.spread = 25.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.012
	pm.scale_max = 0.03
	pm.color = Color(1.0, 0.62, 0.2)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.15)
	m.emission_energy_multiplier = 3.0
	q.material = m
	p.draw_pass_1 = q
	get_parent().add_child(p)
	return p

## FOV punch (degrees) for near misses.
func kick_fov(deg: float) -> void:
	_fov_kick = maxf(_fov_kick, deg)

## Follow camera (racing-game style): behind and above the bike on its path, yaw following the
## direction of travel with a little lag, horizon kept nearly level (the bike leans in the frame,
## the world doesn't), pulling back slightly with speed. The bike sits in the lower-middle of the frame.
var _chase_yaw_dir := Vector3.FORWARD
var _chase_roll := 0.0
var _chase_dist := 2.6

func _update_chase_camera(t: Transform3D, dt: float) -> void:
	var road_t := road.xform(s, d)
	var up := road_t.basis.y.normalized()
	var travel := (-t.basis.z).normalized()          # bike heading (road heading + psi)
	if not _chase_init:
		_chase_yaw_dir = travel
		_chase_roll = 0.0
		_chase_init = true
	# Heading follows with lag: in a lane change the bike moves across the frame a little and
	# the camera catches up, instead of the camera swinging around the bike.
	_chase_yaw_dir = _chase_yaw_dir.slerp(travel, 1.0 - exp(-4.0 * dt)).normalized()
	var fwd := (_chase_yaw_dir - up * _chase_yaw_dir.dot(up)).normalized()
	_chase_dist = lerpf(_chase_dist, 2.55 + clampf(v / 80.0, 0.0, 1.0) * 0.45, 1.0 - exp(-2.0 * dt))
	var pivot := road.point(s, d) + up * 0.7
	var eye := pivot - fwd * _chase_dist + up * (0.55 + clampf(v / 80.0, 0.0, 1.0) * 0.05)
	var target := pivot + fwd * 3.0 + up * 0.2
	# A touch of roll with the lean (about 10%), smoothed.
	_chase_roll = lerpf(_chase_roll, -lean * 0.1, 1.0 - exp(-3.0 * dt))
	var xf := Transform3D(Basis(), eye).looking_at(target, up)
	xf.basis = xf.basis * Basis(Vector3.BACK, _chase_roll)
	var sh := _shake_vec(_cam_shake * 0.05 + 0.0012 * clampf(v / 80.0, 0.0, 1.0))
	xf.origin += xf.basis.x * sh.x + xf.basis.y * sh.y
	camera.global_transform = xf
	var target_fov := 56.0 + 10.0 * clampf((v - 15.0) / 70.0, 0.0, 1.0)
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-3.0 * dt))
	camera.fov = _fov + _fov_kick * 0.5

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
