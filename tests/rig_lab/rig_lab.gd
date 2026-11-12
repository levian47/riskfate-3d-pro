extends Node3D
## Isolated interactive rig examination. No gameplay / authored animations.

const SOURCE := preload("res://assets/characters/Riskfate_Male_FingerRig52_WEBPREVIEW.glb")

var rig: Skeleton3D
var orbit_camera: Camera3D
var line_mesh: ImmediateMesh
var line_instance: MeshInstance3D
var part_name: Label
var hand_name: Label
var selected_group_index := -1
var selected_axis := 2
var selected_hand := "Left"
var group_labels: Array[String] = []
var group_indices: Array[Array] = []
var axis_buttons: Array[Button] = []
var finger_buttons: Dictionary = {}
var current_finger := "Index"
var finger_joint_buttons: Array[Button] = []
var handle_attachment: BoneAttachment3D
var handle_cylinder: MeshInstance3D
var handle_on := true
var handle_toggle: Button
var handle_status: Label
var saved_rotations: Dictionary = {}
var saved_angles: Dictionary = {}
var saved_axes: Dictionary = {}
var angle_slider: HSlider
var angle_value: Label
var info_text: Label
var overlay_button: Button
var full_button: Button
var controls_panel: PanelContainer
var angle_panel: PanelContainer
var angle_minus_button: Button
var angle_plus_button: Button
var controls_scroll: ScrollContainer
var ui_root: Control
var mesh_instance: MeshInstance3D
var selected: Array[int] = []
var original_rotations: Array[Quaternion] = []
var orbit_yaw := 0.0
var orbit_pitch := 0.12
var distance := 3.4
var focus := Vector3(0.0, 1.0, 0.0)
var focus_mode := 0
var show_lines := false

func _ready() -> void:
	# Only this isolated test scene needs pointer emulation for dragging sliders on mobile Web.
	# Keep the project's gameplay input settings unchanged.
	Input.emulate_mouse_from_touch = true
	var model := SOURCE.instantiate() as Node3D
	if model == null:
		push_error("Rig Lab: GLB did not instantiate")
		return
	add_child(model)
	rig = _find_skeleton(model)
	mesh_instance = _find_mesh(model)
	if mesh_instance == null or mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
		push_error("Rig Lab: imported GLB does not contain a visible character mesh")
		return
	mesh_instance.visible = true
	if rig == null:
		push_error("Rig Lab: Skeleton3D not found")
		return
	for i in range(rig.get_bone_count()):
		original_rotations.append(rig.get_bone_pose_rotation(i))
	_setup_environment()
	_setup_overlay()
	_setup_camera()
	_setup_handle()
	_setup_ui()
	_update_camera()
	print("Rig Lab: loaded ", rig.get_bone_count(), " bones and ", mesh_instance.mesh.get_surface_count(), " mesh surfaces")

func _bone_index(requested: String) -> int:
	# Godot glTF importer may normalize Mixamo namespace separators in bone names.
	var exact := rig.find_bone(requested)
	if exact >= 0:
		return exact
	var simple := requested.get_slice(":", requested.get_slice_count(":") - 1)
	for index in range(rig.get_bone_count()):
		var found := String(rig.get_bone_name(index))
		if found == simple or found.ends_with(":" + simple) or found.ends_with("_" + simple):
			return index
	return -1

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_mesh(child)
		if result != null:
			return result
	return null

func _setup_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "Lighting"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.13, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.89, 1.0)
	env.ambient_light_energy = 0.65
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 1.15
	add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	floor.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.21, 0.24, 0.29)
	mat.roughness = 1.0
	floor.material_override = mat
	floor.position.y = -0.012
	add_child(floor)

func _setup_camera() -> void:
	orbit_camera = Camera3D.new()
	orbit_camera.current = true
	orbit_camera.fov = 45
	orbit_camera.near = 0.015
	add_child(orbit_camera)

func _setup_overlay() -> void:
	line_mesh = ImmediateMesh.new()
	line_instance = MeshInstance3D.new()
	line_instance.name = "BoneLines"
	line_instance.mesh = line_mesh
	line_instance.visible = show_lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	line_instance.material_override = mat
	add_child(line_instance)

