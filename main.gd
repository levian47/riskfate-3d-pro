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
const WORLD_SCRIPT := preload("res://world/environment.gd")
# The attack runs on the upper body while the legs retain their movement animation.
const ATTACK_SPEED := 1.65
# Approximate visual swing target: ~130 degrees instead of the reported ~90.
# Scales the right upper-arm excursion, NOT combat damage or timing.
const ATTACK_SWING_AMPLITUDE := 130.0 / 90.0
# Prototype combat parameters. Not approved balance values.
const TRAINING_HIT_DAMAGE := 25
const TRAINING_HIT_REACH := 3.1
const TRAINING_HIT_FACING_DOT := 0.60
const TRAINING_HIT_MOMENT := 0.42
const UPPER_BODY_BONES := [
	"Abdomen", "Torso", "Neck", "Head",
	"Shoulder.L", "UpperArm.L", "LowerArm.L", "Fist.L",
	"Shoulder.R", "UpperArm.R", "LowerArm.R", "Fist.R"
]

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
	# Ground and air steering match the joystick immediately, including reversals.
	var direction := _camera_relative_direction(input_vector)
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
		# Releasing Space early makes a shorter jump.
		if not jump_pressed and hero.velocity.y > 0.0:
			hero.velocity.y -= GRAVITY * (1.0 / JUMP_RELEASE_MULTIPLIER - 1.0) * delta
	else:
		hero.velocity.y = -0.1

	hero.move_and_slide()

	if facing_direction.length_squared() > 0.01:
		# Keep the model-specific 180-degree facing correction without turning lag.
		visual.rotation.y = atan2(-facing_direction.x, -facing_direction.z) + PI

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

func _camera_relative_direction(input_vector: Vector2) -> Vector3:
	var camera_right := camera.global_transform.basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var camera_forward := -camera.global_transform.basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	return camera_right * input_vector.x - camera_forward * input_vector.y


func _start_dash() -> void:
	if dash_cooldown_left > 0.0 or dash_time_left > 0.0:
		return
	var intended_direction := Vector3.ZERO
	if touch_hud != null:
		intended_direction = _camera_relative_direction(touch_hud.move_vector)
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
	animator = _find_animation_player(model)
	if animator != null:
		# Imported glTF clips are often not marked as looping. Without this,
		# Run/Walk stops moving the legs at the last frame while the body moves.
		_configure_animation_loops()
		_attach_simple_sword(model)
		_setup_animation_tree(model)
	else:
		push_warning("AnimationPlayer not found in imported model")

func _start_attack() -> void:
	if animation_tree == null or attack_time_left > 0.0:
		return
	var clip_name := _find_clip("SwordSlash")
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

func _find_clip(short_name: String) -> String:
	if animator == null:
		return ""
	for name in animator.get_animation_list():
		var full_name := String(name)
		if full_name == short_name or full_name.ends_with("/" + short_name):
			return full_name
	push_warning("Animation not found: " + short_name)
	return ""


func _make_wider_sword_slash(source_name: String) -> String:
	# Keep the imported clip untouched; build an independently editable variation.
	# Extrapolating upper-arm key rotations widens the existing slash without
	# reorienting the sword in the grip or disturbing the locomotion layer.
	var source := animator.get_animation(source_name)
	if source == null:
		return ""
	var wide := source.duplicate(true) as Animation
	var altered_keys := 0
	for track in range(wide.get_track_count()):
		if wide.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var track_path := wide.track_get_path(track)
		if track_path.get_subname_count() == 0:
			continue
		var bone_name := String(track_path.get_subname(track_path.get_subname_count() - 1))
		if bone_name != "UpperArm.R" or wide.track_is_compressed(track):
			continue
		var key_count := wide.track_get_key_count(track)
		if key_count < 2:
			continue
		var start_rotation: Quaternion = wide.track_get_key_value(track, 0)
		for key_index in range(1, key_count):
			var original: Quaternion = wide.track_get_key_value(track, key_index)
			var relative: Quaternion = (start_rotation.inverse() * original).normalized()
			# Quaternions q and -q encode the same rotation; choose shortest arc.
			if relative.w < 0.0:
				relative = Quaternion(-relative.x, -relative.y, -relative.z, -relative.w)
			var angle := relative.get_angle()
			if angle <= 0.001:
				continue
			var wider_rotation := start_rotation * Quaternion(relative.get_axis(), angle * ATTACK_SWING_AMPLITUDE)
			wide.track_set_key_value(track, key_index, wider_rotation.normalized())
			altered_keys += 1
	if altered_keys == 0:
		push_warning("SwordSlash: upper-arm animation track cannot be widened")
		return ""
	var library := AnimationLibrary.new()
	if library.add_animation("WideSwordSlash", wide) != OK:
		return ""
	if animator.add_animation_library("combat", library) != OK:
		return ""
	return "combat/WideSwordSlash"


