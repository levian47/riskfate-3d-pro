extends Control
# Touch overlay: independent joystick, attack, jump and dash controls.
# Position and sizes adapt to viewport aspect ratio (landscape recommended).

signal attack_requested
signal dash_requested
signal zoom_requested
signal fullscreen_requested
signal weapon_requested
signal naruto_requested
signal skeleton_requested
signal materials_requested

var move_vector := Vector2.ZERO
var jump_held := false
var stick_finger := -1
var jump_finger := -1
var dash_finger := -1
var attack_finger := -1
var zoom_finger := -1
var fullscreen_finger := -1
var weapon_finger := -1
var naruto_finger := -1
var skeleton_finger := -1
var materials_finger := -1
var ninja_visual_controls := true # Disable Ninja-only MAT/RUN buttons for VRoid.
var naruto_run_enabled := false
var skeleton_enabled := false
var material_variant := 0
var weapon_index := 1
var zoom_level := 2
var stick_thumb := Vector2.ZERO
var portrait_mode := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	resized.connect(_on_resized)
	_on_resized()

func _on_resized() -> void:
	var now_portrait := size.y > size.x
	if now_portrait != portrait_mode:
		portrait_mode = now_portrait
		# Clear held controls when screen orientation changes.
		stick_finger = -1
		jump_finger = -1
		dash_finger = -1
		attack_finger = -1
		zoom_finger = -1
		fullscreen_finger = -1
		weapon_finger = -1
		naruto_finger = -1
		skeleton_finger = -1
		materials_finger = -1
		move_vector = Vector2.ZERO
		stick_thumb = Vector2.ZERO
		jump_held = false
	queue_redraw()

func _layout() -> Dictionary:
	var width := size.x
	var height := size.y
	var scale := clampf(minf(width / 1280.0, height / 720.0), 0.55, 1.5)
	var margin := 36.0 * scale
	var stick_radius := 107.5 * scale # 86 * 1.25
	# Secondary controls remain finger-accessible (at least 48px diameter)
	# while avoiding the oversized debug buttons of the first prototype.
	var zoom_radius := maxf(24.0, 30.0 * scale)
	var fullscreen_radius := maxf(24.0, 30.0 * scale)
	var attack_radius := 70.0 * scale
	var jump_radius := 46.0 * scale
	var dash_radius := 46.0 * scale
	return {
		"stick": Vector2(maxf(margin + stick_radius, width * 0.17), height - margin - stick_radius),
		"stick_radius": stick_radius,
		"attack": Vector2(width - margin - attack_radius, height - margin - attack_radius),
		"attack_radius": attack_radius,
		"jump": Vector2(width - margin - attack_radius * 2.50 - jump_radius, height - margin - jump_radius),
		"jump_radius": jump_radius,
		"dash": Vector2(width - margin - attack_radius * 2.30 - dash_radius, height - margin - attack_radius * 2.0 - dash_radius),
		"dash_radius": dash_radius,
		"zoom": Vector2(width - margin - zoom_radius, margin + zoom_radius),
		"zoom_radius": zoom_radius,
		"weapon": Vector2(width - margin - zoom_radius, margin + zoom_radius * 3.6),
		"weapon_radius": zoom_radius,
		"materials": Vector2(width - margin - zoom_radius, margin + zoom_radius * 6.2),
		"materials_radius": zoom_radius,
		"fullscreen": Vector2(margin + fullscreen_radius, margin + fullscreen_radius),
		"fullscreen_radius": fullscreen_radius,
		"naruto": Vector2(margin + fullscreen_radius, margin + fullscreen_radius * 3.6),
		"naruto_radius": fullscreen_radius,
		"skeleton": Vector2(margin + fullscreen_radius, margin + fullscreen_radius * 6.2),
		"skeleton_radius": fullscreen_radius
	}

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if portrait_mode:
			# Keep the fullscreen button accessible before turning the phone.
			if event.pressed:
				_press_fullscreen(event.index, event.position)
			else:
				_release(event.index)
			return
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif not portrait_mode and event is InputEventScreenDrag and event.index == stick_finger:
		_update_stick(event.position)

func _press_fullscreen(finger: int, point: Vector2) -> bool:
	var layout := _layout()
	if fullscreen_finger == -1 and point.distance_to(layout["fullscreen"]) <= layout["fullscreen_radius"] * 1.25:
		fullscreen_finger = finger
		# Browsers require the request to come directly from a press event.
		fullscreen_requested.emit()
		queue_redraw()
		return true
	return false

