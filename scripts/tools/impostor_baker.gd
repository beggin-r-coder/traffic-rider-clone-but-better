extends Node
## Dev tool (--bake-vegetation=<dir with Poly Haven glTF folders>):
## renders each plant from 8 directions into one shared albedo + normal atlas and writes
## res://assets/vegetation/{atlas_albedo,atlas_normal}.png and vegetation.json.
## Needs a real renderer (run under xvfb), not --headless.

const FRAME_W := 256
const FRAMES := 8
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
	["shrub_02", "shrub_02_c", "shrub", 256],
	["fern_02", "fern_02_b", "fern", 256],
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
	# Normal atlas: copy alpha from albedo so edges match, and fill empty texels with "facing camera".
	for y in atlas_n.get_height():
		for x in atlas_n.get_width():
			var a := atlas_a.get_pixel(x, y).a
			var n := atlas_n.get_pixel(x, y)
			if a < 0.02:
				n = Color(0.5, 0.5, 1.0)
			atlas_n.set_pixel(x, y, Color(n.r, n.g, n.b, a))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	atlas_a.save_png(OUT_DIR + "/atlas_albedo.png")
	atlas_n.save_png(OUT_DIR + "/atlas_normal.png")
	var f := FileAccess.open(OUT_DIR + "/vegetation.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"frame_w": FRAME_W, "frames": FRAMES, "atlas_w": FRAME_W * FRAMES, "atlas_h": total_h, "species": meta}, "  "))
	f.close()
	print("[bake] done ", total_h, "px atlas")
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
			mats_a[[mi, si]] = a
			mats_n[[mi, si]] = n
	var fw := FRAME_W
	for pass_i in 2:
		for key in mats_a:
			var mi: MeshInstance3D = key[0]
			mi.set_surface_override_material(key[1], mats_a[key] if pass_i == 0 else mats_n[key])
		for k in FRAMES:
			pivot.rotation.y = -TAU * k / FRAMES
			for w in 3:
				await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(fw, frame_h, Image.INTERPOLATE_LANCZOS)
			var dst := atlas_a if pass_i == 0 else atlas_n
			dst.blit_rect(img, Rect2i(0, 0, fw, frame_h), Vector2i(k * fw, row_y))
	vp.queue_free()
	return {"name": variant, "world_w": world_w, "world_h": world_h, "height": height, "radius": radius}

func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
