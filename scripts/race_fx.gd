extends Node3D
class_name RaceFx
## Tyre effects in world space: smoke off the rear tyre when it slides or locks under hard braking,
## and dark skid marks laid on the road behind it (a pooled MultiMesh of thin quads, oldest reused).

const MARKS := 360
const MARK_STEP := 0.22          # metres between skid-mark quads

var smoke: GPUParticles3D
var marks: MultiMeshInstance3D
var _mm: MultiMesh
var _next := 0
var _last := Vector3.INF

func _ready() -> void:
	smoke = GPUParticles3D.new()
	smoke.amount = 48 if Game.quality >= 1 else 20
	smoke.lifetime = 1.4
	smoke.local_coords = false
	smoke.emitting = false
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 10, 40))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var c := Curve.new()
	c.add_point(Vector2(0, 0.35))
	c.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	var a := Gradient.new()
	a.set_color(0, Color(0.85, 0.85, 0.86, 0.5))
	a.set_color(1, Color(0.85, 0.85, 0.86, 0.0))
	var at := GradientTexture1D.new()
	at.gradient = a
	pm.color_ramp = at
	smoke.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	m.albedo_texture = gt
	q.material = m
	smoke.draw_pass_1 = q
	add_child(smoke)

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var mq := QuadMesh.new()
	mq.size = Vector2(0.1, MARK_STEP * 1.15)
	mq.orientation = PlaneMesh.FACE_Y
	_mm.mesh = mq
	_mm.instance_count = MARKS
	_mm.visible_instance_count = 0
	marks = MultiMeshInstance3D.new()
	marks.multimesh = _mm
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.vertex_color_use_as_albedo = true
	mm.albedo_color = Color(0.02, 0.02, 0.02, 1.0)
	mm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	marks.material_override = mm
	add_child(marks)

## Called every frame: `contact` = rear tyre contact point (world), `heading` = travel direction,
## `up` = road normal, `amount` 0..1 = how hard the tyre is sliding / locked.
func update_tyre(contact: Vector3, heading: Vector3, up: Vector3, amount: float) -> void:
	smoke.emitting = amount > 0.35
	if smoke.emitting:
		smoke.global_position = contact + up * 0.08
		smoke.amount_ratio = clampf(amount, 0.3, 1.0)
	if amount < 0.25:
		_last = Vector3.INF
		return
	if _last == Vector3.INF:
		_last = contact
		return
	var seg := contact - _last
	if seg.length() < MARK_STEP:
		return
	var mid := (_last + contact) * 0.5 + up * 0.012
	var fwd := seg.normalized()
	var right := fwd.cross(up).normalized()
	var b := Basis(right, up, -fwd)
	_mm.set_instance_transform(_next, Transform3D(b, mid))
	_mm.set_instance_color(_next, Color(0, 0, 0, clampf(amount, 0.3, 0.75)))
	_next = (_next + 1) % MARKS
	_mm.visible_instance_count = mini(_mm.visible_instance_count + 1, MARKS)
	marks.custom_aabb = AABB(contact - Vector3(400, 50, 400), Vector3(800, 100, 800))
	_last = contact