func _press(finger: int, point: Vector2) -> void:
	var layout := _layout()
	# Large thumb-friendly touch areas, with one owner finger per control.
	if stick_finger == -1 and point.distance_to(layout["stick"]) <= layout["stick_radius"] * 1.65:
		stick_finger = finger
		_update_stick(point)
	elif zoom_finger == -1 and point.distance_to(layout["zoom"]) <= layout["zoom_radius"] * 1.20:
		zoom_finger = finger
		zoom_requested.emit()
		queue_redraw()
	elif weapon_finger == -1 and point.distance_to(layout["weapon"]) <= layout["weapon_radius"] * 1.20:
		weapon_finger = finger
		weapon_requested.emit()
		queue_redraw()
	elif ninja_visual_controls and materials_finger == -1 and point.distance_to(layout["materials"]) <= layout["materials_radius"] * 1.20:
		materials_finger = finger
		materials_requested.emit()
		queue_redraw()
	elif ninja_visual_controls and naruto_finger == -1 and point.distance_to(layout["naruto"]) <= layout["naruto_radius"] * 1.20:
		naruto_finger = finger
		naruto_requested.emit()
		queue_redraw()
	elif skeleton_finger == -1 and point.distance_to(layout["skeleton"]) <= layout["skeleton_radius"] * 1.20:
		skeleton_finger = finger
		skeleton_requested.emit()
		queue_redraw()
	elif _press_fullscreen(finger, point):
		pass
	elif attack_finger == -1 and point.distance_to(layout["attack"]) <= layout["attack_radius"] * 1.18:
		attack_finger = finger
		attack_requested.emit()
		queue_redraw()
	elif jump_finger == -1 and point.distance_to(layout["jump"]) <= layout["jump_radius"] * 1.25:
		jump_finger = finger
		jump_held = true
		queue_redraw()
	elif dash_finger == -1 and point.distance_to(layout["dash"]) <= layout["dash_radius"] * 1.25:
		dash_finger = finger
		dash_requested.emit()
		queue_redraw()

func _release(finger: int) -> void:
	if finger == stick_finger:
		stick_finger = -1
		move_vector = Vector2.ZERO
		stick_thumb = Vector2.ZERO
	if finger == jump_finger:
		jump_finger = -1
		jump_held = false
	if finger == dash_finger:
		dash_finger = -1
	if finger == attack_finger:
		attack_finger = -1
	if finger == zoom_finger:
		zoom_finger = -1
	if finger == fullscreen_finger:
		fullscreen_finger = -1
	if finger == weapon_finger:
		weapon_finger = -1
	if finger == naruto_finger:
		naruto_finger = -1
	if finger == skeleton_finger:
		skeleton_finger = -1
	if finger == materials_finger:
		materials_finger = -1
	queue_redraw()

