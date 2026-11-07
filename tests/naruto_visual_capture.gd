extends SceneTree
# Temporary visual QA capture, removed before merging game changes.
func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var source := load("res://main.tscn") as PackedScene
	if source == null:
		push_error("Visual QA: missing main scene")
		quit(1)
		return
	var game := source.instantiate() as Node3D
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	var tree := game.get("animation_tree") as AnimationTree
	var hero := game.get("hero") as CharacterBody3D
	var camera := game.get("camera") as Camera3D
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if tree == null or hero == null or camera == null:
		push_error("Visual QA: missing gameplay camera or animator")
		quit(1)
		return
	if hud != null:
		hud.hide()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.5
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	game.call("_set_locomotion", "Naruto")
	var output_dir := OS.get_environment("GITHUB_WORKSPACE").path_join("naruto-preview")
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Visual QA: cannot create screenshot directory")
		quit(1)
		return
	for state in ["Run", "Naruto"]:
		game.call("_set_locomotion", state)
		tree.advance(0.15)
		for view in ["side", "diagonal"]:
			if view == "side":
				camera.position = Vector3(8.0, 3.2, 0.0)
			else:
				camera.position = Vector3(7.0, 4.6, 7.0)
			camera.look_at(hero.global_position + Vector3(0.0, 1.1, 0.0), Vector3.UP)
			for frame in range(4):
				tree.advance(0.13)
				await process_frame
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				if image == null or image.is_empty():
					push_error("Visual QA: blank viewport image")
					quit(1)
					return
				var filename := "%s/%s_%s_%d.png" % [output_dir, state, view, frame]
				if image.save_png(filename) != OK:
					push_error("Visual QA: failed to save " + filename)
					quit(1)
					return
				print("VISUAL_QA_IMAGE: ", filename, " size=", image.get_size())
	print("VISUAL_QA_CAPTURE_OK")
	quit(0)
