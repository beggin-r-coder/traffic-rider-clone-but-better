extends RefCounted
class_name CarFactory
## Builds procedural traffic vehicle meshes by lofting cross-sections.
## Vehicle space: origin on the ground at the centre, -Z forward.
## Surface 0 is always the body paint so it can be recoloured per car.

const PAINT_COLORS := [
	Color(0.92, 0.92, 0.92), Color(0.93, 0.93, 0.95), Color(0.62, 0.64, 0.66), Color(0.75, 0.76, 0.78),
	Color(0.06, 0.06, 0.07), Color(0.12, 0.13, 0.15), Color(0.32, 0.34, 0.37), Color(0.55, 0.06, 0.06),
	Color(0.08, 0.17, 0.38), Color(0.15, 0.25, 0.45), Color(0.66, 0.66, 0.6), Color(0.25, 0.3, 0.22),
	Color(0.85, 0.45, 0.08), Color(0.9, 0.78, 0.2),
]

static var _cache := {}
static var mat_glass: StandardMaterial3D
static var mat_trim: StandardMaterial3D
static var mat_tyre: StandardMaterial3D
static var mat_rim: StandardMaterial3D
static var mat_head: StandardMaterial3D
static var mat_tail: StandardMaterial3D
static var mat_tail_brake: StandardMaterial3D
static var mat_cargo: StandardMaterial3D
static var mat_amber: StandardMaterial3D
static var mat_default_paint: StandardMaterial3D
static var paint_mats: Array[StandardMaterial3D] = []

static func _init_mats() -> void:
	if mat_glass != null:
		return
	mat_glass = StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.04, 0.05, 0.07)
	mat_glass.metallic = 0.3
	mat_glass.roughness = 0.04
	mat_glass.metallic_specular = 0.9
	mat_trim = StandardMaterial3D.new()
	mat_trim.albedo_color = Color(0.05, 0.05, 0.055)
	mat_trim.roughness = 0.7
	mat_tyre = StandardMaterial3D.new()
	mat_tyre.albedo_color = Color(0.035, 0.035, 0.035)
	mat_tyre.roughness = 0.9
	mat_rim = StandardMaterial3D.new()
	mat_rim.albedo_color = Color(0.6, 0.62, 0.64)
	mat_rim.metallic = 0.8
	mat_rim.roughness = 0.3
	mat_head = StandardMaterial3D.new()
	mat_head.albedo_color = Color(0.9, 0.92, 0.95)
	mat_head.emission_enabled = true
	mat_head.emission = Color(1, 0.97, 0.9)
	mat_head.emission_energy_multiplier = 1.5
	mat_tail = StandardMaterial3D.new()
	mat_tail.albedo_color = Color(0.5, 0.03, 0.03)
	mat_tail.emission_enabled = true
	mat_tail.emission = Color(1, 0.05, 0.03)
	mat_tail.emission_energy_multiplier = 1.0
	mat_tail_brake = mat_tail.duplicate()
	mat_tail_brake.emission_energy_multiplier = 7.0
	mat_amber = StandardMaterial3D.new()
	mat_amber.albedo_color = Color(0.9, 0.5, 0.05)
	mat_amber.emission_enabled = true
	mat_amber.emission = Color(1, 0.55, 0.05)
	mat_amber.emission_energy_multiplier = 0.4
	mat_cargo = StandardMaterial3D.new()
	mat_cargo.albedo_color = Color(0.9, 0.9, 0.88)
	mat_cargo.roughness = 0.6
	mat_default_paint = _paint(Color(0.8, 0.8, 0.8))
	for c in PAINT_COLORS:
		paint_mats.append(_paint(c))

static func _paint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.45
	m.roughness = 0.28
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.1
	return m

static func set_night(on: bool) -> void:
	_init_mats()
	mat_head.emission_energy_multiplier = 6.0 if on else 1.5
	mat_tail.emission_energy_multiplier = 2.5 if on else 1.0

