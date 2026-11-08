extends RefCounted
# Riskfate first original heroine: generated low-poly mesh for the EXISTING
# Ninja Skeleton3D/Skin. This is authored geometry, not a recolored Ninja mesh.
# Prototype V1 — pending artistic approval and animation inspection on device.

const COLORS := [
	"79503f", # 0 warm dark skin
	"a26b54", # 1 skin highlight
	"56362f", # 2 skin shadow
	"191923", # 3 suit shadow
	"2c2938", # 4 graphite suit
	"51346c", # 5 dark violet
	"7950a0", # 6 brighter violet
	"e8e2f3", # 7 silver-white hair
	"b9b2d0", # 8 silver hair shade
	"fcf9ff", # 9 hair highlight
	"9d9cab", # 10 metal
	"52515f", # 11 metal shadow
	"ad80f1", # 12 violet eyes
	"e7dce4", # 13 eye white
	"9f6467", # 14 lips
	"101017"  # 15 darkest accents
]

# Index in existing Ninja_Female.gltf skin.joints. Never change the live rig.
const BODY := 2
const HIPS := 3
const ABDOMEN := 4
const TORSO := 5
const NECK := 6
const HEAD := 7
const SHOULDER_L := 8
const UPPER_ARM_L := 9
const LOWER_ARM_L := 10
const FIST_L := 11
const SHOULDER_R := 12
const UPPER_ARM_R := 13
const LOWER_ARM_R := 14
const FIST_R := 15
const UPPER_LEG_L := 16
const LOWER_LEG_L := 17
const UPPER_LEG_R := 18
const LOWER_LEG_R := 19
const FOOT_L := 1
const FOOT_R := 21

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()


func build_mesh() -> ArrayMesh:
	_build_body()
	_build_legs_and_boots()
	_build_arms()
	_build_head_and_face()
	_build_hair()
	_build_equipment()

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Palette texture is generated once. One material/surface for the entire hero.
	var palette := Image.create(COLORS.size(), 1, false, Image.FORMAT_RGBA8)
	for i in range(COLORS.size()):
		palette.set_pixel(i, 0, Color.html(COLORS[i]))
	var material := StandardMaterial3D.new()
	material.resource_name = "Riskfate Assassin V1 — opaque palette"
	material.albedo_texture = ImageTexture.create_from_image(palette)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.81
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.surface_set_material(0, material)
	mesh.resource_name = "Riskfate Assassin V1 (rigged, low-poly)"
	return mesh


func _skin(p: Vector3, fixed_joint: int) -> Array:
	if fixed_joint >= 0:
		return [fixed_joint, fixed_joint, 1.0]
	var x := absf(p.x)
	# In the source mesh, arms are in a horizontal bind pose even though
	# the armature preview appears animated. Geometry is authored in bind space.
	if x > 0.44 and p.y > 1.56 and p.y < 2.15:
		var shoulder := SHOULDER_L if p.x > 0.0 else SHOULDER_R
		var upper := UPPER_ARM_L if p.x > 0.0 else UPPER_ARM_R
		var lower := LOWER_ARM_L if p.x > 0.0 else LOWER_ARM_R
		var fist := FIST_L if p.x > 0.0 else FIST_R
		if x < 0.54:
			return [shoulder, upper, clampf((x - 0.43) / 0.13, 0.0, 1.0)]
		if x < 0.88:
			return [upper, lower, clampf((x - 0.78) / 0.22, 0.0, 1.0)]
		if x < 1.32:
			return [lower, fist, clampf((x - 1.22) / 0.18, 0.0, 1.0)]
		return [fist, fist, 1.0]
	if p.y > 2.22:
		return [HEAD, HEAD, 1.0]
	if p.y > 2.04:
		return [NECK, HEAD, clampf((p.y - 2.04) / 0.18, 0.0, 1.0)]
	if p.y < 1.24 and x > 0.09:
		var upper_leg := UPPER_LEG_L if p.x > 0.0 else UPPER_LEG_R
		var lower_leg := LOWER_LEG_L if p.x > 0.0 else LOWER_LEG_R
		var foot := FOOT_L if p.x > 0.0 else FOOT_R
		if p.y < 0.105:
			return [foot, lower_leg, clampf((p.y - 0.055) / 0.08, 0.0, 1.0)]
		if p.y < 0.51:
			return [lower_leg, lower_leg, 1.0]
		if p.y < 0.69:
			return [lower_leg, upper_leg, clampf((p.y - 0.51) / 0.18, 0.0, 1.0)]
		if p.y < 1.07:
			return [upper_leg, upper_leg, 1.0]
		return [upper_leg, HIPS, clampf((p.y - 1.07) / 0.17, 0.0, 1.0)]
	if p.y < 1.22:
		return [BODY, HIPS, clampf((p.y - 0.94) / 0.28, 0.0, 1.0)]
	if p.y < 1.54:
		return [HIPS, ABDOMEN, clampf((p.y - 1.22) / 0.32, 0.0, 1.0)]
	if p.y < 1.87:
		return [ABDOMEN, TORSO, clampf((p.y - 1.54) / 0.33, 0.0, 1.0)]
	return [TORSO, NECK, clampf((p.y - 2.01) / 0.19, 0.0, 1.0)]


