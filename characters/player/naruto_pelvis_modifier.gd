extends SkeletonModifier3D
# Naruto-only pelvis adjustment. The pelvis and Hips must lean together;
# compensating Hips directly would cancel the visible hip deformation.
# This modifier runs after AnimationTree and before the existing foot IK.
const PELVIS_BONE := "Body_2"
const HIPS_BONE := "Hips"
const ABDOMEN_BONE := "Abdomen"
const LEG_ROOT_BONES := ["UpperLeg.L", "UpperLeg.R"]
const DROP_METERS := 0.14
const PELVIS_TILT_DEGREES := 20.0

var pelvis_index := -1
var hips_index := -1
var abdomen_index := -1
var leg_indices: Array[int] = []
var leg_counter_rotations: Array[Quaternion] = []

var hips_rest_rotation := Quaternion.IDENTITY
var abdomen_rest_rotation := Quaternion.IDENTITY
var tilt := Quaternion.IDENTITY
var tilt_inverse := Quaternion.IDENTITY
# Diagnostics are sampled inside modification_processed during smoke tests.
var applied_count := 0
var last_source_y := 0.0


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	pelvis_index = skeleton.find_bone(PELVIS_BONE)
	hips_index = skeleton.find_bone(HIPS_BONE)
	abdomen_index = skeleton.find_bone(ABDOMEN_BONE)
	if hips_index < 0 or abdomen_index < 0:
		return
	tilt = Quaternion(Vector3.RIGHT, deg_to_rad(PELVIS_TILT_DEGREES))
	tilt_inverse = tilt.inverse()
	hips_rest_rotation = skeleton.get_bone_rest(hips_index).basis.orthonormalized().get_rotation_quaternion()
	abdomen_rest_rotation = skeleton.get_bone_rest(abdomen_index).basis.orthonormalized().get_rotation_quaternion()
	for bone_name in LEG_ROOT_BONES:
		var index := skeleton.find_bone(bone_name)
		leg_indices.append(index)
		if index >= 0:
			var rest_rotation := skeleton.get_bone_rest(index).basis.orthonormalized().get_rotation_quaternion()
			leg_counter_rotations.append((rest_rotation.inverse() * tilt_inverse * rest_rotation).normalized())
		else:
			leg_counter_rotations.append(Quaternion.IDENTITY)


func _process_modification_with_delta(_delta: float) -> void:
	if pelvis_index < 0 or hips_index < 0 or abdomen_index < 0:
		return
	if leg_indices.size() != LEG_ROOT_BONES.size():
		return
	for index in leg_indices:
		if index < 0:
			return
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	# Body_2 carries the pelvic mesh, while Hips carries further pelvic weights.
	# Do NOT undo the tilt on Hips: that is why the former implementation made
	# only a small part of the pelvis move.
	#
	# Abdomen is the first bone above the pelvis. Counter-rotate it instead.
	# The counter-rotation must include the current animated Hips pose and the
	# two rest rotations, otherwise the upper body turns by an unwanted angle.
	var hips_animation := skeleton.get_bone_pose_rotation(hips_index)
	var hips_chain := (hips_rest_rotation * hips_animation).normalized()
	var abdomen_counter := (
		abdomen_rest_rotation.inverse()
		* hips_chain.inverse()
		* tilt_inverse
		* hips_chain
		* abdomen_rest_rotation
	).normalized()
	var abdomen_animation := skeleton.get_bone_pose_rotation(abdomen_index)
	skeleton.set_bone_pose_rotation(abdomen_index, (abdomen_counter * abdomen_animation).normalized())

	# Restore the imported Run orientation of both leg roots; foot IK then
	# handles any positional change in the feet caused by lowering the pelvis.
	for i in range(leg_indices.size()):
		var index := leg_indices[i]
		var source_rotation := skeleton.get_bone_pose_rotation(index)
		skeleton.set_bone_pose_rotation(index, (leg_counter_rotations[i] * source_rotation).normalized())

	var source_position := skeleton.get_bone_pose_position(pelvis_index)
	var source_rotation := skeleton.get_bone_pose_rotation(pelvis_index)
	last_source_y = source_position.y
	applied_count += 1
	skeleton.set_bone_pose_position(pelvis_index, source_position + Vector3.DOWN * DROP_METERS)
	skeleton.set_bone_pose_rotation(pelvis_index, (source_rotation * tilt).normalized())
