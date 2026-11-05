# 탱크 (W19 고퀄 스타일화 — 스매시 레전드 급 목표): 귀엽고 든든한 중무장 방패병 아이.
# 치비 비율 (큰 머리 — 목·어깨 관절 자리는 그대로, 메시만 키움), 얼굴이 보이는 투구 + 플레이어 색 깃, 두툼한 곡면 갑옷 (흉갑·어깨·팔·정강이),
# 크림색 누빈 옷, 가죽 벨트·장갑, 금 테·리벳·가슴 별, 플레이어 색 허리 천 (앞·뒤) + 금 단, 큰 둥근 방패 (따로).
# 자리는 ref/tank_rig.json (고도 몸 쉬는 자세 관절, 게임 좌표 m). look 이름은 build_character.LOOKS (굽기 재질), tint = 플레이어 색 칸
import math
from mathutils import Vector

import build_character as B

B.look("steel", 0xb9c3cf, "metal", band=0.42, edge=0.38, hi=0xffffff)
B.look("steel_dark", 0x75808f, "metal", band=0.3, edge=0.3, hi=0xe8f0ff)
B.look("gold", 0xe9b440, "metal", band=0.5, edge=0.45, hi=0xfff2c0, ao_min=0.6)
B.look("leather", 0x8a5532, "leather", edge=0.12, hi=0xffd9b0)
B.look("leather_dark", 0x5a3520, "leather", edge=0.1, hi=0xd0a080)
B.look("cloth", 0xeee2c6, "cloth", edge=0.08, hi=0xffffff, ao_min=0.55)
B.look("skin", 0xf6cba8, "skin", edge=0.05, hi=0xffffff, ao_min=0.7)
B.look("hair", 0x7a4422, "cloth", edge=0.2, hi=0xffc890)
B.look("tint", 0xeeeeee, "tint", edge=0.12, hi=0xffffff, ao_min=0.55)
B.look("sole", 0x4a3a34, "leather", edge=0.05)

SHIELD_GLB = "res://assets/models/ext/tank_shield.glb"
# 고도 조정 값 (build_character.py 가 tank.json 으로). 방패: 안쪽 몸 방패 노드 (등 / 공격 동안 앞, 1인칭은 왼손) — 예전 그대로
CFG = {
    "attach": [
        {"glb": SHIELD_GLB, "ref": "shields.back", "vm": False},
        {"glb": SHIELD_GLB, "ref": "shields.front", "rot": [0, 0, 180], "vm": False},
        {"glb": SHIELD_GLB, "ref": "shields.front", "third": False},
    ],
    # 그림 살리기: 칠한 음영이 있으니 툰 단계를 부드럽게 + 얇은 외곽선 + 림 빛 (chars/chars_config.gd EXT_DEFAULTS 설명)
    "toon_steps": [0.66, 0.84, 1.0],
    "outline": 0.45,
    "rim": [0.35, 3.0],
}


def _rot_to(d):
    e = Vector((0, 0, 1)).rotation_difference(Vector(d).normalized()).to_euler("XYZ")
    return (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z))


def _on(c, r, d, out=0.0):
    """타원체 (가운데 c, 반지름 r) 겉면에서 방향 d 쪽 점 (+ out 만큼 밖으로)"""
    d = Vector(d).normalized()
    t = 1.0 / math.sqrt((d.x / r[0]) ** 2 + (d.y / r[1]) ** 2 + (d.z / r[2]) ** 2)
    return Vector(c) + d * (t + out)


