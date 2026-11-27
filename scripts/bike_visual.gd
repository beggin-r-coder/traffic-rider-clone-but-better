extends Node3D
class_name BikeVisual
## Loads the supplied motorcycle model, splits its wheels out so they can spin,
## and exposes lean / wheel spin / brake light controls.
##
## Local space: origin on the ground halfway between the tyre contact patches,
## -Z is forward, +Y is up.

const MODEL := preload("res://assets/bike/scene.gltf")

## Paint schemes selectable in the garage: [name, target hue (-1 = keep), saturation x, value x, swatch].
## Index 0 is the bike's factory livery.
const PAINTS := [
	["Factory", -1.0, 1.0, 1.0, Color(0, 0, 0, 0)],
	["Racing Blue", 0.66, 1.0, 1.0, Color(0.1, 0.2, 0.75)],
	["Rosso", 0.98, 1.1, 1.25, Color(0.85, 0.08, 0.08)],
	["Midnight", -1.0, 0.15, 0.35, Color(0.12, 0.12, 0.14)],
	["Acid Green", 0.29, 1.0, 1.5, Color(0.35, 0.85, 0.1)],
	["Sunburst", 0.08, 1.1, 1.8, Color(1.0, 0.55, 0.05)],
	["Pearl", -1.0, 0.05, 2.6, Color(0.9, 0.9, 0.92)],
]

## Factory swatch colour of a bike (for the garage paint chips).
static func factory_swatch(d: Dictionary) -> Color:
	match String(d.get("id", "r1")):
		"r1": return Color(0.1, 0.2, 0.75)
		"zx6r": return Color(0.2, 0.75, 0.1)
	return d.get("factory_color", Color(0.1, 0.1, 0.1))

var def: Dictionary = {}       # BikeDefs entry; defaults to the selected bike

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
	if def.is_empty():
		def = BikeDefs.current()
	lean_node = Node3D.new()
	lean_node.name = "Lean"
	add_child(lean_node)
	if def.has("model"):
		var holder := Node3D.new()
		holder.name = "Model"
		lean_node.add_child(holder)
		# Normalise: rotate + scale into bike space, then shift so the origin is on the ground
		# midway between the contact patches (offset measured on the mesh, see BikeDefs).
		holder.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(def["rot_y"])).scaled(Vector3.ONE * float(def["scale"])), -def["offset"])
		var m: Node3D = load(def["model"]).instantiate()
		holder.add_child(m)
		_setup_generic(holder)
	else:
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
const LEVER_MAX_ANGLE := deg_to_rad(18.0)
var brake_lever: Node3D
var clutch_lever: Node3D

## Axis the lever swings about (perpendicular to the bar, roughly "up"); for side +1 / -1.
static func lever_axis(d: Dictionary, side: float) -> Vector3:
	var gi: Vector3 = d["grip_in"] * Vector3(side, 1, 1)
	var go: Vector3 = d["grip_out"] * Vector3(side, 1, 1)
	var a := (go - gi).normalized()
	return (Vector3.UP - a * Vector3.UP.dot(a)).normalized()

## Rotation of a lever for pull 0..1 (moves the lever end back towards the grip).
static func lever_basis(d: Dictionary, side: float, pull: float) -> Basis:
	return Basis(lever_axis(d, side), -side * LEVER_MAX_ANGLE * clampf(pull, 0.0, 1.0))

static func lever_pivot(d: Dictionary, side: float) -> Vector3:
	var p: Vector3 = d["lever_pivot"]
	return Vector3(p.x * side, p.y, p.z)

