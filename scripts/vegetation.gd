extends RefCounted
class_name Vegetation
## Roadside forest.
## - Trees: depth impostors baked from Poly Haven models (scripts/tools/impostor_baker.gd),
##   one MultiMesh (= one draw call) per road chunk.
## - Undergrowth next to the road (grass clumps, ferns, shrubs): real Poly Haven meshes
##   (1-9k triangles each, auto-LODs), MultiMesh per variant, culled beyond ~100 m.

static var _meta: Dictionary
static var _species := {}
static var material: ShaderMaterial
static var quad: QuadMesh
static var wall_material: ShaderMaterial
static var _plant_meshes := {}       # "fern_0" -> Mesh
static var grass_material: ShaderMaterial
static var grass_mesh: ArrayMesh
## Grass card bands: e_min, e_max, spacing (m), scale min, scale max
const GRASS := [[0.5, 3.0, 0.7, 0.7, 1.2], [2.5, 10.0, 1.2, 0.8, 1.35]]
const GRASS_RANGE := 130.0

const PLANT_SOURCES := {
	"fern": ["res://assets/plants/fern_02/fern_02_1k.gltf", ["fern_02_b", "fern_02_c"]],
	"shrub": ["res://assets/plants/shrub_02/shrub_02_1k.gltf", ["shrub_02_a", "shrub_02_c"]],
}

## Tree rows: e_min, e_max (m beyond the guard rail), spacing (m), [species, scale min, scale max]...
const ROWS := [
	[2.6, 8.0, 2.5, [["fir_sapling_a", 2.6, 4.8], ["pine_sapling_small_a", 2.5, 4.4], ["searsia_lucida_a_LOD0", 1.0, 1.7], ["tree_small_02_LOD0", 1.2, 1.7], ["island_tree_02_LOD0", 1.0, 1.5]]],
	[7.0, 16.0, 2.8, [["fir_tree_01_a_LOD0", 0.7, 1.0], ["fir_tree_01_b_LOD0", 0.8, 1.15], ["fir_tree_01_c_LOD0", 0.8, 1.1], ["fir_sapling_a", 5.0, 8.0], ["tree_small_02_LOD0", 1.5, 2.1]]],
	[15.0, 29.0, 3.1, [["fir_tree_01_a_LOD0", 0.85, 1.25], ["fir_tree_01_b_LOD0", 1.0, 1.35], ["fir_tree_01_c_LOD0", 0.95, 1.3], ["fir_tree_01_a_LOD0", 0.85, 1.25]]],
]
## Undergrowth: kind, e_min, e_max, spacing, scale min, scale max
const UNDERGROWTH := [
	["fern", 0.6, 7.0, 1.9, 1.0, 1.8],
	["shrub", 1.8, 8.0, 5.0, 0.7, 1.1],
]
const UNDERGROWTH_RANGE := 100.0
const WALL_E := 30.0
const WALL_H := 18.0

static func ensure_loaded() -> void:
	if material != null:
		return
	var f := FileAccess.open("res://assets/vegetation/vegetation.json", FileAccess.READ)
	_meta = JSON.parse_string(f.get_as_text())
	for sp in _meta["species"]:
		_species[sp["name"]] = sp
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/impostor_hq.gdshader") if Game.quality >= 2 else preload("res://shaders/impostor.gdshader")
	material.set_shader_parameter("albedo_atlas", preload("res://assets/vegetation/atlas_albedo.png"))
	material.set_shader_parameter("normal_atlas", preload("res://assets/vegetation/atlas_normal.png"))
	material.set_shader_parameter("atlas_px", Vector2(_meta["atlas_w"], _meta["atlas_h"]))
	material.set_shader_parameter("frames", float(_meta["frames"]))
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.center_offset = Vector3(0, 0.5, 0)
	wall_material = ShaderMaterial.new()
	wall_material.shader = preload("res://shaders/forest_wall.gdshader")
	wall_material.set_shader_parameter("albedo_atlas", preload("res://assets/vegetation/atlas_albedo.png"))
	var ah: float = _meta["atlas_h"]
	var fir_rows := []
	for nm in ["fir_tree_01_a_LOD0", "fir_tree_01_b_LOD0", "fir_tree_01_c_LOD0"]:
		fir_rows.append(float(_species[nm]["row_y"]) / ah)
	wall_material.set_shader_parameter("row_y", Vector3(fir_rows[0], fir_rows[1], fir_rows[2]))
	wall_material.set_shader_parameter("row_h", 512.0 / ah)
	wall_material.set_shader_parameter("frames", float(_meta["frames"]))
	grass_material = ShaderMaterial.new()
	grass_material.shader = preload("res://shaders/grass_cards.gdshader")
	grass_material.set_shader_parameter("grass_albedo", preload("res://assets/vegetation/grass_albedo.png"))
	grass_material.set_shader_parameter("grass_normal", preload("res://assets/vegetation/grass_normal.png"))
	grass_mesh = _cross_mesh(2.0, 1.0)
	_load_plants()

