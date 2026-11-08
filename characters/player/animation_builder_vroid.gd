extends RefCounted
# VRoid-only animation graph. The original Ninja graph and its approved
# animation resources are deliberately left untouched for regression testing.
# Original VRoid Walk/Jog are retained as rollback clips. New Walk/Run come
# from retargeted CC0 Quaternius motion; Idle, Jump, attack stay provisional.
# functional placeholders until purpose-made VRoid clips are available.

const QUATERNIUS_LOCOMOTION := preload("res://characters/player/locomotion_quaternius.gd")

const ARM_BONES := [
	"J_Bip_R_Shoulder", "J_Bip_R_UpperArm", "J_Bip_R_LowerArm",
	"J_Bip_R_Hand"
]

static func find_clip(animator: AnimationPlayer, short_name: String) -> String:
	if animator == null:
		return ""
	for name in animator.get_animation_list():
		var full_name := String(name)
		if full_name == short_name or full_name.ends_with("/" + short_name):
			return full_name
	return ""


static func configure_animation_loops(animator: AnimationPlayer) -> void:
	for name in animator.get_animation_list():
		var animation := animator.get_animation(name)
		var short_name := String(name).get_slice("/", String(name).get_slice_count("/") - 1)
		animation.loop_mode = Animation.LOOP_LINEAR if short_name in ["Walk", "Jog"] else Animation.LOOP_NONE


static func _hold_pose(source: Animation, sample_time: float, duration: float, looping: bool) -> Animation:
	# A single sampled pose avoids T-pose when the character is standing still
	# or airborne. Replace these placeholders with authored clips later.
	var result := Animation.new()
	result.length = duration
	result.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	for index in range(source.get_track_count()):
		var kind := source.track_get_type(index)
		if kind not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var track := result.add_track(kind)
		result.track_set_path(track, source.track_get_path(index))
		match kind:
			Animation.TYPE_ROTATION_3D:
				result.rotation_track_insert_key(track, 0.0, source.rotation_track_interpolate(index, sample_time))
			Animation.TYPE_POSITION_3D:
				result.position_track_insert_key(track, 0.0, source.position_track_interpolate(index, sample_time))
			Animation.TYPE_SCALE_3D:
				result.scale_track_insert_key(track, 0.0, source.scale_track_interpolate(index, sample_time))
	return result


static func _sword_swing(walk: Animation) -> Animation:
	var clip := Animation.new()
	clip.length = 1.0416666
	clip.loop_mode = Animation.LOOP_NONE
	# Only the weapon arm is animated; walking/jumping continue underneath.
	# This swing is not the previously approved Ninja/Mixamo sweeping clip.
	for index in range(walk.get_track_count()):
		if walk.track_get_type(index) != Animation.TYPE_ROTATION_3D:
			continue
		var path := walk.track_get_path(index)
		var bone := String(path.get_subname(path.get_subname_count() - 1)) if path.get_subname_count() > 0 else ""
		if bone not in ARM_BONES:
			continue
		var baseline := walk.rotation_track_interpolate(index, 0.15)
		var attack := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(attack, path)
		clip.rotation_track_insert_key(attack, 0.0, baseline)
		if bone == "J_Bip_R_UpperArm":
			clip.rotation_track_insert_key(attack, 0.22, baseline * Quaternion(Vector3.FORWARD, -1.1))
			clip.rotation_track_insert_key(attack, 0.52, baseline * Quaternion(Vector3.FORWARD, 1.15))
		elif bone == "J_Bip_R_LowerArm":
			clip.rotation_track_insert_key(attack, 0.22, baseline * Quaternion(Vector3.UP, -0.85))
			clip.rotation_track_insert_key(attack, 0.52, baseline * Quaternion(Vector3.UP, 0.55))
		else:
			clip.rotation_track_insert_key(attack, 0.22, baseline)
			clip.rotation_track_insert_key(attack, 0.52, baseline)
		clip.rotation_track_insert_key(attack, 1.0416666, baseline)
	return clip


static func _add_clip(root: AnimationNodeBlendTree, node_name: String, animation_name: String) -> void:
	var clip_node := AnimationNodeAnimation.new()
	clip_node.animation = animation_name
	root.add_node(node_name, clip_node)


