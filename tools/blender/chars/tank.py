# 탱크 (W19 — 히어로 비율 고퀄 스타일화, 2026-11-05 재혁 확정: 치비 아님, 오버워치·브롤스타즈 식 6등신 전투원, 얼굴은 투구로 가림·눈만 작게).
# 중무장 방패병 어른 전사: 넓은 가슴·큰 어깨 갑옷·잘록한 허리·긴 다리, 닫힌 투구 (가로 눈 틈 + 세로 숨구멍, 안쪽 어둠에 빛나는 작은 눈),
# 플레이어 색 깃·허리 천·어깨띠·방패 판, 금 테·리벳, 큰 둥근 방패 (따로).
#
# 뼈 자리 (HERO): 우리 코드 몸 (ref/tank_rig.json, 다리 짧은 땅딸막 비율) 과 다름 — 같은 뼈 이름·같은 쉬는 방향 (팔 내림) 으로 길이만 다르게.
# 고도 external.gd 는 관절 '회전' 만 옮기고 뼈 길이·자리는 모델 것 (골반 높이는 root_k 배율) 이라 그대로 받음. 방패는 안쪽 몸 허리 노드 아래라
# 모델 허리가 올라간 만큼 attach "pos" 로 올림 (shield_pos — 방패 노드 축 기준).
import math
from mathutils import Vector, Quaternion

import build_character as B
import face_paint

B.look("steel", 0xb7c1cd, "metal", band=0.42, edge=0.38, hi=0xffffff)
B.look("steel_dark", 0x6f7988, "metal", band=0.3, edge=0.3, hi=0xe8f0ff)
B.look("gold", 0xe6b043, "metal", band=0.5, edge=0.45, hi=0xfff2c0, ao_min=0.6)
B.look("leather", 0x7f4c2c, "leather", edge=0.12, hi=0xffd9b0)
B.look("leather_dark", 0x52321e, "leather", edge=0.1, hi=0xd0a080)
B.look("cloth", 0x5a6478, "cloth", edge=0.08, hi=0xd0d8ff, ao_min=0.55)  # 사슬·누빈 속옷 (짙은 청회)
B.look("visor", 0x14161c, "cloth", edge=0.0, ao_min=1.0)
B.look("tint", 0xeeeeee, "tint", edge=0.12, hi=0xffffff, ao_min=0.55)
B.look("sole", 0x3e302a, "leather", edge=0.05)

# 히어로 비율 뼈 자리 (게임 좌표 m): 키 ~1.95 (깃 끝), 머리 ~0.33 → 6등신. 팔·다리 쉬는 방향은 코드 몸과 같게
HERO = {
    "hips": (0.0, 0.0, 0.93), "waist": (0.0, 0.0, 0.99), "torso": (0.015, 0.0, 1.25), "neck": (0.03, 0.0, 1.56),
    "shoulder_R": (0.02, -0.36, 1.47), "elbow_R": (0.008, -0.497, 1.17), "hand_R": (0.042, -0.627, 0.9),
    "thigh_R": (0.0, -0.145, 0.92), "knee_R": (0.022, -0.15, 0.515), "foot_R": (0.0, -0.15, 0.09),
}
for _k in list(HERO):
    if _k.endswith("_R"):
        x, y, z = HERO[_k]
        HERO[_k[:-2] + "_L"] = (x, -y, z)

SHIELD_GLB = "res://assets/models/ext/tank_shield.glb"


def _shield_pos(key):
    """방패 노드 (안쪽 몸 허리 아래, ref props) 축 기준으로 모델 허리 - 코드 허리 만큼 올림 (+ 앞 방패는 가슴이 두꺼운 만큼 앞으로)"""
    import json
    import os
    r = json.load(open(os.path.join(os.path.dirname(__file__), "..", "ref", "tank_rig.json")))
    sb = r["props"][key]
    q = Quaternion((sb["rot"][3], sb["rot"][0], sb["rot"][1], sb["rot"][2]))
    d = Vector(HERO["waist"]) - Vector(r["joints"]["waist"]["pos"])
    d += Vector((0.06 if key == "shield_front" else -0.05, 0, -0.06 if key == "shield_front" else -0.2))
    loc = q.inverted() @ d / sb["scale"][0]
    return [round(loc.x, 4), round(loc.y, 4), round(loc.z, 4)]


