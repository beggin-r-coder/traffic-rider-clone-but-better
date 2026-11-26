extends Node3D
class_name Road
## Endless procedural highway with gentle curves and hills.
##
## Everything on the road lives in road ("Frenet") coordinates: `s` = distance along the
## centre line, `d` = lateral offset in metres (+ = right). `xform(s, d)` maps to world space.

const DS := 2.0                    # spacing of centre-line samples
const CHUNK_LEN := 40.0
const LANE_W := 3.6
const LANES := 4
const HALF_W := LANE_W * LANES * 0.5       # 7.2 m
const SHOULDER := 1.8
const RAIL_D := HALF_W + SHOULDER + 0.25    # guard rail offset from centre
const VIEW_AHEAD := 640.0
const KEEP_BEHIND := 80.0
const TERRAIN_W := 260.0

var two_way := false
var night := false
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()

# centre-line samples
var _pos := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _curv := PackedFloat32Array()
# curvature program: list of [s_start, s_end, k_start, k_end]
var _segs: Array = []
var _seg_end := 0.0

var _chunks := {}          # chunk index -> Node3D
var _mat_road: ShaderMaterial
var _mat_terrain: ShaderMaterial
var _mat_rail: StandardMaterial3D
var _mat_post: StandardMaterial3D
var _mat_pole: StandardMaterial3D
var _mat_lamp: StandardMaterial3D
var _mat_glow: StandardMaterial3D
var _mesh_pole: Mesh
var _mesh_post: Mesh
var _mesh_glow: Mesh
var _mesh_sign: Mesh

func setup(seed_value: int, is_two_way: bool, is_night: bool) -> void:
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.004
	noise.fractal_octaves = 3
	two_way = is_two_way
	night = is_night
	_build_materials()
	_build_props()
	_segs.clear()
	_seg_end = 0.0
	# Long straight start so the player can get going.
	_segs.append([0.0, 500.0, 0.0, 0.0])
	_seg_end = 500.0
	_pos.clear(); _yaw.clear(); _curv.clear()
	_pos.append(Vector3.ZERO); _yaw.append(0.0); _curv.append(0.0)

# ---------------------------------------------------------------- centre line

func _extend_program(to_s: float) -> void:
	while _seg_end < to_s:
		var k_prev: float = _segs[-1][3]
		var difficulty := clampf(_seg_end / 8000.0, 0.0, 1.0)
		if absf(k_prev) < 1e-6:
			# Straight -> ramp into a curve.
			var radius := lerpf(1400.0, 520.0, difficulty) * rng.randf_range(0.8, 1.4)
			var k := (1.0 if rng.randf() < 0.5 else -1.0) / radius
			var ramp := rng.randf_range(90.0, 160.0)
			var hold := rng.randf_range(80.0, 320.0)
			_segs.append([_seg_end, _seg_end + ramp, 0.0, k]); _seg_end += ramp
			_segs.append([_seg_end, _seg_end + hold, k, k]); _seg_end += hold
			# Sometimes flow straight into an opposite curve (S-bend).
			if rng.randf() < 0.35:
				var k2 := -k * rng.randf_range(0.7, 1.2)
				var r2 := rng.randf_range(140.0, 220.0)
				var h2 := rng.randf_range(80.0, 240.0)
				_segs.append([_seg_end, _seg_end + r2, k, k2]); _seg_end += r2
				_segs.append([_seg_end, _seg_end + h2, k2, k2]); _seg_end += h2
				k = k2
			var ramp_out := rng.randf_range(90.0, 160.0)
			_segs.append([_seg_end, _seg_end + ramp_out, k, 0.0]); _seg_end += ramp_out
		else:
			var straight := rng.randf_range(150.0, 600.0) * lerpf(1.3, 0.7, difficulty)
			_segs.append([_seg_end, _seg_end + straight, 0.0, 0.0]); _seg_end += straight