func _make_button(text_value: String, cb: Callable, box: Container) -> Button:
	var b := Button.new()
	b.text = text_value
	b.custom_minimum_size.y = 46
	b.pressed.connect(cb)
	box.add_child(b)
	return b

# Test-only neutral handle. All points are calculated from imported bone REST.
# The handle does not prevent mesh clipping: the user inspects the overlap.
func _setup_handle() -> void:
	handle_attachment = BoneAttachment3D.new()
	handle_attachment.name = "TestGripAttachment"
	rig.add_child(handle_attachment)
	handle_cylinder = MeshInstance3D.new()
	handle_cylinder.name = "TestGripCylinder"
	var unit := maxf(rig.global_transform.basis.x.length(), 0.0001)
	var cylinder := CylinderMesh.new()
	cylinder.height = 0.18 / unit
	cylinder.top_radius = 0.013 / unit
	cylinder.bottom_radius = 0.013 / unit
	cylinder.radial_segments = 12
	handle_cylinder.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.48, 0.29, 0.11)
	material.roughness = 1.0
	handle_cylinder.material_override = material
	handle_attachment.add_child(handle_cylinder)
	_position_handle()


func _position_handle() -> void:
	if handle_attachment == null:
		return
	var wrist := _bone_index("mixamorig:%sHand" % selected_hand)
	var finger_roots: Array[Vector3] = []
	for finger in ["Pinky", "Ring", "Middle", "Index"]:
		var index := _bone_index("mixamorig:%sHand%s1" % [selected_hand, finger])
		if index >= 0:
			finger_roots.append(rig.get_bone_global_rest(index).origin)
	if wrist < 0 or finger_roots.size() != 4:
		handle_cylinder.visible = false
		return
	var center := Vector3.ZERO
	for point in finger_roots:
		center += point
	center /= 4.0
	var wrist_rest: Transform3D = rig.get_bone_global_rest(wrist)
	center = center.lerp(wrist_rest.origin, 0.35)
	var across := (finger_roots[3] - finger_roots[0]).normalized()
	var target := Transform3D(Basis(Quaternion(Vector3.UP, across)), center)
	handle_attachment.bone_name = rig.get_bone_name(wrist)
	handle_cylinder.transform = wrist_rest.affine_inverse() * target
	handle_cylinder.visible = handle_on


func _toggle_handle() -> void:
	handle_on = not handle_on
	_position_handle()
	handle_toggle.text = "РУКОЯТЬ: ПОКАЗАНО" if handle_on else "РУКОЯТЬ: СХОВАНО"


func _set_test_rotation(index: int, degrees: float, axis_index: int) -> void:
	var axis := Vector3.RIGHT
	if axis_index == 1:
		axis = Vector3.UP
	elif axis_index == 2:
		axis = Vector3.BACK
	var name := String(rig.get_bone_name(index))
	var sign := -1.0 if axis_index == 0 and name.contains("RightHandThumb") else 1.0
	if is_zero_approx(degrees):
		saved_rotations.erase(index)
		saved_angles.erase(index)
		saved_axes.erase(index)
	else:
		saved_rotations[index] = original_rotations[index] * Quaternion(axis, deg_to_rad(degrees * sign))
		saved_angles[index] = degrees
		saved_axes[index] = axis_index


func _update_stored_pose() -> void:
	_reset_all_bones()
	for bone_index in saved_rotations:
		rig.set_bone_pose_rotation(int(bone_index), saved_rotations[bone_index])


func _set_grip_pose() -> void:
	# Approximate candidate for visual review; not a collision-solving grasp.
	var angles := {
		"Thumb": [24.0, 18.0],
		"Index": [40.0, 48.0, 30.0],
		"Middle": [46.0, 52.0, 34.0],
		"Ring": [48.0, 52.0, 34.0],
		"Pinky": [42.0, 46.0, 28.0]
	}
	saved_rotations.clear()
	saved_angles.clear()
	saved_axes.clear()
	for finger in angles:
		var values: Array = angles[finger]
		for i in range(values.size()):
			var bone_idx := _bone_index("mixamorig:%sHand%s%d" % [selected_hand, finger, i + 1])
			if bone_idx >= 0:
				_set_test_rotation(bone_idx, float(values[i]), 0)
	_update_stored_pose()
	handle_on = true
	_position_handle()
	handle_toggle.text = "РУКОЯТЬ: ПОКАЗАНО"
	handle_status.text = "Тестова поза: %d суглобів. Перевір перетини." % saved_rotations.size()
	angle_slider.set_value_no_signal(0.0)
	angle_value.text = "Кут: 0° (вибери суглоб для корекції)"


