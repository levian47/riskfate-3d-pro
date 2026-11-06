extends Node3D

const MODEL := preload("res://assets/Ninja_Female.gltf")
# Ninja movement tuning. The approved v4 camera directions stay unchanged.
const WALK_SPEED := 7.0
const RUN_SPEED := 12.0
const GROUND_ACCELERATION := 48.0
const GROUND_BRAKING := 62.0
const AIR_ACCELERATION := 15.0
const TURN_SPEED := 13.0
const JUMP_SPEED := 8.0
const GRAVITY := 22.0
const JUMP_RELEASE_MULTIPLIER := 0.55
const COYOTE_TIME := 0.11
const JUMP_BUFFER_TIME := 0.13
const MOVE_ANIMATION_THRESHOLD := 0.45
const TOUCH_HUD_SCRIPT := preload("res://touch_hud.gd")

var hero: CharacterBody3D
var visual: Node3D
var animator: AnimationPlayer
var camera: Camera3D
var camera_distance := 15.0
var camera_zoom := 12.0
# Orthographic camera sizes: lower value = closer view.
const MOBILE_ZOOM_LEVELS := [8.0, 12.0, 18.0]
var mobile_zoom_index := 1
var current_animation := ""
var attack_time_left := 0.0
var coyote_left := 0.0
var jump_buffer_left := 0.0
var jump_was_pressed := false
var jump_animation_active := false
var touch_hud

func _ready() -> void:
	_build_environment()
	_build_hero()
	_build_camera()
	_build_ui()

func _physics_process(delta: float) -> void:
	var grounded_before := hero.is_on_floor()
	if attack_time_left > 0.0:
		attack_time_left = maxf(0.0, attack_time_left - delta)
		if attack_time_left <= 0.0:
			current_animation = ""

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

	var keyboard_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()
	# Joystick has analog strength; stick pushed fully outward = running.
	var input_vector := keyboard_input
	var mobile_running := false
	if touch_hud != null and touch_hud.move_vector.length_squared() > 0.0001:
		input_vector = touch_hud.move_vector
		mobile_running = input_vector.length() >= 0.77
	# Movement is always aligned with screen space, not world X/Z axes.
	var camera_right := camera.global_transform.basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var camera_forward := -camera.global_transform.basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var direction := (camera_right * input_vector.x - camera_forward * input_vector.y)
	var target_speed := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) or mobile_running else WALK_SPEED
	var target_velocity := direction * target_speed

	var acceleration := AIR_ACCELERATION
	if grounded_before:
		acceleration = GROUND_ACCELERATION if direction.length_squared() > 0.01 else GROUND_BRAKING
	var horizontal := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	horizontal = horizontal.move_toward(target_velocity, acceleration * delta)
	hero.velocity.x = horizontal.x
	hero.velocity.z = horizontal.z

	var launched := false
	if jump_buffer_left > 0.0 and coyote_left > 0.0:
		hero.velocity.y = JUMP_SPEED
		jump_buffer_left = 0.0
		coyote_left = 0.0
		jump_animation_active = true
		launched = true
	elif not grounded_before:
		hero.velocity.y -= GRAVITY * delta
		# Releasing Space early makes a shorter jump.
		if not jump_pressed and hero.velocity.y > 0.0:
			hero.velocity.y -= GRAVITY * (1.0 / JUMP_RELEASE_MULTIPLIER - 1.0) * delta
	else:
		hero.velocity.y = -0.1

	hero.move_and_slide()

	if direction.length_squared() > 0.01:
		# Keep the model-specific 180-degree facing correction from v4.
		var facing := atan2(-direction.x, -direction.z) + PI
		visual.rotation.y = lerp_angle(visual.rotation.y, facing, minf(TURN_SPEED * delta, 1.0))

	# Full attack animation has priority over movement and jumping.
	if attack_time_left > 0.0:
		return

	if launched:
		_play_animation("Jump", true)
	elif not hero.is_on_floor():
		if not jump_animation_active:
			_play_animation("Jump", true)
			jump_animation_active = true
	else:
		jump_animation_active = false
		var actual_speed := Vector2(hero.velocity.x, hero.velocity.z).length()
		if actual_speed < MOVE_ANIMATION_THRESHOLD:
			_play_animation("Idle")
		elif actual_speed >= (WALK_SPEED + RUN_SPEED) * 0.5:
			_play_animation("Run")
		else:
			_play_animation("Walk")
		# The animation transitions use crossfades; movement remains responsive.
		if animator != null:
			if current_animation == "Walk":
				animator.speed_scale = clampf(actual_speed / WALK_SPEED, 0.85, 1.25)
			elif current_animation == "Run":
				animator.speed_scale = clampf(actual_speed / RUN_SPEED, 0.85, 1.25)
			else:
				animator.speed_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
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
	animator = _find_animation_player(model)
	if animator != null:
		# Imported glTF clips are often not marked as looping. Without this,
		# Run/Walk stops moving the legs at the last frame while the body moves.
		_configure_animation_loops()
		_attach_simple_sword(model)
		_play_animation("Idle")
	else:
		push_warning("AnimationPlayer not found in imported model")

