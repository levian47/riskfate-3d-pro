extends RefCounted
# CC0 frames from Quaternius Universal Animation Library 2 [Standard].
# Melee_Hook (15 frames) + Melee_Hook_Rec (19 frames), 30 fps.
# The duplicate boundary frame is removed; quaternions quantized to int16.
# Only right arm + chest rotations: no left-arm punch or root movement.
# Source and CC0 license: https://quaternius.com
const FRAME_RATE := 30.0
const FRAME_COUNT := 33
const BONES := ["spine_02", "spine_03", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
const ROTATIONS_BASE64 := "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"

static func get_clip_length() -> float:
	return float(FRAME_COUNT - 1) / FRAME_RATE

static func decode_tracks() -> Dictionary:
	var raw := Marshalls.base64_to_raw(ROTATIONS_BASE64)
	if raw.size() != BONES.size() * FRAME_COUNT * 8:
		push_error("UAL2 Hook: invalid quaternion sample count")
		return {}
	var tracks := {}
	for bone_index in range(BONES.size()):
		var quats: Array[Quaternion] = []
		for frame in range(FRAME_COUNT):
			var offset := (bone_index * FRAME_COUNT + frame) * 8
			quats.append(Quaternion(
				float(raw.decode_s16(offset)) / 32767.0,
				float(raw.decode_s16(offset + 2)) / 32767.0,
				float(raw.decode_s16(offset + 4)) / 32767.0,
				float(raw.decode_s16(offset + 6)) / 32767.0).normalized())
		tracks[BONES[bone_index]] = quats
	return tracks