func _split_levers(model: Node3D) -> void:
	var all: Array[MeshInstance3D] = []
	_collect(model, all)
	var box_min: Vector3 = def.get("lever_box_min", Vector3(0.236, 0.885, -0.53))
	var box_max: Vector3 = def.get("lever_box_max", Vector3(0.385, 0.97, -0.44))
	var whole_tri: bool = def.has("model")     # generic bikes: only triangles entirely inside the box
	var only: Array = def.get("lever_meshes", [])
	var parts := {1.0: SurfaceTool.new(), -1.0: SurfaceTool.new()}
	var counts := {1.0: 0, -1.0: 0}
	var lever_mat: Material = null
	for mi in all:
		if not def.has("model") and _mat_name(mi) != "Front_End_-_Aluminum":
			continue
		if not only.is_empty() and not String(mi.name) in only:
			continue
		if def.has("model"):
			var ab: AABB = _rel_xform(mi) * mi.mesh.get_aabb()
			var bb := AABB(box_min, box_max - box_min)
			var bm := AABB(Vector3(-box_max.x, box_min.y, box_min.z), box_max - box_min)
			if not (ab.intersects(bb) or ab.intersects(bm)):
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
				var inside := _in_box(cen, box_min, box_max)
				if inside and whole_tri:
					for v in tri:
						if not _in_box(xf * verts[v], box_min, box_max):
							inside = false
				if inside:
					var piv := lever_pivot(def, side)
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
		pivot.position = lever_pivot(def, side)
		lean_node.add_child(pivot)
		var lm := MeshInstance3D.new()
		lm.mesh = parts[side].commit()
		pivot.add_child(lm)
		if side > 0:
			brake_lever = pivot
		else:
			clutch_lever = pivot

static func _in_box(p: Vector3, lo: Vector3, hi: Vector3) -> bool:
	var q := Vector3(absf(p.x), p.y, p.z)
	return q.x > lo.x and q.x < hi.x and q.y > lo.y and q.y < hi.y and q.z > lo.z and q.z < hi.z

func set_levers(brake: float, clutch: float) -> void:
	if brake_lever:
		brake_lever.basis = lever_basis(def, 1.0, brake)
	if clutch_lever:
		clutch_lever.basis = lever_basis(def, -1.0, clutch)

# --- working rear-view mirrors ---
var mirror_viewport: SubViewport
var mirror_camera: Camera3D
var _mirror_mats: Array[ShaderMaterial] = []
var _mirror_glass: Array[MeshInstance3D] = []
var _mirror_frame := 0

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
	var generic: bool = def.has("model")
	for mi in all:
		if generic:
			if not String(mi.name) in def.get("mirror_meshes", []):
				continue
		elif _mat_name(mi) != "Mirrors":
			continue
		var xf := _rel_xform(mi)
		# Generic models: the glass is the set of rear-facing triangles out on the mirror heads; the
		# housing stays. (The R1 has a separate glass material.)
		var side_pts := {-1.0: [], 1.0: []}
		var rebuilt := ArrayMesh.new()
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var keep := PackedInt32Array()
			for t in idx.size() / 3:
				var tri := [xf * verts[idx[t * 3]], xf * verts[idx[t * 3 + 1]], xf * verts[idx[t * 3 + 2]]]
				var cx: float = (tri[0].x + tri[1].x + tri[2].x) / 3.0
				var is_glass := true
				if generic:
					var fn: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0])
					is_glass = fn.length() > 1e-9 and fn.normalized().z > 0.6 and absf(cx) > 0.22
				if is_glass:
					side_pts[signf(cx)].append_array(tri)
				else:
					keep.append_array([idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]])
			if generic:
				arrays[Mesh.ARRAY_INDEX] = keep
				if not keep.is_empty():
					rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
					rebuilt.surface_set_material(rebuilt.get_surface_count() - 1, mi.get_active_material(si))
			if not generic:
				break
		for side: float in [-1.0, 1.0]:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var pts: Array = side_pts[side]
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
		if generic:
			mi.mesh = rebuilt
			for si in rebuilt.get_surface_count():
				mi.set_surface_override_material(si, null)
		else:
			mi.visible = false

