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
	# Temporary inventory to find licensed authored fist clips in current UAL2 source.
	var ual2_source := VROID_ANIM.UAL2_COMBAT.SOURCE.instantiate()
	var ual2_player := VROID_ANIM.UAL2_COMBAT._find_animator(ual2_source)
	if ual2_player != null:
		print("AVAILABLE_UAL2_CLIPS=", ual2_player.get_animation_list())
	ual2_source.free()
	var zip := ZIPReader.new()
	if zip.open("res://assets_source/animation_libraries/quaternius/ual1_standard_godot.zip") == OK:
		for filename in zip.get_files():
			var label := filename.to_lower()
			if "punch" in label or "fight" in label or "attack" in label or "combat" in label or "melee" in label or "unarmed" in label or "animations" in label:
				print("AVAILABLE_UAL1_FILE=", filename)
		zip.close()
	var packed := load("res://main.tscn") as PackedScene
	if not _check(packed != null, "main.tscn not loaded"):
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	if not _check(not bool(game.get("use_legacy_hero")), "VRoid heroine must be default"):
		return
	var movement = game.get("movement_controller")
	if not _check(movement != null and bool(movement.get("run_by_default")), "VRoid must default to Run on desktop"):
		return
	game.call("_toggle_run_mode")
	if not _check(not bool(movement.get("run_by_default")), "Run/Walk toggle must activate Walk"):
		return
	game.call("_toggle_run_mode")
	if not _check(bool(movement.get("run_by_default")), "Run/Walk toggle must restore Run"):
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
	var attachment := rig.get_node_or_null("SwordGrip") as BoneAttachment3D
	if not _check(attachment != null and attachment.bone_name == "J_Bip_R_Hand", "Sword I must follow the original right-hand bone"):
		return
	# The VRoid hand/fingers point local +Y and its thumb lies at +Z.
	# A sword still pointing along local +Y would follow the forearm; the
	# blade must leave the grip toward the thumb side for this test pose.
	var sword_axis := grip.transform.basis.y.normalized()
	if not _check(grip.position.y > 0.04 and grip.position.y < 0.08 and sword_axis.dot(Vector3.BACK) > 0.95, "Sword I blade must cross the palm toward the thumb, not follow the forearm"):
		return
	if not _check(grip.get_node_or_null("EquippedWeapon") != null, "Sword I geometry not attached to palm"):
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
	var new_walk: Animation = animator.get_animation(new_walk_name)
	var new_run: Animation = animator.get_animation(new_run_name)
	if not _check(new_walk.loop_mode == Animation.LOOP_LINEAR and new_run.loop_mode == Animation.LOOP_LINEAR, "new locomotion must loop"):
		return
	if not _check(new_walk.get_track_count() == 23 and new_run.get_track_count() == 23, "22 retargeted bones plus hips movement expected"):
		return
	if not _check(new_run.length > 0.90 and new_run.length < 1.00, "forward jog must replace overly aggressive sprint"):
		return
	# Weapon-safe running only retunes the right arm; verify the original
	# Quaternius gait, torso and left arm are left identical.
	var original_run := VROID_ANIM.QUATERNIUS_LOCOMOTION.build_from_reference(animator.get_animation(walk), true, rig)
	if not _check(original_run != null, "original run data unavailable for regression comparison"):
		return
	var carry_changed := 0
	for index in range(new_run.get_track_count()):
		var path := new_run.track_get_path(index)
		var kind := new_run.track_get_type(index)
		var bone_name := String(path.get_subname(path.get_subname_count() - 1)) if path.get_subname_count() > 0 else ""
		if kind != Animation.TYPE_ROTATION_3D:
			continue
		var time := new_run.length * 0.28
		var original_pose := original_run.rotation_track_interpolate(index, time)
		var carried_pose := new_run.rotation_track_interpolate(index, time)
		var difference := original_pose.angle_to(carried_pose)
		if VROID_ANIM.RUN_WEAPON_CARRY_BLEND.has(bone_name):
			if difference > 0.02:
				carry_changed += 1
		else:
			if not _check(difference < 0.001,
				"weapon-run correction altered accepted legs, torso, or left arm: " + bone_name):
				return
	if not _check(carry_changed >= 2,
		"weapon-run pose must move multiple right-arm bones from head-height swing"):
		return
	print("VRoid running weapon carry: changed_right_arm_tracks=", carry_changed)
	for candidate in [new_walk, new_run]:
		var new_clip: Animation = candidate as Animation
		var lower_leg_track := -1
		for index in range(new_clip.get_track_count()):
			if new_clip.track_get_type(index) != Animation.TYPE_ROTATION_3D:
				continue
			var track_path: NodePath = new_clip.track_get_path(index)
			if track_path.get_subname_count() > 0 and String(track_path.get_subname(track_path.get_subname_count() - 1)) == "J_Bip_L_LowerLeg":
				lower_leg_track = index
				break
		if not _check(lower_leg_track >= 0, "new locomotion clip must animate the left lower leg"):
			return
		var start_pose: Quaternion = new_clip.rotation_track_interpolate(lower_leg_track, 0.0)
		var half_pose: Quaternion = new_clip.rotation_track_interpolate(lower_leg_track, new_clip.length * 0.5)
		var end_pose: Quaternion = new_clip.rotation_track_interpolate(lower_leg_track, new_clip.length)
		if not _check(start_pose.angle_to(half_pose) > 0.03, "new locomotion lower leg must actually move"):
			return
		if not _check(start_pose.angle_to(end_pose) < 0.02, "new locomotion must have a seamless loop"):
			return
	# Regression: Godot 4 bone transform tracks must include bone rest.
	# Without rest position, hips fall to y≈0; without rest rotations,
	# limbs collapse into a sideways/T-pose despite a passing basic smoke test.
	var hips_index := rig.find_bone("J_Bip_C_Hips")
	var thigh_index := rig.find_bone("J_Bip_L_UpperLeg")
	if not _check(hips_index >= 0 and thigh_index >= 0, "VRoid hips/thigh rest missing"):
		return
	var hips_rest := rig.get_bone_rest(hips_index).origin
	var thigh_rest := rig.get_bone_rest(thigh_index).basis.get_rotation_quaternion()
	for candidate in [new_walk, new_run]:
		var clip: Animation = candidate as Animation
		var hips_track := -1
		var thigh_track := -1
		for index in range(clip.get_track_count()):
			var path: NodePath = clip.track_get_path(index)
			if path.get_subname_count() == 0:
				continue
			var bone_name := String(path.get_subname(path.get_subname_count() - 1))
			if bone_name == "J_Bip_C_Hips" and clip.track_get_type(index) == Animation.TYPE_POSITION_3D:
				hips_track = index
			if bone_name == "J_Bip_L_UpperLeg" and clip.track_get_type(index) == Animation.TYPE_ROTATION_3D:
				thigh_track = index
		if not _check(hips_track >= 0 and thigh_track >= 0, "Quaternius tracks missing hips/thigh"):
			return
		var hips_pose := clip.position_track_interpolate(hips_track, 0.0)
		if not _check(hips_pose.distance_to(hips_rest) < 0.10, "Quaternius hips position omitted Bone Rest"):
			return
		var thigh_pose := clip.rotation_track_interpolate(thigh_track, 0.0)
		if not _check(thigh_pose.angle_to(thigh_rest) < 1.7, "Quaternius thigh rotation omitted Bone Rest"):
			return
	var graph := tree.tree_root as AnimationNodeBlendTree
	if not _check(graph != null, "VRoid AnimationTree root missing"):
		return
	var run_arms_node := graph.get_node("RunArms") as AnimationNodeBlend2
	if not _check(run_arms_node != null and run_arms_node.sync, "armed/unarmed Run must keep both clips synchronized"):
		return
	var grip_name := VROID_ANIM.find_clip(animator, "SwordGrip")
	if not _check(not grip_name.is_empty(), "VRoid Sword I finger grip animation missing"):
		return
	var grip_clip := animator.get_animation(grip_name)
	if not _check(grip_clip.get_track_count() == 14, "VRoid grip must curl twelve finger joints and two distal thumb joints"):
		return
	var grip_overlay := graph.get_node("GripOverlay") as AnimationNodeBlend2
	if not _check(grip_overlay != null and grip_overlay.filter_enabled, "finger grip must be a filtered animation layer"):
		return
	for i in range(grip_clip.get_track_count()):
		var track_path := grip_clip.track_get_path(i)
		if not _check(grip_overlay.is_path_filtered(track_path), "finger grip track is missing its blend filter"):
			return
		var original_index := animator.get_animation(walk).find_track(track_path, Animation.TYPE_ROTATION_3D)
		if not _check(original_index >= 0, "grip must reuse the imported VRoid finger track"):
			return
		var original_rotation := animator.get_animation(walk).rotation_track_interpolate(original_index, 0.15)
		var gripped_rotation := grip_clip.rotation_track_interpolate(i, 0.0)
		var bend := original_rotation.angle_to(gripped_rotation)
		if not _check(bend > 0.30 and bend < 1.10, "grip finger curl angle out of the initial safe range"):
			return
	if not _check(float(tree.get("parameters/GripOverlay/blend_amount")) > 0.99, "Sword I grip must be active by default"):
		return
	game.call("_cycle_weapon")
	if not _check(float(tree.get("parameters/GripOverlay/blend_amount")) > 0.99, "Sword II must share the one-handed finger grip"):
		return
	if not _check(grip.transform.basis.y.normalized().dot(Vector3.BACK) > 0.95, "Sword II blade must also point across the palm"):
		return
	var weapon_visuals = game.get("weapon_visuals")
	if not _check(grip.get_node_or_null("EquippedWeapon") == weapon_visuals.current_visual, "Sword II weapon node name was lost during switching"):
		return
	if not _check(weapon_visuals.equip(2), "Dagger cannot be equipped for grip exclusion test"):
		return
	game.call("_update_weapon_display")
	if not _check(grip.get_node_or_null("EquippedWeapon") == weapon_visuals.current_visual, "Dagger weapon node name was lost during switching"):
		return
	if not _check(float(tree.get("parameters/GripOverlay/blend_amount")) > 0.99, "Dagger must also use the closed-hand grip"):
		return
	if not _check(grip.transform.basis.y.normalized().dot(Vector3.BACK) > 0.95 and grip.position.y > 0.04, "Dagger must sit across the palm, not extend the forearm"):
		return
	for candidate_index in [3, 4]:
		if not _check(weapon_visuals.equip(candidate_index), "Knife/Cutlass cannot be equipped for grip test"):
			return
		game.call("_update_weapon_display")
		if not _check(grip.get_node_or_null("EquippedWeapon") == weapon_visuals.current_visual, "Knife/Cutlass weapon attachment lost after switching"):
			return
		var min_forward := 0.85 if candidate_index == 4 else 0.95
		if not _check(grip.position.y > 0.04 and grip.transform.basis.y.normalized().dot(Vector3.BACK) > min_forward, "Knife/Cutlass must be fitted across the palm with approved outward-tilt range"):
			return
		if not _check(float(tree.get("parameters/GripOverlay/blend_amount")) > 0.99, "Knife/Cutlass must use the same closed-hand grip"):
			return
	if not _check(weapon_visuals.equip(0), "Sword I cannot be re-equipped"):
		return
	game.call("_update_weapon_display")
	if not _check(grip.get_node_or_null("EquippedWeapon") == weapon_visuals.current_visual, "Sword I weapon node name was lost when re-equipping"):
		return
	if not _check(float(tree.get("parameters/GripOverlay/blend_amount")) > 0.99, "Sword I grip not restored after switching weapons"):
		return
	var walk_node := graph.get_node("Walk") as AnimationNodeAnimation
	var run_node := graph.get_node("Run") as AnimationNodeAnimation
	if not _check(walk_node != null and run_node != null and String(walk_node.animation) == new_walk_name and String(run_node.animation) == new_run_name, "gameplay graph not using new Walk/Run"):
		return
	var regular_name := VROID_ANIM.find_clip(animator, "SwordSlash")
	var heavy_name := VROID_ANIM.find_clip(animator, "SwordHeavyCandidate")
	if not _check(not regular_name.is_empty() and not heavy_name.is_empty(), "UAL2 combat clips missing"):
		return
	var regular_clip := animator.get_animation(regular_name)
	var heavy_clip := animator.get_animation(heavy_name)
	if not _check(regular_clip.get_track_count() >= 10 and heavy_clip.get_track_count() >= 10, "UAL2 attack must retarget both arms and spine"):
		return
	if not _check(regular_clip.length > 0.40 and regular_clip.length < 0.50 and heavy_clip.length > 0.70 and heavy_clip.length < 0.80, "source attack durations do not match UAL2"):
		return
	# Confirm stronger authored arm motion rather than faster weapon visuals.
	for short_name in ["Sword_Regular_A", "Sword_Heavy_A"]:
		var original_attack := VROID_ANIM.UAL2_COMBAT.build(short_name, animator.get_animation(walk), rig)
		var boosted_attack: Animation = regular_clip if short_name == "Sword_Regular_A" else heavy_clip
		if not _check(original_attack != null and original_attack.get_track_count() == boosted_attack.get_track_count(),
			"cannot compare authored attack with widened-arc version"):
			return
		var arm_amplification := 0.0
		for track in range(boosted_attack.get_track_count()):
			var path := boosted_attack.track_get_path(track)
			var bone := String(path.get_subname(path.get_subname_count() - 1)) if path.get_subname_count() > 0 else ""
			if bone != "J_Bip_R_UpperArm":
				continue
			var sample_time := boosted_attack.length * 0.5
			arm_amplification = original_attack.rotation_track_interpolate(track, sample_time).angle_to(
				boosted_attack.rotation_track_interpolate(track, sample_time))
		if not _check(arm_amplification > 0.045,
			"wider attack must change the right upper-arm arc: " + short_name):
			return
		print("VRoid attack arc ", short_name, ": upper_arm_extra_radians=", arm_amplification)
	var slash_blend := graph.get_node("SlashChoice") as AnimationNodeBlend2
	if not _check(slash_blend != null, "UAL2 combat clip selector missing"):
		return
	if not _check(float(tree.get("parameters/SlashChoice/blend_amount")) > 0.99, "Sword I heavy must select heavy attack"):
		return
	if not _check(weapon_visuals.equip(1), "Sword II cannot be equipped for regular one-hand preview"):
		return
	game.call("_update_weapon_display")
	if not _check(float(tree.get("parameters/SlashChoice/blend_amount")) < 0.01, "Sword II must select regular one-hand preview"):
		return
	if not _check(weapon_visuals.equip(0), "Sword I re-equip after regular preview failed"):
		return
	game.call("_update_weapon_display")
	game.call("_set_locomotion", "Walk", true)
	tree.advance(0.10)
	game.call("_set_locomotion", "Run", true)
	tree.advance(0.10)
	if not _check(String(game.get("locomotion_state")) == "Run", "Run transition unavailable"):
		return
	game.call("_set_locomotion", "Jump", true)
	tree.advance(0.10)
	game.call("_set_locomotion", "Idle", true)
	tree.advance(0.10)
	if not _check(grip.get_node_or_null("EquippedWeapon") != null, "weapon mount lost during animation transitions"):
		return
	var bone := rig.find_bone("J_Bip_L_UpperLeg")
	tree.active = false
	# Validate a real kinematic height change, not only extra rotation keys:
	# compare the right wrist in the same retargeted heavy clip with/without lift.
	var heavy_baseline: Animation = VROID_ANIM.UAL2_COMBAT.build("Sword_Heavy_A", animator.get_animation(walk), rig, true)
	if not _check(heavy_baseline != null, "heavy sword baseline unavailable"):
		return
	var diagnostic_library := AnimationLibrary.new()
	diagnostic_library.add_animation("HeavyBaseline", heavy_baseline)
	var heavy_previous: Animation = VROID_ANIM._apply_sword_i_sin_lift(heavy_baseline)
	diagnostic_library.add_animation("HeavyPrevious", heavy_previous)
	if not _check(animator.add_animation_library("heavy_height_test", diagnostic_library) == OK,
		"cannot register heavy-attack baseline"):
		return
	var hand_idx := rig.find_bone("J_Bip_R_Hand")
	if not _check(hand_idx >= 0, "right hand missing for attack height test"):
		return
	var attack_height_gain := 0.0
	for phase in [0.35, 0.50, 0.65]:
		var time := heavy_clip.length * float(phase)
		animator.play("heavy_height_test/HeavyBaseline")
		animator.seek(time, true)
		rig.force_update_all_bone_transforms()
		var original_y := rig.get_bone_global_pose(hand_idx).origin.y
		animator.play(heavy_name)
		animator.seek(time, true)
		rig.force_update_all_bone_transforms()
		var raised_y := rig.get_bone_global_pose(hand_idx).origin.y
		var delta_y := raised_y - original_y
		attack_height_gain = maxf(attack_height_gain, delta_y)
		print("Sword I attack height phase=", phase, " baseline_hand_y=", original_y,
			" raised_hand_y=", raised_y, " extra_y=", delta_y)
	if not _check(attack_height_gain > 0.035, "Sword I heavy attack failed to lift the sword hand"):
		return
	# --- RF-VROID-015D A: Sword I finishing phase -------------------------------
	if not _check(heavy_previous.get_track_count() == heavy_clip.get_track_count(), "Sword I clip lost tracks"):
		return
	var corrected_bones := VROID_ANIM.SWORD_I_FINISH_CORRECTION.keys()
	var max_speed_previous := 0.0
	var max_speed_new := 0.0
	var finish_changed := 0.0
	for track in range(heavy_clip.get_track_count()):
		if heavy_clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var track_path := heavy_clip.track_get_path(track)
		var track_bone := String(track_path.get_subname(track_path.get_subname_count() - 1))
		var previous_track := heavy_previous.find_track(track_path, Animation.TYPE_ROTATION_3D)
		if not _check(previous_track >= 0 and heavy_previous.track_get_key_count(previous_track) == heavy_clip.track_get_key_count(track), "Sword I track layout changed: " + track_bone):
			return
		var previous_pose := Quaternion.IDENTITY
		var new_pose := Quaternion.IDENTITY
		var previous_time := 0.0
		for key in range(heavy_clip.track_get_key_count(track)):
			var key_time := heavy_clip.track_get_key_time(track, key)
			var progress := key_time / heavy_clip.length
			var old_value: Quaternion = heavy_previous.track_get_key_value(previous_track, key)
			var new_value: Quaternion = heavy_clip.track_get_key_value(track, key)
			var diff := old_value.angle_to(new_value)
			if track_bone in corrected_bones:
				if progress <= VROID_ANIM.SWORD_I_FINISH_ENVELOPE.x + 0.0001 or key == heavy_clip.track_get_key_count(track) - 1:
					if not _check((old_value - new_value).length() < 0.00002, "Sword I start/wind-up/end must stay identical: %s key %d diff %f" % [track_bone, key, diff]):
						return
				else:
					finish_changed = maxf(finish_changed, diff)
				if key > 0:
					var dt := maxf(key_time - previous_time, 0.001)
					max_speed_previous = maxf(max_speed_previous, previous_pose.angle_to(old_value) / dt)
					max_speed_new = maxf(max_speed_new, new_pose.angle_to(new_value) / dt)
			else:
				if not _check((old_value - new_value).length() < 0.00002, "Sword I correction leaked into another bone: " + track_bone):
					return
			previous_pose = old_value
			new_pose = new_value
			previous_time = key_time
	if not _check(finish_changed > 0.25, "Sword I finishing phase was not corrected"):
		return
	if not _check(max_speed_new <= max_speed_previous * 1.5 + 1.0, "Sword I correction creates a sharp jerk: %f vs %f" % [max_speed_new, max_speed_previous]):
		return
	print("Sword I finish correction: max_key_change=", finish_changed, " max_angular_speed ", max_speed_previous, " -> ", max_speed_new)
	var upper_idx := rig.find_bone("J_Bip_R_UpperArm")
	var sword_holder := weapon_visuals.current_visual as Node3D
	var sword_bounds: AABB = weapon_visuals._bounds_in_root(sword_holder)
	var sword_tip_local := Vector3(sword_bounds.get_center().x, sword_bounds.end.y, sword_bounds.get_center().z)
	var finish_hand_height := -99.0
	var finish_tip_height := -99.0
	var previous_tip_height := -99.0
	for phase in [0.30, 0.36, 0.41]:
		var early_time := heavy_clip.length * float(phase)
		var early := []
		for clip_name in [heavy_name, "heavy_height_test/HeavyPrevious"]:
			animator.play(clip_name)
			animator.seek(early_time, true)
			rig.force_update_all_bone_transforms()
			early.append(rig.get_bone_global_pose(hand_idx).origin)
		if not _check((early[0] as Vector3).distance_to(early[1]) < 0.002, "Sword I initial swing (phase %f) must match the previous implementation" % phase):
			return
	for phase in [0.62, 0.70, 0.79, 0.88]:
		var finish_time := heavy_clip.length * float(phase)
		var heights := []
		for clip_name in [heavy_name, "heavy_height_test/HeavyPrevious"]:
			animator.play(clip_name)
			animator.seek(finish_time, true)
			rig.force_update_all_bone_transforms()
			var shoulder_y: float = (rig.global_transform * rig.get_bone_global_pose(upper_idx)).origin.y
			var hand_global: Transform3D = rig.global_transform * rig.get_bone_global_pose(hand_idx)
			var tip_global: Vector3 = hand_global * (grip.transform * (sword_holder.transform * sword_tip_local))
			heights.append([hand_global.origin.y - shoulder_y, tip_global.y - shoulder_y])
		print("Sword I finish phase=", phase, " hand/tip relative to shoulder (new)=", heights[0], " (previous)=", heights[1])
		if absf(phase - 0.70) < 0.001:
			if not _check(float((heights[0] as Array)[1]) > -0.46, "Sword I finishing blade must rise toward shoulder level"):
				return
		if absf(phase - 0.79) < 0.001:
			finish_hand_height = (heights[0] as Array)[0]
			finish_tip_height = (heights[0] as Array)[1]
			previous_tip_height = (heights[1] as Array)[1]
			if not _check(finish_tip_height - previous_tip_height > 0.25 and (heights[0] as Array)[0] - (heights[1] as Array)[0] > 0.10, "Sword I finishing hand/blade is not higher than before"):
				return
	if not _check(finish_hand_height > -0.40 and finish_hand_height < 0.12, "Sword I finishing hand must end near shoulder height"):
		return
	if not _check(finish_tip_height > -0.40 and finish_tip_height < 0.30, "Sword I finishing blade tip must end near shoulder height, not overhead or at the knee"):
		return
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
	var combat = game.get("combat_controller")
	var heavy_duration := heavy_clip.length / VROID_ANIM.VROID_ATTACK_SPEED
	if not _check(absf(float(combat.get("attack_duration")) - heavy_duration) < 0.02, "Sword I attack timer must match slowed heavy clip"):
		return
	if not _check(absf(float(tree.get("parameters/AttackSpeed/scale")) - VROID_ANIM.VROID_ATTACK_SPEED) < 0.001, "VRoid visual attack speed must be reduced without changing Ninja"):
		return
	combat.attack_time_left = 0.0
	if not _check(weapon_visuals.equip(1), "Sword II cannot be re-equipped for regular timing test"):
		return
	game.call("_update_weapon_display")
	game.call("_start_attack")
	var regular_duration := regular_clip.length / VROID_ANIM.VROID_ATTACK_SPEED
	if not _check(absf(float(combat.get("attack_duration")) - regular_duration) < 0.02, "Sword II attack timer must match slowed regular clip"):
		return
	# Diagnostic: identify each imported weapon's actual mesh orientation and
	# grip anchor before altering artwork-relative offsets. Keep in test logs.
	for weapon_id in range(WEAPONS.WEAPONS.size()):
		if not _check(weapon_visuals.equip(weapon_id), "cannot inspect weapon geometry"):
			return
		var holder := weapon_visuals.current_visual as Node3D
		var source := holder.get_child(0) as Node3D
		var local_bounds: AABB = weapon_visuals._bounds_in_root(holder)
		var hilt_center: Vector3 = weapon_visuals._hilt_anchor_in_root(holder, local_bounds)
		if weapon_id == 4:
			hilt_center += WEAPONS.VROID_CUTLASS_HILT_LOCAL_OFFSET
		var advance := WEAPONS.VROID_GRIP_ADVANCE_FRACTION
		if weapon_id in [2, 3]:
			advance += WEAPONS.VROID_DAGGER_EXTRA_GRIP_ADVANCE_FRACTION
		hilt_center.y += local_bounds.size.y * advance
		var fitted_hilt: Vector3 = holder.transform * hilt_center
		if not _check(fitted_hilt.length() < 0.025,
			"weapon grip midpoint displaced from mount, including vertical position"):
			return
		# Verify the shared 90° roll and Cutlass-only extra clockwise 225°.
		# The hand bone must remain unaffected by the weapon's model rotation.
		var expected_roll := WEAPONS.VROID_WEAPON_MODEL_ROLL_DEGREES
		if weapon_id == 4:
			expected_roll += WEAPONS.VROID_CUTLASS_EXTRA_ROLL_DEGREES
		if not _check(absf(source.rotation_degrees.y - expected_roll) < 0.1,
			"wrong weapon axial roll, including Cutlass clockwise correction"):
			return
		# Rest-relative blade direction must lean outward only for the Cutlass;
		# switching back to other weapons resets the shared hand attachment.
		var expected_mount_x := WEAPONS.VROID_WEAPON_GRIP_ROTATION.x
		if weapon_id == 4:
			expected_mount_x -= WEAPONS.VROID_CUTLASS_OUTWARD_TILT_DEGREES
			if not _check(grip.transform.basis.y.normalized().y > 0.42,
				"Cutlass blade must lean outward from right-hand palm"):
				return
		if not _check(absf(grip.rotation_degrees.x - expected_mount_x) < 0.1,
			"Cutlass-only outward tilt leaked to another weapon"):
			return
		# Check that the anchor is not on the pommel / very end of the grip.
		var anchor_fraction := (hilt_center.y - local_bounds.position.y) / local_bounds.size.y
		var min_grip_fraction := 0.25 if weapon_id in [2, 3] else 0.16
		var max_grip_fraction := 0.34 if weapon_id in [2, 3] else 0.24
		if not _check(anchor_fraction > min_grip_fraction and anchor_fraction < max_grip_fraction,
			"weapon grip fraction does not reflect the requested dagger advance"):
			return
		# Requested sizes are relative to the original imported weapon lengths.
		# On the legacy Ninja, vroid_scale is deliberately ignored.
		var specification: Dictionary = WEAPONS.WEAPONS[weapon_id]
		var expected_length := float(specification["length"]) * float(specification.get("vroid_scale", 1.0))
		var measured_length := local_bounds.size.y * holder.scale.y * grip.global_transform.basis.get_scale().y
		if not _check(absf(measured_length - expected_length) < 0.03,
			"VRoid weapon length does not match the requested scaling"):
			return
		if not _check(grip.position.z > 0.02, "VRoid weapon must project forward of the palm"):
			return
		if not _check(grip.position.x < -0.005 and grip.position.x > -0.03,
			"VRoid weapon mount must be shifted slightly left of the palm"):
			return
		if weapon_id == 3:
			if not _check(is_equal_approx(float(specification.get("vroid_scale", 1.0)), 1.30),
				"second dagger (Knife) must be scaled x1.30"):
				return
		print("WEAPON_FIT id=", weapon_id, " name=", WEAPONS.WEAPONS[weapon_id]["name"],
			" mount=", grip.position, " mount_rotation=", grip.rotation_degrees,
			" source_rotation=", source.rotation_degrees,
			" holder_position=", holder.position, " holder_scale=", holder.scale,
			" mesh_aabb=", local_bounds, " hilt_center=", hilt_center, " grip_fraction=", anchor_fraction,
			" expected_length=", expected_length, " measured_length=", measured_length, " fitted=", fitted_hilt)
	# --- RF-VROID-015D B: sixth "no weapon" state -------------------------------
	tree.active = true
	var attack_combat = game.get("combat_controller")
	attack_combat.attack_time_left = 0.0
	attack_combat.attack_hit_pending = false
	if not _check(weapon_visuals.equip(0), "Sword I start state for six-state test"):
		return
	game.call("_update_weapon_display")
	var hud = game.get("touch_hud")
	var expected_sequence := [1, 2, 3, 4, -1, 0, 1]
	var expected_names := ["Sword II (1H)", "Dagger", "Knife", "Cutlass", "None", "Sword I (Heavy)", "Sword II (1H)"]
	for step in range(expected_sequence.size()):
		game.call("_cycle_weapon")
		if not _check(weapon_visuals.current_index == int(expected_sequence[step]) and weapon_visuals.selected_name() == String(expected_names[step]), "weapon cycle step %d is out of order" % step):
			return
		if hud != null and not _check(int(hud.weapon_index) == int(expected_sequence[step]) + 1 and int(hud.weapon_slots) == 6, "HUD must show %d/6" % (int(expected_sequence[step]) + 1)):
			return
		if int(expected_sequence[step]) == -1:
			if not _check(not weapon_visuals.has_weapon() and grip.get_node_or_null("EquippedWeapon") == null and _count_meshes(grip) == 0, "no weapon model may remain visible in the None state"):
				return
			game.call("_sync_weapon_pose", 1.0)
			if not _check(float(tree.get("parameters/GripOverlay/blend_amount")) < 0.01 and float(tree.get("parameters/RunArms/blend_amount")) > 0.99, "None state must disable the finger grip and enable the full Run arms"):
				return
		else:
			game.call("_sync_weapon_pose", 1.0)
			if not _check(float(tree.get("parameters/GripOverlay/blend_amount")) > 0.99 and float(tree.get("parameters/RunArms/blend_amount")) < 0.01, "armed state must use the finger grip and the weapon-safe Run"):
				return
	# Currently Sword II. Re-equip scale/orientation after None, for every weapon.
	for weapon_id in range(WEAPONS.WEAPONS.size()):
		weapon_visuals.unequip()
		game.call("_update_weapon_display")
		if not _check(weapon_visuals.equip(weapon_id), "cannot re-equip after None"):
			return
		game.call("_update_weapon_display")
		var again := weapon_visuals.current_visual as Node3D
		var spec: Dictionary = WEAPONS.WEAPONS[weapon_id]
		var again_bounds: AABB = weapon_visuals._bounds_in_root(again)
		var again_length := again_bounds.size.y * again.scale.y * grip.global_transform.basis.get_scale().y
		var wanted := float(spec["length"]) * float(spec.get("vroid_scale", 1.0))
		if not _check(absf(again_length - wanted) < 0.03, "re-equipped weapon scale changed after None: " + String(spec["name"])):
			return
		var wanted_tilt := WEAPONS.VROID_WEAPON_GRIP_ROTATION.x - (WEAPONS.VROID_CUTLASS_OUTWARD_TILT_DEGREES if weapon_id == 4 else 0.0)
		if not _check(absf(grip.rotation_degrees.x - wanted_tilt) < 0.1 and grip.position.y > 0.04, "re-equipped grip orientation changed after None: " + String(spec["name"])):
			return
	# Approved Cutlass fit must be untouched: roll -225 + 30 deg outward tilt.
	if not _check(weapon_visuals.equip(4) and absf((weapon_visuals.current_visual.get_child(0) as Node3D).rotation_degrees.y - (WEAPONS.VROID_WEAPON_MODEL_ROLL_DEGREES + WEAPONS.VROID_CUTLASS_EXTRA_ROLL_DEGREES)) < 0.1 and absf(WEAPONS.VROID_CUTLASS_OUTWARD_TILT_DEGREES - 30.0) < 0.001, "approved Cutlass roll/tilt changed"):
		return
	# Other four attacks keep the standard clip; ATK without a weapon does nothing.
	for weapon_id in [1, 2, 3, 4]:
		weapon_visuals.equip(weapon_id)
		game.call("_update_weapon_display")
		if not _check(float(tree.get("parameters/SlashChoice/blend_amount")) < 0.01, "Sword II/Dagger/Knife/Cutlass must keep the standard attack"):
			return
	var regular_reference: Animation = VROID_ANIM.UAL2_COMBAT.build("Sword_Regular_A", animator.get_animation(walk), rig, true)
	for track in range(regular_clip.get_track_count()):
		for key in range(regular_clip.track_get_key_count(track)):
			var regular_diff: float = (regular_clip.track_get_key_value(track, key) as Quaternion).angle_to(regular_reference.track_get_key_value(track, key))
			if not _check((regular_clip.track_get_key_value(track, key) as Quaternion).is_equal_approx(regular_reference.track_get_key_value(track, key)), "standard attack clip changed"):
				return
	weapon_visuals.unequip()
	game.call("_update_weapon_display")
	attack_combat.attack_time_left = 0.0
	attack_combat.attack_hit_pending = false
	game.call("_start_attack")
	if not _check(attack_combat.attack_time_left == 0.0 and not attack_combat.attack_hit_pending, "ATK without a weapon must not start a sword attack"):
		return
	# Switching to None in the middle of an attack must cancel it cleanly.
	weapon_visuals.equip(0)
	game.call("_update_weapon_display")
	game.call("_start_attack")
	if not _check(attack_combat.attack_time_left > 0.0 and attack_combat.attack_hit_pending, "Sword I attack did not start"):
		return
	weapon_visuals.equip(1)
	game.call("_update_weapon_display")
	if not _check(float(tree.get("parameters/SlashChoice/blend_amount")) > 0.99, "attack clip must not be swapped in the middle of a swing"):
		return
	game.call("_cycle_weapon")
	game.call("_cycle_weapon")
	game.call("_cycle_weapon")
	game.call("_cycle_weapon")
	if not _check(weapon_visuals.current_index == -1 and attack_combat.attack_time_left == 0.0 and not attack_combat.attack_hit_pending, "removing the weapon mid-attack must cancel the attack and its hit"):
		return
	tree.advance(0.2)
	# Running switch: poses blend smoothly, never snapping.
	game.call("_set_locomotion", "Run", true)
	tree.advance(0.3)
	game.call("_sync_weapon_pose", 1.0)
	var arm_idx := rig.find_bone("J_Bip_R_UpperArm")
	var index_idx := rig.find_bone("J_Bip_R_Index2")
	var free_arm := []
	var free_finger := []
	for sample in range(4):
		tree.advance(0.12)
		free_arm.append(rig.get_bone_pose_rotation(arm_idx))
		free_finger.append(rig.get_bone_pose_rotation(index_idx))
	weapon_visuals.equip(0)
	game.call("_update_weapon_display")
	game.call("_sync_weapon_pose", 0.09)
	var half_blend := float(tree.get("parameters/RunArms/blend_amount"))
	if not _check(half_blend > 0.3 and half_blend < 0.7, "weapon pose must blend smoothly on re-equip, not snap: %f" % half_blend):
		return
	game.call("_sync_weapon_pose", 1.0)
	var armed_arm := []
	var armed_finger := []
	for sample in range(4):
		tree.advance(0.12)
		armed_arm.append(rig.get_bone_pose_rotation(arm_idx))
		armed_finger.append(rig.get_bone_pose_rotation(index_idx))
	var arm_difference := 0.0
	var finger_difference := 0.0
	for sample in range(4):
		arm_difference = maxf(arm_difference, (free_arm[sample] as Quaternion).angle_to(armed_arm[sample]))
		finger_difference = maxf(finger_difference, (free_finger[sample] as Quaternion).angle_to(armed_finger[sample]))
	print("Unarmed vs armed Run: right upper arm max diff=", arm_difference, " index finger diff=", finger_difference)
	if not _check(arm_difference > 0.10, "full Run must restore the right-arm swing compared with weapon-safe Run"):
		return
	if not _check(finger_difference > 0.30, "finger grip must switch on at equip and off without a weapon"):
		return
	var free_clip: Animation = animator.get_animation(VROID_ANIM.find_clip(animator, "QuaterniusRunFree"))
	if not _check(free_clip != null and free_clip.length == new_run.length and free_clip.get_track_count() == new_run.get_track_count(), "full Run clip must share phase/length with weapon-safe Run"):
		return
	for index in range(free_clip.get_track_count()):
		if free_clip.track_get_type(index) != Animation.TYPE_ROTATION_3D:
			continue
		var free_path := free_clip.track_get_path(index)
		var free_bone := String(free_path.get_subname(free_path.get_subname_count() - 1))
		if VROID_ANIM.RUN_WEAPON_CARRY_BLEND.has(free_bone):
			continue
		if not _check(free_clip.rotation_track_interpolate(index, 0.3).angle_to(new_run.rotation_track_interpolate(index, 0.3)) < 0.001, "full and weapon-safe Run must differ only in the right arm: " + free_bone):
			return
	if not _check(weapon_visuals.equip(0), "restore Sword I after diagnostics"):
		return
	game.call("_update_weapon_display")
	print("VRoid smoke test OK: 103 bones, ", mesh_count, " mesh nodes, Quaternius Walk/Run, weapon-safe Run right-arm carry, amplified UAL2 attack arcs, preserved VRoid weapon fitting")
	game.queue_free()
	quit(0)


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count