## Vehicle specs: length, width, height, wheel radius, wheelbase, mesh.
static func get_vehicle(kind: String) -> Dictionary:
	_init_mats()
	if _cache.has(kind):
		return _cache[kind]
	var v: Dictionary
	match kind:
		"hatch":
			v = _car(4.1, 1.78, [
				# z, hw, y_bottom, y_top
				[-2.05, 0.76, 0.30, 0.64], [-1.9, 0.87, 0.22, 0.76], [-1.1, 0.89, 0.2, 0.86], [-0.65, 0.89, 0.2, 0.92],
				[1.6, 0.89, 0.22, 0.96], [2.0, 0.84, 0.28, 0.94], [2.05, 0.8, 0.34, 0.86]],
				[
				# z, hw_base, hw_roof, y_base, y_roof
				[-0.65, 0.84, 0.8, 0.91, 0.91], [0.15, 0.84, 0.70, 0.93, 1.48], [1.55, 0.84, 0.70, 0.95, 1.46], [1.95, 0.82, 0.68, 0.95, 1.05]],
				0.31, 2.55)
		"suv":
			v = _car(4.75, 1.92, [
				[-2.37, 0.82, 0.38, 0.78], [-2.2, 0.93, 0.32, 0.95], [-1.3, 0.95, 0.3, 1.05], [-0.8, 0.95, 0.3, 1.1],
				[1.9, 0.95, 0.32, 1.12], [2.3, 0.92, 0.36, 1.1], [2.37, 0.86, 0.45, 1.0]],
				[
				[-0.8, 0.9, 0.86, 1.09, 1.09], [-0.05, 0.9, 0.78, 1.11, 1.76], [2.0, 0.9, 0.78, 1.12, 1.74], [2.3, 0.89, 0.76, 1.12, 1.3]],
				0.37, 2.85)
		"van":
			v = _car(5.1, 1.98, [
				[-2.55, 0.85, 0.36, 0.78], [-2.4, 0.97, 0.3, 0.98], [-1.8, 0.99, 0.3, 1.08],
				[2.45, 0.99, 0.3, 1.1], [2.55, 0.95, 0.34, 1.05]],
				[
				[-1.8, 0.96, 0.92, 1.07, 1.07], [-1.0, 0.96, 0.9, 1.09, 2.0], [-0.6, 0.96, 0.9, 1.1, 2.08], [2.5, 0.96, 0.9, 1.1, 2.08], [2.55, 0.94, 0.88, 1.08, 2.0]],
				0.35, 3.1, true)
		"truck":
			v = _truck()
		_:
			v = _car(4.7, 1.84, [
				[-2.35, 0.78, 0.30, 0.62], [-2.2, 0.89, 0.22, 0.74], [-1.4, 0.92, 0.2, 0.82], [-0.75, 0.92, 0.2, 0.88],
				[1.3, 0.92, 0.2, 0.91], [2.15, 0.89, 0.22, 0.93], [2.35, 0.81, 0.3, 0.82]],
				[
				[-0.75, 0.87, 0.82, 0.87, 0.87], [0.05, 0.87, 0.70, 0.89, 1.43], [1.0, 0.87, 0.70, 0.9, 1.41], [1.75, 0.87, 0.82, 0.91, 0.92]],
				0.33, 2.8)
	_cache[kind] = v
	return v