## Two crossed vertical quads (width w, height h), base at y = 0.
static func _cross_mesh(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in [Vector3.RIGHT, Vector3.BACK]:
		var n: Vector3 = Vector3.BACK if axis == Vector3.RIGHT else Vector3.LEFT
		var a: Vector3 = -axis * w * 0.5
		var b: Vector3 = axis * w * 0.5
		var verts := [[a, Vector2(0, 1)], [a + Vector3.UP * h, Vector2(0, 0)], [b + Vector3.UP * h, Vector2(1, 0)], [b, Vector2(1, 1)]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(verts[i][1])
			st.add_vertex(verts[i][0])
	st.generate_tangents()
	return st.commit()

## Pull each variant mesh out of the Poly Haven glTFs.
static func _load_plants() -> void:
	for kind in PLANT_SOURCES:
		var src: Array = PLANT_SOURCES[kind]
		var scene: Node = (load(src[0]) as PackedScene).instantiate()
		var i := 0
		for vname in src[1]:
			var n := scene.find_child(vname, true, false)
			var mi: MeshInstance3D = n if n is MeshInstance3D else (n.find_child("*", true, false) as MeshInstance3D if n else null)
			if mi == null or mi.mesh == null:
				continue
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
				if m:
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
					m.roughness = 0.75
					m.backlight_enabled = true
					m.backlight = Color(0.25, 0.3, 0.1)
			_plant_meshes["%s_%d" % [kind, i]] = mi.mesh
			i += 1
		scene.free()

static func _variants(kind: String) -> Array:
	var out := []
	for k in _plant_meshes:
		if String(k).begins_with(kind + "_"):
			out.append(k)
	return out

static func set_tint(c: Color) -> void:
	ensure_loaded()
	material.set_shader_parameter("tint", c)

## Builds the vegetation for one chunk. `road` provides point()/terrain_offset().
static func build_chunk(road: Road, s0: float, s1: float, rng: RandomNumberGenerator, density: float, shadows: bool) -> Node3D:
	ensure_loaded()
	var root := Node3D.new()
	root.add_child(_trees(road, s0, s1, rng, density, shadows))
	for n in _undergrowth(road, s0, s1, rng, density):
		root.add_child(n)
	root.add_child(_grass(road, s0, s1, rng, density))
	root.add_child(_wall(road, s0, s1))
	return root

static func _trees(road: Road, s0: float, s1: float, rng: RandomNumberGenerator, density: float, shadows: bool) -> MultiMeshInstance3D:
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var atlas_h: float = _meta["atlas_h"]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for side: float in [-1.0, 1.0]:
		for row in ROWS:
			var spacing: float = row[2] / maxf(density, 0.2)
			var s := s0 + rng.randf() * spacing
			while s < s1:
				var pick: Array = row[3][rng.randi() % row[3].size()]
				var sp: Dictionary = _species[pick[0]]
				var e: float = rng.randf_range(row[0], row[1])
				var d: float = side * (Road.RAIL_D + e)
				var sc: float = rng.randf_range(pick[1], pick[2])
				var p := road.point(s, d, road.terrain_offset(s, d) - 0.1 * sc)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sp["world_w"] * sc, sp["world_h"] * sc, sp["world_w"] * sc))
				xforms.append(Transform3D(b, p))
				var kind := 0.0 if String(sp["kind"]).contains("conifer") else 1.0
				customs.append(Color(float(sp["row_y"]) / atlas_h, float(sp["row_h"]) / atlas_h, kind + rng.randf() * 0.999,
						float(sp.get("depth_range", sp["world_w"])) / float(sp["world_w"])))
				lo = lo.min(p)
				hi = hi.max(p + Vector3.UP * sp["world_h"] * sc)
				s += spacing * rng.randf_range(0.7, 1.3)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(lo - Vector3(8, 1, 8), (hi - lo) + Vector3(16, 4, 16))
	return mmi

