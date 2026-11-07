extends MeshInstance3D
# Optional runtime bone visualization for desktop and mobile inspection.
# It does not modify the imported skeleton or any animations.
var rig: Skeleton3D
var lines := ImmediateMesh.new()
var line_material := StandardMaterial3D.new()


func setup(source: Skeleton3D) -> void:
	rig = source
	mesh = lines
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	# Draw through the skinned mesh so bones remain readable on a phone.
	line_material.no_depth_test = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(_delta: float) -> void:
	if not visible or rig == null:
		return
	lines.clear_surfaces()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	for bone_index in range(rig.get_bone_count()):
		var bone_name := rig.get_bone_name(bone_index)
		# Foot.* and PoleTarget.* are detached rig controllers, not the
		# anatomical leg chain; showing their root links would be misleading.
		if bone_name.begins_with("Foot.") or bone_name.begins_with("PoleTarget.") or bone_name == "Bone":
			continue
		var position := rig.get_bone_global_pose(bone_index).origin
		var is_pelvis := bone_name == "Body_2" or bone_name == "Hips"
		var color := Color(1.0, 0.72, 0.18) if is_pelvis else Color(0.10, 1.0, 0.92)
		var parent_index := rig.get_bone_parent(bone_index)
		if parent_index >= 0:
			var parent_position := rig.get_bone_global_pose(parent_index).origin
			lines.surface_set_color(color)
			lines.surface_add_vertex(parent_position)
			lines.surface_add_vertex(position)
		# A small cross marks every joint (the lines mark the bone chains).
		var radius := 0.038 if is_pelvis else 0.024
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
			lines.surface_set_color(color)
			lines.surface_add_vertex(position - axis * radius)
			lines.surface_add_vertex(position + axis * radius)
	lines.surface_end()
