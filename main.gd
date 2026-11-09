extends Node3D

const MODEL := preload("res://assets/Ninja_Female.gltf")
const VROID_MODEL := preload("res://characters/player/model/heroine_vroid.gltf")
const MODEL_MATERIAL_A := preload("res://assets/Ninja_Female_material_A.gltf")
const MODEL_MATERIAL_B := preload("res://assets/Ninja_Female_material_B.gltf")
const CROWD_PALETTE_ATLAS := preload("res://assets/Ninja_Female_palette_atlas.gltf")
# Approved movement values and physics are owned by the player component.
const MOVEMENT_CONTROLLER := preload("res://characters/player/movement_controller.gd")
const WALK_SPEED := MOVEMENT_CONTROLLER.WALK_SPEED
const RUN_SPEED := MOVEMENT_CONTROLLER.RUN_SPEED
const MOVE_ANIMATION_THRESHOLD := 0.45
const TOUCH_HUD_SCRIPT := preload("res://touch_hud.gd")
const HUD_BUILDER := preload("res://ui/hud_builder.gd")
const SKELETON_DEBUG := preload("res://ui/skeleton_debug.gd")
const CROWD_BENCHMARK := preload("res://tests/ninja_crowd_benchmark.gd")
const ANIMATION_BUILDER := preload("res://characters/player/animation_builder.gd")
const VROID_ANIMATION_BUILDER := preload("res://characters/player/animation_builder_vroid.gd")
const COMBAT_CONTROLLER := preload("res://characters/player/combat_controller.gd")
const WEAPON_VISUALS := preload("res://characters/player/weapon_visuals.gd")
const WORLD_SCRIPT := preload("res://world/environment.gd")
# Attack still overlays only the upper body; movement continues unchanged.
const ATTACK_SPEED := COMBAT_CONTROLLER.ATTACK_SPEED

var use_legacy_hero := false # Smoke tests may explicitly select the previous Ninja as a control.
var hero: CharacterBody3D
var visual: Node3D
var ninja_mesh: MeshInstance3D
var ninja_mesh_variants: Array[Mesh] = []
var crowd_atlas_mesh: Mesh
var material_variant_index := 1 # Approved A: culling, original retained as control
var crowd_benchmark = CROWD_BENCHMARK.new()
var crowd_button: Button
var crowd_mode_button: Button
var fps_limit_button: Button
var crowd_build_label: Label
var crowd_stats_label: Label
var debug_panel: PanelContainer
var debug_toggle_button: Button
var debug_skeleton_button: Button
var debug_material_button: Button
var debug_naruto_button: Button
var animator: AnimationPlayer
var camera: Camera3D
var skeleton_debug: MeshInstance3D
var camera_distance := 13.0
var camera_zoom := 12.0
# Orthographic camera sizes: lower value = closer view.
const MOBILE_ZOOM_LEVELS := [18.0, 12.0, 8.0, 6.0]
var mobile_zoom_index := 1
var animation_tree: AnimationTree
var locomotion_state := ""
var naruto_run_enabled := false
var naruto_clip_speed_ratio := 1.0
var movement_controller = MOVEMENT_CONTROLLER.new()
var combat_controller = COMBAT_CONTROLLER.new()
var weapon_visuals = WEAPON_VISUALS.new()
var touch_hud
const WEAPON_POSE_BLEND_TIME := 0.18
var weapon_pose_blend := 1.0 # 1 = armed (finger grip, weapon-safe Run), 0 = no weapon
var fps_label: Label
var fps_update_elapsed := 0.0

func _ready() -> void:
	_build_environment()
	_build_hero()
	_init_crowd_atlas()
	_build_camera()
	_build_ui()
	crowd_benchmark.initialize(self)

