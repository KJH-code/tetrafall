# 닌자 동작 클립 (W23): 자동 리깅 닌자 뼈대 (Mixamo 식 이름) 에 손으로 만든 키프레임 동작을 넣어 ninja_anim.glb 로 (뼈대 + 동작만, 메시 없음).
# blender -b --factory-startup -P tools/blender/tripo/anim_ninja.py -- --rig <ninja_rigged.glb> --out <ninja_anim.glb> [--clips clips_tank]  (W33: --rig 는 assets/models/ext/<id>.glb 그대로 가능)
#
# 자세 쓰는 법 (아래 POSES·CLIPS): 코드 몸 (figure) 처럼 '관절 각' 으로 쓰되 (앞뒤·옆·비틀기·굽힘, 라디안 아닌 도), 코드 몸에 없는 관절 (척추 셋·빗장·머리·발목·손목) 도 쓸 수 있음.
#   좌표 (Blender, 원본 닌자): 앞 +X, 왼쪽 +Y, 위 +Z.  각 뼈의 회전 Δ 는 '부모가 이미 돌아간 뒤' 에 이 축으로 더함 (FK).
#   서 있는 몸 기준: 윗몸 pitch + = 앞으로 숙임, twist + = 왼쪽으로 돎, side + = 오른쪽으로 기움.
#   팔다리 (아래로 늘어진 뼈): fwd + = 앞으로 듦, out + = 바깥 (왼쪽 뼈는 +Y, 오른쪽 뼈는 -Y, 값은 늘 '바깥 +'), knee·elbow + = 접음, foot + = 발끝 내림.
#   값 두 개짜리 = (오른쪽, 왼쪽) — 코드 몸 figure 와 같은 순서.
# 동작마다 시간표 (초, 30fps): 공격은 정해진 눈금 (WIND_END 까지 준비 → STRIKE_END 까지 타격 → REC_END 까지 회복) 이라 런타임이 서버 단계 (준비·타격·회복, u 0~1) 를 눈금에 구간별로 맞춤.
import bpy
import sys
import os
import math
from mathutils import Vector, Matrix

P = "mixamorig:"
FPS = 30
AX = Vector((1, 0, 0))
AY = Vector((0, 1, 0))
AZ = Vector((0, 0, 1))

# 공격 눈금 (초): 이 시각들에 키를 찍고, 런타임이 준비 u 0~1 → 0~WIND, 타격 u → WIND~STRIKE, 회복 u → STRIKE~REC
WIND = 0.30
STRIKE = 0.40
REC = 0.80


