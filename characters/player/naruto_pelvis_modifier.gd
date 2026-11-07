extends SkeletonModifier3D
# Naruto-only crouch layer. Runs after imported animation playback and before
# the two native IK modifiers, without rewriting the approved Ninja Run clip.
const PELVIS_BONE := "Body_2"
const DROP_METERS := 0.14

var pelvis_bone_index := -1


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton != null:
		pelvis_bone_index = skeleton.find_bone(PELVIS_BONE)


func _process_modification_with_delta(_delta: float) -> void:
	if pelvis_bone_index < 0:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	# AnimationTree provides the original pose afresh every frame.
	var original_position := skeleton.get_bone_pose_position(pelvis_bone_index)
	skeleton.set_bone_pose_position(pelvis_bone_index, original_position + Vector3.DOWN * DROP_METERS)
