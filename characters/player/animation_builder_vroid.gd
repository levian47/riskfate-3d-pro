extends RefCounted
# VRoid-only animation graph. The original Ninja graph and its approved
# animation resources are deliberately left untouched for regression testing.
# Original VRoid Walk/Jog are retained as rollback clips. New Walk/Run come
# from retargeted CC0 Quaternius motion; Idle, Jump, attack stay provisional.
# functional placeholders until purpose-made VRoid clips are available.

const QUATERNIUS_LOCOMOTION := preload("res://characters/player/locomotion_quaternius.gd")
const UAL2_COMBAT := preload("res://characters/player/combat_retarget_ual2.gd")

# VRoid-only preview attack speed. Keeps legacy Ninja timing untouched.
# Sword Regular ~0.45 s -> ~0.64 s, Sword Heavy ~0.75 s -> ~1.07 s.
const VROID_ATTACK_SPEED := 0.70
# Unarmed preview is visual only; damage and melee balance remain undecided.
const UNARMED_ATTACK_SPEED := 1.0
# Preview-only lift of Sword I's one-handed heavy swing; no timing or hitbox changes.
const SWORD_I_ATTACK_LIFT_DEGREES := 34.0
# Sword I finishing phase: rotation vectors (axis * radians, parent-local, applied
# before the authored key) solved offline so that the hand ends just below shoulder
# height and the blade tip near it. Hand finish is calibrated against actual
# Godot skeleton/weapon-tip measurements, not only bone Euler angles.
# Envelope in fractions of clip length: starts after the wind-up/initial swing,
# fully applied at the finish, released again before the clip end.
const SWORD_I_FINISH_CORRECTION := {
	"J_Bip_R_Shoulder": Vector3(0.0487803, -0.0720999, 0.0061250),
	"J_Bip_R_UpperArm": Vector3(0.3609113, 0.0284501, 0.1484187),
	"J_Bip_R_LowerArm": Vector3(-0.2360918, 0.0000086, -0.3150864),
	"J_Bip_R_Hand": Vector3(0.3283362, -0.2250152, -0.0397931),
}
const SWORD_I_FINISH_ENVELOPE := Vector4(0.409, 0.682, 0.818, 1.0)
# Retain Quaternius Run leg/body timing, but keep the weapon arm close to the
# neutral walking carry instead of letting its high run swing cross the head.
const RUN_WEAPON_CARRY_BLEND := {
	"J_Bip_R_Shoulder": 0.90,
	"J_Bip_R_UpperArm": 0.92,
	"J_Bip_R_LowerArm": 0.86,
	"J_Bip_R_Hand": 0.82,
}

const ARM_BONES := [
	"J_Bip_R_Shoulder", "J_Bip_R_UpperArm", "J_Bip_R_LowerArm",
	"J_Bip_R_Hand"
]

# Preview closed-hand pose for all five VRoid weapons. Curl the distal thumb
# joints gently, keeping the unusually oriented thumb root in its source pose.
# Final contact and mesh clipping still require visual approval.
const SWORD_GRIP_FINGER_BENDS := {
	"J_Bip_R_Index1": 0.62, "J_Bip_R_Index2": 0.80, "J_Bip_R_Index3": 0.38,
	"J_Bip_R_Middle1": 0.66, "J_Bip_R_Middle2": 0.83, "J_Bip_R_Middle3": 0.40,
	"J_Bip_R_Ring1": 0.68, "J_Bip_R_Ring2": 0.87, "J_Bip_R_Ring3": 0.42,
	"J_Bip_R_Little1": 0.68, "J_Bip_R_Little2": 0.85, "J_Bip_R_Little3": 0.42,
	"J_Bip_R_Thumb2": 0.42, "J_Bip_R_Thumb3": 0.36
}

static func find_clip(animator: AnimationPlayer, short_name: String) -> String:
	if animator == null:
		return ""
	for name in animator.get_animation_list():
		var full_name := String(name)
		if full_name == short_name or full_name.ends_with("/" + short_name):
			return full_name
	return ""


static func configure_animation_loops(animator: AnimationPlayer) -> void:
	for name in animator.get_animation_list():
		var animation := animator.get_animation(name)
		var short_name := String(name).get_slice("/", String(name).get_slice_count("/") - 1)
		animation.loop_mode = Animation.LOOP_LINEAR if short_name in ["Walk", "Jog"] else Animation.LOOP_NONE


