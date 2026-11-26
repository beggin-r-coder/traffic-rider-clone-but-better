extends Node3D
## Main menu: bike showroom on a turntable plus mode / time-of-day / settings UI.

const ACCENT := Color(1.0, 0.7, 0.12)

var bike: BikeVisual
var cam: Camera3D
var turntable: Node3D
var ui: Control
var main_panel: Control
var settings_panel: Control
var _t := 0.0
var _mode_btns: Array[Button] = []
var _time_btns: Array[Button] = []
var best_lbl: Label
var cash_lbl: Label
var garage_panel: Control
var _upgrade_rows := {}
var _paint_btns: Array[Button] = []

func _ready() -> void:
	_build_scene()
	_build_ui()
	if Game.has_flag("shot") and Game.has_flag("menu"):
		if Game.has_flag("settings"):
			_show_settings(true)
		if Game.has_flag("garage"):
			_show_garage(true)
		await get_tree().create_timer(float(Game.flag("at", "1.0"))).timeout
		await Game.save_shot(String(Game.flag("shot")))
		get_tree().quit()

func _build_scene() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = env.background_color
	env.fog_depth_begin = 6.0
	env.fog_depth_end = 22.0
	env.fog_sky_affect = 1.0
	we.environment = env
	add_child(we)
	# Studio lights.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 35, 0)
	key.light_energy = 1.8
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 20.0
	add_child(key)
	for p in [[Vector3(-3.5, 2.5, -3), Color(0.45, 0.6, 1.0), 4.0], [Vector3(3.5, 2.0, 2.5), Color(1.0, 0.7, 0.45), 3.0], [Vector3(-1, 3.5, 4), Color(1, 1, 1), 3.5]]:
		var o := OmniLight3D.new()
		o.position = p[0]
		o.light_color = p[1]
		o.light_energy = p[2]
		o.omni_range = 12.0
		add_child(o)
	# Glossy floor with a soft spotlight pool.
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	floor_mi.mesh = pm
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://shaders/showroom_floor.gdshader")
	floor_mi.material_override = fm
	add_child(floor_mi)
	turntable = Node3D.new()
	add_child(turntable)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.9
	cm.bottom_radius = 1.95
	cm.height = 0.06
	cm.radial_segments = 64
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.09, 0.09, 0.1)
	dm.metallic = 0.7
	dm.roughness = 0.25
	disc.material_override = dm
	disc.position.y = 0.03
	turntable.add_child(disc)
	bike = BikeVisual.new()
	bike.position.y = 0.06
	turntable.add_child(bike)
	# Studio softboxes: bright panels around the bike that show up as long highlights in the paint.
	var soft := StandardMaterial3D.new()
	soft.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	soft.albedo_color = Color(1, 1, 1)
	soft.emission_enabled = true
	soft.emission = Color(1, 1, 1)
	soft.emission_energy_multiplier = 2.5
	soft.cull_mode = BaseMaterial3D.CULL_DISABLED
	for b in [[Vector3(0, 4.2, 0), Vector3(-PI * 0.5, 0, 0), Vector2(5.0, 1.4)],
			[Vector3(-4.5, 2.0, -1.0), Vector3(0, PI * 0.35, 0), Vector2(2.2, 3.2)],
			[Vector3(3.5, 1.8, -3.5), Vector3(0, -PI * 0.2, 0), Vector2(3.0, 2.0)],
			[Vector3(-1.5, 2.2, -5.0), Vector3(0, 0.15, 0), Vector2(4.0, 1.0)]]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = b[2]
		q.mesh = qm
		q.material_override = soft
		q.position = b[0]
		q.rotation = b[1]
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.layers = 4          # seen by the reflection probe, hidden from the camera
		add_child(q)
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(20, 12, 20)
	probe.origin_offset = Vector3(0, 0.8, 0)
	probe.cull_mask = 1 | 4
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	add_child(probe)
	cam = Camera3D.new()
	cam.cull_mask = 0xFFFFF & ~4
	cam.fov = 38.0
	add_child(cam)
	# Frame the bike in the right half of the screen (the menu sits on the left).
	cam.look_at_from_position(Vector3(0.9, 1.25, 5.0), Vector3(-1.05, 0.58, 0.0))

