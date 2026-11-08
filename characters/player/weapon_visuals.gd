extends RefCounted
# Visual-only weapon testing. No damage, animation or equipment rules here.
# Each imported model is fitted to the same hand mount at runtime.
const WEAPONS := [
	{"name": "Sword I", "path": "res://assets/equipment/weapons/quaternius_sword_01.glb", "length": 1.35},
	{"name": "Sword II", "path": "res://assets/equipment/weapons/quaternius_sword_02.glb", "length": 1.25},
	{"name": "Dagger", "path": "res://assets/equipment/weapons/quaternius_dagger_01.glb", "length": 0.85},
	{"name": "Knife", "path": "res://assets/equipment/weapons/quaternius_knife_01.glb", "length": 0.72},
	{"name": "Cutlass", "path": "res://assets/equipment/weapons/quaternius_cutlass_01.fbx", "length": 1.20}
]

var mount: Node3D
var current_visual: Node3D
var current_index := -1


static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := find_skeleton(child)
		if found != null:
			return found
	return null


func initialize(model: Node) -> bool:
	var skeleton := find_skeleton(model)
	if skeleton == null:
		push_error("Weapon test: character skeleton missing")
		return false
	var right_hand := "Fist.R"
	if skeleton.find_bone(right_hand) < 0:
		right_hand = "J_Bip_R_Hand"
	if skeleton.find_bone(right_hand) < 0:
		push_error("Weapon test: no supported right-hand bone")
		return false
	var attachment := BoneAttachment3D.new()
	attachment.name = "SwordGrip"
	attachment.bone_name = right_hand
	skeleton.add_child(attachment)
	mount = Node3D.new()
	mount.name = "WeaponMount"
	attachment.add_child(mount)
	# This mount has the same identity transform as the approved test sword;
	# animation pose checks use it as a fixed reference, not the mesh tip.
	return equip(0)


func equip(index: int) -> bool:
	if mount == null or index < 0 or index >= WEAPONS.size():
		return false
	var specification: Dictionary = WEAPONS[index]
	var packed := load(String(specification["path"])) as PackedScene
	if packed == null:
		push_error("Weapon test: cannot load " + String(specification["path"]))
		return false
	var imported := packed.instantiate() as Node3D
	if imported == null:
		push_error("Weapon test: model root is not Node3D")
		return false
	# The holder is the stable grip/scale pivot. Rotate the imported child so
	# the bounds recomputed in holder-space reflect its actual orientation.
	var holder := Node3D.new()
	holder.name = "EquippedWeapon"
	mount.add_child(holder)
	holder.add_child(imported)
	var bounds := _bounds_in_root(holder)
	# FBX imports may use a different up-axis. Reorient only the candidate.
	if bounds.size.x > bounds.size.y * 1.25 and bounds.size.x > bounds.size.z:
		imported.rotation_degrees.z = 90.0
		bounds = _bounds_in_root(holder)
	elif bounds.size.z > bounds.size.y * 1.25 and bounds.size.z > bounds.size.x:
		imported.rotation_degrees.x = -90.0
		bounds = _bounds_in_root(holder)
	if bounds.size.y <= 0.001:
		mount.remove_child(holder)
		holder.queue_free()
		push_error("Weapon test: model has no usable mesh: " + String(specification["path"]))
		return false
	var factor := float(specification["length"]) / bounds.size.y
	# The Quaternius origin is near the crossguard; grip is halfway down
	# the portion of the handle below the origin.
	var grip_y := minf(0.0, bounds.position.y) * 0.5
	holder.scale = Vector3.ONE * factor
	holder.position = Vector3(
		-(bounds.position.x + bounds.size.x * 0.5) * factor,
		-grip_y * factor,
		-(bounds.position.z + bounds.size.z * 0.5) * factor
	)
	if current_visual != null:
		mount.remove_child(current_visual)
		current_visual.queue_free()
	current_visual = holder
	current_index = index
	return true


func cycle() -> bool:
	return equip((current_index + 1) % WEAPONS.size())


func selected_name() -> String:
	if current_index < 0:
		return "None"
	return String(WEAPONS[current_index]["name"])


func _bounds_in_root(root: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	var result := AABB()
	var has_point := false
	var inverse := root.global_transform.affine_inverse()
	for part in meshes:
		if part.mesh == null:
			continue
		var box := part.mesh.get_aabb()
		var to_root := inverse * part.global_transform
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					var point := to_root * (box.position + box.size * Vector3(x, y, z))
					if has_point:
						result = result.expand(point)
					else:
						result = AABB(point, Vector3.ZERO)
						has_point = true
	return result


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node)
	for child in node.get_children():
		_collect_meshes(child, output)
