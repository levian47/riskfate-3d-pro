extends SkeletonModifier3D
# Naruto-only crouch layer. Applies pelvis lean after the native running pose
# and before the existing leg IK. Approved attacks and the source clips stay intact.
const PELVIS_BONE := "Body_2"
const SPINE_BONE := "Hips"
const LEG_ROOT_BONES := ["UpperLeg.L", "UpperLeg.R"]
const DROP_METERS := 0.14
# Small anatomical hip tilt, not the full ~65-degree torso lean.
const PELVIS_TILT_DEGREES := 20.0

var pelvis_bone_index := -1
var spine_bone_index := -1
var leg_root_indices: Array[int] = []


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	pelvis_bone_index = skeleton.find_bone(PELVIS_BONE)
	spine_bone_index = skeleton.find_bone(SPINE_BONE)
	for bone_name in LEG_ROOT_BONES:
		leg_root_indices.append(skeleton.find_bone(bone_name))


func _process_modification_with_delta(_delta: float) -> void:
	if pelvis_bone_index < 0 or spine_bone_index < 0:
		return
	for index in leg_root_indices:
		if index < 0:
			return
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	# Body_2 is parent to BOTH the spine and the legs. Rotating it without
	# correction would pitch the already-approved torso farther forward and
	# turn the legs away from the original run's stride.
	var tilt := Quaternion(Vector3.RIGHT, deg_to_rad(PELVIS_TILT_DEGREES))
	var untilted_child_indices: Array[int] = [spine_bone_index]
	untilted_child_indices.append_array(leg_root_indices)
	for index in untilted_child_indices:
		# Rest orientation differs between spine and leg bones. Conjugating by
		# the child rest basis cancels the parent's extra rotation in that bone's
		# local pose while preserving its animated global orientation.
		var rest_rotation := skeleton.get_bone_rest(index).basis.orthonormalized().get_rotation_quaternion()
		var local_counter_rotation := rest_rotation.inverse() * tilt.inverse() * rest_rotation
		var source_rotation := skeleton.get_bone_pose_rotation(index)
		skeleton.set_bone_pose_rotation(index, (local_counter_rotation * source_rotation).normalized())

	# Translate and pitch the pelvis only in Naruto mode. The following two
	# stock TwoBoneIK3D modifiers restore the animated foot targets.
	var source_position := skeleton.get_bone_pose_position(pelvis_bone_index)
	var source_rotation := skeleton.get_bone_pose_rotation(pelvis_bone_index)
	skeleton.set_bone_pose_position(pelvis_bone_index, source_position + Vector3.DOWN * DROP_METERS)
	skeleton.set_bone_pose_rotation(pelvis_bone_index, (source_rotation * tilt).normalized())
