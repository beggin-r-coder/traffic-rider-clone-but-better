extends Node3D
class_name RiderModel
## The rider, posed procedurally on the selected bike every frame:
## seated tuck (torso pitch solved so the arms reach the bars of each bike), head up, two-bone IK
## arms with the hands locked onto the grips and the fingers wrapped around the bar, IK legs with
## the balls of the feet on the footpegs, hang-off in corners.
## Throttle rolls the right wrist back around the grip; braking moves the right fingers onto the
## brake lever and pulls it; gear shifts blip the left fingers on the clutch.
##
## Works with two rigs through a bone-name profile: the leather-suited Biker (default; mitten glove
## fingers, no toe bones: finger tips and toes are found from the skin weights) and the older Ready
## Player Me avatar (--rider=rpm).
##
## Lives in the bike's leaning frame (bike space: -Z forward, +X right, origin on the ground).
## All solving happens in skeleton space (avatar faces +Z, left = +X); bike points are mapped
## with (x, y, z) -> (-x, y, -z).

const PROFILES := {
	"biker": {
		"model": "res://assets/rider2/Biker.glb",
		"hips": "Origin", "spine": ["Spine1", "Spine2", "Spine3"], "neck": "Neck", "head": "Head",
		"eyes": ["Leye", "Reye"],
		"L": {"clav": "Lclavicle", "arm": "Lshoulder", "fore": "Lelbow", "hand": "Lwrist",
			"fingers": [["Lmitt01", "Lmitt02"]], "thumb": ["Lthumb01", "Lthumb01|Rthumb02"],
			"upleg": "Lhip", "leg": "Lknee", "foot": "Lankle"},
		"R": {"clav": "Rclavicle", "arm": "Rshoulder", "fore": "Relbow", "hand": "Rwrist",
			"fingers": [["Rmitt01", "Rmitt02"]], "thumb": ["Rthumb01", "Rthumb01|Rthumb02"],
			"upleg": "Rhip", "leg": "Rknee", "foot": "Rankle"},
		"head_meshes": [],
		"seat_lift": 0.10,
		"head_comp": 0.47,
	},
	"rpm": {
		"model": "res://assets/rider/rider.glb",
		"hips": "Hips", "spine": ["Spine", "Spine1", "Spine2"], "neck": "Neck", "head": "Head",
		"eyes": ["LeftEye", "RightEye"],
		"L": {"clav": "LeftShoulder", "arm": "LeftArm", "fore": "LeftForeArm", "hand": "LeftHand",
			"fingers": [["LeftHandIndex1", "LeftHandIndex2", "LeftHandIndex3", "LeftHandIndex4"],
				["LeftHandMiddle1", "LeftHandMiddle2", "LeftHandMiddle3", "LeftHandMiddle4"],
				["LeftHandRing1", "LeftHandRing2", "LeftHandRing3", "LeftHandRing4"],
				["LeftHandPinky1", "LeftHandPinky2", "LeftHandPinky3", "LeftHandPinky4"]],
			"thumb": ["LeftHandThumb1", "LeftHandThumb2", "LeftHandThumb3", "LeftHandThumb4"],
			"upleg": "LeftUpLeg", "leg": "LeftLeg", "foot": "LeftFoot", "toe": "LeftToeBase", "toe_end": "LeftToe_End"},
		"R": {"clav": "RightShoulder", "arm": "RightArm", "fore": "RightForeArm", "hand": "RightHand",
			"fingers": [["RightHandIndex1", "RightHandIndex2", "RightHandIndex3", "RightHandIndex4"],
				["RightHandMiddle1", "RightHandMiddle2", "RightHandMiddle3", "RightHandMiddle4"],
				["RightHandRing1", "RightHandRing2", "RightHandRing3", "RightHandRing4"],
				["RightHandPinky1", "RightHandPinky2", "RightHandPinky3", "RightHandPinky4"]],
			"thumb": ["RightHandThumb1", "RightHandThumb2", "RightHandThumb3", "RightHandThumb4"],
			"upleg": "RightUpLeg", "leg": "RightLeg", "foot": "RightFoot", "toe": "RightToeBase", "toe_end": "RightToe_End"},
		"head_meshes": ["Wolf3D_Head", "Wolf3D_Teeth", "EyeLeft", "EyeRight", "Wolf3D_Headwear"],
		"seat_lift": 0.105,
	},
}

