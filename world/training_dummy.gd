extends StaticBody3D
## Repeatable stationary melee target for the first combat milestone.
## Health and damage are provisional and independent of the MMORPG balance.

const MAX_HP := 100
const RESPAWN_DELAY := 2.5
const HIT_FLASH_SECONDS := 0.16

var hp := MAX_HP
var is_available := true
var respawn_left := 0.0
var flash_left := 0.0

var body_mesh: MeshInstance3D
var body_material: StandardMaterial3D
var health_label: Label3D
var damage_label: Label3D
var health_fill: MeshInstance3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 2.7, 0.65)
	collision.shape = shape
	collision.position.y = 1.40
	add_child(collision)

	var post := MeshInstance3D.new()
	post.name = "WoodenPost"
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.15
	post_mesh.bottom_radius = 0.21
	post_mesh.height = 2.45
	post_mesh.radial_segments = 7
	post.mesh = post_mesh
	post.position.y = 1.25
	post.material_override = _color_material(Color("805331"))
	add_child(post)

	body_mesh = MeshInstance3D.new()
	body_mesh.name = "TargetBody"
	var body_geometry := BoxMesh.new()
	body_geometry.size = Vector3(1.30, 1.55, 0.42)
	body_mesh.mesh = body_geometry
	body_mesh.position.y = 1.85
	body_material = _color_material(Color("bba176"))
	body_mesh.material_override = body_material
	add_child(body_mesh)

	# Simple contrasting strike marker on the front side.
	var front := MeshInstance3D.new()
	front.name = "StrikeMarker"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.36
	disc.bottom_radius = 0.36
	disc.height = 0.08
	disc.radial_segments = 12
	front.mesh = disc
	front.rotation_degrees.x = 90
	front.position = Vector3(0.0, 1.92, 0.27)
	front.material_override = _color_material(Color("8a342e"))
	add_child(front)

	health_label = _label("HP 100 / 100", Vector3(0, 3.35, 0))
	health_label.name = "HealthLabel"
	damage_label = _label("", Vector3(0, 3.85, 0))
	damage_label.name = "DamageLabel"
	damage_label.modulate = Color("ffd17b")

	var backdrop := MeshInstance3D.new()
	backdrop.name = "HealthBarBackground"
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.62, 0.18, 0.06)
	backdrop.mesh = bar_mesh
	backdrop.position = Vector3(0, 3.07, 0)
	backdrop.material_override = _color_material(Color("322a27"))
	add_child(backdrop)

	health_fill = MeshInstance3D.new()
	health_fill.name = "HealthBarFill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(1.56, 0.13, 0.07)
	health_fill.mesh = fill_mesh
	health_fill.position = Vector3(0, 3.07, 0.05)
	health_fill.material_override = _color_material(Color("6ec06d"))
	add_child(health_fill)


func _process(delta: float) -> void:
	if flash_left > 0.0:
		flash_left = maxf(0.0, flash_left - delta)
		if flash_left <= 0.0:
			body_material.albedo_color = Color("bba176")
			damage_label.text = ""
	if not is_available:
		respawn_left = maxf(0.0, respawn_left - delta)
		if respawn_left <= 0.0:
			_reset_target()


func take_damage(amount: int) -> bool:
	if not is_available or amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	flash_left = HIT_FLASH_SECONDS
	body_material.albedo_color = Color("ffe5aa")
	damage_label.text = "-%d" % amount
	_update_health_visuals()
	if hp == 0:
		is_available = false
		respawn_left = RESPAWN_DELAY
		body_material.albedo_color = Color("514741")
	return true


func _reset_target() -> void:
	hp = MAX_HP
	is_available = true
	respawn_left = 0.0
	flash_left = 0.0
	body_material.albedo_color = Color("bba176")
	damage_label.text = ""
	_update_health_visuals()


func _update_health_visuals() -> void:
	health_label.text = "HP %d / %d" % [hp, MAX_HP]
	var percentage := float(hp) / float(MAX_HP)
	health_fill.scale.x = percentage
	health_fill.position.x = -(1.56 * (1.0 - percentage)) * 0.5
	health_fill.visible = hp > 0


func _label(message: String, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = message
	label.position = at
	label.font_size = 36
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	return label


func _color_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
