extends RefCounted
# Retargeted Quaternius Universal Animation Library [Standard] motion data.
# Source: Walk_Loop + Sprint_Loop by Quaternius, CC0 1.0 Universal.
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
const RUN_FRAME_COUNT := 21
const RUN_DURATION := 0.66666669

const WALK_B64 := "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"
const RUN_B64 := "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"


static func build_from_reference(reference: Animation, running: bool) -> Animation:
    # Reuse the imported VRoid skeleton track paths. Preserve the original
    # Walk/Jog resources as a rollback option; no imported rig changes.
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
        var track := clip.add_track(Animation.TYPE_ROTATION_3D)
        clip.track_set_path(track, rotation_paths[bone_name])
        for frame in range(frames):
            var x := float(data.decode_s16(offset)) / 32767.0
            var y := float(data.decode_s16(offset + 2)) / 32767.0
            var z := float(data.decode_s16(offset + 4)) / 32767.0
            offset += 6
            var w := sqrt(maxf(0.0, 1.0 - x * x - y * y - z * z))
            var pose := Quaternion(x, y, z, w).normalized()
            clip.rotation_track_insert_key(track, duration * float(frame) / float(frames - 1), pose)

    if hips_position_path == NodePath():
        push_error("VRoid animation missing hips position track")
        return null
    var position_track := clip.add_track(Animation.TYPE_POSITION_3D)
    clip.track_set_path(position_track, hips_position_path)
    for frame in range(frames):
        var dx := float(data.decode_s16(offset)) / 10000.0
        var dy := float(data.decode_s16(offset + 2)) / 10000.0
        offset += 4
        clip.position_track_insert_key(position_track, duration * float(frame) / float(frames - 1), Vector3(dx, dy, 0.0))
    return clip