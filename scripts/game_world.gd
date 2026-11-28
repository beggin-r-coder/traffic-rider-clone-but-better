extends Node3D
## Main gameplay scene: builds the world, runs the simulation loop, scoring and game flow.
## Also hosts the autopilot used by the --autotest / --shot dev flags.

enum State { COUNTDOWN, RIDING, CRASHED, OVER }

const SCORE_SPEED := 100.0 / 3.6       # score only accrues above 100 km/h
const NEAR_MISS_POINTS := 300
const COMBO_WINDOW := 4.0
const COMBO_MAX := 10
const HIGH_SPEED := 200.0 / 3.6         # high-speed bonus above 200 km/h

var road: Road
var traffic: Traffic
var rider: Rider
var hud: Hud
var audio: BikeAudio
var sun: DirectionalLight3D
var env: Environment
var backdrop: MeshInstance3D
var headlight: SpotLight3D
var sparks: GPUParticles3D
var sky_info := {}
var street_lights: StreetLightPool

var state := State.COUNTDOWN
var countdown := 3.0
var score := 0.0
var combo := 0
var combo_timer := 0.0
var near_misses := 0
var run_time := 0.0
var time_left := 60.0
var next_checkpoint := 2500.0
var oncoming_time := 0.0
var top_speed := 0.0
var paused := false
## Bonus streaks: points build up while the streak lasts and are banked (popup) when it ends.
## name -> {"on": bool, "t": seconds, "pts": float}
var streaks := {"HIGH SPEED": {"on": false, "t": 0.0, "pts": 0.0},
	"ONCOMING": {"on": false, "t": 0.0, "pts": 0.0},
	"WHEELIE": {"on": false, "t": 0.0, "pts": 0.0}}
var _thr_in := 0.0
var _brk_in := 0.0
var _slowmo_t := -1.0      # real seconds since the crash slow-motion started

# test harness
var autopilot := false
var _auto_lane := Road.LANE_W * 0.5
var _auto_log_t := 0.0
var _auto_stage := 0
var _until := 0.0
var _shot_times: Array = []
var _shot_dir := ""
var _shot_path := ""
var _shot_at := 0.0
var _crash_count := 0
var _sim_time := 0.0
var _quitting := false
var _max_lean := 0.0
var _max_k := 0.0