func _choose_finger_joint(joint: int) -> void:
	if current_finger == "All":
		return
	var limit := 2 if current_finger == "Thumb" else 3
	if joint < 1 or joint > limit:
		return
	var index := _bone_index("mixamorig:%sHand%s%d" % [selected_hand, current_finger, joint])
	if index < 0:
		return
	selected.clear()
	# Temporarily empty the selection while changing axis: the axis button
	# handler would otherwise overwrite a previously tuned grip rotation.
	_select_axis(int(saved_axes.get(index, 0)))
	selected.append(index)
	part_name.text = ("%s %s — суглоб %d" % [selected_hand, current_finger, joint])
	var degrees := float(saved_angles.get(index, 0.0))
	angle_slider.set_value_no_signal(degrees)
	angle_value.text = "Кут: %d° (суглоб %d)" % [int(degrees), joint]


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui_root = Control.new()
	ui_root.name = "TouchUI"
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui_root)

	controls_panel = PanelContainer.new()
	controls_panel.name = "RigControls"
	controls_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(controls_panel)
	controls_scroll = ScrollContainer.new()
	controls_scroll.name = "ControlsScroll"
	controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	controls_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	controls_scroll.follow_focus = true
	controls_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_panel.add_child(controls_scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	controls_scroll.add_child(margin)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 7)
	margin.add_child(controls)
	var header := Label.new()
	header.text = "RISKFATE | RIG LAB 52"
	header.add_theme_font_size_override("font_size", 17)
	controls.add_child(header)
	info_text = Label.new()
	info_text.text = "52 кістки | рухи без анімацій"
	controls.add_child(info_text)

	var part_label := Label.new()
	part_label.text = "ОБЕРИ ПАЛЕЦЬ АБО СУГЛОБ"
	controls.add_child(part_label)

	var hand_row := HBoxContainer.new()
	controls.add_child(hand_row)
	var left_button := _make_button("ЛІВА РУКА", Callable(self, "_select_hand").bind("Left"), hand_row)
	left_button.name = "LeftHandButton"
	left_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_button := _make_button("ПРАВА РУКА", Callable(self, "_select_hand").bind("Right"), hand_row)
	right_button.name = "RightHandButton"
	right_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	hand_name = Label.new()
	hand_name.text = "Ліва рука"
	controls.add_child(hand_name)
	var fingers_row := HBoxContainer.new()
	controls.add_child(fingers_row)
	var finger_keys := ["Thumb", "Index", "Middle", "Ring", "Pinky"]
	var finger_titles := ["ВЕЛ", "ВКАЗ", "СЕР", "БЕЗ", "МІЗ"]
	for finger_index in range(finger_keys.size()):
		var finger_key: String = finger_keys[finger_index]
		var button := _make_button(finger_titles[finger_index], Callable(self, "_select_finger").bind(finger_key), fingers_row)
		button.name = "Finger" + finger_key
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		finger_buttons[finger_key] = button
	var all_button := _make_button("УСІ ПАЛЬЦІ", Callable(self, "_select_finger").bind("All"), controls)
	all_button.name = "AllFingersButton"
	var joint_label := Label.new()
	joint_label.text = "ВИБРАТИ ОДИН СУГЛОБ:"
	controls.add_child(joint_label)
	var joints := HBoxContainer.new()
	controls.add_child(joints)
	for n in range(1, 4):
		var button := _make_button(str(n), Callable(self, "_choose_finger_joint").bind(n), joints)
		button.name = "Joint" + str(n)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		finger_joint_buttons.append(button)
	var grip_label := Label.new()
	grip_label.text = "ТЕСТ ХВАТУ (БЕЗ ФІЗИКИ)"
	controls.add_child(grip_label)
	handle_toggle = _make_button("РУКОЯТЬ: ПОКАЗАНО", _toggle_handle, controls)
	handle_toggle.name = "HandleToggle"
	var grip_button := _make_button("СТИСНУТИ РУКОЯТЬ", _set_grip_pose, controls)
	grip_button.name = "GripPoseButton"
	handle_status = Label.new()
	handle_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	handle_status.text = "Поза ще не налаштована; це візуальна перевірка."
	controls.add_child(handle_status)

	_add_groups()
	var choice_row := HBoxContainer.new()
	controls.add_child(choice_row)
	_make_button("◀", func() -> void: _step_selection(-1), choice_row)
	part_name = Label.new()
	part_name.name = "SelectedPart"
	part_name.text = "Кістка не вибрана"
	part_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	part_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	part_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	part_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choice_row.add_child(part_name)
	_make_button("▶", func() -> void: _step_selection(1), choice_row)

	var axis_row := HBoxContainer.new()
	controls.add_child(axis_row)
	var axis_label := Label.new()
	axis_label.text = "ВІСЬ:"
	axis_row.add_child(axis_label)
	for axis_index in range(3):
		var axis_title: String = ["X", "Y", "Z"][axis_index]
		var axis_button := _make_button(axis_title, Callable(self, "_select_axis").bind(axis_index), axis_row)
		axis_button.name = "Axis" + axis_title
		axis_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axis_buttons.append(axis_button)

	var angle_hint := Label.new()
	angle_hint.text = "КУТ — ПОВЗУНОК ЗНИЗУ"
	controls.add_child(angle_hint)
	_make_button("СКИНУТИ ПОЗУ", _reset_pose, controls)
	overlay_button = _make_button("КІСТКИ: ВИМКНЕНО", _toggle_overlay, controls)
	overlay_button.name = "SkeletonToggle"

	var views := HBoxContainer.new()
	controls.add_child(views)
	_make_button("ТІЛО", func() -> void: _focus_on(0), views)
	_make_button("ЛІВА", func() -> void: _focus_on(1), views)
	_make_button("ПРАВА", func() -> void: _focus_on(2), views)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Хват — початкова поза. Оглянь рукоять з усіх боків. Кнопки 1–3 дозволяють змінити окремий суглоб."
	controls.add_child(hint)

	# Keep the drag-sensitive HSlider OUTSIDE ScrollContainer; on phones, vertical
	# scroll gesture handling can capture the movement before HSlider receives it.
	angle_panel = PanelContainer.new()
	angle_panel.name = "FixedAnglePanel"
	angle_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(angle_panel)
	var angle_margin := MarginContainer.new()
	angle_margin.add_theme_constant_override("margin_left", 12)
	angle_margin.add_theme_constant_override("margin_right", 12)
	angle_margin.add_theme_constant_override("margin_top", 7)
	angle_margin.add_theme_constant_override("margin_bottom", 7)
	angle_panel.add_child(angle_margin)
	var angle_controls := VBoxContainer.new()
	angle_controls.add_theme_constant_override("separation", 4)
	angle_margin.add_child(angle_controls)
	angle_value = Label.new()
	angle_value.name = "AngleValue"
	angle_value.text = "Кут: 0°"
	angle_controls.add_child(angle_value)
	angle_slider = HSlider.new()
	angle_slider.name = "AngleSlider"
	angle_slider.min_value = -90.0
	angle_slider.max_value = 90.0
	angle_slider.step = 1.0
	angle_slider.custom_minimum_size = Vector2(200, 44)
	angle_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	angle_slider.value_changed.connect(_apply_angle)
	angle_controls.add_child(angle_slider)
	var step_row := HBoxContainer.new()
	angle_controls.add_child(step_row)
	angle_minus_button = _make_button("−15°", func() -> void: _adjust_angle(-15), step_row)
	angle_minus_button.name = "AngleMinus15"
	angle_minus_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_plus_button = _make_button("+15°", func() -> void: _adjust_angle(15), step_row)
	angle_plus_button.name = "AnglePlus15"
	angle_plus_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	full_button = Button.new()
	full_button.name = "FullscreenButton"
	full_button.text = "FULL"
	full_button.custom_minimum_size = Vector2(104, 46)
	full_button.pressed.connect(_toggle_fullscreen)
	ui_root.add_child(full_button)
	get_viewport().size_changed.connect(_layout_ui)
	_layout_ui()
	_select_axis(2)
	_select_finger("Index")