func _process(delta: float) -> void:
	# Sample twice per second to keep the counter readable and inexpensive.
	if fps_label == null:
		return
	fps_update_elapsed += delta
	if fps_update_elapsed >= 0.5:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
		if crowd_stats_label != null and crowd_stats_label.visible:
			var viewport_rid := get_viewport().get_viewport_rid()
			var visible_draws := RenderingServer.viewport_get_render_info(viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			var shadow_draws := RenderingServer.viewport_get_render_info(viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			crowd_stats_label.text = "Draws: %d visible / %d shadow" % [visible_draws, shadow_draws]
		fps_update_elapsed = 0.0


func _physics_process(delta: float) -> void:
	combat_controller.physics_step(delta, self, hero, visual)

	_sync_weapon_pose(delta)

	# Motion is isolated from combat and animation state transitions.
	var launched: bool = movement_controller.physics_step(hero, visual, camera, touch_hud, delta)

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
			_set_locomotion("Naruto" if naruto_run_enabled else "Run")
		else:
			_set_locomotion("Walk")
		if animation_tree != null:
			animation_tree.set("parameters/WalkSpeed/scale", clampf(actual_speed / WALK_SPEED, 0.85, 1.25))
			var run_scale := clampf(actual_speed / RUN_SPEED, 0.85, 1.25)
			animation_tree.set("parameters/RunSpeed/scale", run_scale)
			animation_tree.set("parameters/NarutoBaseRunSpeed/scale", run_scale)
			animation_tree.set("parameters/NarutoFullSpeed/scale", run_scale * naruto_clip_speed_ratio)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		_start_dash()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_toggle_naruto_run()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		_toggle_run_mode()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K:
		_toggle_skeleton_debug()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		_cycle_crowd_benchmark()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_cycle_crowd_mode()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_toggle_fps_limit()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		_toggle_debug_panel()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_cycle_ninja_materials()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_cycle_weapon()
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

func _toggle_run_mode() -> void:
	movement_controller.run_by_default = not movement_controller.run_by_default
	_update_weapon_display()


func _toggle_debug_panel() -> void:
	if debug_panel == null:
		return
	debug_panel.visible = not debug_panel.visible
	debug_toggle_button.text = "CLOSE" if debug_panel.visible else "DEBUG"


func _toggle_naruto_run() -> void:
	if not use_legacy_hero:
		return # No VRoid-compatible Naruto animation has been supplied.
	naruto_run_enabled = not naruto_run_enabled
	if locomotion_state == "Run" or locomotion_state == "Naruto":
		_set_locomotion("Naruto" if naruto_run_enabled else "Run")
	if touch_hud != null:
		touch_hud.naruto_run_enabled = naruto_run_enabled
		touch_hud.queue_redraw()
	if debug_naruto_button != null:
		debug_naruto_button.text = "RUN ON" if naruto_run_enabled else "RUN OFF"
	_update_weapon_display()


func _toggle_skeleton_debug() -> void:
	if skeleton_debug == null:
		return
	skeleton_debug.visible = not skeleton_debug.visible
	if touch_hud != null:
		touch_hud.skeleton_enabled = skeleton_debug.visible
		touch_hud.queue_redraw()
	if debug_skeleton_button != null:
		debug_skeleton_button.text = "SKEL ON" if skeleton_debug.visible else "SKEL OFF"


func _cycle_ninja_materials() -> void:
	if ninja_mesh == null or ninja_mesh_variants.size() != 3:
		return
	material_variant_index = (material_variant_index + 1) % 2 # B rejected after visual QA
	ninja_mesh.mesh = ninja_mesh_variants[material_variant_index]
	# Keep the crowd on its independently optimized one-surface palette mesh.
	if touch_hud != null:
		touch_hud.material_variant = material_variant_index
		touch_hud.queue_redraw()
	if debug_material_button != null:
		debug_material_button.text = "MAT O" if material_variant_index == 0 else "MAT A"
	_update_weapon_display()


func _cycle_crowd_benchmark() -> void:
	crowd_benchmark.count_index = (crowd_benchmark.count_index + 1) % CROWD_BENCHMARK.COUNTS.size()
	var count: int = CROWD_BENCHMARK.COUNTS[crowd_benchmark.count_index]
	crowd_benchmark.set_count(count, MODEL, _benchmark_crowd_mesh())
	camera.size = 40.0 if count > 0 else camera_zoom
	if crowd_button != null:
		crowd_button.text = "LOAD %d" % count
	if crowd_stats_label != null:
		crowd_stats_label.visible = count > 0


func _cycle_crowd_mode() -> void:
	var mode: String = crowd_benchmark.cycle_mode()
	if crowd_mode_button != null:
		crowd_mode_button.text = "MODE %s" % mode


func _benchmark_crowd_mesh(force_legacy: bool = false) -> Mesh:
	# The classic APK uses the approved six-surface A mesh; other exports
	# use the optimized one-surface palette atlas. Gameplay is identical.
	if force_legacy or OS.has_feature("legacy_crowd"):
		return ninja_mesh_variants[1] if ninja_mesh_variants.size() > 1 else null
	return crowd_atlas_mesh


func _toggle_fps_limit() -> void:
	# 0 removes the Godot Engine limit; display VSync/hardware may still cap FPS.
	Engine.max_fps = 0 if Engine.max_fps == 60 else 60
	if fps_limit_button != null:
		fps_limit_button.text = "FPS CAP 60" if Engine.max_fps == 60 else "FPS CAP OFF"


func _prepare_legacy_crowd_meshes() -> void:
	# Keep both benchmark mesh modes independent of the new playable hero.
	var reference := MODEL.instantiate()
	_setup_material_comparison(reference)
	reference.free()
	ninja_mesh = null


func _init_crowd_atlas() -> void:
	var preview := CROWD_PALETTE_ATLAS.instantiate()
	var found := _find_model_mesh(preview)
	if found != null:
		crowd_atlas_mesh = found.mesh
	preview.free()
	if crowd_atlas_mesh == null or crowd_atlas_mesh.get_surface_count() != 1:
		push_error("Single-surface Ninja crowd atlas unavailable")


func _find_model_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for child in root.get_children():
		var match_mesh := _find_model_mesh(child)
		if match_mesh != null:
			return match_mesh
	return null


func _setup_material_comparison(model: Node3D) -> void:
	ninja_mesh = _find_model_mesh(model)
	if ninja_mesh == null:
		push_warning("Ninja source mesh not found for material comparison")
		return
	ninja_mesh_variants.clear()
	ninja_mesh_variants.append(ninja_mesh.mesh)
	for variant_scene in [MODEL_MATERIAL_A, MODEL_MATERIAL_B]:
		var temporary: Node3D = variant_scene.instantiate()
		var variant_mesh := _find_model_mesh(temporary)
		if variant_mesh == null or variant_mesh.mesh == null:
			push_warning("Ninja material variant mesh missing")
		else:
			ninja_mesh_variants.append(variant_mesh.mesh)
		temporary.free()
	if ninja_mesh_variants.size() != 3:
		push_warning("Ninja material comparison incomplete")
		return
	# Preserve original animated rig; render approved A geometry by default.
	ninja_mesh.mesh = ninja_mesh_variants[material_variant_index]
	# Godot 4.7 glTF import does not reliably activate vertex colors
	# as albedo. Make the intended per-vertex RGB explicit for variant B.
	var one_surface_mesh := ninja_mesh_variants[2].duplicate() as ArrayMesh
	if one_surface_mesh != null:
		var color_material := one_surface_mesh.surface_get_material(0) as StandardMaterial3D
		if color_material != null:
			color_material = color_material.duplicate() as StandardMaterial3D
			color_material.vertex_color_use_as_albedo = true
			color_material.vertex_color_is_srgb = false
			one_surface_mesh.surface_set_material(0, color_material)
			ninja_mesh_variants[2] = one_surface_mesh


func _cycle_weapon() -> void:
	# This is a visual playtest only. Current attack state stays untouched.
	if weapon_visuals.cycle():
		_update_weapon_display()


func _update_weapon_display() -> void:
	if touch_hud != null:
		touch_hud.weapon_index = weapon_visuals.current_index + 1
		touch_hud.weapon_slots = 5 if use_legacy_hero else WEAPON_VISUALS.WEAPONS.size() + 1
		touch_hud.queue_redraw()
	if not use_legacy_hero and animation_tree != null:
		# Switching across armed/unarmed modes cancels the incompatible attack.
		# Sword-to-sword switches retain the existing in-flight clip behaviour.
		if not weapon_visuals.has_weapon() or (combat_controller.attack_time_left > 0.0 and float(animation_tree.get("parameters/UnarmedChoice/blend_amount")) > 0.5):
			combat_controller.cancel_attack(animation_tree)
		_sync_weapon_pose(0.0)
	var help_label := get_node_or_null("HUD/HelpPanel/HelpText") as Label
	if help_label != null:
		help_label.text = HUD_BUILDER.desktop_help_text(weapon_visuals.selected_name(), naruto_run_enabled, use_legacy_hero, movement_controller.run_by_default)
		help_label.text += (" | M: MAT %s" % ["O", "A", "B"][material_variant_index]) if use_legacy_hero else " | VRoid"


func _sync_weapon_pose(delta: float) -> void:
	# VRoid only. Armed: closed-hand grip + weapon-safe Run. Unarmed: open hand
	# + full Run. Both are smoothed so that a switch never pops the pose.
	if use_legacy_hero or animation_tree == null:
		return
	var armed: bool = weapon_visuals.has_weapon()
	weapon_pose_blend = move_toward(weapon_pose_blend, 1.0 if armed else 0.0, delta / WEAPON_POSE_BLEND_TIME)
	animation_tree.set("parameters/GripOverlay/blend_amount", weapon_pose_blend)
	animation_tree.set("parameters/RunArms/blend_amount", 1.0 - weapon_pose_blend)
	# Sword I previews the one-handed heavy strike; the others use the standard 1H.
	# The clip choice is held until the current attack has finished.
	if combat_controller.attack_time_left <= 0.0:
		animation_tree.set("parameters/UnarmedChoice/blend_amount", 0.0 if armed else 1.0)
		if armed:
			animation_tree.set("parameters/SlashChoice/blend_amount", 1.0 if weapon_visuals.current_index == 0 else 0.0)


func _start_dash() -> void:
	# Keep the same callback name for Q, the touch HUD and existing tests.
	movement_controller.start_dash(touch_hud, camera)


func _toggle_fullscreen() -> void:
	# On Web this is called directly from a real button/touch event.
	var current_mode := DisplayServer.window_get_mode()
	var is_fullscreen := current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _cycle_mobile_zoom() -> void:
	mobile_zoom_index = (mobile_zoom_index + 1) % MOBILE_ZOOM_LEVELS.size()
	camera_zoom = float(MOBILE_ZOOM_LEVELS[mobile_zoom_index])
	if crowd_benchmark.count_index == 0:
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
	var model := MODEL.instantiate() if use_legacy_hero else VROID_MODEL.instantiate()
	visual.add_child(model)
	# Match the 2.8 m player capsule using the actual VRoid mesh bounds, not
	# a hard-coded source-file height. Keep feet aligned with the ground.
	if not use_legacy_hero:
		var bounds := weapon_visuals._bounds_in_root(model)
		if bounds.size.y > 0.01:
			var hero_scale := capsule.height / bounds.size.y
			model.scale = Vector3.ONE * hero_scale
			model.position.y = -bounds.position.y * hero_scale
		else:
			push_error("VRoid heroine has no usable mesh bounds")
	if use_legacy_hero:
		_setup_material_comparison(model)
	else:
		_prepare_legacy_crowd_meshes()
	var rig := WEAPON_VISUALS.find_skeleton(model) as Skeleton3D
	if rig != null:
		skeleton_debug = SKELETON_DEBUG.new() as MeshInstance3D
		skeleton_debug.name = "SkeletonDebug"
		rig.add_child(skeleton_debug)
		skeleton_debug.call("setup", rig)
	animator = ANIMATION_BUILDER.find_animation_player(model)
	if animator != null:
		# Preserve imported locomotion loop behavior and accepted attack clips.
		if use_legacy_hero:
			ANIMATION_BUILDER.configure_animation_loops(animator)
		else:
			VROID_ANIMATION_BUILDER.configure_animation_loops(animator)
		if not weapon_visuals.initialize(model):
			push_warning("Visual weapon test could not initialize")
		if use_legacy_hero:
			animation_tree = ANIMATION_BUILDER.setup_animation_tree(model, animator, ATTACK_SPEED)
		else:
			animation_tree = VROID_ANIMATION_BUILDER.setup_animation_tree(model, animator, VROID_ANIMATION_BUILDER.VROID_ATTACK_SPEED)
		if animation_tree != null:
			naruto_clip_speed_ratio = float(animation_tree.get("parameters/NarutoFullSpeed/scale"))
			_set_locomotion("Idle")
	else:
		push_warning("AnimationPlayer not found in imported model")

func _start_attack() -> void:
	# Maintain the existing desktop/mobile signal and test-facing entrypoint.
	if use_legacy_hero:
		combat_controller.start_attack(animation_tree, animator)
	else:
		if not weapon_visuals.has_weapon():
			# Fist combo is visual-only; do not inherit the sword training hit.
			_sync_weapon_pose(0.0)
			combat_controller.start_attack(animation_tree, animator, VROID_ANIMATION_BUILDER.UNARMED_ATTACK_SPEED, "UnarmedCombo", false)
			return
		# Match VRoid-only playback and the selected heavy/regular source clip.
		var clip := "SwordHeavyCandidate" if weapon_visuals.current_index == 0 else "SwordSlash"
		combat_controller.start_attack(animation_tree, animator, VROID_ANIMATION_BUILDER.VROID_ATTACK_SPEED, clip)


func _resolve_training_hit() -> void:
	# Preserve the existing smoke-test entrypoint, no separate hit mechanic.
	combat_controller.resolve_training_hit(self, hero, visual)


func _set_locomotion(state: String, restart: bool = false) -> void:
	if animation_tree == null:
		return
	if state == locomotion_state and not restart:
		return
	# With Naruto running, the attack overlay may move the weapon arm only.
	# Normal locomotion keeps the original approved full upper-body strike.
	if use_legacy_hero:
		ANIMATION_BUILDER.preserve_naruto_pose_during_attack(animation_tree, state == "Naruto")
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
	var debug_controls: Dictionary = HUD_BUILDER.build_debug_controls(canvas, use_legacy_hero)
	debug_panel = debug_controls["panel"] as PanelContainer
	debug_toggle_button = debug_controls["toggle"] as Button
	crowd_button = debug_controls["crowd"] as Button
	crowd_mode_button = debug_controls["mode"] as Button
	fps_limit_button = debug_controls["limit"] as Button
	crowd_stats_label = debug_controls["stats"] as Label
	crowd_build_label = debug_controls["build"] as Label
	debug_skeleton_button = debug_controls["skeleton"] as Button
	debug_material_button = debug_controls.get("materials") as Button
	debug_naruto_button = debug_controls.get("naruto") as Button
	debug_toggle_button.pressed.connect(_toggle_debug_panel)
	crowd_button.pressed.connect(_cycle_crowd_benchmark)
	crowd_mode_button.pressed.connect(_cycle_crowd_mode)
	fps_limit_button.pressed.connect(_toggle_fps_limit)
	debug_skeleton_button.pressed.connect(_toggle_skeleton_debug)
	if debug_material_button != null:
		debug_material_button.pressed.connect(_cycle_ninja_materials)
		debug_material_button.text = "MAT O" if material_variant_index == 0 else "MAT A"
	if debug_naruto_button != null:
		debug_naruto_button.pressed.connect(_toggle_naruto_run)
	if DisplayServer.is_touchscreen_available():
		# Multiple fingers are handled independently in touch_hud.gd.
		touch_hud = TOUCH_HUD_SCRIPT.new()
		touch_hud.ninja_visual_controls = use_legacy_hero
		touch_hud.name = "MobileControls"
		canvas.add_child(touch_hud)
		touch_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		touch_hud.attack_requested.connect(_start_attack)
		touch_hud.dash_requested.connect(_start_dash)
		touch_hud.zoom_requested.connect(_cycle_mobile_zoom)
		touch_hud.fullscreen_requested.connect(_toggle_fullscreen)
		touch_hud.weapon_requested.connect(_cycle_weapon)
		touch_hud.material_variant = material_variant_index
		_update_weapon_display()
		touch_hud.zoom_level = mobile_zoom_index + 1
		return
	var fullscreen_button := HUD_BUILDER.build_desktop_controls(canvas)
	fullscreen_button.pressed.connect(_toggle_fullscreen)
	_update_weapon_display()