static func setup_animation_tree(model: Node, animator: AnimationPlayer, attack_speed: float) -> AnimationTree:
	var walk_name := find_clip(animator, "Walk")
	var jog_name := find_clip(animator, "Jog")
	if walk_name.is_empty() or jog_name.is_empty():
		push_error("VRoid heroine requires imported Walk and Jog clips")
		return null
	var walk := animator.get_animation(walk_name)
	var jog := animator.get_animation(jog_name)
	var library := AnimationLibrary.new()
	library.add_animation("Idle", _hold_pose(walk, 0.15, 0.8, true))
	library.add_animation("Jump", _hold_pose(jog, 0.10, 0.65, false))
	var swing := _sword_swing(walk)
	if swing.get_track_count() < 2:
		push_error("VRoid sword placeholder missing right arm rotation tracks")
		return null
	library.add_animation("SwordSlash", swing)
	# The original imported Walk/Jog clips are kept intact on the VRoid model.
	var replacement_walk: Animation = QUATERNIUS_LOCOMOTION.build_from_reference(walk, false)
	var replacement_run: Animation = QUATERNIUS_LOCOMOTION.build_from_reference(walk, true)
	if replacement_walk == null or replacement_run == null:
		push_error("Failed to retarget Quaternius locomotion to VRoid skeleton")
		return null
	library.add_animation("QuaterniusWalk", replacement_walk)
	library.add_animation("QuaterniusRun", replacement_run)
	if animator.add_animation_library("vroid", library) != OK:
		return null

	var root := AnimationNodeBlendTree.new()
	var locomotion := AnimationNodeTransition.new()
	locomotion.input_count = 5
	locomotion.xfade_time = 0.10
	root.add_node("Locomotion", locomotion)
	var state_names := ["Idle", "Walk", "Run", "Jump"]
	var clips := ["vroid/Idle", "vroid/QuaterniusWalk", "vroid/QuaterniusRun", "vroid/Jump"]
	for i in range(state_names.size()):
		var state: String = state_names[i]
		_add_clip(root, state, clips[i])
		locomotion.set_input_name(i, state)
		if state == "Walk" or state == "Run":
			var speed := AnimationNodeTimeScale.new()
			root.add_node(state + "Speed", speed)
			root.connect_node(state + "Speed", 0, state)
			root.connect_node("Locomotion", i, state + "Speed")
		else:
			root.connect_node("Locomotion", i, state)

	# The Naruto toggle remains available, but temporarily reuses Jog;
	# applying Ninja-specific tracks to this different rig would be unsafe.
	_add_clip(root, "NarutoBaseRun", jog_name)
	_add_clip(root, "NarutoFull", jog_name)
	var naruto_base_speed := AnimationNodeTimeScale.new()
	var naruto_full_speed := AnimationNodeTimeScale.new()
	var naruto_blend := AnimationNodeBlend2.new()
	root.add_node("NarutoBaseRunSpeed", naruto_base_speed)
	root.add_node("NarutoFullSpeed", naruto_full_speed)
	root.add_node("NarutoFullBodyBlend", naruto_blend)
	root.connect_node("NarutoBaseRunSpeed", 0, "NarutoBaseRun")
	root.connect_node("NarutoFullSpeed", 0, "NarutoFull")
	root.connect_node("NarutoFullBodyBlend", 0, "NarutoBaseRunSpeed")
	root.connect_node("NarutoFullBodyBlend", 1, "NarutoFullSpeed")
	locomotion.set_input_name(4, "Naruto")
	root.connect_node("Locomotion", 4, "NarutoFullBodyBlend")

	_add_clip(root, "SwordSlash", "vroid/SwordSlash")
	var attack_speed_node := AnimationNodeTimeScale.new()
	var attack_layer := AnimationNodeOneShot.new()
	attack_layer.fadein_time = 0.09
	attack_layer.fadeout_time = 0.10
	attack_layer.filter_enabled = true
	for index in range(swing.get_track_count()):
		attack_layer.set_filter_path(swing.track_get_path(index), true)
	root.add_node("AttackSpeed", attack_speed_node)
	root.add_node("Attack", attack_layer)
	root.connect_node("AttackSpeed", 0, "SwordSlash")
	root.connect_node("Attack", 0, "Locomotion")
	root.connect_node("Attack", 1, "AttackSpeed")
	root.connect_node("output", 0, "Attack")

	var animation_tree := AnimationTree.new()
	animation_tree.name = "CharacterAnimationTree"
	model.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animator)
	animation_tree.tree_root = root
	animator.stop()
	animation_tree.active = true
	animation_tree.set("parameters/AttackSpeed/scale", attack_speed)
	animation_tree.set("parameters/NarutoFullBodyBlend/blend_amount", 1.0)
	animation_tree.set("parameters/NarutoFullSpeed/scale", 1.0)
	return animation_tree