## Keep the rear camera behind the rider, looking backwards (call every frame).
func update_mirrors() -> void:
	if mirror_camera == null:
		return
	var lt := lean_node.global_transform
	var o := lt * (def["mirror_cam"] as Vector3)
	mirror_camera.global_transform = Transform3D(Basis(), o).looking_at(o + lt.basis.z * 10.0 - lt.basis.y * 0.6, lt.basis.y)
	# Medium graphics: refresh the mirrors every other frame to halve their cost.
	if Game.quality == 1:
		_mirror_frame += 1
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if _mirror_frame % 2 == 0 else SubViewport.UPDATE_DISABLED

# --- rain: wetter, glossier surfaces + droplet overlay pass on everything ---
var wet_material: ShaderMaterial

func set_wet(on: bool) -> void:
	if not on:
		return
	wet_material = ShaderMaterial.new()
	wet_material.shader = preload("res://shaders/wet_drops.gdshader")
	_build_body_sims()
	wet_material.render_priority = 1
	var all: Array[MeshInstance3D] = []
	_collect(self, all)
	var done := {}
	for mi in all:
		if mi.mesh == null or mi in _mirror_glass:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si)
			if m == null:
				continue
			if done.has(m):
				mi.set_surface_override_material(si, done[m])
				continue
			if m is BaseMaterial3D:
				var b := m as BaseMaterial3D
				if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
					continue
				var w: BaseMaterial3D = b.duplicate()
				w.roughness = clampf(b.roughness * 0.5, 0.05, 0.4)
				w.metallic_specular = maxf(b.metallic_specular, 0.7)
				w.clearcoat_enabled = true
				w.clearcoat = 1.0
				w.clearcoat_roughness = 0.02
				w.next_pass = wet_material
				done[m] = w
				mi.set_surface_override_material(si, w)
			elif m is ShaderMaterial and (m as ShaderMaterial).shader == preload("res://shaders/bike_paint.gdshader"):
				var sm: ShaderMaterial = (m as ShaderMaterial).duplicate()
				sm.set_shader_parameter("roughness", 0.03)
				sm.next_pass = wet_material
				done[m] = sm
				mi.set_surface_override_material(si, sm)
				var i := _paint_mats.find(m)
				if i >= 0:
					_paint_mats[i] = sm

# Simulated drops on the bodywork: one sim for the sides (bike z/y plane), one for the top
# surfaces (x/z plane). 1 px ~ 2.3 mm.
const SIDE_DOMAIN := Rect2(-1.2, 0.0, 2.4, 1.6)     # z range, y range (metres)
const TOP_DOMAIN := Rect2(-0.6, -1.2, 1.2, 2.4)     # x range, z range
var side_sim: DropSim
var top_sim: DropSim
var _body_frame := 0

func _build_body_sims() -> void:
	if Game.quality <= 0:
		return
	var a: Array = DropSim.create(Vector2i(1024, 680))
	add_child(a[0])
	side_sim = a[1]
	var b: Array = DropSim.create(Vector2i(512, 1024))
	add_child(b[0])
	top_sim = b[1]
	for sim: DropSim in [side_sim, top_sim]:
		sim.r_min = 0.9
		sim.r_max = 3.2
		sim.run_radius = 4.2
		sim.trail_spacing = 5.0
	side_sim.max_drops = 1000 if Game.quality >= 2 else 600
	side_sim.spawn_rate = 360.0
	top_sim.max_drops = 600 if Game.quality >= 2 else 380
	top_sim.spawn_rate = 240.0
	wet_material.set_shader_parameter("side_map", a[0].get_texture())
	wet_material.set_shader_parameter("top_map", b[0].get_texture())
	wet_material.set_shader_parameter("side_domain", Vector4(SIDE_DOMAIN.position.x, SIDE_DOMAIN.position.y, SIDE_DOMAIN.size.x, SIDE_DOMAIN.size.y))
	wet_material.set_shader_parameter("top_domain", Vector4(TOP_DOMAIN.position.x, TOP_DOMAIN.position.y, TOP_DOMAIN.size.x, TOP_DOMAIN.size.y))
	wet_material.set_shader_parameter("use_sim", true)
	# Pre-warm: the bike has been out in the rain for a while already.
	side_sim.flow = Vector2(0, 90)
	top_sim.flow = Vector2.ZERO
	top_sim.run_radius = 99.0
	for k in 150:
		side_sim.step(1.0 / 30.0)
		top_sim.step(1.0 / 30.0)

