extends Node3D
## Main gameplay scene: builds the world, runs the simulation loop, scoring and game flow.
## Also hosts the autopilot used by the --autotest / --shot dev flags.

enum State { COUNTDOWN, RIDING, CRASHED, OVER }

const SCORE_SPEED := 100.0 / 3.6       # score only accrues above 100 km/h
const NEAR_MISS_POINTS := 300
const COMBO_WINDOW := 4.0

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
	road.setup(Game.run_seed, two_way, night)
	traffic = Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(road, Game.run_seed, two_way, night)
	traffic.near_miss.connect(_on_near_miss)
	rider = Rider.new()
	rider.name = "Rider"
	add_child(rider)
	rider.road = road
	rider.assist = Game.assist
	rider.reset_at(4.0, Road.LANE_W * 0.5)
	rider.set_view(Game.view)
	rider.crashed.connect(_on_crash)
	rider.gear_changed.connect(func(g): if audio: audio.on_shift(g))
	if night:
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
	audio = BikeAudio.new()
	audio.name = "Audio"
	add_child(audio)
	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)
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
		print("[autotest] start mode=%s time=%s seed=%d view=%d" % [Game.MODE_NAMES[Game.mode], Game.TIME_NAMES[Game.time_of_day], Game.run_seed, Game.view])

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
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
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
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.1
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Game.quality > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.0
	match tod:
		Game.TimeOfDay.DAY:
			sky_mat.sky_top_color = Color(0.12, 0.33, 0.72)
			sky_mat.sky_horizon_color = Color(0.6, 0.74, 0.9)
			sky_mat.sky_curve = 0.12
			sky_mat.ground_horizon_color = Color(0.6, 0.74, 0.9)
			sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.3)
			sky_mat.sun_angle_max = 20.0
			sun.light_color = Color(1.0, 0.96, 0.88)
			sun.light_energy = 1.45
			sun.rotation_degrees = Vector3(-38, -150, 0)
			env.ambient_light_energy = 1.0
			env.ambient_light_sky_contribution = 0.75
			env.ambient_light_color = Color(0.75, 0.78, 0.8)
			env.fog_light_color = Color(0.64, 0.75, 0.88)
			env.fog_depth_begin = 120.0
			env.fog_depth_end = 1300.0
		Game.TimeOfDay.SUNSET:
			var ss := ShaderMaterial.new()
			ss.shader = preload("res://shaders/sunset_sky.gdshader")
			ss.set_shader_parameter("top_color", Color(0.1, 0.13, 0.34))
			ss.set_shader_parameter("mid_color", Color(0.55, 0.36, 0.52))
			ss.set_shader_parameter("horizon_color", Color(1.0, 0.56, 0.3))
			ss.set_shader_parameter("ground_color", Color(0.12, 0.1, 0.12))
			ss.set_shader_parameter("glow_color", Color(1.0, 0.62, 0.3))
			sky.sky_material = ss
			sun.light_color = Color(1.0, 0.6, 0.32)
			sun.light_energy = 1.6
			sun.rotation_degrees = Vector3(-7, 160, 0)
			env.ambient_light_energy = 0.9
			env.ambient_light_sky_contribution = 0.6
			env.ambient_light_color = Color(0.55, 0.5, 0.6)
			env.fog_light_color = Color(0.8, 0.5, 0.42)
			env.fog_depth_begin = 160.0
			env.fog_depth_end = 1200.0
		Game.TimeOfDay.NIGHT:
			var ns := ShaderMaterial.new()
			ns.shader = preload("res://shaders/night_sky.gdshader")
			ns.set_shader_parameter("top_color", Color(0.008, 0.012, 0.04))
			ns.set_shader_parameter("horizon_color", Color(0.06, 0.08, 0.15))
			sky.sky_material = ns
			sun.light_color = Color(0.6, 0.7, 1.0)
			sun.light_energy = 0.3
			sun.rotation_degrees = Vector3(-35, 150, 0)
			sun.shadow_enabled = false
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.16, 0.2, 0.32)
			env.ambient_light_energy = 1.0
			env.fog_light_color = Color(0.05, 0.065, 0.12)
			env.fog_depth_begin = 30.0
			env.fog_depth_end = 650.0
			env.glow_intensity = 0.9
			env.glow_hdr_threshold = 0.9
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
	var far_col: Color
	var near_col: Color
	match tod:
		Game.TimeOfDay.SUNSET:
			far_col = Color(0.62, 0.38, 0.38)
			near_col = Color(0.32, 0.2, 0.25)
		Game.TimeOfDay.NIGHT:
			far_col = Color(0.03, 0.04, 0.07)
			near_col = Color(0.015, 0.02, 0.035)
		_:
			far_col = Color(0.55, 0.64, 0.74)
			near_col = Color(0.36, 0.45, 0.5)
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
	_sim_time += dt
	Game.harness_time += dt
	# Fixed sub-steps for stable bike dynamics.
	var steps := maxi(1, ceili(dt / (1.0 / 60.0)))
	var h := dt / steps
	for i in steps:
		_step(h)
	rider.update_visuals(dt)
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
			_read_input()
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

