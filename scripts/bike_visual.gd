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
var dash: DashDisplay
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
				if mname == "Main_Decals":
					_strip_ground_quad(mi)
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
			"Display":
				var dm := _dup_mat(mi)
				if dm:
					dash = DashDisplay.new()
					dash.name = "Dash"
					add_child(dash)
					dash.setup(dm.albedo_texture)
					var vt := dash.get_texture()
					dm.albedo_texture = vt
					dm.emission_enabled = true
					dm.emission_texture = vt
					dm.emission = Color(1, 1, 1)
					dm.emission_energy_multiplier = 0.9
					dm.roughness = 0.15
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
	_split_levers(model)
	_apply_finishes()

## Render layer for the bike itself, so the reflection probe can leave it out of its capture.
const BIKE_LAYER := 2

## Surface finishes: [metallic, roughness, clearcoat]. Makes the bike read as polished and shiny.
const FINISHES := {
	"Mechanicals-Aluminum": [1.0, 0.24, 0.0],
	"Front_End_-_Aluminum": [1.0, 0.18, 0.0],
	"Main_Decals_-_Aluminum": [1.0, 0.2, 0.0],
	"Exhaust-Aluminum": [1.0, 0.16, 0.0],
	"Muffler-Aluminum": [1.0, 0.2, 0.0],
	"Muffler": [0.9, 0.26, 0.0],
	"Exhaust": [0.9, 0.3, 0.0],
	"Forks": [1.0, 0.06, 0.0],
	"Bolts": [1.0, 0.22, 0.0],
	"Brake_Discs": [1.0, 0.28, 0.0],
	"Sprocket": [0.9, 0.32, 0.0],
	"Chain": [0.8, 0.38, 0.0],
	"Mirrors": [1.0, 0.02, 0.0],
	"Rims": [0.25, 0.12, 1.0],
	"Lights_-_Plastic": [0.2, 0.12, 1.0],
	"Mechanicals": [0.35, 0.45, 0.0],
	"Seats": [0.0, 0.55, 0.0],
	"Display": [0.0, 0.08, 1.0],
}

func _apply_finishes() -> void:
	var all: Array[MeshInstance3D] = []
	_collect(self, all)
	var cache := {}
	for mi in all:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.layers = BIKE_LAYER
		for si in mi.mesh.get_surface_count():
			if mi.get_surface_override_material(si) != null:
				continue   # paint / glass / lights already customised
			var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if m == null or not FINISHES.has(m.resource_name):
				continue
			var d: BaseMaterial3D = cache.get(m)
			if d == null:
				d = m.duplicate()
				var f: Array = FINISHES[m.resource_name]
				d.metallic = f[0]
				d.roughness = f[1]
				d.metallic_specular = 0.6
				d.roughness_texture = null
				d.metallic_texture = null
				if f[2] > 0.0:
					d.clearcoat_enabled = true
					d.clearcoat = f[2]
					d.clearcoat_roughness = 0.05
				if m.resource_name == "Mirrors":
					d.albedo_color = Color(0.92, 0.93, 0.95)
				cache[m] = d
			mi.set_surface_override_material(si, d)

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

# --- brake (right) and clutch (left) levers, cut out of the merged mesh so they can pivot ---
const LEVER_PIVOT := Vector3(0.238, 0.952, -0.494)   # right lever pivot (bike space); left is mirrored
const LEVER_MAX_ANGLE := deg_to_rad(18.0)
const LEVER_BOX_MIN := Vector3(0.236, 0.885, -0.53)
const LEVER_BOX_MAX := Vector3(0.385, 0.97, -0.44)
var brake_lever: Node3D
var clutch_lever: Node3D

## Axis the lever swings about (perpendicular to the bar, roughly "up"); for side +1 / -1.
static func lever_axis(side: float) -> Vector3:
	var gi := Vector3(0.228 * side, 0.959, -0.430)
	var go := Vector3(0.348 * side, 0.921, -0.363)
	var a := (go - gi).normalized()
	return (Vector3.UP - a * Vector3.UP.dot(a)).normalized()

