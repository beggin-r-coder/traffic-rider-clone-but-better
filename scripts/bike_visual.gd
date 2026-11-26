extends Node3D
class_name BikeVisual
## Loads the supplied motorcycle model, splits its wheels out so they can spin,
## and exposes lean / wheel spin / brake light controls.
##
## Local space: origin on the ground halfway between the tyre contact patches,
## -Z is forward, +Y is up.

const MODEL := preload("res://assets/bike/scene.gltf")

## Paint schemes selectable in the garage: [name, hue shift, saturation x, value x, swatch].
const PAINTS := [
	["Racing Blue", 0.0, 1.0, 1.0, Color(0.1, 0.2, 0.75)],
	["Rosso", 0.32, 1.1, 1.25, Color(0.85, 0.08, 0.08)],
	["Midnight", 0.0, 0.15, 0.35, Color(0.12, 0.12, 0.14)],
	["Acid Green", -0.37, 1.0, 1.5, Color(0.35, 0.85, 0.1)],
	["Sunburst", 0.42, 1.1, 1.8, Color(1.0, 0.55, 0.05)],
	["Pearl", 0.0, 0.05, 2.6, Color(0.9, 0.9, 0.92)],
]

var lean_node: Node3D
var front_wheel: Node3D
var rear_wheel: Node3D
var wheel_radius := 0.3
var wheelbase := 1.4
var front_hub := Vector3.ZERO
var rear_hub := Vector3.ZERO
var _wheel_angle := 0.0
var _taillight_mats: Array[StandardMaterial3D] = []
var _paint_mats: Array[ShaderMaterial] = []
var _paint_cache := {}

func _ready() -> void:
	lean_node = Node3D.new()
	lean_node.name = "Lean"
	add_child(lean_node)
	var model: Node3D = MODEL.instantiate()
	lean_node.add_child(model)
	_setup_model(model)

