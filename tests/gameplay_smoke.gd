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
	var direction_node := blend.get_node("SwordDirection") as AnimationNodeBlend2
	if not _require(direction_node != null, "Camera-dependent sword direction Blend2 selector missing"):
		return
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

	# Both generated clips are independent and preserve source animation timing.
	if not _require(animator.has_animation("combat/WideSwordSlash") and animator.has_animation("combat_mirror/WideSwordSlashMirror"), "Both sword clips must exist"):
		return
	var original_clip := animator.get_animation(sword_name)
	var wide_clip := animator.get_animation("combat/WideSwordSlash")
	var mirror_clip := animator.get_animation("combat_mirror/WideSwordSlashMirror")
	if not _require(wide_clip != original_clip and is_equal_approx(wide_clip.length, original_clip.length) and is_equal_approx(mirror_clip.length, original_clip.length), "Combat clips must preserve timing"):
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
	if not _require(attack_node != null and String(attack_node.animation) == "combat/WideSwordSlash", "Attack blend node must play wider clip"):
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
	# Test the visible right-to-left swing with the actual isometric camera
	# while the player faces the training dummy (+Z), not just the model's axes.
	game.set_physics_process(false)
	visual_node.rotation.y = 0.0
	var view_camera := game.get("camera") as Camera3D
	if not _require(view_camera != null, "Isometric camera must exist for screen-direction test"):
		return
	var view_right := view_camera.global_transform.basis.x.normalized()
	var skel := game.call("_find_skeleton", visual_node) as Skeleton3D
	print("Shoulder.R rest basis: ", skel.get_bone_rest(skel.find_bone("Shoulder.R")).basis)
	var sword_grip := skel.get_node_or_null("SwordGrip/SimpleSword") as Node3D
	if not _require(sword_grip != null, "Test sword attachment must be present"):
		return
	# Verify the real player attack BEFORE temporarily letting AnimationPlayer
	# drive the same skeleton directly for the clip-only trajectory check.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.set("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.advance(0.001)
	game.call("_set_locomotion", "Idle", true)
	tree.advance(0.15)
	game.set("attack_time_left", 0.0)
	game.call("_start_attack")
	var blended_screen_positions: Array[float] = []
	var last_fraction := 0.0
	var playback_duration: float = float(game.get("attack_duration"))
	print("Attack playback duration: ", playback_duration, ", OneShot request: ", tree.get("parameters/Attack/request"))
	for fraction in [0.16, 0.24, 0.32, 0.40, 0.48, 0.56, 0.64]:
		tree.advance(playback_duration * (fraction - last_fraction))
		last_fraction = fraction
		# BoneAttachment3D synchronizes on Skeleton3D updates, not during
		# a chain of manual AnimationTree.advance() calls in the same frame.
		await process_frame
		blended_screen_positions.append(view_right.dot(sword_grip.to_global(Vector3(0.0, 1.305, 0.0))))
	print("Blended player attack screen positions: ", blended_screen_positions, ", OneShot active: ", tree.get("parameters/Attack/active"))
	# User's front-facing regression: a rightward snap BEFORE the cutting
	# phase looks like a left-to-right strike. Check the full visible sequence,
	# rather than only the clean tail from 32% onward.
	if not _require(blended_screen_positions[0] - blended_screen_positions[blended_screen_positions.size() - 1] > 2.0, "Front-facing full swing must travel screen-right to screen-left"):
		return
	for i in range(1, blended_screen_positions.size()):
		if not _require(blended_screen_positions[i] <= blended_screen_positions[i - 1] + 0.30, "Front-facing sword must not snap rightward mid-swing"):
			return
	tree.active = false
	animator.play("combat/WideSwordSlash")
	var tip_points: Array[Vector3] = []
	var screen_right_positions: Array[float] = []
	for fraction in [0.16, 0.24, 0.32, 0.40, 0.48, 0.56, 0.64]:
		animator.seek(wide_clip.length * fraction, true)
		await process_frame
		var world_tip := sword_grip.to_global(Vector3(0.0, 1.305, 0.0))
		tip_points.append(visual_node.to_local(world_tip))
		screen_right_positions.append(view_right.dot(world_tip))
	animator.stop()
	tree.active = true
	print("Horizontal sword tip positions: ", tip_points)
	print("Camera-horizontal sword positions: ", screen_right_positions)
	var start_tip := tip_points[0]
	var end_tip := tip_points[tip_points.size() - 1]
	var min_height: float = start_tip.y
	var max_height: float = start_tip.y
	for point in tip_points:
		min_height = minf(min_height, point.y)
		max_height = maxf(max_height, point.y)
	if not _require(start_tip.x - end_tip.x > 2.5, "Sword must sweep from the hero's right side to left"):
		return
	if not _require(screen_right_positions[0] - screen_right_positions[screen_right_positions.size() - 1] > 2.0, "Sword must visually sweep right-to-left from the isometric camera"):
		return
	if not _require(start_tip.y - end_tip.y > 0.3 and max_height - min_height < 1.0, "Sword should descend slightly, not arc vertically"):
		return
	for point in tip_points:
		if not _require(point.z > 0.20, "Sword blade must remain forward during the active sweep"):
			return

	# Turn the hero around. Local left/right reverses on screen, so the
	# mirrored clip must take over without changing damage, duration or camera.
	var mirrored_name := "combat_mirror/WideSwordSlashMirror"
	if not _require(animator.has_animation(mirrored_name), "Mirrored attack clip must exist"):
		return
	var mirrored_clip := animator.get_animation(mirrored_name)
	visual_node.rotation.y = PI
	tree.active = false
	animator.play(mirrored_name)
	var mirrored_screen: Array[float] = []
	for fraction in [0.16, 0.24, 0.32, 0.40, 0.48, 0.56, 0.64]:
		animator.seek(mirrored_clip.length * fraction, true)
		await process_frame
		mirrored_screen.append(view_right.dot(sword_grip.to_global(Vector3(0.0, 1.305, 0.0))))
	animator.stop()
	tree.active = true
	print("Opposite facing mirrored attack screen positions: ", mirrored_screen)
	if not _require(mirrored_screen[0] - mirrored_screen[mirrored_screen.size() - 1] > 2.0, "Mirrored sword clip must move right-to-left on screen when hero faces backwards"):
		return
	# The actual input handler must select the appropriate variant, not just
	# keep the correct mirrored animation unused in the resource library.
	tree.set("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.advance(0.01)
	game.set("attack_time_left", 0.0)
	game.call("_start_attack")
	tree.advance(0.04)
	if not _require(is_equal_approx(float(tree.get("parameters/SwordDirection/blend_amount")), 1.0), "Turning around must select mirrored animation in the live AnimationTree"):
		return
	var mirrored_blended: Array[float] = []
	var previous_fraction := 0.0
	var mirror_duration: float = float(game.get("attack_duration"))
	for fraction in [0.16, 0.24, 0.32, 0.40, 0.48, 0.56, 0.64]:
		tree.advance(mirror_duration * (fraction - previous_fraction))
		previous_fraction = fraction
		await process_frame
		mirrored_blended.append(view_right.dot(sword_grip.to_global(Vector3(0.0, 1.305, 0.0))))
	print("Opposite facing blended attack screen positions: ", mirrored_blended)
	if not _require(mirrored_blended[2] - mirrored_blended[mirrored_blended.size() - 1] > 1.7, "Live reverse-facing attack cutting phase must move right-to-left"):
		return
	for i in range(3, mirrored_blended.size()):
		if not _require(mirrored_blended[i] < mirrored_blended[i - 1] + 0.25, "Reverse-facing cutting phase must not reverse direction"):
			return

	print("Gameplay smoke test passed: camera-selected right-to-left sword attack from both facing directions, descent, FPS cap, offline ping, movement, dash, world, training hits, HP and respawn.")
	quit(0)


func _require(value: bool, message: String) -> bool:
	if not value:
		push_error("Gameplay smoke test: " + message)
		quit(1)
	return value