## Rotation of a lever for pull 0..1 (moves the lever end back towards the grip).
static func lever_basis(side: float, pull: float) -> Basis:
	return Basis(lever_axis(side), -side * LEVER_MAX_ANGLE * clampf(pull, 0.0, 1.0))

static func lever_pivot(side: float) -> Vector3:
	return Vector3(LEVER_PIVOT.x * side, LEVER_PIVOT.y, LEVER_PIVOT.z)

func _split_levers(model: Node3D) -> void:
	var all: Array[MeshInstance3D] = []
	_collect(model, all)
	var parts := {1.0: SurfaceTool.new(), -1.0: SurfaceTool.new()}
	var counts := {1.0: 0, -1.0: 0}
	var lever_mat: Material = null
	for mi in all:
		if _mat_name(mi) != "Front_End_-_Aluminum":
			continue
		var xf := _rel_xform(mi)
		var src := mi.mesh
		var out := ArrayMesh.new()
		for si in src.get_surface_count():
			var arrays := src.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs = arrays[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			lever_mat = src.surface_get_material(si)
			var keep := PackedInt32Array()
			for side in [1.0, -1.0]:
				if counts[side] == 0:
					parts[side].begin(Mesh.PRIMITIVE_TRIANGLES)
					parts[side].set_material(lever_mat)
			for t in idx.size() / 3:
				var tri := [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
				var cen := (xf * verts[tri[0]] + xf * verts[tri[1]] + xf * verts[tri[2]]) / 3.0
				var side := signf(cen.x)
				var q := Vector3(absf(cen.x), cen.y, cen.z)
				var inside := q.x > LEVER_BOX_MIN.x and q.x < LEVER_BOX_MAX.x and q.y > LEVER_BOX_MIN.y and q.y < LEVER_BOX_MAX.y and q.z > LEVER_BOX_MIN.z and q.z < LEVER_BOX_MAX.z
				if inside:
					var piv := lever_pivot(side)
					for v in tri:
						parts[side].set_normal(xf.basis * norms[v])
						if uvs != null and uvs.size() == verts.size():
							parts[side].set_uv(uvs[v])
						parts[side].add_vertex(xf * verts[v] - piv)
					counts[side] += 1
				else:
					keep.append_array(tri)
			arrays[Mesh.ARRAY_INDEX] = keep
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(si, lever_mat)
		mi.mesh = out
	for side in [1.0, -1.0]:
		if counts[side] == 0:
			continue
		var pivot := Node3D.new()
		pivot.name = "BrakeLever" if side > 0 else "ClutchLever"
		pivot.position = lever_pivot(side)
		lean_node.add_child(pivot)
		var lm := MeshInstance3D.new()
		lm.mesh = parts[side].commit()
		pivot.add_child(lm)
		if side > 0:
			brake_lever = pivot
		else:
			clutch_lever = pivot

func set_levers(brake: float, clutch: float) -> void:
	if brake_lever:
		brake_lever.basis = lever_basis(1.0, brake)
	if clutch_lever:
		clutch_lever.basis = lever_basis(-1.0, clutch)

# --- working rear-view mirrors ---
var mirror_viewport: SubViewport
var mirror_camera: Camera3D
var _mirror_mats: Array[ShaderMaterial] = []
var _mirror_glass: Array[MeshInstance3D] = []
var _mirror_frame := 0
const MIRROR_CAM_LOCAL := Vector3(0.0, 1.22, -0.25)   # behind the screen, roughly at rider eye height

## Rebuilds the mirror glass with planar UVs and a material that shows the rear camera image.
## `live` = render a real rear view (costs one extra low-res render per frame).
func enable_mirrors(live: bool) -> void:
	var all: Array[MeshInstance3D] = []
	_collect(self, all)
	if live:
		mirror_viewport = SubViewport.new()
		mirror_viewport.size = Vector2i(512, 160)
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		mirror_viewport.msaa_3d = Viewport.MSAA_DISABLED
		mirror_viewport.positional_shadow_atlas_size = 0
		add_child(mirror_viewport)
		mirror_camera = Camera3D.new()
		mirror_camera.fov = 26.0
		mirror_camera.near = 0.3
		mirror_camera.far = 400.0
		mirror_camera.cull_mask = 0xFFFFF & ~BIKE_LAYER
		mirror_viewport.add_child(mirror_camera)
		mirror_camera.current = true
	for mi in all:
		if _mat_name(mi) != "Mirrors":
			continue
		var xf := _rel_xform(mi)
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for side: float in [-1.0, 1.0]:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var pts := []
			for t in idx.size() / 3:
				var tri := [xf * verts[idx[t * 3]], xf * verts[idx[t * 3 + 1]], xf * verts[idx[t * 3 + 2]]]
				if signf((tri[0].x + tri[1].x + tri[2].x)) == side:
					pts.append_array(tri)
			if pts.is_empty():
				continue
			var lo: Vector3 = pts[0]
			var hi: Vector3 = pts[0]
			for p: Vector3 in pts:
				lo = lo.min(p)
				hi = hi.max(p)
			for p: Vector3 in pts:
				# u: 0 at the inner edge .. 1 at the outer edge; v: 0 top .. 1 bottom.
				var u := (absf(p.x) - minf(absf(lo.x), absf(hi.x))) / maxf(absf(hi.x - lo.x), 0.001)
				var v := 1.0 - (p.y - lo.y) / maxf(hi.y - lo.y, 0.001)
				st.set_uv(Vector2(u, v))
				st.set_normal(Vector3.BACK)
				st.add_vertex(p)
			var glass := MeshInstance3D.new()
			glass.mesh = st.commit()
			glass.layers = BIKE_LAYER
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := ShaderMaterial.new()
			m.shader = preload("res://shaders/mirror.gdshader")
			m.set_shader_parameter("live", live)
			if live:
				m.set_shader_parameter("rear_view", mirror_viewport.get_texture())
			# The rear camera looks backwards, so world-left is on the image's right. The left mirror
			# shows the right half (outer edge = far right of the image), the right mirror the left half.
			if side < 0:
				m.set_shader_parameter("u_start", 0.5)
				m.set_shader_parameter("u_dir", 1.0)
			else:
				m.set_shader_parameter("u_start", 0.5)
				m.set_shader_parameter("u_dir", -1.0)
			glass.material_override = m
			lean_node.add_child(glass)
			glass.position = Vector3.ZERO
			# Nudge the glass a hair towards the rider so it sits on top of the original face.
			glass.position.z += 0.0015
			_mirror_mats.append(m)
			_mirror_glass.append(glass)
		mi.visible = false

## Keep the rear camera behind the rider, looking backwards (call every frame).
func update_mirrors() -> void:
	if mirror_camera == null:
		return
	var lt := lean_node.global_transform
	var o := lt * MIRROR_CAM_LOCAL
	mirror_camera.global_transform = Transform3D(Basis(), o).looking_at(o + lt.basis.z * 10.0 - lt.basis.y * 0.6, lt.basis.y)
	# Medium graphics: refresh the mirrors every other frame to halve their cost.
	if Game.quality == 1:
		_mirror_frame += 1
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if _mirror_frame % 2 == 0 else SubViewport.UPDATE_DISABLED

func set_brake_light(on: bool) -> void:
	for m in _taillight_mats:
		m.emission_enabled = true
		m.emission = Color(1, 0.05, 0.02)
		m.emission_energy_multiplier = 6.0 if on else 1.2

## The source model has a stray 25 cm textured square lying on the ground under the bike
## (inside the decal mesh). Rebuild that mesh without triangles that sit flat at ground level.
func _strip_ground_quad(mi: MeshInstance3D) -> void:
	var src := mi.mesh
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for t in idx.size() / 3:
			var a := verts[idx[t * 3]]
			var b := verts[idx[t * 3 + 1]]
			var c := verts[idx[t * 3 + 2]]
			if absf(a.y) < 0.004 and absf(b.y) < 0.004 and absf(c.y) < 0.004:
				continue
			keep.append(idx[t * 3])
			keep.append(idx[t * 3 + 1])
			keep.append(idx[t * 3 + 2])
		arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(si, src.surface_get_material(si))
	mi.mesh = out

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
			sm.set_shader_parameter("roughness", clampf(m.roughness * 0.5, 0.06, 0.16))
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
