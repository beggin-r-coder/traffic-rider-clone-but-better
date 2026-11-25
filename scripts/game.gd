extends Node
## Global state: settings, save data, run configuration and dev/test flags.

const SAVE_PATH := "user://save.cfg"

enum Mode { ONE_WAY, TWO_WAY, TIME_TRIAL }
enum View { FIRST_PERSON, CHASE }
enum Steering { TILT, TOUCH }
enum TimeOfDay { DAY, SUNSET, NIGHT }

const MODE_NAMES := ["One-Way", "Two-Way", "Time Trial"]
const TIME_NAMES := ["Day", "Sunset", "Night"]

# --- settings (persisted) ---
var steering: int = Steering.TILT
var view: int = View.FIRST_PERSON
var tilt_sensitivity: float = 1.0
var assist: bool = true            # steering assist: auto-lean through road curves
var sfx_volume: float = 0.9
var quality: int = 1               # 0 low, 1 medium, 2 high

# --- progress (persisted) ---
var best_scores := {}              # mode(int) -> score
var best_distance := 0.0
var cash := 0
var bike_color := 0

# --- per-run configuration ---
var mode: int = Mode.ONE_WAY
var time_of_day: int = TimeOfDay.DAY
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
		time_of_day = maxi(0, ["day", "sunset", "night"].find(t))
	if has_flag("view"):
		view = View.CHASE if flag("view", "fp") == "chase" else View.FIRST_PERSON
	if has_flag("touch"):
		steering = Steering.TOUCH
	if has_flag("quality"):
		quality = int(flag("quality", "1"))
	run_seed = int(flag("seed", str(randi() % 100000)))
	if has_flag("fps"):
		Engine.max_fps = int(flag("fps", "60"))
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

func save() -> void:
	if has_flag("nosave"):
		return
	var c := ConfigFile.new()
	c.set_value("settings", "steering", steering)
	c.set_value("settings", "view", view)
	c.set_value("settings", "tilt_sensitivity", tilt_sensitivity)
	c.set_value("settings", "assist", assist)
	c.set_value("settings", "sfx_volume", sfx_volume)
	c.set_value("settings", "quality", quality)
	c.set_value("progress", "best_scores", best_scores)
	c.set_value("progress", "best_distance", best_distance)
	c.set_value("progress", "cash", cash)
	c.set_value("progress", "bike_color", bike_color)
	c.set_value("run", "mode", mode)
	c.set_value("run", "time_of_day", time_of_day)
	c.save(SAVE_PATH)

func load_save() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	steering = c.get_value("settings", "steering", steering)
	view = c.get_value("settings", "view", view)
	tilt_sensitivity = c.get_value("settings", "tilt_sensitivity", tilt_sensitivity)
	assist = c.get_value("settings", "assist", assist)
	sfx_volume = c.get_value("settings", "sfx_volume", sfx_volume)
	quality = c.get_value("settings", "quality", quality)
	best_scores = c.get_value("progress", "best_scores", {})
	best_distance = c.get_value("progress", "best_distance", 0.0)
	cash = c.get_value("progress", "cash", 0)
	bike_color = c.get_value("progress", "bike_color", 0)
	mode = c.get_value("run", "mode", mode)
	time_of_day = c.get_value("run", "time_of_day", time_of_day)

## Saves a screenshot of the main viewport.
func save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] saved ", path)
