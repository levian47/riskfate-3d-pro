extends SceneTree

const LAB := preload("res://tests/rig_lab/rig_lab.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Rig Lab smoke: " + message)
	quit(1)
	return false

func _run() -> void:
	var lab := LAB.instantiate()
	root.add_child(lab)
	await process_frame
	var rig: Skeleton3D = lab.get("rig")
	if not _require(rig != null, "Skeleton3D not imported"):
		return
	if not _require(rig.get_bone_count() == 52, "Expected 52 bones"):
		return
	for side in ["Left", "Right"]:
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			var digits := 2 if finger == "Thumb" else 3
			for joint in range(1, digits + 1):
				var name := "mixamorig:%sHand%s%d" % [side, finger, joint]
				if not _require(int(lab.call("_bone_index", name)) >= 0, "Missing " + name):
					return
	lab.call("_on_part_changed", 1) # Left index: first entry is Left thumb.
	var index := int(lab.call("_bone_index", "mixamorig:LeftHandIndex1"))
	var initial := rig.get_bone_pose_rotation(index)
	lab.call("_apply_angle", 35.0)
	if not _require(rig.get_bone_pose_rotation(index).angle_to(initial) > 0.1, "Finger did not rotate"):
		return
	lab.call("_reset_pose")
	if not _require(rig.get_bone_pose_rotation(index).angle_to(initial) < 0.001, "Reset did not restore finger"):
		return
	print("Rig Lab smoke passed: 52 bones, 28 finger bones, basic pose/reset")
	quit(0)