func _ready() -> void:
	var night := Game.time_of_day == Game.TimeOfDay.NIGHT
	var two_way := Game.mode == Game.Mode.TWO_WAY
	_apply_quality()
	_build_environment()
	road = Road.new()
	road.name = "Road"
	add_child(road)
	road.lamps_on = night or Game.rain
	road.setup(Game.run_seed, two_way, night)
	traffic = Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(road, Game.run_seed, two_way, night)
	traffic.lights_on = night or Game.rain
	if road.lamps_on:
		street_lights = StreetLightPool.new()
		street_lights.name = "StreetLights"
		add_child(street_lights)
		street_lights.setup(road, [3, 5, 7][clampi(Game.quality, 0, 2)], night)
	traffic.near_miss.connect(_on_near_miss)
	traffic.passed.connect(_on_passed)
	traffic.honk.connect(_on_honk)
	rider = Rider.new()
	rider.name = "Rider"
	add_child(rider)
	rider.road = road
	rider.assist = Game.assist
	rider.power_mult = 1.0 + 0.07 * Game.upgrade_level("engine")
	rider.top_mult = 1.0 + 0.02 * Game.upgrade_level("engine")
	rider.brake_mult = 1.0 + 0.08 * Game.upgrade_level("brakes")
	rider.handling_mult = rider.base_handling * (1.0 + 0.05 * Game.upgrade_level("handling"))
	rider.bike.set_paint(Game.bike_color)
	rider.reset_at(4.0, Road.LANE_W * 0.5)
	rider.set_view(Game.view)
	rider.crashed.connect(_on_crash)
	rider.gear_changed.connect(_on_gear)
	if night or Game.rain:
		headlight = SpotLight3D.new()
		headlight.light_color = Color(1.0, 0.96, 0.88)
		headlight.light_energy = 28.0
		headlight.spot_range = 120.0
		headlight.spot_angle = 30.0
		headlight.spot_angle_attenuation = 0.7
		headlight.spot_attenuation = 0.9
		headlight.position = Vector3(0, 0.95, -1.05)
		headlight.rotation.x = deg_to_rad(-4.0)
		headlight.shadow_enabled = false
		rider.bike.lean_node.add_child(headlight)
	_build_sparks()
	road.update_stream(rider.s)
	for i in 40:
		road.update_stream(rider.s)
	# Pre-populate some traffic ahead so the road is never empty at the start.
	for i in 14:
		traffic._try_spawn(rider.s - 150.0, 30.0)
	rider.update_visuals(0.0)
	audio = BikeAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.popped.connect(func(dl: float, st: float): rider.bike.flame(dl, st))
	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)
	if Game.rain:
		_setup_rain()
	if Game.mode == Game.Mode.TIME_TRIAL:
		time_left = 60.0
	# --- dev flags ---
	autopilot = Game.has_flag("autotest") or Game.has_flag("auto")
	_until = float(Game.flag("until", "0"))
	if Game.has_flag("shot"):
		autopilot = autopilot or not Game.has_flag("noauto")
		_shot_path = String(Game.flag("shot"))
		_shot_at = float(Game.flag("at", "6"))
	if Game.has_flag("shots"):
		autopilot = true
		_shot_dir = String(Game.flag("shots"))
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		_shot_times = [0.5, 3.5, 8.0, 14.0, 22.0, 32.0]
		if Game.has_flag("times"):
			_shot_times = []
			for x in String(Game.flag("times")).split(","):
				_shot_times.append(float(x))
	if Game.has_flag("nocountdown") or autopilot:
		countdown = 0.6 if autopilot else 0.0
	if autopilot:
		print("[autotest] start mode=%s time=%s rain=%s seed=%d view=%d sky=%s" % [Game.MODE_NAMES[Game.mode], Game.TIME_NAMES[Game.time_of_day], str(Game.rain), Game.run_seed, Game.view, str(sky_info.get("id", -1))])

# ------------------------------------------------------------------ rain

var rain: Rain

func _setup_rain() -> void:
	rain = Rain.new()
	rain.name = "Rain"
	add_child(rain)
	rain.setup(rider, road, self)
	rider.grip = 0.78
	CarFactory.set_wet(true)
	CarFactory.set_night(true)          # lights on in the rain
	audio.raining = true
	var rm: ShaderMaterial = road._mat_road
	rm.set_shader_parameter("wetness", 1.0)
	rm.set_shader_parameter("puddles", 1.0)
	var rt := rain.reflection_texture()
	rm.set_shader_parameter("has_reflection", rt != null)
	rm.set_shader_parameter("streak_taps", 10 if Game.quality >= 2 else 6)
	if rt:
		rm.set_shader_parameter("reflection_tex", rt)
	rider.bike.set_wet.call_deferred(true)

# ------------------------------------------------------------------ environment

## Phones have very high-DPI screens; render 3D below native resolution on lower settings.
func _apply_quality() -> void:
	var vp := get_viewport()
	match Game.quality:
		0:
			vp.scaling_3d_scale = 0.6
			vp.msaa_3d = Viewport.MSAA_DISABLED
		1:
			vp.scaling_3d_scale = 0.8
			vp.msaa_3d = Viewport.MSAA_2X
		_:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
	if Game.has_flag("shot") or Game.has_flag("shots"):
		vp.scaling_3d_scale = 1.0

