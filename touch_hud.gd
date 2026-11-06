extends Control
# A touch-only overlay: independent multitouch joystick + attack/jump buttons.
# Position and sizes adapt to viewport aspect ratio (landscape recommended).

signal attack_requested
signal zoom_requested

var move_vector := Vector2.ZERO
var jump_held := false
var stick_finger := -1
var jump_finger := -1
var attack_finger := -1
var zoom_finger := -1
var zoom_level := 2
var stick_thumb := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	resized.connect(queue_redraw)
	queue_redraw()

func _layout() -> Dictionary:
	var width := size.x
	var height := size.y
	var scale := clampf(minf(width / 1280.0, height / 720.0), 0.55, 1.5)
	var margin := 36.0 * scale
	var stick_radius := 107.5 * scale # 86 * 1.25
	var zoom_radius := 43.0 * scale
	var attack_radius := 70.0 * scale
	var jump_radius := 46.0 * scale
	return {
		"stick": Vector2(maxf(margin + stick_radius, width * 0.17), height - margin - stick_radius),
		"stick_radius": stick_radius,
		"attack": Vector2(width - margin - attack_radius, height - margin - attack_radius),
		"attack_radius": attack_radius,
		"jump": Vector2(width - margin - attack_radius * 2.30 - jump_radius, height - margin - attack_radius * 2.0 - jump_radius),
		"jump_radius": jump_radius,
		"zoom": Vector2(width - margin - zoom_radius, margin + zoom_radius),
		"zoom_radius": zoom_radius
	}

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag and event.index == stick_finger:
		_update_stick(event.position)

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
	elif attack_finger == -1 and point.distance_to(layout["attack"]) <= layout["attack_radius"] * 1.18:
		attack_finger = finger
		attack_requested.emit()
		queue_redraw()
	elif jump_finger == -1 and point.distance_to(layout["jump"]) <= layout["jump_radius"] * 1.25:
		jump_finger = finger
		jump_held = true
		queue_redraw()

func _release(finger: int) -> void:
	if finger == stick_finger:
		stick_finger = -1
		move_vector = Vector2.ZERO
		stick_thumb = Vector2.ZERO
	if finger == jump_finger:
		jump_finger = -1
		jump_held = false
	if finger == attack_finger:
		attack_finger = -1
	if finger == zoom_finger:
		zoom_finger = -1
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
	var zoom_center: Vector2 = layout["zoom"]
	var zoom_r: float = layout["zoom_radius"]
	_draw_button(zoom_center, zoom_r, Color(0.15, 0.25, 0.39, 0.94 if zoom_finger != -1 else 0.76), Color(0.76, 0.87, 1.0, 0.92))
	_draw_label(zoom_center + Vector2(0, -zoom_r * 0.18), "ZOOM", zoom_r * 0.29)
	_draw_label(zoom_center + Vector2(0, zoom_r * 0.28), "%d/3" % zoom_level, zoom_r * 0.34)

func _draw_button(center: Vector2, radius: float, inside: Color, outline: Color) -> void:
	draw_circle(center, radius, inside, true, -1.0, true)
	draw_arc(center, radius - 2.0, 0.0, TAU, 48, outline, 3.0, true)

func _draw_label(center: Vector2, label: String, font_size: float) -> void:
	var font := ThemeDB.fallback_font
	var pixels := maxi(13, roundi(font_size))
	var dimensions := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels)
	draw_string(font, center + Vector2(-dimensions.x / 2.0, dimensions.y * 0.34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, Color.WHITE)
