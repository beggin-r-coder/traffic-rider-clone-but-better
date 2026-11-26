extends RefCounted
class_name Vegetation
## Roadside forest made of baked impostors (see scripts/tools/impostor_baker.gd).
## Builds one MultiMesh per road chunk (a single draw call for all its plants).

static var _meta: Dictionary
static var _species := {}            # name -> spec dict
static var _by_kind := {}            # kind -> [names]
static var material: ShaderMaterial
static var quad: QuadMesh
static var wall_material: ShaderMaterial

static func ensure_loaded() -> void:
	if material != null:
		return
	var f := FileAccess.open("res://assets/vegetation/vegetation.json", FileAccess.READ)
	_meta = JSON.parse_string(f.get_as_text())
	for sp in _meta["species"]:
		_species[sp["name"]] = sp
		if not _by_kind.has(sp["kind"]):
			_by_kind[sp["kind"]] = []
		_by_kind[sp["kind"]].append(sp["name"])
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/impostor.gdshader")
	material.set_shader_parameter("albedo_atlas", preload("res://assets/vegetation/atlas_albedo.png"))
	material.set_shader_parameter("normal_atlas", preload("res://assets/vegetation/atlas_normal.png"))
	material.set_shader_parameter("atlas_px", Vector2(_meta["atlas_w"], _meta["atlas_h"]))
	material.set_shader_parameter("frames", float(_meta["frames"]))
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.center_offset = Vector3(0, 0.5, 0)
	wall_material = ShaderMaterial.new()
	wall_material.shader = preload("res://shaders/forest_wall.gdshader")

static func set_tint(c: Color) -> void:
	ensure_loaded()
	material.set_shader_parameter("tint", c)

## A placement: [species name, scale min, scale max]
const ROWS := [
	# e_min, e_max (m beyond the rail), spacing (m along road), species table
	[1.2, 3.2, 1.7, [["fern_02_b", 1.3, 2.2], ["fern_02_b", 1.3, 2.2], ["shrub_02_c", 0.5, 0.9], ["searsia_lucida_a_LOD0", 0.7, 1.1]]],
	[2.8, 8.0, 2.6, [["fir_sapling_a", 2.8, 5.0], ["pine_sapling_small_a", 2.6, 4.5], ["searsia_lucida_a_LOD0", 1.0, 1.6], ["tree_small_02_LOD0", 1.2, 1.7], ["island_tree_02_LOD0", 1.0, 1.5]]],
	[7.0, 16.0, 2.9, [["fir_tree_01_a_LOD0", 0.7, 1.0], ["fir_tree_01_b_LOD0", 0.8, 1.15], ["fir_tree_01_c_LOD0", 0.8, 1.1], ["fir_sapling_a", 5.0, 8.0], ["tree_small_02_LOD0", 1.5, 2.1]]],
	[15.0, 29.0, 3.2, [["fir_tree_01_a_LOD0", 0.85, 1.25], ["fir_tree_01_b_LOD0", 1.0, 1.35], ["fir_tree_01_c_LOD0", 0.95, 1.3], ["fir_tree_01_a_LOD0", 0.85, 1.25]]],
]
const WALL_E := 30.0
const WALL_H := 17.0

## Builds the vegetation for one chunk. `road` provides point()/terrain_offset().
static func build_chunk(road: Road, s0: float, s1: float, rng: RandomNumberGenerator, density: float, shadows: bool) -> Node3D:
	ensure_loaded()
	var root := Node3D.new()
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
				var p := road.point(s, d, road.terrain_offset(s, d) - 0.12 * sc)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sp["world_w"] * sc, sp["world_h"] * sc, sp["world_w"] * sc))
				xforms.append(Transform3D(b, p))
				customs.append(Color(float(sp["row_y"]) / atlas_h, float(sp["row_h"]) / atlas_h, rng.randf(), rng.randf()))
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
	# Billboards turn to face the camera, so widen the culling box.
	mmi.custom_aabb = AABB(lo - Vector3(8, 1, 8), (hi - lo) + Vector3(16, 4, 16))
	root.add_child(mmi)
	root.add_child(_wall(road, s0, s1))
	return root

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
