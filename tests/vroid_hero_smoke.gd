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
