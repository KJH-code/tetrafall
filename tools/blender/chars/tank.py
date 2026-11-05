# 탱크 (W19 v2 — 2026-11-05 재혁 레퍼런스: 둥글둥글 금지, '디테일로 각진' 하드서피스 중무장 기사).
# 덩치 큰 역삼각형 6등신 어른 전사: 매우 넓은 어깨 + 3겹 어깨 갑옷, 두꺼운 면진 흉갑 (능선·패널 라인·금 테·돋을새김 별), 큰 장갑 주먹,
# 판이 겹친 팔·허벅지, 큼직한 정강이 갑옷·육중한 장화. 닫힌 투구 (가로 눈 틈 + 세로 슬릿 十, 옆 지느러미, 정수리 능선 + 깃, 금 이마 테) 안 어둠에 작은 빛나는 눈.
# 플레이어 색 (부분 틴트): 깃·허리 천 (방패꼴)·뒤 천·어깨 갑옷 안감·무릎 보석·방패 판 — 위에서 봐도 색으로 구분.
# 모양 함수는 build_character.Kit (HARD = 서브디비전 대신 각진 면 + 작은 베벨, 평면 음영). 뼈 자리는 HERO (회전만 코드 몸에서 옮김 — README 3절).
import math
from mathutils import Vector, Quaternion

import build_character as B
import face_paint

HARD = True
SUB = 0

B.look("steel", 0xbcc5d0, "metal", band=0.4, edge=0.55, hi=0xffffff, edge_from=0.5, edge_to=0.56)
B.look("steel_dark", 0x5f6878, "metal", band=0.28, edge=0.45, hi=0xe8f0ff, edge_from=0.5, edge_to=0.56)
B.look("gold", 0xe3ad3e, "metal", band=0.5, edge=0.6, hi=0xfff4c8, ao_min=0.6, edge_from=0.5, edge_to=0.56)
B.look("leather", 0x7a4a2b, "leather", edge=0.2, hi=0xffd9b0)
B.look("leather_dark", 0x4c2f1d, "leather", edge=0.15, hi=0xd0a080)
B.look("cloth", 0x3e4656, "cloth", edge=0.12, hi=0xc0c8ff, ao_min=0.55)  # 어두운 관절 틈 (사슬·속옷)
B.look("visor", 0x14161c, "cloth", edge=0.0, ao_min=1.0)
B.look("tint", 0xeeeeee, "tint", edge=0.25, hi=0xffffff, ao_min=0.55, edge_from=0.5, edge_to=0.56)
B.look("sole", 0x3a2c26, "leather", edge=0.08)

HERO = {
    "hips": (0.0, 0.0, 0.93), "waist": (0.0, 0.0, 0.99), "torso": (0.015, 0.0, 1.25), "neck": (0.03, 0.0, 1.57),
    "shoulder_R": (0.02, -0.4, 1.47), "elbow_R": (0.008, -0.537, 1.17), "hand_R": (0.042, -0.667, 0.9),
    "thigh_R": (0.0, -0.15, 0.92), "knee_R": (0.022, -0.155, 0.515), "foot_R": (0.0, -0.155, 0.09),
}
for _k in list(HERO):
    if _k.endswith("_R"):
        x, y, z = HERO[_k]
        HERO[_k[:-2] + "_L"] = (x, -y, z)

SHIELD_GLB = "res://assets/models/ext/tank_shield.glb"


def _shield_pos(key):
    """방패 노드 (안쪽 몸 허리 아래) 축 기준: 모델 허리 - 코드 허리 만큼 올림 (+ 앞 방패는 가슴이 두꺼운 만큼 앞으로, 등 방패는 등 뒤로)"""
    import json
    import os
    r = json.load(open(os.path.join(os.path.dirname(__file__), "..", "ref", "tank_rig.json")))
    sb = r["props"][key]
    q = Quaternion((sb["rot"][3], sb["rot"][0], sb["rot"][1], sb["rot"][2]))
    d = Vector(HERO["waist"]) - Vector(r["joints"]["waist"]["pos"])
    d += Vector((0.09 if key == "shield_front" else -0.09, 0, -0.06 if key == "shield_front" else -0.17))
    loc = q.inverted() @ d / sb["scale"][0]
    return [round(loc.x, 4), round(loc.y, 4), round(loc.z, 4)]


