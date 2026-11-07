extends RefCounted
# Builds and configures the imported rig's animation graph.
# No gameplay input, attack damage or state transitions live here.
const STANDARD_SWORD_CLIP := preload("res://assets/animations/standard_sword_slash.tres")
const SWEEPING_SWORD_CLIP := preload("res://assets/animations/sweeping_sword_slash.tres")
const NARUTO_RUN_FULL_CLIP := preload("res://assets/animations/naruto_run_fullbody.tres")
const UPPER_BODY_BONES := [
	"Abdomen", "Torso", "Neck", "Head",
	"Shoulder.L", "UpperArm.L", "LowerArm.L", "Fist.L",
	"Shoulder.R", "UpperArm.R", "LowerArm.R", "Fist.R"
]

static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := find_animation_player(child)
		if result != null:
			return result
	return null

static func configure_animation_loops(animator: AnimationPlayer) -> void:
	if animator == null:
		return
	for name in animator.get_animation_list():
		var clip_name := String(name)
		var animation := animator.get_animation(name)
		if animation == null:
			continue
		if clip_name.ends_with("/Idle") or clip_name == "Idle" or clip_name.ends_with("/Walk") or clip_name == "Walk" or clip_name.ends_with("/Run") or clip_name == "Run":
			animation.loop_mode = Animation.LOOP_LINEAR
		else:
			# Actions (SwordSlash, Jump, etc.) should play once.
			animation.loop_mode = Animation.LOOP_NONE

static func find_clip(animator: AnimationPlayer, short_name: String) -> String:
	if animator == null:
		return ""
	for name in animator.get_animation_list():
		var full_name := String(name)
		if full_name == short_name or full_name.ends_with("/" + short_name):
			return full_name
	push_warning("Animation not found: " + short_name)
	return ""


