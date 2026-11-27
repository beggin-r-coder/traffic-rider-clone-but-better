extends CanvasLayer
class_name Hud
## In-game HUD and touch controls (pedals, optional steering buttons, tilt steering).

const ACCENT := Color(1.0, 0.7, 0.12)
const RED := Color(0.95, 0.22, 0.18)
const PANEL := Color(0.04, 0.05, 0.07, 0.62)

var world  # game_world.gd
var root: Control
var score_lbl: Label
var dist_lbl: Label
var info_lbl: Label
var combo_lbl: Label
var msg_lbl: Label
var popup_box: VBoxContainer
var speed_lbl: Label
var pedal_gas: Pedal
var pedal_brake: Pedal
var steer_l: Pedal
var steer_r: Pedal
var pause_btn: Button
var pause_panel: Control
var over_panel: Control
var _msg_t := 0.0
var _touches := {}      # index -> zone name
var _tilt_neutral := 0.0
var _tilt_smooth := 0.0
var _btn_steer := 0.0
var _font: Font
var speed_fx: ColorRect

func setup(w) -> void:
	world = w
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_font = ThemeDB.fallback_font
	speed_fx = ColorRect.new()
	speed_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/speed_lines.gdshader")
	speed_fx.material = sm
	root.add_child(speed_fx)

	# --- top-left: score ---
	var tl := _panel(Vector2(18, 14), Vector2(270, 84))
	score_lbl = _label("0", 40, Color.WHITE)
	score_lbl.position = Vector2(16, 2)
	tl.add_child(score_lbl)
	dist_lbl = _label("0.00 km", 20, Color(0.8, 0.84, 0.9))
	dist_lbl.position = Vector2(18, 50)
	tl.add_child(dist_lbl)

	# --- top-center: mode info ---
	info_lbl = _label("", 30, Color.WHITE)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info_lbl.position = Vector2(-200, 18)
	info_lbl.size = Vector2(400, 44)
	root.add_child(info_lbl)
	combo_lbl = _label("", 24, ACCENT)
	combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	combo_lbl.position = Vector2(-200, 58)
	combo_lbl.size = Vector2(400, 34)
	root.add_child(combo_lbl)

	# --- popups (near misses) ---
	popup_box = VBoxContainer.new()
	popup_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	popup_box.position = Vector2(-300, 120)
	popup_box.size = Vector2(600, 200)
	popup_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	popup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(popup_box)

	# --- big centre message ---
	msg_lbl = _label("", 84, Color.WHITE)
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_lbl.set_anchors_preset(Control.PRESET_CENTER)
	msg_lbl.position = Vector2(-400, -150)
	msg_lbl.size = Vector2(800, 140)
	msg_lbl.add_theme_constant_override("outline_size", 14)
	root.add_child(msg_lbl)

	# --- compact speed readout (chase view only; in first person the bike's own dash shows it) ---
	speed_lbl = _label("", 30, Color.WHITE)
	speed_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_lbl.position = Vector2(-430, 26)
	speed_lbl.size = Vector2(320, 44)
	root.add_child(speed_lbl)

	# --- pedals / steering buttons ---
	pedal_gas = Pedal.new()
	pedal_gas.kind = "gas"
	root.add_child(pedal_gas)
	pedal_brake = Pedal.new()
	pedal_brake.kind = "brake"
	root.add_child(pedal_brake)
	steer_l = Pedal.new()
	steer_l.kind = "left"
	root.add_child(steer_l)
	steer_r = Pedal.new()
	steer_r.kind = "right"
	root.add_child(steer_r)
	_layout_controls()
	get_viewport().size_changed.connect(_layout_controls)

	# --- pause button ---
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.add_theme_font_size_override("font_size", 30)
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(-92, 16)
	pause_btn.size = Vector2(74, 64)
	pause_btn.focus_mode = Control.FOCUS_NONE
	_style_button(pause_btn, PANEL)
	pause_btn.pressed.connect(toggle_pause)
	root.add_child(pause_btn)

	_tilt_neutral = _raw_tilt()
	show_message("3", 1.0)

