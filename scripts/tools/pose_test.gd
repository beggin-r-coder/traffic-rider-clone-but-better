extends Node3D
## Dev tool (--posetest=DIR): renders the rider on the bike from several cameras in several input
## states so posture, grip, throttle roll and brake-finger poses can be reviewed as images.

var bike: BikeVisual
var rider: RiderModel
var cam: Camera3D

func _ready() -> void:
	if get_tree().current_scene == self:
		run(String(Game.flag("posetest", "/tmp/posetest")))

func run(dir: String) -> void:
	print("[posetest] run ", dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.85)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -40, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.46, 0.48)
	floor_mi.material_override = fm
	add_child(floor_mi)
	bike = BikeVisual.new()
	add_child(bike)
	rider = RiderModel.new()
	bike.lean_node.add_child(rider)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	if Game.has_flag("posenum"):
		rider.speed = 30.0
		rider.brake = float(Game.flag("brakeval", "0"))
		for i in 30:
			rider.update_pose(1.0 / 30.0)
		var sd: Dictionary = rider._side[1.0]
		var bk := func(i: int) -> Vector3:
			var v: Vector3 = rider._g[i].origin
			return Vector3(-v.x, v.y, -v.z).snapped(Vector3.ONE * 0.001)
		for k in ["arm", "fore", "hand", "upleg", "leg", "foot"]:
			print("[posenum] ", k, " ", bk.call(sd[k]))
		var g := rider.GRIP_IN.lerp(rider.GRIP_OUT, 0.48)
		print("[posenum] grip centre ", g, " knuckle ", Vector3(-rider._knuckle(sd).x, rider._knuckle(sd).y, -rider._knuckle(sd).z))
		var toe: Vector3 = rider._toe_pt(sd)
		print("[posenum] fpcam ", rider.fp_camera_position())
		print("[posenum] peg ", rider.PEG, " toe ", Vector3(-toe.x, toe.y, -toe.z), " pitch_extra ", rad_to_deg(rider._pitch_extra))
		var gi: Vector3 = RiderModel._sk(rider.GRIP_IN)
		var go: Vector3 = RiderModel._sk(rider.GRIP_OUT)
		var ax := (go - gi).normalized()
		var c := gi.lerp(go, 0.48)
		var top := (Vector3.UP - ax * Vector3.UP.dot(ax)).normalized()
		for chain: Array in sd["fingers"] + [sd["thumb"]]:
			var line := ""
			for j in rider._chain_len(chain):
				var q: Vector3 = rider._chain_pt(chain, j) - c
				line += " %d:(a%+.3f u%+.3f r%.3f)" % [j, q.dot(ax), q.dot(top), (q - ax * q.dot(ax)).length()]
			print("[posenum] chain", line)
		get_tree().quit()
		return
	if Game.has_flag("markers"):
		rider.visible = false
		var pts := [rider.GRIP_IN, rider.GRIP_OUT, rider.LEVER_IN, rider.LEVER_OUT, rider.PEG, rider.SEAT]
		var cols := [Color.RED, Color.GREEN, Color.YELLOW, Color.ORANGE, Color.CYAN, Color.MAGENTA]
		for i in pts.size():
			var sp := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.008
			sm.height = 0.016
			sp.mesh = sm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = cols[i]
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			sp.material_override = mat
			sp.position = pts[i]
			bike.lean_node.add_child(sp)
		var gc: Vector3 = rider.GRIP_IN.lerp(rider.GRIP_OUT, 0.5)
		var mviews := {
			"m_top": [gc + Vector3(0, 0.7, -0.05), gc + Vector3(0, 0, -0.05), Vector3.FORWARD, 30.0],
			"m_side": [gc + Vector3(0.9, 0, -0.05), gc + Vector3(0, 0, -0.05), Vector3.UP, 20.0],
			"m_front": [gc + Vector3(0, 0.02, -0.95), gc + Vector3(0, 0, -0.05), Vector3.UP, 16.0],
			"m_feet": [rider.PEG + Vector3(1.0, 0.25, 0.0), rider.PEG, Vector3.UP, 30.0],
		}
		for vn in mviews:
			var v: Array = mviews[vn]
			cam.fov = v[3]
			cam.global_transform = Transform3D(Basis(), v[0]).looking_at(v[1], v[2])
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, vn])
		get_tree().quit()
		return
	var states := {
		"cruise": [0.3, 0.0, 0.0, 30.0],
		"throttle": [1.0, 0.0, 0.0, 30.0],
		"brake": [0.0, 1.0, 0.0, 30.0],
		"lean": [0.6, 0.0, 0.6, 40.0],
	}
	var gc: Vector3 = rider.GRIP_IN.lerp(rider.GRIP_OUT, 0.5)
	var pg: Vector3 = rider.PEG
	var views := {
		"side": [Vector3(3.2, 1.1, -0.1), Vector3(0, 0.8, -0.1), 40.0],
		"sideclose": [Vector3(2.2, 1.15, 0.0), Vector3(0, 0.95, -0.05), 32.0],
		"rear34": [Vector3(1.6, 1.6, 2.2), Vector3(0, 1.0, 0.0), 36.0],
		"front": [Vector3(0.0, 1.2, -3.0), Vector3(0, 1.0, 0.0), 30.0],
		"feet_r": [pg + Vector3(0.75, 0.1, -0.02), pg + Vector3(0, 0.03, 0.02), 30.0],
		"feet_rear": [pg + Vector3(0.45, 0.3, 0.95), pg + Vector3(-0.02, 0.03, 0.02), 30.0],
		"dash": [Vector3(0.0, gc.y + 0.30, -0.30), Vector3(0.0, gc.y + 0.075, -0.6), 34.0],
		"front34": [Vector3(1.8, 1.5, -2.6), Vector3(0, 0.9, -0.2), 40.0],
		"hand_r": [gc + Vector3(0.46, 0.21, -0.35), gc, 30.0],
		"hand_top": [gc + Vector3(0, 0.51, 0.0), gc, 30.0],
		"hand_l": [gc * Vector3(-1, 1, 1) + Vector3(-0.46, 0.21, -0.35), gc * Vector3(-1, 1, 1), 30.0],
		"hand_under": [gc + Vector3(0.26, -0.16, -0.35), gc, 28.0],
		"legs": [Vector3(1.9, 0.7, 0.05), Vector3(0.0, 0.68, 0.05), 32.0],
		"legs_top": [Vector3(0.0, 2.3, 0.15), Vector3(0.0, 0.7, 0.1), 34.0],
	}
	for st in states:
		var s: Array = states[st]
		rider.throttle = s[0]
		rider.brake = s[1]
		rider.speed = s[3]
		bike.set_lean(s[2])
		rider.lean = s[2]
		for i in 40:
			rider.update_pose(1.0 / 30.0)
		bike.set_levers(rider.lever_pull, rider.clutch_pull)
		if bike.dash:
			bike.dash.set_values(s[3] * 3.6, 6000.0 + s[0] * 7200.0, 3)
		var only: Array = String(Game.flag("views", "")).split(",", false)
		var only_states: Array = String(Game.flag("states", "")).split(",", false)
		if not only_states.is_empty() and not st in only_states:
			continue
		for vn in views:
			if not only.is_empty() and not vn in only:
				continue
			if st != "cruise" and (vn.begins_with("feet") or vn == "dash"):
				continue
			if st == "lean" and vn.begins_with("hand"):
				continue
			var v: Array = views[vn]
			var lt := bike.lean_node.global_transform if (vn.begins_with("hand") or vn == "dash") else Transform3D.IDENTITY
			cam.fov = v[2]
			var upv := Vector3.FORWARD if vn == "hand_top" else Vector3.UP
			cam.global_transform = Transform3D(Basis(), lt * v[0]).looking_at(lt * v[1], upv)
			rider.set_first_person(vn == "dash")
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, st, vn])
			if vn == "dash" and bike.dash:
				bike.dash.get_texture().get_image().save_png("%s/dash_texture.png" % dir)
		# first person
		if not only.is_empty() and not "fp" in only:
			continue
		rider.set_first_person(true)
		for variant in [[rider.fp_camera_position(), -11.0, "a"]]:
			var eye: Vector3 = bike.lean_node.global_transform * variant[0]
			cam.fov = 62.0
			cam.global_transform = Transform3D(bike.lean_node.global_transform.basis * Basis(Vector3.RIGHT, deg_to_rad(variant[1])), eye)
			var pitch: float = variant[1]
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_fp_%s.png" % [dir, st, variant[2]])
	print("[posetest] done")
	get_tree().quit()
