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
	print("Gameplay smoke test passed: movement, animation, dash, world, training hits, HP and respawn.")
	quit(0)


func _require(value: bool, message: String) -> bool:
	if not value:
		push_error("Gameplay smoke test: " + message)
		quit(1)
	return value