static func _hold_pose(source: Animation, sample_time: float, duration: float, looping: bool) -> Animation:
	# A single sampled pose avoids T-pose when the character is standing still
	# or airborne. Replace these placeholders with authored clips later.
	var result := Animation.new()
	result.length = duration
	result.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	for index in range(source.get_track_count()):
		var kind := source.track_get_type(index)
		if kind not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var track := result.add_track(kind)
		result.track_set_path(track, source.track_get_path(index))
		match kind:
			Animation.TYPE_ROTATION_3D:
				result.rotation_track_insert_key(track, 0.0, source.rotation_track_interpolate(index, sample_time))
			Animation.TYPE_POSITION_3D:
				result.position_track_insert_key(track, 0.0, source.position_track_interpolate(index, sample_time))
			Animation.TYPE_SCALE_3D:
				result.scale_track_insert_key(track, 0.0, source.scale_track_interpolate(index, sample_time))
	return result


static func _sword_swing(walk: Animation) -> Animation:
	var clip := Animation.new()
	clip.length = 1.0416666
	clip.loop_mode = Animation.LOOP_NONE
	# Only the weapon arm is animated; walking/jumping continue underneath.
	# This swing is not the previously approved Ninja/Mixamo sweeping clip.
	for index in range(walk.get_track_count()):
		if walk.track_get_type(index) != Animation.TYPE_ROTATION_3D:
			continue
		var path := walk.track_get_path(index)
		var bone := String(path.get_subname(path.get_subname_count() - 1)) if path.get_subname_count() > 0 else ""
		if bone not in ARM_BONES:
			continue
		var baseline := walk.rotation_track_interpolate(index, 0.15)
		var attack := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(attack, path)
		clip.rotation_track_insert_key(attack, 0.0, baseline)
		if bone == "J_Bip_R_UpperArm":
			clip.rotation_track_insert_key(attack, 0.22, baseline * Quaternion(Vector3.FORWARD, -1.1))
			clip.rotation_track_insert_key(attack, 0.52, baseline * Quaternion(Vector3.FORWARD, 1.15))
		elif bone == "J_Bip_R_LowerArm":
			clip.rotation_track_insert_key(attack, 0.22, baseline * Quaternion(Vector3.UP, -0.85))
			clip.rotation_track_insert_key(attack, 0.52, baseline * Quaternion(Vector3.UP, 0.55))
		else:
			clip.rotation_track_insert_key(attack, 0.22, baseline)
			clip.rotation_track_insert_key(attack, 0.52, baseline)
		clip.rotation_track_insert_key(attack, 1.0416666, baseline)
	return clip


static func _safe_weapon_run(run: Animation, walk: Animation) -> Animation:
	# A derived Run variant: do not modify imported Walk/Jog or the source
	# Quaternius motion. Only the four right-arm bone rotations are blended
	# toward the neutral position sampled from the approved Walk cycle.
	# Left-arm counter-swing, legs, hips and torso continue using real Run.
	var corrected := run.duplicate() as Animation
	for track in range(corrected.get_track_count()):
		if corrected.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path := corrected.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone := String(path.get_subname(path.get_subname_count() - 1))
		if not RUN_WEAPON_CARRY_BLEND.has(bone):
			continue
		var walk_track := walk.find_track(path, Animation.TYPE_ROTATION_3D)
		if walk_track < 0:
			push_error("VRoid weapon run missing Walk arm track: " + bone)
			return null
		var neutral := walk.rotation_track_interpolate(walk_track, 0.0)
		# Four evenly spaced walking poses average out the arm swing while
		# preserving the imported VRoid bone-rest orientation.
		for i in range(1, 4):
			var sample_time := walk.length * float(i) / 4.0
			var sampled := walk.rotation_track_interpolate(walk_track, sample_time)
			neutral = neutral.slerp(sampled, 1.0 / float(i + 1)).normalized()
		for key in range(corrected.track_get_key_count(track)):
			var original: Quaternion = run.track_get_key_value(track, key)
			var blend := float(RUN_WEAPON_CARRY_BLEND[bone])
			corrected.track_set_key_value(track, key, original.slerp(neutral, blend).normalized())
	return corrected


