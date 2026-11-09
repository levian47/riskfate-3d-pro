extends RefCounted
# Retargeted Quaternius Universal Animation Library [Standard] motion data.
# Source: Walk_Loop + Jog_Fwd_Loop by Quaternius, CC0 1.0 Universal.
# https://quaternius.com/ | https://creativecommons.org/publicdomain/zero/1.0/
# 22 VRoid humanoid bones, 16-bit rotation-delta keys, in-place hip sway.

const BONES := [
    "J_Bip_C_Hips", "J_Bip_C_Spine", "J_Bip_C_Chest", "J_Bip_C_UpperChest",
    "J_Bip_C_Neck", "J_Bip_C_Head",
    "J_Bip_L_Shoulder", "J_Bip_L_UpperArm", "J_Bip_L_LowerArm", "J_Bip_L_Hand",
    "J_Bip_R_Shoulder", "J_Bip_R_UpperArm", "J_Bip_R_LowerArm", "J_Bip_R_Hand",
    "J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_L_Foot", "J_Bip_L_ToeBase",
    "J_Bip_R_UpperLeg", "J_Bip_R_LowerLeg", "J_Bip_R_Foot", "J_Bip_R_ToeBase",
]

const WALK_FRAME_COUNT := 37
const WALK_DURATION := 1.33333337
const RUN_FRAME_COUNT := 29
const RUN_DURATION := 0.93333334

const WALK_B64 := "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"
const RUN_B64 := "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"


static func build_from_reference(reference: Animation, running: bool, skeleton: Skeleton3D) -> Animation:
    # Reuse the imported VRoid skeleton paths and actual bone rests. Preserve the original
    # Walk/Jog resources as a rollback option; no imported rig changes.
    if skeleton == null:
        push_error("Quaternius retarget needs the imported VRoid Skeleton3D")
        return null
    var frames := RUN_FRAME_COUNT if running else WALK_FRAME_COUNT
    var duration := RUN_DURATION if running else WALK_DURATION
    var data := Marshalls.base64_to_raw(RUN_B64 if running else WALK_B64)
    var expected := BONES.size() * frames * 6 + frames * 4
    if data.size() != expected:
        push_error("Quaternius locomotion data length mismatch")
        return null

    var rotation_paths := {}
    var hips_position_path := NodePath()
    for i in range(reference.get_track_count()):
        var path := reference.track_get_path(i)
        if path.get_subname_count() == 0:
            continue
        var bone := String(path.get_subname(path.get_subname_count() - 1))
        if reference.track_get_type(i) == Animation.TYPE_ROTATION_3D:
            rotation_paths[bone] = path
        elif reference.track_get_type(i) == Animation.TYPE_POSITION_3D and bone == "J_Bip_C_Hips":
            hips_position_path = path

    var clip := Animation.new()
    clip.length = duration
    clip.loop_mode = Animation.LOOP_LINEAR
    var offset := 0
    for bone_name in BONES:
        if not rotation_paths.has(bone_name):
            push_error("VRoid animation missing rotation track: " + bone_name)
            return null
        var bone_index := skeleton.find_bone(bone_name)
        if bone_index < 0:
            push_error("VRoid skeleton missing bone: " + bone_name)
            return null
        # Godot 4 animation tracks contain Bone Rest, not only the pose delta.
        var rest_rotation := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
        var track := clip.add_track(Animation.TYPE_ROTATION_3D)
        clip.track_set_path(track, rotation_paths[bone_name])
        for frame in range(frames):
            var x := float(data.decode_s16(offset)) / 32767.0
            var y := float(data.decode_s16(offset + 2)) / 32767.0
            var z := float(data.decode_s16(offset + 4)) / 32767.0
            offset += 6
            var w := sqrt(maxf(0.0, 1.0 - x * x - y * y - z * z))
            var rest_delta := Quaternion(x, y, z, w).normalized()
            var local_pose := (rest_rotation * rest_delta).normalized()
            clip.rotation_track_insert_key(track, duration * float(frame) / float(frames - 1), local_pose)

    if hips_position_path == NodePath():
        push_error("VRoid animation missing hips position track")
        return null
    var hips_index := skeleton.find_bone("J_Bip_C_Hips")
    if hips_index < 0:
        push_error("VRoid skeleton missing hips")
        return null
    var hips_rest_position := skeleton.get_bone_rest(hips_index).origin
    var position_track := clip.add_track(Animation.TYPE_POSITION_3D)
    clip.track_set_path(position_track, hips_position_path)
    for frame in range(frames):
        var dx := float(data.decode_s16(offset)) / 10000.0
        var dy := float(data.decode_s16(offset + 2)) / 10000.0
        offset += 4
        clip.position_track_insert_key(
            position_track, duration * float(frame) / float(frames - 1),
            hips_rest_position + Vector3(dx, dy, 0.0)
        )
    return clip