const GRIP_RADIUS := 0.02                          # grip rubber + glove

var def: Dictionary = {}       # BikeDefs entry (contact points); defaults to the selected bike
var prof: Dictionary
var GRIP_IN: Vector3
var GRIP_OUT: Vector3
var LEVER_IN: Vector3
var LEVER_OUT: Vector3
var PEG: Vector3
var SEAT: Vector3

var skel: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var head_meshes: Array[MeshInstance3D] = []
var _rest_local: Array[Transform3D] = []
var _g: Array[Transform3D] = []         # working global (skeleton-space) transforms
var _children := {}                     # bone -> [descendant bones incl. itself]
var _b := {}                            # name -> index
var _side := {}                         # 1.0 / -1.0 -> resolved bone indices for that side
var _tip := {}                          # last bone of a chain -> tip offset in its rest-local frame
var _hand_side_local := {}              # hand bone -> index->pinky direction in its local frame

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
var _pitch_extra := 0.0
var frozen := false
var lever_pull := 0.0      # current brake lever pull (for the bike's lever mesh)
var clutch_pull := 0.0

func _ready() -> void:
	if def.is_empty():
		def = BikeDefs.current()
	GRIP_IN = def["grip_in"]
	GRIP_OUT = def["grip_out"]
	LEVER_IN = def["lever_in"]
	LEVER_OUT = def["lever_out"]
	PEG = def["peg"]
	SEAT = def["seat"]
	prof = PROFILES["rpm" if String(Game.flag("rider", "biker")) == "rpm" else "biker"]
	var avatar: Node3D = load(prof["model"]).instantiate()
	avatar.rotation.y = PI               # avatar faces +Z; the bike faces -Z
	add_child(avatar)
	skel = avatar.find_children("*", "Skeleton3D", true, false)[0]
	for m in avatar.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		meshes.append(mi)
		mi.layers = BikeVisual.BIKE_LAYER
		if mi.name in prof["head_meshes"]:
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
	for side: float in [1.0, -1.0]:
		var src: Dictionary = prof["R" if side > 0 else "L"]
		var d := {}
		for k in ["clav", "arm", "fore", "hand", "upleg", "leg", "foot"]:
			d[k] = _b[src[k]]
		d["fingers"] = []
		for chain: Array in src["fingers"]:
			d["fingers"].append(chain.map(func(b): return _b[b]))
		d["thumb"] = (src["thumb"] as Array).map(func(b): return _b[b])
		d["toe"] = _b.get(src.get("toe", ""), -1)
		d["toe_end"] = _b.get(src.get("toe_end", ""), -1)
		_side[side] = d
	_measure_rig()
	update_pose(1.0)

## Rig facts that are not in the bone list: finger/thumb tips (rigs without tip bones), the toe
## (rigs without toe bones) and the across-the-knuckles direction of each hand.
func _measure_rig() -> void:
	var rest_g: Array[Transform3D] = []
	rest_g.resize(skel.get_bone_count())
	for i in rest_g.size():
		rest_g[i] = skel.get_bone_global_rest(i)
	for side: float in [1.0, -1.0]:
		var d: Dictionary = _side[side]
		var chains: Array = d["fingers"].duplicate()
		chains.append(d["thumb"])
		for chain: Array in chains:
			if chain.size() >= 4:
				continue          # last bone is already a tip marker
			var last: int = chain[-1]
			var prev: int = chain[-2] if chain.size() > 1 else d["hand"]
			var dir := (rest_g[last].origin - rest_g[prev].origin).normalized()
			var reach := _vertex_reach(last, rest_g[last].origin, dir)
			var tip := rest_g[last].origin + dir * maxf(reach - 0.006, 0.02)
			_tip[last] = rest_g[last].affine_inverse() * tip
		# Index -> pinky across the knuckles. In the rest pose both hands' index side faces +Z.
		var hb: int = d["hand"]
		_hand_side_local[hb] = rest_g[hb].basis.inverse() * Vector3(0, 0, -1)
		if d["toe"] < 0:
			var f: int = d["foot"]
			var reach := _vertex_reach(f, rest_g[f].origin, Vector3(0, 0, 1))
			var toe := rest_g[f].origin + Vector3(0, 0, reach)
			toe.y = rest_g[f].origin.y - 0.045
			_tip[f] = rest_g[f].affine_inverse() * toe

