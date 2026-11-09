extends RefCounted
# Local prototype combat only. The network-authoritative combat rules for
# MMORPG play have not been designed or implemented.
const ANIMATION_BUILDER := preload("res://characters/player/animation_builder.gd")

const ATTACK_SPEED := 1.65
# Provisional test values; these are not approved game balance.
const TRAINING_HIT_DAMAGE := 25
const TRAINING_HIT_REACH := 3.1
const TRAINING_HIT_FACING_DOT := 0.60
const TRAINING_HIT_MOMENT := 0.42

var attack_time_left := 0.0
var attack_duration := 0.0
var attack_hit_pending := false


func start_attack(animation_tree: AnimationTree, animator: AnimationPlayer, speed: float = ATTACK_SPEED, clip_short_name: String = "SwordSlash", can_hit: bool = true) -> void:
	if animation_tree == null or attack_time_left > 0.0:
		return
	# Default arguments preserve the approved Ninja timing and clip.
	# VRoid passes its own visual playback speed and selected preview clip
	# so the hit/cooldown timer matches the visible animation duration.
	var clip_name := ANIMATION_BUILDER.find_clip(animator, clip_short_name)
	if clip_name.is_empty():
		return
	attack_duration = animator.get_animation(clip_name).length / maxf(speed, 0.001)
	attack_time_left = attack_duration
	# Fist animations are visual-only until unarmed damage/range are approved.
	attack_hit_pending = can_hit
	animation_tree.set("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func cancel_attack(animation_tree: AnimationTree) -> void:
	# Used when the weapon is removed mid-attack: no later hit, no stuck layer.
	if attack_time_left <= 0.0 and not attack_hit_pending:
		return
	attack_time_left = 0.0
	attack_hit_pending = false
	if animation_tree != null:
		animation_tree.set("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func physics_step(delta: float, game: Node3D, hero: CharacterBody3D, visual: Node3D) -> void:
	if attack_time_left > 0.0:
		attack_time_left = maxf(0.0, attack_time_left - delta)
		if attack_hit_pending and attack_time_left <= attack_duration * (1.0 - TRAINING_HIT_MOMENT):
			attack_hit_pending = false
			resolve_training_hit(game, hero, visual)


func resolve_training_hit(game: Node3D, hero: CharacterBody3D, visual: Node3D) -> void:
	# Forward range/cone check, not physical blade-to-target collision.
	var target := game.get_node_or_null("Environment/TrainingDummy") as StaticBody3D
	if target == null or not target.has_method("take_damage") or not target.get("is_available"):
		return
	var offset := target.global_position - hero.global_position
	var height_difference := absf(offset.y)
	offset.y = 0.0
	var distance := offset.length()
	if distance > TRAINING_HIT_REACH or distance < 0.001 or height_difference > 2.2:
		return
	# Imported model's +Z remains the strike direction after the PI correction.
	var facing := visual.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized()
	if facing.dot(offset / distance) < TRAINING_HIT_FACING_DOT:
		return
	target.take_damage(TRAINING_HIT_DAMAGE)