func _layout_controls() -> void:
	var vs := root.get_viewport_rect().size
	var touch := Game.steering == Game.Steering.TOUCH
	var pw := 150.0
	var ph := 210.0
	pedal_gas.position = Vector2(vs.x - pw - 26, vs.y - ph - 22)
	pedal_gas.size = Vector2(pw, ph)
	if touch:
		pedal_brake.position = Vector2(vs.x - pw * 2 - 44, vs.y - ph * 0.72 - 22)
		pedal_brake.size = Vector2(pw * 0.9, ph * 0.72)
		steer_l.visible = true
		steer_r.visible = true
		steer_l.position = Vector2(26, vs.y - 170)
		steer_l.size = Vector2(140, 148)
		steer_r.position = Vector2(184, vs.y - 170)
		steer_r.size = Vector2(140, 148)
	else:
		pedal_brake.position = Vector2(26, vs.y - ph * 0.8 - 22)
		pedal_brake.size = Vector2(pw, ph * 0.8)
		steer_l.visible = false
		steer_r.visible = false

func _panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	return p

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _style_button(b: Button, bg: Color) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg if st != "pressed" else bg.lightened(0.2)
		if st == "hover":
			sb.bg_color = bg.lightened(0.08)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		if st == "focus":
			sb.draw_center = false
			sb.border_color = Color(1, 1, 1, 0.0)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)

# ------------------------------------------------------------------ input

func _input(e: InputEvent) -> void:
	if (pause_panel and pause_panel.visible) or (over_panel and over_panel.visible):
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			var z := _zone_at(e.position)
			if z != "":
				_touches[e.index] = z
				get_viewport().set_input_as_handled()
		else:
			_touches.erase(e.index)
	elif e is InputEventScreenDrag:
		if _touches.has(e.index):
			var z := _zone_at(e.position)
			if z != "":
				_touches[e.index] = z

func _zone_at(p: Vector2) -> String:
	for pd in [pedal_gas, pedal_brake, steer_l, steer_r]:
		if pd.visible and pd.get_global_rect().grow(18).has_point(p):
			return pd.kind
	return ""

func _held(kind: String) -> bool:
	return _touches.values().has(kind)

func throttle_input() -> float:
	return 1.0 if _held("gas") else 0.0

func brake_input() -> float:
	return 1.0 if _held("brake") else 0.0

func _raw_tilt() -> float:
	var a := Input.get_accelerometer()
	if a == Vector3.ZERO:
		return 0.0
	# Landscape: steering-wheel style tilt shows up on the device's long (y) axis.
	var t := atan2(a.y, sqrt(a.x * a.x + a.z * a.z))
	if DisplayServer.screen_get_orientation() == DisplayServer.SCREEN_REVERSE_LANDSCAPE:
		t = -t
	return t

func steer_input() -> float:
	if Game.steering == Game.Steering.TOUCH:
		var target := 0.0
		if _held("left"):
			target -= 1.0
		if _held("right"):
			target += 1.0
		# Button sensitivity: how far the bike leans and how quickly the input builds up.
		var sens := clampf(Game.button_sensitivity, 0.2, 2.0)
		target *= clampf(0.45 + 0.55 * sens, 0.3, 1.0)
		var rate := 2.5 + 3.5 * sens
		if target == 0.0:
			rate *= 2.0   # let go: recentre quickly
		_btn_steer = move_toward(_btn_steer, target, rate * get_process_delta_time())
		return _btn_steer
	var t := _raw_tilt() - _tilt_neutral
	var full := deg_to_rad(24.0) / maxf(Game.tilt_sensitivity, 0.2)
	var dead := deg_to_rad(1.5)
	var x := 0.0
	if absf(t) > dead:
		x = clampf((absf(t) - dead) / full, 0.0, 1.0) * signf(t)
	_tilt_smooth = lerpf(_tilt_smooth, x, 0.35)
	return _tilt_smooth

