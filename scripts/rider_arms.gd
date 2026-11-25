extends Node3D
class_name RiderArms
## First-person rider arms and gloves gripping the clip-ons.
## Lives in the bike's leaning frame (-Z forward).

const GRIP_L := Vector3(-0.335, 0.955, -0.5)
const GRIP_R := Vector3(0.335, 0.955, -0.5)
const SHOULDER_L := Vector3(-0.23, 1.0, 0.32)
const SHOULDER_R := Vector3(0.23, 1.0, 0.32)

var _parts := {}
var _mat_jacket: StandardMaterial3D
var _mat_panel: StandardMaterial3D
var _mat_glove: StandardMaterial3D
var _mat_knuckle: StandardMaterial3D
var _steer_vis := 0.0
## Full-body pose (chase view): real shoulder positions instead of the low first-person ones.
var full_body := false

func _ready() -> void:
	_mat_jacket = StandardMaterial3D.new()
	_mat_jacket.albedo_color = Color(0.13, 0.13, 0.14)
	_mat_jacket.roughness = 0.42
	_mat_jacket.rim_enabled = true
	_mat_jacket.rim = 0.25
	_mat_panel = StandardMaterial3D.new()
	_mat_panel.albedo_color = Color(0.1, 0.22, 0.7)
	_mat_panel.roughness = 0.4
	_mat_glove = StandardMaterial3D.new()
	_mat_glove.albedo_color = Color(0.05, 0.05, 0.055)
	_mat_glove.roughness = 0.35
	_mat_knuckle = StandardMaterial3D.new()
	_mat_knuckle.albedo_color = Color(0.32, 0.33, 0.35)
	_mat_knuckle.metallic = 0.4
	_mat_knuckle.roughness = 0.3
	for side in ["L", "R"]:
		_parts["upper" + side] = _limb(0.058, 0.05, _mat_jacket)
		_parts["fore" + side] = _limb(0.047, 0.036, _mat_jacket)
		_parts["panel" + side] = _limb(0.0485, 0.042, _mat_panel)
		_parts["cuff" + side] = _limb(0.04, 0.038, _mat_glove)
		_parts["hand" + side] = _hand(side == "L")
	update_pose(0.0, 0.0, 1.0)

## Tapered limb segment: unit height along +Y, radius r0 at the start and r1 at the end.
func _limb(r0: float, r1: float, mat: Material) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = r0
	m.top_radius = r1
	m.height = 1.0
	m.radial_segments = 14
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _blob(parent: Node3D, radii: Vector3, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis.from_euler(rot) * Basis.from_scale(radii), pos)
	parent.add_child(mi)

func _hand(left: bool) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var sx := -1.0 if left else 1.0
	# Back of the hand draped over the grip, knuckles forward.
	_blob(root, Vector3(0.048, 0.026, 0.06), Vector3(0, 0.03, 0.012), Vector3(-0.45, 0, 0), _mat_glove)
	# Knuckle armour.
	_blob(root, Vector3(0.04, 0.012, 0.022), Vector3(0, 0.052, -0.022), Vector3(-0.5, 0, 0), _mat_knuckle)
	# Fingers wrapped around the front of the grip.
	_blob(root, Vector3(0.05, 0.024, 0.026), Vector3(0, 0.0, -0.035), Vector3(0, 0, 0), _mat_glove)
	# Thumb tucked on the inner side.
	_blob(root, Vector3(0.016, 0.016, 0.036), Vector3(-sx * 0.048, 0.012, -0.005), Vector3(0.4, 0, 0), _mat_glove)
	return root

func _place_limb(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var len := dir.length()
	var y := dir / len
	var x := y.cross(Vector3.BACK).normalized()
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * len, z), (a + b) * 0.5)

func update_pose(steer: float, lean: float, dt: float) -> void:
	_steer_vis = lerpf(_steer_vis, steer, 1.0 - exp(-10.0 * dt))
	for side: int in [-1, 1]:
		var key := "L" if side < 0 else "R"
		var grip: Vector3 = GRIP_L if side < 0 else GRIP_R
		# Counter-steer: the inside hand pushes the bar forward slightly.
		var push: float = _steer_vis * side * 0.02
		grip += Vector3(0, 0, -push)
		var shoulder: Vector3 = SHOULDER_L if side < 0 else SHOULDER_R
		var elbow := Vector3(side * 0.37, 0.84, -0.13)
		if full_body:
			var hang := clampf(lean / 0.9, -1.0, 1.0)
			shoulder = Vector3(side * 0.2 + hang * 0.1, 1.12 - absf(hang) * 0.03, 0.08)
			elbow = Vector3(side * 0.33 + hang * 0.06, 0.95, -0.2)
		else:
			shoulder += Vector3(lean * 0.12, -absf(lean) * 0.05, 0)
			# Elbows bent down and outwards.
			elbow += Vector3(lean * 0.08, 0, 0)
		var wrist := grip + Vector3(side * 0.01, 0.02, 0.075)
		_place_limb(_parts["upper" + key], shoulder, elbow)
		_place_limb(_parts["fore" + key], elbow, wrist)
		_place_limb(_parts["panel" + key], elbow.lerp(wrist, 0.05), elbow.lerp(wrist, 0.45))
		_place_limb(_parts["cuff" + key], wrist.lerp(elbow, 0.22), wrist)
		var hand: Node3D = _parts["hand" + key]
		hand.position = grip
		hand.rotation = Vector3(0.0, side * 0.12, 0.0)
