extends Control
## Resolution-independent clickable anatomy map for the isolated Rig Lab.
## Drawn from polygons: visible boundaries are also the actual hit regions.

signal body_selected(region: String)
signal finger_selected(finger: String)

const BODY_SIZE := Vector2(200.0, 320.0)
const HAND_SIZE := Vector2(200.0, 250.0)
const FILL := Color("#526578")
const OUTLINE := Color("#a4bacb")
const ACTIVE := Color("#edb661")
const HOVER := Color("#80cbd1")
const MUTED := Color("#32465a")

var mode := "body"
var hand_side := "Left"
var active_region := ""
var hover_region := ""
var regions: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(180.0, 310.0)
	_rebuild()


func set_view(next_mode: String, side: String = "Left") -> void:
	mode = "hand" if next_mode == "hand" else "body"
	hand_side = side
	active_region = ""
	hover_region = ""
	custom_minimum_size.y = 240.0 if mode == "hand" else 310.0
	_rebuild()
	update_minimum_size()
	queue_redraw()


func mark_region(region: String) -> void:
	active_region = region
	queue_redraw()


func _shape(region: String, flat_points: Array) -> void:
	var polygon := PackedVector2Array()
	for index in range(0, flat_points.size(), 2):
		polygon.append(Vector2(float(flat_points[index]), float(flat_points[index + 1])))
	regions.append({"id": region, "polygon": polygon})


func _mirrored(region: String, flat_points: Array) -> void:
	_shape(region, flat_points)
	var counterpart := PackedVector2Array()
	var original: PackedVector2Array = regions[regions.size() - 1]["polygon"]
	for point in original:
		counterpart.append(Vector2(200.0 - point.x, point.y))
	regions.append({"id": region.replace("Right", "Left"), "polygon": counterpart})


func _rebuild() -> void:
	regions.clear()
	if mode == "body":
		# Front-facing anatomy: screen left is the character's right side.
		_shape("Head", [100, 6, 112, 10, 120, 22, 120, 36, 112, 49, 100, 54, 88, 49, 80, 36, 80, 22, 88, 10])
		_shape("Neck", [91, 52, 109, 52, 112, 67, 88, 67])
		_mirrored("RightLeg", [69, 230, 89, 233, 85, 276, 82, 291, 63, 291, 61, 271])
		_mirrored("RightLeg", [63, 287, 82, 287, 89, 305, 54, 305, 54, 299])
		_mirrored("RightUpLeg", [75, 162, 100, 169, 96, 208, 89, 237, 68, 232, 69, 204])
		_shape("Pelvis", [73, 134, 127, 134, 133, 165, 119, 178, 100, 170, 81, 178, 67, 165])
		_shape("Torso", [86, 64, 114, 64, 135, 78, 131, 109, 122, 141, 78, 141, 69, 109, 65, 78])
		_mirrored("RightArm", [71, 68, 56, 73, 47, 89, 37, 120, 53, 126, 64, 98, 76, 83])
		_mirrored("RightForeArm", [37, 118, 53, 124, 45, 157, 38, 184, 23, 179, 27, 151])
		_mirrored("RightHand", [23, 178, 38, 182, 40, 200, 36, 219, 28, 226, 20, 218, 16, 195])
	else:
		# A small hand silhouette, with five independent finger hit regions.
		# The finger-joint controls in Rig Lab remain the precise second level.
		_shape("", [60, 124, 151, 124, 154, 206, 142, 228, 80, 230, 61, 211])
		_shape("Thumb", [60, 152, 42, 135, 20, 110, 15, 93, 23, 83, 35, 85, 70, 125, 79, 143])
		_shape("Index", [65, 142, 60, 64, 62, 42, 73, 35, 84, 42, 85, 141])
		_shape("Middle", [85, 138, 84, 43, 88, 18, 100, 15, 111, 23, 109, 139])
		_shape("Ring", [111, 141, 114, 43, 119, 29, 131, 28, 141, 40, 134, 144])
		_shape("Pinky", [137, 147, 143, 69, 149, 57, 160, 57, 169, 69, 158, 156])
		if hand_side == "Right":
			for item in regions:
				var flipped := PackedVector2Array()
				for point in item["polygon"]:
					flipped.append(Vector2(200.0 - point.x, point.y))
				item["polygon"] = flipped


func _map_scale() -> float:
	var design := HAND_SIZE if mode == "hand" else BODY_SIZE
	return minf(size.x / design.x, size.y / design.y)


func _map_origin() -> Vector2:
	var design := HAND_SIZE if mode == "hand" else BODY_SIZE
	return (size - design * _map_scale()) * 0.5


func _draw() -> void:
	var design := HAND_SIZE if mode == "hand" else BODY_SIZE
	draw_set_transform(_map_origin(), 0.0, _map_scale() * Vector2.ONE)
	# Subtle technical guides frame the illustration without obscuring anatomy.
	for x in [24.0, 100.0, 176.0]:
		draw_line(Vector2(x, 4), Vector2(x, design.y - 4), Color(0.33, 0.49, 0.60, 0.13), 1.0)
	for y in [64.0, 144.0, 224.0]:
		if y < design.y:
			draw_line(Vector2(12, y), Vector2(188, y), Color(0.33, 0.49, 0.60, 0.13), 1.0)
	for item in regions:
		var region: String = item["id"]
		var polygon: PackedVector2Array = item["polygon"]
		var tint := MUTED if region.is_empty() or region == "Torso" or region == "Pelvis" else FILL
		if region == hover_region and not region.is_empty():
			tint = HOVER
		if region == active_region and not region.is_empty():
			tint = ACTIVE
		draw_colored_polygon(polygon, tint)
		var ring := polygon.duplicate()
		ring.append(polygon[0])
		draw_polyline(ring, OUTLINE if region != active_region else Color("#ffe3a7"), 1.6, true)
	if mode == "hand":
		# Fine palm creases and knuckle landmarks, kept noninteractive.
		for x in [75.0, 99.0, 126.0, 151.0]:
			var position := Vector2(x if hand_side == "Left" else 200.0 - x, 144.0)
			draw_circle(position, 2.5, Color("#b9d1dd"))
		var a := Vector2(80, 205)
		var b := Vector2(141, 205)
		if hand_side == "Right":
			a.x = 200 - a.x
			b.x = 200 - b.x
		draw_line(a, b, Color("#8da7bb"), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _region_at(position: Vector2) -> String:
	var p := (position - _map_origin()) / maxf(_map_scale(), 0.001)
	for index in range(regions.size() - 1, -1, -1):
		var item: Dictionary = regions[index]
		if Geometry2D.is_point_in_polygon(p, item["polygon"]):
			return String(item["id"])
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var next_hover := _region_at(event.position)
		if next_hover != hover_region:
			hover_region = next_hover
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var region := _region_at(event.position)
		if region.is_empty():
			return
		active_region = region
		queue_redraw()
		if mode == "body":
			body_selected.emit(region)
		else:
			finger_selected.emit(region)
		accept_event()