func _setup_animation_tree(model: Node) -> void:
	var root := AnimationNodeBlendTree.new()
	var locomotion := AnimationNodeTransition.new()
	locomotion.input_count = 4
	locomotion.xfade_time = 0.10
	root.add_node("Locomotion", locomotion)

	var states := ["Idle", "Walk", "Run", "Jump"]
	for i in range(states.size()):
		var state: String = states[i]
		var clip_name := _find_clip(state)
		if clip_name.is_empty():
			push_error("Cannot build locomotion tree without " + state)
			return
		locomotion.set_input_name(i, state)
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = clip_name
		root.add_node(state, clip_node)
		if state == "Walk" or state == "Run":
			var speed_node := AnimationNodeTimeScale.new()
			root.add_node(state + "Speed", speed_node)
			root.connect_node(state + "Speed", 0, state)
			root.connect_node("Locomotion", i, state + "Speed")
		else:
			root.connect_node("Locomotion", i, state)

	var attack_clip_name := _find_clip("SwordSlash")
	if attack_clip_name.is_empty():
		push_error("SwordSlash clip missing")
		return
	var wide_clip_name := _make_wider_sword_slash(attack_clip_name)
	if not wide_clip_name.is_empty():
		attack_clip_name = wide_clip_name
	var attack_clip := animator.get_animation(attack_clip_name)
	var attack_node := AnimationNodeAnimation.new()
	attack_node.animation = attack_clip_name
	var attack_speed := AnimationNodeTimeScale.new()
	var attack_layer := AnimationNodeOneShot.new()
	attack_layer.fadein_time = 0.06
	attack_layer.fadeout_time = 0.10
	attack_layer.filter_enabled = true
	var filtered := 0
	for track_index in range(attack_clip.get_track_count()):
		var track_path := attack_clip.track_get_path(track_index)
		if track_path.get_subname_count() == 0:
			continue
		var bone := String(track_path.get_subname(track_path.get_subname_count() - 1))
		if bone in UPPER_BODY_BONES:
			attack_layer.set_filter_path(track_path, true)
			filtered += 1
	if filtered == 0:
		push_error("The imported SwordSlash animation has no matching upper-body tracks")
		return

	root.add_node("SwordSlash", attack_node)
	root.add_node("AttackSpeed", attack_speed)
	root.add_node("Attack", attack_layer)
	root.connect_node("AttackSpeed", 0, "SwordSlash")
	root.connect_node("Attack", 0, "Locomotion")
	root.connect_node("Attack", 1, "AttackSpeed")
	root.connect_node("output", 0, "Attack")

	animation_tree = AnimationTree.new()
	animation_tree.name = "CharacterAnimationTree"
	model.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animator)
	animation_tree.tree_root = root
	animator.stop()
	animation_tree.active = true
	animation_tree.set("parameters/AttackSpeed/scale", ATTACK_SPEED)
	_set_locomotion("Idle")


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


func _build_fps_counter(canvas: CanvasLayer) -> void:
	# Top center stays clear of FULL (top left), ZOOM (top right) and actions.
	var panel := PanelContainer.new()
	panel.name = "FPSCounter"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -54.0
	panel.offset_right = 54.0
	panel.offset_top = 12.0
	panel.offset_bottom = 45.0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.05, 0.08, 0.11, 0.72)
	background.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", background)
	canvas.add_child(panel)

	fps_label = Label.new()
	fps_label.name = "FPSLabel"
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.text = "FPS: --"
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(fps_label)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	_build_fps_counter(canvas)
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
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	canvas.add_child(panel)
	var label := Label.new()
	label.text = "NINJA 3D TEST\nWASD — рух   |   SHIFT — біг   |   Q — ривок\nSPACE — стрибок   |   ЛКМ — удар мечем\nКолесо миші — масштаб"
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
