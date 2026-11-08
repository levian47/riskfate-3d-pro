extends SceneTree

const ANIMATION_BUILDER := preload("res://characters/player/animation_builder.gd")
const MOVEMENT_MATH := preload("res://characters/player/movement_math.gd")
const MOVEMENT_CONTROLLER := preload("res://characters/player/movement_controller.gd")
const COMBAT_CONTROLLER := preload("res://characters/player/combat_controller.gd")
const WEAPON_VISUALS := preload("res://characters/player/weapon_visuals.gd")
const NARUTO_FULL := preload("res://assets/animations/naruto_run_fullbody.tres")

func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	var scene := load("res://main.tscn") as PackedScene
	if not _require(scene != null, "Main scene not loaded"):
		return
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	if not _require(Engine.max_fps == 60, "Engine must read the 60 FPS project limit"):
		return
	var ping_label := game.get_node_or_null("HUD/FPSCounter/Stats/PingLabel") as Label
	if not _require(ping_label != null and ping_label.text == "PING: — (offline)", "Ping must show offline while no game server exists"):
		return
	var fps_label := game.get("fps_label") as Label
	if not _require(fps_label != null and fps_label.text == "FPS: --", "FPS counter should initialize in HUD"):
		return
	game.call("_process", 0.51)
	if not _require(fps_label.text.begins_with("FPS: ") and fps_label.text != "FPS: --", "FPS counter must update from Engine FPS"):
		return
	# The standalone HUD builder must preserve the original scene paths
	# and the desktop fullscreen action; the mobile HUD remains unchanged.
	var hud_panel := game.get_node_or_null("HUD/FPSCounter") as PanelContainer
	if not _require(hud_panel != null and hud_panel.get_node_or_null("Stats/FPSLabel") == fps_label and hud_panel.get_node_or_null("Stats/PingLabel") == ping_label, "HUD counter hierarchy must survive extraction"):
		return
	if not DisplayServer.is_touchscreen_available():
		var fullscreen_control := game.get_node_or_null("HUD/FullscreenButton") as Button
		if not _require(fullscreen_control != null and fullscreen_control.pressed.is_connected(Callable(game, "_toggle_fullscreen")), "Desktop fullscreen callback must survive HUD extraction"):
			return
	# Verify every playable model, including the imported FBX, can be equipped.
	var weapon_component = game.get("weapon_visuals")
	if not _require(weapon_component != null and WEAPON_VISUALS.WEAPONS.size() == 5, "Five test weapons must be available"):
		return
	for index in range(WEAPON_VISUALS.WEAPONS.size()):
		if not _require(bool(weapon_component.call("equip", index)), "Failed to equip weapon index %d" % index):
			return
		var fitted := weapon_component.get("current_visual") as Node3D
		if not _require(fitted != null and int(weapon_component.get("current_index")) == index, "Equipped weapon instance and index must be valid"):
			return
		var measured: AABB = weapon_component.call("_bounds_in_root", fitted)
		var target_length: float = float(WEAPON_VISUALS.WEAPONS[index]["length"])
		if not _require(measured.size.y > 0.1 and absf(measured.size.y * fitted.scale.y - target_length) < 0.02, "Imported weapon must be scaled to expected test length"):
			return
	game.call("_cycle_weapon")
	if not _require(int(weapon_component.get("current_index")) == 0, "Weapon selection must wrap to first model"):
		return
	if not DisplayServer.is_touchscreen_available():
		var help := game.get_node_or_null("HUD/HelpPanel/HelpText") as Label
		if not _require(help != null and help.text.contains("Sword I"), "Desktop HUD must show the selected weapon"):
			return
	else:
		var mobile := game.get("touch_hud") as Control
		if not _require(mobile != null and int(mobile.weapon_index) == 1, "Mobile HUD must show current weapon index"):
			return
	var hero := game.get("hero") as CharacterBody3D
	var tree := game.get("animation_tree") as AnimationTree
	if not _require(hero != null and tree != null and tree.active, "Character and AnimationTree must initialize"):
		return
	# Skeleton inspection must not alter the model or animation; it is a
	# disabled-by-default runtime drawing overlay.
	var debug_rig := WEAPON_VISUALS.find_skeleton(game.get("visual") as Node3D) as Skeleton3D
	var debug_overlay := debug_rig.get_node_or_null("SkeletonDebug") as MeshInstance3D if debug_rig != null else null
	if not _require(debug_overlay != null and debug_overlay.mesh is ImmediateMesh and not debug_overlay.visible, "Skeleton inspection must be available and disabled by default"):
		return
	game.call("_toggle_skeleton_debug")
	await process_frame
	if not _require(debug_overlay.visible and debug_overlay.mesh.get_surface_count() > 0, "Skeleton debug must draw live bone chains when enabled"):
		return
	game.call("_toggle_skeleton_debug")
	if not _require(not debug_overlay.visible, "Skeleton debug must turn off without altering animations"):
		return
	# The camera gains one close zoom step without losing its original 12
	# size and without changing the mobile joystick/attack controls.
	var gameplay_camera := game.get("camera") as Camera3D
	if not _require(gameplay_camera != null and is_equal_approx(gameplay_camera.size, 12.0), "Default camera zoom must remain unchanged"):
		return
	for expected_zoom in [8.0, 6.0, 18.0, 12.0]:
		game.call("_cycle_mobile_zoom")
		if not _require(is_equal_approx(gameplay_camera.size, expected_zoom), "Camera must cycle through four zoom settings, including close-up"):
			return
	if DisplayServer.is_touchscreen_available():
		var mobile_controls := game.get("touch_hud") as Control
		if not _require(int(mobile_controls.zoom_level) == 2 and not bool(mobile_controls.skeleton_enabled), "Mobile skeleton and zoom indicators must reset correctly"):
			return
	# Naruto state must be independently selectable without replacing the
	# previously accepted Run or either sword slash.
	if not _require(NARUTO_FULL != null and NARUTO_FULL.loop_mode == Animation.LOOP_LINEAR and NARUTO_FULL.get_track_count() == 13, "Naruto overlay must contain spine-root Hips and twelve upper-body tracks; legs stay native Ninja Run"):
		return
	var blend := tree.tree_root as AnimationNodeBlendTree
	if not _require(blend != null, "Blend tree missing"):
		return
	var naruto_layer := blend.get_node("NarutoFullBodyBlend") as AnimationNodeBlend2
	if not _require(naruto_layer != null and naruto_layer.filter_enabled and is_equal_approx(float(tree.get("parameters/NarutoFullBodyBlend/blend_amount")), 1.0), "Naruto upper-body layer must be filtered and enabled"):
		return
	# The incompatible Mixamo leg chain previously twisted Ninja shins and feet.
	# Use ONLY upper-body tracks; one native Run drives the entire lower body.
	var naruto_bones: Dictionary = {}
	for track_index in range(NARUTO_FULL.get_track_count()):
		var track_path := NARUTO_FULL.track_get_path(track_index)
		if not _require(NARUTO_FULL.track_get_type(track_index) == Animation.TYPE_ROTATION_3D and track_path.get_subname_count() > 0, "Naruto full-body clip must contain only skeletal rotations"):
			return
		var bone_name := String(track_path.get_subname(track_path.get_subname_count() - 1))
		naruto_bones[bone_name] = true
		if not _require(bone_name in ANIMATION_BUILDER.NARUTO_POSE_BONES, "Naruto overlay must not animate native Ninja legs or foot controls: " + bone_name):
			return
	for bone_name in ANIMATION_BUILDER.NARUTO_POSE_BONES:
		if not _require(naruto_bones.has(bone_name) and naruto_layer.is_path_filtered(NodePath("CharacterArmature/Skeleton3D:" + bone_name)), "Naruto must animate the spine hinge and every upper-body bone: " + bone_name):
			return
	for bone_name in ["Body_2", "UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R", "Foot.L", "Foot.R"]:
		if not _require(not naruto_bones.has(bone_name) and not naruto_layer.is_path_filtered(NodePath("CharacterArmature/Skeleton3D:" + bone_name)), "Naruto must preserve native leg/foot animation: " + bone_name):
			return
	# The Ninja Run input must have a separate branch: Godot rejects connecting
	# the same RunSpeed output to both Locomotion and NarutoUpperBlend.
	if not _require(blend.get_node("NarutoBaseRun") is AnimationNodeAnimation and blend.get_node("NarutoBaseRunSpeed") is AnimationNodeTimeScale, "Naruto layer needs both a connected Run base and connected upper-body overlay"):
		return
	var source_run := ANIMATION_BUILDER.find_clip(game.get("animator") as AnimationPlayer, "Run")
	var run_asset := (game.get("animator") as AnimationPlayer).get_animation(source_run)
	var full_speed := blend.get_node("NarutoFullSpeed") as AnimationNodeTimeScale
	if not _require(full_speed != null and run_asset != null and is_equal_approx(float(tree.get("parameters/NarutoFullSpeed/scale")), NARUTO_FULL.length / run_asset.length), "Naruto full-body loop must match the Ninja Run root/foot stride"):
		return
	var attack := blend.get_node("Attack") as AnimationNodeOneShot
	var animator := game.get("animator") as AnimationPlayer
	if not _require(animator.has_animation("movement_naruto/NarutoRunFull"), "Naruto run must be registered separately"):
		return
	if not _require(not bool(game.get("naruto_run_enabled")), "Classic Run must remain default"):
		return
	game.call("_toggle_naruto_run")
	if not _require(bool(game.get("naruto_run_enabled")), "Naruto mode must toggle on"):
		return
	game.call("_set_locomotion", "Naruto")
	if not _require(String(tree.get("parameters/Locomotion/current_state")) == "Naruto" or String(game.get("locomotion_state")) == "Naruto", "Naruto state must be selectable"):
		return
	game.call("_toggle_naruto_run")
	if not _require(not bool(game.get("naruto_run_enabled")) and String(game.get("locomotion_state")) == "Run", "Turning Naruto mode off must restore the normal Run state"):
		return
	# Regression: the previous Naruto graph had a disconnected Run base.
	# Verify actual skeleton motion, not just selected state/graph metadata.
	var locomotion_skeleton := WEAPON_VISUALS.find_skeleton(game.get("visual") as Node3D) as Skeleton3D
	if not _require(locomotion_skeleton != null and locomotion_skeleton.find_bone("UpperLeg.L") >= 0, "Ninja skeleton needs left upper leg to test Naruto stride"):
		return
	var leg_index := locomotion_skeleton.find_bone("UpperLeg.L")
	var left_hand_index := locomotion_skeleton.find_bone("Fist.L")
	var right_hand_index := locomotion_skeleton.find_bone("Fist.R")
	var torso_index := locomotion_skeleton.find_bone("Torso")
	var hips_index := locomotion_skeleton.find_bone("Hips")
	var upper_left_index := locomotion_skeleton.find_bone("UpperArm.L")
	var upper_right_index := locomotion_skeleton.find_bone("UpperArm.R")
	var elbow_left_index := locomotion_skeleton.find_bone("LowerArm.L")
	var elbow_right_index := locomotion_skeleton.find_bone("LowerArm.R")
	var abdomen_index := locomotion_skeleton.find_bone("Abdomen")
	var neck_index := locomotion_skeleton.find_bone("Neck")
	var head_index := locomotion_skeleton.find_bone("Head")
	if not _require(left_hand_index >= 0 and right_hand_index >= 0 and torso_index >= 0 and hips_index >= 0 and upper_left_index >= 0 and upper_right_index >= 0 and elbow_left_index >= 0 and elbow_right_index >= 0 and abdomen_index >= 0 and neck_index >= 0 and head_index >= 0, "Naruto pose verification requires both fists, torso and head"):
		return
	# Naruto must keep the imported Ninja Run's complete leg/foot cycle.
	# No extra pelvic root displacement, solver or foot target is allowed to
	# override that coherent motion; previous experiments made the hero float.
	for legacy_name in ["NarutoPelvisLowering", "NarutoLegIKL", "NarutoLegIKR", "NarutoFootL", "NarutoFootR"]:
		if not _require(locomotion_skeleton.get_node_or_null(legacy_name) == null, "Naruto sprint must not retain legacy runtime IK modifier " + legacy_name):
			return
	game.set_physics_process(false)
	game.call("_set_locomotion", "Naruto")
	for frame in range(8):
		await physics_frame
	# Compare actual imported animation on bones; leg motion is verified
	# over a full stride below rather than inferred from graph connections.
	var torso_pose := locomotion_skeleton.get_bone_global_pose(torso_index).origin
	var head_pose := locomotion_skeleton.get_bone_global_pose(head_index).origin
	var abdomen_pose := locomotion_skeleton.get_bone_global_pose(abdomen_index).origin
	var neck_pose := locomotion_skeleton.get_bone_global_pose(neck_index).origin
	var spine_direction := neck_pose - abdomen_pose
	var forward_lean_degrees := rad_to_deg(atan2(spine_direction.z, spine_direction.y))
	# The upper spine has its own moderate forward lean. The imported
	# Ninja Run keeps the root, both legs and every foot control.
	if not _require(forward_lean_degrees >= 25.0 and forward_lean_degrees <= 85.0, "Naruto upper spine must stay leaned forward"):
		return
	var hips_pose := locomotion_skeleton.get_bone_global_pose(hips_index).origin
	# Hips is the spine hinge; the root and the complete running leg cycle
	# remain in the original Ninja animation.
	var full_torso_vector := head_pose - hips_pose
	var full_torso_angle := rad_to_deg(atan2(full_torso_vector.z, full_torso_vector.y))
	# Track whole-body lean instead of only the upper spine.
	# The new Naruto pose aims for a forward ~55-degree head-to-pelvis angle.
	if not _require(full_torso_angle >= 34.0 and full_torso_angle <= 55.0, "Naruto must hinge its whole upper body from the hips, not just bend the upper spine"):
		return
	if not _require(head_pose.y > 1.15 and head_pose.z > torso_pose.z + 0.30, "Naruto sprint head must be forward and remain above the ground"):
		return
	# The head remains physically low, but its local forward (+Z) should
	# face near-horizontally along the run, not down into the ground.
	var gaze := locomotion_skeleton.get_bone_global_pose(head_index).basis.z.normalized()
	if not _require(gaze.z > 0.90 and absf(gaze.y) < 0.18, "Naruto face must look forward while the torso leans down"):
		return
	# Attack animation must not override the sprinting spine, head or left arm.
	# Only the weapon arm may play the already approved SweepingSwordSlash.
	var attack_pose_layer := blend.get_node("Attack") as AnimationNodeOneShot
	if not _require(attack_pose_layer != null, "Naruto sword attack layer must exist"):
		return
	for bone_name in ["Abdomen", "Torso", "Neck", "Head", "Shoulder.L", "UpperArm.L", "LowerArm.L", "Fist.L"]:
		if not _require(not attack_pose_layer.is_path_filtered(NodePath("CharacterArmature/Skeleton3D:" + bone_name)), "Naruto strike must preserve running pose: " + bone_name):
			return
	for bone_name in ANIMATION_BUILDER.NARUTO_ATTACK_ARM_BONES:
		if not _require(attack_pose_layer.is_path_filtered(NodePath("CharacterArmature/Skeleton3D:" + bone_name)), "Naruto strike must allow the weapon arm: " + bone_name):
			return

	# Verify an actual weapon strike uses the running pose mask, not only
	# static tree configuration. All other locomotion tests run after abort.
	game.call("_start_attack")
	for frame in range(4):
		await physics_frame
	if not _require(bool(tree.get("parameters/Attack/active")), "Naruto strike must start without leaving the sprint pose"):
		return
	var head_gaze_during_attack := locomotion_skeleton.get_bone_global_pose(head_index).basis.z.normalized()
	if not _require(head_gaze_during_attack.z > 0.90 and absf(head_gaze_during_attack.y) < 0.18, "Naruto strike must not lower the head or override forward gaze"):
		return
	tree.set("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	var sprint_combat := game.get("combat_controller") as RefCounted
	sprint_combat.set("attack_time_left", 0.0)
	sprint_combat.set("attack_hit_pending", false)
	for frame in range(4):
		await physics_frame

	var left_hand_pose := locomotion_skeleton.get_bone_global_pose(left_hand_index).origin
	var right_hand_pose := locomotion_skeleton.get_bone_global_pose(right_hand_index).origin
	var left_shoulder_pose := locomotion_skeleton.get_bone_global_pose(locomotion_skeleton.find_bone("Shoulder.L")).origin
	var right_shoulder_pose := locomotion_skeleton.get_bone_global_pose(locomotion_skeleton.find_bone("Shoulder.R")).origin
	for hand_pose in [left_hand_pose, right_hand_pose]:
		if not _require(hand_pose.y < torso_pose.y - 0.10 and hand_pose.z < torso_pose.z - 0.15, "Naruto hands must still trail low and behind the torso"):
			return
	var hand_width := absf(left_hand_pose.x - right_hand_pose.x)
	var shoulder_width := absf(left_shoulder_pose.x - right_shoulder_pose.x)
	if not _require(hand_width > 1.65 and hand_width > shoulder_width + 1.15, "Naruto hands must stay in a broad V shape"):
		return
	var upper_arm_width := absf(locomotion_skeleton.get_bone_global_pose(upper_left_index).origin.x - locomotion_skeleton.get_bone_global_pose(upper_right_index).origin.x)
	var elbow_width := absf(locomotion_skeleton.get_bone_global_pose(elbow_left_index).origin.x - locomotion_skeleton.get_bone_global_pose(elbow_right_index).origin.x)
	if not _require(upper_arm_width > 0.70 and elbow_width > 1.2, "Naruto shoulders and elbows must fan outward, not pinch inward"):
		return
	# A broad spread must not rotate the collarbones down from the chest.
	var shoulder_left_index := locomotion_skeleton.find_bone("Shoulder.L")
	var shoulder_right_index := locomotion_skeleton.find_bone("Shoulder.R")
	var shoulder_left_height := locomotion_skeleton.get_bone_global_pose(upper_left_index).origin.y - locomotion_skeleton.get_bone_global_pose(shoulder_left_index).origin.y
	var shoulder_right_height := locomotion_skeleton.get_bone_global_pose(upper_right_index).origin.y - locomotion_skeleton.get_bone_global_pose(shoulder_right_index).origin.y
	if not _require(shoulder_left_height > -0.02 and shoulder_right_height > -0.02, "Naruto clavicles must stay level rather than sag below the torso"):
		return
	# Check the silhouette across a full stride, rather than a single frame.
	for phase in range(4):
		for frame in range(5):
			await physics_frame
		var current_hip := locomotion_skeleton.get_bone_global_pose(hips_index).origin
		var current_head := locomotion_skeleton.get_bone_global_pose(head_index).origin
		var current_axis := current_head - current_hip
		var current_angle := rad_to_deg(atan2(current_axis.z, current_axis.y))
		var current_width := absf(locomotion_skeleton.get_bone_global_pose(left_hand_index).origin.x - locomotion_skeleton.get_bone_global_pose(right_hand_index).origin.x)
		if not _require(current_angle >= 34.0 and current_angle <= 55.0 and current_width > 1.65, "Naruto full-body lean and wide arms must survive the whole run cycle"):
			return
	var leg_samples: Array[Quaternion] = []
	for sample in range(4):
		for frame in range(5):
			await physics_frame
		leg_samples.append(locomotion_skeleton.get_bone_pose_rotation(leg_index))
	var leg_motion := 0.0
	for sample in range(1, leg_samples.size()):
		leg_motion = maxf(leg_motion, leg_samples[sample - 1].angle_to(leg_samples[sample]))
	if not _require(leg_motion > 0.01, "Naruto mode must actually animate leg rotations, not slide with frozen pose"):
		return
	game.call("_set_locomotion", "Run")
	# Leaving Naruto must restore every approved attack track.
	for bone_name in ANIMATION_BUILDER.UPPER_BODY_BONES:
		if not _require(attack_pose_layer.is_path_filtered(NodePath("CharacterArmature/Skeleton3D:" + bone_name)), "Standard Run must restore the full approved sword attack: " + bone_name):
			return
	for frame in range(8):
		await physics_frame
	var ordinary_before := locomotion_skeleton.get_bone_pose_rotation(leg_index)
	for frame in range(8):
		await physics_frame
	var ordinary_after := locomotion_skeleton.get_bone_pose_rotation(leg_index)
	if not _require(ordinary_before.angle_to(ordinary_after) > 0.01, "Normal Run stride must still animate after Naruto mode"):
		return
	game.call("_set_locomotion", "Idle")
	game.set_physics_process(true)
	var combat_state := game.get("combat_controller") as RefCounted
	if not _require(combat_state != null, "Combat state must be owned by the dedicated player combat controller"):
		return
	if not _require(is_equal_approx(float(COMBAT_CONTROLLER.ATTACK_SPEED), 1.65) and int(COMBAT_CONTROLLER.TRAINING_HIT_DAMAGE) == 25, "Attack speed and provisional damage must remain unchanged"):
		return
	if not _require(attack != null and animator != null and attack.filter_enabled, "Upper-body attack layer missing"):
		return

	# Animation graph ownership moved out of main.gd without changing
	# clip names, upper-body masking or the selected test attack.
	if not _require(is_equal_approx(float(tree.get("parameters/AttackSpeed/scale")), 1.65), "Animation builder must preserve the accepted sword attack speed"):
		return
	for state in ["Idle", "Walk", "Run"]:
		var loop_name: String = ANIMATION_BUILDER.find_clip(animator, state)
		if not _require(not loop_name.is_empty() and animator.get_animation(loop_name).loop_mode == Animation.LOOP_LINEAR, "Movement loops must survive animation builder extraction: " + state):
			return
	var sword_name := ""
	for name in animator.get_animation_list():
		if String(name) == "SwordSlash" or String(name).ends_with("/SwordSlash"):
			sword_name = String(name)
			break
	if not _require(not sword_name.is_empty(), "SwordSlash missing"):
		return
	var clip := animator.get_animation(sword_name)
	var arm_found := false
	var leg_found := false
	for i in range(clip.get_track_count()):
		var path := clip.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		var bone := String(path.get_subname(path.get_subname_count() - 1))
		if bone == "UpperArm.R":
			arm_found = attack.is_path_filtered(path)
		elif bone == "UpperLeg.R":
			leg_found = attack.is_path_filtered(path)
	if not _require(arm_found and not leg_found, "Attack must affect arms, not legs"):
		return

	# Only the original back-facing combat clip remains after initialization.
	if not _require(animator.has_animation("combat_mirror/WideSwordSlashMirror"), "Preferred back-facing sword slash must exist"):
		return
	if not _require(not animator.has_animation("combat/WideSwordSlash") and not blend.has_node("SwordDirection") and not blend.has_node("AttackSeek"), "Unused slash and direction selectors must be removed"):
		return
	# Preserve the accepted standard as an independent, inactive clip.
	# This build tests the new sweeping attack without a gameplay selector.
	if not _require(animator.has_animation("combat_sweeping/SweepingSwordSlash"), "Sweeping sword clip must exist"):
		return
	var sweeping_clip := animator.get_animation("combat_sweeping/SweepingSwordSlash")
	var standard_clip := animator.get_animation("combat_mirror/WideSwordSlashMirror")
	# Guard against returning to expensive runtime pose reconstruction.
	var standard_file := load("res://assets/animations/standard_sword_slash.tres") as Animation
	var sweeping_file := load("res://assets/animations/sweeping_sword_slash.tres") as Animation
	if not _require(standard_file != null and sweeping_file != null and standard_clip == standard_file and sweeping_clip == sweeping_file, "Both combat clips must load directly from their individual Godot resources"):
		return
	if not _require(standard_clip != null and sweeping_clip != null and standard_clip != sweeping_clip and is_equal_approx(standard_clip.length, sweeping_clip.length), "Standard and sweeping clips must be independent and match timing"):
		return
	if not _require(not blend.has_node("AttackVariant") and not blend.has_node("SwordDirection") and not blend.has_node("AttackSeek"), "Only the sweeping attack may be wired for playtest"):
		return
	var standard_shoulder_track := -1
	var sweeping_shoulder_track := -1
	for i in range(standard_clip.get_track_count()):
		if standard_clip.track_get_type(i) == Animation.TYPE_ROTATION_3D and String(standard_clip.track_get_path(i)).ends_with("Shoulder.R"):
			standard_shoulder_track = i
			break
	for i in range(sweeping_clip.get_track_count()):
		if sweeping_clip.track_get_type(i) == Animation.TYPE_ROTATION_3D and String(sweeping_clip.track_get_path(i)).ends_with("Shoulder.R"):
			sweeping_shoulder_track = i
			break
	if not _require(standard_shoulder_track >= 0 and sweeping_shoulder_track >= 0, "Both clips must keep separate shoulder tracks"):
		return
	var distinct_keys := 0
	for i in range(mini(standard_clip.track_get_key_count(standard_shoulder_track), sweeping_clip.track_get_key_count(sweeping_shoulder_track))):
		var original_pose: Quaternion = standard_clip.track_get_key_value(standard_shoulder_track, i)
		var new_pose: Quaternion = sweeping_clip.track_get_key_value(sweeping_shoulder_track, i)
		if original_pose.angle_to(new_pose) > 0.05:
			distinct_keys += 1
	if not _require(distinct_keys > 8, "New wide ascending attack must differ materially from standard"):
		return
	var original_clip := animator.get_animation(sword_name)
	var wide_clip := animator.get_animation("combat_mirror/WideSwordSlashMirror")
	if not _require(wide_clip != original_clip and is_equal_approx(wide_clip.length, original_clip.length) , "Combat clips must preserve timing"):
		return
	var arm_source := -1
	var arm_wide := -1
	for i in range(original_clip.get_track_count()):
		var track_path := original_clip.track_get_path(i)
		if original_clip.track_get_type(i) == Animation.TYPE_ROTATION_3D and track_path.get_subname_count() > 0 and String(track_path.get_subname(track_path.get_subname_count() - 1)) == "UpperArm.R":
			arm_source = i
			break
	for i in range(wide_clip.get_track_count()):
		var track_path := wide_clip.track_get_path(i)
		if wide_clip.track_get_type(i) == Animation.TYPE_ROTATION_3D and track_path.get_subname_count() > 0 and String(track_path.get_subname(track_path.get_subname_count() - 1)) == "UpperArm.R":
			arm_wide = i
			break
	if not _require(arm_source >= 0 and arm_wide >= 0, "Right upper arm tracks must exist"):
		return
	var source_base: Quaternion = original_clip.track_get_key_value(arm_source, 0)
	var wide_base: Quaternion = wide_clip.track_get_key_value(arm_wide, 0)
	var source_max := 0.0
	var wide_max := 0.0
	var added_swing := 0.0
	for key in range(original_clip.track_get_key_count(arm_source)):
		var q: Quaternion = original_clip.track_get_key_value(arm_source, key)
		source_max = maxf(source_max, source_base.angle_to(q))
	for key in range(wide_clip.track_get_key_count(arm_wide)):
		var q: Quaternion = wide_clip.track_get_key_value(arm_wide, key)
		wide_max = maxf(wide_max, wide_base.angle_to(q))
		if key < original_clip.track_get_key_count(arm_source):
			var original_key: Quaternion = original_clip.track_get_key_value(arm_source, key)
			var previous_angle := source_base.angle_to(original_key) * (130.0 / 90.0)
			added_swing = maxf(added_swing, wide_base.angle_to(q) - previous_angle)
	if not _require(source_max > 0.05 and added_swing > 0.10 and wide_max <= deg_to_rad(171.0), "Original arm widening must remain intact"):
		return
	# The re-authored sword arc should be smooth rather than an overhead pose.
	var shoulder_wide := -1
	for i in range(wide_clip.get_track_count()):
		var path := wide_clip.track_get_path(i)
		if wide_clip.track_get_type(i) == Animation.TYPE_ROTATION_3D and path.get_subname_count() > 0:
			if String(path.get_subname(path.get_subname_count() - 1)) == "Shoulder.R":
				shoulder_wide = i
				break
	if not _require(shoulder_wide >= 0, "Horizontal slash requires a generated shoulder track"):
		return
	if not _require(wide_clip.track_get_key_count(shoulder_wide) >= 20, "Shoulder swing must have enough samples"):
		return
	var first_q: Quaternion = wide_clip.track_get_key_value(shoulder_wide, 0)
	var last_q: Quaternion = wide_clip.track_get_key_value(shoulder_wide, wide_clip.track_get_key_count(shoulder_wide) - 1)
	if not _require(first_q.angle_to(Quaternion.IDENTITY) < 0.01 and last_q.angle_to(Quaternion.IDENTITY) < 0.01, "Horizontal slash must return to the rest shoulder pose"):
		return
	var previous_q: Quaternion = first_q
	for i in range(1, wide_clip.track_get_key_count(shoulder_wide)):
		var adjusted_q: Quaternion = wide_clip.track_get_key_value(shoulder_wide, i)
		var step_angle := rad_to_deg(previous_q.angle_to(adjusted_q))
		if step_angle > 46.0:
			print("Horizontal slash diagnostic: shoulder step ", i, ", time ", wide_clip.track_get_key_time(shoulder_wide, i), ", delta degrees ", step_angle)
		if not _require(step_angle < 120.0, "Horizontal slash rotation must not jump by 120+ degrees"):
			return
		previous_q = adjusted_q

	var attack_node := blend.get_node("SwordSlash") as AnimationNodeAnimation
	if not _require(attack_node != null and String(attack_node.animation) == "combat_sweeping/SweepingSwordSlash", "Active attack must be the new sweeping clip"):
		return

	game.call("_set_locomotion", "Run")
	game.call("_start_attack")
	await process_frame
	if not _require(float(combat_state.get("attack_time_left")) > 0.0, "Attack must begin"):
		return
	if not _require(String(tree.get("parameters/Locomotion/current_state")) == "Run", "Running animation must remain active during attack"):
		return
	game.call("_set_locomotion", "Jump")
	await process_frame
	if not _require(String(tree.get("parameters/Locomotion/current_state")) == "Jump", "Jump animation must remain selectable during attack"):
		return

	# Isolated movement helper must preserve exact camera-relative steering,
	# jump release, ground reset and imported model facing correction.
	var camera_for_movement := game.get("camera") as Camera3D
	var camera_right := camera_for_movement.global_transform.basis.x
	camera_right.y = 0.0
	var expected_right := camera_right.normalized()
	var actual_right := MOVEMENT_MATH.camera_relative_direction(camera_for_movement, Vector2.RIGHT)
	if not _require(actual_right.distance_to(expected_right) < 0.001, "Extracted movement must preserve camera-right steering"):
		return
	var physics_body := CharacterBody3D.new()
	physics_body.velocity.y = 4.0
	MOVEMENT_MATH.apply_vertical_velocity(physics_body, false, false, false, 0.1, 8.0, 22.0, 0.55)
	if not _require(absf(physics_body.velocity.y - (4.0 - 22.0 * 0.1 / 0.55)) < 0.001, "Jump release must preserve early-release gravity"):
		return
	var jumped := MOVEMENT_MATH.apply_vertical_velocity(physics_body, true, true, true, 0.016, 8.0, 22.0, 0.55)
	if not _require(jumped and is_equal_approx(physics_body.velocity.y, 8.0), "Buffered jump must preserve takeoff velocity"):
		return
	MOVEMENT_MATH.apply_vertical_velocity(physics_body, true, false, false, 0.016, 8.0, 22.0, 0.55)
	if not _require(is_equal_approx(physics_body.velocity.y, -0.1), "Grounded vertical reset must remain unchanged"):
		return
	physics_body.free()
	var test_visual := Node3D.new()
	MOVEMENT_MATH.apply_facing(test_visual, Vector3.FORWARD)
	if not _require(absf(test_visual.rotation.y - PI) < 0.001, "Imported rig facing correction must remain unchanged"):
		return
	test_visual.free()

	# Movement state must be owned by its component after extraction.
	var movement_state := game.get("movement_controller") as RefCounted
	if not _require(movement_state != null, "Player movement controller must initialize"):
		return
	if not _require(is_equal_approx(float(MOVEMENT_CONTROLLER.WALK_SPEED), 7.0) and is_equal_approx(float(MOVEMENT_CONTROLLER.RUN_SPEED), 12.0), "Approved movement speeds must remain unchanged"):
		return
	# Direction reversal and stopping must be immediate, without braking inertia.
	var touch_controls = load("res://touch_hud.gd").new()
	root.add_child(touch_controls)
	touch_controls.size = Vector2(1280.0, 720.0)
	game.set("touch_hud", touch_controls)
	touch_controls.move_vector = Vector2.RIGHT
	game.call("_physics_process", 1.0 / 60.0)
	var right_velocity := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	touch_controls.move_vector = Vector2.LEFT
	game.call("_physics_process", 1.0 / 60.0)
	var left_velocity := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	if not _require(right_velocity.length() > 10.0 and left_velocity.distance_to(-right_velocity) < 0.05, "Steering must reverse immediately"):
		return
	if not _require(movement_state.get("last_move_direction") is Vector3 and (movement_state.get("last_move_direction") as Vector3).length() > 0.99, "Movement controller must retain the most recent direction for dash fallback"):
		return
	touch_controls.move_vector = Vector2.ZERO
	game.call("_physics_process", 1.0 / 60.0)
	if not _require(Vector2(hero.velocity.x, hero.velocity.z).length() < 0.05, "Releasing joystick must stop immediately"):
		return

	var layout: Dictionary = touch_controls.call("_layout")
	var jump_center: Vector2 = layout["jump"]
	var dash_center: Vector2 = layout["dash"]
	var attack_center: Vector2 = layout["attack"]
	if not _require(jump_center.y > dash_center.y and jump_center.y > attack_center.y, "Jump must be below dash and attack"):
		return
	touch_controls.dash_requested.connect(Callable(game, "_start_dash"))
	touch_controls.move_vector = Vector2.RIGHT
	touch_controls.call("_press", 37, dash_center)
	if not _require(int(touch_controls.get("dash_finger")) == 37 and float(movement_state.get("dash_time_left")) > 0.0, "Dash button must trigger dash"):
		return
	touch_controls.call("_release", 37)
	if not _require(int(touch_controls.get("dash_finger")) == -1, "Dash touch must release cleanly"):
		return
	var original_cooldown := float(movement_state.get("dash_cooldown_left"))
	game.call("_start_dash")
	if not _require(is_equal_approx(float(movement_state.get("dash_cooldown_left")), original_cooldown), "Dash cooldown must reject immediate second press"):
		return
	touch_controls.move_vector = Vector2.ZERO

	# Stationary combat target: front-facing reach, once per swing, HP and reset.
	var dummy := game.get_node_or_null("Environment/TrainingDummy")
	if not _require(dummy != null and int(dummy.get("hp")) == 100, "Training dummy must spawn with 100 HP"):
		return
	var original_position := hero.global_position
	var visual_node := game.get("visual") as Node3D
	var original_rotation: float = visual_node.rotation.y
	hero.global_position = Vector3(0, 0.2, 5.1)
	visual_node.rotation.y = 0.0
	game.call("_resolve_training_hit")
	if not _require(int(dummy.get("hp")) == 75 and dummy.get_node("HealthLabel").text == "HP 75 / 100", "Facing target in reach should lose 25 HP"):
		return
	visual_node.rotation.y = PI
	game.call("_resolve_training_hit")
	if not _require(int(dummy.get("hp")) == 75, "Back-facing attack must not deal damage"):
		return
	visual_node.rotation.y = 0.0
	hero.global_position = Vector3(0, 0.2, 0)
	game.call("_resolve_training_hit")
	if not _require(int(dummy.get("hp")) == 75, "Out-of-range attack must not deal damage"):
		return
	hero.global_position = Vector3(0, 0.2, 5.1)
	dummy.take_damage(75)
	if not _require(int(dummy.get("hp")) == 0 and not bool(dummy.get("is_available")), "Target must become inactive at 0 HP"):
		return
	game.call("_resolve_training_hit")
	if not _require(int(dummy.get("hp")) == 0, "Destroyed dummy must not accept additional hits"):
		return
	dummy.call("_process", 2.6)
	if not _require(int(dummy.get("hp")) == 100 and bool(dummy.get("is_available")), "Training dummy must respawn"):
		return

	# The refactored combat timer must retain the approved moment of impact.
	# Repeated input cannot restart the swing or deal damage twice.
	combat_state.set("attack_time_left", 0.0)
	game.call("_start_attack")
	var full_attack_duration := float(combat_state.get("attack_duration"))
	if not _require(full_attack_duration > 0.0 and is_equal_approx(full_attack_duration, animator.get_animation(sword_name).length / COMBAT_CONTROLLER.ATTACK_SPEED), "Combat controller must retain original attack duration"):
		return
	game.call("_start_attack")
	if not _require(is_equal_approx(float(combat_state.get("attack_time_left")), full_attack_duration), "Repeated attack input must not restart the active swing"):
		return
	var before_hit := full_attack_duration * COMBAT_CONTROLLER.TRAINING_HIT_MOMENT - 0.001
	combat_state.physics_step(before_hit, game, hero, visual_node)
	if not _require(int(dummy.get("hp")) == 100 and bool(combat_state.get("attack_hit_pending")), "Attack must not hit before the existing impact frame"):
		return
	combat_state.physics_step(0.002, game, hero, visual_node)
	if not _require(int(dummy.get("hp")) == 75 and not bool(combat_state.get("attack_hit_pending")), "Impact frame must deal exactly 25 damage once"):
		return
	combat_state.physics_step(0.02, game, hero, visual_node)
	if not _require(int(dummy.get("hp")) == 75, "One swing must not damage the same target twice"):
		return
	dummy.take_damage(75)
	dummy.call("_process", 2.6)
	if not _require(int(dummy.get("hp")) == 100, "Target must reset after combat timing test"):
		return
	hero.global_position = original_position
	visual_node.rotation.y = original_rotation

	var environment := game.get_node_or_null("Environment/Ground")
	if not _require(environment is StaticBody3D, "World ground missing"):
		return
	var collision := environment.get_node("CollisionShape3D") as CollisionShape3D
	if not _require(collision != null and (collision.shape as BoxShape3D).size.x >= 200.0, "Expanded terrain missing"):
		return
	# The new sweeping variant is the only live attack for this visual test.
	# The approved standard remains available in AnimationPlayer.
	game.set_physics_process(false)
	var view_camera := game.get("camera") as Camera3D
	var skel := WEAPON_VISUALS.find_skeleton(visual_node) as Skeleton3D
	var sword_grip := skel.get_node_or_null("SwordGrip/WeaponMount") as Node3D
	if not _require(view_camera != null and sword_grip != null, "Camera and sword attachment must exist"):
		return
	var view_right := view_camera.global_transform.basis.x.normalized()
	if not _require(attack_node != null and String(attack_node.animation) == "combat_sweeping/SweepingSwordSlash", "OneShot must test sweeping clip only"):
		return

	# The camera is at +X,+Z. PI rotates the hero's back toward the camera.
	visual_node.rotation.y = PI
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.set("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.advance(0.01)
	game.call("_set_locomotion", "Idle", true)
	tree.advance(0.15)
	combat_state.set("attack_time_left", 0.0)
	game.call("_start_attack")
	if not _require(float(combat_state.get("attack_time_left")) > 0.0, "Back-facing strike must start"):
		return
	var back_screen: Array[float] = []
	var last_fraction := 0.0
	var swing_duration: float = float(combat_state.get("attack_duration"))
	for fraction in [0.16, 0.24, 0.32, 0.40, 0.48, 0.56, 0.64]:
		tree.advance(swing_duration * (fraction - last_fraction))
		last_fraction = fraction
		await process_frame
		back_screen.append(view_right.dot(sword_grip.to_global(Vector3(0.0, 1.305, 0.0))))
	print("Single sword slash / back-facing screen positions: ", back_screen)
	if not _require(back_screen[3] - back_screen[back_screen.size() - 1] > 1.0, "Sweeping attack must cross right-to-left on screen"):
		return

	# Sample actual blade-tip 3D positions in both generated clips.
	# Ascending and wider must be verified in the rig, not assumed from angles.
	tree.active = false
	var standard_tips: Array[Vector3] = []
	var sweeping_tips: Array[Vector3] = []
	for clip_to_check in [standard_clip, sweeping_clip]:
		var points: Array[Vector3] = []
		var sampled_name := "combat_mirror/WideSwordSlashMirror" if clip_to_check == standard_clip else "combat_sweeping/SweepingSwordSlash"
		animator.play(sampled_name)
		for fraction in [0.20, 0.32, 0.44, 0.56, 0.64]:
			animator.seek(clip_to_check.length * fraction, true)
			await process_frame
			points.append(visual_node.to_local(sword_grip.to_global(Vector3(0.0, 1.305, 0.0))))
		if clip_to_check == standard_clip:
			standard_tips = points
		else:
			sweeping_tips = points
	animator.stop()
	tree.active = true
	# Inspect startup pose and early frame continuity; the old sweeping
	# clip inherited a high initial pose from the imported SwordSlash.
	var start_traces: Dictionary = {}
	for clip_name in ["combat_mirror/WideSwordSlashMirror", "combat_sweeping/SweepingSwordSlash"]:
		var sampled_clip := animator.get_animation(clip_name)
		var first_positions: Array[Vector3] = []
		animator.play(clip_name)
		for fraction in [0.0, 0.04, 0.08, 0.12, 0.16, 0.20]:
			animator.seek(sampled_clip.length * fraction, true)
			await process_frame
			first_positions.append(visual_node.to_local(sword_grip.to_global(Vector3(0.0, 1.305, 0.0))))
		start_traces[clip_name] = first_positions
	animator.stop()
	var standard_start: Array[Vector3] = start_traces["combat_mirror/WideSwordSlashMirror"]
	var sweeping_start: Array[Vector3] = start_traces["combat_sweeping/SweepingSwordSlash"]
	print("Standard early sword positions: ", standard_start)
	print("Sweeping early sword positions: ", sweeping_start)
	var early_max_step := 0.0
	for step in range(1, sweeping_start.size()):
		early_max_step = maxf(early_max_step, sweeping_start[step].distance_to(sweeping_start[step - 1]))
	print("Sweeping early maximum 4%-interval sword travel: ", early_max_step)
	var sweeping_early_high := -INF
	for point in sweeping_start:
		sweeping_early_high = maxf(sweeping_early_high, point.y)
	if not _require(sweeping_early_high < 2.05 and sweeping_start[1].y < standard_start[1].y - 0.8, "Sweeping strike must start low rather than inherit the imported overhead pose"):
		return
	if not _require(early_max_step < 0.65, "Sweeping first frames must not have sudden jumps"):
		return
	print("Standard sword tip positions in hero local space: ", standard_tips)
	print("Sweeping sword tip positions in hero local space: ", sweeping_tips)
	# Visual acceptance baseline before conversion to .tres resources.
	# A change here means the baked clips no longer reproduce approved poses.
	if not _require(standard_tips[0].distance_to(Vector3(-1.924545, 2.295721, 1.238922)) < 0.04, "Standard approved sword pose changed during resource migration"):
		return
	if not _require(sweeping_tips[0].distance_to(Vector3(-2.201129, 1.863062, 0.963700)) < 0.04, "Sweeping approved sword pose changed during resource migration"):
		return
	var standard_min_x := INF
	var standard_max_x := -INF
	var sweeping_min_x := INF
	var sweeping_max_x := -INF
	for point in standard_tips:
		standard_min_x = minf(standard_min_x, point.x)
		standard_max_x = maxf(standard_max_x, point.x)
	for point in sweeping_tips:
		sweeping_min_x = minf(sweeping_min_x, point.x)
		sweeping_max_x = maxf(sweeping_max_x, point.x)
	var standard_span := standard_max_x - standard_min_x
	var sweeping_span := sweeping_max_x - sweeping_min_x
	print("Sword horizontal spans: Standard=", standard_span, ", Sweeping=", sweeping_span)
	if not _require(sweeping_span > standard_span + 0.25, "Sweeping swing must actually cover a wider horizontal span"):
		return
	if not _require(sweeping_tips[sweeping_tips.size() - 1].y - sweeping_tips[0].y > 0.30, "Sweeping swing must clearly rise across the cut"):
		return

	# Test a freshly spawned hero through the real AnimationTree and
	# OneShot fade. Clip-only checks do not reveal a high idle-to-attack blend.
	var fresh_game := scene.instantiate()
	root.add_child(fresh_game)
	await process_frame
	fresh_game.set_physics_process(false)
	var fresh_visual := fresh_game.get("visual") as Node3D
	fresh_visual.rotation.y = PI
	var fresh_tree := fresh_game.get("animation_tree") as AnimationTree
	fresh_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var fresh_skeleton := WEAPON_VISUALS.find_skeleton(fresh_visual) as Skeleton3D
	var fresh_sword := fresh_skeleton.get_node_or_null("SwordGrip/WeaponMount") as Node3D
	# Let the newly created AnimationTree evaluate Idle before the OneShot.
	# This mirrors a character that has actually stood still in the game.
	fresh_tree.advance(0.15)
	await process_frame
	print("Fresh hero stabilized idle sword position: ", fresh_visual.to_local(fresh_sword.to_global(Vector3(0.0, 1.305, 0.0))))
	var fresh_combat_state := fresh_game.get("combat_controller") as RefCounted
	fresh_game.call("_start_attack")
	var blended_start_trace: Array[Vector3] = []
	var previous_fraction := 0.0
	var attack_period := float(fresh_combat_state.get("attack_duration"))
	for fraction in [0.0, 0.04, 0.08, 0.12, 0.16, 0.20]:
		fresh_tree.advance(attack_period * (fraction - previous_fraction))
		previous_fraction = fraction
		await process_frame
		blended_start_trace.append(fresh_visual.to_local(fresh_sword.to_global(Vector3(0.0, 1.305, 0.0))))
	print("Fresh hero blended sweeping start positions: ", blended_start_trace)
	fresh_game.queue_free()

	# Turning the hero must not change the selected test attack.
	# The same sweeping animation runs from every orientation.
	tree.set("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.advance(0.01)
	visual_node.rotation.y = 0.0
	combat_state.set("attack_time_left", 0.0)
	game.call("_start_attack")
	tree.advance(0.02)
	if not _require(float(combat_state.get("attack_time_left")) > 0.0 and bool(tree.get("parameters/Attack/active")), "Same sword slash must start when hero turns around"):
		return

	# Three Ninja material candidates must preserve the same skeleton and
	# animations while changing only render surfaces. Switching in-place
	# avoids destroying AnimationTree and the approved sword attachment.
	var candidate_mesh := game.get("ninja_mesh") as MeshInstance3D
	var candidates: Array = game.get("ninja_mesh_variants")
	if not _require(candidate_mesh != null and candidates.size() == 3, "Original/A/B mesh candidates must be available"):
		return
	for case_index in range(3):
		var candidate := candidates[case_index] as Mesh
		var expected_surfaces := 1 if case_index == 2 else 6
		if not _require(candidate != null and candidate.get_surface_count() == expected_surfaces, "Ninja material candidate surface count should be 6/6/1"):
			return
		if not _require(candidate.surface_get_array_len(0) > 0, "Every material candidate must have vertices"):
			return
	var orig_mat := (candidates[0] as Mesh).surface_get_material(0) as BaseMaterial3D
	var a_mat := (candidates[1] as Mesh).surface_get_material(0) as BaseMaterial3D
	var b_mat := (candidates[2] as Mesh).surface_get_material(0) as StandardMaterial3D
	if not _require(orig_mat != null and a_mat != null and orig_mat.cull_mode == BaseMaterial3D.CULL_DISABLED and a_mat.cull_mode == BaseMaterial3D.CULL_BACK, "A must enable backface culling while Original remains double-sided"):
		return
	if not _require(b_mat != null and b_mat.cull_mode == BaseMaterial3D.CULL_BACK and b_mat.vertex_color_use_as_albedo and not b_mat.vertex_color_is_srgb, "B must use linear-space vertex colors with backface culling"):
		return
	var b_arrays: Array = (candidates[2] as Mesh).surface_get_arrays(0)
	if not _require(b_arrays[Mesh.ARRAY_VERTEX].size() == 9948 and b_arrays[Mesh.ARRAY_INDEX].size() == 21312 and b_arrays[Mesh.ARRAY_COLOR].size() == 9948, "B must preserve all 7104 triangles and provide a color for every vertex"):
		return
	if not _require(int(game.get("material_variant_index")) == 1 and candidate_mesh.mesh == candidates[1], "Ninja must load approved A at startup"):
		return
	for expected in [0, 1]:
		game.call("_cycle_ninja_materials")
		if not _require(int(game.get("material_variant_index")) == expected and candidate_mesh.mesh == candidates[expected], "Ninja material switching must preserve the original animated mesh node"):
			return
	if DisplayServer.is_touchscreen_available():
		var material_touch := game.get("touch_hud") as Control
		if not _require(int(material_touch.material_variant) == 1, "Mobile material indicator must show approved A"):
			return
	# Full automated benchmark state matrix: every supported crowd size,
	# every profiling mode and both approved material choices. This checks
	# animation/shadow/geometry state and UI wiring, not actual device FPS.
	var crowd_atlas := game.get("crowd_atlas_mesh") as Mesh
	if not _require(crowd_atlas != null and crowd_atlas.get_surface_count() == 1, "Crowd atlas must have one surface instead of six"):
		return
	var atlas_mat := crowd_atlas.surface_get_material(0) as StandardMaterial3D
	if not _require(atlas_mat != null and atlas_mat.albedo_texture != null, "Crowd atlas must preserve six colors through a real color texture"):
		return
	var atlas_uv := crowd_atlas.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	if not _require(atlas_uv.size() == 9948, "Crowd atlas UVs must cover every original skinned vertex"):
		return
	var bench = game.get("crowd_benchmark")
	var bench_button := game.get_node_or_null("HUD/CrowdBenchmarkButton") as Button
	var mode_button := game.get_node_or_null("HUD/CrowdModeButton") as Button
	var draw_stats := game.get_node_or_null("HUD/CrowdDrawStats") as Label
	if not _require(bench != null and bench_button != null and mode_button != null and draw_stats != null, "Benchmark and diagnostic HUD controls must exist"):
		return
	if not _require(bench_button.text == "LOAD 0" and mode_button.text == "MODE RUN" and not draw_stats.visible, "Crowd diagnostics must start disabled"):
		return
	if not _require(bench_button.pressed.is_connected(Callable(game, "_cycle_crowd_benchmark")) and mode_button.pressed.is_connected(Callable(game, "_cycle_crowd_mode")), "Crowd diagnostic buttons must be wired to real callbacks"):
		return
	var matrix_cases := 0
	for count in [10, 30, 60, 100, 0]:
		bench_button.pressed.emit()
		var actor_nodes: Array = bench.get("actors")
		var crowd_meshes: Array = bench.get("mesh_nodes")
		var animation_players: Array = bench.get("players")
		var original_shadows: Array = bench.get("original_shadows")
		if not _require(actor_nodes.size() == count and crowd_meshes.size() == count and animation_players.size() == count and original_shadows.size() == count and bench_button.text == "LOAD %d" % count, "All crowd arrays and LOAD text must match %d" % count):
			return
		if count == 0:
			if not _require(not draw_stats.visible and is_equal_approx(gameplay_camera.size, 12.0), "LOAD 0 must hide draw stats and restore camera size"):
				return
			continue
		if not _require(draw_stats.visible and is_equal_approx(gameplay_camera.size, 40.0), "Active crowd must show draw stats and use wide camera"):
			return
		# Renderer stats are updated by the normal HUD tick. Values may be zero
		# under headless Godot and are intentionally not used as a GPU benchmark.
		game.call("_process", 0.51)
		if not _require(draw_stats.text.begins_with("Draws: ") and draw_stats.text.contains("shadow"), "Visible and shadow draw counters must update"):
			return
		for mode_name in ["RUN", "PAUSE", "HIDE", "NO SHADOW"]:
			if mode_name != "RUN":
				mode_button.pressed.emit()
			if not _require(mode_button.text == "MODE %s" % mode_name, "MODE control must enter %s" % mode_name):
				return
			for material_index in [0, 1]:
				game.call("_cycle_ninja_materials")
				if not _require(int(game.get("material_variant_index")) == material_index and candidate_mesh.mesh == candidates[material_index], "Hero material must match A/O control during %s" % mode_name):
					return
				for i in range(count):
					var crowd_mesh := crowd_meshes[i] as MeshInstance3D
					var crowd_player := animation_players[i] as AnimationPlayer
					var expected_shadow := int(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) if mode_name == "NO SHADOW" else int(original_shadows[i])
					if not _require(crowd_mesh != null and crowd_player != null and crowd_mesh.mesh == crowd_atlas, "All %d crowd meshes must use one-surface atlas while hero is MAT %d" % [count, material_index]):
						return
					if not _require(crowd_mesh.visible == (mode_name != "HIDE") and crowd_player.is_playing() == (mode_name != "PAUSE") and int(crowd_mesh.cast_shadow) == expected_shadow, "Crowd actor %d failed %s/MAT %d at LOAD %d" % [i, mode_name, material_index, count]):
						return
				matrix_cases += 1
		# Cycling after NO SHADOW must restore original shadow settings.
		mode_button.pressed.emit()
		if not _require(mode_button.text == "MODE RUN" and int((crowd_meshes[0] as MeshInstance3D).cast_shadow) == int(original_shadows[0]), "RUN must restore shadows after NO SHADOW"):
			return
	if not _require(matrix_cases == 32 and int(game.get("material_variant_index")) == 1, "Benchmark must cover all 32 nonzero crowd/mode/material combinations and return to A"):
		return
	print("Crowd atlas matrix passed: 4 loads x 4 modes x 2 hero materials; 1 surface and 6 palette colors preserved; LOAD 0 cleanup.")
	print("Gameplay smoke test passed: independent baked sword resources retain approved poses; active Sweeping, movement, dash, world, training hits, HP and respawn.")
	quit(0)

func _require(value: bool, message: String) -> bool:
	if not value:
		push_error("Gameplay smoke test: " + message)
		quit(1)
	return value
