extends Node3D
## Isolated interactive rig examination. No gameplay / authored animations.

const SOURCE := preload("res://assets/characters/Riskfate_Male_FingerRig52_WEBPREVIEW.glb")

var rig: Skeleton3D
var orbit_camera: Camera3D
var line_mesh: ImmediateMesh
var line_instance: MeshInstance3D
var part_picker: OptionButton
var axis_picker: OptionButton
var angle_slider: HSlider
var angle_value: Label
var info_text: Label
var overlay_button: Button
var full_button: Button
var controls_panel: PanelContainer
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
	part_label.text = "ВИБІР ПАЛЬЦЯ / СУГЛОБА"
	controls.add_child(part_label)
	var picker_row := HBoxContainer.new()
	controls.add_child(picker_row)
	_make_button("◀", func() -> void: _step_selection(-1), picker_row)
	part_picker = OptionButton.new()
	part_picker.name = "BonePicker"
	part_picker.custom_minimum_size.y = 46
	part_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_row.add_child(part_picker)
	_make_button("▶", func() -> void: _step_selection(1), picker_row)
	_add_groups()
	part_picker.item_selected.connect(_on_part_changed)

	var axis_row := HBoxContainer.new()
	controls.add_child(axis_row)
	var axis_label := Label.new()
	axis_label.text = "ВІСЬ"
	axis_row.add_child(axis_label)
	axis_picker = OptionButton.new()
	axis_picker.name = "AxisPicker"
	axis_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axis_picker.custom_minimum_size.y = 46
	for axis_name in ["X", "Y", "Z"]:
		axis_picker.add_item(axis_name)
	axis_picker.select(2)
	axis_picker.item_selected.connect(func(_index: int) -> void: _apply_angle(angle_slider.value))
	axis_row.add_child(axis_picker)

	angle_value = Label.new()
	angle_value.text = "Кут: 0°"
	controls.add_child(angle_value)
	angle_slider = HSlider.new()
	angle_slider.name = "AngleSlider"
	angle_slider.min_value = -90
	angle_slider.max_value = 90
	angle_slider.step = 1
	angle_slider.custom_minimum_size = Vector2(190, 42)
	angle_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_slider.value_changed.connect(_apply_angle)
	controls.add_child(angle_slider)
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
	hint.text = "◀ ▶ — вибір. Повзунок — згинання. Прокрути панель угору/вниз, щоб побачити всі кнопки."
	controls.add_child(hint)

	full_button = Button.new()
	full_button.name = "FullscreenButton"
	full_button.text = "FULL"
	full_button.custom_minimum_size = Vector2(104, 46)
	full_button.pressed.connect(_toggle_fullscreen)
	ui_root.add_child(full_button)
	get_viewport().size_changed.connect(_layout_ui)
	_layout_ui()
	if part_picker.item_count > 0:
		var preferred := 1 if part_picker.item_count > 1 else 0
		part_picker.select(preferred)
		_on_part_changed(preferred)


func _layout_ui() -> void:
	if controls_panel == null or full_button == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_width := minf(326.0, maxf(230.0, viewport_size.x * 0.48))
	var panel_height := maxf(170.0, viewport_size.y - 24.0)
	controls_panel.position = Vector2(12.0, 12.0)
	controls_panel.size = Vector2(panel_width, panel_height)
	full_button.position = Vector2(viewport_size.x - 114.0, 12.0)
	full_button.size = Vector2(102.0, 46.0)


func _step_selection(delta: int) -> void:
	if part_picker == null or part_picker.item_count == 0:
		return
	var previous := part_picker.selected
	var next := posmod(previous + delta, part_picker.item_count)
	part_picker.select(next)
	_on_part_changed(next)


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
	part_picker.add_item(label_text)
	part_picker.set_item_metadata(part_picker.item_count - 1, matches)

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
	_reset_all_bones()
	selected.clear()
	var data = part_picker.get_item_metadata(item_index)
	for index in data:
		selected.append(int(index))
	angle_slider.set_value_no_signal(0.0)
	angle_value.text = "Кут: 0°"

func _reset_all_bones() -> void:
	if rig == null:
		return
	for index in range(original_rotations.size()):
		rig.set_bone_pose_rotation(index, original_rotations[index])

func _reset_pose() -> void:
	_reset_all_bones()
	angle_slider.set_value_no_signal(0.0)
	angle_value.text = "Кут: 0°"

func _apply_angle(value: float) -> void:
	if rig == null:
		return
	_reset_all_bones()
	angle_value.text = "Кут: %d°" % int(value)
	var axis := Vector3.RIGHT
	if axis_picker.selected == 1:
		axis = Vector3.UP
	elif axis_picker.selected == 2:
		axis = Vector3.BACK
	for bone_index in selected:
		var bone_name := String(rig.get_bone_name(bone_index))
		var joint_factor := 1.0
		if bone_name.ends_with("2"):
			joint_factor = 0.85
		elif bone_name.ends_with("3"):
			joint_factor = 0.70
		var rotation := Quaternion(axis, deg_to_rad(value * joint_factor))
		rig.set_bone_pose_rotation(bone_index, original_rotations[bone_index] * rotation)

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