func _setup_model(model: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect(model, meshes)
	# Wheel geometry: whole meshes that belong to one wheel, and shared meshes to split.
	var front_parts: Array = []
	var rear_parts: Array = []
	var split_parts: Array = []
	var tyre_f_aabb := AABB()
	var tyre_r_aabb := AABB()
	for mi in meshes:
		var mname := _mat_name(mi)
		match mname:
			"Front_Tire":
				front_parts.append(mi)
				tyre_f_aabb = mi.mesh.get_aabb()
			"Rear_Tire":
				rear_parts.append(mi)
				tyre_r_aabb = mi.mesh.get_aabb()
			"Rims", "Brake_Discs":
				split_parts.append(mi)
			"Sprocket":
				rear_parts.append(mi)
			"Taillight", "Taillight_Glass":
				var m := _dup_mat(mi)
				if m:
					_taillight_mats.append(m)
			"Main_Decals", "Main_Decals_-_Plastics", "Front_End", "Front_End_-_Plastics":
				_make_paintable(mi)
			"Glass", "Windshield":
				var g := _dup_mat(mi)
				if g:
					g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					g.albedo_texture = null
					g.albedo_color = Color(0.08, 0.1, 0.13, 0.2)
					g.roughness = 0.05
					g.metallic_specular = 0.25
					g.cull_mode = BaseMaterial3D.CULL_DISABLED
			"Headlights", "DRLs":
				var h := _dup_mat(mi)
				if h:
					h.emission_enabled = true
					h.emission = Color(1.0, 0.97, 0.9)
					h.emission_energy_multiplier = 3.0
	# Mesh-local hub centres (model space before the importer's root transform).
	var f_center := tyre_f_aabb.get_center()
	var r_center := tyre_r_aabb.get_center()
	wheel_radius = maxf(tyre_f_aabb.size.y, tyre_r_aabb.size.y) * 0.5
	# Convert to our local space through the mesh instance's global transform relative to us.
	var xf: Transform3D = _rel_xform(front_parts[0])
	front_hub = xf * f_center
	rear_hub = xf * r_center
	wheelbase = absf(front_hub.z - rear_hub.z)
	# Re-centre the whole model so origin is midway between contact patches on the ground.
	var ground_y := minf(front_hub.y, rear_hub.y) - wheel_radius
	var mid_z := (front_hub.z + rear_hub.z) * 0.5
	model.position -= Vector3(0, ground_y, mid_z)
	front_hub -= Vector3(0, ground_y, mid_z)
	rear_hub -= Vector3(0, ground_y, mid_z)
	front_hub.x = 0.0
	rear_hub.x = 0.0

	front_wheel = Node3D.new()
	front_wheel.name = "FrontWheel"
	front_wheel.position = front_hub
	lean_node.add_child(front_wheel)
	rear_wheel = Node3D.new()
	rear_wheel.name = "RearWheel"
	rear_wheel.position = rear_hub
	lean_node.add_child(rear_wheel)

	var split_z := (f_center.z + r_center.z) * 0.5
	for mi in front_parts:
		_move_to_wheel(mi, front_wheel)
	for mi in rear_parts:
		_move_to_wheel(mi, rear_wheel)
	for mi in split_parts:
		var halves := _split_mesh(mi.mesh, split_z, f_center.z > r_center.z)
		for i in 2:
			if halves[i] == null:
				continue
			var n := MeshInstance3D.new()
			n.mesh = halves[i]
			n.name = mi.name + ("_F" if i == 0 else "_R")
			var target := front_wheel if i == 0 else rear_wheel
			target.add_child(n)
			n.transform = _wheel_rel(mi, target)
		mi.queue_free()
	for mi in meshes:
		if is_instance_valid(mi):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _wheel_rel(mi: MeshInstance3D, target: Node3D) -> Transform3D:
	return _rel_xform_node(target).affine_inverse() * _rel_xform(mi)

func _move_to_wheel(mi: MeshInstance3D, target: Node3D) -> void:
	var t := _wheel_rel(mi, target)
	mi.get_parent().remove_child(mi)
	target.add_child(mi)
	mi.transform = t

## Transform of a node relative to this BikeVisual (works before entering the tree).
func _rel_xform(n: Node3D) -> Transform3D:
	return _rel_xform_node(n)

func _rel_xform_node(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)

func _mat_name(mi: MeshInstance3D) -> String:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return ""
	var m := mi.mesh.surface_get_material(0)
	return m.resource_name if m else ""

func _dup_mat(mi: MeshInstance3D) -> BaseMaterial3D:
	var m := mi.mesh.surface_get_material(0)
	if not (m is BaseMaterial3D):
		return null
	var d: BaseMaterial3D = m.duplicate()
	mi.set_surface_override_material(0, d)
	return d

## Splits a mesh's triangles into [front, rear] halves by triangle centroid z.
func _split_mesh(mesh: Mesh, split_z: float, front_is_positive: bool) -> Array:
	var out := [null, null]
	var sts := [SurfaceTool.new(), SurfaceTool.new()]
	var counts := [0, 0]
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var has_uv: bool = uvs != null and uvs.size() == verts.size()
		for st in sts:
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mesh.surface_get_material(si))
		var tri_count := idx.size() / 3
		for t in tri_count:
			var a := idx[t * 3]
			var b := idx[t * 3 + 1]
			var c := idx[t * 3 + 2]
			var cz := (verts[a].z + verts[b].z + verts[c].z) / 3.0
			var is_front := (cz > split_z) == front_is_positive
			var k := 0 if is_front else 1
			var st: SurfaceTool = sts[k]
			for v in [a, b, c]:
				st.set_normal(norms[v])
				if has_uv:
					st.set_uv(uvs[v])
				st.add_vertex(verts[v])
			counts[k] += 1
	for k in 2:
		if counts[k] > 0:
			out[k] = sts[k].commit()
	return out

## Lean (roll) in radians, positive = lean right.
func set_lean(angle: float) -> void:
	lean_node.rotation.z = -angle

## Advance wheel spin by the distance travelled.
func roll(distance: float) -> void:
	_wheel_angle = fmod(_wheel_angle - distance / maxf(wheel_radius, 0.05), TAU)
	front_wheel.rotation.x = _wheel_angle
	rear_wheel.rotation.x = _wheel_angle

func set_brake_light(on: bool) -> void:
	for m in _taillight_mats:
		m.emission_enabled = true
		m.emission = Color(1, 0.05, 0.02)
		m.emission_energy_multiplier = 6.0 if on else 1.2

func _make_paintable(mi: MeshInstance3D) -> void:
	for si in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
		if m == null or m.albedo_texture == null:
			continue
		var sm: ShaderMaterial = _paint_cache.get(m)
		if sm == null:
			sm = ShaderMaterial.new()
			sm.shader = preload("res://shaders/bike_paint.gdshader")
			sm.set_shader_parameter("albedo_tex", m.albedo_texture)
			sm.set_shader_parameter("roughness", maxf(m.roughness, 0.12))
			sm.set_shader_parameter("metallic", m.metallic)
			_paint_cache[m] = sm
			_paint_mats.append(sm)
		mi.set_surface_override_material(si, sm)

func set_paint(i: int) -> void:
	var p: Array = PAINTS[clampi(i, 0, PAINTS.size() - 1)]
	for sm in _paint_mats:
		sm.set_shader_parameter("hue_shift", p[1])
		sm.set_shader_parameter("sat_mul", p[2])
		sm.set_shader_parameter("val_mul", p[3])
