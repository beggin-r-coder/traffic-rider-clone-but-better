extends Node
## Dev tool (--bake-vegetation=<dir with Poly Haven glTF folders>):
## renders each plant from 8 directions into one shared albedo + normal atlas and writes
## res://assets/vegetation/{atlas_albedo,atlas_normal}.png and vegetation.json.
## Needs a real renderer (run under xvfb), not --headless.

const FRAME_W := 256
const FRAMES := 16
const SS := 2                     # supersampling factor
const OUT_DIR := "res://assets/vegetation"

## [asset folder, variant node (top-level node in the glTF), kind, frame height px].
## 512 rows are 256x512 (tall trees), 256 rows are 256x256 (wide/low plants).
const SPECIES := [
	["fir_tree_01", "fir_tree_01_a_LOD0", "conifer", 512],
	["fir_tree_01", "fir_tree_01_b_LOD0", "conifer", 512],
	["fir_tree_01", "fir_tree_01_c_LOD0", "conifer", 512],
	["tree_small_02", "tree_small_02_LOD0", "broadleaf", 512],
	["fir_sapling", "fir_sapling_a", "young_conifer", 512],
	["pine_sapling_small", "pine_sapling_small_a", "young_conifer", 512],
	["island_tree_02", "island_tree_02_LOD0", "broadleaf_wide", 256],
	["searsia_lucida", "searsia_lucida_a_LOD0", "bush_tree", 256],
]

var src_dir := ""

func run(dir: String) -> void:
	src_dir = dir
	var total_h := 0
	for sp in SPECIES:
		total_h += int(sp[3])
	var atlas_a := Image.create(FRAME_W * FRAMES, total_h, false, Image.FORMAT_RGBA8)
	var atlas_n := Image.create(FRAME_W * FRAMES, total_h, false, Image.FORMAT_RGBA8)
	atlas_a.fill(Color(0, 0, 0, 0))
	atlas_n.fill(Color(0.5, 0.5, 1.0, 0))
	var meta := []
	var row_y := 0
	for sp in SPECIES:
		var info := await _bake_species(sp[0], sp[1], int(sp[3]), atlas_a, atlas_n, row_y)
		if info.is_empty():
			push_error("failed " + str(sp[0]))
			continue
		info["kind"] = sp[2]
		info["row_y"] = row_y
		info["row_h"] = int(sp[3])
		meta.append(info)
		row_y += int(sp[3])
		print("[bake] ", sp[0], " ", info)
	atlas_a.fix_alpha_edges()
	# Empty normal texels: "facing camera", far depth.
	for y in atlas_n.get_height():
		for x in atlas_n.get_width():
			if atlas_a.get_pixel(x, y).a < 0.02:
				atlas_n.set_pixel(x, y, Color(0.5, 0.5, 1.0, 1.0))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	atlas_a.save_png(OUT_DIR + "/atlas_albedo.png")
	atlas_n.save_png(OUT_DIR + "/atlas_normal.png")
	var f := FileAccess.open(OUT_DIR + "/vegetation.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"frame_w": FRAME_W, "frames": FRAMES, "atlas_w": FRAME_W * FRAMES, "atlas_h": total_h, "species": meta}, "  "))
	f.close()
	print("[bake] done ", total_h, "px atlas")
	get_tree().quit()

## Bakes a dense side-on strip of real grass tufts (grass_medium_02, scaled up) for grass cards:
## res://assets/vegetation/grass_{albedo,normal}.png covering 4 m x 1 m.
func run_grass(dir: String) -> void:
	src_dir = dir
	var path := _find_gltf("grass_medium_02")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_file(path, state)
	var scene: Node3D = doc.generate_scene(state)
	var tufts: Array = []
	_collect(scene, tufts)
	var vp := SubViewport.new()
	var W := 2048
	var H := 512
	vp.size = Vector2i(W * SS, H * SS)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	var holder := Node3D.new()
	vp.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mat_a := {}
	var mat_n := {}
	var placed: Array = []
	for i in 140:
		var src: MeshInstance3D = tufts[rng.randi() % tufts.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		var sc := rng.randf_range(1.4, 2.8)
		var x := rng.randf_range(-1.9, 1.9)
		mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.4), sc)), Vector3(x, -src.mesh.get_aabb().position.y * sc, rng.randf_range(-0.5, 0.5)))
		holder.add_child(mi)
		placed.append(mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(0, 0.5, 6.0)
	cam.far = 20.0
	vp.add_child(cam)
	cam.current = true
	var out := []
	for pass_i in 2:
		for mi: MeshInstance3D in placed:
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
				var sm := ShaderMaterial.new()
				sm.shader = preload("res://shaders/tools/bake_albedo.gdshader") if pass_i == 0 else preload("res://shaders/tools/bake_normal.gdshader")
				if m:
					sm.set_shader_parameter("tint", m.albedo_color.srgb_to_linear())
					if m.albedo_texture:
						sm.set_shader_parameter("tex", m.albedo_texture)
						sm.set_shader_parameter("has_tex", true)
					if pass_i == 1 and m.normal_enabled and m.normal_texture:
						sm.set_shader_parameter("ntex", m.normal_texture)
						sm.set_shader_parameter("has_ntex", true)
				if pass_i == 0:
					sm.set_shader_parameter("depth_near", 5.5)
					sm.set_shader_parameter("depth_far", 6.6)
				mi.set_surface_override_material(si, sm)
		for w in 3:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(W, H, Image.INTERPOLATE_LANCZOS)
		out.append(img)
	out[0].fix_alpha_edges()
	var n: Image = out[1]
	for y in H:
		for x in W:
			var a: float = out[0].get_pixel(x, y).a
			var c := n.get_pixel(x, y)
			n.set_pixel(x, y, Color(c.r, c.g, c.b, a) if a > 0.02 else Color(0.5, 0.5, 1.0, 0.0))
	out[0].save_png(OUT_DIR + "/grass_albedo.png")
	n.save_png(OUT_DIR + "/grass_normal.png")
	print("[bake] grass strip done")
	get_tree().quit()

func _find_gltf(folder: String) -> String:
	var d := DirAccess.open(src_dir + "/" + folder)
	if d == null:
		return ""
	for f in d.get_files():
		if f.ends_with(".gltf"):
			return src_dir + "/" + folder + "/" + f
	return ""

func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)

