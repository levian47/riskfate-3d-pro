extends Node3D

const MODEL := preload("res://assets/Ninja_Female.gltf")
# Ninja movement tuning. The approved v4 camera directions stay unchanged.
const WALK_SPEED := 7.0
const RUN_SPEED := 12.0
# Steering responds directly to the joystick, without acceleration or turning lag.
# Dash values are provisional until playtested on a real phone.
const DASH_SPEED := 24.0
const DASH_DURATION := 0.18
const DASH_COOLDOWN := 0.85
const JUMP_SPEED := 8.0
const GRAVITY := 22.0
const JUMP_RELEASE_MULTIPLIER := 0.55
const COYOTE_TIME := 0.11
const JUMP_BUFFER_TIME := 0.13
const MOVE_ANIMATION_THRESHOLD := 0.45
const TOUCH_HUD_SCRIPT := preload("res://touch_hud.gd")
const HUD_BUILDER := preload("res://ui/hud_builder.gd")
const ANIMATION_BUILDER := preload("res://characters/player/animation_builder.gd")
const MOVEMENT_MATH := preload("res://characters/player/movement_math.gd")
const WORLD_SCRIPT := preload("res://world/environment.gd")
# The attack runs on the upper body while the legs retain their movement animation.
const ATTACK_SPEED := 1.65
# Prototype combat parameters. Not approved balance values.
const TRAINING_HIT_DAMAGE := 25
const TRAINING_HIT_REACH := 3.1
const TRAINING_HIT_FACING_DOT := 0.60
const TRAINING_HIT_MOMENT := 0.42

var hero: CharacterBody3D
var visual: Node3D
var animator: AnimationPlayer
var camera: Camera3D
var camera_distance := 13.0
var camera_zoom := 12.0
# Orthographic camera sizes: lower value = closer view.
const MOBILE_ZOOM_LEVELS := [8.0, 12.0, 18.0]
var mobile_zoom_index := 1
var animation_tree: AnimationTree
var locomotion_state := ""
var attack_time_left := 0.0
var attack_duration := 0.0
var attack_hit_pending := false
var coyote_left := 0.0
var jump_buffer_left := 0.0
var jump_was_pressed := false
var last_move_direction := Vector3.FORWARD
var dash_direction := Vector3.FORWARD
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var touch_hud
var fps_label: Label
var fps_update_elapsed := 0.0

func _ready() -> void:
	_build_environment()
	_build_hero()
	_build_camera()
	_build_ui()

func _process(delta: float) -> void:
	# Sample twice per second to keep the counter readable and inexpensive.
	if fps_label == null:
		return
	fps_update_elapsed += delta
	if fps_update_elapsed >= 0.5:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
		fps_update_elapsed = 0.0