func _build_environment() -> void:
	var tod := Game.time_of_day
	var we := WorldEnvironment.new()
	env = Environment.new()
	# --- sky: a cloudy panorama picked for the time of day ---
	# Rain: overcast skies (night keeps its own).
	var sky_tod := tod
	if Game.rain and tod != Game.TimeOfDay.NIGHT:
		sky_tod = Game.TimeOfDay.CLOUDY
	var sky_id := int(Game.flag("sky", str(SkyLibrary.pick(sky_tod, Game.run_seed))))
	var pano: Texture2D = load(SkyLibrary.path(sky_id))
	var info := SkyLibrary.analyze(pano)
	sky_info = info
	sky_info["id"] = sky_id
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_panorama.gdshader")
	sky_mat.set_shader_parameter("panorama", pano)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128 if Game.quality > 0 else Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = Game.quality > 0
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.08
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Game.quality > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.0
	# Rotate the panorama so its sun sits where it lights the scene nicely at the start
	# (ahead for sunsets, off to the side during the day), then aim the light at it.
	var desired_az: float
	var exposure := 1.0
	var sun_energy := 1.5
	var amb_energy := 1.05
	var min_elev := deg_to_rad(12.0)
	match tod:
		Game.TimeOfDay.SUNSET:
			desired_az = deg_to_rad(-18.0)
			sky_mat.set_shader_parameter("sun_boost", 0.6)
			exposure = 0.92
			sun_energy = 1.5
			amb_energy = 1.0
			min_elev = deg_to_rad(6.0)
		Game.TimeOfDay.NIGHT:
			desired_az = deg_to_rad(25.0)
			exposure = 0.32
			sun_energy = 0.28
			amb_energy = 0.55
			sky_mat.set_shader_parameter("star_amount", 1.0)
			sky_mat.set_shader_parameter("sun_boost", 1.0)
		Game.TimeOfDay.CLOUDY:
			desired_az = deg_to_rad(40.0)
			sun_energy = 0.95
			amb_energy = 1.45
			sun.shadow_opacity = 0.55
		_:
			desired_az = deg_to_rad(-55.0)
			exposure = 0.9
	if Game.rain:
		exposure *= 0.85 if tod != Game.TimeOfDay.NIGHT else 0.45
		sun_energy *= 0.4
		amb_energy *= 1.25
		sky_mat.set_shader_parameter("sun_boost", 0.2)
	var rot: float = desired_az - (float(info["sun_u"]) - 0.5) * TAU
	sky_mat.set_shader_parameter("rotation", rot)
	sky_mat.set_shader_parameter("exposure", exposure)
	var sun_dir := SkyLibrary.uv_to_dir(float(info["sun_u"]), float(info["sun_v"]), rot)
	# Keep the light a little above the horizon so shadows stay readable.
	var flat := Vector3(sun_dir.x, 0.0, sun_dir.z).normalized()
	var elev := clampf(asin(clampf(sun_dir.y, -1.0, 1.0)), min_elev, deg_to_rad(70.0))
	var light_dir := (flat * cos(elev) + Vector3.UP * sin(elev)).normalized()
	sun.basis = Basis.looking_at(-light_dir, Vector3.UP if absf(light_dir.y) < 0.99 else Vector3.FORWARD)
	var sc: Color = info["sun_color"]
	var scn := Color(sc.r, sc.g, sc.b) / maxf(maxf(sc.r, sc.g), maxf(sc.b, 0.001))
	sun.light_color = Color(1, 1, 1).lerp(scn, 0.55 if tod != Game.TimeOfDay.DAY else 0.3)
	sun.light_energy = sun_energy
	if tod == Game.TimeOfDay.NIGHT:
		sun.light_color = Color(0.62, 0.7, 1.0)
		sun.shadow_enabled = false
		env.glow_intensity = 0.9
		env.glow_hdr_threshold = 0.9
	env.ambient_light_energy = amb_energy
	# Fog takes the horizon colour of the panorama so the land melts into the sky.
	var hz: Color = info["horizon"]
	hz = Color(hz.r, hz.g, hz.b) * exposure
	env.fog_light_color = hz
	match tod:
		Game.TimeOfDay.NIGHT:
			env.fog_depth_begin = 30.0
			env.fog_depth_end = 650.0
		Game.TimeOfDay.CLOUDY:
			env.fog_depth_begin = 60.0
			env.fog_depth_end = 900.0
		_:
			env.fog_depth_begin = 120.0
			env.fog_depth_end = 1300.0
	sky_mat.set_shader_parameter("ground_color", Color(hz.r * 0.35, hz.g * 0.38, hz.b * 0.3))
	if Game.rain:
		# Overcast downpour: no hard shadows, close grey mist, muted colours.
		sun.shadow_enabled = false
		var grey := (hz.r + hz.g + hz.b) / 3.0
		env.fog_light_color = Color(grey, grey * 1.02, grey * 1.06).lerp(hz, 0.3) * 0.9
		env.fog_depth_begin = 8.0
		env.fog_depth_end = 320.0 if tod != Game.TimeOfDay.NIGHT else 260.0
		env.fog_depth_curve = 1.25
		env.adjustment_saturation = 0.88
		env.adjustment_contrast = 1.12
		# Wide, soft bloom so lights glow through the wet air.
		env.glow_enabled = Game.quality > 0
		env.glow_hdr_threshold = 0.8
		env.glow_intensity = 0.9
		env.glow_bloom = 0.12
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT if false else Environment.GLOW_BLEND_MODE_ADDITIVE
		for lvl in 7:
			env.set_glow_level(lvl, [0.0, 0.6, 0.8, 1.0, 1.0, 0.8, 0.5][lvl])
		env.tonemap_exposure = 1.2
		env.ambient_light_energy = amb_energy * 1.3
		# Overcast light comes from the whole sky: aim the light almost straight down, soft and neutral.
		var night_r := tod == Game.TimeOfDay.NIGHT
		sun.basis = Basis.looking_at(Vector3(0.15, -1.0, 0.25).normalized(), Vector3.FORWARD)
		sun.light_energy = 0.25 if night_r else 1.0
		sun.light_color = Color(0.86, 0.9, 1.0)
	we.environment = env
	add_child(we)
	add_child(sun)
	# Distant mountain silhouette ring that follows the camera.
	backdrop = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1400.0
	cyl.bottom_radius = 1400.0
	cyl.height = 400.0
	cyl.radial_segments = 64
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	backdrop.mesh = cyl
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/backdrop.gdshader")
	# Mountains take on the sky's horizon colour (aerial perspective).
	var far_col := hz.lerp(Color(hz.r * 0.7, hz.g * 0.78, hz.b * 0.92), 0.5)
	var near_col := hz.lerp(Color(0.18, 0.24, 0.24) * maxf(exposure, 0.15), 0.55)
	bm.set_shader_parameter("far_color", far_col)
	bm.set_shader_parameter("near_color", near_col)
	backdrop.material_override = bm
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)

