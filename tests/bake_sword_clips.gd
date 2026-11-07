extends SceneTree
# One-time migration: bake the currently accepted runtime Animation objects to
# separate Godot text resources. Remove this utility after committing the files.
func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var scene := load("res://main.tscn") as PackedScene
	if scene == null:
		push_error("Animation bake: main scene missing")
		quit(1)
		return
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	var animator := game.get("animator") as AnimationPlayer
	if animator == null:
		push_error("Animation bake: AnimationPlayer missing")
		quit(1)
		return

	var specs := [
		["combat_mirror/WideSwordSlashMirror", "standard_sword_slash.tres"],
		["combat_sweeping/SweepingSwordSlash", "sweeping_sword_slash.tres"],
	]
	var directory := "res://assets/animations/"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		push_error("Animation bake: could not create animation directory")
		quit(1)
		return
	for spec in specs:
		var animation_name: String = spec[0]
		var path: String = directory + spec[1]
		var animation := animator.get_animation(animation_name)
		if animation == null:
			push_error("Animation bake: missing " + animation_name)
			quit(1)
			return
		# Duplicate so saving the resource cannot alter the live AnimationPlayer.
		var saved := animation.duplicate(true) as Animation
		saved.resource_name = spec[1].get_basename()
		if ResourceSaver.save(saved, path) != OK:
			push_error("Animation bake: failed to save " + path)
			quit(1)
			return
		var reloaded := load(path) as Animation
		if reloaded == null or reloaded.get_track_count() != animation.get_track_count() or not is_equal_approx(reloaded.length, animation.length):
			push_error("Animation bake: reloaded clip differs from live " + animation_name)
			quit(1)
			return
		for track in range(animation.get_track_count()):
			if animation.track_get_path(track) != reloaded.track_get_path(track) or animation.track_get_key_count(track) != reloaded.track_get_key_count(track):
				push_error("Animation bake: changed track " + str(track) + " of " + animation_name)
				quit(1)
				return
		var file_text := FileAccess.get_file_as_string(path)
		var base64 := Marshalls.utf8_to_base64(file_text)
		var chunk_size := 12000
		for start in range(0, base64.length(), chunk_size):
			print("BAKED_ANIMATION_DATA|", spec[1], "|", start / chunk_size, "|", base64.substr(start, chunk_size))
		print("BAKED_ANIMATION_END|", spec[1], "|bytes=", file_text.to_utf8_buffer().size(), "|tracks=", animation.get_track_count(), "|duration=", animation.length)
	quit(0)
