# 탱크 (W19 시험 제작, 화풍 ③ 중간: 둥글고 굵은 형태 + 단순한 색). 중무장 방패병 — 둥근 투구 + 볏 (몸 색), 넓은 어깨 갑옷, 단단한 장갑, 왕눈알, 큰 둥근 방패 (따로).
# 자리는 ref/tank_rig.json (고도 몸 쉬는 자세 관절, 게임 좌표 m). 색: JS figure.js dressTank 와 같은 값 (쇠 a3adb8 · 어두운 쇠 5d6672 · 가죽 6a4428 · 금 d8a838),
# skin=True 는 플레이어 색 칸 (JS cloth: 겉옷·소매·볏·방패 판·얼굴)
import math
from mathutils import Vector

STEEL = 0xa3adb8
DARK = 0x5d6672
LEATHER = 0x6a4428
GOLD = 0xd8a838
WHITE = 0xffffff
PUPIL = 0x15151a

SHIELD_GLB = "res://assets/models/ext/tank_shield.glb"
# 고도 조정 값 (build_character.py 가 height·offset·tint 와 합쳐 tank.json 으로).
# 방패: 안쪽 몸 방패 노드 (shields.back 등 = 등 / front 방패 동작 동안 가슴 앞, 1인칭은 viewmodel 이 왼손에 쥠) 아래에 붙임 — 보이기·1인칭 쥐기는 예전 그대로.
# 판 3인칭 앞 방패만 돌기가 바깥을 보게 z 180° (JS 는 등 방패를 복제해서 앞 방패 돌기가 몸 쪽 — 1인칭은 viewmodel 이 돌기 = -x 로 맞춤)
CFG = {
    "attach": [
        {"glb": SHIELD_GLB, "ref": "shields.back"},
        {"glb": SHIELD_GLB, "ref": "shields.front", "rot": [0, 0, 180], "vm": False},
        {"glb": SHIELD_GLB, "ref": "shields.front", "third": False},
    ],
}


def _rot_to(d):
    """게임 z 축을 d 로 돌리는 오일러 XYZ (도)"""
    e = Vector((0, 0, 1)).rotation_difference(Vector(d).normalized()).to_euler("XYZ")
    return (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z))