func _bake_species(folder: String, variant: String, frame_h: int, atlas_a: Image, atlas_n: Image, row_y: int) -> Dictionary:
	var path := _find_gltf(folder)
	if path == "":
		return {}
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return {}
	var scene: Node3D = doc.generate_scene(state)
	# Keep only the requested variant (files ship several plants side by side).
	for c in scene.get_children():
		if c.name != variant:
			scene.remove_child(c)
			c.free()
	if scene.get_child_count() == 0:
		return {}
	(scene.get_child(0) as Node3D).position = Vector3.ZERO
	var vp := SubViewport.new()
	vp.size = Vector2i(FRAME_W * SS, frame_h * SS)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(scene)
	# Bounds in model space.
	var meshes: Array = []
	_collect(scene, meshes)
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		var xf := _rel(mi, scene)
		var b: AABB = xf * mi.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	var cx := aabb.get_center().x
	var cz := aabb.get_center().z
	var base_y := aabb.position.y
	var height := aabb.size.y
	# Silhouette half-width over all view angles (a bit more than the larger half-extent).
	var radius := maxf(aabb.size.x, aabb.size.z) * 0.5 * 1.12
	scene.position = Vector3(-cx, -base_y, -cz)
	# Frame: width = 2 * radius, height = 2 * width for tall frames (1:1 for small ones), whichever fits.
	var aspect := float(frame_h) / FRAME_W
	var world_w := maxf(radius * 2.0, height / aspect) * 1.04
	var world_h := world_w * aspect
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = world_h
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.far = radius * 4.0 + 20.0
	var dist := radius + 5.0
	cam.position = Vector3(0, world_h * 0.5, dist)
	vp.add_child(cam)
	cam.current = true
	# Prepare override materials for both passes.
	var mats_a := {}
	var mats_n := {}
	var mats_d := {}
	for mi: MeshInstance3D in meshes:
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
			var a := ShaderMaterial.new()
			a.shader = preload("res://shaders/tools/bake_albedo.gdshader")
			var n := ShaderMaterial.new()
			n.shader = preload("res://shaders/tools/bake_normal.gdshader")
			if m:
				for sm in [a, n]:
					sm.set_shader_parameter("tint", m.albedo_color.srgb_to_linear())
					if m.albedo_texture:
						sm.set_shader_parameter("tex", m.albedo_texture)
						sm.set_shader_parameter("has_tex", true)
				if m.normal_enabled and m.normal_texture:
					n.set_shader_parameter("ntex", m.normal_texture)
					n.set_shader_parameter("has_ntex", true)
			a.set_shader_parameter("depth_near", dist - radius * 0.9)
			a.set_shader_parameter("depth_far", dist + radius * 0.5)
			var dm := ShaderMaterial.new()
			dm.shader = preload("res://shaders/tools/bake_depth.gdshader")
			if m:
				dm.set_shader_parameter("tint", m.albedo_color.srgb_to_linear())
				if m.albedo_texture:
					dm.set_shader_parameter("tex", m.albedo_texture)
					dm.set_shader_parameter("has_tex", true)
			dm.set_shader_parameter("depth_near", dist - radius)
			dm.set_shader_parameter("depth_far", dist + radius)
			mats_a[[mi, si]] = a
			mats_n[[mi, si]] = n
			mats_d[[mi, si]] = dm
	var fw := FRAME_W
	var depth_img := Image.create(fw * FRAMES, frame_h, false, Image.FORMAT_RGBA8)
	for pass_i in 3:
		var set_mats: Dictionary = [mats_a, mats_n, mats_d][pass_i]
		for key in set_mats:
			var mi: MeshInstance3D = key[0]
			mi.set_surface_override_material(key[1], set_mats[key])
		for k in FRAMES:
			pivot.rotation.y = -TAU * k / FRAMES
			for w in 3:
				await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(fw, frame_h, Image.INTERPOLATE_LANCZOS)
			if pass_i == 2:
				depth_img.blit_rect(img, Rect2i(0, 0, fw, frame_h), Vector2i(k * fw, 0))
			else:
				var dst := atlas_a if pass_i == 0 else atlas_n
				dst.blit_rect(img, Rect2i(0, 0, fw, frame_h), Vector2i(k * fw, row_y))
	# Pack depth into the normal atlas alpha (1.0 = far/empty).
	for y in frame_h:
		for x in fw * FRAMES:
			var dpx := depth_img.get_pixel(x, y)
			var n := atlas_n.get_pixel(x, row_y + y)
			atlas_n.set_pixel(x, row_y + y, Color(n.r, n.g, n.b, dpx.r if dpx.a > 0.5 else 1.0))
	vp.queue_free()
	# depth_range: world-space thickness encoded by the 0..1 depth values (front..back).
	return {"name": variant, "world_w": world_w, "world_h": world_h, "height": height, "radius": radius, "depth_range": radius * 2.0}

func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