## Generic lofted car. `body` and `cabin` are station lists (see get_vehicle).
static func _car(length: float, width: float, body: Array, cabin: Array, wheel_r: float, wheelbase: float, boxy: bool = false) -> Dictionary:
	var paint_st := _st(mat_default_paint)
	var glass_st := _st(mat_glass)
	var trim_st := _st(mat_trim)
	var parts := {"paint": paint_st, "glass": glass_st, "trim": trim_st}
	# --- body loft (rounded box cross-section) ---
	var rings := []
	for b in body:
		var hw: float = b[1]
		var y0: float = b[2]
		var y1: float = b[3]
		var r := minf(0.12, (y1 - y0) * 0.3)
		var ring := [
			Vector3(-hw * 0.94, y0, b[0]),
			Vector3(-hw, y0 + r, b[0]),
			Vector3(-hw, y1 - r * 1.4, b[0]),
			Vector3(-hw * 0.93, y1, b[0]),
			Vector3(hw * 0.93, y1, b[0]),
			Vector3(hw, y1 - r * 1.4, b[0]),
			Vector3(hw, y0 + r, b[0]),
			Vector3(hw * 0.94, y0, b[0]),
		]
		rings.append(ring)
	_loft(paint_st, rings, true)
	_cap(paint_st, rings[0], true)
	_cap(paint_st, rings[-1], false)
	# Lower trim strip (bumpers/sills) as a slightly wider dark band at the bottom.
	var sill := []
	for b in body:
		var hw2: float = b[1] + 0.008
		sill.append([Vector3(-hw2, b[2], b[0]), Vector3(-hw2, b[2] + 0.12, b[0])])
	_ribbon(trim_st, sill, false)
	var sill_r := []
	for b in body:
		var hw3: float = b[1] + 0.008
		sill_r.append([Vector3(hw3, b[2] + 0.12, b[0]), Vector3(hw3, b[2], b[0])])
	_ribbon(trim_st, sill_r, false)
	# --- cabin loft ---
	for i in cabin.size() - 1:
		var a: Array = cabin[i]
		var c: Array = cabin[i + 1]
		var a_pts := [Vector3(-a[1], a[3], a[0]), Vector3(-a[2], a[4], a[0]), Vector3(a[2], a[4], a[0]), Vector3(a[1], a[3], a[0])]
		var c_pts := [Vector3(-c[1], c[3], c[0]), Vector3(-c[2], c[4], c[0]), Vector3(c[2], c[4], c[0]), Vector3(c[1], c[3], c[0])]
		var roof_flat := absf(float(a[4]) - float(c[4])) < 0.12 and float(a[4]) - float(a[3]) > 0.3
		for j in 3:
			var target: SurfaceTool = glass_st
			if j == 1 and roof_flat:
				target = paint_st
			_quad(target, a_pts[j], a_pts[j + 1], c_pts[j + 1], c_pts[j])
		# Pillars: thin paint strips on the side windows at each station.
		if i > 0 and i < cabin.size() - 1:
			for side: float in [-1.0, 1.0]:
				var p0 := Vector3(side * (a[1] + 0.005), a[3], a[0])
				var p1 := Vector3(side * (a[2] + 0.005), a[4], a[0])
				var dz := Vector3(0, 0, 0.09)
				if side < 0:
					_quad(paint_st, p0 - dz, p1 - dz, p1 + dz, p0 + dz)
				else:
					_quad(paint_st, p0 + dz, p1 + dz, p1 - dz, p0 - dz)
	# Window belt line strip under the glass.
	# --- lights ---
	var front: Array = body[1]
	var rear: Array = body[-2]
	var fz: float = body[0][0]
	var rz: float = body[-1][0]
	var hl_y: float = lerpf(front[2], front[3], 0.72)
	var tl_y: float = lerpf(rear[2], rear[3], 0.75)
	var hl_w := 0.34
	var hx: float = front[1] - 0.2
	var tx: float = rear[1] - 0.18
	var head_st := _st(mat_head)
	var tail_st := _st(mat_tail)
	var amber_st := _st(mat_amber)
	for side: float in [-1.0, 1.0]:
		_box(head_st, Vector3(side * (hx - hl_w * 0.3), hl_y, fz + 0.06), Vector3(hl_w, 0.1, 0.12))
		_box(amber_st, Vector3(side * (hx + 0.12), hl_y - 0.02, fz + 0.1), Vector3(0.08, 0.06, 0.1))
		_box(tail_st, Vector3(side * tx, tl_y, rz - 0.05), Vector3(0.36 if not boxy else 0.14, 0.12 if not boxy else 0.4, 0.12))
	# grille + plates
	_box(trim_st, Vector3(0, lerpf(front[2], front[3], 0.42), fz + 0.03), Vector3(front[1] * 0.9, 0.16, 0.08))
	_box(trim_st, Vector3(0, rear[2] + 0.1, rz + 0.02), Vector3(rear[1] * 1.8, 0.16, 0.08))
	var plate_st := _st(mat_cargo)
	_box(plate_st, Vector3(0, lerpf(rear[2], rear[3], 0.45), rz - 0.0), Vector3(0.5, 0.12, 0.04))
	# --- wheels ---
	var wheel_st := _st(mat_tyre)
	var rim_st := _st(mat_rim)
	for z in [-wheelbase * 0.5, wheelbase * 0.5]:
		for side: float in [-1.0, 1.0]:
			_wheel(wheel_st, rim_st, Vector3(side * (width * 0.5 - 0.13), wheel_r, z), wheel_r, 0.22, side)
	# Dark wheel-well shadows (flat discs just inside the body sides).
	var mesh := ArrayMesh.new()
	paint_st.commit(mesh)   # surface 0 = paint
	for st in [glass_st, trim_st, head_st, tail_st, amber_st, plate_st, wheel_st, rim_st]:
		st.commit(mesh)
	var height: float = 0.0
	for c2 in cabin:
		height = maxf(height, c2[4])
	return {"mesh": mesh, "length": length, "width": width, "height": height, "tail_surface": 4}