static func setup_animation_tree(model: Node, animator: AnimationPlayer, attack_speed_value: float) -> AnimationTree:
	var root := AnimationNodeBlendTree.new()
	var locomotion := AnimationNodeTransition.new()
	locomotion.input_count = 5
	locomotion.xfade_time = 0.10
	root.add_node("Locomotion", locomotion)

	var states := ["Idle", "Walk", "Run", "Jump"]
	for i in range(states.size()):
		var state: String = states[i]
		var clip_name := find_clip(animator, state)
		if clip_name.is_empty():
			push_error("Cannot build locomotion tree without " + state)
			return null
		locomotion.set_input_name(i, state)
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = clip_name
		root.add_node(state, clip_node)
		if state == "Walk" or state == "Run":
			var speed_node := AnimationNodeTimeScale.new()
			root.add_node(state + "Speed", speed_node)
			root.connect_node(state + "Speed", 0, state)
			root.connect_node("Locomotion", i, state + "Speed")
		else:
			root.connect_node("Locomotion", i, state)

	# Independent Naruto sprint with a complete limb cycle. Keep the imported
	# Run separately for the root and the Ninja's original foot helper controls.
	# The Mixamo source foot joints cannot be mapped to this footless Ninja rig.
	var naruto_library := AnimationLibrary.new()
	if naruto_library.add_animation("NarutoRunFull", NARUTO_RUN_FULL_CLIP) != OK:
		push_error("Could not register Naruto full-body running clip")
		return null
	if animator.add_animation_library("movement_naruto", naruto_library) != OK:
		push_error("Could not attach Naruto running library")
		return null
	var run_clip := animator.get_animation(find_clip(animator, "Run"))
	if run_clip == null or run_clip.length <= 0.0:
		push_error("Cannot synchronize Naruto running clip without Ninja Run")
		return null
	var naruto_speed_ratio := NARUTO_RUN_FULL_CLIP.length / run_clip.length
	var naruto_base_run := AnimationNodeAnimation.new()
	naruto_base_run.animation = find_clip(animator, "Run")
	var naruto_base_speed := AnimationNodeTimeScale.new()
	var naruto_full := AnimationNodeAnimation.new()
	naruto_full.animation = "movement_naruto/NarutoRunFull"
	var naruto_full_speed := AnimationNodeTimeScale.new()
	var naruto_blend := AnimationNodeBlend2.new()
	naruto_blend.filter_enabled = true
	# Exclude Body_2 / Hips and both Foot.* IK helpers. The earlier raw Mixamo
	# root pitch made the character crawl; the foot joints are incompatible.
	for bone in ["Abdomen", "Torso", "Neck", "Head",
			"Shoulder.L", "UpperArm.L", "LowerArm.L", "Fist.L",
			"Shoulder.R", "UpperArm.R", "LowerArm.R", "Fist.R",
			"UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R"]:
		naruto_blend.set_filter_path(NodePath("CharacterArmature/Skeleton3D:" + bone), true)
	root.add_node("NarutoBaseRun", naruto_base_run)
	root.add_node("NarutoBaseRunSpeed", naruto_base_speed)
	root.add_node("NarutoFull", naruto_full)
	root.add_node("NarutoFullSpeed", naruto_full_speed)
	root.add_node("NarutoFullBodyBlend", naruto_blend)
	root.connect_node("NarutoBaseRunSpeed", 0, "NarutoBaseRun")
	root.connect_node("NarutoFullSpeed", 0, "NarutoFull")
	root.connect_node("NarutoFullBodyBlend", 0, "NarutoBaseRunSpeed")
	root.connect_node("NarutoFullBodyBlend", 1, "NarutoFullSpeed")
	locomotion.set_input_name(4, "Naruto")
	root.connect_node("Locomotion", 4, "NarutoFullBodyBlend")

	# Register both approved attacks as independent, pre-baked animations.
	# The Standard remains available, while ATK still plays only Sweeping.
	var standard_library := AnimationLibrary.new()
	var sweeping_library := AnimationLibrary.new()
	if standard_library.add_animation("WideSwordSlashMirror", STANDARD_SWORD_CLIP) != OK:
		push_error("Could not register the Standard sword animation")
		return null
	if sweeping_library.add_animation("SweepingSwordSlash", SWEEPING_SWORD_CLIP) != OK:
		push_error("Could not register the Sweeping sword animation")
		return null
	if animator.add_animation_library("combat_mirror", standard_library) != OK:
		push_error("Could not attach Standard sword animation")
		return null
	if animator.add_animation_library("combat_sweeping", sweeping_library) != OK:
		push_error("Could not attach Sweeping sword animation")
		return null
	var attack_clip_name := "combat_sweeping/SweepingSwordSlash"
	var attack_clip := animator.get_animation(attack_clip_name)
	var attack_node := AnimationNodeAnimation.new()
	attack_node.animation = attack_clip_name
	var attack_speed := AnimationNodeTimeScale.new()
	var attack_layer := AnimationNodeOneShot.new()
	# Slightly soften the transition from locomotion to the new test pose.
	# Only the sweeping animation is currently attached to the OneShot.
	attack_layer.fadein_time = 0.09
	attack_layer.fadeout_time = 0.10
	attack_layer.filter_enabled = true
	var filtered := 0
	for track_index in range(attack_clip.get_track_count()):
		var track_path := attack_clip.track_get_path(track_index)
		if track_path.get_subname_count() == 0:
			continue
		var bone := String(track_path.get_subname(track_path.get_subname_count() - 1))
		if bone in UPPER_BODY_BONES:
			attack_layer.set_filter_path(track_path, true)
			filtered += 1
	if filtered == 0:
		push_error("The imported SwordSlash animation has no matching upper-body tracks")
		return null

	root.add_node("SwordSlash", attack_node)
	root.add_node("AttackSpeed", attack_speed)
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
	animation_tree.set("parameters/AttackSpeed/scale", attack_speed_value)
	animation_tree.set("parameters/NarutoFullBodyBlend/blend_amount", 1.0)
	animation_tree.set("parameters/NarutoFullSpeed/scale", naruto_speed_ratio)
	return animation_tree


