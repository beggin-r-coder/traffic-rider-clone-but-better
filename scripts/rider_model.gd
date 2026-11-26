extends Node3D
class_name RiderModel
## The rider (Ready Player Me avatar) posed procedurally on the R1 every frame:
## seated tuck, head up, two-bone IK arms with hands locked onto the clip-on grips and every
## finger wrapped around the bar, IK legs on the footpegs, hang-off in corners.
## Throttle rolls the right wrist back around the grip; braking extends the right index +
## middle fingers onto the brake lever and pulls it; gear shifts blip the left fingers on the clutch.
##
## Lives in the bike's leaning frame (bike space: -Z forward, +X right, origin on the ground).
## All solving happens in skeleton space (avatar faces +Z, left = +X); bike points are mapped
## with (x, y, z) -> (-x, y, -z).

const MODEL := preload("res://assets/rider/rider.glb")

# --- bike contact points, measured on the R1 mesh (bike space) ---
const GRIP_IN := Vector3(0.228, 0.959, -0.430)     # right grip rubber, inner end (by the switchgear)
const GRIP_OUT := Vector3(0.348, 0.921, -0.363)    # right grip rubber, outer end (before the bar-end weight)
const LEVER_IN := Vector3(0.255, 0.948, -0.490)    # brake lever, pivot side
const LEVER_OUT := Vector3(0.368, 0.904, -0.471)   # brake lever, tip
const PEG := Vector3(0.245, 0.455, 0.340)          # right footpeg (ball of the foot)
const SEAT := Vector3(0.0, 0.925, 0.27)           # seat surface under the pelvis
const GRIP_RADIUS := 0.02                          # grip rubber + glove

var skel: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var head_meshes: Array[MeshInstance3D] = []
var _rest_local: Array[Transform3D] = []
var _g: Array[Transform3D] = []         # working global (skeleton-space) transforms
var _children := {}                     # bone -> [descendant bones incl. itself]
var _b := {}                            # name -> index

# inputs (smoothed)
var throttle := 0.0
var brake := 0.0
var lean := 0.0
var steer := 0.0
var speed := 0.0
var clutch := 0.0
var _thr_s := 0.0
var _brk_cover := 0.0
var _brk_pull := 0.0
var _hang := 0.0
var _tuck := 0.0
var frozen := false
var lever_pull := 0.0      # current brake lever pull (for the bike's lever mesh)
var clutch_pull := 0.0

func _ready() -> void:
	var avatar: Node3D = MODEL.instantiate()
	avatar.rotation.y = PI               # avatar faces +Z; the bike faces -Z
	add_child(avatar)
	skel = avatar.find_children("*", "Skeleton3D", true, false)[0]
	for m in avatar.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		meshes.append(mi)
		mi.layers = BikeVisual.BIKE_LAYER
		if mi.name in ["Wolf3D_Head", "Wolf3D_Teeth", "EyeLeft", "EyeRight", "Wolf3D_Headwear"]:
			head_meshes.append(mi)
	var n := skel.get_bone_count()
	_rest_local.resize(n)
	_g.resize(n)
	for i in n:
		_rest_local[i] = skel.get_bone_rest(i)
		_b[skel.get_bone_name(i)] = i
		_children[i] = [i]
	for i in n:
		var p := skel.get_bone_parent(i)
		while p >= 0:
			_children[p].append(i)
			p = skel.get_bone_parent(p)
	update_pose(1.0)

var _fp_mats := {}          # MeshInstance3D -> [original, fp copy] per surface

## First person: hide the helmet/head, and dither away any part of the body within ~45 cm of the
## camera (back, collar, shoulders) so only the arms and gloved hands remain in view.
func set_first_person(fp: bool) -> void:
	for m in head_meshes:
		m.visible = not fp
	for mi in meshes:
		if mi in head_meshes or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			if fp:
				var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
				if src == null:
					continue
				var key := [mi, si]
				if not _fp_mats.has(key):
					var c: BaseMaterial3D = src.duplicate()
					c.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
					# Single-sided, so faded-away sleeves don't reveal the hollow inside of the arm.
					c.cull_mode = BaseMaterial3D.CULL_BACK
					c.distance_fade_min_distance = 0.6
					c.distance_fade_max_distance = 0.68
					_fp_mats[key] = c
				mi.set_surface_override_material(si, _fp_mats[key])
			else:
				mi.set_surface_override_material(si, null)

## Midpoint between the shoulder joints (bike-leaning-frame space).
func shoulder_mid() -> Vector3:
	var m := (_g[_b["LeftArm"]].origin + _g[_b["RightArm"]].origin) * 0.5
	return Vector3(-m.x, m.y, -m.z)