func set_wet_speed(v01: float) -> void:
	if wet_material == null:
		return
	wet_material.set_shader_parameter("speed", v01)
	wet_material.set_shader_parameter("world_to_bike", lean_node.global_transform.affine_inverse())
	if side_sim:
		# The two bodywork sims update on alternate frames (each with a double time step).
		_body_frame += 1
		var dt := get_process_delta_time() * 2.0
		# Map y is down (= world down). Airflow pushes drops backwards (+z = +x in the side map).
		side_sim.flow = Vector2(lerpf(0.0, 2600.0, v01 * v01), 90.0)
		side_sim.run_radius = lerpf(4.2, 1.6, v01)
		side_sim.max_speed = lerpf(120.0, 2400.0, v01)
		if _body_frame % 2 == 0:
			side_sim.step(dt)
		# Top surfaces: no gravity run, wind sweeps drops backwards (+z = +y in the top map).
		top_sim.flow = Vector2(0.0, lerpf(0.0, 2600.0, v01 * v01))
		top_sim.run_radius = lerpf(99.0, 1.4, clampf(v01 * 3.0, 0.0, 1.0))
		top_sim.max_speed = lerpf(10.0, 2400.0, v01)
		if _body_frame % 2 == 1:
			top_sim.step(dt)

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
	var base_hue: float = def.get("paint_hue", 0.66)
	var solid := String(def.get("paint_mode", "hue")) == "solid"
	for sm in _paint_mats:
		if solid:
			sm.set_shader_parameter("solid_color", def.get("factory_color", Color(0.1, 0.1, 0.1)) if i == 0 else p[4])
			continue
		sm.set_shader_parameter("hue_shift", 0.0 if p[1] < 0.0 else p[1] - base_hue)
		sm.set_shader_parameter("sat_mul", p[2])
		sm.set_shader_parameter("val_mul", p[3])

# ------------------------------------------------------------------ generic (BikeDefs) models

