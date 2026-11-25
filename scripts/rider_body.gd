extends Node3D
class_name RiderBody
## Procedural rider (helmet, torso, legs) in a sport tuck, shown in chase view and crashes.
## Lives in the bike's leaning frame (-Z forward). Arms are handled by RiderArms.

var _mat_leather: StandardMaterial3D
var _mat_blue: StandardMaterial3D
var _mat_white: StandardMaterial3D
var _mat_boot: StandardMaterial3D
var _mat_helmet: StandardMaterial3D
var _mat_visor: StandardMaterial3D
var torso_root: Node3D
var _legs := {}

func _ready() -> void:
	_mat_leather = _m(Color(0.07, 0.07, 0.08), 0.4)
	_mat_blue = _m(Color(0.1, 0.22, 0.72), 0.4)
	_mat_white = _m(Color(0.9, 0.9, 0.92), 0.4)
	_mat_boot = _m(Color(0.05, 0.05, 0.05), 0.5)
	_mat_helmet = _m(Color(0.92, 0.93, 0.95), 0.15)
	_mat_helmet.clearcoat_enabled = true
	_mat_helmet.clearcoat = 1.0
	_mat_visor = _m(Color(0.02, 0.02, 0.03), 0.03)
	_mat_visor.metallic = 0.9
	torso_root = Node3D.new()
	add_child(torso_root)
	# Torso (hips -> chest), flattened front-to-back.
	_seg(torso_root, Vector3(0, 0.93, 0.36), Vector3(0, 1.15, 0.06), 0.17, 0.2, _mat_leather, Vector3(1.0, 1.0, 0.72))
	# Colour panels on the back / sides.
	_seg(torso_root, Vector3(0, 0.97, 0.33), Vector3(0, 1.12, 0.12), 0.172, 0.19, _mat_blue, Vector3(1.04, 1.0, 0.6))
	# Aero hump.
	_blob(torso_root, Vector3(0.1, 0.07, 0.14), Vector3(0, 1.21, 0.2), Vector3(-0.5, 0, 0), _mat_leather)
	# Neck + helmet.
	_seg(torso_root, Vector3(0, 1.17, 0.06), Vector3(0, 1.24, -0.02), 0.06, 0.055, _mat_leather, Vector3.ONE)
	_blob(torso_root, Vector3(0.135, 0.13, 0.155), Vector3(0, 1.3, -0.06), Vector3(-0.2, 0, 0), _mat_helmet)
	_blob(torso_root, Vector3(0.11, 0.06, 0.08), Vector3(0, 1.31, -0.165), Vector3(-0.15, 0, 0), _mat_visor)
	_blob(torso_root, Vector3(0.03, 0.02, 0.08), Vector3(0, 1.43, 0.0), Vector3(-0.2, 0, 0), _mat_blue)
	# Legs: thigh + shin + boot per side, posed in update_pose().
	for side in ["L", "R"]:
		_legs["thigh" + side] = _seg(self, Vector3.ZERO, Vector3.UP, 0.085, 0.065, _mat_leather, Vector3.ONE)
		_legs["knee" + side] = _blob(self, Vector3(0.06, 0.06, 0.06), Vector3.ZERO, Vector3.ZERO, _mat_white)
		_legs["shin" + side] = _seg(self, Vector3.ZERO, Vector3.UP, 0.06, 0.05, _mat_leather, Vector3.ONE)
		_legs["boot" + side] = _blob(self, Vector3(0.05, 0.06, 0.13), Vector3.ZERO, Vector3.ZERO, _mat_boot)
	update_pose(0.0, 1.0)

func _m(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _seg(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material, squash: Vector3) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = 1.0
	cm.radial_segments = 12
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	parent.add_child(mi)
	mi.set_meta("squash", squash)
	_place(mi, a, b)
	return mi

func _place(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var len := maxf(dir.length(), 0.001)
	var y := dir / len
	var x := y.cross(Vector3.BACK).normalized()
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	var sq: Vector3 = mi.get_meta("squash", Vector3.ONE)
	mi.transform = Transform3D(Basis(x * sq.x, y * len, z * sq.z), (a + b) * 0.5)

func _blob(parent: Node3D, radii: Vector3, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_euler(rot) * Basis.from_scale(radii), pos)
	parent.add_child(mi)
	return mi

## Hang off the inside of the bike in corners; inside knee sticks out.
func update_pose(lean: float, dt: float) -> void:
	var hang := clampf(lean / 0.9, -1.0, 1.0)
	torso_root.position = Vector3(hang * 0.1, -absf(hang) * 0.03, 0)
	torso_root.rotation = Vector3(0, 0, -hang * 0.12)
	for s: int in [-1, 1]:
		var key := "L" if s < 0 else "R"
		var inside := 1.0 if signf(hang) == float(s) else 0.0
		var hip := Vector3(s * 0.12 + hang * 0.1, 0.9, 0.34)
		var knee := Vector3(s * (0.25 + inside * absf(hang) * 0.18), 0.7 - inside * absf(hang) * 0.06, -0.02)
		var foot := Vector3(s * 0.2, 0.37, 0.43)
		_place(_legs["thigh" + key], hip, knee)
		_place(_legs["shin" + key], knee, foot)
		(_legs["knee" + key] as Node3D).position = knee + Vector3(s * 0.02, 0, -0.02)
		var boot: Node3D = _legs["boot" + key]
		boot.position = foot + Vector3(0, -0.02, 0.02)