func _add_vertex(p: Vector3, n: Vector3, color_index: int, fixed_joint: int = -1) -> void:
	vertices.append(p)
	normals.append(n)
	uvs.append(Vector2((float(color_index) + 0.5) / float(COLORS.size()), 0.5))
	var sw := _skin(p, fixed_joint)
	var blend: float = float(sw[2])
	bones.append(int(sw[0]))
	bones.append(int(sw[1]))
	bones.append(0)
	bones.append(0)
	weights.append(1.0 - blend)
	weights.append(blend)
	weights.append(0.0)
	weights.append(0.0)


func _tri(a: Vector3, b: Vector3, c: Vector3, color_index: int, joint: int = -1) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.00000001:
		return
	normal = normal.normalized()
	_add_vertex(a, normal, color_index, joint)
	_add_vertex(b, normal, color_index, joint)
	_add_vertex(c, normal, color_index, joint)


func _quad_out(a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3, color_index: int, joint: int = -1) -> void:
	var normal := (b - a).cross(c - a)
	if normal.dot((a + b + c + d) * 0.25 - center) < 0.0:
		_tri(a, c, b, color_index, joint)
		_tri(a, d, c, color_index, joint)
	else:
		_tri(a, b, c, color_index, joint)
		_tri(a, c, d, color_index, joint)


# Ring: [height, radius_x, radius_z, center_x, center_z].
func _loft_y(rings: Array, sides: int, color_index: int, joint: int = -1) -> void:
	for row in range(rings.size() - 1):
		var lower: Array = rings[row]
		var upper: Array = rings[row + 1]
		for i in range(sides):
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var p0 := Vector3(float(lower[3]) + cos(a0) * float(lower[1]), float(lower[0]), float(lower[4]) + sin(a0) * float(lower[2]))
			var p1 := Vector3(float(lower[3]) + cos(a1) * float(lower[1]), float(lower[0]), float(lower[4]) + sin(a1) * float(lower[2]))
			var q0 := Vector3(float(upper[3]) + cos(a0) * float(upper[1]), float(upper[0]), float(upper[4]) + sin(a0) * float(upper[2]))
			var q1 := Vector3(float(upper[3]) + cos(a1) * float(upper[1]), float(upper[0]), float(upper[4]) + sin(a1) * float(upper[2]))
			var axis := (Vector3(float(lower[3]), float(lower[0]), float(lower[4])) + Vector3(float(upper[3]), float(upper[0]), float(upper[4]))) * 0.5
			_quad_out(p0, q0, q1, p1, axis, color_index, joint)


# Ring: [x, radius_y, radius_z, center_y, center_z]. T-pose sleeves/arms.
func _loft_x(rings: Array, sides: int, color_index: int, joint: int = -1) -> void:
	for row in range(rings.size() - 1):
		var left: Array = rings[row]
		var right: Array = rings[row + 1]
		for i in range(sides):
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var p0 := Vector3(float(left[0]), float(left[3]) + cos(a0) * float(left[1]), float(left[4]) + sin(a0) * float(left[2]))
			var p1 := Vector3(float(left[0]), float(left[3]) + cos(a1) * float(left[1]), float(left[4]) + sin(a1) * float(left[2]))
			var q0 := Vector3(float(right[0]), float(right[3]) + cos(a0) * float(right[1]), float(right[4]) + sin(a0) * float(right[2]))
			var q1 := Vector3(float(right[0]), float(right[3]) + cos(a1) * float(right[1]), float(right[4]) + sin(a1) * float(right[2]))
			var axis := (Vector3(float(left[0]), float(left[3]), float(left[4])) + Vector3(float(right[0]), float(right[3]), float(right[4]))) * 0.5
			_quad_out(p0, p1, q1, q0, axis, color_index, joint)