var _seg_cursor := 0
func curvature_at(s: float) -> float:
	_extend_program(s + 10.0)
	if _seg_cursor >= _segs.size() or s < _segs[_seg_cursor][0]:
		_seg_cursor = 0
	while _seg_cursor < _segs.size() - 1 and s >= _segs[_seg_cursor][1]:
		_seg_cursor += 1
	var g: Array = _segs[_seg_cursor]
	var t := clampf((s - g[0]) / maxf(g[1] - g[0], 0.001), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(g[2], g[3], t)

func height_at(s: float) -> float:
	var ramp := clampf(s / 600.0, 0.0, 1.0)
	return ramp * (7.0 * sin(s / 420.0) + 3.0 * sin(s / 173.0 + 1.3) + 1.2 * sin(s / 61.0 + 0.4))

func grade_at(s: float) -> float:
	return (height_at(s + 1.0) - height_at(s - 1.0)) * 0.5

func _ensure(s: float) -> void:
	var need := int(ceil(s / DS)) + 2
	while _pos.size() <= need:
		var i := _pos.size()
		var sm := (i - 0.5) * DS
		var k := curvature_at(sm)
		var yaw := _yaw[i - 1] + k * DS
		var ym := (_yaw[i - 1] + yaw) * 0.5
		var p := _pos[i - 1] + Vector3(sin(ym), 0.0, -cos(ym)) * DS
		p.y = height_at(i * DS)
		_pos.append(p)
		_yaw.append(yaw)
		_curv.append(curvature_at(i * DS))

func yaw_at(s: float) -> float:
	_ensure(s)
	var f := maxf(s, 0.0) / DS
	var i := int(f)
	return lerpf(_yaw[i], _yaw[i + 1], f - i)

func center_at(s: float) -> Vector3:
	_ensure(s)
	var f := maxf(s, 0.0) / DS
	var i := int(f)
	var p := _pos[i].lerp(_pos[i + 1], f - i)
	p.y = height_at(s)
	return p

## Road-aligned basis at s (x = right, y = up incl. slope, z = backwards).
func basis_at(s: float) -> Basis:
	var yaw := yaw_at(s)
	var fwd := Vector3(sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, sin(yaw))
	var fwd3 := (fwd + Vector3.UP * grade_at(s)).normalized()
	var up := (-fwd3).cross(right).normalized()
	return Basis(right, up, -fwd3)

func xform(s: float, d: float, h: float = 0.0) -> Transform3D:
	var b := basis_at(s)
	return Transform3D(b, center_at(s) + b.x * d + b.y * h)

func point(s: float, d: float, h: float = 0.0) -> Vector3:
	var yaw := yaw_at(s)
	return center_at(s) + Vector3(cos(yaw), 0.0, sin(yaw)) * d + Vector3.UP * h

## Terrain height relative to the road surface at (s, d).
func terrain_offset(s: float, d: float) -> float:
	var e := absf(d) - (RAIL_D + 1.0)
	if e <= 0.0:
		return -0.05
	var ditch := -0.9 * clampf(e / 3.0, 0.0, 1.0) * (1.0 - clampf((e - 5.0) / 6.0, 0.0, 1.0))
	var a := clampf((e - 6.0) / 70.0, 0.0, 1.0)
	var hills := noise.get_noise_2d(s, d * 1.3) * 34.0 * a * a + a * 6.0
	return ditch + hills

# ---------------------------------------------------------------- streaming

func update_stream(player_s: float) -> void:
	var first := int(floor(maxf(player_s - KEEP_BEHIND, 0.0) / CHUNK_LEN))
	var last := int(floor((player_s + VIEW_AHEAD) / CHUNK_LEN))
	for k in _chunks.keys():
		if k < first or k > last:
			_chunks[k].queue_free()
			_chunks.erase(k)
	# Build at most two chunks per frame to avoid hitches.
	var built := 0
	for k in range(first, last + 1):
		if not _chunks.has(k):
			_chunks[k] = _build_chunk(k)
			built += 1
			if built >= 2 and _chunks.size() > 4:
				break

func chunk_count() -> int:
	return _chunks.size()

# ---------------------------------------------------------------- chunk building

func _build_chunk(k: int) -> Node3D:
	var s0 := k * CHUNK_LEN
	var s1 := s0 + CHUNK_LEN
	_ensure(s1 + DS)
	var node := Node3D.new()
	node.name = "Chunk%d" % k
	add_child(node)
	var crng := RandomNumberGenerator.new()
	crng.seed = hash(k * 7919 + rng.seed)

	var steps := 10
	var ss := PackedFloat32Array()
	for i in steps + 1:
		ss.append(s0 + CHUNK_LEN * i / steps)

	# --- road surface (incl. shoulders) ---
	var road_d := [-(HALF_W + SHOULDER + 0.6), -HALF_W, HALF_W, HALF_W + SHOULDER + 0.6]
	node.add_child(_strip_mesh(ss, road_d, _mat_road, 0.0, true))

	# --- terrain both sides ---
	# Terrain only needs to reach just past the forest wall.
	var tr := [RAIL_D + 0.4, RAIL_D + 2.0, RAIL_D + 4.5, RAIL_D + 9.0, RAIL_D + 16.0, RAIL_D + 24.0, RAIL_D + 33.0, RAIL_D + 45.0]
	var tl := []
	for x in tr:
		tl.push_front(-x)
	var tss := PackedFloat32Array()
	for i in 5 + 1:
		tss.append(s0 + CHUNK_LEN * i / 5)
	var ter := MeshInstance3D.new()
	ter.mesh = _terrain_mesh(tss, tl, tr)
	ter.material_override = _mat_terrain
	ter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ter)

	# --- guard rails ---
	for side: float in [-1.0, 1.0]:
		if two_way or true:
			node.add_child(_rail_mesh(ss, side * RAIL_D, side))
	# posts (multimesh)
	var posts: Array[Transform3D] = []
	var s_post: float = ceil(s0 / 4.0) * 4.0
	while s_post < s1:
		for side: float in [-1.0, 1.0]:
			var t := xform(s_post, side * (RAIL_D + 0.08))
			posts.append(t)
		s_post += 4.0
	node.add_child(_multimesh(_mesh_post, posts, _mat_post, false))

	# --- street lights every 50 m, alternating sides ---
	var lamps: Array[Transform3D] = []
	var glows: Array[Transform3D] = []
	var s_lamp: float = ceil(s0 / 50.0) * 50.0
	while s_lamp < s1:
		var side := 1.0 if int(s_lamp / 50.0) % 2 == 0 else -1.0
		var t := xform(s_lamp, side * (RAIL_D + 0.7))
		if side < 0:
			t.basis = t.basis.rotated(t.basis.y, PI)
		lamps.append(t)
		if night:
			var g := xform(s_lamp, side * (RAIL_D - 2.6), 0.03)
			glows.append(g)
		s_lamp += 50.0
	if not lamps.is_empty():
		node.add_child(_multimesh(_mesh_pole, lamps, null, true))
	if not glows.is_empty():
		node.add_child(_multimesh(_mesh_glow, glows, _mat_glow, false))

	# --- distance sign every 1 km ---
	if int(s0) % 1000 == 0 and s0 > 0:
		var st := xform(s0, RAIL_D + 1.6)
		var sign := MeshInstance3D.new()
		sign.mesh = _mesh_sign
		sign.transform = st
		node.add_child(sign)
		var lbl := Label3D.new()
		lbl.text = "%d km" % int(s0 / 1000.0)
		lbl.font_size = 96
		lbl.pixel_size = 0.006
		lbl.modulate = Color(1, 1, 1)
		lbl.outline_size = 0
		lbl.position = Vector3(0, 2.35, 0.06)
		lbl.rotation.y = 0.0
		lbl.double_sided = false
		sign.add_child(lbl)

	# --- dense roadside forest (baked Poly Haven impostors, one draw call per chunk) ---
	var density: float = [0.55, 0.85, 1.0][clampi(Game.quality, 0, 2)]
	node.add_child(Vegetation.build_chunk(self, s0, s1, crng, density, Game.quality > 0))
	return node