# ------------------------------------------------------------------ per-frame

func refresh(dt: float) -> void:
	var r: Rider = world.rider
	score_lbl.text = _fmt(int(world.score))
	dist_lbl.text = "%.2f km   %s" % [r.distance / 1000.0, Game.MODE_NAMES[Game.mode]]
	var vs := root.get_viewport_rect().size
	var sfx_mat := speed_fx.material as ShaderMaterial
	sfx_mat.set_shader_parameter("amount", clampf((r.kmh() - 170.0) / 110.0, 0.0, 1.0) if not r.is_crashed else 0.0)
	sfx_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	speed_lbl.visible = Game.view != Game.View.FIRST_PERSON
	speed_lbl.text = "%d km/h   %s" % [int(round(r.kmh())), ("G%d" % r.gear)]
	if Game.mode == Game.Mode.TIME_TRIAL:
		info_lbl.text = "%.1f" % world.time_left
		info_lbl.add_theme_color_override("font_color", RED if world.time_left < 10.0 else Color.WHITE)
	elif Game.mode == Game.Mode.TWO_WAY and r.d < -0.3 and r.v > Rider.G:
		info_lbl.text = "ONCOMING x2"
		info_lbl.add_theme_color_override("font_color", ACCENT)
	elif r.v < 100.0 / 3.6 and world.is_riding() and world.run_time > 2.0:
		info_lbl.text = "100+ KM/H TO SCORE"
		info_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	else:
		info_lbl.text = ""
	combo_lbl.text = ("COMBO x%d" % world.combo) if world.combo > 1 else ""
	pedal_gas.active = r.throttle > 0.1
	pedal_brake.active = r.brake > 0.1 and world.is_riding()
	steer_l.active = _held("left")
	steer_r.active = _held("right")
	for p in [pedal_gas, pedal_brake, steer_l, steer_r]:
		p.queue_redraw()
	if world.is_countdown():
		var n := int(ceil(world.countdown))
		if n > 0:
			msg_lbl.text = str(n)
			msg_lbl.modulate.a = 1.0
	elif _msg_t > 0.0:
		_msg_t -= dt
		msg_lbl.modulate.a = clampf(_msg_t * 3.0, 0.0, 1.0)
	else:
		msg_lbl.text = ""

func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

func show_message(text: String, t: float) -> void:
	msg_lbl.text = text
	msg_lbl.modulate.a = 1.0
	_msg_t = t

