extends RefCounted
# Builds visual HUD elements only. Input events and gameplay callbacks
# remain owned by main.gd so accepted controls are not reworked.


static func build_fps_counter(canvas: CanvasLayer) -> Label:
	# Top center stays clear of FULL (top left), ZOOM (top right) and actions.
	var panel := PanelContainer.new()
	panel.name = "FPSCounter"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -156.0
	panel.offset_right = 156.0
	panel.offset_top = 12.0
	panel.offset_bottom = 45.0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.05, 0.08, 0.11, 0.72)
	background.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", background)
	canvas.add_child(panel)

	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 10)
	panel.add_child(stats)

	var fps_label := Label.new()
	fps_label.name = "FPSLabel"
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.text = "FPS: --"
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_label.add_theme_font_size_override("font_size", 18)
	stats.add_child(fps_label)

	# No network session exists in this prototype. Do not fabricate ping values.
	var ping_label := Label.new()
	ping_label.name = "PingLabel"
	ping_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ping_label.text = "PING: — (offline)"
	ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ping_label.add_theme_font_size_override("font_size", 15)
	stats.add_child(ping_label)
	return fps_label


static func build_desktop_controls(canvas: CanvasLayer) -> Button:
	var panel := PanelContainer.new()
	panel.name = "HelpPanel"
	panel.position = Vector2(18, 18)
	canvas.add_child(panel)
	var label := Label.new()
	label.name = "HelpText"
	label.text = desktop_help_text("Sword I")
	panel.add_child(label)

	# Fullscreen must still be connected by the scene's gameplay controller.
	var fullscreen_button := Button.new()
	fullscreen_button.name = "FullscreenButton"
	fullscreen_button.text = "FULLSCREEN"
	fullscreen_button.anchor_left = 1.0
	fullscreen_button.anchor_right = 1.0
	fullscreen_button.offset_left = -132.0
	fullscreen_button.offset_right = -18.0
	fullscreen_button.offset_top = 18.0
	fullscreen_button.offset_bottom = 52.0
	canvas.add_child(fullscreen_button)
	return fullscreen_button


static func desktop_help_text(weapon_name: String, naruto_enabled: bool = false, ninja_visual_controls: bool = true, run_by_default: bool = true) -> String:
	var title := "NINJA 3D TEST" if ninja_visual_controls else "VROID 3D TEST"
	var mode := "біг" if run_by_default else "ходьба"
	var description := title + "\nWASD — " + mode + " | P — біг/ходьба | SHIFT — біг | Q — ривок\nSPACE — стрибок | ЛКМ — удар\nКолесо миші — масштаб | E — зброя\n"
	if ninja_visual_controls:
		description += "R — Naruto Run (" + ("ON" if naruto_enabled else "OFF") + ")   |   "
	return description + "Зброя: " + weapon_name
