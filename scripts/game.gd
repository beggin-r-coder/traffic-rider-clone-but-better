extends Node
## Global state: settings, save data, run configuration and dev/test flags.

const SAVE_PATH := "user://save.cfg"

enum Mode { ONE_WAY, TWO_WAY, TIME_TRIAL }
enum View { FIRST_PERSON, CHASE }
enum Steering { TILT, TOUCH }
enum TimeOfDay { DAY, SUNSET, NIGHT, CLOUDY }

const MODE_NAMES := ["One-Way", "Two-Way", "Time Trial"]
const TIME_NAMES := ["Day", "Sunset", "Night", "Cloudy"]

# --- settings (persisted) ---
var steering: int = Steering.TILT
var view: int = View.FIRST_PERSON
var tilt_sensitivity: float = 1.0
var button_sensitivity: float = 1.0   # on-screen steering buttons: how hard/fast they steer
# Cockpit camera (POV) adjustments
var cam_height: float = 0.0           # metres, + = higher
var cam_forward: float = 0.0          # metres, + = closer to the bars
var cam_fov: float = 60.0             # degrees
var cam_pitch: float = -11.0          # degrees, negative = looking down
var helmet_view: bool = false     # helmet visor frame over the cockpit view
var assist: bool = true            # steering assist: auto-lean through road curves
var sfx_volume: float = 0.9
var quality: int = 1               # 0 low, 1 medium, 2 high

# --- progress (persisted) ---
var best_scores := {}              # mode(int) -> score
var best_distance := 0.0
var cash := 0
var bike_color := 0
var bike := 0                      # index into BikeDefs.LIST
var owned_bikes: Array = [0]
var upgrades := {"engine": 0, "brakes": 0, "handling": 0}
const UPGRADE_MAX := 5
const UPGRADE_INFO := {
	"engine": ["Engine", "+power, +top speed"],
	"brakes": ["Brakes", "shorter stopping"],
	"handling": ["Handling", "quicker lean & tighter lines"],
}

# --- per-run configuration ---
var mode: int = Mode.ONE_WAY
var time_of_day: int = TimeOfDay.DAY
var rain := false
var run_seed: int = 0

# --- dev flags (passed after `--` on the command line) ---
var flags := {}
var harness_time := 0.0   # total simulated time across restarts (for --until)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
			var eq := s.find("=")
			if eq >= 0:
				flags[s.substr(0, eq)] = s.substr(eq + 1)
			else:
				flags[s] = true
	if not has_flag("fresh"):
		load_save()
	if has_flag("mode"):
		mode = int(flag("mode", "0"))
	if has_flag("time"):
		var t := String(flag("time", "day"))
		time_of_day = maxi(0, ["day", "sunset", "night", "cloudy"].find(t))
	if has_flag("rain"):
		rain = str(flag("rain", "1")) not in ["0", "false"]
	view = View.FIRST_PERSON   # chase cam disabled for now (dev flag --view=chase still works)
	if has_flag("view"):
		view = View.CHASE if flag("view", "fp") == "chase" else View.FIRST_PERSON
	if has_flag("touch"):
		steering = Steering.TOUCH
	if has_flag("cash"):
		cash = int(flag("cash", "0"))
	if has_flag("bike"):
		var bf := String(flag("bike", "0"))
		bike = int(bf) if bf.is_valid_int() else maxi(0, ["r1", "h2", "zx6r"].find(bf))
	if has_flag("paint"):
		bike_color = int(flag("paint", "0"))
	if has_flag("helmet"):
		helmet_view = true
	if has_flag("quality"):
		quality = int(flag("quality", "1"))
	run_seed = int(flag("seed", str(randi() % 100000)))
	if has_flag("fps"):
		Engine.max_fps = int(flag("fps", "60"))
	if has_flag("posetest"):
		return
	if has_flag("bake-grass"):
		var gb = load("res://scripts/tools/impostor_baker.gd").new()
		add_child(gb)
		gb.run_grass.call_deferred(String(flag("bake-grass")))
		return
	if has_flag("bake-vegetation"):
		var baker = load("res://scripts/tools/impostor_baker.gd").new()
		add_child(baker)
		baker.run.call_deferred(String(flag("bake-vegetation")))
		return
	if has_flag("dyntest"):
		_dyn_test.call_deferred()
		return
	if has_flag("audiotest"):
		BikeAudio.self_test()
		get_tree().quit()
		return
	if has_flag("bake-audio"):
		BikeAudio.bake_all()
		get_tree().quit()
		return
	# Start straight into the game for test runs.
	if has_flag("game") or has_flag("autotest"):
		call_deferred("_goto_game_from_flags")
	elif (has_flag("shot") or has_flag("shots")) and not has_flag("menu"):
		call_deferred("_goto_game_from_flags")

func _goto_game_from_flags() -> void:
	if get_tree().current_scene and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn":
		get_tree().change_scene_to_file("res://scenes/game.tscn")

func has_flag(n: String) -> bool:
	return flags.has(n)

func flag(n: String, def = null):
	return flags.get(n, def)

func best_score(m: int) -> int:
	return int(best_scores.get(m, 0))