## First-person camera mount: just above and behind the shoulders, fixed relative to the torso so
## the near-camera fade always cuts the body in the same place (only forearms + gloves stay visible).
func fp_camera_position() -> Vector3:
	return shoulder_mid() + Vector3(0, 0.15, 0.44)

## Eye position (bike-leaning-frame space).
func eye_position() -> Vector3:
	var e := (_g[_b["LeftEye"]].origin + _g[_b["RightEye"]].origin) * 0.5
	return Vector3(-e.x, e.y, -e.z)

## First-person camera mount: a chin cam just below and in front of the eyes (classic onboard view).
func chin_cam_position() -> Vector3:
	var head := _g[_b["Head"]]
	var e := (_g[_b["LeftEye"]].origin + _g[_b["RightEye"]].origin) * 0.5
	var p := e + head.basis.y.normalized() * -0.07 + head.basis.z.normalized() * 0.06
	return Vector3(-p.x, p.y, -p.z)

# ------------------------------------------------------------------ helpers

static func _sk(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, -v.z)

func _bi(n: String) -> int:
	return _b[n]

func _fk_all() -> void:
	for i in _g.size():
		var p := skel.get_bone_parent(i)
		_g[i] = _rest_local[i] if p < 0 else _g[p] * _rest_local[i]

## Rotate a bone and everything below it about a pivot (global rotation).
func _rot(bone: int, axis: Vector3, angle: float, pivot: Vector3) -> void:
	if absf(angle) < 1e-6 or axis.length_squared() < 1e-10:
		return
	var r := Basis(axis.normalized(), angle)
	for j in _children[bone]:
		var t: Transform3D = _g[j]
		_g[j] = Transform3D(r * t.basis, pivot + r * (t.origin - pivot))

## Rotate a bone subtree with an arbitrary basis about a pivot.
func _rot_basis(bone: int, r: Basis, pivot: Vector3) -> void:
	for j in _children[bone]:
		var t: Transform3D = _g[j]
		_g[j] = Transform3D(r * t.basis, pivot + r * (t.origin - pivot))

func _move(bone: int, delta: Vector3) -> void:
	for j in _children[bone]:
		_g[j].origin += delta

## Shortest-arc rotation of a bone subtree so the direction from `bone` to `tip_bone` points at `target`.
func _aim(bone: int, tip_bone: int, target: Vector3) -> void:
	var o := _g[bone].origin
	var a := (_g[tip_bone].origin - o).normalized()
	var b := (target - o).normalized()
	var axis := a.cross(b)
	if axis.length() < 1e-6:
		return
	_rot(bone, axis, a.angle_to(b), o)

## Two-bone IK: root -> mid -> end reaches `target`, bending towards `pole`.
func _two_bone(root: int, mid: int, end: int, target: Vector3, pole: Vector3) -> void:
	var s := _g[root].origin
	var l1 := (_g[mid].origin - s).length()
	var l2 := (_g[end].origin - _g[mid].origin).length()
	var to_t := target - s
	var d := clampf(to_t.length(), 0.05, l1 + l2 - 0.002)
	var dir := to_t.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pp := (pole - dir * pole.dot(dir))
	pp = pp.normalized() if pp.length() > 1e-5 else Vector3.UP
	var elbow := s + dir * a + pp * h
	_aim(root, mid, elbow)
	_aim(mid, end, s + dir * d)

## Orient a bone subtree so (forward_from, side_from) -> (forward_to, side_to).
func _orient(bone: int, f_from: Vector3, s_from: Vector3, f_to: Vector3, s_to: Vector3) -> void:
	var b_from := _frame(f_from, s_from)
	var b_to := _frame(f_to, s_to)
	_rot_basis(bone, b_to * b_from.inverse(), _g[bone].origin)

static func _frame(f: Vector3, s: Vector3) -> Basis:
	var x := f.normalized()
	var z := x.cross(s).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)

# ------------------------------------------------------------------ posing

