extends RefCounted
# Stateless movement calculations. The main controller owns timers, input
# callbacks and animation transitions so accepted controls remain unchanged.

static func camera_relative_direction(camera: Camera3D, input_vector: Vector2) -> Vector3:
	var camera_right := camera.global_transform.basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var camera_forward := -camera.global_transform.basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	return camera_right * input_vector.x - camera_forward * input_vector.y


static func read_keyboard_move() -> Vector2:
	return Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()


static func horizontal_velocity(direction: Vector3, speed: float) -> Vector3:
	return Vector3(direction.x * speed, 0.0, direction.z * speed)


static func apply_vertical_velocity(body: CharacterBody3D, grounded: bool, jump_pressed: bool, can_jump: bool, delta: float, jump_speed: float, gravity: float, release_multiplier: float) -> bool:
	if can_jump:
		body.velocity.y = jump_speed
		return true
	if not grounded:
		body.velocity.y -= gravity * delta
		# Releasing jump early produces the approved shorter jump.
		if not jump_pressed and body.velocity.y > 0.0:
			body.velocity.y -= gravity * (1.0 / release_multiplier - 1.0) * delta
	else:
		body.velocity.y = -0.1
	return false


static func apply_facing(visual: Node3D, direction: Vector3, delta: float = 0.0) -> void:
	if direction.length_squared() > 0.01:
		# Keep the imported rig's 180-degree correction. Smooth only the visual
		# heading; velocity and direction changes remain immediate.
		var target_y := atan2(-direction.x, -direction.z) + PI
		if delta > 0.0:
			visual.rotation.y = lerp_angle(visual.rotation.y, target_y, minf(1.0, delta * 12.0))
		else:
			visual.rotation.y = target_y