CFG = {
    "attach": [
        {"glb": SHIELD_GLB, "ref": "shields.back", "vm": False, "pos": _shield_pos("shield_back")},
        {"glb": SHIELD_GLB, "ref": "shields.front", "rot": [0, 0, 180], "vm": False, "pos": _shield_pos("shield_front")},
        {"glb": SHIELD_GLB, "ref": "shields.front", "third": False},
    ],
    "toon_steps": [0.66, 0.84, 1.0],
    "outline": 0.45,
    "rim": [0.35, 3.0],
    "face_glow": 0.9,  # 얼굴 (눈) 재질이 제 색으로 빛남 — 투구 안 어둠에서 눈이 보이게
}


def _rot_to(d):
    e = Vector((0, 0, 1)).rotation_difference(Vector(d).normalized()).to_euler("XYZ")
    return (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z))


def _on(c, r, d, out=0.0):
    d = Vector(d).normalized()
    t = 1.0 / math.sqrt((d.x / r[0]) ** 2 + (d.y / r[1]) ** 2 + (d.z / r[2]) ** 2)
    return Vector(c) + d * (t + out)


def build(k):
    for j, p in HERO.items():
        k.J[j] = Vector(p)
    k.face_painter = face_paint.paint_visor
    k.face_px = 256
    J = k.j
    T, N, H = J("torso"), J("neck"), J("hips")

    # ===== 머리: 닫힌 투구 (눈 틈 안쪽 어둠 = 얼굴 텍스처) =====
    hc = N + Vector((0.03, 0, 0.15))
    HR = (0.145, 0.14, 0.158)
    k.face_frame = (hc.copy(), HR[1], HR[2])
    k.blob("face", hc, HR, "visor", "neck", cuts=1, face=True)
    HH = (HR[0] + 0.035, HR[1] + 0.03, HR[2] + 0.03)
    slit_z = 0.04 / HH[2]

    def helm_keep(p):
        if p.z < -0.75 and p.x < 0.3:
            return False  # 목 아래 열림
        if p.x > 0.25 and abs(p.z - slit_z) < 0.11 and abs(p.y) < 0.62:
            return False  # 가로 눈 틈
        if p.x > 0.55 and p.z < slit_z - 0.1 and p.z > -0.55 and abs(p.y) < 0.09:
            return False  # 세로 숨 틈 (T 바이저)
        return True
    k.shell("helmet", hc, HH, "steel", "neck", helm_keep, thick=0.03, cuts=5)
    # 얼굴 가운데 세로 능선 (눈 틈 아래 → 턱) + 투구 아래 테 (어두운 쇠, 살짝 벌어짐)
    fr = [_on(hc, HH, (1.0, 0.0, zz), 0.002) for zz in (slit_z - 0.14, -0.3, -0.55, -0.72)]
    k.sweep("face_ridge", fr, [(0.016, 0.012)] * len(fr), "steel", "neck", sides=6, up=(1, 0, 0), sub=1)
    k.sweep("visor_ridge", [_on(hc, HH, (0.6, -0.8, slit_z + 0.14), 0.004), _on(hc, HH, (1.0, 0.0, slit_z + 0.15), 0.006),
                            _on(hc, HH, (0.6, 0.8, slit_z + 0.14), 0.004)], [(0.012, 0.016)] * 3, "steel", "neck", sides=6, up=(0, 0, 1), sub=1)
    k.torus("helm_rim", hc + Vector((-0.01, 0, -0.66 * HH[2])), 1.0, 0.018, "steel_dark", "neck", scale=(HH[0] * 0.78 + 0.01, HH[1] * 0.78 + 0.01, 1.0),
            seg=16, ring=5, sub=1)
    # 눈 틈 위 금 이마 테 (투구 앞 반 바퀴) + 볼 리벳 + 마루 + 깃
    bz = slit_z + 0.16
    bw = math.sqrt(max(0.0, 1 - bz ** 2))
    k.torus("brow_trim", hc + Vector((0, 0, bz * HH[2])), 1.0, 0.014, "gold", "neck", scale=(HH[0] * bw + 0.008, HH[1] * bw + 0.008, 1.0),
            seg=16, ring=5, arc=(-1.6, 1.6), sub=1)
    for s in (-1, 1):
        for zz in (-0.25, -0.5):
            k.blob("cheek_rivet_%d_%d" % (s, int(-zz * 10)), _on(hc, HH, (0.55, s * 0.75, zz)), (0.012, 0.012, 0.012), "gold", "neck", cuts=0, sub=1)
    crest_pts, plume_pts, plume_r = [], [], []
    for i in range(7):
        a = math.radians(50 - i * 30)
        crest_pts.append(hc + Vector((math.sin(a) * HH[0] * 1.0, 0, math.cos(a) * HH[2] * 1.0)))
        r1 = 0.05 + 0.03 * math.sin(math.pi * i / 6)
        plume_pts.append(hc + Vector((math.sin(a) * (HH[0] + r1), 0, math.cos(a) * (HH[2] + r1))))
        t = i / 6
        plume_r.append((0.03 + 0.018 * math.sin(math.pi * t), 0.05 + 0.04 * math.sin(math.pi * min(1, t * 1.2))))
    k.sweep("crest", crest_pts[:6], [(0.02, 0.02)] * 6, "steel_dark", "neck", sides=6, up=(1, 0, 0), sub=1)
    k.sweep("plume", plume_pts, plume_r, "tint", "neck", sides=8, up=(0, 1, 0))
    # 목 가리개 (사슬 + 쇠 고르짓)
    k.sweep("neck_mail", [N + Vector((0, 0, -0.06)), N + Vector((0.01, 0, 0.06))], [(0.075, 0.08)] * 2, "cloth", "neck", sides=8)
    k.torus("gorget", N + Vector((0.0, 0, -0.06)), 0.13, 0.04, "steel", "torso", scale=(1.0, 1.1, 1.0), seg=16, ring=6)

    # ===== 몸통: 넓은 가슴 (V), 잘록한 허리 =====
    k.blob("chest_core", T + Vector((0, 0, 0.02)), (0.2, 0.27, 0.27), "cloth", "torso", cuts=2, blend=["torso", "waist"])
    k.blob("belly_core", Vector((0.0, 0, 1.03)), (0.18, 0.23, 0.15), "cloth", "waist", cuts=1, blend=["waist", "hips", "torso"])
    PR = (0.225, 0.305, 0.26)
    pc = T + Vector((0.01, 0, 0.05))
    k.shell("breastplate", pc, PR, "steel", "torso", lambda p: p.z > -0.55, thick=0.04, cuts=3)
    zt = -0.55 * PR[2] * 1.06
    tw = math.sqrt(1 - 0.55 ** 2) * 1.03
    k.torus("plate_trim", pc + Vector((0, 0, zt + 0.004)), 1.0, 0.016, "gold", "torso", scale=(PR[0] * tw + 0.008, PR[1] * tw + 0.008, 1.0), seg=24, ring=5, sub=1)
    ridge = [_on(pc, PR, (1.0, 0.0, zz), 0.003) for zz in (0.6, 0.3, 0.0, -0.3, -0.5)]
    k.sweep("plate_ridge", ridge, [(0.012, 0.009)] * len(ridge), "steel", "torso", sides=6, up=(1, 0, 0), sub=1)
    k.star("chest_star", _on(pc, PR, (0.92, 0.38, 0.32), 0.003), 0.055, 0.02, "gold", "torso", rot=(0, 72, 24))
    for s in (-1, 1):
        for d in ((0.75, s * 0.62, 0.1), (0.6, s * 0.75, -0.35)):
            k.blob("plate_rivet_%d_%d" % (s, int(d[2] * 10)), _on(pc, PR, d, -0.003), (0.012, 0.012, 0.012), "steel_dark", "torso", cuts=0, sub=1)
    # 배 가리개 (겹친 쇠 띠 셋, 아래로 좁아짐)
    for i in range(3):
        z = 1.1 - i * 0.055
        rx, ry = 0.19 - i * 0.012, 0.235 - i * 0.012
        k.torus("fauld_%d" % i, Vector((0.012, 0, z)), 1.0, 0.03, "steel" if i % 2 == 0 else "steel_dark", "waist",
                scale=(rx, ry, 0.9), seg=20, ring=6, blend=["waist", "torso"] if i == 0 else None)
    # 어깨띠 (플레이어 색, 오른어깨 → 왼허리 사선) + 금 고리
    sash = [_on(pc, PR, (0.55, -0.6, 0.75), 0.012), _on(pc, PR, (0.95, -0.15, 0.25), 0.014), _on(pc, PR, (0.9, 0.35, -0.25), 0.014),
            _on(pc, PR, (0.55, 0.75, -0.5), 0.012)]
    k.sweep("sash", sash, [(0.045, 0.012)] * 4, "tint", "torso", sides=6, up=(1, 0, 0), sub=1)
    k.torus("sash_ring", _on(pc, PR, (0.95, -0.15, 0.25), 0.03), 0.028, 0.008, "gold", "torso", rot=(0, 75, 0), seg=10, ring=4, sub=1)
    # 벨트 + 금 버클 + 주머니
    zb = 0.975
    k.torus("belt", Vector((0.005, 0, zb)), 1.0, 0.032, "leather", "waist", scale=(0.195, 0.235, 1.0), seg=20, ring=6, sub=1)
    k.rbox("buckle", (0.205, 0, zb), (0.03, 0.085, 0.07), "gold", "waist", round_=0.5, sub=1)
    k.rbox("buckle_in", (0.217, 0, zb), (0.015, 0.042, 0.035), "leather_dark", "waist", round_=0.5, sub=1)
    k.rbox("pouch", (0.03, 0.22, zb - 0.05), (0.09, 0.05, 0.09), "leather", "waist", rot=(0, 0, 18), round_=0.6)
    # 허리 천 (플레이어 색) 앞·뒤 + 금 단
    TAB_TOP, TAB_LEN, TAB_W = 0.96, 0.36, 0.95
    for nm, ang in (("front", 0.0), ("back", math.pi)):
        k.panel("tabard_" + nm, (H.x, 0), TAB_TOP, TAB_LEN, 0.2, 0.25, ang, TAB_W, "tint", "hips", depth=0.85, thick=0.022,
                seg=4, rows=3, round_bottom=0.05, blend=["hips", "thigh_R", "thigh_L"])
        k.torus("tabard_hem_" + nm, Vector((H.x, 0, TAB_TOP - TAB_LEN + 0.01)), 1.0, 0.013, "gold", "hips",
                scale=(0.25 * 0.85 + 0.01, 0.25 + 0.01, 1.0), seg=8, ring=5, arc=(ang - TAB_W / 2 + 0.1, ang + TAB_W / 2 - 0.1), sub=1,
                blend=["hips", "thigh_R", "thigh_L"])
    # 옆 치마판 (쇠 두 겹 + 리벳)
    for side, a in (("R", -math.pi / 2), ("L", math.pi / 2)):
        for i, lk in enumerate(("steel", "steel_dark")):
            k.panel("tasset_%s%d" % (side, i), (H.x, 0), 0.95 - i * 0.075, 0.13, 0.21 + i * 0.022, 0.27 + i * 0.022, a, 1.25, lk, "hips",
                    depth=0.85, thick=0.022, seg=4, rows=1, blend=["hips", "thigh_" + side])
        k.blob("tasset_rivet_" + side, (H.x, math.sin(a) * 0.225, 0.915), (0.012, 0.012, 0.012), "gold", "hips", cuts=0, sub=1)

    # ===== 다리 (긴 다리, 단단한 정강이 갑옷) =====
    k.blob("pelvis", (0, 0, H.z + 0.01), (0.17, 0.24, 0.12), "cloth", "hips", cuts=1)

    def leg(side, sign):
        th, kn, ft = J("thigh_" + side), J("knee_" + side), J("foot_" + side)
        mid = th + (kn - th) * 0.45
        k.sweep("thigh_" + side, [th + Vector((0, 0, 0.03)), mid, kn], [(0.125, 0.125), (0.12, 0.12), (0.09, 0.095)], "cloth", "thigh_" + side,
                sides=8, blend=["thigh_" + side, "knee_" + side, "hips"])
        k.shell("cuisse_" + side, mid + Vector((0.02, 0, 0.02)), (0.125, 0.13, 0.2), "steel", "thigh_" + side, lambda p: p.x > -0.15, thick=0.022, cuts=2)
        k.blob("knee_" + side, kn + Vector((0.055, 0, 0.0)), (0.065, 0.09, 0.08), "steel", "knee_" + side, cuts=1)
        k.blob("knee_rivet_" + side, kn + Vector((0.113, 0, 0.0)), (0.013, 0.015, 0.015), "gold", "knee_" + side, cuts=0, sub=1)
        ank = ft + Vector((0, 0, 0.1))
        k.sweep("greave_" + side, [kn + Vector((0, 0, -0.04)), kn + (ank - kn) * 0.4, ank], [(0.09, 0.09), (0.1, 0.1), (0.088, 0.09)],
                "steel", "knee_" + side, sides=8)
        k.torus("boot_cuff_" + side, ank + Vector((0, 0, -0.005)), 0.09, 0.028, "leather", "foot_" + side, seg=12, ring=5, sub=1)
        k.rbox("boot_" + side, (ft.x + 0.05, ft.y, 0.085), (0.3, 0.16, 0.16), "steel", "foot_" + side, round_=0.75)
        k.rbox("toecap_" + side, (ft.x + 0.16, ft.y, 0.07), (0.1, 0.15, 0.11), "steel_dark", "foot_" + side, round_=0.8, sub=1)
        k.rbox("sole_" + side, (ft.x + 0.05, ft.y, 0.018), (0.31, 0.165, 0.036), "sole", "foot_" + side, round_=0.6, sub=1)

    k.mirror(leg)

    # ===== 팔 (굵고 긴 팔, 큰 어깨 갑옷) =====
    def arm(side, sign):
        sh, el, hd = J("shoulder_" + side), J("elbow_" + side), J("hand_" + side)
        fwd = (hd - el).normalized()
        pc2 = sh + Vector((0.0, sign * 0.04, 0.05))
        PRR = (0.15, 0.15, 0.13)
        k.shell("pauldron_" + side, pc2, PRR, "steel", "shoulder_" + side, lambda p: p.z > -0.3, thick=0.03, rot=(sign * 24, 0, 0), cuts=2)
        k.shell("lame_" + side, pc2 + Vector((0, sign * 0.025, -0.06)), (0.14, 0.14, 0.11), "steel_dark", "shoulder_" + side,
                lambda p: p.z > -0.3 and p.z < 0.6, thick=0.025, rot=(sign * 36, 0, 0), cuts=2)
        k.torus("paul_trim_" + side, pc2 + Vector((0, sign * 0.012, 0.0)), 1.0, 0.012, "gold", "shoulder_" + side,
                rot=(sign * 24, 0, 0), scale=(PRR[0] * 0.96 + 0.006, PRR[1] * 0.96 + 0.006, 1.0), seg=16, ring=4, sub=1)
        for i, d in enumerate(((0.5, sign * 0.3, 0.8), (-0.5, sign * 0.3, 0.8), (0.0, sign * 0.7, 0.68))):
            k.blob("paul_rivet_%s%d" % (side, i), _on(pc2, PRR, d, 0.0), (0.014, 0.014, 0.014), "gold", "shoulder_" + side, cuts=0, sub=1)
        k.sweep("sleeve_" + side, [sh, (sh + el) / 2, el], [(0.095, 0.095), (0.1, 0.1), (0.085, 0.085)], "cloth", "shoulder_" + side,
                sides=8, blend=["shoulder_" + side, "elbow_" + side])
        k.shell("rerebrace_" + side, (sh + el) / 2 + Vector((0.0, sign * 0.015, -0.02)), (0.105, 0.105, 0.13), "steel", "shoulder_" + side,
                lambda p: p.y * sign > -0.3, thick=0.018, rot=_rot_to(el - sh), cuts=2)
        k.blob("elbow_" + side, el - fwd * 0.005, (0.08, 0.08, 0.08), "steel_dark", "elbow_" + side, cuts=1)
        wr = hd - fwd * 0.04
        k.sweep("bracer_" + side, [el + fwd * 0.035, (el + wr) / 2, wr], [(0.085, 0.085), (0.095, 0.095), (0.105, 0.105)], "steel", "elbow_" + side, sides=8)
        k.torus("wrist_" + side, wr + fwd * 0.005, 0.09, 0.016, "gold", "elbow_" + side, rot=_rot_to(fwd), seg=14, ring=5, sub=1)
        hcn = hd + fwd * 0.035
        k.blob("fist_" + side, hcn, (0.075, 0.075, 0.085), "leather", "hand_" + side, rot=_rot_to(fwd), cuts=1)
        k.rbox("knuckle_" + side, hcn + fwd * 0.03 + Vector((0.035, 0, 0)), (0.05, 0.11, 0.07), "steel_dark", "hand_" + side,
               rot=_rot_to(fwd), round_=0.7, sub=1)
        k.blob("thumb_" + side, hcn + Vector((0.045, -sign * 0.02, 0.02)), (0.025, 0.022, 0.03), "leather", "hand_" + side, cuts=0)

    k.mirror(arm)

    # ===== 방패 (따로, prop="shield"): 안쪽 몸 방패 노드 좌표 (원판 면이 +x, 돌기 = -x, FIGURE_SCALE 은 부모에서) =====
    sr = max(0.3, k.rig["dims"]["chestR"] * 1.2)
    S = "shield"
    k.disk("shield_face", (0, 0, 0), sr, 0.055, "tint", "waist", rot=(0, 90, 0), seg=20, edge=0.3, prop=S)
    k.torus("shield_rim", (0, 0, 0), sr, 0.03, "steel", "waist", rot=(0, 90, 0), seg=24, ring=6, prop=S, sub=1)
    k.torus("shield_ring", (-0.033, 0, 0), sr * 0.52, 0.018, "gold", "waist", rot=(0, 90, 0), seg=20, ring=5, prop=S, sub=1)
    k.blob("shield_boss", (-0.045, 0, 0), (0.05, 0.095, 0.095), "gold", "waist", cuts=1, prop=S)
    k.star("shield_star", (-0.09, 0, 0), 0.05, 0.018, "steel", "waist", rot=(0, -90, 0), prop=S)
    for i in range(8):
        a = math.radians(22.5 + 45 * i)
        k.blob("shield_rivet_%d" % i, (-0.032, math.cos(a) * sr * 0.8, math.sin(a) * sr * 0.8), (0.015, 0.018, 0.018), "gold", "waist", cuts=0, prop=S, sub=1)
    k.sweep("shield_grip", [(0.04, 0, -0.1), (0.09, 0, -0.06), (0.09, 0, 0.06), (0.04, 0, 0.1)], [(0.02, 0.028)] * 4, "leather", "waist",
            sides=6, up=(1, 0, 0), prop=S, sub=1)
    for zz in (-0.16, 0.16):
        k.rbox("shield_strap_%d" % int(zz * 100), (0.035, 0, zz), (0.015, sr * 1.4, 0.045), "leather_dark", "waist", round_=0.5, prop=S, sub=1)


