extends Node3D
# Single reusable world component; visuals are generated at runtime.
# Repeated scenery uses MultiMesh to keep the Web rendering cost low.

const WORLD_SIZE := 220.0
const TREE_COUNT := 150
const ROCK_COUNT := 110
const BUSH_COUNT := 95


func _ready() -> void:
	_build_ground()
	_build_landscape()
	_build_ruins()
	_build_camp()


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	add_child(ground)
	var shape := BoxShape3D.new()
	shape.size = Vector3(WORLD_SIZE, 1.0, WORLD_SIZE)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = -0.5
	ground.add_child(collision)
	_add_box(ground, shape.size, Vector3(0.0, -0.5, 0.0), Color("527c45"))
	# A subtle track helps the player orient without expensive terrain meshes.
	_add_box(self, Vector3(4.5, 0.035, 85.0), Vector3(0, 0.018, -1), Color("677257"))


func _build_landscape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 407207
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []

	for i in range(TREE_COUNT):
		var point := _landscape_point(rng, 19.0, 106.0)
		var size_factor := rng.randf_range(0.80, 1.45)
		var scale_basis := Basis().scaled(Vector3.ONE * size_factor)
		trunks.append(Transform3D(scale_basis, point + Vector3.UP * (1.05 * size_factor)))
		crowns.append(Transform3D(scale_basis, point + Vector3.UP * (3.3 * size_factor)))

	for i in range(ROCK_COUNT):
		var point := _landscape_point(rng, 12.0, 105.0)
		var scale_basis := Basis().scaled(Vector3(rng.randf_range(0.45, 1.35), rng.randf_range(0.35, 0.75), rng.randf_range(0.5, 1.4)))
		rocks.append(Transform3D(scale_basis, point + Vector3.UP * 0.35))

	for i in range(BUSH_COUNT):
		var point := _landscape_point(rng, 15.0, 104.0)
		var size_factor := rng.randf_range(0.50, 1.1)
		bushes.append(Transform3D(Basis().scaled(Vector3(size_factor, size_factor * 0.65, size_factor)), point + Vector3.UP * (0.45 * size_factor)))

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.27
	trunk_mesh.height = 2.1
	trunk_mesh.radial_segments = 6
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 1.25
	crown_mesh.height = 3.0
	crown_mesh.radial_segments = 7
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 4
	var bush_mesh := SphereMesh.new()
	bush_mesh.radius = 1.0
	bush_mesh.height = 2.0
	bush_mesh.radial_segments = 8
	bush_mesh.rings = 4

	_add_batch("TreeTrunks", trunk_mesh, trunks, Color("75513a"))
	_add_batch("TreeCrowns", crown_mesh, crowns, Color("3c8250"))
	_add_batch("ScatteredRocks", rock_mesh, rocks, Color("898e88"))
	_add_batch("Bushes", bush_mesh, bushes, Color("406a3a"))


func _landscape_point(rng: RandomNumberGenerator, min_radius: float, max_radius: float) -> Vector3:
	var candidate := Vector3.ZERO
	for attempt in range(20):
		var angle := rng.randf_range(0.0, TAU)
		var radius := sqrt(rng.randf_range(min_radius * min_radius, max_radius * max_radius))
		candidate = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if absf(candidate.x) < 6.0 and absf(candidate.z) < 47.0:
			continue
		if candidate.distance_to(Vector3(-30, 0, -22)) < 14.0:
			continue
		if candidate.distance_to(Vector3(28, 0, 26)) < 13.0:
			continue
		return candidate
	return candidate


func _add_batch(batch_name: String, geometry: Mesh, transforms: Array[Transform3D], color: Color) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = geometry
	batch.instance_count = transforms.size()
	for i in range(transforms.size()):
		batch.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = batch_name
	instance.multimesh = batch
	instance.material_override = _material(color)
	add_child(instance)


func _build_ruins() -> void:
	var stone := Color("929187")
	var worn := Color("777c78")
	# A small ruined gate and broken wall give the larger area a landmark.
	_add_solid_box(Vector3(-36, 1.45, -22), Vector3(1.8, 2.9, 1.8), stone)
	_add_solid_box(Vector3(-25, 1.45, -22), Vector3(1.8, 2.9, 1.8), stone)
	_add_solid_box(Vector3(-30.5, 3.2, -22), Vector3(12.0, 0.85, 1.8), worn)
	_add_solid_box(Vector3(-37.5, 0.8, -28), Vector3(4.5, 1.6, 1.0), stone)
	_add_solid_box(Vector3(-22.0, 0.6, -28), Vector3(3.5, 1.2, 1.0), worn)
	_add_solid_box(Vector3(-30.5, 0.3, -30), Vector3(5.5, 0.6, 3.0), stone)


func _build_camp() -> void:
	# Simple crates, pillars and fire pit, with physical obstacles to test jumping.
	var timber := Color("82613b")
	_add_solid_box(Vector3(25, 0.7, 25), Vector3(1.4, 1.4, 1.4), timber)
	_add_solid_box(Vector3(27, 0.55, 25), Vector3(1.1, 1.1, 1.1), timber)
	_add_solid_box(Vector3(23, 0.45, 27), Vector3(0.9, 0.9, 0.9), timber)
	_add_solid_box(Vector3(33, 1.4, 28), Vector3(1.0, 2.8, 1.0), timber)
	_add_solid_box(Vector3(33, 1.4, 21), Vector3(1.0, 2.8, 1.0), timber)
	_add_solid_box(Vector3(33, 2.9, 24.5), Vector3(2.5, 0.45, 9.0), timber)
	_add_box(self, Vector3(2.4, 0.3, 2.4), Vector3(28, 0.15, 31), Color("858580"))
	_add_box(self, Vector3(0.7, 0.9, 0.7), Vector3(28, 0.6, 31), Color("b56d33"))


func _add_solid_box(where: Vector3, dimensions: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = where
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_add_box(body, dimensions, Vector3.ZERO, color)


func _add_box(parent: Node3D, dimensions: Vector3, at: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	visual.material_override = _material(color)
	visual.position = at
	parent.add_child(visual)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat
