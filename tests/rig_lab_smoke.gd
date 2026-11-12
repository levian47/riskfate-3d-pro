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
	var visible_mesh: MeshInstance3D = lab.get("mesh_instance")
	if not _require(visible_mesh != null and visible_mesh.mesh != null and visible_mesh.visible, "Visible character geometry must be available"):
		return
	var groups: Array = lab.get("group_labels")
	var group_indices: Array = lab.get("group_indices")
	if not _require(groups.size() >= 20 and group_indices.size() == groups.size(), "Finger and joint choices are missing"):
		return
	if not _require(lab.get("part_name") is Label, "Selected part must have a visible label, not a popup"):
		return
	var touch_ui: Node = lab.get("ui_root")
	if not _require(touch_ui.get_node_or_null("RigControls") != null, "Touch controls are missing"):
		return
	var finger_buttons: Dictionary = lab.get("finger_buttons")
	if not _require(finger_buttons.size() == 5, "Five direct finger buttons must be present"):
		return
	for finger_key in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		if not _require((finger_buttons[finger_key] as Button).pressed.is_connected(Callable(lab, "_select_finger").bind(finger_key)), "Unconnected direct finger button: " + finger_key):
			return
	var axis_buttons: Array = lab.get("axis_buttons")
	if not _require(axis_buttons.size() == 3, "X/Y/Z must be plain buttons"):
		return
	for axis_button in axis_buttons:
		if not _require(axis_button is Button, "Axis selector must not open a popup"):
			return
	var fullscreen: Button = lab.get("full_button")
	if not _require(fullscreen != null and fullscreen.visible and fullscreen.pressed.is_connected(Callable(lab, "_toggle_fullscreen")), "FULL button not wired"):
		return
	var overlay: MeshInstance3D = lab.get("line_instance")
	if not _require(overlay != null and not overlay.visible, "Skeleton overlay must start hidden so the model remains visible"):
		return
	var previous_label: String = (lab.get("part_name") as Label).text
	lab.call("_step_selection", 1)
	if not _require((lab.get("part_name") as Label).text != previous_label, "Touch navigation must change selected finger"):
		return
	(finger_buttons["Thumb"] as Button).pressed.emit()
	if not _require((lab.get("part_name") as Label).text.contains("великий"), "Direct finger tap did not select thumb"):
		return
	lab.call("_select_hand", "Right")
	if not _require((lab.get("part_name") as Label).text.begins_with("Права"), "Right-hand button must change hand"):
		return
	lab.call("_select_hand", "Left")
	(finger_buttons["Index"] as Button).pressed.emit()
	if not _require((lab.get("part_name") as Label).text.contains("вказівний"), "Index finger direct button must select index"):
		return
	lab.call("_select_axis", 1)
	if not _require(int(lab.get("selected_axis")) == 1, "Axis button did not change axis"):
		return
	var angle_slider: HSlider = lab.get("angle_slider")
	var angle_panel: PanelContainer = lab.get("angle_panel")
	var controls_scroll: ScrollContainer = lab.get("controls_scroll")
	if not _require(angle_slider != null and angle_panel != null
		and not controls_scroll.is_ancestor_of(angle_slider)
		and angle_panel.is_ancestor_of(angle_slider), "Angle slider must be independent from scrollable controls"):
		return
	if not _require(Input.emulate_mouse_from_touch, "Touch-to-mouse emulation must be enabled inside Rig Lab"):
		return
	var plus: Button = lab.get("angle_plus_button")
	var minus: Button = lab.get("angle_minus_button")
	if not _require(plus != null and minus != null and plus.visible and minus.visible,
		"Separate accessible angle buttons are missing"):
		return
	var index := int(lab.call("_bone_index", "mixamorig:LeftHandIndex1"))
	var initial := rig.get_bone_pose_rotation(index)
	plus.pressed.emit()
	if not _require(is_equal_approx(angle_slider.value, 15.0)
		and rig.get_bone_pose_rotation(index).angle_to(initial) > 0.1,
		"+15 button must move the slider and rotate selected finger"):
		return
	minus.pressed.emit()
	if not _require(is_zero_approx(angle_slider.value)
		and rig.get_bone_pose_rotation(index).angle_to(initial) < 0.001,
		"-15 button must return slider and finger to rest pose"):
		return
	angle_slider.value = 35.0
	if not _require(is_equal_approx(angle_slider.value, 35.0)
		and rig.get_bone_pose_rotation(index).angle_to(initial) > 0.1,
		"Dragging slider value must be connected to finger rotation"):
		return
	lab.call("_apply_angle", 35.0)
	if not _require(rig.get_bone_pose_rotation(index).angle_to(initial) > 0.1, "Finger did not rotate"):
		return
	lab.call("_reset_pose")
	if not _require(rig.get_bone_pose_rotation(index).angle_to(initial) < 0.001, "Reset did not restore finger"):
		return

	# Mirrored thumb anatomy regression: +30° bends both thumb joints toward
	# equivalent mirrored targets rather than sending the right thumb away.
	var left_distal := int(lab.call("_bone_index", "mixamorig:LeftHandThumb2"))
	var right_distal := int(lab.call("_bone_index", "mixamorig:RightHandThumb2"))
	lab.call("_select_hand", "Left")
	lab.call("_select_finger", "Thumb")
	if not _require(int(lab.get("selected_axis")) == 0, "Thumb selection must activate anatomical X flexion"):
		return
	var left_rest := rig.get_bone_global_pose(left_distal).origin
	angle_slider.value = 30.0
	var left_delta := rig.get_bone_global_pose(left_distal).origin - left_rest
	lab.call("_reset_pose")
	lab.call("_select_hand", "Right")
	lab.call("_select_finger", "Thumb")
	if not _require(int(lab.get("selected_axis")) == 0, "Right thumb must use anatomical X flexion"):
		return
	var right_rest := rig.get_bone_global_pose(right_distal).origin
	angle_slider.value = 30.0
	var right_delta := rig.get_bone_global_pose(right_distal).origin - right_rest
	if not _require(left_delta.length() > 0.001 and right_delta.length() > 0.001
		and absf(left_delta.x + right_delta.x) < 0.005
		and absf(left_delta.y - right_delta.y) < 0.005
		and absf(left_delta.z - right_delta.z) < 0.005,
		"Positive X thumb flexion must be mirrored anatomically on both hands"):
		return
	lab.call("_reset_pose")

	# Grip Lab regression: a neutral cylinder follows the selected hand via
	# BoneAttachment3D, and a preset affects all 14 independent finger joints.
	var grip_attachment: BoneAttachment3D = lab.get("handle_attachment")
	var grip_handle: MeshInstance3D = lab.get("handle_cylinder")
	if not _require(grip_attachment != null and grip_handle != null
		and grip_handle.get_parent() == grip_attachment
		and grip_handle.mesh is CylinderMesh and grip_handle.visible,
		"Grip cylinder must be visible and parented to a BoneAttachment3D"):
		return
	if not _require(grip_attachment.bone_name.contains("RightHand"),
		"Test handle must be attached to the currently selected right hand"):
		return
	var grip_buttons: Array = lab.get("finger_joint_buttons")
	if not _require(grip_buttons.size() == 3, "Independent digit-joint buttons are missing"):
		return
	lab.call("_set_grip_pose")
	var grip_rotations: Dictionary = lab.get("saved_rotations")
	if not _require(grip_rotations.size() == 14, "Grip candidate must rotate exactly 14 joints of the selected hand"):
		return
	var ring_index := int(lab.call("_bone_index", "mixamorig:RightHandRing1"))
	var ring_candidate := rig.get_bone_pose_rotation(ring_index)
	lab.call("_select_finger", "Index")
	(grip_buttons[0] as Button).pressed.emit()
	var independently_selected: Array = lab.get("selected")
	if not _require(independently_selected.size() == 1
		and independently_selected[0] == int(lab.call("_bone_index", "mixamorig:RightHandIndex1")),
		"Joint 1 button must select only the requested joint"):
		return
	angle_slider.value = 10.0
	if not _require(rig.get_bone_pose_rotation(ring_index).angle_to(ring_candidate) < 0.001
		and grip_rotations.size() == 14,
		"Per-joint tuning must preserve the other fingers' grip"):
		return
	var right_hand_idx := int(lab.call("_bone_index", "mixamorig:RightHand"))
	if not _require(grip_attachment.bone_name == rig.get_bone_name(right_hand_idx),
		"Grip must remain attached to the selected wrist"):
		return
	lab.call("_select_hand", "Left")
	if not _require(grip_attachment.bone_name.contains("LeftHand"),
		"Grip attachment must follow hand switching"):
		return
	lab.call("_set_grip_pose")
	if not _require(grip_rotations.size() == 14, "Left-hand grip must use its own 14 joints"):
		return
	lab.call("_reset_pose")
	if not _require(grip_rotations.is_empty() and grip_handle.visible,
		"Reset must open the hand without hiding the test cylinder"):
		return
	print("Rig Lab grip smoke passed: attached handle, 14-joint pose, independent tuning, both hands")
	print("Rig Lab smoke passed: 52 bones, 28 finger bones, mirrored thumb flexion, pose/reset")
	quit(0)
