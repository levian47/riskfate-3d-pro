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

	var environment := game.get_node_or_null("Environment/Ground")
	if not _require(environment is StaticBody3D, "World ground missing"):
		return
	var collision := environment.get_node("CollisionShape3D") as CollisionShape3D
	if not _require(collision != null and (collision.shape as BoxShape3D).size.x >= 200.0, "Expanded terrain missing"):
		return
	print("Gameplay smoke test passed: upper-body attack overlay, movement/jump, expanded world.")
	quit(0)


func _require(value: bool, message: String) -> bool:
	if not value:
		push_error("Gameplay smoke test: " + message)
		quit(1)
	return value
