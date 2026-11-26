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
		bike.set_levers(rider.lever_pull, rider.clutch_pull)
		print("[posenum] lever pull ", rider.lever_pull, " brake lever node ", bike.brake_lever, " clutch ", bike.clutch_lever)
		var b: Dictionary = rider._b
		var sk := rider.skel
		var gt := func(n: String) -> Vector3:
			var v: Vector3 = sk.get_bone_global_pose(b[n]).origin
			return Vector3(-v.x, v.y, -v.z).snapped(Vector3.ONE * 0.001)
		for n in ["Hips", "Spine2", "Head", "RightArm", "RightForeArm", "RightHand", "RightHandMiddle1", "RightHandIndex1", "RightHandPinky1", "RightHandIndex4", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]:
			print("[posenum] ", n, " ", gt.call(n), " solver=", (func(): var v: Vector3 = rider._g[b[n]].origin; return Vector3(-v.x, v.y, -v.z).snapped(Vector3.ONE * 0.001)).call())
		var gi := RiderModel.GRIP_IN
		var go := RiderModel.GRIP_OUT
		var ax := (go - gi).normalized()
		var c := gi.lerp(go, 0.48)
		var top := (Vector3.UP - ax * Vector3.UP.dot(ax)).normalized()
		var fr := top.cross(ax)
		if fr.z > 0:
			fr = -fr
		for f in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
			var line := ""
			for j in range(1, 5):
				var p: Vector3 = gt.call("RightHand" + f + str(j)) - c
				line += " %d:(a%+.3f u%+.3f f%+.3f r%.3f)" % [j, p.dot(ax), p.dot(top), p.dot(fr), Vector2(p.dot(top), p.dot(fr)).length()]
			print("[posenum] ", f, line)
		var lbs := BikeVisual.lever_basis(1.0, rider.lever_pull)
		var lpv := BikeVisual.lever_pivot(1.0)
		var la := lpv + lbs * (RiderModel.LEVER_IN - lpv)
		var lb := lpv + lbs * (RiderModel.LEVER_OUT - lpv)
		for f in ["Index", "Middle"]:
			for j in [3, 4]:
				var p: Vector3 = gt.call("RightHand" + f + str(j))
				var t := clampf((p - la).dot(lb - la) / (lb - la).length_squared(), 0.0, 1.0)
				var cl := la.lerp(lb, t)
				print("[posenum] %s%d dist to lever %.3f (t=%.2f) offset %s" % [f, j, p.distance_to(cl), t, (p - cl).snapped(Vector3.ONE * 0.001)])
		var wp: Vector3 = gt.call("RightHand") - c
		print("[posenum] wrist a%+.3f u%+.3f f%+.3f" % [wp.dot(ax), wp.dot(top), wp.dot(fr)])
		print("[posenum] chin ", rider.chin_cam_position(), " eye ", rider.eye_position(), " skel parent xf ", sk.get_parent().transform.origin, " ", sk.transform.origin)
		get_tree().quit()
		return
	if Game.has_flag("markers"):
		rider.visible = false
		var pts := [RiderModel.GRIP_IN, RiderModel.GRIP_OUT, RiderModel.GRIP_IN.lerp(RiderModel.GRIP_OUT, 0.5)]
		var cols := [Color.RED, Color.GREEN, Color.YELLOW]
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
		var mviews := {
			"m_top": [Vector3(0.3, 1.6, -0.48), Vector3(0.3, 0.9, -0.48), Vector3.FORWARD, 30.0],
			"m_side": [Vector3(1.2, 0.93, -0.48), Vector3(0.3, 0.93, -0.48), Vector3.UP, 20.0],
			"m_front": [Vector3(0.3, 0.95, -1.4), Vector3(0.3, 0.93, -0.48), Vector3.UP, 16.0],
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
	var views := {
		"side": [Vector3(3.2, 1.1, -0.1), Vector3(0, 0.8, -0.1), 40.0],
		"sideclose": [Vector3(2.2, 1.15, 0.0), Vector3(0, 0.95, -0.05), 32.0],
		"rear34": [Vector3(1.6, 1.6, 2.2), Vector3(0, 1.0, 0.0), 36.0],
		"front": [Vector3(0.0, 1.2, -3.0), Vector3(0, 1.0, 0.0), 30.0],
		"feet_r": [Vector3(1.0, 0.55, 0.32), Vector3(0.24, 0.48, 0.36), 30.0],
		"feet_rear": [Vector3(0.7, 0.75, 1.3), Vector3(0.22, 0.48, 0.36), 30.0],
		"dash": [Vector3(0.0, 1.3, -0.25), Vector3(0.0, 1.03, -0.625), 40.0],
		"front34": [Vector3(1.8, 1.5, -2.6), Vector3(0, 0.9, -0.2), 40.0],
		"hand_r": [Vector3(0.75, 1.15, -0.75), Vector3(0.29, 0.94, -0.42), 30.0],
		"hand_top": [Vector3(0.29, 1.45, -0.42), Vector3(0.29, 0.94, -0.42), 30.0],
		"hand_l": [Vector3(-0.75, 1.15, -0.75), Vector3(-0.29, 0.94, -0.42), 30.0],
		"hand_under": [Vector3(0.55, 0.78, -0.75), Vector3(0.29, 0.94, -0.42), 28.0],
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
		for vn in views:
			if st != "cruise" and (vn.begins_with("feet") or vn == "dash"):
				continue
			if st == "lean" and vn.begins_with("hand"):
				continue
			var v: Array = views[vn]
			var lt := bike.lean_node.global_transform if (vn.begins_with("hand") or vn == "dash") else Transform3D.IDENTITY
			cam.fov = v[2]
			var upv := Vector3.FORWARD if vn == "hand_top" else Vector3.UP
			cam.global_transform = Transform3D(Basis(), lt * v[0]).looking_at(lt * v[1], upv)
			rider.set_first_person(false)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, st, vn])
		# first person
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
