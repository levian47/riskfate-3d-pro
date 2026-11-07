extends RefCounted
# Player locomotion state. This is the same movement model as the accepted
# prototype: immediate steering, coyote/buffer jumps and camera-relative dash.
# The main scene owns combat, animation-state requests, camera and UI.

const WALK_SPEED := 7.0
const RUN_SPEED := 12.0
const DASH_SPEED := 24.0
const DASH_DURATION := 0.18
const DASH_COOLDOWN := 0.85
const JUMP_SPEED := 8.0
const GRAVITY := 22.0
const JUMP_RELEASE_MULTIPLIER := 0.55
const COYOTE_TIME := 0.11
const JUMP_BUFFER_TIME := 0.13

var coyote_left := 0.0
var jump_buffer_left := 0.0
var jump_was_pressed := false
var last_move_direction := Vector3.FORWARD
var dash_direction := Vector3.FORWARD
var dash_time_left := 0.0
var dash_cooldown_left := 0.0


func camera_relative_direction(input_vector: Vector2, camera: Camera3D) -> Vector3:
	var camera_right := camera.global_transform.basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var camera_forward := -camera.global_transform.basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	return camera_right * input_vector.x - camera_forward * input_vector.y


func start_dash(touch_hud, camera: Camera3D) -> void:
	if dash_cooldown_left > 0.0 or dash_time_left > 0.0:
		return
	var intended_direction := Vector3.ZERO
	if touch_hud != null:
		intended_direction = camera_relative_direction(touch_hud.move_vector, camera)
	if intended_direction.length_squared() < 0.01:
		intended_direction = last_move_direction
	dash_direction = intended_direction.normalized()
	dash_time_left = DASH_DURATION
	dash_cooldown_left = DASH_COOLDOWN


func physics_step(hero: CharacterBody3D, visual: Node3D, camera: Camera3D, touch_hud, delta: float) -> bool:
	var grounded_before := hero.is_on_floor()
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)

	# Keep the original input polling, short-tap buffering and coyote time.
	var jump_pressed: bool = Input.is_key_pressed(KEY_SPACE)
	if touch_hud != null:
		jump_pressed = jump_pressed or bool(touch_hud.jump_held)
	if jump_pressed and not jump_was_pressed:
		jump_buffer_left = JUMP_BUFFER_TIME
	jump_was_pressed = jump_pressed
	jump_buffer_left = maxf(0.0, jump_buffer_left - delta)
	if grounded_before:
		coyote_left = COYOTE_TIME
	else:
		coyote_left = maxf(0.0, coyote_left - delta)

	var keyboard_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()
	var input_vector := keyboard_input
	var mobile_running := false
	if touch_hud != null and touch_hud.move_vector.length_squared() > 0.0001:
		input_vector = touch_hud.move_vector
		mobile_running = input_vector.length() >= 0.77

	var direction := camera_relative_direction(input_vector, camera)
	if direction.length_squared() > 0.01:
		last_move_direction = direction.normalized()
	var target_speed := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) or mobile_running else WALK_SPEED
	var facing_direction := direction
	if dash_time_left > 0.0:
		facing_direction = dash_direction
		hero.velocity.x = dash_direction.x * DASH_SPEED
		hero.velocity.z = dash_direction.z * DASH_SPEED
		dash_time_left = maxf(0.0, dash_time_left - delta)
	else:
		hero.velocity.x = direction.x * target_speed
		hero.velocity.z = direction.z * target_speed

	var launched := false
	if jump_buffer_left > 0.0 and coyote_left > 0.0:
		hero.velocity.y = JUMP_SPEED
		jump_buffer_left = 0.0
		coyote_left = 0.0
		launched = true
	elif not grounded_before:
		hero.velocity.y -= GRAVITY * delta
		if not jump_pressed and hero.velocity.y > 0.0:
			hero.velocity.y -= GRAVITY * (1.0 / JUMP_RELEASE_MULTIPLIER - 1.0) * delta
	else:
		hero.velocity.y = -0.1

	hero.move_and_slide()
	if facing_direction.length_squared() > 0.01:
		# Retain the imported rig's 180-degree correction without turn lag.
		visual.rotation.y = atan2(-facing_direction.x, -facing_direction.z) + PI
	return launched