func _build_sparks() -> void:
	sparks = GPUParticles3D.new()
	sparks.amount = 64
	sparks.lifetime = 0.45
	sparks.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.6, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	sparks.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.12)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.75, 0.3)
	sm.emission_enabled = true
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = sm
	sparks.draw_pass_1 = q
	add_child(sparks)

# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if paused:
		return
	var dt := minf(delta, 0.1)
	_update_slowmo(delta)
	_sim_time += dt
	Game.harness_time += dt
	# Fixed sub-steps for stable bike dynamics.
	var steps := maxi(1, ceili(dt / (1.0 / 60.0)))
	var h := dt / steps
	for i in steps:
		_step(h)
	rider.update_visuals(dt)
	if street_lights:
		street_lights.update(rider.s)
	if rain:
		rain.update(dt)
		rider.bike.set_wet_speed(clampf(rider.v / 50.0, 0.0, 1.0))
	_update_effects(dt)
	hud.refresh(dt)
	audio.update(rider, dt)
	_harness(dt)

func _step(dt: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown -= dt
			rider.throttle = 0.0
			rider.brake = 1.0
			rider.steer = 0.0
			if countdown <= 0.0:
				state = State.RIDING
				hud.show_message("GO!", 0.8)
		State.RIDING:
			run_time += dt
			_read_input(dt)
			if Game.has_flag("crashat") and run_time >= float(Game.flag("crashat")):
				rider.crash("test")
		State.CRASHED, State.OVER:
			rider.throttle = 0.0
	rider.simulate(dt)
	road.update_stream(rider.s)
	traffic.update(dt, rider.s, rider.d, rider.v)
	if state == State.RIDING:
		var hit := traffic.check_player(rider.s, rider.d, rider.v, Rider.BIKE_HALF_LEN, Rider.BIKE_HALF_W)
		if hit:
			if autopilot:
				print("[autotest] hit car ds=%.2f dd=%.2f car_d=%.2f target_d=%.2f car_v=%.1f kind=%s player_d=%.2f psi=%.3f auto_lane=%.2f" % [hit.s - rider.s, hit.d - rider.d, hit.d, hit.target_d, hit.speed, hit.kind, rider.d, rider.psi, _auto_lane])
			hit.speed *= 0.6
			rider.crash("car")
		else:
			_score(dt)
	elif state == State.CRASHED:
		if rider.crash_time > 2.2:
			_game_over()

func _read_input(dt: float) -> void:
	if autopilot:
		_autopilot()
		return
	var t := hud.throttle_input()
	var b := hud.brake_input()
	t = maxf(t, Input.get_action_strength("throttle"))
	b = maxf(b, Input.get_action_strength("brake"))
	var st := Input.get_axis("steer_left", "steer_right")
	if absf(st) < 0.01:
		st = hud.steer_input()
	# Throttle rolls on quickly but not instantly; the brake bites at once (35%) and then builds,
	# so a tap scrubs speed and a hold stops hard. Releases are near-instant.
	_thr_in = move_toward(_thr_in, t, dt * (9.0 if t > _thr_in else 14.0))
	if b > 0.0:
		_brk_in = maxf(_brk_in, minf(b, 0.35))
		_brk_in = move_toward(_brk_in, b, dt * 2.6)
	else:
		_brk_in = move_toward(_brk_in, 0.0, dt * 12.0)
	rider.throttle = _thr_in
	rider.brake = _brk_in
	rider.steer = clampf(st, -1.0, 1.0)

func _score(dt: float) -> void:
	top_speed = maxf(top_speed, rider.kmh())
	var oncoming := Game.mode == Game.Mode.TWO_WAY and rider.d < -0.3
	if oncoming:
		oncoming_time += dt
	var base := 0.0
	if rider.v > SCORE_SPEED:
		var mult := 1.0 + (rider.v - SCORE_SPEED) / 25.0
		base = rider.v * dt * 0.5 * mult
		score += base
	# Bonus streaks (each adds on top of the distance score while it lasts).
	_streak("HIGH SPEED", rider.v > HIGH_SPEED, base * 0.5, dt)
	_streak("ONCOMING", oncoming and rider.v > SCORE_SPEED, base, dt)
	_streak("WHEELIE", rider.wheelie_angle > deg_to_rad(8.0) and rider.v > 8.0, 140.0 * dt * (1.0 + rider.wheelie_angle / Rider.WHEELIE_MAX), dt)
	if combo_timer > 0.0:
		combo_timer -= dt
		if combo_timer <= 0.0:
			if combo > 1:
				hud.popup("COMBO ENDED  x%d" % combo, 1)
			combo = 0
	if Game.mode == Game.Mode.TIME_TRIAL:
		time_left -= dt
		if rider.distance >= next_checkpoint:
			var bonus := maxf(20.0, 40.0 - next_checkpoint / 2500.0 * 3.0)
			time_left += bonus
			next_checkpoint += 2500.0
			hud.show_message("CHECKPOINT  +%ds" % int(bonus), 1.6)
			if audio:
				audio.play_bonus()
		if time_left <= 0.0:
			time_left = 0.0
			state = State.CRASHED
			rider.controls_enabled = false
			rider.crash_time = 0.0
			hud.show_message("TIME UP", 2.0)
			_game_over_delayed()

## Streak bookkeeping: accumulate while active; bank with a popup when it ends (if it lasted).
func _streak(name: String, active: bool, pts: float, dt: float) -> void:
	var st: Dictionary = streaks[name]
	if active:
		st["on"] = true
		st["t"] += dt
		st["pts"] += pts
		score += pts
	elif st["on"]:
		st["on"] = false
		if st["t"] > 1.5 and st["pts"] >= 50.0:
			hud.popup("%s  %.1fs  +%d" % [name, st["t"], int(st["pts"])], 1)
			if autopilot:
				print("[autotest] bonus %s %.1fs +%d" % [name, st["t"], int(st["pts"])])
			if audio:
				audio.play_bonus()
		st["t"] = 0.0
		st["pts"] = 0.0

## The live streak to show under the score line ("" if none).
func active_streak() -> String:
	var best := ""
	var best_pts := 0.0
	for n in streaks:
		var st: Dictionary = streaks[n]
		if st["on"] and st["t"] > 0.5 and st["pts"] >= best_pts:
			best = "%s  +%d" % [n, int(st["pts"])]
			best_pts = st["pts"]
	return best

func _game_over_delayed() -> void:
	await get_tree().create_timer(1.5).timeout
	_game_over()

func _on_near_miss(clearance: float, oncoming: bool) -> void:
	if state != State.RIDING:
		return
	near_misses += 1
	combo = mini(combo + 1, COMBO_MAX) if combo_timer > 0.0 else 1
	combo_timer = COMBO_WINDOW
	var close := clearance < 0.45
	# Faster and closer pays more; oncoming doubles; the combo multiplies.
	var speed_f := clampf(rider.v / 27.8, 0.8, 2.6)
	var pts := int(NEAR_MISS_POINTS * speed_f * (1.6 if close else 1.0) * (2.0 if oncoming else 1.0) * combo)
	score += pts
	var label := "CLOSE CALL" if close else "NEAR MISS"
	if oncoming:
		label = "ONCOMING " + label
	hud.popup("%s  +%d" % [label, pts], combo)
	hud.combo_flash()
	if autopilot:
		print("[autotest] %s clear=%.2f kmh=%.0f combo=%d +%d" % [label, clearance, rider.kmh(), combo, pts])
	Input.vibrate_handheld(45 if close else 25, 0.9 if close else 0.5)
	rider.kick_fov(4.5 if close else 2.5)
	if audio:
		audio.play_whoosh(rider.v)
		if randf() < 0.45:
			audio.play_horn()
	if Game.mode == Game.Mode.TIME_TRIAL:
		time_left += 1.0

## Ordinary close pass: a softer whoosh, and it keeps a running combo alive.
func _on_passed(clearance: float, rel_speed: float, oncoming: bool) -> void:
	if state != State.RIDING:
		return
	if combo > 0:
		combo_timer = maxf(combo_timer, COMBO_WINDOW * 0.6)
	if audio:
		audio.play_whoosh(rel_speed, -13.0 + (PASS_LOUD - clearance) * 2.0)

const PASS_LOUD := 2.8

func _on_honk(distance: float) -> void:
	if state == State.RIDING and audio:
		audio.play_horn(clampf(-4.0 - distance * 0.12, -18.0, -4.0))

func _on_gear(g: int) -> void:
	if audio:
		audio.on_shift(g)
	if state == State.RIDING and g > 1:
		Input.vibrate_handheld(12, 0.35)

func _on_crash(reason: String) -> void:
	state = State.CRASHED
	if audio:
		audio.play_crash()
	sparks.emitting = true
	Input.vibrate_handheld(300, 1.0)
	hud.show_message("CRASHED", 2.0)
	hud.show_retry(true)
	# Slow motion at the moment of impact, easing back to real time (see _update_slowmo).
	if not autopilot:
		_slowmo_t = 0.0
		Engine.time_scale = 0.25
	if autopilot:
		_crash_count += 1
		print("[autotest] crash reason=%s t=%.1f s=%.0f kmh=%.0f score=%d" % [reason, run_time, rider.s, rider.kmh(), int(score)])

func _update_slowmo(delta: float) -> void:
	if _slowmo_t < 0.0:
		return
	_slowmo_t += delta / maxf(Engine.time_scale, 0.01)      # real time
	Engine.time_scale = lerpf(0.25, 1.0, smoothstep(0.45, 1.6, _slowmo_t))
	if _slowmo_t > 1.6:
		Engine.time_scale = 1.0
		_slowmo_t = -1.0

func _game_over() -> void:
	if state == State.OVER:
		return
	state = State.OVER
	_slowmo_t = -1.0
	Engine.time_scale = 1.0
	hud.show_retry(false)
	var earned := int(score / 25.0) + near_misses * 5
	var is_best := Game.submit_run(Game.mode, int(score), rider.distance, earned)
	hud.show_game_over(int(score), rider.distance, top_speed, near_misses, earned, is_best)
	if autopilot:
		print("[autotest] game_over score=%d dist=%.0f top=%.0f near=%d earned=%d best=%s" % [int(score), rider.distance, top_speed, near_misses, earned, str(is_best)])
		if _until <= 0.0 or Game.harness_time < _until:
			await get_tree().create_timer(1.0).timeout
			if not _quitting:
				restart()

func _update_effects(dt: float) -> void:
	var cam := rider.camera.global_position
	backdrop.global_position = Vector3(cam.x, road.center_at(rider.s).y + 120.0, cam.z)
	if rider.scrape > 0.5:
		var t := rider.bike.global_transform
		var side := signf(rider.d) if not rider.is_crashed else 0.0
		sparks.global_transform = Transform3D(t.basis, t.origin + t.basis.x * side * 0.45 + Vector3.UP * 0.2)
		sparks.emitting = true
	elif not rider.is_crashed or rider.crash_time > 1.5:
		sparks.emitting = false
	if sun.shadow_enabled:
		# Keep the shadow-casting light tracking the player (directional, so only orientation matters).
		pass

# ------------------------------------------------------------------ flow

func is_riding() -> bool:
	return state == State.RIDING

func is_countdown() -> bool:
	return state == State.COUNTDOWN

func set_paused(p: bool) -> void:
	paused = p
	get_tree().paused = false
	if audio:
		audio.set_paused(p)

func restart() -> void:
	Engine.time_scale = 1.0
	Game.run_seed = randi() % 100000
	get_tree().reload_current_scene()

func quit_to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _unhandled_input(e: InputEvent) -> void:
	if false:
		pass
	elif e.is_action_pressed("pause") and state == State.RIDING:
		hud.toggle_pause()

# ------------------------------------------------------------------ autopilot & test harness

func _autopilot() -> void:
	var lanes := [-1.5, -0.5, 0.5, 1.5]
	var best_d := _auto_lane
	var best_score := -1e9
	for l in lanes:
		var ld: float = l * Road.LANE_W
		var gap := traffic.gap_ahead(rider.s, ld, 0.9)
		var closing := traffic.closing_speed_ahead(rider.s, ld, 0.9, rider.v)
		var ttc := (gap - closing * closing / 16.0) / maxf(closing, 1.0)
		var sc := minf(ttc, 8.0) - absf(ld - rider.d) * 0.25
		if traffic.occupied(rider.s + 2.0, rider.s + 8.0 + rider.v * 0.8, ld, 0.6):
			sc -= 10.0
		if absf(ld - _auto_lane) < 0.1:
			sc += 0.8
		# Path to the lane must be clear right next to us.
		var mid := (ld + rider.d) * 0.5
		if absf(ld - rider.d) > 1.0 and traffic.occupied(rider.s - 4.0, rider.s + 6.0 + rider.v * 0.6, mid, absf(ld - rider.d) * 0.5 + 0.4):
			sc -= 20.0
		if sc > best_score:
			best_score = sc
			best_d = ld
	_auto_lane = best_d
	var aim := _auto_lane
	if Game.has_flag("risky"):
		# Test rider who passes close: ride near the lane line on the road-centre side.
		aim -= signf(_auto_lane) * 1.15
	var err := aim - rider.d
	rider.steer = clampf(err * 0.55, -1.0, 1.0)
	var gap_here := traffic.gap_ahead(rider.s, rider.d, 0.7)
	var closing_here := traffic.closing_speed_ahead(rider.s, rider.d, 0.7, rider.v)
	var need := closing_here * closing_here / (14.0 * rider.grip) + closing_here * 0.6 + 8.0
	var limit := 58.0
	# Slow for tight bends.
	var k := absf(road.curvature_at(rider.s + rider.v * 1.5))
	if k > 0.0001:
		limit = minf(limit, sqrt(G_LAT / k))
	if gap_here < need and closing_here > 0.0:
		rider.throttle = 0.0
		rider.brake = clampf((need - gap_here) / need * 3.0, 0.5, 1.0)
	elif rider.v > limit:
		rider.throttle = 0.0
		rider.brake = 0.3
	else:
		rider.throttle = 1.0
		rider.brake = 0.0

const G_LAT := 7.5

func _harness(dt: float) -> void:
	if not (autopilot or _shot_path != "" or _shot_dir != ""):
		return
	_auto_log_t += dt
	_max_lean = maxf(_max_lean, absf(rider.lean))
	_max_k = maxf(_max_k, absf(road.curvature_at(rider.s)))
	if Game.has_flag("autotest") and _auto_log_t >= 5.0:
		_auto_log_t = 0.0
		_auto_stage += 1
		var ml := _max_lean
		var mk := _max_k
		_max_lean = 0.0
		_max_k = 0.0
		print("[autotest] stage=%d t=%.1f state=%d s=%.0f d=%.2f kmh=%.0f gear=%d rpm=%.0f lean=%.1f maxlean=%.0f minR=%.0f score=%d near=%d cars=%d chunks=%d fps=%.0f knee=%.2f" % [
			_auto_stage, _sim_time, state, rider.s, rider.d, rider.kmh(), rider.gear, rider.rpm,
			rad_to_deg(rider.lean), rad_to_deg(ml), 1.0 / maxf(mk, 1e-5), int(score), near_misses, traffic.cars.size(), road.chunk_count(), Engine.get_frames_per_second(), rider.knee_min_h])
		rider.knee_min_h = 9.0
	if _shot_path != "" and _sim_time >= _shot_at:
		var p := _shot_path
		_shot_path = ""
		await Game.save_shot(p)
		_quit()
		return
	if _shot_dir != "" and not _shot_times.is_empty() and _sim_time >= float(_shot_times[0]):
		var t: float = _shot_times.pop_front()
		await Game.save_shot("%s/t%05.1f.png" % [_shot_dir, t])
		if _shot_times.is_empty():
			_quit()
			return
	if _until > 0.0 and Game.harness_time >= _until and not _quitting:
		print("[autotest] done total_t=%.1f s=%.0f score=%d near=%d crashes=%d top=%.0f" % [Game.harness_time, rider.s, int(score), near_misses, _crash_count, top_speed])
		_quit()

func _quit() -> void:
	_quitting = true
	get_tree().quit()
