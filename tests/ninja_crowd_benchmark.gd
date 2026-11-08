extends RefCounted
# Explicit manual render/animation stress test, never active during normal play.
# Not a server load test; does not create physics bodies or network traffic.
const ANIM := preload("res://characters/player/animation_builder.gd")
const COUNTS := [0, 10, 30, 60, 100]

var root: Node3D
var actors: Array[Node3D] = []
var mesh_nodes: Array[MeshInstance3D] = []
var count_index := 0

func initialize(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "NinjaCrowdBenchmark"
	parent.add_child(root)

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null

func set_count(target: int, scene: PackedScene, mesh: Mesh) -> void:
	if root == null or mesh == null or scene == null:
		return
	target = clampi(target, 0, 100)
	while actors.size() > target:
		var actor: Node3D = actors.pop_back()
		mesh_nodes.pop_back()
		root.remove_child(actor)
		actor.queue_free()
	while actors.size() < target:
		var index := actors.size()
		var actor := scene.instantiate() as Node3D
		if actor == null:
			push_error("Ninja benchmark actor is not Node3D")
			return
		root.add_child(actor)
		# 10 x 10 grid spanning 24.3 m; no physical collisions.
		var row := index / 10
		var column := index % 10
		actor.position = Vector3((float(column) - 4.5) * 2.7, 0.0, (float(row) - 4.5) * 2.7)
		var skinned := _find_mesh(actor)
		if skinned == null:
			actor.queue_free()
			push_error("Ninja benchmark mesh missing")
			return
		skinned.mesh = mesh
		var player := ANIM.find_animation_player(actor)
		if player != null:
			ANIM.configure_animation_loops(player)
			var run_name := ANIM.find_clip(player, "Run")
			if run_name != "":
				player.play(run_name)
				player.seek(fmod(float(index) * 0.067, player.current_animation_length), true)
		actors.append(actor)
		mesh_nodes.append(skinned)

func set_mesh(mesh: Mesh) -> void:
	if mesh == null:
		return
	for skinned in mesh_nodes:
		skinned.mesh = mesh

func clear() -> void:
	count_index = 0
	if root == null:
		return
	for actor in actors:
		root.remove_child(actor)
		actor.queue_free()
	actors.clear()
	mesh_nodes.clear()