## Farthest extent along `dir` of the skin vertices mostly weighted to `bone`, from `origin`.
func _vertex_reach(bone: int, origin: Vector3, dir: Vector3) -> float:
	var best := 0.0
	for mi in meshes:
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if bones == null or weights == null or verts.is_empty():
				continue
			var per := int(bones.size() / verts.size())
			for v in verts.size():
				var w := 0.0
				for k in per:
					if int(bones[v * per + k]) == bone:
						w += float(weights[v * per + k])
				if w > 0.5:
					best = maxf(best, (verts[v] - origin).dot(dir))
	return best

## Position of joint k of a chain (k == size -> the measured tip of the last bone).
func _chain_pt(chain: Array, k: int) -> Vector3:
	if k < chain.size():
		return _g[chain[k]].origin
	var last: int = chain[-1]
	return _g[last] * (_tip[last] as Vector3)

func _chain_len(chain: Array) -> int:
	return chain.size() + (1 if _tip.has(chain[-1]) else 0)

func _toe_pt(d: Dictionary) -> Vector3:
	if d["toe"] >= 0:
		return _g[d["toe"]].origin
	return _g[d["foot"]] * (_tip[d["foot"]] as Vector3)

var _fp_arms: Array[MeshInstance3D] = []   # forearm+glove-only copies, shown in first person

## First person: show only the forearms and gloves (separate meshes built from the suit by bone
## weights), hide everything else: head, torso, shoulders, upper arms, legs. No fading, no seams.
func set_first_person(fp: bool) -> void:
	if fp and _fp_arms.is_empty():
		_build_fp_arms()
	for mi in meshes:
		mi.visible = not fp
	for a in _fp_arms:
		a.visible = fp

func _build_fp_arms() -> void:
	# Per side: bones that make up the arm, and the rest-pose rotation that swings the upper arm
	# into a straight continuation of the forearm (so in first person the sleeve runs on past the
	# elbow and out of frame instead of ending in view).
	var arm_info := {}
	for side: float in [1.0, -1.0]:
		var sd: Dictionary = _side[side]
		var ua: int = sd["arm"]
		var fa: int = sd["fore"]
		var hb: int = sd["hand"]
		var sh_p := skel.get_bone_global_rest(ua).origin
		var el_p := skel.get_bone_global_rest(fa).origin
		var wr_p := skel.get_bone_global_rest(hb).origin
		var u := (sh_p - el_p).normalized()
		var f := (el_p - wr_p).normalized()      # continuing back past the elbow
		var ax := u.cross(f)
		var rot := Basis() if ax.length() < 1e-5 else Basis(ax.normalized(), u.angle_to(f))
		var hand_bones := {}
		for bi in _children[hb]:
			hand_bones[bi] = true
		arm_info[side] = {"ua": ua, "fa": fa, "elbow": el_p, "rot": rot, "hand": hand_bones}
	for mi in meshes:
		if mi in head_meshes or mi.mesh == null:
			continue
		var out := ArrayMesh.new()
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if bones == null or weights == null or idx.is_empty():
				continue
			var per := int(bones.size() / verts.size())
			var keepv := PackedByteArray()
			keepv.resize(verts.size())
			for v in verts.size():
				for side in arm_info:
					var info: Dictionary = arm_info[side]
					var w_hand := 0.0
					var w_arm := 0.0
					for k in per:
						var bi := int(bones[v * per + k])
						var w := float(weights[v * per + k])
						if info["hand"].has(bi):
							w_hand += w
						elif bi == info["fa"] or bi == info["ua"]:
							w_arm += w
					if w_hand + w_arm < 0.6:
						continue
					keepv[v] = 1
					if w_hand < 0.5:
						# Sleeve: rigidly on the forearm; upper-arm part swung onto the forearm line.
						var w_ua := 0.0
						for k in per:
							if int(bones[v * per + k]) == info["ua"]:
								w_ua += float(weights[v * per + k])
						if w_ua > 0.0:
							var el: Vector3 = info["elbow"]
							var r: Basis = info["rot"]
							var t := clampf(w_ua * 2.0, 0.0, 1.0)
							var moved := el + r * (verts[v] - el)
							verts[v] = verts[v].lerp(moved, t)
							norms[v] = norms[v].lerp(r * norms[v], t).normalized()
						for k in per:
							bones[v * per + k] = info["fa"] if k == 0 else 0
							weights[v * per + k] = 1.0 if k == 0 else 0.0
					break
			var keep := PackedInt32Array()
			for t in idx.size() / 3:
				if keepv[idx[t * 3]] and keepv[idx[t * 3 + 1]] and keepv[idx[t * 3 + 2]]:
					keep.append(idx[t * 3])
					keep.append(idx[t * 3 + 1])
					keep.append(idx[t * 3 + 2])
			if keep.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = keep
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
			arrays[Mesh.ARRAY_TANGENT] = null
			var fmt: int = mi.mesh.surface_get_format(si) & ~Mesh.ARRAY_FORMAT_TANGENT
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
			var m: Material = mi.mesh.surface_get_material(si)
			if m is BaseMaterial3D:
				m = m.duplicate()
				(m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_BACK
			out.surface_set_material(out.get_surface_count() - 1, m)
		if out.get_surface_count() == 0:
			continue
		var c := MeshInstance3D.new()
		c.mesh = out
		c.skin = mi.skin
		c.layers = mi.layers
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.get_parent().add_child(c)
		c.transform = mi.transform
		c.skeleton = c.get_path_to(skel)
		c.visible = false
		_fp_arms.append(c)

## Midpoint between the shoulder joints (bike-leaning-frame space).
func shoulder_mid() -> Vector3:
	var m := (_g[_side[-1.0]["arm"]].origin + _g[_side[1.0]["arm"]].origin) * 0.5
	return Vector3(-m.x, m.y, -m.z)

## First-person camera mount: above and behind the rider's shoulders, placed relative to the bike's
## bars (same view on every bike and rider: ~0.46 m above and 0.74 m behind the grips), dipping a
## little as the rider tucks in at speed.
func fp_camera_position() -> Vector3:
	var g := GRIP_IN.lerp(GRIP_OUT, 0.5)
	return Vector3(0.0, g.y + 0.46 - 0.03 * _tuck, g.z + 0.74 + 0.02 * _tuck)

## Eye position (bike-leaning-frame space).
func eye_position() -> Vector3:
	var e := (_g[_b[prof["eyes"][0]]].origin + _g[_b[prof["eyes"][1]]].origin) * 0.5
	return Vector3(-e.x, e.y, -e.z)

## First-person camera mount: a chin cam just below and in front of the eyes (classic onboard view).
func chin_cam_position() -> Vector3:
	var head := _g[_b[prof["head"]]]
	var e := (_g[_b[prof["eyes"][0]]].origin + _g[_b[prof["eyes"][1]]].origin) * 0.5
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

## Shortest-arc rotation of a bone subtree so the direction from `bone` to point `tip` points at `target`.
func _aim_pt(bone: int, tip: Vector3, target: Vector3) -> void:
	var o := _g[bone].origin
	var a := (tip - o).normalized()
	var b := (target - o).normalized()
	var axis := a.cross(b)
	if axis.length() < 1e-6:
		return
	_rot(bone, axis, a.angle_to(b), o)

func _aim(bone: int, tip_bone: int, target: Vector3) -> void:
	_aim_pt(bone, _g[tip_bone].origin, target)

## Two-bone IK: root -> mid -> end reaches `target`, bending towards `pole` (a direction).
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

## Current index->pinky direction of a hand.
func _hand_across(d: Dictionary) -> Vector3:
	var hb: int = d["hand"]
	var f: Array = d["fingers"]
	if f.size() >= 4:
		return _g[f[3][0]].origin - _g[f[0][0]].origin
	return _g[hb].basis * (_hand_side_local[hb] as Vector3)

## Knuckle (base of the middle finger) of a hand.
func _knuckle(d: Dictionary) -> Vector3:
	var f: Array = d["fingers"]
	return _g[f[1][0] if f.size() >= 4 else f[0][0]].origin

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
	var hips := _bi(prof["hips"])
	var spine: Array = (prof["spine"] as Array).map(func(b): return _b[b])

	# --- pelvis on the seat, tilted forward; hang off the inside in corners ---
	var hip_target := _sk(SEAT) + up * float(prof["seat_lift"]) + Vector3(-_hang * 0.11, -absf(_hang) * 0.015, 0)
	_move(hips, hip_target - _g[hips].origin)
	var base_pitch := deg_to_rad(42.0 + 8.0 * _tuck)
	_rot(hips, Vector3.RIGHT, base_pitch, _g[hips].origin)

	# --- spine curve: more tuck at speed ---
	var curve := [[5.0, 3.0], [7.0, 3.0], [6.0, 3.0]]
	for i in 3:
		var bi: int = spine[i]
		_rot(bi, Vector3.RIGHT, deg_to_rad(curve[i][0] + curve[i][1] * _tuck), _g[bi].origin)

	# --- torso pitch solved per bike: shoulders at a natural reach (elbows bent) from the grips ---
	var want := _target_pitch_extra(hips)
	_pitch_extra = want if dt >= 0.5 else lerpf(_pitch_extra, want, 1.0 - exp(-8.0 * dt))
	_rot(hips, Vector3.RIGHT, _pitch_extra, _g[hips].origin)
	_rot(hips, fwd, deg_to_rad(_hang * 10.0), _g[hips].origin)
	# Lean the upper body a little into the turn.
	_rot(spine[1], fwd, deg_to_rad(_hang * 9.0), _g[spine[1]].origin)

	# --- head up, eyes level, looking a touch into the turn ---
	var torso_pitch := 42.0 + 8.0 * _tuck + 18.0 + 9.0 * _tuck + rad_to_deg(_pitch_extra)
	var neck := _bi(prof["neck"])
	var head := _bi(prof["head"])
	_rot(neck, Vector3.RIGHT, deg_to_rad(-torso_pitch * 0.55), _g[neck].origin)
	_rot(head, Vector3.RIGHT, deg_to_rad(-torso_pitch * float(prof.get("head_comp", 0.38))), _g[head].origin)
	_rot(head, up, deg_to_rad(-steer * 8.0 - _hang * 6.0), _g[head].origin)
	_rot(head, fwd, deg_to_rad(-_hang * 12.0), _g[head].origin)

	# --- arms + hands ---
	for side: float in [1.0, -1.0]:
		_pose_arm(side)

	# --- legs on the pegs ---
	for side: float in [1.0, -1.0]:
		_pose_leg(side)

	_apply()

## Extra forward pitch of the torso (about the hips) that puts the shoulders at ~86% of the full
## arm reach from the grips: bikes with lower / further bars get a deeper crouch.
func _target_pitch_extra(hips: int) -> float:
	var d: Dictionary = _side[1.0]
	var l_arm := (_g[d["fore"]].origin - _g[d["arm"]].origin).length() + (_g[d["hand"]].origin - _g[d["fore"]].origin).length()
	var grip := _sk(GRIP_IN.lerp(GRIP_OUT, 0.48))
	var want := l_arm * 0.86 + 0.035      # wrist sits a few cm behind the grip centre
	var hp := _g[hips].origin
	var sh := _g[d["arm"]].origin
	# Shoulder moves on a circle about the hip joint (pitch axis = X). Search the pitch numerically.
	var best := 0.0
	var best_err := 1e9
	for i in 41:
		var a := deg_to_rad(-14.0 + i * 0.7)
		var p := hp + Basis(Vector3.RIGHT, a) * (sh - hp)
		var err := absf(p.distance_to(grip) - want)
		if err < best_err:
			best_err = err
			best = a
	return best

func _pose_arm(side: float) -> void:
	var sd: Dictionary = _side[side]
	var shoulder: int = sd["clav"]
	var arm: int = sd["arm"]
	var fore: int = sd["fore"]
	var hand: int = sd["hand"]
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
	var hand_len := (_knuckle(sd) - _g[hand].origin).length()
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
	var cur_f := _knuckle(sd) - _g[hand].origin
	var cur_s := _hand_across(sd)
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
	_move(hand, knuckles - _knuckle(sd))

	# --- fingers: each joint is aimed so the next one lands on a circle hugging the grip ---
	var wrap_r := GRIP_RADIUS + 0.0095
	var on_lever := 0.0
	var pull := 0.0
	if side > 0:
		on_lever = _brk_cover
		pull = _brk_pull
	elif clutch > 0.0:
		on_lever = clutch
		pull = clutch
	# Lever contact point, swung back exactly like the bike's pivoting lever mesh.
	var lv_b := Vector3(LEVER_IN.x * side, LEVER_IN.y, LEVER_IN.z).lerp(Vector3(LEVER_OUT.x * side, LEVER_OUT.y, LEVER_OUT.z), 0.42)
	var piv := BikeVisual.lever_pivot(def, side)
	lv_b = piv + BikeVisual.lever_basis(def, side, pull) * (lv_b - piv)
	var lever_c := _sk(lv_b)
	if side > 0:
		lever_pull = pull
	else:
		clutch_pull = pull
	var fingers: Array = sd["fingers"]
	for fi in fingers.size():
		var chain: Array = fingers[fi]
		# Four-finger rigs: index + middle go to the lever. Mitten rigs: the whole mitten does.
		var lever_finger: bool = fingers.size() == 1 or fi <= 1
		if lever_finger and on_lever > 0.5:
			_wrap_chain(chain, lever_c, 0.011, axis, front_r, top_r)
		else:
			_wrap_chain(chain, center, wrap_r + (0.002 if fi == 3 else 0.0), axis, front_r, top_r)
	# Thumb wraps under the inner side of the grip, coming from behind.
	var inner := -axis
	var tb: Array = sd["thumb"]
	var tpts := [center + inner * 0.03 - front_r * 0.03 + top_r * 0.0,
			center + inner * 0.02 - front_r * 0.012 - top_r * 0.026,
			center + inner * 0.008 + front_r * 0.008 - top_r * 0.028]
	var nseg := _chain_len(tb) - 1
	for j in nseg:
		_aim_pt(tb[j], _chain_pt(tb, j + 1), tpts[3 - nseg + j])

## Wrap a finger chain around a circle (center, radius) in the plane perpendicular to `axis`,
## travelling from the top-front, forward, down and under (the way a hand closes on a bar).
func _wrap_chain(bones: Array, c: Vector3, r: float, axis: Vector3, e1: Vector3, e2: Vector3) -> void:
	var hand_sign := signf(e1.cross(e2).dot(axis))
	for j in _chain_len(bones) - 1:
		var p: Vector3 = _chain_pt(bones, j)
		var q: Vector3 = _chain_pt(bones, j + 1)
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
	var sd: Dictionary = _side[side]
	var up_leg: int = sd["upleg"]
	var leg: int = sd["leg"]
	var foot: int = sd["foot"]
	var peg := _sk(Vector3(PEG.x * side, PEG.y, PEG.z))
	var inside := 1.0 if signf(_hang) == side else 0.0
	# Ball of the foot on the peg, foot pointing forward (slightly down and out), heel up and
	# clear of the heel guard. The ankle is placed back from the ball by the real foot length.
	var out := Vector3(-side, 0, 0)
	var want_f := (Vector3(0, 0, 1) * 0.95 + Vector3.DOWN * 0.27 + out * 0.1).normalized()
	var toe_len := (_toe_pt(sd) - _g[foot].origin).length()
	# Rigs with a toe bone: that joint is the ball of the foot. Otherwise the ball is ~72% of the
	# way from the ankle to the toe tip.
	var ball_len := toe_len if sd["toe"] >= 0 else toe_len * 0.72
	var ball := peg + out * 0.02 + Vector3.UP * 0.035
	var ankle := ball - want_f * ball_len + Vector3.UP * 0.02
	var pole := (Vector3(0, 0, 1) * 0.95 + out * (-0.08 + inside * absf(_hang) * 0.9) + Vector3.UP * 0.25).normalized()
	_two_bone(up_leg, leg, foot, ankle, pole)
	_move(foot, ankle - _g[foot].origin)
	var cur_f := _toe_pt(sd) - _g[foot].origin
	_orient(foot, cur_f, Vector3(-1, 0, 0), want_f, Vector3(-1, 0, 0))
	# Toes flat-ish on the peg rather than pointing down.
	if sd["toe"] >= 0 and sd["toe_end"] >= 0:
		_aim(sd["toe"], sd["toe_end"], _g[sd["toe"]].origin + (Vector3(0, 0, 1) + out * 0.1).normalized() * 0.1)

## Thrown off in a crash: arms and legs flail while airborne and go limp, sprawled, once the rider
## is sliding on the ground. `t` = seconds since the crash, `ground` = 0 airborne .. 1 on the ground.
func update_crash_pose(t: float, ground: float) -> void:
	if skel == null:
		return
	_fk_all()
	var hips := _bi(prof["hips"])
	var spine: Array = (prof["spine"] as Array).map(func(b): return _b[b])
	var air := 1.0 - ground
	var fl := exp(-t * 0.9) * air          # flailing dies down
	# Torso curls in the air, flattens out on the ground.
	for i in 3:
		var bi: int = spine[i]
		_rot(bi, Vector3.RIGHT, deg_to_rad(10.0 * air + 6.0 * sin(t * 7.0 + i) * fl), _g[bi].origin)
	_rot(_bi(prof["head"]), Vector3.RIGHT, deg_to_rad(-15.0 * ground + 20.0 * sin(t * 5.0) * fl), _g[_bi(prof["head"])].origin)
	for side: float in [1.0, -1.0]:
		var sd: Dictionary = _side[side]
		var ph := 0.0 if side > 0 else 1.7
		# Arms (rest pose = T-pose, straight out): flail up/down and fore/aft; on the ground, limp
		# and spread above the head.
		var up_ang := deg_to_rad(lerpf(20.0, 55.0, ground) + 45.0 * sin(t * 9.0 + ph) * fl)
		var fwd_ang := deg_to_rad(lerpf(30.0, -10.0, ground) + 35.0 * sin(t * 6.5 + ph * 1.3) * fl)
		var arm: int = sd["arm"]
		# Rider's right arm points -X: raising it is a negative turn about +Z (and vice versa).
		_rot(arm, Vector3(0, 0, 1), up_ang * -side, _g[arm].origin)
		_rot(arm, Vector3.UP, fwd_ang * side, _g[arm].origin)
		_rot(sd["fore"], Vector3.UP, deg_to_rad(25.0 + 30.0 * absf(sin(t * 8.0 + ph)) * fl) * side, _g[sd["fore"]].origin)
		# Legs: kick and spread in the air, splayed and slightly bent on the ground.
		var leg: int = sd["upleg"]
		var flex := deg_to_rad(lerpf(35.0, 10.0, ground) + 40.0 * sin(t * 7.5 + ph) * fl)
		_rot(leg, Vector3.RIGHT, -flex, _g[leg].origin)
		_rot(leg, Vector3(0, 0, 1), deg_to_rad(lerpf(15.0, 22.0, ground)) * -side, _g[leg].origin)
		_rot(sd["leg"], Vector3.RIGHT, deg_to_rad(lerpf(55.0, 20.0, ground) + 30.0 * absf(sin(t * 6.0 + ph)) * fl), _g[sd["leg"]].origin)
	_apply()

## Convert working globals back to local bone poses.
func _apply() -> void:
	for i in _g.size():
		var p := skel.get_bone_parent(i)
		var local: Transform3D = _g[i] if p < 0 else _g[p].affine_inverse() * _g[i]
		skel.set_bone_pose_position(i, local.origin)
		skel.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