func _read_input() -> void:
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
	rider.throttle = t
	rider.brake = b
	rider.steer = clampf(st, -1.0, 1.0)

func _score(dt: float) -> void:
	top_speed = maxf(top_speed, rider.kmh())
	var oncoming := Game.mode == Game.Mode.TWO_WAY and rider.d < -0.3
	if oncoming:
		oncoming_time += dt
	if rider.v > SCORE_SPEED:
		var mult := 1.0 + (rider.v - SCORE_SPEED) / 25.0
		if oncoming:
			mult *= 2.0
		score += rider.v * dt * 0.5 * mult
	if combo_timer > 0.0:
		combo_timer -= dt
		if combo_timer <= 0.0:
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

func _game_over_delayed() -> void:
	await get_tree().create_timer(1.5).timeout
	_game_over()

func _on_near_miss(clearance: float, oncoming: bool) -> void:
	if state != State.RIDING:
		return
	near_misses += 1
	combo = combo + 1 if combo_timer > 0.0 else 1
	combo_timer = COMBO_WINDOW
	var pts := int(NEAR_MISS_POINTS * (1.0 + (1.0 - clearance) * 0.6) * (2.0 if oncoming else 1.0) * combo)
	score += pts
	var label := "CLOSE CALL" if clearance < 0.35 else "NEAR MISS"
	if oncoming:
		label = "ONCOMING " + label
	hud.popup("%s  +%d" % [label, pts], combo)
	Input.vibrate_handheld(25)
	if audio:
		audio.play_whoosh(rider.v)
		if randf() < 0.45:
			audio.play_horn()
	if Game.mode == Game.Mode.TIME_TRIAL:
		time_left += 1.0

func _on_crash(reason: String) -> void:
	state = State.CRASHED
	if audio:
		audio.play_crash()
	sparks.emitting = true
	Input.vibrate_handheld(250)
	hud.show_message("CRASHED", 2.0)
	Engine.time_scale = 0.45 if not autopilot else 1.0
	get_tree().create_timer(0.6, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
	if autopilot:
		_crash_count += 1
		print("[autotest] crash reason=%s t=%.1f s=%.0f kmh=%.0f score=%d" % [reason, run_time, rider.s, rider.kmh(), int(score)])

func _game_over() -> void:
	if state == State.OVER:
		return
	state = State.OVER
	Engine.time_scale = 1.0
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
	if e.is_action_pressed("change_view"):
		Game.view = Game.View.CHASE if Game.view == Game.View.FIRST_PERSON else Game.View.FIRST_PERSON
		rider.set_view(Game.view)
		Game.save()
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
	var err := _auto_lane - rider.d
	rider.steer = clampf(err * 0.55, -1.0, 1.0)
	var gap_here := traffic.gap_ahead(rider.s, rider.d, 0.7)
	var closing_here := traffic.closing_speed_ahead(rider.s, rider.d, 0.7, rider.v)
	var need := closing_here * closing_here / 14.0 + closing_here * 0.6 + 8.0
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
		print("[autotest] stage=%d t=%.1f state=%d s=%.0f d=%.2f kmh=%.0f gear=%d rpm=%.0f lean=%.1f maxlean=%.0f minR=%.0f score=%d near=%d cars=%d chunks=%d fps=%.0f" % [
			_auto_stage, _sim_time, state, rider.s, rider.d, rider.kmh(), rider.gear, rider.rpm,
			rad_to_deg(rider.lean), rad_to_deg(ml), 1.0 / maxf(mk, 1e-5), int(score), near_misses, traffic.cars.size(), road.chunk_count(), Engine.get_frames_per_second()])
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