func popup(text: String, combo: int) -> void:
	var l := _label(text, 30 if combo < 3 else 34, ACCENT if combo < 3 else Color(1, 0.45, 0.2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(600, 40)
	popup_box.add_child(l)
	popup_box.move_child(l, 0)
	l.pivot_offset = Vector2(300, 20)
	l.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
	while popup_box.get_child_count() > 3:
		popup_box.get_child(popup_box.get_child_count() - 1).queue_free()
		break

# ------------------------------------------------------------------ panels

func _modal(title: String) -> Array:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.94)
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 26
	sb.content_margin_bottom = 30
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2)
	box.add_theme_stylebox_override("panel", sb)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(cc)
	cc.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	var t := _label(title, 48, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return [shade, box, v]

func _center(_box: Control) -> void:
	pass

func _button(parent: Control, text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 64)
	b.add_theme_font_size_override("font_size", 28)
	b.focus_mode = Control.FOCUS_NONE
	_style_button(b, Color(0.85, 0.5, 0.05) if primary else Color(0.18, 0.2, 0.26))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func toggle_pause() -> void:
	if over_panel and over_panel.visible:
		return
	if pause_panel and pause_panel.visible:
		pause_panel.queue_free()
		pause_panel = null
		world.set_paused(false)
		_tilt_neutral = _raw_tilt()
		return
	world.set_paused(true)
	_touches.clear()
	var m := _modal("PAUSED")
	pause_panel = m[0]
	var v: VBoxContainer = m[2]
	_button(v, "Resume", toggle_pause, true)
	v.add_child(_label("COCKPIT VIEW", 18, Color(1, 1, 1, 0.6)))
	var pg := GridContainer.new()
	pg.columns = 2
	pg.add_theme_constant_override("h_separation", 20)
	v.add_child(pg)
	for row in [["Height", -0.12, 0.15, "cam_height"], ["Forward", -0.15, 0.15, "cam_forward"],
			["Field of view", 45.0, 85.0, "cam_fov"], ["Look down", -22.0, -2.0, "cam_pitch"]]:
		pg.add_child(_label(row[0], 22, Color(0.85, 0.88, 0.95)))
		var sl := HSlider.new()
		sl.min_value = row[1]
		sl.max_value = row[2]
		sl.step = (row[2] - row[1]) / 60.0
		sl.value = Game.get(row[3])
		sl.custom_minimum_size = Vector2(240, 44)
		var key: String = row[3]
		var cb := func(x: float):
			Game.set(key, x)
			Game.save()
		sl.value_changed.connect(cb)
		pg.add_child(sl)
	# Live preview while paused: keep the camera updating.
	world.rider.update_visuals(0.0)
	_button(v, "Restart", func(): world.restart())
	_button(v, "Main Menu", func(): world.quit_to_menu())
	_center(m[1])

func show_game_over(score: int, distance: float, top: float, near: int, earned: int, is_best: bool) -> void:
	if pause_panel:
		pause_panel.queue_free()
		pause_panel = null
	_touches.clear()
	var m := _modal("NEW BEST!" if is_best else "RUN OVER")
	over_panel = m[0]
	var v: VBoxContainer = m[2]
	var big := _label(_fmt(score), 64, ACCENT)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for row in [["Best", _fmt(Game.best_score(Game.mode))], ["Distance", "%.2f km" % (distance / 1000.0)],
			["Top speed", "%d km/h" % int(top)], ["Near misses", str(near)], ["Cash earned", "$%d" % earned]]:
		var a := _label(row[0], 24, Color(0.75, 0.78, 0.85))
		var b := _label(row[1], 24, Color.WHITE)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(a)
		grid.add_child(b)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	v.add_child(sp)
	_button(v, "Ride Again", func(): world.restart(), true)
	_button(v, "Main Menu", func(): world.quit_to_menu())
	_center(m[1])

# ------------------------------------------------------------------ widgets

class Pedal extends Control:
	var kind := "gas"
	var active := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		var base := Color(0.05, 0.06, 0.08, 0.45)
		if active:
			base = Color(0.25, 0.27, 0.32, 0.6)
		sb.bg_color = base
		sb.set_corner_radius_all(22)
		sb.border_color = Color(1, 1, 1, 0.35 if active else 0.18)
		sb.set_border_width_all(3)
		draw_style_box(sb, rect)
		var c := size * 0.5
		var col := Color(1, 1, 1, 0.85 if active else 0.6)
		match kind:
			"gas":
				# ribbed pedal + up arrow
				for i in 5:
					var y := size.y * 0.3 + i * size.y * 0.1
					draw_line(Vector2(size.x * 0.3, y), Vector2(size.x * 0.7, y), col, 6.0)
				_label("GAS", col)
			"brake":
				draw_rect(Rect2(size.x * 0.28, size.y * 0.28, size.x * 0.44, size.y * 0.36), col, false, 5.0)
				for i in 3:
					var y2 := size.y * 0.36 + i * size.y * 0.1
					draw_line(Vector2(size.x * 0.34, y2), Vector2(size.x * 0.66, y2), col, 4.0)
				_label("BRAKE", col)
			"left":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-34, 0), c + Vector2(24, -36), c + Vector2(24, 36)]), col)
			"right":
				draw_colored_polygon(PackedVector2Array([c + Vector2(34, 0), c + Vector2(-24, -36), c + Vector2(-24, 36)]), col)

	func _label(t: String, col: Color) -> void:
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f, Vector2((size.x - w) * 0.5, size.y - 22), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