func _ellipsoid(center: Vector3, radii: Vector3, color_index: int, joint: int = -1, sides: int = 12, layers: int = 7) -> void:
	var rings: Array = []
	for i in range(layers + 1):
		var angle := PI * float(i) / float(layers)
		var f := sin(angle)
		rings.append([center.y - radii.y * cos(angle), radii.x * f, radii.z * f, center.x, center.z])
	_loft_y(rings, sides, color_index, joint)


# Tapered 3D strand / strap following an arbitrary polyline.
func _tube(points: Array, radii: Array, color_index: int, joint: int = -1, sides: int = 7) -> void:
	if points.size() < 2:
		return
	var ring_vertices: Array = []
	for i in range(points.size()):
		var here: Vector3 = points[i]
		var before: Vector3 = points[maxi(0, i - 1)]
		var after: Vector3 = points[mini(points.size() - 1, i + 1)]
		var direction := (after - before).normalized()
		if direction.length_squared() < 0.000001:
			continue
		var guide := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.92 else Vector3.FORWARD
		var right := direction.cross(guide).normalized()
		var up := direction.cross(right).normalized()
		var ring: Array = []
		for k in range(sides):
			var phi := TAU * float(k) / float(sides)
			ring.append(here + (right * cos(phi) + up * sin(phi)) * float(radii[i]))
		ring_vertices.append(ring)
	for i in range(ring_vertices.size() - 1):
		var r0: Array = ring_vertices[i]
		var r1: Array = ring_vertices[i + 1]
		var mid: Vector3 = (points[i] + points[i + 1]) * 0.5
		for k in range(sides):
			var t := (k + 1) % sides
			_quad_out(r0[k], r0[t], r1[t], r1[k], mid, color_index, joint)


func _build_body() -> void:
	# Natural waist and shoulder outline. Body is opaque beneath garments.
	_loft_y([
		[1.09, 0.315, 0.225, 0.0, -0.015],
		[1.22, 0.340, 0.225, 0.0, 0.0],
		[1.33, 0.285, 0.180, 0.0, 0.0],
		[1.44, 0.248, 0.165, 0.0, 0.005],
		[1.56, 0.280, 0.175, 0.0, 0.003],
		[1.68, 0.353, 0.214, 0.0, 0.012],
		[1.79, 0.396, 0.226, 0.0, 0.008],
		[1.94, 0.389, 0.205, 0.0, 0.0],
		[2.04, 0.165, 0.137, 0.0, 0.004],
		[2.15, 0.116, 0.108, 0.0, 0.004]
	], 18, 0)

	# High-waist fitted combat pants with exposed narrow midriff.
	_loft_y([
		[1.085, 0.324, 0.234, 0.0, -0.012],
		[1.18, 0.351, 0.237, 0.0, 0.0],
		[1.31, 0.294, 0.195, 0.0, 0.003]
	], 18, 4)
	# Fitted cropped armored tunic with a shaped waist/chest.
	_loft_y([
		[1.565, 0.287, 0.185, 0.0, 0.004],
		[1.655, 0.356, 0.239, 0.0, 0.015],
		[1.79, 0.414, 0.242, 0.0, 0.009],
		[1.935, 0.405, 0.214, 0.0, 0.0],
		[2.045, 0.174, 0.148, 0.0, 0.005]
	], 18, 4)
	# Anatomical volume stays subtle in the stylized combat top.
	for side in [-1.0, 1.0]:
		_ellipsoid(Vector3(side * 0.168, 1.731, 0.215), Vector3(0.172, 0.153, 0.091), 3, -1, 12, 6)
		_tube([Vector3(side * 0.35, 1.80, 0.206), Vector3(side * 0.27, 1.97, 0.18), Vector3(side * 0.11, 2.075, 0.095)], [0.032, 0.028, 0.025], 5, -1, 7)
		_ellipsoid(Vector3(side * 0.42, 1.89, 0.015), Vector3(0.111, 0.108, 0.159), 3, -1, 12, 6)
	# Torso seams, subtle purple underbust piping and center armor.
	_tube([Vector3(-0.345, 1.612, 0.158), Vector3(0.0, 1.599, 0.225), Vector3(0.345, 1.612, 0.158)], [0.017, 0.024, 0.017], 6)
	_tube([Vector3(0.0, 1.612, 0.225), Vector3(0.0, 1.81, 0.247), Vector3(0.0, 1.97, 0.172)], [0.017, 0.017, 0.012], 5)


