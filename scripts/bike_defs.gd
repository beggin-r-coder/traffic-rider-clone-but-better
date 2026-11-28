class_name BikeDefs
## Selectable motorcycles: model normalisation, part names, finishes, rider contact points and
## performance. Contact points are in bike space (-Z forward, +X right, origin on the ground midway
## between the tyre contact patches) and were measured on each mesh from orthographic renders.
## Only the right-hand side is listed; the left side is mirrored.

const LIST := [
	{
		"id": "r1",
		"name": "Yamaha YZF-R1",
		"price": 0,
		"blurb": "Crossplane inline-4. The balanced all-rounder.",
		# performance
		"mass": 285.0, "power": 128000.0, "cda": 0.29, "redline": 14000.0, "idle": 1300.0,
		"gear_top": [41.0, 53.0, 62.0, 70.0, 77.5, 84.5], "max_lean": 54.0, "handling": 1.0,
		"audio_rpm": 1.0,
		# rider contact points
		"grip_in": Vector3(0.228, 0.959, -0.430), "grip_out": Vector3(0.348, 0.921, -0.363),
		"lever_in": Vector3(0.255, 0.948, -0.490), "lever_out": Vector3(0.368, 0.904, -0.471),
		"lever_pivot": Vector3(0.238, 0.952, -0.494),
		"peg": Vector3(0.245, 0.455, 0.340), "seat": Vector3(0.0, 0.925, 0.35),
		"mirror_cam": Vector3(0.0, 1.22, -0.25),
		"exhaust_mats": ["Muffler", "Muffler-Aluminum"],
		"disc_mats": ["Brake_Discs"],
	},
	{
		"id": "h2",
		"name": "Kawasaki Ninja H2",
		"price": 18000,
		"blurb": "Supercharged 998 cc. Brutal top speed, heavy in the turns.",
		"mass": 318.0, "power": 158000.0, "cda": 0.30, "redline": 12500.0, "idle": 1150.0,
		"gear_top": [45.0, 59.0, 69.0, 78.0, 86.0, 93.0], "max_lean": 52.0, "handling": 0.9,
		"audio_rpm": 1.06,
		"model": "res://assets/bikes/h2/h2.fbx",
		"rot_y": -90.0, "scale": 0.82, "offset": Vector3(-0.051, -0.065, 0.0515),
		"front_wheel": ["Mesh_0009_rip", "Mesh_0006_rip", "Mesh_0014_rip"],
		"rear_wheel": ["Mesh_0010_rip", "Mesh_0007_rip", "Mesh_0017_rip"],
		"hide": ["Mesh_0153_rip", "Mesh_0162_rip"],
		"paint_mats": ["Vật Liệu.001"], "paint_mode": "solid", "factory_color": Color(0.07, 0.075, 0.08),
		"glass_mats": ["Vật Liệu.015"],
		"mirror_meshes": ["Mesh_0005_rip"],
		# [metallic, roughness, clearcoat, (optional albedo)]
		"finishes": {
			"Vật Liệu.005": [0.0, 0.82, 0.0],                     # tyres
			"Vật Liệu.004": [0.85, 0.22, 0.6, Color(0.55, 0.56, 0.58)],  # rims
			"Vật Liệu.009": [1.0, 0.3, 0.0],                      # brake discs
			"Vật Liệu.020": [1.0, 0.3, 0.0],
			"Vật Liệu.006": [0.25, 0.18, 1.0],                    # green trellis frame
			"Vật Liệu.011": [0.6, 0.38, 0.0],                     # engine
			"Vật Liệu": [1.0, 0.16, 0.0, Color(0.78, 0.78, 0.8)],  # silencer
			"Vật Liệu.002": [1.0, 0.12, 0.0],                     # pipes / chrome
			"Vật Liệu.007": [0.9, 0.25, 0.0],
			"Vật Liệu.018": [0.8, 0.3, 0.0],
			"Vật Liệu.012": [0.1, 0.35, 0.6],
			"Vật Liệu.003": [0.2, 0.5, 0.0],
			"Vật Liệu.016": [0.2, 0.4, 0.5],
			"Vật Liệu.017": [0.3, 0.4, 0.0],
			"Vật Liệu.010": [0.3, 0.4, 0.0],
			"Vật Liệu.013": [0.2, 0.4, 0.0],
			"Vật Liệu.019": [0.6, 0.3, 0.0],
			"Vật Liệu.021": [0.7, 0.25, 0.0],
			"Vật Liệu.008": [0.0, 0.2, 0.8],                      # amber indicator lenses
		},
		"lever_box_min": Vector3(0.185, 0.86, -0.50), "lever_box_max": Vector3(0.39, 0.935, -0.44),
		"grip_in": Vector3(0.215, 0.896, -0.414), "grip_out": Vector3(0.325, 0.862, -0.362),
		"lever_in": Vector3(0.205, 0.905, -0.470), "lever_out": Vector3(0.355, 0.878, -0.455),
		"lever_pivot": Vector3(0.185, 0.908, -0.475),
		"peg": Vector3(0.235, 0.405, 0.265), "seat": Vector3(0.0, 0.84, 0.35),
		"dash": {"center": Vector3(0.0, 0.985, -0.55), "size": Vector2(0.17, 0.066), "tilt": 52.0},
		"mirror_cam": Vector3(0.0, 1.13, -0.25),
		"exhaust_meshes": ["Mesh_0001_rip"],
		"disc_meshes": ["Mesh_0014_rip"],
	},
	{
		"id": "zx6r",
		"name": "Kawasaki Ninja ZX-6R",
		"price": 9000,
		"blurb": "Screaming 636 cc middleweight. Light and razor sharp.",
		"mass": 272.0, "power": 92000.0, "cda": 0.28, "redline": 16000.0, "idle": 1400.0,
		"gear_top": [37.0, 48.0, 56.0, 63.0, 69.0, 74.0], "max_lean": 56.0, "handling": 1.12,
		"audio_rpm": 1.12,
		"model": "res://assets/bikes/zx6r/Kawasaki.fbx",
		"rot_y": 180.0, "scale": 0.435, "offset": Vector3(0.0, -0.5435, -0.0055),
		"front_wheel": ["Front Wheel", "Front Rim", "Brakes", "Brakes Too"],
		"rear_wheel": ["Rear Wheel", "Rear Rim", "Rear Brakes", "Rear Brakes Too_", "Rear Main Brakes", "Cylinder"],
		"hide": ["Radiator"],
		"textures": "res://assets/bikes/zx6r/tex/",   # <Material>_albedo / _orm / _normal
		"paint_mats": ["Panels"], "paint_mode": "hue", "paint_hue": 0.33,
		"glass_meshes": ["Windshield", "Headlight Cover", "Taillight Cover"],
		"taillight_meshes": ["Taillight"],
		"headlight_meshes": ["Headlight", "Front Lights"],
		"mirror_meshes": ["Side Mirror"],
		"lever_meshes": ["Steering Wheel"],
		"lever_box_min": Vector3(0.165, 0.84, -0.50), "lever_box_max": Vector3(0.345, 0.91, -0.435),
		"grip_in": Vector3(0.200, 0.882, -0.430), "grip_out": Vector3(0.305, 0.850, -0.372),
		"lever_in": Vector3(0.190, 0.880, -0.475), "lever_out": Vector3(0.310, 0.860, -0.449),
		"lever_pivot": Vector3(0.170, 0.884, -0.478),
		"peg": Vector3(0.225, 0.37, 0.29), "seat": Vector3(0.0, 0.868, 0.37),
		"dash": {"decal_mesh": "Dashboard_001", "style": "zx6r"},
		"mirror_cam": Vector3(0.0, 1.12, -0.25),
		"exhaust_meshes": ["Exhaust"],
		"disc_meshes": ["Brakes Too"],
	},
]

static func count() -> int:
	return LIST.size()

static func get_def(i: int) -> Dictionary:
	return LIST[clampi(i, 0, LIST.size() - 1)]

static func current() -> Dictionary:
	return get_def(Game.bike)