CFG = {
    "attach": [
        {"glb": SHIELD_GLB, "ref": "shields.back", "vm": False, "pos": _shield_pos("shield_back")},
        {"glb": SHIELD_GLB, "ref": "shields.front", "rot": [0, 0, 180], "vm": False, "pos": _shield_pos("shield_front")},
        {"glb": SHIELD_GLB, "ref": "shields.front", "third": False},
    ],
    "toon_steps": [0.7, 0.86, 1.0],
    "outline": 0.45,
    "rim": [0.3, 3.0],
    "face_glow": 0.9,
}


def _rot_to(d):
    e = Vector((0, 0, 1)).rotation_difference(Vector(d).normalized()).to_euler("XYZ")
    return (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z))


def _on(c, r, d, out=0.0):
    d = Vector(d).normalized()
    t = 1.0 / math.sqrt((d.x / r[0]) ** 2 + (d.y / r[1]) ** 2 + (d.z / r[2]) ** 2)
    return Vector(c) + d * (t + out)


RIV = dict(cuts=0, sub=1)  # 리벳: 작은 둥근 머리


def build(k):
    for j, p in HERO.items():
        k.J[j] = Vector(p)
    k.face_painter = face_paint.paint_visor
    k.face_px = 256
    J = k.j
    T, N, H = J("torso"), J("neck"), J("hips")

    # ===== 투구 (닫힌 면진 투구, 十 슬릿, 옆 지느러미, 정수리 능선 + 깃) =====
    hc = N + Vector((0.035, 0, 0.155))
    HR = (0.14, 0.135, 0.15)
    k.face_frame = (hc.copy(), HR[1], HR[2])
    k.blob("face", hc, HR, "visor", "neck", cuts=1, face=True, bevel=0)
    HH = (HR[0] + 0.045, HR[1] + 0.035, HR[2] + 0.035)
    slit_z = 0.012 / HH[2]

    def helm_keep(p):
        if p.z < -0.78 and p.x < 0.35:
            return False
        if p.x > 0.3 and abs(p.z - slit_z) < 0.075 and abs(p.y) < 0.6:
            return False  # 가로 눈 틈
        if p.x > 0.6 and p.z < slit_z and p.z > -0.5 and abs(p.y) < 0.07:
            return False  # 세로 슬릿 (十)
        return True
    k.shell("helmet", hc, HH, "steel", "neck", helm_keep, thick=0.03, cuts=4)
    # 정수리 능선 (앞→뒤, 높은 칼날) + 깃 (플레이어 색, 뒤로 넘어가는 넓은 날)
    crest, plume, pr = [], [], []
    for i in range(6):
        a = math.radians(60 - i * 30)
        crest.append(hc + Vector((math.sin(a) * (HH[0] + 0.005), 0, math.cos(a) * (HH[2] + 0.005))))
        r1 = 0.05 + 0.035 * math.sin(math.pi * i / 5)
        plume.append(hc + Vector((math.sin(a) * (HH[0] + r1), 0, math.cos(a) * (HH[2] + r1))))
        pr.append((0.022 + 0.01 * math.sin(math.pi * i / 5), 0.045 + 0.04 * math.sin(math.pi * min(1, i / 4))))
    k.sweep("crest", crest, [(0.016, 0.035)] * 6, "gold", "neck", sides=4, up=(1, 0, 0))
    k.sweep("plume", plume, pr, "tint", "neck", sides=6, up=(0, 1, 0))
    # 옆 지느러미 (관자놀이에서 뒤·위로 뻗은 날개꼴 판)
    for s in (-1, 1):
        base = _on(hc, HH, (0.15, s * 1.0, 0.15))
        k.sweep("fin_%d" % s, [base + Vector((0.03, 0, 0)), base + Vector((-0.08, s * 0.05, 0.04)), base + Vector((-0.2, s * 0.075, 0.1))],
                [(0.014, 0.075), (0.011, 0.06), (0.006, 0.022)], "steel", "neck", sides=4, up=(0.3, 0, 1))
        k.sweep("fin_trim_%d" % s, [base + Vector((0.03, s * 0.01, 0.07)), base + Vector((-0.08, s * 0.062, 0.1)), base + Vector((-0.2, s * 0.083, 0.122))],
                [(0.008, 0.01)] * 3, "gold", "neck", sides=4, up=(0.3, 0, 1))
    # 금 이마 테 (눈 틈 위 반 바퀴, 면진 고리) + 얼굴 능선·볼 리벳 + 아래 테
    bz = slit_z + 0.17
    bw = math.sqrt(max(0.0, 1 - bz ** 2))
    k.torus("brow_trim", hc + Vector((0, 0, bz * HH[2])), 1.0, 0.016, "gold", "neck", scale=(HH[0] * bw + 0.006, HH[1] * bw + 0.006, 1.0),
            seg=12, ring=4, arc=(-1.7, 1.7))
    fr = [_on(hc, HH, (1.0, 0.0, zz), 0.004) for zz in (slit_z + 0.13, 0.55, 0.85)]
    k.sweep("brow_ridge", fr, [(0.012, 0.016)] * 3, "steel", "neck", sides=4, up=(1, 0, 0))
    for s in (-1, 1):
        for zz in (-0.2, -0.45):
            k.blob("cheek_rivet_%d_%d" % (s, int(-zz * 100)), _on(hc, HH, (0.6, s * 0.7, zz)), (0.011, 0.011, 0.011), "gold", "neck", **RIV)
        for i in range(3):  # 숨구멍 (어두운 점)
            k.blob("vent_%d_%d" % (s, i), _on(hc, HH, (0.8, s * (0.25 + i * 0.1), -0.45 - i * 0.05), -0.002), (0.008, 0.008, 0.008), "visor", "neck", **RIV)
    k.torus("helm_rim", hc + Vector((-0.012, 0, -0.7 * HH[2])), 1.0, 0.02, "steel_dark", "neck", scale=(HH[0] * 0.74 + 0.012, HH[1] * 0.74 + 0.012, 1.0),
            seg=12, ring=4)
    k.torus("gorget", N + Vector((0.0, 0, -0.07)), 0.15, 0.045, "steel", "torso", scale=(1.0, 1.12, 1.0), seg=10, ring=4)

    # ===== 몸통 (두꺼운 면진 흉갑, 역삼각형) =====
    k.blob("chest_core", T + Vector((0, 0, 0.02)), (0.22, 0.3, 0.28), "cloth", "torso", cuts=1, blend=["torso", "waist"])
    k.blob("belly_core", Vector((0.0, 0, 1.03)), (0.17, 0.22, 0.16), "cloth", "waist", cuts=1, blend=["waist", "hips", "torso"])
    PR = (0.255, 0.345, 0.29)
    pc = T + Vector((0.015, 0, 0.06))
    k.shell("breastplate", pc, PR, "steel", "torso", lambda p: p.z > -0.58, thick=0.045, cuts=2)
    # 가슴 위 덧판 (두 겹 — 패널 라인), 가운데 능선, 아래 금 테, 돋을새김 별 (금)
    k.shell("chest_upper", pc + Vector((0.012, 0, 0.02)), (PR[0] + 0.012, PR[1] + 0.01, PR[2]), "steel", "torso",
            lambda p: p.z > 0.15 and p.x > -0.2, thick=0.02, cuts=2)
    ridge = [_on(pc, PR, (1.0, 0.0, zz), 0.005) for zz in (0.55, 0.2, -0.15, -0.5)]
    k.sweep("plate_ridge", ridge, [(0.014, 0.012)] * 4, "steel", "torso", sides=4, up=(1, 0, 0))
    zt = -0.58 * PR[2]
    tw = math.sqrt(1 - 0.58 ** 2)
    k.torus("plate_trim", pc + Vector((0, 0, zt + 0.006)), 1.0, 0.018, "gold", "torso", scale=(PR[0] * tw + 0.01, PR[1] * tw + 0.01, 1.0), seg=16, ring=4)
    k.torus("chest_trim", pc + Vector((0.012, 0, 0.15 * PR[2] + 0.004)), 1.0, 0.012, "gold", "torso",
            scale=(PR[0] * 0.99 + 0.016, PR[1] * 0.99 + 0.014, 1.0), seg=16, ring=4, arc=(-1.9, 1.9))
    k.star("chest_star", _on(pc, PR, (1.0, 0.0, -0.18), 0.01), 0.085, 0.03, "gold", "torso", rot=(0, 90, 0), points=4, inner=0.38)
    for s in (-1, 1):
        for d in ((0.8, s * 0.55, 0.0), (0.75, s * 0.6, -0.38), (0.55, s * 0.8, 0.3)):
            k.blob("plate_rivet_%d_%d_%d" % (s, int(d[1] * 10), int(d[2] * 10)), _on(pc, PR, d, -0.002), (0.012, 0.012, 0.012), "gold", "torso", **RIV)
    # 배 가리개 (겹친 면진 쇠 띠 셋)
    for i in range(3):
        z = 1.1 - i * 0.055
        rx, ry = 0.205 - i * 0.012, 0.255 - i * 0.012
        k.torus("fauld_%d" % i, Vector((0.012, 0, z)), 1.0, 0.032, "steel" if i % 2 == 0 else "steel_dark", "waist",
                scale=(rx, ry, 0.8), seg=12, ring=4, blend=["waist", "torso"] if i == 0 else None)
    # 벨트 + 금 버클 + 주머니
    zb = 0.97
    k.torus("belt", Vector((0.005, 0, zb)), 1.0, 0.034, "leather", "waist", scale=(0.2, 0.245, 1.0), seg=12, ring=4)
    k.rbox("buckle", (0.215, 0, zb), (0.035, 0.1, 0.08), "gold", "waist", round_=0.2)
    k.rbox("buckle_in", (0.229, 0, zb), (0.015, 0.05, 0.04), "leather_dark", "waist", round_=0.2)
    k.rbox("pouch", (0.03, 0.235, zb - 0.055), (0.1, 0.055, 0.1), "leather", "waist", rot=(0, 0, 18), round_=0.2)
    # 허리 천 (플레이어 색): 앞 = 아래가 뾰족한 방패꼴, 뒤 = 넓은 천, 금 테
    TAB_TOP, TAB_LEN = 0.955, 0.42
    k.panel("tabard_front", (H.x, 0), TAB_TOP, TAB_LEN, 0.205, 0.235, 0.0, 0.95, "tint", "hips", depth=0.85, thick=0.022,
            seg=4, rows=3, round_bottom=-0.0, blend=["hips", "thigh_R", "thigh_L"])
    k.panel("tabard_back", (H.x, 0), TAB_TOP, TAB_LEN + 0.06, 0.21, 0.27, math.pi, 1.15, "tint", "hips", depth=0.85, thick=0.022,
            seg=4, rows=3, blend=["hips", "thigh_R", "thigh_L"])
    _pointed(k, "tabard_front")
    k.torus("tabard_hem_back", Vector((H.x, 0, TAB_TOP - TAB_LEN - 0.05)), 1.0, 0.013, "gold", "hips",
            scale=(0.27 * 0.85 + 0.01, 0.27 + 0.01, 1.0), seg=6, ring=4, arc=(math.pi - 0.5, math.pi + 0.5), blend=["hips", "thigh_R", "thigh_L"])
    # 옆 치마판 (면진 쇠 두 겹 + 리벳)
    for side, a in (("R", -math.pi / 2), ("L", math.pi / 2)):
        for i, lk in enumerate(("steel", "steel_dark")):
            k.panel("tasset_%s%d" % (side, i), (H.x, 0), 0.95 - i * 0.08, 0.14, 0.22 + i * 0.024, 0.29 + i * 0.024, a, 1.3, lk, "hips",
                    depth=0.85, thick=0.024, seg=3, rows=1, blend=["hips", "thigh_" + side])
        k.blob("tasset_rivet_" + side, (H.x, math.sin(a) * 0.235, 0.915), (0.012, 0.012, 0.012), "gold", "hips", **RIV)

    # ===== 다리 (두꺼운 판 겹침, 큰 정강이 갑옷, 육중한 장화) =====
    k.blob("pelvis", (0, 0, H.z + 0.01), (0.18, 0.25, 0.12), "cloth", "hips", cuts=1)

    def leg(side, sign):
        th, kn, ft = J("thigh_" + side), J("knee_" + side), J("foot_" + side)
        k.sweep("thigh_" + side, [th + Vector((0, 0, 0.03)), th + (kn - th) * 0.5, kn], [(0.12, 0.12), (0.115, 0.115), (0.09, 0.09)], "cloth",
                "thigh_" + side, sides=8, blend=["thigh_" + side, "knee_" + side, "hips"])
        for i in range(3):  # 허벅지 판 겹침 (위에서 아래로)
            z = th.z - 0.07 - i * 0.11
            k.shell("cuisse_%s%d" % (side, i), Vector((th.x + 0.02, th.y, z)), (0.13 - i * 0.008, 0.135 - i * 0.008, 0.1), "steel" if i != 1 else "steel_dark",
                    "thigh_" + side, lambda p: p.x > -0.3 and p.z > -0.55, thick=0.02, cuts=2)
        k.blob("knee_" + side, kn + Vector((0.06, 0, 0.0)), (0.07, 0.095, 0.085), "steel", "knee_" + side, cuts=1)
        k.blob("knee_gem_" + side, kn + Vector((0.125, 0, 0.0)), (0.018, 0.035, 0.035), "tint", "knee_" + side, cuts=0)
        k.sweep("knee_wing_%s" % side, [kn + Vector((0.05, sign * 0.06, 0.03)), kn + Vector((0.02, sign * 0.115, -0.01))],
                [(0.015, 0.05), (0.008, 0.03)], "steel_dark", "knee_" + side, sides=4, up=(1, 0, 0))
        ank = ft + Vector((0, 0, 0.11))
        k.sweep("greave_" + side, [kn + Vector((0, 0, -0.04)), kn + (ank - kn) * 0.45, ank], [(0.1, 0.1), (0.115, 0.112), (0.1, 0.1)],
                "steel", "knee_" + side, sides=8)
        k.sweep("greave_ridge_" + side, [kn + Vector((0.1, 0, -0.06)), kn + (ank - kn) * 0.45 + Vector((0.118, 0, 0)), ank + Vector((0.1, 0, 0.02))],
                [(0.012, 0.012)] * 3, "gold", "knee_" + side, sides=4, up=(1, 0, 0))
        k.torus("boot_cuff_" + side, ank + Vector((0, 0, -0.01)), 0.105, 0.03, "steel_dark", "foot_" + side, seg=8, ring=4)
        k.rbox("boot_" + side, (ft.x + 0.05, ft.y, 0.085), (0.32, 0.18, 0.16), "steel", "foot_" + side, round_=0.25)
        k.rbox("toecap_" + side, (ft.x + 0.17, ft.y, 0.07), (0.11, 0.17, 0.12), "steel_dark", "foot_" + side, round_=0.3)
        k.rbox("sole_" + side, (ft.x + 0.05, ft.y, 0.018), (0.34, 0.19, 0.036), "sole", "foot_" + side, round_=0.2)

    k.mirror(leg)

    # ===== 팔 (3겹 어깨 갑옷 + 플레이어 색 안감, 판 겹친 팔, 큰 장갑 주먹) =====
    def arm(side, sign):
        sh, el, hd = J("shoulder_" + side), J("elbow_" + side), J("hand_" + side)
        fwd = (hd - el).normalized()
        pc2 = sh + Vector((0.0, sign * 0.05, 0.06))
        PRR = (0.21, 0.2, 0.16)
        k.shell("paul_lining_" + side, pc2 + Vector((0, sign * 0.012, -0.012)), (PRR[0] + 0.012, PRR[1] + 0.012, PRR[2]), "tint", "shoulder_" + side,
                lambda p: p.z > -0.45 and p.z < -0.05, thick=0.015, rot=(sign * 24, 0, 0), cuts=2)
        k.shell("pauldron_" + side, pc2, PRR, "steel", "shoulder_" + side, lambda p: p.z > -0.3, thick=0.035, rot=(sign * 24, 0, 0), cuts=2)
        for i in range(2):  # 아래 람 판 두 겹
            k.shell("lame_%s%d" % (side, i), pc2 + Vector((0, sign * (0.03 + i * 0.025), -0.07 - i * 0.055)), (0.17 - i * 0.012, 0.165 - i * 0.012, 0.12),
                    "steel_dark" if i == 0 else "steel", "shoulder_" + side, lambda p: p.z > -0.25 and p.z < 0.5, thick=0.025,
                    rot=(sign * (34 + i * 10), 0, 0), cuts=2)
        k.torus("paul_trim_" + side, pc2 + Vector((0, sign * 0.014, -0.004)), 1.0, 0.013, "gold", "shoulder_" + side,
                rot=(sign * 24, 0, 0), scale=(PRR[0] * 0.95 + 0.008, PRR[1] * 0.95 + 0.008, 1.0), seg=12, ring=4)
        k.sweep("paul_ridge_" + side, [_on(pc2, PRR, (0.8, sign * 0.3, 0.45)), _on(pc2, PRR, (0.0, sign * 0.45, 0.9), 0.006), _on(pc2, PRR, (-0.8, sign * 0.3, 0.45))],
                [(0.012, 0.016)] * 3, "steel", "shoulder_" + side, sides=4, up=(0, 0, 1))
        for i, d in enumerate(((0.55, sign * 0.55, 0.62), (-0.55, sign * 0.55, 0.62), (0.0, sign * 0.85, 0.5))):
            k.blob("paul_rivet_%s%d" % (side, i), _on(pc2, PRR, d, 0.0), (0.014, 0.014, 0.014), "gold", "shoulder_" + side, **RIV)
        k.sweep("sleeve_" + side, [sh, (sh + el) / 2, el], [(0.1, 0.1), (0.1, 0.1), (0.085, 0.085)], "cloth", "shoulder_" + side,
                sides=8, blend=["shoulder_" + side, "elbow_" + side])
        up = (el - sh).normalized()
        for i in range(2):  # 위팔 판 두 겹
            c = sh + up * (0.12 + i * 0.1)
            k.shell("rerebrace_%s%d" % (side, i), c + Vector((0, sign * 0.012, 0)), (0.115 - i * 0.006, 0.115 - i * 0.006, 0.075), "steel", "shoulder_" + side,
                    lambda p: p.z > -0.6, thick=0.018, rot=_rot_to(-up), cuts=2)
        k.blob("elbow_" + side, el - fwd * 0.005, (0.085, 0.085, 0.085), "steel_dark", "elbow_" + side, cuts=1)
        k.sweep("elbow_wing_" + side, [el + Vector((0.0, sign * 0.06, 0.03)), el + Vector((-0.03, sign * 0.1, -0.03))], [(0.012, 0.05), (0.008, 0.025)],
                "steel", "elbow_" + side, sides=4, up=(1, 0, 0))
        wr = hd - fwd * 0.04
        k.sweep("bracer_" + side, [el + fwd * 0.035, (el + wr) / 2, wr], [(0.09, 0.09), (0.105, 0.105), (0.125, 0.125)], "steel", "elbow_" + side, sides=8)
        k.torus("wrist_" + side, wr + fwd * 0.008, 0.115, 0.018, "gold", "elbow_" + side, rot=_rot_to(fwd), seg=8, ring=4)
        hcn = hd + fwd * 0.05
        k.rbox("fist_" + side, hcn, (0.17, 0.15, 0.17), "leather", "hand_" + side, rot=_rot_to(fwd), round_=0.45)
        k.rbox("knuckle_" + side, hcn + fwd * 0.05 + Vector((0.06, 0, 0)), (0.07, 0.16, 0.09), "steel", "hand_" + side, rot=_rot_to(fwd), round_=0.3)
        k.rbox("gauntlet_back_" + side, hcn + Vector((0, -sign * 0.07, 0)), (0.12, 0.035, 0.13), "steel", "hand_" + side, rot=_rot_to(fwd), round_=0.3)

    k.mirror(arm)

    # ===== 방패 (따로): 큰 면진 팔각 방패 — 두꺼운 테, 플레이어 색 판, 금 十 돋을새김·돌기·리벳, 뒤 손잡이 =====
    sr = 0.4
    S = "shield"
    k.disk("shield_face", (0, 0, 0), sr, 0.07, "tint", "waist", rot=(0, 90, 22.5), seg=8, edge=0.35, prop=S)
    k.disk("shield_inner", (-0.03, 0, 0), sr * 0.62, 0.03, "steel", "waist", rot=(0, 90, 22.5), seg=8, edge=0.4, prop=S)
    k.torus("shield_rim", (0, 0, 0), sr, 0.04, "steel", "waist", rot=(0, 90, 22.5), seg=8, ring=4, prop=S)
    k.torus("shield_rim_gold", (-0.03, 0, 0), sr * 0.86, 0.014, "gold", "waist", rot=(0, 90, 22.5), seg=8, ring=4, prop=S)
    k.star("shield_cross", (-0.055, 0, 0), sr * 0.55, 0.025, "gold", "waist", rot=(0, -90, 0), points=4, inner=0.22, prop=S)
    k.blob("shield_boss", (-0.07, 0, 0), (0.045, 0.075, 0.075), "steel", "waist", cuts=0, prop=S)
    for i in range(8):
        a = math.radians(45 * i)
        k.blob("shield_rivet_%d" % i, (-0.035, math.cos(a) * sr * 0.93, math.sin(a) * sr * 0.93), (0.016, 0.018, 0.018), "gold", "waist", prop=S, **RIV)
    k.sweep("shield_grip", [(0.04, 0, -0.1), (0.09, 0, -0.06), (0.09, 0, 0.06), (0.04, 0, 0.1)], [(0.02, 0.028)] * 4, "leather", "waist",
            sides=4, up=(1, 0, 0), prop=S)
    for zz in (-0.17, 0.17):
        k.rbox("shield_strap_%d" % int(zz * 100), (0.038, 0, zz), (0.015, sr * 1.4, 0.05), "leather_dark", "waist", round_=0.2, prop=S)


def _pointed(k, name):
    """앞 허리 천 아래 가운데를 뾰족하게 (방패꼴): 아래 가장자리 정점을 가운데로 갈수록 더 내림"""
    ob = next(r["obj"] for r in k.parts if r["obj"].name == name)
    vs = ob.data.vertices
    zmin = min(v.co.z for v in vs)
    ys = [v.co.x for v in vs]  # Blender X = 게임 y (좌우)
    w = max(abs(y) for y in ys)
    for v in vs:
        if v.co.z < zmin + 0.13:
            t = 1 - min(1.0, abs(v.co.x) / max(1e-6, w))
            v.co.z -= 0.09 * t * (1 - (v.co.z - zmin) / 0.13)


def _back():
    import json
    import os
    r = json.load(open(os.path.join(os.path.dirname(__file__), "..", "ref", "tank_rig.json")))
    sb = r["props"]["shield_back"]
    p = Vector(HERO["waist"]) + Vector(sb["pos"]) * r["figure_scale"] + Vector((-0.09, 0, -0.17))
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