func _build_legs_and_boots() -> void:
	for side in [-1.0, 1.0]:
		var x: float = 0.257 * side
		# Athletic thighs; knees and calves align with the legacy T-pose bind.
		_loft_y([
			[0.100, 0.088, 0.094, x, -0.012],
			[0.23, 0.124, 0.133, x, -0.008],
			[0.39, 0.143, 0.142, x, -0.017],
			[0.53, 0.129, 0.132, x, -0.013],
			[0.67, 0.156, 0.153, x, 0.0],
			[0.86, 0.189, 0.191, x, 0.0],
			[1.06, 0.196, 0.203, x, -0.004],
			[1.19, 0.182, 0.189, x, -0.003]
		], 12, 3)
		# Flexible purple thigh band and knee protection.
		_loft_y([[0.88, 0.199, 0.201, x, 0.0], [0.958, 0.202, 0.207, x, 0.0]], 12, 5)
		_loft_y([[0.462, 0.135, 0.137, x, -0.015], [0.57, 0.143, 0.151, x, -0.011]], 12, 11)
		_ellipsoid(Vector3(x, 0.511, 0.135), Vector3(0.095, 0.109, 0.044), 10, -1, 10, 5)
		# Closed shin guards follow the lower leg, not the entire animation.
		_loft_y([
			[0.095, 0.105, 0.113, x, -0.012],
			[0.22, 0.134, 0.146, x, -0.008],
			[0.381, 0.153, 0.157, x, -0.017]
		], 12, 4)
		_tube([Vector3(x, 0.155, 0.124), Vector3(x, 0.325, 0.15), Vector3(x, 0.425, 0.137)], [0.018, 0.021, 0.012], 10)
		# Soft-heeled boot and pointed, forward-facing toe.
		_ellipsoid(Vector3(x, 0.102, 0.102), Vector3(0.128, 0.097, 0.218), 3, -1, 12, 6)
		_ellipsoid(Vector3(x, 0.066, 0.245), Vector3(0.129, 0.060, 0.135), 4, -1, 10, 5)
		_loft_y([[0.120, 0.113, 0.121, x, -0.008], [0.208, 0.128, 0.137, x, -0.008]], 12, 11)


func _build_arms() -> void:
	for side in [-1.0, 1.0]:
		# One continuous uncovered upper-arm silhouette in the bind T-pose.
		_loft_x([
			[side * 0.350, 0.151, 0.160, 1.865, 0.0],
			[side * 0.510, 0.162, 0.165, 1.871, 0.0],
			[side * 0.710, 0.135, 0.139, 1.865, 0.0],
			[side * 0.905, 0.111, 0.116, 1.855, 0.0],
			[side * 1.151, 0.091, 0.099, 1.856, 0.002],
			[side * 1.355, 0.079, 0.089, 1.860, 0.0],
			[side * 1.524, 0.082, 0.083, 1.859, 0.0]
		], 10, 0)
		# Sleeve cuff at shoulder, half-glove and silver-edged bracer.
		_loft_x([
			[side * 0.383, 0.162, 0.171, 1.868, 0.0],
			[side * 0.479, 0.170, 0.176, 1.869, 0.0]
		], 10, 4)
		_loft_x([
			[side * 0.919, 0.119, 0.121, 1.854, 0.0],
			[side * 1.26, 0.098, 0.106, 1.857, 0.0]
		], 10, 3)
		for x in [1.00, 1.24]:
			_loft_x([
				[side * (x - 0.018), 0.121 - (x - 1.0) * 0.07, 0.123 - (x - 1.0) * 0.06, 1.856, 0.0],
				[side * (x + 0.018), 0.121 - (x - 1.0) * 0.07, 0.123 - (x - 1.0) * 0.06, 1.856, 0.0]
			], 10, 10)
		_loft_x([
			[side * 1.32, 0.087, 0.094, 1.860, 0.0],
			[side * 1.49, 0.101, 0.099, 1.859, 0.0],
			[side * 1.552, 0.035, 0.040, 1.860, 0.0]
		], 10, 3)
		# Dark plum fingerless cuff.
		_loft_x([[side * 1.344, 0.098, 0.103, 1.858, 0.0], [side * 1.383, 0.104, 0.108, 1.857, 0.0]], 10, 5)


