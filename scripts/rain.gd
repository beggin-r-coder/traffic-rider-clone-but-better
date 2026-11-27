extends Node3D
class_name Rain
## Rain mode: falling streaks, road splashes, tyre spray, visor drops (first person) and a planar
## reflection camera that feeds the wet road shader with a real-time mirror image of the scene.

const RAIN_LAYER := 1 << 3          # render layer for rain effects (kept out of reflections)

var rider: Rider
var road: Road
var streaks: GPUParticles3D
var splashes: GPUParticles3D
var spray: GPUParticles3D
var visor: ColorRect
var refl_vp: SubViewport
var refl_cam: Camera3D
var _rain_mat: ShaderMaterial
var _visor_mat: ShaderMaterial
var _frame := 0
var _quality := 1

func setup(r: Rider, rd: Road, ui_parent: Node) -> void:
	rider = r
	road = rd
	_quality = Game.quality
	_build_streaks()
	_build_splashes()
	_build_spray()
	_build_visor(ui_parent)
	if _quality >= 1:
		_build_reflection()

# ------------------------------------------------------------------ particles

func _build_streaks() -> void:
	streaks = GPUParticles3D.new()
	streaks.amount = [700, 1800, 3200][_quality]
	streaks.lifetime = 1.1
	streaks.preprocess = 1.1
	streaks.local_coords = false
	streaks.layers = RAIN_LAYER
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streaks.visibility_aabb = AABB(Vector3(-60, -40, -80), Vector3(120, 80, 160))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 4, 22)
	pm.direction = Vector3.DOWN
	pm.spread = 3.0
	pm.initial_velocity_min = 8.5
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3.ZERO
	streaks.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = preload("res://shaders/rain_streak.gdshader")
	_rain_mat.set_shader_parameter("tint", Color(0.72, 0.76, 0.82, 0.16))
	q.material = _rain_mat
	streaks.draw_pass_1 = q
	add_child(streaks)

func _build_splashes() -> void:
	splashes = GPUParticles3D.new()
	splashes.amount = [150, 350, 600][_quality]
	splashes.lifetime = 0.35
	splashes.local_coords = false
	splashes.layers = RAIN_LAYER
	splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splashes.visibility_aabb = AABB(Vector3(-40, -10, -60), Vector3(80, 20, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9, 0.01, 18)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, -6, 0)
	pm.scale_min = 0.05
	pm.scale_max = 0.11
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	splashes.process_material = pm
	var q := QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/rain_splash.gdshader")
	m.set_shader_parameter("tint", Color(0.82, 0.86, 0.9, 0.45))
	q.material = m
	splashes.draw_pass_1 = q
	add_child(splashes)

func _build_spray() -> void:
	spray = GPUParticles3D.new()
	spray.amount = [40, 90, 140][_quality]
	spray.lifetime = 0.7
	spray.local_coords = false
	spray.layers = RAIN_LAYER
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spray.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 20, 60))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.45, 1)
	pm.spread = 14.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -3, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.35
	pm.scale_max = 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.2))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	spray.process_material = pm
	var q := QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/rain_splash.gdshader")
	m.set_shader_parameter("tint", Color(0.78, 0.82, 0.86, 0.22))
	q.material = m
	spray.draw_pass_1 = q
	add_child(spray)

func _build_visor(ui_parent: Node) -> void:
	if _quality == 0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 1                # under the HUD
	ui_parent.add_child(layer)
	visor = ColorRect.new()
	visor.set_anchors_preset(Control.PRESET_FULL_RECT)
	visor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor_mat = ShaderMaterial.new()
	_visor_mat.shader = preload("res://shaders/visor_rain.gdshader")
	visor.material = _visor_mat
	layer.add_child(visor)

# ------------------------------------------------------------------ planar reflection

func _build_reflection() -> void:
	refl_vp = SubViewport.new()
	var scale := 0.5 if _quality >= 2 else 0.33
	var vs := get_viewport().get_visible_rect().size
	refl_vp.size = Vector2i(maxi(int(vs.x * scale), 64), maxi(int(vs.y * scale), 36))
	refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	refl_vp.msaa_3d = Viewport.MSAA_DISABLED
	refl_vp.positional_shadow_atlas_size = 0
	add_child(refl_vp)
	refl_cam = Camera3D.new()
	refl_cam.cull_mask = 0xFFFFF & ~RAIN_LAYER & ~Road.GROUND_LAYER
	refl_vp.add_child(refl_cam)
	refl_cam.current = true

func reflection_texture() -> Texture2D:
	return refl_vp.get_texture() if refl_vp else null

## Mirror the main camera about the road surface under the bike.
func _update_reflection() -> void:
	if refl_cam == null:
		return
	if _quality == 1:
		_frame += 1
		refl_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if _frame % 2 == 0 else SubViewport.UPDATE_DISABLED
	var cam := rider.camera
	var p0 := road.point(rider.s, rider.d)
	var n := road.basis_at(rider.s).y.normalized()
	var ct := cam.global_transform
	var refl := func(v: Vector3) -> Vector3: return v - 2.0 * v.dot(n) * n
	var o: Vector3 = ct.origin - 2.0 * (ct.origin - p0).dot(n) * n
	var bx: Vector3 = refl.call(ct.basis.x)
	var by: Vector3 = refl.call(ct.basis.y)
	var bz: Vector3 = refl.call(ct.basis.z)
	# A reflection flips handedness; negate X to get a valid camera (the shader flips U back).
	refl_cam.global_transform = Transform3D(Basis(-bx, by, bz), o)
	refl_cam.fov = cam.fov
	refl_cam.near = cam.near
	refl_cam.far = minf(cam.far, 700.0)
	var vs := get_viewport().get_visible_rect().size
	var scale := 0.5 if _quality >= 2 else 0.33
	var want := Vector2i(maxi(int(vs.x * scale), 64), maxi(int(vs.y * scale), 36))
	if refl_vp.size != want:
		refl_vp.size = want

# ------------------------------------------------------------------ per frame

func update(dt: float) -> void:
	var cam := rider.camera
	var ct := cam.global_transform
	var bike_t := rider.bike.global_transform
	var fwd := -bike_t.basis.z
	var vel := fwd * rider.v
	# Streak box sits around/ahead of the camera so it is full at any speed.
	streaks.global_position = ct.origin + fwd * (6.0 + rider.v * 0.45) + Vector3.UP * 4.0
	_rain_mat.set_shader_parameter("viewer_velocity", vel)
	# Splashes on the road around and ahead of the bike.
	splashes.global_position = road.point(rider.s + 10.0 + rider.v * 0.3, rider.d, 0.02)
	# Tyre spray off the rear wheel, more with speed.
	var rear := bike_t * Vector3(0, 0.05, 0.85)
	spray.global_transform = Transform3D(bike_t.basis, rear)
	spray.amount_ratio = clampf(rider.v / 45.0, 0.0, 1.0)
	spray.emitting = rider.v > 3.0 and not rider.is_crashed
	if visor:
		visor.visible = Game.view == Game.View.FIRST_PERSON and not rider.is_crashed and not Game.has_flag("photo")
		var vs := visor.get_viewport_rect().size
		_visor_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
		_visor_mat.set_shader_parameter("speed", clampf(rider.v / 45.0, 0.0, 1.0))
	_update_reflection()