def build(k):
    J = k.j
    T = J("torso")
    N = J("neck")
    H = J("hips")

    # ===== 머리 (치비: 크게) =====
    hc = N + Vector((0.035, 0, 0.255))  # 머리 가운데
    HR = (0.245, 0.27, 0.245)
    k.face_frame = (hc.copy(), HR[1], HR[2])  # 얼굴 텍스처 투영 (build_character.face_uv)
    k.blob("face", hc, HR, "skin", "neck", cuts=2, face=True)
    # 투구: 얼굴창 (이마 아래 앞이 열림, 볼 가리개는 옆에), 뒤통수·목 뒤 덮개
    HH = (HR[0] + 0.045, HR[1] + 0.045, HR[2] + 0.045)

    def helm_keep(p):
        if p.z < -0.62:
            return False
        if p.x > 0.18 and p.z < 0.46 and abs(p.y) < 0.72:
            return False  # 얼굴창
        if p.x > 0.5 and p.z < -0.3:
            return False  # 턱 아래
        return True
    k.shell("helmet", hc + Vector((-0.01, 0, 0.0)), HH, "steel", "neck", helm_keep, thick=0.04, cuts=3)
    # 이마 띠 (금) — 얼굴창 위 테
    bz = 0.46 * HH[2]
    bw = math.sqrt(max(0.0, 1 - 0.46 ** 2))
    k.torus("brow_band", hc + Vector((-0.01, 0, bz)), 1.0, 0.026, "gold", "neck", scale=(HH[0] * bw + 0.012, HH[1] * bw + 0.012, 1.0),
            seg=20, ring=6, sub=1)
    # 볼 가리개 리벳
    for s in (-1, 1):
        for zz in (-0.02, -0.12):
            p = _on(hc, HH, (0.45, s * 1.0, zz / HH[2]), 0.0)
            k.blob("cheek_rivet_%d_%d" % (s, int(zz * 100)), p, (0.022, 0.016, 0.022), "gold", "neck", cuts=0, sub=1)
    # 투구 위 마루 (쇠) + 깃 (플레이어 색, 굵고 부드럽게 뒤로 넘어감)
    crest_pts, plume_pts, plume_r, crest_r = [], [], [], []
    for i in range(7):
        a = math.radians(55 - i * 28)
        r0 = HH[2] + 0.005
        crest_pts.append(hc + Vector((math.sin(a) * r0 * 0.98, 0, math.cos(a) * r0)))
        crest_r.append((0.03, 0.03))
        r1 = HH[2] + 0.075 + 0.04 * math.sin(math.pi * i / 6)
        plume_pts.append(hc + Vector((math.sin(a) * r1 * 0.98, 0, math.cos(a) * r1)))
        t = i / 6
        plume_r.append((0.045 + 0.025 * math.sin(math.pi * t), 0.075 + 0.045 * math.sin(math.pi * min(1, t * 1.2))))
    k.sweep("crest", crest_pts[:6], crest_r[:6], "steel_dark", "neck", sides=6, up=(1, 0, 0), sub=1)
    k.sweep("plume", plume_pts, plume_r, "tint", "neck", sides=8, up=(0, 1, 0))
    # 앞머리 (투구 아래로 삐져나온 머리칼 세 갈래)
    for i, (dy, sz) in enumerate(((-0.13, 0.05), (-0.04, 0.06), (0.06, 0.055), (0.14, 0.045))):
        p = _on(hc, HR, (0.75, dy / HR[1], 0.42), -0.012)
        k.blob("bang_%d" % i, p, (0.035, sz, 0.045), "hair", "neck", rot=(0, 20, -dy * 140), cuts=1)

    # ===== 몸통 =====
    BR = (0.30, 0.345, 0.40)
    k.blob("tunic", T + Vector((0, 0, -0.02)), BR, "cloth", "torso", cuts=2, blend=["torso", "waist", "hips"])
    # 흉갑: 가슴·등 윗부분, 아래 가장자리 금 테
    PR = (BR[0] + 0.045, BR[1] + 0.04, BR[2] + 0.02)
    pc = T + Vector((0.005, 0, 0.03))
    k.shell("breastplate", pc, PR, "steel", "torso", lambda p: p.z > -0.6, thick=0.045, cuts=3)
    zt = -0.6 * PR[2] * 1.06
    tw = math.sqrt(1 - 0.6 ** 2) * 1.04
    k.torus("plate_trim", pc + Vector((0, 0, zt + 0.004)), 1.0, 0.024, "gold", "torso", scale=(PR[0] * tw + 0.01, PR[1] * tw + 0.01, 1.0), seg=24, ring=6, sub=1)
    # 가슴 별 (금) + 리벳
    k.star("chest_star", pc + Vector((PR[0] * 0.93, 0, 0.13)), 0.1, 0.03, "gold", "torso", rot=(0, 72, 0))
    for s in (-1, 1):
        for zz in (0.27, 0.0):
            a = math.radians(38 if zz > 0 else 50)
            p = _on(pc, PR, (math.cos(a), s * math.sin(a), zz / PR[2]), -0.004)
            k.blob("plate_rivet_%d_%d" % (s, int(zz * 100)), p, (0.018, 0.018, 0.018), "steel_dark", "torso", cuts=0, sub=1)
    # 목 받이 (고르짓)
    k.torus("gorget", N + Vector((0.0, 0, -0.03)), 0.165, 0.05, "steel", "torso", scale=(1.0, 1.08, 0.9), seg=16, ring=6)
    # 벨트 + 금 버클 + 주머니
    zb = 0.72
    k.torus("belt", Vector((H.x + 0.01, 0, zb)), 1.0, 0.045, "leather", "waist", scale=(0.265, 0.3, 1.0), seg=20, ring=6, sub=1)
    k.rbox("buckle", (0.285, 0, zb), (0.04, 0.12, 0.1), "gold", "waist", round_=0.5, sub=1)
    k.rbox("buckle_in", (0.3, 0, zb), (0.02, 0.06, 0.05), "leather_dark", "waist", round_=0.5, sub=1)
    k.rbox("pouch", (0.06, 0.29, zb - 0.06), (0.12, 0.07, 0.12), "leather", "waist", rot=(0, 0, 15), round_=0.6)
    # 허리 천 (플레이어 색) 앞·뒤 + 금 단
    TAB_TOP, TAB_LEN, TAB_W = 0.7, 0.32, 1.3
    for nm, ang in (("front", 0.0), ("back", math.pi)):
        k.panel("tabard_" + nm, (H.x, 0), TAB_TOP, TAB_LEN, 0.26, 0.32, ang, TAB_W, "tint", "hips", depth=0.92, thick=0.03,
                seg=4, rows=3, round_bottom=0.06, blend=["hips", "thigh_R", "thigh_L"])
        zb2 = TAB_TOP - TAB_LEN + 0.012
        k.torus("tabard_hem_" + nm, Vector((H.x, 0, zb2)), 1.0, 0.018, "gold", "hips", scale=(0.32 * 0.92 + 0.012, 0.32 + 0.012, 1.0),
                seg=8, ring=5, arc=(ang - TAB_W / 2 + 0.1, ang + TAB_W / 2 - 0.1), sub=1, blend=["hips", "thigh_R", "thigh_L"])
    # 옆 치마판 (쇠 두 겹 + 리벳)
    for side, a in (("R", -math.pi / 2), ("L", math.pi / 2)):
        for i, lk in enumerate(("steel", "steel_dark")):
            k.panel("tasset_%s%d" % (side, i), (H.x, 0), 0.69 - i * 0.07, 0.12, 0.27 + i * 0.03, 0.34 + i * 0.03, a, 1.35, lk, "hips",
                    depth=0.92, thick=0.028, seg=4, rows=1, blend=["hips", "thigh_" + side])
        k.blob("tasset_rivet_" + side, (H.x, math.sin(a) * 0.29, 0.66), (0.018, 0.016, 0.018), "gold", "hips", cuts=0, sub=1)

    # ===== 다리 (짧고 통통) =====
    k.blob("pelvis", (0, 0, H.z + 0.02), (0.23, 0.27, 0.14), "cloth", "hips", cuts=1)

    def leg(side, sign):
        th, kn, ft = J("thigh_" + side), J("knee_" + side), J("foot_" + side)
        mid = (th + kn) / 2
        k.sweep("thigh_" + side, [th + Vector((0, 0, 0.04)), mid, kn], [(0.125, 0.125), (0.135, 0.13), (0.11, 0.11)], "cloth", "thigh_" + side,
                sides=8, blend=["thigh_" + side, "knee_" + side, "hips"])
        k.blob("knee_" + side, kn + Vector((0.045, 0, 0.0)), (0.075, 0.1, 0.09), "steel", "knee_" + side, cuts=1)
        k.blob("knee_rivet_" + side, kn + Vector((0.118, 0, 0.0)), (0.018, 0.02, 0.02), "gold", "knee_" + side, cuts=0, sub=1)
        ank = ft + Vector((0, 0, 0.1))
        k.sweep("greave_" + side, [kn + Vector((0, 0, -0.04)), (kn + ank) / 2, ank], [(0.1, 0.105), (0.112, 0.115), (0.12, 0.12)], "steel", "knee_" + side, sides=8)
        k.torus("boot_cuff_" + side, ank + Vector((0, 0, -0.005)), 0.12, 0.035, "leather", "foot_" + side, seg=12, ring=5, sub=1)
        k.rbox("boot_" + side, (ft.x + 0.055, ft.y, 0.085), (0.32, 0.21, 0.15), "steel", "foot_" + side, round_=0.8)
        k.rbox("toecap_" + side, (ft.x + 0.17, ft.y, 0.08), (0.12, 0.19, 0.12), "steel_dark", "foot_" + side, round_=0.8, sub=1)
        k.rbox("sole_" + side, (ft.x + 0.055, ft.y, 0.022), (0.33, 0.22, 0.045), "sole", "foot_" + side, round_=0.6, sub=1)

    k.mirror(leg)

    # ===== 팔 =====
    def arm(side, sign):
        sh, el, hd = J("shoulder_" + side), J("elbow_" + side), J("hand_" + side)
        fwd = (hd - el).normalized()
        up = (el - sh).normalized()
        # 어깨 갑옷: 큰 둥근 판 두 겹 + 금 테 + 리벳
        pc = sh + Vector((0.0, sign * 0.045, 0.055))
        k.shell("pauldron_" + side, pc, (0.2, 0.19, 0.17), "steel", "shoulder_" + side, lambda p: p.z > -0.25, thick=0.04,
                rot=(sign * 22, 0, 0), cuts=2)
        k.shell("lame_" + side, pc + Vector((0, sign * 0.03, -0.07)), (0.185, 0.175, 0.15), "steel_dark", "shoulder_" + side,
                lambda p: p.z > -0.3 and p.z < 0.55, thick=0.035, rot=(sign * 32, 0, 0), cuts=2)
        for i, d in enumerate(((0.55, sign * 0.35, 0.75), (-0.55, sign * 0.35, 0.75), (0.0, sign * 0.75, 0.62))):
            p = _on(pc, (0.2, 0.19, 0.17), d, 0.0)
            k.blob("paul_rivet_%s%d" % (side, i), p, (0.02, 0.02, 0.02), "gold", "shoulder_" + side, cuts=0, sub=1)
        # 누빈 소매 (크림, 가운데가 불룩)
        k.sweep("sleeve_" + side, [sh + up * 0.02, (sh + el) / 2, el], [(0.1, 0.1), (0.112, 0.112), (0.095, 0.095)], "cloth", "shoulder_" + side,
                sides=8, blend=["shoulder_" + side, "elbow_" + side])
        k.blob("elbow_" + side, el - fwd * 0.005, (0.085, 0.085, 0.085), "steel_dark", "elbow_" + side, cuts=1)
        # 팔 보호대 (아래로 넓어짐) + 손목 금 테
        wr = hd - fwd * 0.05
        k.sweep("bracer_" + side, [el + fwd * 0.04, (el + wr) / 2, wr], [(0.088, 0.088), (0.1, 0.1), (0.118, 0.118)], "steel", "elbow_" + side, sides=8)
        k.torus("wrist_" + side, wr + fwd * 0.005, 0.1, 0.02, "gold", "elbow_" + side, rot=_rot_to(fwd), seg=14, ring=5, sub=1)
        # 둥근 장갑 손 (주먹) + 엄지
        hcn = hd + fwd * 0.045
        k.blob("fist_" + side, hcn, (0.095, 0.095, 0.1), "leather", "hand_" + side, rot=_rot_to(fwd), cuts=1)
        k.blob("thumb_" + side, hcn + Vector((0.06, -sign * 0.02, 0.02)), (0.035, 0.03, 0.04), "leather", "hand_" + side, cuts=0)

    k.mirror(arm)

    # ===== 방패 (따로, prop="shield"): 안쪽 몸 방패 노드 좌표 (원판 면이 +x 를 봄, 돌기 = -x, FIGURE_SCALE 은 부모에서) =====
    sr = max(0.3, k.rig["dims"]["chestR"] * 1.2)
    S = "shield"
    k.disk("shield_face", (0, 0, 0), sr, 0.06, "tint", "waist", rot=(0, 90, 0), seg=20, edge=0.3, prop=S)
    k.torus("shield_rim", (0, 0, 0), sr, 0.035, "steel", "waist", rot=(0, 90, 0), seg=24, ring=6, prop=S, sub=1)
    k.torus("shield_ring", (-0.035, 0, 0), sr * 0.5, 0.022, "gold", "waist", rot=(0, 90, 0), seg=20, ring=5, prop=S, sub=1)
    k.blob("shield_boss", (-0.05, 0, 0), (0.06, 0.105, 0.105), "gold", "waist", cuts=1, prop=S)
    k.star("shield_star", (-0.1, 0, 0), 0.06, 0.02, "steel", "waist", rot=(0, -90, 0), prop=S)
    for i in range(8):
        a = math.radians(22.5 + 45 * i)
        k.blob("shield_rivet_%d" % i, (-0.035, math.cos(a) * sr * 0.8, math.sin(a) * sr * 0.8), (0.018, 0.022, 0.022), "gold", "waist", cuts=0, prop=S, sub=1)
    # 뒤 손잡이 (가죽 고리) + 띠 두 줄
    k.sweep("shield_grip", [(0.04, 0, -0.1), (0.09, 0, -0.06), (0.09, 0, 0.06), (0.04, 0, 0.1)], [(0.022, 0.03)] * 4, "leather", "waist",
            sides=6, up=(1, 0, 0), prop=S, sub=1)
    for zz in (-0.16, 0.16):
        k.rbox("shield_strap_%d" % int(zz * 100), (0.035, 0, zz), (0.015, sr * 1.4, 0.05), "leather_dark", "waist", round_=0.5, prop=S, sub=1)


# 미리보기에만: 방패를 등 자리에 (허리 뼈, 고도 몸 shields.back — ref json props)
def _back():
    import json
    import os
    from mathutils import Quaternion
    r = json.load(open(os.path.join(os.path.dirname(__file__), "..", "ref", "tank_rig.json")))
    w = Vector(r["joints"]["waist"]["pos"])
    sb = r["props"]["shield_back"]
    p = w + Vector(sb["pos"]) * r["figure_scale"]
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