def R(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


def two(v):
    return (v, v) if not isinstance(v, (tuple, list)) else v


class Pose(dict):
    """자세: 키 → 값 (중앙 값은 숫자, 좌우 값은 (오른쪽, 왼쪽))"""

    def g(self, k, i=None):
        v = self.get(k, 0.0)
        if i is None:
            return v
        return two(v)[i]


def sided(pose, key):
    return pose.g(key, 0), pose.g(key, 1)


CHAIN = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
         "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
         "RightShoulder", "RightArm", "RightForeArm", "RightHand",
         "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
         "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
PARENT = {"Spine": "Hips", "Spine1": "Spine", "Spine2": "Spine1", "Neck": "Spine2", "Head": "Neck",
          "LeftShoulder": "Spine2", "LeftArm": "LeftShoulder", "LeftForeArm": "LeftArm", "LeftHand": "LeftForeArm",
          "RightShoulder": "Spine2", "RightArm": "RightShoulder", "RightForeArm": "RightArm", "RightHand": "RightForeArm",
          "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
          "RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg", "RightToeBase": "RightFoot"}


def deltas(p, cum):
    """자세 → 뼈마다 Δ (3x3). cum = 지금까지 쌓인 부모 회전 (뼈 이름 → 3x3), 접는 관절의 축을 부모 따라 돌리려고 씀"""
    d = {}
    d["Hips"] = R("Z", p.g("hips_twist")) @ R("X", p.g("hips_side")) @ R("Y", p.g("hips_pitch"))
    for nm, k in (("Spine", 0.3), ("Spine1", 0.3), ("Spine2", 0.4)):
        d[nm] = R("Z", p.g("spine_twist") * k) @ R("X", p.g("spine_side") * k) @ R("Y", p.g("spine_pitch") * k)
    d["Neck"] = R("Z", p.g("neck_yaw") * 0.4) @ R("X", p.g("neck_side") * 0.4) @ R("Y", p.g("neck_pitch") * 0.4)
    d["Head"] = R("Z", p.g("neck_yaw") * 0.6) @ R("X", p.g("neck_side") * 0.6) @ R("Y", p.g("neck_pitch") * 0.6)
    for i, sd in ((0, "Right"), (1, "Left")):
        s = 1.0 if sd == "Left" else -1.0
        d[sd + "Shoulder"] = R("X", s * p.g("clav_lift", i)) @ R("Z", -s * p.g("clav_fwd", i))
        d[sd + "Arm"] = ("arm", p.g("arm_fwd", i), s * p.g("arm_out", i), p.g("arm_twist", i))
        d[sd + "ForeArm"] = ("hinge", p.g("elbow", i), 1.0, sd + "Arm", p.g("fore_twist", i))
        d[sd + "Hand"] = ("hinge", p.g("hand", i), 1.0, sd + "ForeArm", 0.0)
        d[sd + "UpLeg"] = ("arm", p.g("leg_fwd", i), s * p.g("leg_out", i), p.g("leg_twist", i))
        d[sd + "Leg"] = ("hinge", p.g("knee", i), -1.0, sd + "UpLeg", 0.0)
        d[sd + "Foot"] = ("hinge", p.g("foot", i), -1.0, sd + "Leg", 0.0)
        d[sd + "ToeBase"] = ("hinge", p.g("toe", i), -1.0, sd + "Foot", 0.0)
    return d


def apply_pose(arm, p):
    """뼈대에 자세 p 를 검 (부모 먼저). 위치는 골반만: hips_x·y·z (m, 원본 단위)"""
    pb = arm.pose.bones
    cum = {}
    d = deltas(p, {})
    # 쉬는 자세 구하기 위해 모두 초기화
    for b in pb:
        b.rotation_mode = "QUATERNION"
        b.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for nm in CHAIN:
        b = pb[P + nm]
        par = PARENT.get(nm)
        if par is None:
            m = b.bone.matrix_local.copy()
            parent_cum = Matrix.Identity(3)
            m3 = m.to_3x3()
            tr = m.translation + Vector((p.g("hips_x"), p.g("hips_y"), p.g("hips_z")))
        else:
            pp = pb[P + par]
            rel = pp.bone.matrix_local.inverted() @ b.bone.matrix_local
            m = pp.matrix @ rel
            parent_cum = cum[par]
            m3 = m.to_3x3()
            tr = m.translation
        dv = d.get(nm, Matrix.Identity(3))
        if isinstance(dv, tuple):
            kind = dv[0]
            if kind == "arm":
                _, fwd, out, twist = dv
                dm = R("Y", -fwd) @ R("X", out)
                # 비틀기: 뼈 방향 (부모 회전 뒤) 축
                dirv = (m3 @ Vector((0, 1, 0)))  # 뼈의 길이 방향 (Blender 뼈는 +Y 가 머리→꼬리)
                if abs(twist) > 1e-6:
                    dm = Matrix.Rotation(math.radians(twist), 3, (dm @ dirv).normalized()) @ dm
            else:  # hinge: 부모 뼈의 Δ 가 이미 쌓인 축 (옆축 Y 를 부모 회전 따라 돌림)
                _, ang, sign, pname, twist = dv
                axis = (cum[pname] @ AY).normalized() if pname in cum else AY
                dm = Matrix.Rotation(math.radians(sign * -ang), 3, axis)
                if abs(twist) > 1e-6:
                    dirv = m3 @ Vector((0, 1, 0))
                    dm = Matrix.Rotation(math.radians(twist), 3, dirv.normalized()) @ dm
        else:
            dm = dv
        cum[nm] = dm @ parent_cum
        new3 = dm @ m3
        nm4 = new3.to_4x4()
        nm4.translation = tr
        b.matrix = nm4
        bpy.context.view_layer.update()
    return cum


# ---------- 자세 표 ----------
# 값 이름: hips_x/y/z (m) hips_pitch/twist/side · spine_pitch/twist/side · neck_pitch/yaw/side · clav_lift/fwd (R,L) · arm_fwd/out/twist (R,L) · elbow (R,L) · fore_twist · hand
#         leg_fwd/out/twist (R,L) · knee (R,L) · foot (R,L) · toe (R,L)
STAND = Pose(elbow=(15, 15), knee=(5, 5))


NEG_CENTER = ("hips_twist", "hips_side", "hips_y", "spine_twist", "spine_side", "neck_yaw", "neck_side")
NEG_SIDED = ("arm_twist", "fore_twist", "leg_twist")


def mirror(p):
    """좌우 뒤집은 자세: (오른쪽, 왼쪽) 쌍은 맞바꾸고, 비틀기·옆 기울기·옆 이동은 부호를 뒤집음"""
    q = Pose()
    for k, v in p.items():
        if isinstance(v, (tuple, list)):
            a, b = v
            if k in NEG_SIDED:
                a, b = -a, -b
            q[k] = (b, a)
        else:
            q[k] = -v if k in NEG_CENTER else v
    return q


def mix(a, b, t):
    """두 자세 섞기 (숫자·쌍 모두)"""
    out = Pose()
    for k in set(a) | set(b):
        va, vb = a.get(k, 0.0), b.get(k, 0.0)
        if isinstance(va, (tuple, list)) or isinstance(vb, (tuple, list)):
            va, vb = two(va), two(vb)
            out[k] = (va[0] + (vb[0] - va[0]) * t, va[1] + (vb[1] - va[1]) * t)
        else:
            out[k] = va + (vb - va) * t
    return out


def P_(base=None, **kw):
    q = Pose(base if base is not None else STAND)
    q.update(kw)
    return q


# ---------- 클립 ----------
# 클립 = (길이 초, 반복 여부, [(시각 초, 자세), ...])
CLIPS = {}


def clip(name, length, loop, keys):
    CLIPS[name] = (length, loop, keys)


CLIPS_MODULE = "clips_ninja"  # W33: --clips <모듈 이름> 으로 캐릭터별 자세 표 (clips_tank·clips_hunter·clips_hook)


def build_clips():
    import importlib
    define = importlib.import_module(CLIPS_MODULE).define  # 별도 파일 (자세 표가 길어서)
    define(sys.modules[__name__])


def author(arm):
    """CLIPS → 액션 + NLA 트랙 (내보내기가 트랙 이름으로 동작을 가름)"""
    ad = arm.animation_data_create()
    for name, (length, loop, keys) in CLIPS.items():
        act = bpy.data.actions.new(name)
        ad.action = act
        for t, pose in keys:
            apply_pose(arm, pose)
            f = 1 + round(t * FPS)
            for nm in CHAIN:  # 손가락 같은 안 쓰는 뼈는 키를 안 찍음 (파일 크기)
                b = arm.pose.bones[P + nm]
                b.keyframe_insert("rotation_quaternion", frame=f)
                if nm == "Hips":
                    b.keyframe_insert("location", frame=f)
        act.use_fake_user = True
        tr = ad.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, 1, act)
        st.name = name
        ad.action = None
        print("TF 동작", name, "%.2fs" % length, len(keys), "키")
    return ad


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    rig = a[a.index("--rig") + 1]
    out = a[a.index("--out") + 1]
    global CLIPS_MODULE
    if "--clips" in a:
        CLIPS_MODULE = a[a.index("--clips") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=rig)
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    sys.dont_write_bytecode = True
    build_clips()
    author(arm)
    bpy.context.scene.render.fps = FPS
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=1,
                              export_optimize_animation_size=True, export_skins=True, export_def_bones=False,
                              export_leaf_bone=False, export_yup=True, export_extras=False, export_cameras=False, export_lights=False)
    print("TF 내보냄", out)


if __name__ == "__main__":
    main()