def build(k):
    J = k.j
    T = J("torso")  # 통 몸 가운데
    N = J("neck")
    BR = (0.30, 0.355, 0.43)  # 통 몸 반지름 (JS drum chestR·depth·torso × 1.15 와 비슷하게)

    def ell(z, grow=0.0):
        """통 몸의 높이 z 단면 반지름 (x, y)"""
        dz = (z - T.z) / BR[2]
        f = math.sqrt(max(0.0, 1 - dz * dz))
        return BR[0] * f + grow, BR[1] * f + grow

    def band(name, z, t, color, bone="torso", grow=0.0, **kw):
        rx, ry = ell(z, grow)
        ra = (rx + ry) / 2
        k.torus(name, (T.x, 0, z), 1.0, t / ra, color, bone, scale=(rx, ry, ra), seg=22, ring=6, **kw)

    # ---- 몸통: 플레이어 색 통 (겉옷) + 위 가슴 갑옷 껍데기 + 배 띠 + 허리띠·버클 + 목 칼라 + 가슴 금 장식 ----
    k.sphere("barrel", T, BR, WHITE, "torso", seg=22, rings=12, skin=True, blend=["torso", "waist", "hips"])
    k.shell("cuirass", T, (BR[0] + 0.035, BR[1] + 0.035, BR[2] + 0.03), STEEL, "torso",
            keep=lambda p: p.z > -0.05 and p.z < 0.97, thick=0.03, seg=22, rings=12)
    band("cuirass_rim", T.z - 0.03 * BR[2] - 0.005, 0.03, DARK, grow=0.045)
    band("belly_band", 0.86, 0.028, DARK, grow=0.01)
    band("belt", 0.72, 0.045, LEATHER, bone="waist", grow=0.02)
    bx, _ = ell(0.72, 0.06)
    k.rbox("buckle", (T.x + bx, 0, 0.72), (0.05, 0.11, 0.09), GOLD, "waist", bevel=0.3)
    k.torus("collar", (N.x - 0.01, 0, N.z - 0.03), 0.15, 0.045, DARK, "torso", seg=18, ring=6)
    cx, _ = ell(1.17, 0.035)
    k.cylinder("emblem", (T.x + cx + 0.005, 0, 1.17), 0.07, 0.03, GOLD, "torso", rot=(0, 90, 0), seg=16, bevel=0.008)

    # ---- 골반·다리: 가죽 바지 + 무릎 받이 + 정강이 갑옷 + 쇠 장화 + 허벅지 앞 판 ----
    k.sphere("pelvis", (0, 0, J("hips").z + 0.02), (0.25, 0.29, 0.15), LEATHER, "hips", seg=18, rings=10)

    def leg(side, sign):
        th, kn, ft = J("thigh_" + side), J("knee_" + side), J("foot_" + side)
        k.capsule("thigh_" + side, th, kn, 0.125, 0.11, LEATHER, "thigh_" + side, seg=12, rings=3,
                  blend=["thigh_" + side, "knee_" + side, "hips"])
        k.rbox("tasset_" + side, th + Vector((0.13, sign * 0.01, -0.03)), (0.05, 0.2, 0.2), STEEL, "thigh_" + side,
               rot=(0, -12, 0), bevel=0.35)
        k.sphere("knee_" + side, kn + Vector((0.03, 0, 0)), (0.1, 0.11, 0.1), STEEL, "knee_" + side, seg=14, rings=8)
        k.capsule("greave_" + side, kn + Vector((0, 0, -0.05)), ft + Vector((0, 0, 0.09)), 0.1, 0.115, STEEL,
                  "knee_" + side, seg=12, rings=3)
        k.rbox("boot_" + side, (ft.x + 0.06, ft.y, 0.085), (0.36, 0.22, 0.17), DARK, "foot_" + side, bevel=0.4)
        k.rbox("toe_" + side, (ft.x + 0.2, ft.y, 0.07), (0.1, 0.2, 0.1), STEEL, "foot_" + side, bevel=0.4)

    k.mirror(leg)

    # ---- 팔: 큰 어깨 갑옷 (두 겹) + 몸 색 소매 + 팔꿈치 받이 + 쇠 장갑 + 주먹 ----
    def arm(side, sign):
        sh, el, hd = J("shoulder_" + side), J("elbow_" + side), J("hand_" + side)
        fwd = (hd - el).normalized()
        k.shell("pauldron_" + side, sh + Vector((0, sign * 0.03, 0.06)), (0.19, 0.18, 0.16), STEEL, "shoulder_" + side,
                keep=lambda p: p.z > -0.2, thick=0.035, rot=(sign * 18, 0, 0), seg=18, rings=10)
        k.shell("lame_" + side, sh + Vector((0, sign * 0.06, -0.02)), (0.17, 0.16, 0.14), DARK, "shoulder_" + side,
                keep=lambda p: p.z > -0.25, thick=0.03, rot=(sign * 30, 0, 0), seg=16, rings=8)
        k.sphere("pauldron_stud_" + side, sh + Vector((0, sign * 0.13, 0.17)), (0.03, 0.03, 0.03), GOLD, "shoulder_" + side,
                 seg=8, rings=5)
        k.capsule("sleeve_" + side, sh, el, 0.095, 0.085, WHITE, "shoulder_" + side, seg=12, rings=3, skin=True,
                  blend=["shoulder_" + side, "elbow_" + side])
        k.sphere("elbow_" + side, el, (0.09, 0.09, 0.09), DARK, "elbow_" + side, seg=12, rings=7)
        k.capsule("gauntlet_" + side, el + fwd * 0.05, hd - fwd * 0.03, 0.09, 0.105, STEEL, "elbow_" + side, seg=12, rings=3)
        k.torus("cuff_" + side, hd - fwd * 0.06, 0.105, 0.025, DARK, "elbow_" + side, rot=_rot_to(fwd), seg=14, ring=5)
        k.rbox("fist_" + side, hd + fwd * 0.05, (0.15, 0.14, 0.15), DARK, "hand_" + side, rot=_rot_to(fwd), bevel=0.4)

    k.mirror(arm)

    # ---- 머리: 몸 색 얼굴 + 왕눈알 (JS addEyes 자리·크기) + 둥근 투구 (얼굴 앞만 뚫림) + 이마 띠 + 코 가드 + 몸 색 볏 ----
    k.capsule("neck", N + Vector((0, 0, -0.06)), N + Vector((0.01, 0, 0.08)), 0.085, 0.085, WHITE, "neck", seg=10, rings=2, skin=True)
    k.sphere("face", N + Vector((0.005, 0, 0.16)), (0.155, 0.16, 0.16), WHITE, "neck", seg=16, rings=10, skin=True)
    eye_r = 0.062 * k.rig["figure_scale"]
    for sign in (-1, 1):
        e = N + Vector((0.117, sign * 0.0805, 0.1615))
        k.sphere("eye_%d" % sign, e, (eye_r,) * 3, WHITE, "neck", seg=12, rings=8)
        k.sphere("pupil_%d" % sign, e + Vector((eye_r * 0.88, 0, 0)), (eye_r * 0.45,) * 3, PUPIL, "neck", seg=10, rings=6)
    hc = N + Vector((-0.01, 0, 0.19))
    HR = (0.2, 0.2, 0.185)
    # 얼굴 앞 (눈 높이 아래) 만 뚫고 볼·뒤통수까지 덮음
    k.shell("helmet", hc, HR, STEEL, "neck", keep=lambda p: p.z > -0.7 and not (p.x > 0.42 and p.z < 0.3) and not (p.x > 0.7 and p.z < 0.45),
            thick=0.028, seg=22, rings=12)
    k.torus("brow", hc + Vector((0, 0, HR[2] * 0.32)), 1.0, 0.024 / 0.18, DARK, "neck", scale=(HR[0] * 0.96 + 0.02, HR[1] * 0.96 + 0.02, 0.18), seg=20, ring=5)
    k.rbox("nose_guard", hc + Vector((HR[0] * 0.98, 0, -0.03)), (0.03, 0.026, 0.11), DARK, "neck", bevel=0.4)
    # 볏: 투구 꼭대기를 앞에서 뒤로 덮는 몸 색 덩어리 줄 (뒤로 갈수록 크게) + 금 받침
    k.rbox("crest_base", hc + Vector((0, 0, HR[2] + 0.01)), (0.2, 0.05, 0.04), GOLD, "neck", bevel=0.4)
    n = 6
    for i in range(n):
        a = math.radians(70 - i * 25)  # 앞 위 → 뒤 아래
        rr = HR[2] + 0.04 + 0.03 * math.sin(math.pi * i / (n - 1))
        p = hc + Vector((math.sin(a) * rr, 0, math.cos(a) * rr))
        s = 0.045 + 0.01 * i
        k.sphere("crest_%d" % i, p, (s * 1.1, 0.035, s), WHITE, "neck", rot=(0, math.degrees(a), 0), seg=10, rings=6, skin=True)

    # ---- 방패 (따로, prop="shield"): 안쪽 몸 방패 노드 좌표 (JS figure.js: 원판 면이 x 를 봄, 돌기 = -x, 크기 FIGURE_SCALE 은 부모에서) ----
    sr = max(0.28, k.rig["dims"]["chestR"] * 1.15)
    S = "shield"
    k.cylinder("shield_disk", (0, 0, 0), sr, 0.05, WHITE, "waist", rot=(0, 90, 0), seg=24, bevel=0.014, skin=True, prop=S)
    k.sphere("shield_dome", (-0.012, 0, 0), (0.04, sr * 0.86, sr * 0.86), WHITE, "waist", seg=20, rings=8, skin=True, prop=S)
    k.torus("shield_rim", (0, 0, 0), sr, 0.032, STEEL, "waist", rot=(0, 90, 0), seg=24, ring=6, prop=S)
    k.torus("shield_ring", (-0.035, 0, 0), sr * 0.36, 0.02, GOLD, "waist", rot=(0, 90, 0), seg=18, ring=5, prop=S)
    k.sphere("shield_boss", (-0.05, 0, 0), (0.065, 0.09, 0.09), GOLD, "waist", seg=14, rings=8, prop=S)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        k.sphere("shield_stud_%d" % i, (-0.03, math.cos(a) * sr * 0.68, math.sin(a) * sr * 0.68), (0.025, 0.03, 0.03), GOLD,
                 "waist", seg=8, rings=5, prop=S)
    k.rbox("shield_grip", (0.05, 0, 0), (0.04, 0.05, 0.22), LEATHER, "waist", bevel=0.4, prop=S)