func _setup_generic(holder: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect(holder, meshes)
	var by_name := {}
	for mi in meshes:
		by_name[String(mi.name)] = mi
		if String(mi.name) in def.get("hide", []):
			mi.visible = false
	# --- wheels: hub = centre of the tyre's bounding box (bike space) ---
	var fl: Array = def["front_wheel"]
	var rl: Array = def["rear_wheel"]
	var ft: MeshInstance3D = by_name[fl[0]]
	var rt: MeshInstance3D = by_name[rl[0]]
	var fab: AABB = _rel_xform(ft) * ft.mesh.get_aabb()
	var rab: AABB = _rel_xform(rt) * rt.mesh.get_aabb()
	front_hub = fab.get_center()
	rear_hub = rab.get_center()
	wheel_radius = (fab.size.y + rab.size.y) * 0.25
	wheelbase = absf(front_hub.z - rear_hub.z)
	front_wheel = Node3D.new()
	front_wheel.name = "FrontWheel"
	front_wheel.position = front_hub
	lean_node.add_child(front_wheel)
	rear_wheel = Node3D.new()
	rear_wheel.name = "RearWheel"
	rear_wheel.position = rear_hub
	lean_node.add_child(rear_wheel)
	for n in fl:
		if by_name.has(n):
			_move_to_wheel(by_name[n], front_wheel)
	for n in rl:
		if by_name.has(n):
			_move_to_wheel(by_name[n], rear_wheel)
	_split_levers(holder)
	_generic_materials()
	_generic_dash(by_name)

func _generic_materials() -> void:
	var all: Array[MeshInstance3D] = []
	_collect(lean_node, all)
	var tex_dir: String = def.get("textures", "")
	var built := {}        # source material -> replacement
	var finishes: Dictionary = def.get("finishes", {})
	var paint_mats: Array = def.get("paint_mats", [])
	var glass_mats: Array = def.get("glass_mats", [])
	var glass_meshes: Array = def.get("glass_meshes", [])
	var tail_meshes: Array = def.get("taillight_meshes", [])
	var head_meshes: Array = def.get("headlight_meshes", [])
	for mi in all:
		if mi.mesh == null:
			continue
		mi.layers = BIKE_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mname := String(mi.name)
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si)
			var rn: String = src.resource_name if src else ""
			var m: Material = built.get(src)
			if m == null:
				if rn in paint_mats:
					m = _generic_paint(src as BaseMaterial3D, tex_dir, rn)
				elif rn in glass_mats:
					m = _glass_material()
				elif tex_dir != "" and ResourceLoader.exists(tex_dir + rn + "_albedo.png"):
					m = _tex_material(tex_dir, rn)
				elif src is BaseMaterial3D:
					var d: BaseMaterial3D = (src as BaseMaterial3D).duplicate()
					var f: Array = finishes.get(rn, [0.2, 0.5, 0.0])
					d.metallic = f[0]
					d.roughness = f[1]
					d.metallic_specular = 0.6
					if f[2] > 0.0:
						d.clearcoat_enabled = true
						d.clearcoat = f[2]
						d.clearcoat_roughness = 0.05
					if f.size() > 3:
						d.albedo_color = f[3]
					m = d
				built[src] = m
			# Per-mesh variants of a shared (atlas) material.
			if mname in glass_meshes:
				var g: BaseMaterial3D = (m as BaseMaterial3D).duplicate() if m is BaseMaterial3D else _glass_material()
				g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				g.cull_mode = BaseMaterial3D.CULL_DISABLED
				g.roughness = 0.04
				# Clear covers: the atlas has no alpha, so the tint sets the transparency.
				g.albedo_color = Color(0.5, 0.55, 0.6, 0.35) if mname == "Windshield" else Color(1, 1, 1, 0.25)
				m = g
			elif mname in tail_meshes or mname in head_meshes:
				var e: BaseMaterial3D = (m as BaseMaterial3D).duplicate()
				e.emission_enabled = true
				e.emission_texture = e.albedo_texture
				if mname in tail_meshes:
					e.emission = Color(1, 0.08, 0.04)
					_taillight_mats.append(e)
				else:
					e.emission = Color(1.0, 0.97, 0.9)
					e.emission_energy_multiplier = 2.5
				m = e
			elif m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and not rn in glass_mats and rn != "Decal":
				# Atlas alpha only matters on the glass meshes; everything else is opaque.
				var o: BaseMaterial3D = built.get([src, "opaque"])
				if o == null:
					o = (m as BaseMaterial3D).duplicate()
					o.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					built[[src, "opaque"]] = o
				m = o
			mi.set_surface_override_material(si, m)

func _glass_material() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.08, 0.1, 0.13, 0.25)
	g.roughness = 0.04
	g.metallic_specular = 0.8
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	return g