func update_pose(dt: float) -> void:
	if frozen or skel == null:
		return
	var k := 1.0 - exp(-14.0 * dt)
	_thr_s = lerpf(_thr_s, throttle, k)
	_brk_cover = move_toward(_brk_cover, 1.0 if brake > 0.04 else 0.0, dt * 9.0)
	_brk_pull = lerpf(_brk_pull, brake, k)
	_hang = lerpf(_hang, clampf(lean / 0.85, -1.0, 1.0), 1.0 - exp(-6.0 * dt))
	_tuck = lerpf(_tuck, clampf((speed - 25.0) / 45.0, 0.0, 1.0), 1.0 - exp(-2.0 * dt))
	_fk_all()
	var up := Vector3.UP
	var fwd := Vector3(0, 0, 1)          # skeleton space forward
	var right_x := -1.0                  # avatar's right side is -X
	var hips := _bi("Hips")

	# --- pelvis on the seat, tilted forward; hang off the inside in corners ---
	var hip_target := _sk(SEAT) + up * 0.105 + Vector3(-_hang * 0.11, -absf(_hang) * 0.015, 0)
	_move(hips, hip_target - _g[hips].origin)
	_rot(hips, Vector3.RIGHT, deg_to_rad(42.0 + 8.0 * _tuck), _g[hips].origin)
	_rot(hips, fwd, deg_to_rad(_hang * 10.0), _g[hips].origin)

	# --- spine curve: more tuck at speed ---
	for pair in [["Spine", 5.0, 3.0], ["Spine1", 7.0, 3.0], ["Spine2", 6.0, 3.0]]:
		var bi := _bi(pair[0])
		_rot(bi, Vector3.RIGHT, deg_to_rad(pair[1] + pair[2] * _tuck), _g[bi].origin)
	# Lean the upper body a little into the turn.
	_rot(_bi("Spine1"), fwd, deg_to_rad(_hang * 9.0), _g[_bi("Spine1")].origin)

	# --- head up, eyes level, looking a touch into the turn ---
	var torso_pitch := 42.0 + 8.0 * _tuck + 18.0 + 9.0 * _tuck
	_rot(_bi("Neck"), Vector3.RIGHT, deg_to_rad(-torso_pitch * 0.5), _g[_bi("Neck")].origin)
	_rot(_bi("Head"), Vector3.RIGHT, deg_to_rad(-torso_pitch * 0.38), _g[_bi("Head")].origin)
	_rot(_bi("Head"), up, deg_to_rad(-steer * 8.0 - _hang * 6.0), _g[_bi("Head")].origin)
	_rot(_bi("Head"), fwd, deg_to_rad(-_hang * 12.0), _g[_bi("Head")].origin)

	# --- arms + hands ---
	for side: float in [1.0, -1.0]:
		_pose_arm(side)

	# --- legs on the pegs ---
	for side: float in [1.0, -1.0]:
		_pose_leg(side)

	_apply()

