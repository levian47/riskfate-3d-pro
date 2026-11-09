extends RefCounted
# Retargets CC0 Quaternius UAL2 motion from its 65-bone skeleton to the
# approved 103-bone VRoid skeleton. Only selected upper-body channels are
# transferred; locomotion and lower-body/root motion stay with the game.
const SOURCE := preload("res://assets/animations/ual2_selected_combat.glb")
const SAMPLE_FPS := 30.0
const BONE_MAP := {
	"spine_01": "J_Bip_C_Spine",
	"spine_02": "J_Bip_C_Chest",
	"spine_03": "J_Bip_C_UpperChest",
	"clavicle_l": "J_Bip_L_Shoulder",
	"upperarm_l": "J_Bip_L_UpperArm",
	"lowerarm_l": "J_Bip_L_LowerArm",
	"hand_l": "J_Bip_L_Hand",
	"clavicle_r": "J_Bip_R_Shoulder",
	"upperarm_r": "J_Bip_R_UpperArm",
	"lowerarm_r": "J_Bip_R_LowerArm",
	"hand_r": "J_Bip_R_Hand",
}

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

static func _find_animator(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animator(child)
		if found != null:
			return found
	return null

static func _find_clip(player: AnimationPlayer, short_name: String) -> String:
	for name in player.get_animation_list():
		var key := String(name)
		if key == short_name or key.ends_with("/" + short_name):
			return key
	return ""

static func _rotation_paths(clip: Animation) -> Dictionary:
	var paths := {}
	for i in range(clip.get_track_count()):
		if clip.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var path := clip.track_get_path(i)
		if path.get_subname_count() < 1:
			continue
		paths[String(path.get_subname(path.get_subname_count() - 1))] = {"path": path, "index": i}
	return paths

static func build(clip_name: String, target_reference: Animation, target_skeleton: Skeleton3D) -> Animation:
	if target_reference == null or target_skeleton == null:
		push_error("UAL2 retarget: VRoid reference or skeleton missing")
		return null
	var instance := SOURCE.instantiate()
	var source_skeleton := _find_skeleton(instance)
	var source_animator := _find_animator(instance)
	if source_skeleton == null or source_animator == null:
		push_error("UAL2 retarget: source skeleton/AnimationPlayer missing")
		instance.free()
		return null
	var source_name := _find_clip(source_animator, clip_name)
	if source_name.is_empty():
		push_error("UAL2 retarget: source clip missing: " + clip_name)
		instance.free()
		return null
	var source_clip := source_animator.get_animation(source_name)
	var source_paths := _rotation_paths(source_clip)
	var target_paths := _rotation_paths(target_reference)
	var result := Animation.new()
	result.length = source_clip.length
	result.loop_mode = Animation.LOOP_NONE
	var frame_count := maxi(2, ceili(result.length * SAMPLE_FPS) + 1)
	for source_bone in BONE_MAP:
		var target_bone: String = BONE_MAP[source_bone]
		if not source_paths.has(source_bone) or not target_paths.has(target_bone):
			push_error("UAL2 retarget: missing animation bone: %s -> %s; source keys=%s; target keys=%s" % [source_bone, target_bone, str(source_paths.keys()), str(target_paths.keys())])
			instance.free()
			return null
		var src_index := source_skeleton.find_bone(source_bone)
		var dst_index := target_skeleton.find_bone(target_bone)
		if src_index < 0 or dst_index < 0:
			push_error("UAL2 retarget: skeleton bone missing: %s -> %s" % [source_bone, target_bone])
			instance.free()
			return null
		var source_local_rest := source_skeleton.get_bone_rest(src_index).basis.get_rotation_quaternion()
		var source_world_rest := source_skeleton.get_bone_global_rest(src_index).basis.get_rotation_quaternion()
		var target_local_rest := target_skeleton.get_bone_rest(dst_index).basis.get_rotation_quaternion()
		var target_world_rest := target_skeleton.get_bone_global_rest(dst_index).basis.get_rotation_quaternion()
		# Convert motion from source bone-rest local axes into VRoid bone-rest
		# axes. Never rewrite either source rest pose or the VRoid skeleton.
		var source_to_target := (target_world_rest.inverse() * source_world_rest).normalized()
		var track := result.add_track(Animation.TYPE_ROTATION_3D)
		result.track_set_path(track, target_paths[target_bone]["path"])
		var source_track: int = source_paths[source_bone]["index"]
		for frame in range(frame_count):
			var sample_time := result.length * float(frame) / float(frame_count - 1)
			var pose: Quaternion = source_clip.rotation_track_interpolate(source_track, sample_time)
			var delta := (source_local_rest.inverse() * pose).normalized()
			var aligned_delta := (source_to_target * delta * source_to_target.inverse()).normalized()
			result.rotation_track_insert_key(track, sample_time, (target_local_rest * aligned_delta).normalized())
	instance.free()
	return result