func _tex_material(dir: String, rn: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = rn
	m.albedo_texture = load(dir + rn + "_albedo.png")
	if ResourceLoader.exists(dir + rn + "_orm.png"):
		var orm: Texture2D = load(dir + rn + "_orm.png")
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = orm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
		m.roughness = 1.0
	if ResourceLoader.exists(dir + rn + "_normal.png"):
		m.normal_enabled = true
		m.normal_texture = load(dir + rn + "_normal.png")
	m.metallic_specular = 0.6
	if rn == "Decal":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.04
	return m

func _generic_paint(src: BaseMaterial3D, tex_dir: String, rn: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/bike_paint.gdshader")
	if String(def.get("paint_mode", "hue")) == "solid":
		sm.set_shader_parameter("solid", true)
		sm.set_shader_parameter("solid_color", def.get("factory_color", Color(0.1, 0.1, 0.1)))
		sm.set_shader_parameter("roughness", 0.1)
		sm.set_shader_parameter("metallic", 0.55)
	else:
		sm.set_shader_parameter("albedo_tex", load(tex_dir + rn + "_albedo.png"))
		sm.set_shader_parameter("mask_hue", def.get("paint_hue", 0.66))
		sm.set_shader_parameter("roughness", 0.12)
		if ResourceLoader.exists(tex_dir + rn + "_normal.png"):
			sm.set_shader_parameter("use_normal", true)
			sm.set_shader_parameter("normal_tex", load(tex_dir + rn + "_normal.png"))
		if ResourceLoader.exists(tex_dir + rn + "_orm.png"):
			sm.set_shader_parameter("use_orm", true)
			sm.set_shader_parameter("orm_tex", load(tex_dir + rn + "_orm.png"))
	_paint_mats.append(sm)
	return sm

## Live dash: a quad on the instrument face showing the DashDisplay screen.
func _generic_dash(by_name: Dictionary) -> void:
	var dd: Dictionary = def.get("dash", {})
	if dd.is_empty():
		return
	var center: Vector3
	var nrm: Vector3
	var w: float
	if dd.has("decal_mesh") and by_name.has(dd["decal_mesh"]):
		# Fit a plane to the printed dash decal.
		var mi: MeshInstance3D = by_name[dd["decal_mesh"]]
		var xf := _rel_xform(mi)
		var pts := PackedVector3Array()
		for si in mi.mesh.get_surface_count():
			for v in (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(xf * v)
		center = Vector3.ZERO
		for p in pts:
			center += p
		center /= pts.size()
		var lo := pts[0]
		var hi := pts[0]
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		# Normal: the plane through the extents (x width, y-z slope), facing up/back to the rider.
		var dz := hi.z - lo.z
		var dy := hi.y - lo.y
		nrm = Vector3(0, dz, dy).normalized()
		w = (hi.x - lo.x) * 0.95
	else:
		center = dd["center"]
		var t := deg_to_rad(float(dd["tilt"]))
		nrm = Vector3(0, sin(t), cos(t))
		w = (dd["size"] as Vector2).x
	dash = DashDisplay.new()
	dash.name = "Dash"
	dash.redline = float(def["redline"])
	add_child(dash)
	dash.setup(null)
	var h := w / (DashDisplay.SCREEN_SIZE.x / DashDisplay.SCREEN_SIZE.y)
	var right := Vector3.RIGHT
	var up := nrm.cross(right).normalized() * -1.0
	if up.y < 0.0:
		up = -up
	var tex_size := Vector2(1024, 512)
	var c := DashDisplay.SCREEN_CENTER
	var hs := DashDisplay.SCREEN_SIZE * 0.5
	var u0 := (c.x - hs.x) / tex_size.x
	var u1 := (c.x + hs.x) / tex_size.x
	# The overlay is drawn flipped vertically about the screen centre.
	var v_top := (c.y + hs.y) / tex_size.y
	var v_bot := (c.y - hs.y) / tex_size.y
	var o := center + nrm * 0.003
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [
		[o - right * w * 0.5 + up * h * 0.5, Vector2(u0, v_top)],
		[o + right * w * 0.5 + up * h * 0.5, Vector2(u1, v_top)],
		[o + right * w * 0.5 - up * h * 0.5, Vector2(u1, v_bot)],
		[o - right * w * 0.5 - up * h * 0.5, Vector2(u0, v_bot)],
	]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(nrm)
		st.set_uv(corners[k][1])
		st.add_vertex(corners[k][0])
	var q := MeshInstance3D.new()
	q.name = "DashScreen"
	q.mesh = st.commit()
	q.layers = BIKE_LAYER
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dm := StandardMaterial3D.new()
	var vt := dash.get_texture()
	dm.albedo_texture = vt
	dm.emission_enabled = true
	dm.emission_texture = vt
	dm.emission_energy_multiplier = 0.9
	dm.roughness = 0.15
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material_override = dm
	lean_node.add_child(q)