func _multimesh(mesh: Mesh, xforms: Array[Transform3D], mat: Material, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and Game.quality > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

## Flat strip across given lateral offsets; UV.x = d (m), UV.y = s (m, wrapped).
func _strip_mesh(ss: PackedFloat32Array, ds: Array, mat: Material, h: float, uv_world: bool) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv_off := fmod(ss[0], 240.0) - ss[0]
	for i in ss.size() - 1:
		for j in ds.size() - 1:
			var quad := [[ss[i], ds[j]], [ss[i], ds[j + 1]], [ss[i + 1], ds[j + 1]], [ss[i + 1], ds[j]]]
			var pts := []
			for q in quad:
				var b := basis_at(q[0])
				pts.append([point(q[0], q[1], h), b.y, Vector2(q[1], q[0] + uv_off)])
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(pts[idx][1])
				st.set_uv(pts[idx][2])
				st.add_vertex(pts[idx][0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _terrain_mesh(ss: PackedFloat32Array, left: Array, right: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side_ds in [left, right]:
		var grid := []
		for i in ss.size():
			var row := []
			for d in side_ds:
				var h := terrain_offset(ss[i], d)
				var p := point(ss[i], d, h)
				var e := clampf((absf(d) - RAIL_D) / 120.0, 0.0, 1.0)
				var nv := noise.get_noise_2d(ss[i] * 3.0, d * 3.0)
				var c := Color(0.22, 0.42, 0.12).lerp(Color(0.36, 0.46, 0.16), 0.5 + 0.5 * nv)
				if absf(d) < RAIL_D + 1.0:
					c = Color(0.42, 0.40, 0.33)
				# Shaded forest floor (moss, needles) under the trees.
				var forest := clampf((absf(d) - RAIL_D - 2.0) / 5.0, 0.0, 1.0)
				c = c.lerp(Color(0.09, 0.14, 0.05).lerp(Color(0.15, 0.12, 0.07), 0.5 + 0.5 * nv), forest)
				c = c.lerp(c * 0.85, e * 0.6)
				row.append([p, c])
			grid.append(row)
		for i in ss.size() - 1:
			for j in side_ds.size() - 1:
				var a = grid[i][j]
				var b = grid[i][j + 1]
				var c = grid[i + 1][j + 1]
				var d = grid[i + 1][j]
				for v in [a, c, b, a, d, c]:
					st.set_color(v[1])
					st.add_vertex(v[0])
	st.generate_normals()
	return st.commit()

func _rail_mesh(ss: PackedFloat32Array, d: float, side: float) -> MeshInstance3D:
	# W-beam approximated by a 3-segment profile facing the road.
	var prof := [[0.0, 0.52], [0.06 * side, 0.6], [0.0, 0.68], [0.06 * side, 0.76], [0.0, 0.82]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in ss.size() - 1:
		for j in prof.size() - 1:
			var p00 := point(ss[i], d + prof[j][0], prof[j][1])
			var p01 := point(ss[i], d + prof[j + 1][0], prof[j + 1][1])
			var p10 := point(ss[i + 1], d + prof[j][0], prof[j][1])
			var p11 := point(ss[i + 1], d + prof[j + 1][0], prof[j + 1][1])
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
			st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat_rail
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# ---------------------------------------------------------------- materials & props

func _build_materials() -> void:
	_mat_road = ShaderMaterial.new()
	_mat_road.shader = preload("res://shaders/road.gdshader")
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var n := FastNoiseLite.new()
	n.frequency = 0.08
	n.fractal_octaves = 4
	tex.noise = n
	tex.generate_mipmaps = true
	_mat_road.set_shader_parameter("noise_tex", tex)
	_mat_road.set_shader_parameter("asphalt_albedo", preload("res://assets/textures/asphalt_02/asphalt_02_diff_4k.jpg"))
	_mat_road.set_shader_parameter("asphalt_normal", preload("res://assets/textures/asphalt_02/asphalt_02_nor_gl_4k.jpg"))
	_mat_road.set_shader_parameter("asphalt_arm", preload("res://assets/textures/asphalt_02/asphalt_02_arm_4k.jpg"))
	_mat_road.set_shader_parameter("two_way", two_way)
	_mat_road.set_shader_parameter("lane_w", LANE_W)
	_mat_road.set_shader_parameter("half_w", HALF_W)

	_mat_terrain = ShaderMaterial.new()
	_mat_terrain.shader = preload("res://shaders/terrain.gdshader")
	var tex2 := NoiseTexture2D.new()
	tex2.width = 256
	tex2.height = 256
	tex2.seamless = true
	var n2 := FastNoiseLite.new()
	n2.frequency = 0.05
	n2.fractal_octaves = 4
	tex2.noise = n2
	tex2.generate_mipmaps = true
	_mat_terrain.set_shader_parameter("noise_tex", tex2)

	_mat_rail = StandardMaterial3D.new()
	_mat_rail.albedo_color = Color(0.72, 0.74, 0.76)
	_mat_rail.metallic = 0.45
	_mat_rail.roughness = 0.4
	_mat_rail.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_post = StandardMaterial3D.new()
	_mat_post.albedo_color = Color(0.5, 0.52, 0.55)
	_mat_post.metallic = 0.6
	_mat_post.roughness = 0.5
	_mat_pole = StandardMaterial3D.new()
	_mat_pole.albedo_color = Color(0.5, 0.52, 0.54)
	_mat_pole.metallic = 0.15
	_mat_pole.roughness = 0.6
	_mat_lamp = StandardMaterial3D.new()
	_mat_lamp.albedo_color = Color(1, 0.9, 0.7)
	_mat_lamp.emission_enabled = night
	_mat_lamp.emission = Color(1.0, 0.8, 0.5)
	_mat_lamp.emission_energy_multiplier = 12.0
	_mat_glow = StandardMaterial3D.new()
	_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_glow.albedo_texture = _radial_tex()
	_mat_glow.albedo_color = Color(1.0, 0.7, 0.38, 0.85)
	_mat_glow.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

func _radial_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

func _mat(c: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _build_props() -> void:
	_mesh_pole = Props.street_light(_mat_pole, _mat_lamp)
	_mesh_post = Props.box(Vector3(0.1, 0.8, 0.1), Vector3(0, 0.4, 0))
	_mesh_sign = Props.sign(_mat(Color(0.05, 0.38, 0.18), 0.6), _mat_pole)
	var q := QuadMesh.new()
	q.size = Vector2(14.0, 14.0)
	q.orientation = PlaneMesh.FACE_Y
	_mesh_glow = q