func _build_head_and_face() -> void:
	# A smaller human-like head replaces the large source Ninja proportions.
	_loft_y([
		[2.166, 0.047, 0.054, 0.0, 0.013],
		[2.220, 0.154, 0.150, 0.0, 0.006],
		[2.302, 0.216, 0.209, 0.0, -0.005],
		[2.419, 0.256, 0.243, 0.0, -0.003],
		[2.564, 0.269, 0.251, 0.0, 0.0],
		[2.694, 0.244, 0.234, 0.0, -0.002],
		[2.796, 0.174, 0.183, 0.0, -0.009],
		[2.847, 0.083, 0.106, 0.0, -0.016],
		[2.864, 0.01, 0.02, 0.0, -0.017]
	], 20, 0, HEAD)
	# Muzzle/nose, cheek shades, eyebrows and readable violet irises.
	_ellipsoid(Vector3(0.0, 2.433, 0.252), Vector3(0.046, 0.079, 0.073), 1, HEAD, 10, 6)
	_ellipsoid(Vector3(0.0, 2.346, 0.248), Vector3(0.087, 0.019, 0.025), 14, HEAD, 10, 5)
	for side in [-1.0, 1.0]:
		_ellipsoid(Vector3(side * 0.260, 2.478, 0.018), Vector3(0.041, 0.087, 0.047), 0, HEAD, 9, 5)
		_ellipsoid(Vector3(side * 0.110, 2.573, 0.253), Vector3(0.076, 0.029, 0.021), 13, HEAD, 12, 5)
		_ellipsoid(Vector3(side * 0.110, 2.572, 0.272), Vector3(0.030, 0.028, 0.012), 12, HEAD, 10, 5)
		_ellipsoid(Vector3(side * 0.111, 2.574, 0.280), Vector3(0.015, 0.023, 0.010), 15, HEAD, 10, 5)
		_tube([Vector3(side * 0.038, 2.642, 0.240), Vector3(side * 0.116, 2.658, 0.256), Vector3(side * 0.186, 2.636, 0.212)], [0.014, 0.017, 0.013], 15, HEAD, 6)
		# Small violet tattoo near each eye; restrained, not excessive.
		_tube([Vector3(side * 0.201, 2.555, 0.166), Vector3(side * 0.225, 2.510, 0.149)], [0.012, 0.005], 6, HEAD, 5)


