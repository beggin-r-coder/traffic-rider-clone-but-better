extends RefCounted
class_name Props
## Procedural low-poly prop meshes (trees, street lights, signs...).

## Builder that merges transformed primitive meshes into one multi-surface ArrayMesh,
## one surface per material.
class Builder:
	var parts := {}   # Material -> SurfaceTool

	func add(prim: Mesh, xf: Transform3D, mat: Material, jitter: float = 0.0, seed_value: int = 0) -> void:
		if not parts.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mat)
			parts[mat] = st
		var st: SurfaceTool = parts[mat]
		var arr := prim.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		var r := RandomNumberGenerator.new()
		r.seed = seed_value
		var jit := {}
		for i in idx:
			var p := v[i]
			if jitter > 0.0:
				var key := Vector3i(roundi(p.x * 100), roundi(p.y * 100), roundi(p.z * 100))
				if not jit.has(key):
					jit[key] = Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)) * jitter
				p += jit[key]
			st.set_normal((nb * n[i]).normalized())
			st.add_vertex(xf * p)

	func add_flat(prim: Mesh, xf: Transform3D, mat: Material, jitter: float = 0.0, seed_value: int = 0) -> void:
		# Same as add() but with faceted normals (nice for low-poly foliage/rocks).
		var tmp := Builder.new()
		tmp.add(prim, xf, mat, jitter, seed_value)
		var st: SurfaceTool = tmp.parts[mat]
		var m := st.commit()
		var arr := m.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if not parts.has(mat):
			var s2 := SurfaceTool.new()
			s2.begin(Mesh.PRIMITIVE_TRIANGLES)
			s2.set_material(mat)
			parts[mat] = s2
		var dst: SurfaceTool = parts[mat]
		var ii = arr[Mesh.ARRAY_INDEX]
		var order: Array = []
		if ii != null and ii.size() > 0:
			order = Array(ii)
		else:
			order = range(verts.size())
		for t in order.size() / 3:
			var a := verts[order[t * 3]]
			var b := verts[order[t * 3 + 1]]
			var c := verts[order[t * 3 + 2]]
			var nrm := (c - a).cross(b - a).normalized()
			for p in [a, b, c]:
				dst.set_normal(nrm)
				dst.add_vertex(p)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for mat in parts:
			parts[mat].commit(mesh)
		return mesh

static func _cyl(top: float, bottom: float, h: float, seg: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

static func _sphere(r: float, seg: int = 8, rings: int = 5) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s

static func pine(leaf: Material, trunk: Material) -> ArrayMesh:
	var b := Builder.new()
	b.add(_cyl(0.12, 0.2, 2.0, 6), Transform3D(Basis(), Vector3(0, 1.0, 0)), trunk)
	var y := 1.4
	var r := 2.0
	for i in 4:
		var h := 2.6 - i * 0.35
		b.add_flat(_cyl(0.05, r, h, 8), Transform3D(Basis(Vector3.UP, i * 0.6), Vector3(0, y + h * 0.5, 0)), leaf, 0.12, i)
		y += h * 0.55
		r *= 0.74
	return b.commit()

static func broadleaf(leaf: Material, trunk: Material) -> ArrayMesh:
	var b := Builder.new()
	b.add(_cyl(0.14, 0.24, 3.0, 6), Transform3D(Basis(), Vector3(0, 1.5, 0)), trunk)
	var blobs := [[Vector3(0, 4.2, 0), 2.1], [Vector3(1.0, 3.6, 0.4), 1.5], [Vector3(-0.9, 3.7, -0.3), 1.5], [Vector3(0.2, 5.3, 0.3), 1.3]]
	var i := 0
	for bl in blobs:
		b.add_flat(_sphere(bl[1], 7, 4), Transform3D(Basis().scaled(Vector3(1, 0.85, 1)), bl[0]), leaf, 0.22, i)
		i += 1
	return b.commit()

static func bush(leaf: Material) -> ArrayMesh:
	var b := Builder.new()
	b.add_flat(_sphere(0.8, 7, 4), Transform3D(Basis().scaled(Vector3(1.2, 0.7, 1.0)), Vector3(0, 0.35, 0)), leaf, 0.15, 3)
	b.add_flat(_sphere(0.55, 6, 4), Transform3D(Basis(), Vector3(0.6, 0.35, 0.2)), leaf, 0.12, 4)
	return b.commit()

static func rock(mat: Material) -> ArrayMesh:
	var b := Builder.new()
	b.add_flat(_sphere(0.9, 6, 4), Transform3D(Basis().scaled(Vector3(1.3, 0.6, 1.0)), Vector3(0, 0.2, 0)), mat, 0.25, 9)
	return b.commit()

static func box(size: Vector3, offset: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	var b := Builder.new()
	b.add(m, Transform3D(Basis(), offset), null)
	return b.commit()

## Street light: pole at origin, arm reaching towards -X (over the road for right-side poles).
static func street_light(pole: Material, lamp: Material) -> ArrayMesh:
	var b := Builder.new()
	b.add(_cyl(0.07, 0.11, 8.5, 8), Transform3D(Basis(), Vector3(0, 4.25, 0)), pole)
	b.add(_cyl(0.05, 0.06, 2.4, 6), Transform3D(Basis(Vector3.FORWARD, -PI * 0.5 + 0.12), Vector3(-1.15, 8.35, 0)), pole)
	var head := BoxMesh.new()
	head.size = Vector3(0.8, 0.14, 0.32)
	b.add(head, Transform3D(Basis(), Vector3(-2.25, 8.42, 0)), pole)
	var lens := BoxMesh.new()
	lens.size = Vector3(0.6, 0.04, 0.22)
	b.add(lens, Transform3D(Basis(), Vector3(-2.25, 8.33, 0)), lamp)
	return b.commit()

static func sign(face: Material, pole: Material) -> ArrayMesh:
	var b := Builder.new()
	for x in [-0.8, 0.8]:
		b.add(_cyl(0.05, 0.05, 2.8, 6), Transform3D(Basis(), Vector3(x, 1.4, -0.05)), pole)
	var board := BoxMesh.new()
	board.size = Vector3(2.2, 1.0, 0.06)
	b.add(board, Transform3D(Basis(), Vector3(0, 2.35, 0)), face)
	return b.commit()