func _pose_arm(side: float) -> void:
	var pre := "Right" if side > 0 else "Left"
	var shoulder := _bi(pre + "Shoulder")
	var arm := _bi(pre + "Arm")
	var fore := _bi(pre + "ForeArm")
	var hand := _bi(pre + "Hand")
	var gi := _sk(Vector3(GRIP_IN.x * side, GRIP_IN.y, GRIP_IN.z))
	var go := _sk(Vector3(GRIP_OUT.x * side, GRIP_OUT.y, GRIP_OUT.z))
	var axis := (go - gi).normalized()            # along the grip, pointing outwards
	var center := gi.lerp(go, 0.48)
	var up := Vector3.UP
	var fwd := Vector3(0, 0, 1)
	# Grip-local frame: "top" of the bar (perpendicular to the axis) and forward.
	var top := (up - axis * up.dot(axis)).normalized()
	var front := top.cross(axis) * (1.0 if axis.x < 0.0 else -1.0)
	if front.dot(fwd) < 0.0:
		front = -front
	# Throttle (right hand only) rolls the whole hand back around the grip axis.
	var roll := 0.0
	if side > 0:
		roll = _thr_s * deg_to_rad(30.0)
	var spin := Basis(axis, roll * (1.0 if axis.dot(Vector3(-1, 0, 0)) > 0.0 else -1.0))
	var top_r := spin * top
	var front_r := spin * front
	# Hand pose: knuckles on the top-front of the grip, back of the hand sloping up to the wrist.
	var finger_dir := (front_r * cos(deg_to_rad(32.0)) - top_r * sin(deg_to_rad(32.0))).normalized()
	var knuckle_line := axis                       # index (inside) -> pinky (outside)
	var kr := GRIP_RADIUS + 0.016
	var knuckles := center + front_r * (kr * cos(deg_to_rad(72.0))) + top_r * (kr * sin(deg_to_rad(72.0)))
	var hand_len := (_g[_bi(pre + "HandMiddle1")].origin - _g[hand].origin).length()
	var wrist_target := knuckles - finger_dir * hand_len

	# Clavicle reaches a little forward/down toward the bars.
	var sh_o := _g[shoulder].origin
	var to_grip := (center - sh_o).normalized()
	var arm_dir := (_g[arm].origin - sh_o).normalized()
	var ax := arm_dir.cross(to_grip)
	if ax.length() > 1e-5:
		_rot(shoulder, ax, arm_dir.angle_to(to_grip) * 0.22, sh_o)
	# Elbows bent outwards and down.
	var out := Vector3(-side, 0, 0)               # rider's right side = -X in skeleton space
	var pole := (out * 0.55 + Vector3.DOWN * 0.75 + Vector3(0, 0, -0.35)).normalized()
	_two_bone(arm, fore, hand, wrist_target, pole)
	# Straighten the wrist: real riders keep the hand roughly in line with the forearm. Blend the
	# hand direction towards the forearm's line (while still reaching over the grip) and re-solve.
	var fore_dir := (_g[hand].origin - _g[fore].origin).normalized()
	var hand_dir := finger_dir.lerp(fore_dir, 0.6).normalized()
	if hand_dir.dot(front_r) < 0.25:
		hand_dir = (hand_dir + front_r * (0.25 - hand_dir.dot(front_r))).normalized()
	wrist_target = knuckles - hand_dir * hand_len
	_two_bone(arm, fore, hand, wrist_target, pole)
	# Lock the wrist exactly on target and orient the hand along the grip.
	_move(hand, wrist_target - _g[hand].origin)
	var cur_f := _g[_bi(pre + "HandMiddle1")].origin - _g[hand].origin
	var cur_s := _g[_bi(pre + "HandPinky1")].origin - _g[_bi(pre + "HandIndex1")].origin
	_orient(hand, cur_f, cur_s, hand_dir, knuckle_line)
	# Forearm roll: a real forearm pronates with the hand, so pass most of the hand's twist (relative
	# to its rest pose) into the forearm. Without this the skin twists like a wrung towel at the wrist.
	var fa := (_g[hand].origin - _g[fore].origin).normalized()
	var side_local := _g[hand].basis.orthonormalized().inverse() * knuckle_line
	var predicted := (_g[fore].basis.orthonormalized() * _rest_local[hand].basis.orthonormalized()) * side_local
	var p1 := (predicted - fa * predicted.dot(fa)).normalized()
	var p2 := (knuckle_line - fa * knuckle_line.dot(fa)).normalized()
	var twist := atan2(p1.cross(p2).dot(fa), p1.dot(p2))
	_rot(fore, fa, twist * 0.8, _g[fore].origin)
	_rot(hand, fa, -twist * 0.8, _g[hand].origin)
	# Nudge the hand so the middle knuckle sits exactly on its spot (bone lengths differ per finger).
	_move(hand, knuckles - _g[_bi(pre + "HandMiddle1")].origin)

	# --- fingers: each joint is aimed so the next one lands on a circle hugging the grip ---
	var wrap_r := GRIP_RADIUS + 0.0095
	var on_lever := 0.0
	var pull := 0.0
	if side > 0:
		lever_pull = 0.0
	else:
		clutch_pull = 0.0
	if side > 0:
		on_lever = _brk_cover
		pull = _brk_pull
	elif clutch > 0.0:
		on_lever = clutch
		pull = clutch
	# Lever position in the grip cross-section (pulled back towards the grip as pressure rises).
	# Lever contact point, swung back exactly like the bike's pivoting lever mesh.
	var lv_b := Vector3(LEVER_IN.x * side, LEVER_IN.y, LEVER_IN.z).lerp(Vector3(LEVER_OUT.x * side, LEVER_OUT.y, LEVER_OUT.z), 0.42)
	var piv := BikeVisual.lever_pivot(side)
	lv_b = piv + BikeVisual.lever_basis(side, pull) * (lv_b - piv)
	var lever_c := _sk(lv_b)
	lever_pull = pull if side > 0 else lever_pull
	clutch_pull = pull if side < 0 else clutch_pull
	for f: String in ["Index", "Middle", "Ring", "Pinky"]:
		var bones := [_bi(pre + "Hand" + f + "1"), _bi(pre + "Hand" + f + "2"), _bi(pre + "Hand" + f + "3"), _bi(pre + "Hand" + f + "4")]
		var lever_finger: bool = (f == "Index" or f == "Middle")
		if lever_finger and on_lever > 0.5:
			_wrap_chain(bones, lever_c, 0.011, axis, front_r, top_r)
		else:
			_wrap_chain(bones, center, wrap_r + (0.002 if f == "Pinky" else 0.0), axis, front_r, top_r)
	# Thumb wraps under the inner side of the grip, coming from behind.
	var inner := -axis
	var tb := [_bi(pre + "HandThumb1"), _bi(pre + "HandThumb2"), _bi(pre + "HandThumb3"), _bi(pre + "HandThumb4")]
	var tpts := [center + inner * 0.03 - front_r * 0.03 + top_r * 0.0,
			center + inner * 0.02 - front_r * 0.012 - top_r * 0.026,
			center + inner * 0.008 + front_r * 0.008 - top_r * 0.028]
	for j in 3:
		_aim(tb[j], tb[j + 1], tpts[j])