func _build_hair() -> void:
	# Opaque silver-white cap; thin sweeping locks keep the silhouette bright
	# while spending a fraction of the current Ninja hair's triangle budget.
	_loft_y([
		[2.681, 0.226, 0.226, 0.0, -0.019],
		[2.750, 0.257, 0.244, 0.0, -0.020],
		[2.837, 0.238, 0.228, 0.0, -0.020],
		[2.913, 0.179, 0.178, 0.0, -0.020],
		[2.956, 0.073, 0.088, 0.0, -0.022],
		[2.964, 0.001, 0.001, 0.0, -0.022]
	], 18, 8, HEAD)
	# White bangs parted above the eyes with individual sculpted strands.
	for i in range(9):
		var side := -1.0 if i < 5 else 1.0
		var offset := float(i % 5) / 4.0
		var x := side * (0.025 + 0.170 * offset)
		var tip_y := 2.585 + 0.070 * offset
		_tube([
			Vector3(side * 0.035, 2.947, 0.012),
			Vector3(x * 0.72, 2.816, 0.201),
			Vector3(x, 2.680, 0.262),
			Vector3(x + side * 0.020, tip_y, 0.234)
		], [0.043, 0.058, 0.032, 0.004], 7 if i % 3 != 0 else 9, HEAD, 6)
	# Two longer framing locks, lighter at their tips.
	for side in [-1.0, 1.0]:
		_tube([
			Vector3(side * 0.199, 2.862, 0.080),
			Vector3(side * 0.275, 2.646, 0.115),
			Vector3(side * 0.268, 2.430, 0.171),
			Vector3(side * 0.227, 2.225, 0.114)
		], [0.079, 0.077, 0.039, 0.004], 7, HEAD, 8)
	# High ponytail: broad silhouette made from low-poly tapered strands.
	_ellipsoid(Vector3(0.02, 2.906, -0.248), Vector3(0.133, 0.112, 0.112), 9, HEAD, 12, 6)
	_tube([Vector3(-0.092, 2.906, -0.246), Vector3(0.120, 2.907, -0.246)], [0.048, 0.047], 5, HEAD, 9)
	for i in range(13):
		var t := (float(i) - 6.0) / 6.0
		var shift := t * 0.130
		var curl := sin(float(i) * 1.71) * 0.060
		var tail_y := 2.205 + 0.17 * absf(t)
		_tube([
			Vector3(shift * 0.30, 2.923, -0.260),
			Vector3(shift * 0.75 + curl * 0.4, 3.041, -0.409),
			Vector3(shift + curl, 2.865, -0.605),
			Vector3(shift * 1.3 - curl * 0.7, 2.563, -0.642),
			Vector3(shift * 1.8 + curl * 0.7, tail_y, -0.591)
		], [0.049, 0.078, 0.069, 0.044, 0.002], 7 if i % 3 != 0 else 8, HEAD, 7)


func _build_equipment() -> void:
	# Neck scarf and lightweight back collar.
	_loft_y([
		[2.022, 0.154, 0.146, 0.0, -0.003],
		[2.129, 0.172, 0.163, 0.0, -0.005],
		[2.199, 0.122, 0.121, 0.0, -0.005]
	], 14, 5)
	# Belt and low-profile front buckle.
	_loft_y([[1.213, 0.352, 0.241, 0.0, 0.0], [1.284, 0.314, 0.210, 0.0, 0.0]], 18, 3)
	_ellipsoid(Vector3(0.0, 1.244, 0.242), Vector3(0.082, 0.041, 0.024), 10, HIPS, 10, 4)
	_ellipsoid(Vector3(0.0, 1.244, 0.259), Vector3(0.051, 0.024, 0.018), 15, HIPS, 10, 4)
	# Short purple sash; no cloth simulation and no long cape.
	_quad_out(
		Vector3(-0.033, 1.225, 0.244), Vector3(0.134, 1.225, 0.224),
		Vector3(0.172, 0.738, 0.244), Vector3(-0.080, 0.839, 0.259),
		Vector3(0.0, 0.93, 0.0), 5, HIPS
	)
	_quad_out(
		Vector3(-0.025, 1.226, 0.248), Vector3(0.015, 1.222, 0.255),
		Vector3(-0.040, 0.865, 0.268), Vector3(-0.130, 0.901, 0.245),
		Vector3(0.0, 0.93, 0.0), 6, HIPS
	)
	# Small hip pouches and sheathed knives. No separate combat equipment logic.
	for side in [-1.0, 1.0]:
		var j := UPPER_LEG_L if side > 0.0 else UPPER_LEG_R
		_ellipsoid(Vector3(side * 0.377, 1.050, 0.040), Vector3(0.086, 0.131, 0.093), 3, j, 10, 5)
		_tube([
			Vector3(side * 0.425, 1.179, 0.088),
			Vector3(side * 0.438, 0.977, 0.116),
			Vector3(side * 0.450, 0.704, 0.097)
		], [0.062, 0.045, 0.006], 11, j, 7)
		_tube([
			Vector3(side * 0.427, 1.194, 0.103),
			Vector3(side * 0.428, 1.255, 0.107)
		], [0.044, 0.040], 10, j, 7)