func _start_attack() -> void:
	if animator == null or attack_time_left > 0.0:
		return
	_play_animation("SwordSlash", true)
	if current_animation == "SwordSlash":
		# The actual duration is read from the imported animation.
		attack_time_left = maxf(0.15, animator.current_animation_length)

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

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null

func _configure_animation_loops() -> void:
	if animator == null:
		return
	for name in animator.get_animation_list():
		var clip_name := String(name)
		var animation := animator.get_animation(name)
		if animation == null:
			continue
		if clip_name.ends_with("/Idle") or clip_name == "Idle" or clip_name.ends_with("/Walk") or clip_name == "Walk" or clip_name.ends_with("/Run") or clip_name == "Run":
			animation.loop_mode = Animation.LOOP_LINEAR
		else:
			# Actions (SwordSlash, Jump, etc.) should play once.
			animation.loop_mode = Animation.LOOP_NONE

func _play_animation(short_name: String, restart: bool = false) -> void:
	if animator == null:
		return
	if current_animation == short_name and not restart:
		return
	# Imported glTF clips can be named "Idle" or "SomeLibrary/Idle".
	var clip := ""
	for name in animator.get_animation_list():
		var full_name := String(name)
		if full_name == short_name or full_name.ends_with("/" + short_name):
			clip = full_name
			break
	if clip.is_empty():
		push_warning("Animation not found: " + short_name)
		return
	# Short blended transitions avoid abrupt pose changes.
	var fade := 0.10 if short_name == "Jump" else 0.16
	if short_name == "SwordSlash":
		fade = 0.08
	animator.speed_scale = 1.0
	animator.play(clip, fade)
	current_animation = short_name

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
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	add_child(ground)
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(70, 1, 70)
	ground_collision.shape = ground_shape
	ground_collision.position.y = -0.5
	ground.add_child(ground_collision)
	_add_box(ground, Vector3(70, 1, 70), Vector3(0, -0.5, 0), Color("527c45"))
	for i in range(18):
		var angle := TAU * i / 18.0
		var radius := 13.0 + float(i % 4) * 2.3
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		_add_tree(pos)
	for i in range(12):
		var pos := Vector3(-18 + i * 3.2, 0, -12 + sin(float(i) * 2.1) * 2)
		_add_box(self, Vector3(0.9, 0.5, 0.8), pos + Vector3(0, 0.25, 0), Color("a4a59a"))

func _add_box(parent: Node3D, dimensions: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)
	return instance

func _add_tree(at: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.18
	cylinder.bottom_radius = 0.27
	cylinder.height = 2.1
	trunk.mesh = cylinder
	trunk.position = at + Vector3(0, 1.05, 0)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color("75513a")
	trunk.material_override = bark
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0
	cone.bottom_radius = 1.25
	cone.height = 3.0
	crown.mesh = cone
	crown.position = at + Vector3(0, 3.3, 0)
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color("3c8250")
	crown.material_override = leaves
	add_child(crown)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	if DisplayServer.is_touchscreen_available():
		# Multiple fingers are handled independently in touch_hud.gd.
		touch_hud = TOUCH_HUD_SCRIPT.new()
		touch_hud.name = "MobileControls"
		canvas.add_child(touch_hud)
		touch_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		touch_hud.attack_requested.connect(_start_attack)
		touch_hud.zoom_requested.connect(_cycle_mobile_zoom)
		touch_hud.fullscreen_requested.connect(_toggle_fullscreen)
		touch_hud.zoom_level = mobile_zoom_index + 1
		return
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	canvas.add_child(panel)
	var label := Label.new()
	label.text = "NINJA 3D TEST v7 FIX\nWASD — рух   |   SHIFT — біг\nSPACE — стрибок   |   ЛКМ — удар мечем\nКолесо миші — масштаб"
	panel.add_child(label)
	# Also expose fullscreen on desktop without relying on browser controls.
	var fullscreen_button := Button.new()
	fullscreen_button.name = "FullscreenButton"
	fullscreen_button.text = "FULLSCREEN"
	fullscreen_button.anchor_left = 1.0
	fullscreen_button.anchor_right = 1.0
	fullscreen_button.offset_left = -164.0
	fullscreen_button.offset_right = -18.0
	fullscreen_button.offset_top = 18.0
	fullscreen_button.offset_bottom = 62.0
	fullscreen_button.pressed.connect(_toggle_fullscreen)
	canvas.add_child(fullscreen_button)