static func _smoothstep01(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func finish_envelope(progress: float) -> float:
	var e := SWORD_I_FINISH_ENVELOPE
	return _smoothstep01((progress - e.x) / (e.y - e.x)) * (1.0 - _smoothstep01((progress - e.z) / (e.w - e.z)))


static func _apply_sword_i_sin_lift(source: Animation) -> Animation:
	# Previous accepted behaviour: raise only the right upper arm during the blow.
	var elevated := source.duplicate() as Animation
	for track in range(elevated.get_track_count()):
		if elevated.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path := elevated.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		if String(path.get_subname(path.get_subname_count() - 1)) != "J_Bip_R_UpperArm":
			continue
		for key in range(elevated.track_get_key_count(track)):
			var progress := elevated.track_get_key_time(track, key) / maxf(elevated.length, 0.001)
			var lift := deg_to_rad(SWORD_I_ATTACK_LIFT_DEGREES) * sin(PI * progress)
			var pose: Quaternion = elevated.track_get_key_value(track, key)
			elevated.track_set_key_value(track, key,
				(Quaternion(Vector3.BACK, -lift) * pose).normalized())
	return elevated


static func _raise_heavy_sword_arc(source: Animation) -> Animation:
	# Start, wind-up and initial swing stay identical to the previous build
	# (envelope is exactly 0 there); the finishing phase is lifted by a
	# coordinated shoulder/arm/forearm/hand correction.
	var elevated := _apply_sword_i_sin_lift(source)
	for track in range(elevated.get_track_count()):
		if elevated.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path := elevated.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone := String(path.get_subname(path.get_subname_count() - 1))
		if not SWORD_I_FINISH_CORRECTION.has(bone):
			continue
		var vector: Vector3 = SWORD_I_FINISH_CORRECTION[bone]
		var angle := vector.length()
		for key in range(elevated.track_get_key_count(track)):
			var progress := elevated.track_get_key_time(track, key) / maxf(elevated.length, 0.001)
			var weight := finish_envelope(progress)
			if weight <= 0.0:
				continue
			var pose: Quaternion = elevated.track_get_key_value(track, key)
			var correction := Quaternion(vector / angle, angle * weight)
			elevated.track_set_key_value(track, key, (correction * pose).normalized())
	return elevated


# One broad right-handed hook for unarmed preview. The left arm retains
# the active locomotion clip; only the right shoulder/arm, torso and fist are
# keyed. Wind-up -> sweep across the chest -> controlled recovery.
const UNARMED_SWING_TIMES := [0.0, 0.10, 0.22, 0.30, 0.47, 0.55, 0.67, 0.78]
const UNARMED_SWING_GUARD := [0.0, 0.65, 1.0, 1.0, 1.0, 1.0, 0.65, 0.0]
const UNARMED_SWING_WINDUP := [0.0, 0.0, 0.85, 1.0, 0.0, 0.0, 0.0, 0.0]
const UNARMED_SWING_STRIKE := [0.0, 0.0, 0.0, 0.0, 1.0, 0.85, 0.20, 0.0]
const UNARMED_GUARD_ROTATIONS := {
	"J_Bip_R_Shoulder": Vector3(-0.06, 0.03, -0.10),
	"J_Bip_R_UpperArm": Vector3(-0.45, 0.10, -0.42),
	"J_Bip_R_LowerArm": Vector3(0.15, 0.02, -0.76),
	"J_Bip_R_Hand": Vector3(0.06, 0.0, 0.05),
}
const UNARMED_WINDUP_ROTATIONS := {
	"J_Bip_R_Shoulder": Vector3(-0.06, 0.0, -0.12),
	"J_Bip_R_UpperArm": Vector3(0.18, 0.30, -0.08),
	"J_Bip_R_LowerArm": Vector3(0.13, -0.05, -0.28),
	"J_Bip_R_Hand": Vector3(0.0, 0.06, 0.0),
	"J_Bip_C_Chest": Vector3(0.0, 0.12, 0.0),
}
const UNARMED_SWEEP_ROTATIONS := {
	"J_Bip_R_Shoulder": Vector3(-0.08, 0.02, 0.14),
	"J_Bip_R_UpperArm": Vector3(-0.45, -0.40, 0.25),
	"J_Bip_R_LowerArm": Vector3(-0.20, 0.0, 1.10),
	"J_Bip_R_Hand": Vector3(-0.06, 0.0, -0.15),
	"J_Bip_C_Chest": Vector3(0.0, -0.26, 0.0),
	"J_Bip_C_UpperChest": Vector3(0.0, -0.15, 0.0),
}

static func _unarmed_swing(walk: Animation) -> Animation:
	var clip := Animation.new()
	clip.length = UNARMED_SWING_TIMES.back()
	clip.loop_mode = Animation.LOOP_NONE
	var right_upper_arm_tracks := 0
	var curled_finger_tracks := 0
	for index in range(walk.get_track_count()):
		if walk.track_get_type(index) != Animation.TYPE_ROTATION_3D:
			continue
		var path := walk.track_get_path(index)
		if path.get_subname_count() == 0:
			continue
		var bone := String(path.get_subname(path.get_subname_count() - 1))
		var is_right_finger := bone.begins_with("J_Bip_R_") and SWORD_GRIP_FINGER_BENDS.has(bone)
		var is_arm := UNARMED_GUARD_ROTATIONS.has(bone)
		var is_torso := bone in ["J_Bip_C_Chest", "J_Bip_C_UpperChest"]
		if not (is_arm or is_right_finger or is_torso):
			continue
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, path)
		var baseline := walk.rotation_track_interpolate(index, 0.15)
		if is_right_finger:
			curled_finger_tracks += 1
		elif bone == "J_Bip_R_UpperArm":
			right_upper_arm_tracks += 1
		for phase in range(UNARMED_SWING_TIMES.size()):
			var guard := float(UNARMED_SWING_GUARD[phase])
			var windup := float(UNARMED_SWING_WINDUP[phase])
			var strike := float(UNARMED_SWING_STRIKE[phase])
			var pose: Quaternion
			if is_right_finger:
				var bend := float(SWORD_GRIP_FINGER_BENDS[bone])
				pose = (baseline * Quaternion(Vector3.BACK, bend * guard)).normalized()
			else:
				var offset := Vector3.ZERO
				if is_arm:
					offset += (UNARMED_GUARD_ROTATIONS[bone] as Vector3) * guard
				if UNARMED_WINDUP_ROTATIONS.has(bone):
					offset += (UNARMED_WINDUP_ROTATIONS[bone] as Vector3) * windup
				if UNARMED_SWEEP_ROTATIONS.has(bone):
					offset += (UNARMED_SWEEP_ROTATIONS[bone] as Vector3) * strike
				pose = (baseline * Quaternion.from_euler(offset)).normalized()
			clip.rotation_track_insert_key(track, float(UNARMED_SWING_TIMES[phase]), pose)
	if right_upper_arm_tracks != 1 or curled_finger_tracks != SWORD_GRIP_FINGER_BENDS.size():
		push_error("VRoid unarmed swing requires the right upper arm and all right-hand finger tracks")
		return null
	return clip