func _physics_process(delta: float) -> void:
	var grounded_before := hero.is_on_floor()
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	if attack_time_left > 0.0:
		attack_time_left = maxf(0.0, attack_time_left - delta)
		if attack_hit_pending and attack_time_left <= attack_duration * (1.0 - TRAINING_HIT_MOMENT):
			attack_hit_pending = false
			_resolve_training_hit()

	# Keyboard polling is retained for the existing desktop prototype.
	# Edge detection and input buffering make short taps more reliable.
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

	var keyboard_input := MOVEMENT_MATH.read_keyboard_move()
	# Joystick has analog strength; stick pushed fully outward = running.
	var input_vector := keyboard_input
	var mobile_running := false
	if touch_hud != null and touch_hud.move_vector.length_squared() > 0.0001:
		input_vector = touch_hud.move_vector
		mobile_running = input_vector.length() >= 0.77
	# Ground and air steering match the joystick immediately, including reversals.
	var direction := MOVEMENT_MATH.camera_relative_direction(camera, input_vector)
	if direction.length_squared() > 0.01:
		last_move_direction = direction.normalized()
	var target_speed := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) or mobile_running else WALK_SPEED
	var facing_direction := direction
	if dash_time_left > 0.0:
		facing_direction = dash_direction
		var dash_velocity := MOVEMENT_MATH.horizontal_velocity(dash_direction, DASH_SPEED)
		hero.velocity.x = dash_velocity.x
		hero.velocity.z = dash_velocity.z
		dash_time_left = maxf(0.0, dash_time_left - delta)
	else:
		var move_velocity := MOVEMENT_MATH.horizontal_velocity(direction, target_speed)
		hero.velocity.x = move_velocity.x
		hero.velocity.z = move_velocity.z

	var launched := MOVEMENT_MATH.apply_vertical_velocity(
		hero, grounded_before, jump_pressed,
		jump_buffer_left > 0.0 and coyote_left > 0.0,
		delta, JUMP_SPEED, GRAVITY, JUMP_RELEASE_MULTIPLIER
	)
	if launched:
		jump_buffer_left = 0.0
		coyote_left = 0.0

	hero.move_and_slide()

	MOVEMENT_MATH.apply_facing(visual, facing_direction)

	# Locomotion keeps updating throughout the attack (including jumps).
	if launched:
		_set_locomotion("Jump", true)
	elif not hero.is_on_floor():
		_set_locomotion("Jump")
	else:
		var actual_speed := Vector2(hero.velocity.x, hero.velocity.z).length()
		if actual_speed < MOVE_ANIMATION_THRESHOLD:
			_set_locomotion("Idle")
		elif actual_speed >= (WALK_SPEED + RUN_SPEED) * 0.5:
			_set_locomotion("Run")
		else:
			_set_locomotion("Walk")
		if animation_tree != null:
			animation_tree.set("parameters/WalkSpeed/scale", clampf(actual_speed / WALK_SPEED, 0.85, 1.25))
			animation_tree.set("parameters/RunSpeed/scale", clampf(actual_speed / RUN_SPEED, 0.85, 1.25))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		_start_dash()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_start_attack()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_zoom = maxf(5.0, camera_zoom - 1.0)
			camera.size = camera_zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_zoom = minf(28.0, camera_zoom + 1.0)
			camera.size = camera_zoom

func _start_dash() -> void:
	if dash_cooldown_left > 0.0 or dash_time_left > 0.0:
		return
	var intended_direction := Vector3.ZERO
	if touch_hud != null:
		intended_direction = MOVEMENT_MATH.camera_relative_direction(camera, touch_hud.move_vector)
	if intended_direction.length_squared() < 0.01:
		intended_direction = last_move_direction
	dash_direction = intended_direction.normalized()
	dash_time_left = DASH_DURATION
	dash_cooldown_left = DASH_COOLDOWN


func _toggle_fullscreen() -> void:
	# On Web this is called directly from a real button/touch event.
	var current_mode := DisplayServer.window_get_mode()
	var is_fullscreen := current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _cycle_mobile_zoom() -> void:
	mobile_zoom_index = (mobile_zoom_index + 1) % MOBILE_ZOOM_LEVELS.size()
	camera_zoom = float(MOBILE_ZOOM_LEVELS[mobile_zoom_index])
	camera.size = camera_zoom
	if touch_hud != null:
		touch_hud.zoom_level = mobile_zoom_index + 1
		touch_hud.queue_redraw()

func _build_hero() -> void:
	hero = CharacterBody3D.new()
	hero.name = "Ninja"
	hero.position = Vector3(0, 0.2, 0)
	add_child(hero)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 2.8
	collision.shape = capsule
	collision.position.y = 1.4
	hero.add_child(collision)
	visual = Node3D.new()
	visual.name = "Visual"
	hero.add_child(visual)
	var model := MODEL.instantiate()
	visual.add_child(model)
	animator = ANIMATION_BUILDER.find_animation_player(model)
	if animator != null:
		# Preserve imported locomotion loop behavior and accepted attack clips.
		ANIMATION_BUILDER.configure_animation_loops(animator)
		_attach_simple_sword(model)
		animation_tree = ANIMATION_BUILDER.setup_animation_tree(model, animator, ATTACK_SPEED)
		if animation_tree != null:
			_set_locomotion("Idle")
	else:
		push_warning("AnimationPlayer not found in imported model")

