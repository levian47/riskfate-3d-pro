extends SceneTree

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
	var hero := game.get("hero") as CharacterBody3D
	var tree := game.get("animation_tree") as AnimationTree
	if not _require(hero != null and tree != null and tree.active, "Character and AnimationTree must initialize"):
		return
	var blend := tree.tree_root as AnimationNodeBlendTree
	if not _require(blend != null, "Blend tree missing"):
		return
	var attack := blend.get_node("Attack") as AnimationNodeOneShot
	var animator := game.get("animator") as AnimationPlayer
	if not _require(attack != null and animator != null and attack.filter_enabled, "Upper-body attack layer missing"):
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
	if not _require(float(game.get("attack_time_left")) > 0.0, "Attack must begin"):
		return
	if not _require(String(tree.get("parameters/Locomotion/current_state")) == "Run", "Running animation must remain active during attack"):
		return
	game.call("_set_locomotion", "Jump")
	await process_frame
	if not _require(String(tree.get("parameters/Locomotion/current_state")) == "Jump", "Jump animation must remain selectable during attack"):
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
	if not _require(int(touch_controls.get("dash_finger")) == 37 and float(game.get("dash_time_left")) > 0.0, "Dash button must trigger dash"):
		return
	touch_controls.call("_release", 37)
	if not _require(int(touch_controls.get("dash_finger")) == -1, "Dash touch must release cleanly"):
		return
	var original_cooldown := float(game.get("dash_cooldown_left"))
	game.call("_start_dash")
	if not _require(is_equal_approx(float(game.get("dash_cooldown_left")), original_cooldown), "Dash cooldown must reject immediate second press"):
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
	var skel := game.call("_find_skeleton", visual_node) as Skeleton3D
	var sword_grip := skel.get_node_or_null("SwordGrip/SimpleSword") as Node3D
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
	game.set("attack_time_left", 0.0)
	game.call("_start_attack")
	if not _require(float(game.get("attack_time_left")) > 0.0, "Back-facing strike must start"):
		return
	var back_screen: Array[float] = []
	var last_fraction := 0.0
	var swing_duration: float = float(game.get("attack_duration"))
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
	var fresh_skeleton := fresh_game.call("_find_skeleton", fresh_visual) as Skeleton3D
	var fresh_sword := fresh_skeleton.get_node_or_null("SwordGrip/SimpleSword") as Node3D
	# Let the newly created AnimationTree evaluate Idle before the OneShot.
	# This mirrors a character that has actually stood still in the game.
	fresh_tree.advance(0.15)
	await process_frame
	print("Fresh hero stabilized idle sword position: ", fresh_visual.to_local(fresh_sword.to_global(Vector3(0.0, 1.305, 0.0))))
	fresh_game.call("_start_attack")
	var blended_start_trace: Array[Vector3] = []
	var previous_fraction := 0.0
	var attack_period := float(fresh_game.get("attack_duration"))
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
	game.set("attack_time_left", 0.0)
	game.call("_start_attack")
	tree.advance(0.02)
	if not _require(float(game.get("attack_time_left")) > 0.0 and bool(tree.get("parameters/Attack/active")), "Same sword slash must start when hero turns around"):
		return

	print("Gameplay smoke test passed: independent baked sword resources retain approved poses; active Sweeping, movement, dash, world, training hits, HP and respawn.")
	quit(0)

func _require(value: bool, message: String) -> bool:
	if not value:
		push_error("Gameplay smoke test: " + message)
		quit(1)
	return value