static func _truck() -> Dictionary:
	var paint_st := _st(mat_default_paint)
	var glass_st := _st(mat_glass)
	var trim_st := _st(mat_trim)
	var cargo_st := _st(mat_cargo)
	var head_st := _st(mat_head)
	var tail_st := _st(mat_tail)
	var amber_st := _st(mat_amber)
	var wheel_st := _st(mat_tyre)
	var rim_st := _st(mat_rim)
	var plate_st := _st(mat_cargo)
	var L := 8.4
	var fz := -L * 0.5
	# Cab
	var rings := []
	for b in [[fz, 1.1, 0.55, 1.2], [fz + 0.15, 1.2, 0.5, 1.45], [fz + 0.5, 1.22, 0.5, 2.55], [fz + 2.3, 1.22, 0.5, 2.7], [fz + 2.35, 1.2, 0.55, 2.7]]:
		var hw: float = b[1]
		rings.append([Vector3(-hw, b[2], b[0]), Vector3(-hw, b[3] - 0.1, b[0]), Vector3(-hw * 0.95, b[3], b[0]), Vector3(hw * 0.95, b[3], b[0]), Vector3(hw, b[3] - 0.1, b[0]), Vector3(hw, b[2], b[0])])
	_loft(paint_st, rings, true)
	_cap(paint_st, rings[0], true)
	_cap(paint_st, rings[-1], false)
	# windscreen + side windows
	_quad(glass_st, Vector3(-1.12, 1.55, fz + 0.18), Vector3(-1.1, 2.4, fz + 0.45), Vector3(1.1, 2.4, fz + 0.45), Vector3(1.12, 1.55, fz + 0.18))
	for side: float in [-1.0, 1.0]:
		var x: float = side * 1.225
		if side < 0:
			_quad(glass_st, Vector3(x, 1.6, fz + 1.4), Vector3(x, 2.35, fz + 1.4), Vector3(x, 2.35, fz + 0.6), Vector3(x, 1.6, fz + 0.4))
		else:
			_quad(glass_st, Vector3(x, 1.6, fz + 0.4), Vector3(x, 2.35, fz + 0.6), Vector3(x, 2.35, fz + 1.4), Vector3(x, 1.6, fz + 1.4))
	# Cargo box
	_box(cargo_st, Vector3(0, 2.15, fz + 2.45 + 2.95), Vector3(2.5, 3.1, 5.9))
	_box(trim_st, Vector3(0, 0.75, fz + 2.45 + 2.95), Vector3(2.2, 0.35, 5.9))
	# lights
	for side: float in [-1.0, 1.0]:
		_box(head_st, Vector3(side * 0.85, 0.85, fz - 0.01), Vector3(0.35, 0.18, 0.06))
		_box(amber_st, Vector3(side * 1.12, 0.85, fz - 0.01), Vector3(0.1, 0.18, 0.06))
		_box(tail_st, Vector3(side * 1.0, 0.95, -fz + 0.01), Vector3(0.3, 0.16, 0.06))
		_box(amber_st, Vector3(side * 1.2, 3.65, -fz + 0.01), Vector3(0.06, 0.06, 0.04))
	_box(trim_st, Vector3(0, 0.75, fz - 0.03), Vector3(1.6, 0.4, 0.06))
	_box(trim_st, Vector3(0, 0.6, -fz), Vector3(2.4, 0.15, 0.1))
	_box(plate_st, Vector3(0, 0.95, -fz + 0.03), Vector3(0.5, 0.12, 0.03))
	for z in [fz + 1.2, fz + 5.6, fz + 6.8]:
		for side: float in [-1.0, 1.0]:
			_wheel(wheel_st, rim_st, Vector3(side * 1.0, 0.5, z), 0.5, 0.32, side)
	var mesh := ArrayMesh.new()
	paint_st.commit(mesh)
	for st in [glass_st, trim_st, head_st, tail_st, amber_st, cargo_st, plate_st, wheel_st, rim_st]:
		st.commit(mesh)
	return {"mesh": mesh, "length": L, "width": 2.5, "height": 3.7, "tail_surface": 4}