func _start_attack() -> void:
	if animation_tree == null or attack_time_left > 0.0:
		return
	var clip_name := ANIMATION_BUILDER.find_clip(animator, "SwordSlash")
	if clip_name.is_empty():
		return
	attack_duration = animator.get_animation(clip_name).length / ATTACK_SPEED
	attack_time_left = attack_duration
	attack_hit_pending = true
	animation_tree.set("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _resolve_training_hit() -> void:
	# The current training step uses a forward reach check; it does not claim
	# accurate sword-blade collisions or a complete combat damage system.
	var target := get_node_or_null("Environment/TrainingDummy") as StaticBody3D
	if target == null or not target.has_method("take_damage") or not target.get("is_available"):
		return
	var offset := target.global_position - hero.global_position
	var height_difference := absf(offset.y)
	offset.y = 0.0
	var distance := offset.length()
	if distance > TRAINING_HIT_REACH or distance < 0.001 or height_difference > 2.2:
		return
	# Model has a 180° facing correction: its local +Z is the strike direction.
	var facing := visual.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized()
	if facing.dot(offset / distance) < TRAINING_HIT_FACING_DOT:
		return
	target.take_damage(TRAINING_HIT_DAMAGE)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null

func _attach_simple_sword(model: Node) -> void:
	# This GLTF contains SwordSlash animation but no separate sword mesh.
	# Attach a low-poly placeholder weapon to the right hand bone.
	var skeleton := _find_skeleton(model)
	if skeleton == null or skeleton.find_bone("Fist.R") == -1:
		push_warning("Right-hand bone not found: sword placeholder omitted")
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "SwordGrip"
	attachment.bone_name = "Fist.R"
	skeleton.add_child(attachment)
	var sword := Node3D.new()
	sword.name = "SimpleSword"
	# Alignment is approximate and can be adjusted for this imported rig.
	sword.rotation_degrees = Vector3(0, 0, 0)
	attachment.add_child(sword)
	_add_sword_part(sword, "Handle", Vector3(0.10, 0.36, 0.10), Vector3(0, 0.0, 0), Color("493329"))
	_add_sword_part(sword, "Guard", Vector3(0.45, 0.09, 0.13), Vector3(0, 0.22, 0), Color("bca267"))
	_add_sword_part(sword, "Blade", Vector3(0.13, 1.05, 0.065), Vector3(0, 0.78, 0), Color("c9dae1"))

func _add_sword_part(parent: Node3D, part_name: String, dimensions: Vector3, offset: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	part.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.35
	part.material_override = material
	part.position = offset
	parent.add_child(part)

func _set_locomotion(state: String, restart: bool = false) -> void:
	if animation_tree == null:
		return
	if state == locomotion_state and not restart:
		return
	animation_tree.set("parameters/Locomotion/transition_request", state)
	locomotion_state = state


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "IsometricCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_zoom
	camera.current = true
	# Parent the camera to the collision body so there is no lag or drifting.
	# Camera retains its constant rotation and position relative to the hero.
	camera.position = Vector3(9, camera_distance, 9)
	hero.add_child(camera)
	camera.look_at(hero.global_position + Vector3(0, 1.2, 0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("b9d6e4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e7eff3")
	env.ambient_light_energy = 0.7
	world.environment = env
	add_child(world)

func _build_environment() -> void:
	var environment := WORLD_SCRIPT.new()
	environment.name = "Environment"
	add_child(environment)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	fps_label = HUD_BUILDER.build_fps_counter(canvas)
	if DisplayServer.is_touchscreen_available():
		# Multiple fingers are handled independently in touch_hud.gd.
		touch_hud = TOUCH_HUD_SCRIPT.new()
		touch_hud.name = "MobileControls"
		canvas.add_child(touch_hud)
		touch_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		touch_hud.attack_requested.connect(_start_attack)
		touch_hud.dash_requested.connect(_start_dash)
		touch_hud.zoom_requested.connect(_cycle_mobile_zoom)
		touch_hud.fullscreen_requested.connect(_toggle_fullscreen)
		touch_hud.zoom_level = mobile_zoom_index + 1
		return
	var fullscreen_button := HUD_BUILDER.build_desktop_controls(canvas)
	fullscreen_button.pressed.connect(_toggle_fullscreen)