func _update_stick(point: Vector2) -> void:
	var layout := _layout()
	var center: Vector2 = layout["stick"]
	var distance: Vector2 = point - center
	var radius: float = layout["stick_radius"] * 0.76
	stick_thumb = distance.limit_length(radius)
	move_vector = stick_thumb / radius
	# Small dead zone avoids accidental creeping when holding center.
	if move_vector.length() < 0.13:
		move_vector = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	if portrait_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.08, 0.11, 0.86))
		var message := "Поверни телефон горизонтально"
		var font := ThemeDB.fallback_font
		var font_size := maxi(18, roundi(minf(size.x, size.y) * 0.055))
		var message_size := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, (size - message_size) * 0.5 + Vector2(0, message_size.y * 0.7), message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
		_draw_fullscreen_control(_layout())
		return
	var layout := _layout()
	var center: Vector2 = layout["stick"]
	var radius: float = layout["stick_radius"]
	_draw_button(center, radius, Color(0.05, 0.10, 0.16, 0.45), Color(0.78, 0.90, 1.0, 0.65))
	_draw_button(center + stick_thumb, radius * 0.42, Color(0.70, 0.82, 0.94, 0.73), Color(1.0, 1.0, 1.0, 0.85))
	var attack_center: Vector2 = layout["attack"]
	var attack_r: float = layout["attack_radius"]
	_draw_button(attack_center, attack_r, Color(0.67, 0.19, 0.16, 0.90 if attack_finger != -1 else 0.72), Color(1.0, 0.76, 0.65, 0.96))
	_draw_label(attack_center, "ATK", attack_r * 0.40)
	var jump_center: Vector2 = layout["jump"]
	var jump_r: float = layout["jump_radius"]
	_draw_button(jump_center, jump_r, Color(0.14, 0.38, 0.58, 0.91 if jump_held else 0.73), Color(0.75, 0.91, 1.0, 0.95))
	_draw_label(jump_center, "JUMP", jump_r * 0.33)
	var dash_center: Vector2 = layout["dash"]
	var dash_r: float = layout["dash_radius"]
	_draw_button(dash_center, dash_r, Color(0.63, 0.40, 0.12, 0.92 if dash_finger != -1 else 0.75), Color(1.0, 0.88, 0.58, 0.95))
	_draw_label(dash_center, "DASH", dash_r * 0.32)
	var zoom_center: Vector2 = layout["zoom"]
	var zoom_r: float = layout["zoom_radius"]
	_draw_button(zoom_center, zoom_r, Color(0.15, 0.25, 0.39, 0.94 if zoom_finger != -1 else 0.76), Color(0.76, 0.87, 1.0, 0.92))
	_draw_label(zoom_center + Vector2(0, -zoom_r * 0.18), "ZOOM", zoom_r * 0.29)
	_draw_label(zoom_center + Vector2(0, zoom_r * 0.28), "%d/4" % zoom_level, zoom_r * 0.34)
	var weapon_center: Vector2 = layout["weapon"]
	var weapon_r: float = layout["weapon_radius"]
	_draw_button(weapon_center, weapon_r, Color(0.33, 0.27, 0.44, 0.94 if weapon_finger != -1 else 0.83), Color(0.90, 0.82, 1.0, 0.96))
	_draw_label(weapon_center + Vector2(0, -weapon_r * 0.18), "WPN", weapon_r * 0.32)
	_draw_label(weapon_center + Vector2(0, weapon_r * 0.28), "%d/5" % weapon_index, weapon_r * 0.34)
	if ninja_visual_controls:
		var material_center: Vector2 = layout["materials"]
		var material_radius: float = layout["materials_radius"]
		_draw_button(material_center, material_radius, Color(0.23, 0.37, 0.31, 0.93 if materials_finger != -1 else 0.77), Color(0.77, 0.96, 0.86, 0.96))
		_draw_label(material_center + Vector2(0, -material_radius * 0.18), "MAT", material_radius * 0.30)
		_draw_label(material_center + Vector2(0, material_radius * 0.28), ["O", "A", "B"][material_variant], material_radius * 0.36)
		var naruto_center: Vector2 = layout["naruto"]
		var naruto_r: float = layout["naruto_radius"]
		_draw_button(naruto_center, naruto_r, Color(0.27, 0.45, 0.24, 0.95 if naruto_run_enabled else 0.65), Color(0.82, 0.98, 0.77, 0.94))
		_draw_label(naruto_center + Vector2(0, -naruto_r * 0.17), "RUN", naruto_r * 0.31)
		_draw_label(naruto_center + Vector2(0, naruto_r * 0.27), "N4" if naruto_run_enabled else "OFF", naruto_r * 0.27)
	var skeleton_center: Vector2 = layout["skeleton"]
	var skeleton_r: float = layout["skeleton_radius"]
	_draw_button(skeleton_center, skeleton_r, Color(0.16, 0.46, 0.47, 0.92 if skeleton_enabled else 0.70), Color(0.58, 1.0, 0.91, 0.98))
	_draw_label(skeleton_center + Vector2(0, -skeleton_r * 0.17), "SKEL", skeleton_r * 0.30)
	_draw_label(skeleton_center + Vector2(0, skeleton_r * 0.29), "ON" if skeleton_enabled else "OFF", skeleton_r * 0.27)
	_draw_fullscreen_control(layout)

func _draw_fullscreen_control(layout: Dictionary) -> void:
	var fullscreen_center: Vector2 = layout["fullscreen"]
	var fullscreen_r: float = layout["fullscreen_radius"]
	_draw_button(fullscreen_center, fullscreen_r, Color(0.14, 0.31, 0.32, 0.94 if fullscreen_finger != -1 else 0.85), Color(0.77, 0.99, 0.96, 1.0))
	_draw_label(fullscreen_center, "FULL", fullscreen_r * 0.34)

func _draw_button(center: Vector2, radius: float, inside: Color, outline: Color) -> void:
	draw_circle(center, radius, inside, true, -1.0, true)
	draw_arc(center, radius - 2.0, 0.0, TAU, 48, outline, 3.0, true)

func _draw_label(center: Vector2, label: String, font_size: float) -> void:
	var font := ThemeDB.fallback_font
	var pixels := maxi(13, roundi(font_size))
	var dimensions := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels)
	draw_string(font, center + Vector2(-dimensions.x / 2.0, dimensions.y * 0.34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, Color.WHITE)