func _layout_ui() -> void:
	if controls_panel == null or angle_panel == null or full_button == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_width := minf(326.0, maxf(230.0, viewport_size.x * 0.48))
	var dock_height := 152.0
	var panel_height := maxf(138.0, viewport_size.y - dock_height - 36.0)
	controls_panel.position = Vector2(12.0, 12.0)
	controls_panel.size = Vector2(panel_width, panel_height)
	angle_panel.position = Vector2(12.0, viewport_size.y - dock_height - 12.0)
	angle_panel.size = Vector2(panel_width, dock_height)
	full_button.position = Vector2(viewport_size.x - 114.0, 12.0)
	full_button.size = Vector2(102.0, 46.0)


func _step_selection(delta: int) -> void:
	if group_labels.is_empty():
		return
	_on_part_changed(posmod(selected_group_index + delta, group_labels.size()))


func _select_hand(side: String) -> void:
	if selected_hand != side:
		_reset_pose()
	selected_hand = side
	_position_handle()
	_select_finger("Index")


func _select_finger(finger: String) -> void:
	current_finger = finger
	var labels := {
		"Thumb": "великий",
		"Index": "вказівний",
		"Middle": "середній",
		"Ring": "безіменний",
		"Pinky": "мізинець",
		"All": "всі пальці"
	}
	var hand_prefix := "Ліва" if selected_hand == "Left" else "Права"
	var label_text: String = hand_prefix + " — " + String(labels.get(finger, "вказівний"))
	var index := group_labels.find(label_text)
	if index >= 0:
		_on_part_changed(index)