# 미리보기에만: 방패를 등에 (모델 허리 기준 — 게임에서 attach pos 로 올린 자리와 같게)
def _back():
    import json
    import os
    r = json.load(open(os.path.join(os.path.dirname(__file__), "..", "ref", "tank_rig.json")))
    sb = r["props"]["shield_back"]
    p = Vector(HERO["waist"]) + Vector(sb["pos"]) * r["figure_scale"] + Vector((-0.05, 0, -0.2))
    q = Quaternion((sb["rot"][3], sb["rot"][0], sb["rot"][1], sb["rot"][2]))
    e = q.to_euler("XYZ")
    return ("waist", tuple(p), (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z)))


PREVIEW_PROPS = {"shield": _back()}
PREVIEW_POSES = {
    "punch": [("shoulder_R", (0, 1, 0), -95), ("shoulder_L", (0, 1, 0), -30), ("elbow_L", (0, 1, 0), -110),
              ("waist", (0, 0, 1), 25), ("thigh_R", (0, 1, 0), -35), ("knee_R", (0, 1, 0), 50)],
    "crouch": [("thigh_R", (0, 1, 0), -75), ("thigh_L", (0, 1, 0), -75), ("knee_R", (0, 1, 0), 115), ("knee_L", (0, 1, 0), 115),
               ("waist", (0, 1, 0), 30), ("shoulder_R", (0, 1, 0), -60), ("shoulder_L", (0, 1, 0), -60),
               ("elbow_R", (0, 1, 0), -90), ("elbow_L", (0, 1, 0), -90)],
    "slam": [("shoulder_R", (0, 1, 0), -170), ("shoulder_L", (0, 1, 0), -170), ("elbow_R", (0, 1, 0), -30),
             ("elbow_L", (0, 1, 0), -30), ("waist", (0, 1, 0), -20), ("neck", (0, 1, 0), -20)],
}