## Wrap a finger chain (4 joints) around a circle (center, radius) in the plane perpendicular to
## `axis`, travelling from the top-front, forward, down and under (the way a hand closes on a bar).
func _wrap_chain(bones: Array, c: Vector3, r: float, axis: Vector3, e1: Vector3, e2: Vector3) -> void:
	var hand_sign := signf(e1.cross(e2).dot(axis))
	for j in 3:
		var p: Vector3 = _g[bones[j]].origin
		var q: Vector3 = _g[bones[j + 1]].origin
		var seg := q - p
		var seg2 := Vector2(seg.dot(e1), seg.dot(e2))
		var l := seg2.length()
		if l < 1e-4:
			continue
		var p2 := Vector2((p - c).dot(e1), (p - c).dot(e2))
		var target2: Vector2
		var d := p2.length()
		if d > r + l:
			target2 = p2 + (-p2).normalized() * l        # too far: reach straight in
		elif d < absf(r - l):
			# Inside the ring: step tangentially (clockwise in e1/e2 = forward -> down).
			var tang := Vector2(p2.y, -p2.x).normalized()
			target2 = p2 + tang * l
		else:
			# Circle-circle intersection; take the one that advances clockwise.
			var a := (d * d + l * l - r * r) / (2.0 * d)
			var h := sqrt(maxf(l * l - a * a, 0.0))
			var mid := p2 + (-p2 / d) * a
			var perp := Vector2(-(-p2.y / d), -p2.x / d)
			var c1 := mid + perp * h
			var c2 := mid - perp * h
			var ap := atan2(p2.y, p2.x)
			var d1 := fposmod(ap - atan2(c1.y, c1.x), TAU)
			var d2 := fposmod(ap - atan2(c2.y, c2.x), TAU)
			target2 = c1 if d1 < d2 else c2
		var cur_ang := atan2(seg2.y, seg2.x)
		var want_ang := atan2(target2.y - p2.y, target2.x - p2.x)
		var delta := wrapf(want_ang - cur_ang, -PI, PI)
		_rot(bones[j], axis, delta * hand_sign, p)

func _pose_leg(side: float) -> void:
	var pre := "Right" if side > 0 else "Left"
	var up_leg := _bi(pre + "UpLeg")
	var leg := _bi(pre + "Leg")
	var foot := _bi(pre + "Foot")
	var toe := _bi(pre + "ToeBase")
	var peg := _sk(Vector3(PEG.x * side, PEG.y, PEG.z))
	var inside := 1.0 if signf(_hang) == side else 0.0
	# Ball of the foot on the peg, foot pointing forward (slightly down and out), heel up and
	# clear of the heel guard. The ankle is placed back from the ball by the real foot length.
	var out := Vector3(-side, 0, 0)
	var want_f := (Vector3(0, 0, 1) * 0.95 + Vector3.DOWN * 0.27 + out * 0.1).normalized()
	var foot_len := (_g[toe].origin - _g[foot].origin).length()
	var ball := peg + out * 0.02 + Vector3.UP * 0.035
	var ankle := ball - want_f * foot_len + Vector3.UP * 0.02
	var pole := (Vector3(0, 0, 1) * 0.95 + out * (-0.08 + inside * absf(_hang) * 0.9) + Vector3.UP * 0.25).normalized()
	_two_bone(up_leg, leg, foot, ankle, pole)
	_move(foot, ankle - _g[foot].origin)
	var cur_f := _g[toe].origin - _g[foot].origin
	_orient(foot, cur_f, Vector3(-1, 0, 0), want_f, Vector3(-1, 0, 0))
	# Toes flat-ish on the peg rather than pointing down.
	var toe_end := _bi(("Right" if side > 0 else "Left") + "Toe_End")
	_aim(toe, toe_end, _g[toe].origin + (Vector3(0, 0, 1) + out * 0.1).normalized() * 0.1)

## Convert working globals back to local bone poses.
func _apply() -> void:
	for i in _g.size():
		var p := skel.get_bone_parent(i)
		var local: Transform3D = _g[i] if p < 0 else _g[p].affine_inverse() * _g[i]
		skel.set_bone_pose_position(i, local.origin)
		skel.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())