static func _undergrowth(road: Road, s0: float, s1: float, rng: RandomNumberGenerator, density: float) -> Array:
	var per_mesh := {}
	for row in UNDERGROWTH:
		var variants := _variants(row[0])
		if variants.is_empty():
			continue
		for side: float in [-1.0, 1.0]:
			var spacing: float = row[3] / maxf(density, 0.2)
			var s := s0 + rng.randf() * spacing
			while s < s1:
				var key: String = variants[rng.randi() % variants.size()]
				# Denser right at the verge, thinning out into the forest.
				var e: float = lerpf(row[1], row[2], pow(rng.randf(), 1.5))
				var d: float = side * (Road.RAIL_D + e)
				var sc: float = rng.randf_range(row[4], row[5])
				var p := road.point(s, d, road.terrain_offset(s, d) - 0.03)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc * rng.randf_range(0.85, 1.2), sc))
				if not per_mesh.has(key):
					per_mesh[key] = []
				per_mesh[key].append(Transform3D(b, p))
				s += spacing * rng.randf_range(0.5, 1.5)
	var out := []
	for key in per_mesh:
		var xf: Array = per_mesh[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _plant_meshes[key]
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = UNDERGROWTH_RANGE * (0.6 if Game.quality == 0 else 1.0)
		out.append(mmi)
	return out

static func _grass(road: Road, s0: float, s1: float, rng: RandomNumberGenerator, density: float) -> MultiMeshInstance3D:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for side: float in [-1.0, 1.0]:
		for band in GRASS:
			var spacing: float = band[2] / maxf(density, 0.2)
			var s := s0 + rng.randf() * spacing
			while s < s1:
				var e: float = lerpf(band[0], band[1], rng.randf())
				var d: float = side * (Road.RAIL_D + e)
				var sc: float = rng.randf_range(band[3], band[4])
				var p := road.point(s, d, road.terrain_offset(s, d) - 0.04)
				xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc * rng.randf_range(0.85, 1.25), sc)), p))
				cd.append(Color(rng.randf() * 0.5, rng.randf(), 0, 0))
				s += spacing * rng.randf_range(0.6, 1.4)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = grass_mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, cd[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = grass_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = GRASS_RANGE * (0.6 if Game.quality == 0 else 1.0)
	return mmi

## Dark forest band behind the trees on both sides, so no gaps show open land.
static func _wall(road: Road, s0: float, s1: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 5
	for side: float in [-1.0, 1.0]:
		var d: float = side * (Road.RAIL_D + WALL_E)
		for i in steps:
			var sa := s0 + (s1 - s0) * i / steps
			var sb := s0 + (s1 - s0) * (i + 1) / steps
			var a0 := road.point(sa, d, road.terrain_offset(sa, d) - 0.5)
			var b0 := road.point(sb, d, road.terrain_offset(sb, d) - 0.5)
			var a1 := a0 + Vector3.UP * WALL_H
			var b1 := b0 + Vector3.UP * WALL_H
			var n := road.basis_at(sa).x * -side
			for v in [[a0, Vector2(sa, 1)], [a1, Vector2(sa, 0)], [b1, Vector2(sb, 0)], [a0, Vector2(sa, 1)], [b1, Vector2(sb, 0)], [b0, Vector2(sb, 1)]]:
				st.set_normal(n)
				st.set_uv(v[1])
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = wall_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
