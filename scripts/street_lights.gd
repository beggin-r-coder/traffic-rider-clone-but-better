extends Node3D
class_name StreetLightPool
## Real lights for the street lamps: a small pool of SpotLight3Ds that hops onto the lamps nearest
## the rider. They actually light the road, bike, rider and traffic, and on the wet road the GGX
## specular naturally stretches each lamp into a long reflection towards the viewer.

var road: Road
var lights: Array[SpotLight3D] = []
var _assigned := {}       # lamp index -> light
var energy := 5.0

func setup(r: Road, count: int, night: bool) -> void:
	road = r
	energy = 45.0 if night else 14.0
	for i in count:
		var l := SpotLight3D.new()
		l.spot_range = 30.0
		l.spot_angle = 64.0
		l.spot_attenuation = 1.1
		l.spot_angle_attenuation = 1.6
		l.light_specular = 1.0
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 140.0
		l.distance_fade_length = 40.0
		l.visible = false
		add_child(l)
		lights.append(l)

func update(player_s: float) -> void:
	if road == null:
		return
	# Lamps from just behind the rider forwards.
	var first := int(floor((player_s - 15.0) / Road.LAMP_SPACING))
	var want: Array[int] = []
	for k in range(first, first + lights.size()):
		if k >= 0:
			want.append(k)
	# Free lights whose lamp fell out of range.
	for k in _assigned.keys():
		if not want.has(k):
			(_assigned[k] as SpotLight3D).visible = false
			_assigned.erase(k)
	for k in want:
		if _assigned.has(k):
			continue
		for l in lights:
			if not l.visible:
				var info := road.lamp_info(k)
				l.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), info[0] + Vector3.DOWN * 0.15)
				l.light_color = info[1]
				l.light_energy = energy
				l.visible = true
				_assigned[k] = l
				break