func _process(delta: float) -> void:
	_t += delta
	turntable.rotation.y = _t * 0.25 - 0.9
	bike.roll(delta * 0.0)

# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	# Left gradient for readability.
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.75))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.size = Vector2(760, 720)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(grad)

	main_panel = VBoxContainer.new()
	main_panel.position = Vector2(64, 50)
	main_panel.size = Vector2(560, 620)
	main_panel.add_theme_constant_override("separation", 14)
	ui.add_child(main_panel)
	var title := _label("THROTTLE RUSH", 68, Color.WHITE)
	title.add_theme_constant_override("outline_size", 0)
	main_panel.add_child(title)
	var sub := _label("HIGHWAY  •  TRAFFIC  •  300 KM/H", 20, ACCENT)
	main_panel.add_child(sub)
	main_panel.add_child(_spacer(14))
	main_panel.add_child(_label("MODE", 18, Color(1, 1, 1, 0.6)))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	main_panel.add_child(modes)
	for i in Game.MODE_NAMES.size():
		var b := _seg_button(Game.MODE_NAMES[i])
		var sel := func(): _select_mode(i)
		b.pressed.connect(sel)
		modes.add_child(b)
		_mode_btns.append(b)
	main_panel.add_child(_label("TIME OF DAY", 18, Color(1, 1, 1, 0.6)))
	var times := HBoxContainer.new()
	times.add_theme_constant_override("separation", 10)
	main_panel.add_child(times)
	for i in Game.TIME_NAMES.size():
		var b := _seg_button(Game.TIME_NAMES[i])
		b.custom_minimum_size = Vector2(127, 56)
		var sel2 := func(): _select_time(i)
		b.pressed.connect(sel2)
		times.add_child(b)
		_time_btns.append(b)
	main_panel.add_child(_spacer(6))
	best_lbl = _label("", 22, Color(0.85, 0.88, 0.95))
	main_panel.add_child(best_lbl)
	main_panel.add_child(_spacer(6))
	var ride := _button("RIDE", Color(0.88, 0.5, 0.04), 40)
	ride.custom_minimum_size = Vector2(420, 86)
	ride.pressed.connect(_start)
	main_panel.add_child(ride)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	main_panel.add_child(row)
	var gar_btn := _button("Garage", Color(0.16, 0.18, 0.24), 24)
	gar_btn.custom_minimum_size = Vector2(176, 58)
	gar_btn.pressed.connect(func(): _show_garage(true))
	row.add_child(gar_btn)
	var set_btn := _button("Settings", Color(0.16, 0.18, 0.24), 24)
	set_btn.custom_minimum_size = Vector2(176, 58)
	set_btn.pressed.connect(func(): _show_settings(true))
	row.add_child(set_btn)
	var view_btn := _button("", Color(0.16, 0.18, 0.24), 24)
	view_btn.custom_minimum_size = Vector2(196, 58)
	var upd := func(): view_btn.text = "View: " + ("Cockpit" if Game.view == Game.View.FIRST_PERSON else "Chase")
	upd.call()
	var toggle := func():
		Game.view = Game.View.CHASE if Game.view == Game.View.FIRST_PERSON else Game.View.FIRST_PERSON
		Game.save()
		upd.call()
	view_btn.pressed.connect(toggle)
	row.add_child(view_btn)

	var credit := _label("Bike model: \"2022 Yamaha R1\" by Hari (Sketchfab)", 14, Color(1, 1, 1, 0.35))
	credit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	credit.position = Vector2(-420, -34)
	credit.size = Vector2(400, 24)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(credit)
	cash_lbl = _label("$%d" % Game.cash, 30, ACCENT)
	cash_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cash_lbl.position = Vector2(-260, 28)
	cash_lbl.size = Vector2(220, 40)
	cash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(cash_lbl)
	_build_settings()
	_build_garage()
	bike.set_paint(Game.bike_color)
	_select_mode(Game.mode)
	_select_time(Game.time_of_day)