# ------------------------------------------------------------ geometry helpers

static func _st(mat: Material) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	st.set_smooth_group(-1)
	return st

## Quad with flat normal; vertices in clockwise order seen from the front.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	if n.length_squared() < 0.5:
		n = (d - a).cross(c - a).normalized()
	for p in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(p)

static func _loft(st: SurfaceTool, rings: Array, outward: bool) -> void:
	# Rings ordered front (-z) to back; points ordered left-bottom -> over the top -> right-bottom.
	for i in rings.size() - 1:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for j in r0.size() - 1:
			# Smooth-ish normals: average of face normal and outward direction from centre.
			var a: Vector3 = r0[j]
			var b: Vector3 = r0[j + 1]
			var c: Vector3 = r1[j + 1]
			var d: Vector3 = r1[j]
			_quad(st, a, b, c, d)
	# Underside
	for i in rings.size() - 1:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		_quad(st, r0[-1], r0[0], r1[0], r1[-1])

static func _cap(st: SurfaceTool, ring: Array, front: bool) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	for j in ring.size():
		var a: Vector3 = ring[j]
		var b: Vector3 = ring[(j + 1) % ring.size()]
		var tri := [c, a, b] if front else [c, b, a]
		var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
		for p in tri:
			st.set_normal(n)
			st.add_vertex(p)

static func _ribbon(st: SurfaceTool, pairs: Array, flip: bool) -> void:
	for i in pairs.size() - 1:
		var a: Vector3 = pairs[i][0]
		var b: Vector3 = pairs[i][1]
		var c: Vector3 = pairs[i + 1][1]
		var d: Vector3 = pairs[i + 1][0]
		if flip:
			_quad(st, a, d, c, b)
		else:
			_quad(st, a, b, c, d)

static func _box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return center + Vector3(x * h.x, y * h.y, z * h.z)
	# -Z (front)
	_quad(st, p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, -1, -1))
	# +Z (back)
	_quad(st, p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), p.call(-1, -1, 1))
	# -X
	_quad(st, p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), p.call(-1, -1, -1))
	# +X
	_quad(st, p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(1, -1, 1))
	# +Y
	_quad(st, p.call(-1, 1, -1), p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1))
	# -Y
	_quad(st, p.call(-1, -1, 1), p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1))

static func _wheel(tyre: SurfaceTool, rim: SurfaceTool, c: Vector3, r: float, w: float, side: float) -> void:
	var seg := 12
	var hw := w * 0.5
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(0, cos(a0) * r, sin(a0) * r)
		var p1 := Vector3(0, cos(a1) * r, sin(a1) * r)
		# tread
		_quad(tyre, c + p0 + Vector3(-hw, 0, 0), c + p0 + Vector3(hw, 0, 0), c + p1 + Vector3(hw, 0, 0), c + p1 + Vector3(-hw, 0, 0))
		# outer face: tyre sidewall ring + rim disc
		var o := Vector3(side * hw, 0, 0)
		var q0 := p0 * 0.62
		var q1 := p1 * 0.62
		if side > 0:
			_quad(tyre, c + o + p0, c + o + q0, c + o + q1, c + o + p1)
			_tri(rim, c + o + q0, c + o + Vector3(side * 0.02, 0, 0), c + o + q1)
		else:
			_quad(tyre, c + o + p1, c + o + q1, c + o + q0, c + o + p0)
			_tri(rim, c + o + q1, c + o + Vector3(side * 0.02, 0, 0), c + o + q0)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	for p in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(p)