static func _sword_grip(walk: Animation) -> Animation:
	# VRoid finger joints extend along local +Y, with the knuckles distributed
	# along local Z. Positive local-Z curl bends the fingers toward the palm.
	# Reuse existing VRoid track paths and sampled rest-aware bone rotations.
	var grip := Animation.new()
	grip.length = 1.0
	grip.loop_mode = Animation.LOOP_LINEAR
	for index in range(walk.get_track_count()):
		if walk.track_get_type(index) != Animation.TYPE_ROTATION_3D:
			continue
		var path := walk.track_get_path(index)
		if path.get_subname_count() == 0:
			continue
		var bone := String(path.get_subname(path.get_subname_count() - 1))
		if not SWORD_GRIP_FINGER_BENDS.has(bone):
			continue
		var baseline := walk.rotation_track_interpolate(index, 0.15)
		var curl := Quaternion(Vector3.BACK, float(SWORD_GRIP_FINGER_BENDS[bone]))
		var track := grip.add_track(Animation.TYPE_ROTATION_3D)
		grip.track_set_path(track, path)
		grip.rotation_track_insert_key(track, 0.0, baseline * curl)
	return grip


static func _add_clip(root: AnimationNodeBlendTree, node_name: String, animation_name: String) -> void:
	var clip_node := AnimationNodeAnimation.new()
	clip_node.animation = animation_name
	root.add_node(node_name, clip_node)


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func setup_animation_tree(model: Node, animator: AnimationPlayer, attack_speed: float) -> AnimationTree:
	var walk_name := find_clip(animator, "Walk")
	var jog_name := find_clip(animator, "Jog")
	if walk_name.is_empty() or jog_name.is_empty():
		push_error("VRoid heroine requires imported Walk and Jog clips")
		return null
	var walk := animator.get_animation(walk_name)
	var jog := animator.get_animation(jog_name)
	var library := AnimationLibrary.new()
	library.add_animation("Idle", _hold_pose(walk, 0.15, 0.8, true))
	library.add_animation("Jump", _hold_pose(jog, 0.10, 0.65, false))
	var skeleton := _find_skeleton(model)
	if skeleton == null:
		push_error("Imported VRoid Skeleton3D not found")
		return null
	# Source library: CC0 UAL2 65-bone combat motions, retargeted in the
	# current 103-bone VRoid rest pose. The old procedural slash stays
	# available as an unused local function only for regression diagnosis.
	var swing := UAL2_COMBAT.build("Sword_Regular_A", walk, skeleton, true)
	var heavy := UAL2_COMBAT.build("Sword_Heavy_A", walk, skeleton, true)
	if swing == null or heavy == null:
		push_error("UAL2 Sword attack retargeting failed")
		return null
	heavy = _raise_heavy_sword_arc(heavy)
	library.add_animation("SwordSlash", swing)
	library.add_animation("SwordHeavyCandidate", heavy)
	var unarmed_swing := _unarmed_swing(walk)
	if unarmed_swing == null:
		return null
	library.add_animation("UnarmedSwing", unarmed_swing)
	var grip := _sword_grip(walk)
	if grip.get_track_count() != SWORD_GRIP_FINGER_BENDS.size():
		push_error("VRoid weapon grip requires all expected finger and distal thumb tracks")
		return null
	library.add_animation("SwordGrip", grip)
	# Godot 4 bone animation values include the actual per-bone rest transform.
	# The previous retarget missed this and collapsed the VRoid pose in gameplay.
	# The original imported Walk/Jog clips are kept intact on the VRoid model.
	var replacement_walk: Animation = QUATERNIUS_LOCOMOTION.build_from_reference(walk, false, skeleton)
	var replacement_run: Animation = QUATERNIUS_LOCOMOTION.build_from_reference(walk, true, skeleton)
	if replacement_walk == null or replacement_run == null:
		push_error("Failed to retarget Quaternius locomotion to VRoid skeleton")
		return null
	var safe_run := _safe_weapon_run(replacement_run, replacement_walk)
	if safe_run == null:
		push_error("Failed to build VRoid weapon-safe running arm pose")
		return null
	library.add_animation("QuaterniusWalk", replacement_walk)
	library.add_animation("QuaterniusRun", safe_run)
	# Unarmed run: the complete original Quaternius Run, including the natural
	# right-arm swing. It has the same length/phase as the weapon-safe Run
	# (that one is a duplicate with four right-arm tracks retuned).
	library.add_animation("QuaterniusRunFree", replacement_run)
	if animator.add_animation_library("vroid", library) != OK:
		return null

	var root := AnimationNodeBlendTree.new()
	var locomotion := AnimationNodeTransition.new()
	locomotion.input_count = 5
	locomotion.xfade_time = 0.10
	root.add_node("Locomotion", locomotion)
	var state_names := ["Idle", "Walk", "Run", "Jump"]
	var clips := ["vroid/Idle", "vroid/QuaterniusWalk", "vroid/QuaterniusRun", "vroid/Jump"]
	for i in range(state_names.size()):
		var state: String = state_names[i]
		_add_clip(root, state, clips[i])
		locomotion.set_input_name(i, state)
		if state == "Run":
			# RunArms 0 = weapon-safe Run, 1 = full Run. Both clips advance with
			# the same RunSpeed, so switching only crossfades the right arm.
			_add_clip(root, "RunFree", "vroid/QuaterniusRunFree")
			var run_arms := AnimationNodeBlend2.new()
			# Both Run clips must advance at zero blend weight: an equip/unequip
			# crossfade otherwise resumes the inactive clip at an older gait phase.
			run_arms.sync = true
			root.add_node("RunArms", run_arms)
			root.connect_node("RunArms", 0, state)
			root.connect_node("RunArms", 1, "RunFree")
			var run_speed := AnimationNodeTimeScale.new()
			root.add_node("RunSpeed", run_speed)
			root.connect_node("RunSpeed", 0, "RunArms")
			root.connect_node("Locomotion", i, "RunSpeed")
		elif state == "Walk":
			var speed := AnimationNodeTimeScale.new()
			root.add_node(state + "Speed", speed)
			root.connect_node(state + "Speed", 0, state)
			root.connect_node("Locomotion", i, state + "Speed")
		else:
			root.connect_node("Locomotion", i, state)

	# The Naruto toggle remains available, but temporarily reuses Jog;
	# applying Ninja-specific tracks to this different rig would be unsafe.
	_add_clip(root, "NarutoBaseRun", jog_name)
	_add_clip(root, "NarutoFull", jog_name)
	var naruto_base_speed := AnimationNodeTimeScale.new()
	var naruto_full_speed := AnimationNodeTimeScale.new()
	var naruto_blend := AnimationNodeBlend2.new()
	root.add_node("NarutoBaseRunSpeed", naruto_base_speed)
	root.add_node("NarutoFullSpeed", naruto_full_speed)
	root.add_node("NarutoFullBodyBlend", naruto_blend)
	root.connect_node("NarutoBaseRunSpeed", 0, "NarutoBaseRun")
	root.connect_node("NarutoFullSpeed", 0, "NarutoFull")
	root.connect_node("NarutoFullBodyBlend", 0, "NarutoBaseRunSpeed")
	root.connect_node("NarutoFullBodyBlend", 1, "NarutoFullSpeed")
	locomotion.set_input_name(4, "Naruto")
	root.connect_node("Locomotion", 4, "NarutoFullBodyBlend")

	_add_clip(root, "SwordSlash", "vroid/SwordSlash")
	_add_clip(root, "SwordHeavyCandidate", "vroid/SwordHeavyCandidate")
	var slash_choice := AnimationNodeBlend2.new()
	root.add_node("SlashChoice", slash_choice)
	root.connect_node("SlashChoice", 0, "SwordSlash")
	root.connect_node("SlashChoice", 1, "SwordHeavyCandidate")
	_add_clip(root, "UnarmedSwing", "vroid/UnarmedSwing")
	var unarmed_choice := AnimationNodeBlend2.new()
	root.add_node("UnarmedChoice", unarmed_choice)
	root.connect_node("UnarmedChoice", 0, "SlashChoice")
	root.connect_node("UnarmedChoice", 1, "UnarmedSwing")
	var attack_speed_node := AnimationNodeTimeScale.new()
	var attack_layer := AnimationNodeOneShot.new()
	attack_layer.fadein_time = 0.09
	attack_layer.fadeout_time = 0.10
	attack_layer.filter_enabled = true
	for clip in [swing, unarmed_swing]:
		for index in range(clip.get_track_count()):
			attack_layer.set_filter_path(clip.track_get_path(index), true)
	root.add_node("AttackSpeed", attack_speed_node)
	root.add_node("Attack", attack_layer)
	root.connect_node("AttackSpeed", 0, "UnarmedChoice")
	root.connect_node("Attack", 0, "Locomotion")
	root.connect_node("Attack", 1, "AttackSpeed")

	# Only right-hand finger/thumb tracks are overridden. The accepted Walk/Run,
	# upper-arm attack layer, and root locomotion remain unmodified.
	_add_clip(root, "SwordGrip", "vroid/SwordGrip")
	var grip_overlay := AnimationNodeBlend2.new()
	grip_overlay.filter_enabled = true
	for index in range(grip.get_track_count()):
		grip_overlay.set_filter_path(grip.track_get_path(index), true)
	root.add_node("GripOverlay", grip_overlay)
	root.connect_node("GripOverlay", 0, "Attack")
	root.connect_node("GripOverlay", 1, "SwordGrip")
	root.connect_node("output", 0, "GripOverlay")

	var animation_tree := AnimationTree.new()
	animation_tree.name = "CharacterAnimationTree"
	model.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animator)
	animation_tree.tree_root = root
	animator.stop()
	animation_tree.active = true
	animation_tree.set("parameters/AttackSpeed/scale", attack_speed)
	animation_tree.set("parameters/NarutoFullBodyBlend/blend_amount", 1.0)
	animation_tree.set("parameters/NarutoFullSpeed/scale", 1.0)
	animation_tree.set("parameters/GripOverlay/blend_amount", 1.0)
	animation_tree.set("parameters/RunArms/blend_amount", 0.0)
	animation_tree.set("parameters/SlashChoice/blend_amount", 0.0)
	animation_tree.set("parameters/UnarmedChoice/blend_amount", 0.0)
	return animation_tree