func _select_axis(axis_index: int) -> void:
	selected_axis = clampi(axis_index, 0, 2)
	for i in range(axis_buttons.size()):
		var title: String = ["X", "Y", "Z"][i]
		axis_buttons[i].text = ("● " if i == selected_axis else "") + title
	if angle_slider != null:
		_apply_angle(angle_slider.value)


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	call_deferred("_layout_ui")


func _add_part(label_text: String, bone_names: Array) -> void:
	var matches: Array[int] = []
	for value in bone_names:
		var index := _bone_index(String(value))
		if index >= 0:
			matches.append(index)
	if matches.size() != bone_names.size():
		push_warning("Rig Lab: incomplete group " + label_text)
		return
	group_labels.append(label_text)
	group_indices.append(matches)

func _add_groups() -> void:
	for side in ["Left", "Right"]:
		var side_label: String = "Ліва" if side == "Left" else "Права"
		var all_fingers: Array = []
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			var digits: int = 2 if finger == "Thumb" else 3
			var names: Array = []
			for joint in range(1, digits + 1):
				var name := "mixamorig:%sHand%s%d" % [side, finger, joint]
				names.append(name)
				all_fingers.append(name)
			var labels := {"Thumb":"великий", "Index":"вказівний", "Middle":"середній", "Ring":"безіменний", "Pinky":"мізинець"}
			_add_part("%s — %s" % [side_label, labels[finger]], names)
		_add_part("%s — всі пальці" % side_label, all_fingers)
	for name in ["Head", "Neck", "LeftForeArm", "RightForeArm", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg"]:
		_add_part("Суглоб — " + name, ["mixamorig:" + name])

func _on_part_changed(item_index: int) -> void:
	if item_index < 0 or item_index >= group_labels.size():
		return
	selected_group_index = item_index
	selected.clear()
	for bone_index in group_indices[item_index]:
		selected.append(int(bone_index))
	var label_text := group_labels[item_index]
	part_name.text = label_text
	var previous_hand := selected_hand
	if label_text.begins_with("Ліва"):
		selected_hand = "Left"
	elif label_text.begins_with("Права"):
		selected_hand = "Right"
	if selected_hand != previous_hand:
		_position_handle()
	hand_name.text = "Ліва рука" if selected_hand == "Left" else "Права рука"
	# Switching selection must NOT reset the other joints' saved grip pose.
	var finger_label := {
		"великий":"Thumb", "вказівний":"Index", "середній":"Middle",
		"безіменний":"Ring", "мізинець":"Pinky", "всі пальці":"All"
	}
	for key in finger_label:
		if label_text.ends_with(" — " + String(key)):
			current_finger = String(finger_label[key])
			break
	var chosen := selected[0] if not selected.is_empty() else -1
	var axis := int(saved_axes.get(chosen, 0)) if chosen >= 0 and not label_text.begins_with("Суглоб") else selected_axis
	selected_axis = axis
	for i in range(axis_buttons.size()):
		axis_buttons[i].text = ("● " if i == selected_axis else "") + ["X","Y","Z"][i]
	var degrees := float(saved_angles.get(chosen, 0.0))
	angle_slider.set_value_no_signal(degrees)
	angle_value.text = "Кут: %d°" % int(degrees)
	if label_text.ends_with(" — великий"):
		selected_axis = 0
		for i in range(axis_buttons.size()):
			axis_buttons[i].text = ("● " if i == selected_axis else "") + ["X","Y","Z"][i]


func _adjust_angle(delta: int) -> void:
	if angle_slider == null:
		return
	angle_slider.value = clampf(angle_slider.value + float(delta), angle_slider.min_value, angle_slider.max_value)


func _reset_all_bones() -> void:
	if rig == null:
		return
	for index in range(original_rotations.size()):
		rig.set_bone_pose_rotation(index, original_rotations[index])

func _reset_pose() -> void:
	saved_rotations.clear()
	saved_angles.clear()
	saved_axes.clear()
	_reset_all_bones()
	angle_slider.set_value_no_signal(0.0)
	angle_value.text = "Кут: 0°"
	if handle_status != null:
		handle_status.text = "Відкрита кисть. Хват скинуто."

func _apply_angle(value: float) -> void:
	if rig == null:
		return
	angle_value.text = "Кут: %d°" % int(value)
	for bone_idx in selected:
		var name := String(rig.get_bone_name(bone_idx))
		var factor := 1.0
		if name.ends_with("2"):
			factor = 0.85
		elif name.ends_with("3"):
			factor = 0.70
		_set_test_rotation(bone_idx, value * factor, selected_axis)
	_update_stored_pose()


func _toggle_overlay() -> void:
	show_lines = not show_lines
	line_instance.visible = show_lines
	overlay_button.text = "КІСТКИ: УВІМКНЕНО" if show_lines else "КІСТКИ: ВИМКНЕНО"

func _focus_on(mode: int) -> void:
	focus_mode = mode
	if mode == 0:
		distance = 3.4
		focus = Vector3(0.0, 1.0, 0.0)
	else:
		var name := "mixamorig:LeftHand" if mode == 1 else "mixamorig:RightHand"
		var index := _bone_index(name)
		if index >= 0:
			focus = rig.to_global(rig.get_bone_global_pose(index).origin)
		distance = 0.43
	_update_camera()

func _update_camera() -> void:
	if orbit_camera == null:
		return
	var radius := cos(orbit_pitch) * distance
	orbit_camera.global_position = focus + Vector3(sin(orbit_yaw) * radius, sin(orbit_pitch) * distance, cos(orbit_yaw) * radius)
	orbit_camera.look_at(focus, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		orbit_yaw -= event.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.005, -0.8, 0.8)
		_update_camera()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		orbit_yaw -= event.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.005, -0.8, 0.8)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(0.18, distance * 0.9)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(7.0, distance * 1.1)
			_update_camera()

func _process(_delta: float) -> void:
	if rig == null or not show_lines:
		return
	line_mesh.clear_surfaces()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for child_index in range(rig.get_bone_count()):
		var parent_index := rig.get_bone_parent(child_index)
		if parent_index < 0:
			continue
		var start: Vector3 = rig.to_global(rig.get_bone_global_pose(parent_index).origin)
		var end: Vector3 = rig.to_global(rig.get_bone_global_pose(child_index).origin)
		var tint := Color(0.30, 1.0, 0.4) if child_index not in selected else Color(1.0, 0.66, 0.14)
		line_mesh.surface_set_color(tint)
		line_mesh.surface_add_vertex(start)
		line_mesh.surface_set_color(tint)
		line_mesh.surface_add_vertex(end)
	line_mesh.surface_end()