func _build_settings() -> void:
	settings_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	settings_panel.add_theme_stylebox_override("panel", sb)
	settings_panel.position = Vector2(64, 60)
	settings_panel.visible = false
	ui.add_child(settings_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	settings_panel.add_child(v)
	v.add_child(_label("SETTINGS", 44, Color.WHITE))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	_cycle_row(grid, "Steering", ["Tilt", "Touch buttons"], func(): return Game.steering, func(i): Game.steering = i)
	_slider_row(grid, "Tilt sensitivity", 0.5, 2.0, func(): return Game.tilt_sensitivity, func(x): Game.tilt_sensitivity = x)
	_cycle_row(grid, "Steering assist", ["Off (pro lean)", "On"], func(): return 1 if Game.assist else 0, func(i): Game.assist = i == 1)
	_cycle_row(grid, "Camera", ["Cockpit", "Chase"], func(): return Game.view, func(i): Game.view = i)
	_cycle_row(grid, "Graphics", ["Low", "Medium", "High"], func(): return Game.quality, func(i): Game.quality = i)
	_slider_row(grid, "Volume", 0.0, 1.0, func(): return Game.sfx_volume, func(x): Game.sfx_volume = x)
	var back := _button("Done", Color(0.88, 0.5, 0.04), 28)
	back.custom_minimum_size = Vector2(300, 64)
	back.pressed.connect(func(): _show_settings(false))
	v.add_child(back)

func _cycle_row(grid: GridContainer, title: String, options: Array, getter: Callable, setter: Callable) -> void:
	grid.add_child(_label(title, 24, Color(0.85, 0.88, 0.95)))
	var b := _button(options[getter.call()], Color(0.16, 0.18, 0.24), 22)
	b.custom_minimum_size = Vector2(260, 52)
	var cb := func():
		var i: int = (int(getter.call()) + 1) % options.size()
		setter.call(i)
		b.text = options[i]
		Game.save()
	b.pressed.connect(cb)
	grid.add_child(b)

func _slider_row(grid: GridContainer, title: String, lo: float, hi: float, getter: Callable, setter: Callable) -> void:
	grid.add_child(_label(title, 24, Color(0.85, 0.88, 0.95)))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = getter.call()
	s.custom_minimum_size = Vector2(260, 52)
	var cb := func(x: float):
		setter.call(x)
		Game.save()
	s.value_changed.connect(cb)
	grid.add_child(s)

func _build_garage() -> void:
	garage_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.93)
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	garage_panel.add_theme_stylebox_override("panel", sb)
	garage_panel.position = Vector2(64, 50)
	garage_panel.visible = false
	ui.add_child(garage_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	garage_panel.add_child(v)
	v.add_child(_label("GARAGE", 44, Color.WHITE))
	v.add_child(_label("PAINT", 18, Color(1, 1, 1, 0.6)))
	var paints := HBoxContainer.new()
	paints.add_theme_constant_override("separation", 10)
	v.add_child(paints)
	for i in BikeVisual.PAINTS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(70, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = BikeVisual.PAINTS[i][0]
		var pick := func():
			Game.bike_color = i
			Game.save()
			bike.set_paint(i)
			_refresh_garage()
		b.pressed.connect(pick)
		paints.add_child(b)
		_paint_btns.append(b)
	v.add_child(_spacer(4))
	v.add_child(_label("UPGRADES", 18, Color(1, 1, 1, 0.6)))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for kind in ["engine", "brakes", "handling"]:
		var info: Array = Game.UPGRADE_INFO[kind]
		var name_box := VBoxContainer.new()
		name_box.add_theme_constant_override("separation", 0)
		name_box.add_child(_label(info[0], 26, Color.WHITE))
		name_box.add_child(_label(info[1], 15, Color(1, 1, 1, 0.55)))
		grid.add_child(name_box)
		var pips := _label("", 28, ACCENT)
		grid.add_child(pips)
		var buy := _button("", Color(0.88, 0.5, 0.04), 22)
		buy.custom_minimum_size = Vector2(170, 54)
		var do_buy := func():
			Game.buy_upgrade(kind)
			_refresh_garage()
		buy.pressed.connect(do_buy)
		grid.add_child(buy)
		_upgrade_rows[kind] = [pips, buy]
	var back := _button("Done", Color(0.16, 0.18, 0.24), 26)
	back.custom_minimum_size = Vector2(240, 60)
	back.pressed.connect(func(): _show_garage(false))
	v.add_child(back)
	_refresh_garage()

func _refresh_garage() -> void:
	cash_lbl.text = "$%d" % Game.cash
	for i in _paint_btns.size():
		var b := _paint_btns[i]
		var col: Color = BikeVisual.PAINTS[i][4]
		for st in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = col if st != "hover" else col.lightened(0.1)
			sb.set_corner_radius_all(12)
			sb.border_color = Color.WHITE if i == Game.bike_color else Color(1, 1, 1, 0.15)
			sb.set_border_width_all(4 if i == Game.bike_color else 2)
			b.add_theme_stylebox_override(st, sb)
	for kind in _upgrade_rows:
		var lvl := Game.upgrade_level(kind)
		var pips: Label = _upgrade_rows[kind][0]
		var buy: Button = _upgrade_rows[kind][1]
		var t := ""
		for k in Game.UPGRADE_MAX:
			t += "■ " if k < lvl else "□ "
		pips.text = t
		if lvl >= Game.UPGRADE_MAX:
			buy.text = "MAX"
			buy.disabled = true
		else:
			var cost := Game.upgrade_cost(kind)
			buy.text = "$%d" % cost
			buy.disabled = Game.cash < cost
		buy.modulate.a = 0.45 if buy.disabled else 1.0

func _show_garage(on: bool) -> void:
	garage_panel.visible = on
	main_panel.visible = not on
	if on:
		_refresh_garage()

func _show_settings(on: bool) -> void:
	settings_panel.visible = on
	main_panel.visible = not on

func _select_mode(i: int) -> void:
	Game.mode = i
	for k in _mode_btns.size():
		_style_seg(_mode_btns[k], k == i)
	_update_best()

func _select_time(i: int) -> void:
	Game.time_of_day = i
	for k in _time_btns.size():
		_style_seg(_time_btns[k], k == i)

func _update_best() -> void:
	if best_lbl:
		best_lbl.text = "Best score: %d     Best distance: %.1f km" % [Game.best_score(Game.mode), Game.best_distance / 1000.0]

func _start() -> void:
	Game.save()
	Game.run_seed = randi() % 100000
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _button(t: String, bg: Color, fs: int) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fs)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.1 if st == "hover" else (0.22 if st == "pressed" else 0.0))
		sb.set_corner_radius_all(16)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b

func _seg_button(t: String) -> Button:
	var b := _button(t, Color(0.16, 0.18, 0.24), 22)
	b.custom_minimum_size = Vector2(172, 56)
	return b

func _style_seg(b: Button, on: bool) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.18, 0.24, 0.9) if not on else Color(0.95, 0.95, 0.97)
		if st == "hover":
			sb.bg_color = sb.bg_color.lightened(0.06)
		sb.set_corner_radius_all(14)
		b.add_theme_stylebox_override(st, sb)
	var fc := Color(0.05, 0.05, 0.07) if on else Color.WHITE
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