func submit_run(m: int, score: int, distance: float, earned: int) -> bool:
	var is_best := score > best_score(m)
	if is_best:
		best_scores[m] = score
	best_distance = maxf(best_distance, distance)
	cash += earned
	save()
	return is_best

func upgrade_level(kind: String) -> int:
	return int(upgrades.get(kind, 0))

func upgrade_cost(kind: String) -> int:
	return int(round(400.0 * pow(upgrade_level(kind) + 1.0, 1.7) / 10.0)) * 10

func buy_upgrade(kind: String) -> bool:
	var lvl := upgrade_level(kind)
	var cost := upgrade_cost(kind)
	if lvl >= UPGRADE_MAX or cash < cost:
		return false
	cash -= cost
	upgrades[kind] = lvl + 1
	save()
	return true

func save() -> void:
	if has_flag("nosave"):
		return
	var c := ConfigFile.new()
	c.set_value("settings", "steering", steering)
	c.set_value("settings", "view", view)
	c.set_value("settings", "tilt_sensitivity", tilt_sensitivity)
	c.set_value("settings", "cam_pitch", cam_pitch)
	c.set_value("settings", "cam_fov", cam_fov)
	c.set_value("settings", "cam_forward", cam_forward)
	c.set_value("settings", "cam_height", cam_height)
	c.set_value("settings", "button_sensitivity", button_sensitivity)
	c.set_value("settings", "assist", assist)
	c.set_value("settings", "helmet_view", helmet_view)
	c.set_value("settings", "sfx_volume", sfx_volume)
	c.set_value("settings", "quality", quality)
	c.set_value("progress", "best_scores", best_scores)
	c.set_value("progress", "best_distance", best_distance)
	c.set_value("progress", "cash", cash)
	c.set_value("progress", "bike_color", bike_color)
	c.set_value("progress", "upgrades", upgrades)
	c.set_value("progress", "bike", bike)
	c.set_value("progress", "owned_bikes", owned_bikes)
	c.set_value("run", "mode", mode)
	c.set_value("run", "time_of_day", time_of_day)
	c.set_value("run", "rain", rain)
	c.save(SAVE_PATH)

func load_save() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	steering = c.get_value("settings", "steering", steering)
	view = c.get_value("settings", "view", view)
	tilt_sensitivity = c.get_value("settings", "tilt_sensitivity", tilt_sensitivity)
	cam_pitch = c.get_value("settings", "cam_pitch", cam_pitch)
	cam_fov = c.get_value("settings", "cam_fov", cam_fov)
	cam_forward = c.get_value("settings", "cam_forward", cam_forward)
	cam_height = c.get_value("settings", "cam_height", cam_height)
	button_sensitivity = c.get_value("settings", "button_sensitivity", button_sensitivity)
	assist = c.get_value("settings", "assist", assist)
	helmet_view = c.get_value("settings", "helmet_view", helmet_view)
	sfx_volume = c.get_value("settings", "sfx_volume", sfx_volume)
	quality = c.get_value("settings", "quality", quality)
	best_scores = c.get_value("progress", "best_scores", {})
	best_distance = c.get_value("progress", "best_distance", 0.0)
	cash = c.get_value("progress", "cash", 0)
	bike_color = c.get_value("progress", "bike_color", 0)
	bike = c.get_value("progress", "bike", 0)
	owned_bikes = c.get_value("progress", "owned_bikes", [0])
	if not bike in owned_bikes:
		bike = 0
	var up: Dictionary = c.get_value("progress", "upgrades", {})
	for k in up:
		upgrades[k] = int(up[k])
	mode = c.get_value("run", "mode", mode)
	time_of_day = c.get_value("run", "time_of_day", time_of_day)
	rain = c.get_value("run", "rain", rain)

func _start_pose_test() -> void:
	print("[posetest] starting")
	# Replace the menu with the pose-test scene.
	var pt: Node3D = load("res://scripts/tools/pose_test.gd").new()
	get_tree().root.add_child(pt)
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	get_tree().current_scene = pt
	pt.call("run", String(flag("posetest")))

## Prints the bike's response to a steering step at 150 km/h (--dyntest [--pro]).
func _dyn_test() -> void:
	var road := Road.new()
	add_child(road)
	road.setup(1, false, false)
	var r := Rider.new()
	add_child(r)
	r.road = road
	r.assist = not has_flag("pro")
	r.v = float(flag("kmh", "150")) / 3.6
	r.gear = 4
	r.d = 1.8
	var dt := 1.0 / 60.0
	var t := 0.0
	print("[dyn] assist=", r.assist, " v=", r.kmh())
	while t < 3.0:
		if r.assist:
			r.steer = 1.0 if t < 0.6 else 0.0
		else:
			r.steer = 0.5 if t < 0.45 else (-0.5 if t < 0.8 else 0.0)
		r.throttle = 0.5
		r.simulate(dt)
		if int(round(t * 60.0)) % 6 == 0:
			print("[dyn] t=%.1f steer=%+.1f lean=%+5.1f psi=%+5.2f d=%5.2f kmh=%.0f" % [t, r.steer, rad_to_deg(r.lean), rad_to_deg(r.psi), r.d, r.kmh()])
		t += dt
	get_tree().quit()

## Saves a screenshot of the main viewport.
func save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] saved ", path)
