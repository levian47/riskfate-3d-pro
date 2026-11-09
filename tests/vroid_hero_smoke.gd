extends SceneTree

const VROID_ANIM := preload("res://characters/player/animation_builder_vroid.gd")
const WEAPONS := preload("res://characters/player/weapon_visuals.gd")

func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VRoid smoke test: " + message)
	quit(1)
	return false


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if not _check(packed != null, "main.tscn not loaded"):
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	if not _check(not bool(game.get("use_legacy_hero")), "VRoid heroine must be default"):
		return
	var visual := game.get("visual") as Node3D
	var rig := WEAPONS.find_skeleton(visual)
	if not _check(rig != null and rig.get_bone_count() == 103, "original 103-bone VRoid rig missing"):
		return
	for name in ["J_Bip_C_Head", "J_Bip_R_Hand", "J_Bip_L_UpperLeg"]:
		if not _check(rig.find_bone(name) >= 0, "missing required VRoid bone: " + name):
			return
	var mesh_count := _count_meshes(visual)
	if not _check(mesh_count >= 3, "Body/Face/Hair mesh components missing"):
		return
	var grip := rig.get_node_or_null("SwordGrip/WeaponMount") as Node3D
	if not _check(grip != null, "weapon mount missing on VRoid hand"):
		return
	var animator := game.get("animator") as AnimationPlayer
	var tree := game.get("animation_tree") as AnimationTree
	if not _check(animator != null and tree != null and tree.active, "VRoid animation graph missing"):
		return
	var walk := VROID_ANIM.find_clip(animator, "Walk")
	var jog := VROID_ANIM.find_clip(animator, "Jog")
	if not _check(not walk.is_empty() and not jog.is_empty(), "supplied Walk/Jog clips not imported"):
		return
	if not _check(animator.get_animation(walk).loop_mode == Animation.LOOP_LINEAR and animator.get_animation(jog).loop_mode == Animation.LOOP_LINEAR, "Walk/Jog must loop"):
		return
	# Quaternius CC0 locomotion is separate from the preserved original
	# VRoid Walk/Jog and must be the active clip in the gameplay graph.
	var new_walk_name := VROID_ANIM.find_clip(animator, "QuaterniusWalk")
	var new_run_name := VROID_ANIM.find_clip(animator, "QuaterniusRun")
	if not _check(not new_walk_name.is_empty() and not new_run_name.is_empty(), "new CC0 Walk/Run clips missing"):
		return
	var new_walk := animator.get_animation(new_walk_name)
	var new_run := animator.get_animation(new_run_name)
	if not _check(new_walk.loop_mode == Animation.LOOP_LINEAR and new_run.loop_mode == Animation.LOOP_LINEAR, "new locomotion must loop"):
		return
	if not _check(new_walk.get_track_count() == 23 and new_run.get_track_count() == 23, "22 retargeted bones plus hips movement expected"):
		return
	if not _check(new_run.length > 0.90 and new_run.length < 1.00, "forward jog must replace overly aggressive sprint"):
		return
	for new_clip in [new_walk, new_run]:
		var lower_leg_track := -1
		for index in range(new_clip.get_track_count()):
			if new_clip.track_get_type(index) != Animation.TYPE_ROTATION_3D:
				continue
			var track_path := new_clip.track_get_path(index)
			if track_path.get_subname_count() > 0 and String(track_path.get_subname(track_path.get_subname_count() - 1)) == "J_Bip_L_LowerLeg":
				lower_leg_track = index
				break
		if not _check(lower_leg_track >= 0, "new locomotion clip must animate the left lower leg"):
			return
		var start_pose := new_clip.rotation_track_interpolate(lower_leg_track, 0.0)
		var half_pose := new_clip.rotation_track_interpolate(lower_leg_track, new_clip.length * 0.5)
		var end_pose := new_clip.rotation_track_interpolate(lower_leg_track, new_clip.length)
		if not _check(start_pose.angle_to(half_pose) > 0.03, "new locomotion lower leg must actually move"):
			return
		if not _check(start_pose.angle_to(end_pose) < 0.02, "new locomotion must have a seamless loop"):
			return
	var graph := tree.tree_root as AnimationNodeBlendTree
	if not _check(graph != null, "VRoid AnimationTree root missing"):
		return
	var walk_node := graph.get_node("Walk") as AnimationNodeAnimation
	var run_node := graph.get_node("Run") as AnimationNodeAnimation
	if not _check(walk_node != null and run_node != null and String(walk_node.animation) == new_walk_name and String(run_node.animation) == new_run_name, "gameplay graph not using new Walk/Run"):
		return
	if not _check(not VROID_ANIM.find_clip(animator, "SwordSlash").is_empty(), "combat timing clip missing"):
		return
	game.call("_set_locomotion", "Walk", true)
	tree.advance(0.10)
	game.call("_set_locomotion", "Run", true)
	tree.advance(0.10)
	if not _check(String(game.get("locomotion_state")) == "Run", "Run transition unavailable"):
		return
	var bone := rig.find_bone("J_Bip_L_UpperLeg")
	tree.active = false
	animator.play(walk)
	animator.seek(0.02, true)
	var before := rig.get_bone_pose_rotation(bone)
	animator.seek(animator.get_animation(walk).length * 0.45, true)
	var after := rig.get_bone_pose_rotation(bone)
	if not _check(before.angle_to(after) > 0.02, "Walk does not deform the VRoid leg bone"):
		return
	animator.stop()
	tree.active = true
	game.call("_start_attack")
	if not _check(float(game.get("combat_controller").get("attack_time_left")) > 0.0, "attack input/timing broken"):
		return
	print("VRoid smoke test OK: 103 bones, ", mesh_count, " mesh nodes, original Walk/Jog and Quaternius Walk/Run, weapon mount and attack")
	game.queue_free()
	quit(0)


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count