# 미리보기에만: 방패를 등 자리에 (허리 뼈, 게임 자리·회전 = 고도 몸 shields.back — ref json props)
def _back():
    import json
    import os
    r = json.load(open(os.path.join(os.path.dirname(__file__), "..", "ref", "tank_rig.json")))
    w = Vector(r["joints"]["waist"]["pos"])
    sb = r["props"]["shield_back"]
    p = w + Vector(sb["pos"]) * r["figure_scale"]
    from mathutils import Quaternion
    q = Quaternion((sb["rot"][3], sb["rot"][0], sb["rot"][1], sb["rot"][2]))
    e = q.to_euler("XYZ")
    return ("waist", tuple(p), (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z)))


PREVIEW_PROPS = {"shield": _back()}
# 미리보기 자세: [(뼈, 게임 축, 도)] — 팔꿈치·무릎·어깨 극단 자세로 찌그러짐 확인
PREVIEW_POSES = {
    "punch": [("shoulder_R", (0, 1, 0), -95), ("shoulder_L", (0, 1, 0), -30), ("elbow_L", (0, 1, 0), -110),
              ("waist", (0, 0, 1), 25), ("thigh_R", (0, 1, 0), -35), ("knee_R", (0, 1, 0), 50)],
    "crouch": [("thigh_R", (0, 1, 0), -75), ("thigh_L", (0, 1, 0), -75), ("knee_R", (0, 1, 0), 115), ("knee_L", (0, 1, 0), 115),
               ("waist", (0, 1, 0), 30), ("shoulder_R", (0, 1, 0), -60), ("shoulder_L", (0, 1, 0), -60),
               ("elbow_R", (0, 1, 0), -90), ("elbow_L", (0, 1, 0), -90)],
    "extreme": [("shoulder_R", (1, 0, 0), -150), ("shoulder_L", (1, 0, 0), 150), ("elbow_R", (0, 1, 0), -140),
                ("elbow_L", (0, 1, 0), -140), ("thigh_R", (0, 1, 0), -110), ("knee_R", (0, 1, 0), 130),
                ("thigh_L", (0, 1, 0), 40), ("knee_L", (0, 1, 0), 90), ("waist", (0, 0, 1), -45), ("neck", (0, 0, 1), 40)],
    "slam": [("shoulder_R", (0, 1, 0), -170), ("shoulder_L", (0, 1, 0), -170), ("elbow_R", (0, 1, 0), -30),
             ("elbow_L", (0, 1, 0), -30), ("waist", (0, 1, 0), -20), ("neck", (0, 1, 0), -20)],
}
