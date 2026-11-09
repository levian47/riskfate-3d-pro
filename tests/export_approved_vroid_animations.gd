extends SceneTree
# ONE-TIME migration helper. Export runtime VRoid animations without altering
# their source curves. Remove from the final PR after baking approved .tres files.
const CLIPS := {
	"QuaterniusWalk": "walk.tres",
	"QuaterniusRun": "run_armed.tres",
	"QuaterniusRunFree": "run_unarmed.tres",
	"SwordSlash": "attack_sword_regular_1h.tres",
	"SwordHeavyCandidate": "attack_sword_heavy_1h.tres",
	"UnarmedSwing": "attack_unarmed_hook.tres",
	"SwordGrip": "grip_one_handed.tres",
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://main.tscn") as PackedScene
	if scene == null:
		push_error("EXPORT FAILED: scene missing")
		quit(1)
		return
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	var player := game.get("animator") as AnimationPlayer
	if player == null or not player.has_animation_library("vroid"):
		push_error("EXPORT FAILED: VRoid animation library missing")
		quit(1)
		return
	var library := player.get_animation_library("vroid")
	var folder := "res://characters/player/animations"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		push_error("EXPORT FAILED: cannot create folder")
		quit(1)
		return
	for clip_name in CLIPS:
		var anim := library.get_animation(clip_name) as Animation
		if anim == null or anim.get_track_count() == 0:
			push_error("EXPORT FAILED: empty clip " + clip_name)
			quit(1)
			return
		var file_name: String = CLIPS[clip_name]
		var file_path := folder.path_join(file_name)
		var saved := ResourceSaver.save(anim, file_path)
		if saved != OK:
			push_error("EXPORT FAILED: save " + file_name + ": " + str(saved))
			quit(1)
			return
		var reloaded := ResourceLoader.load(file_path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
		if reloaded == null or reloaded.get_track_count() != anim.get_track_count():
			push_error("EXPORT FAILED: cannot reload " + file_name)
			quit(1)
			return
		var encoded := Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(file_path))
		var chunk_size := 10000
		var total_chunks := ceili(float(encoded.length()) / float(chunk_size))
		print("ANIM_META|", file_name, "|", anim.get_track_count(), "|", anim.length, "|", encoded.length(), "|", total_chunks)
		for chunk in range(total_chunks):
			print("ANIM_DATA|", file_name, "|", chunk, "|", encoded.substr(chunk * chunk_size, chunk_size))
	print("ANIM_EXPORT_OK|", CLIPS.size())
	quit(0)
