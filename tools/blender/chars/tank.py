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

B.look("steel", 0x99a3b1, "metal", band=0.22, edge=0.38, hi=0xffffff, edge_from=0.5, edge_to=0.56, ao_dist=0.06, ao_min=0.42)
B.look("steel_bright", 0xb0b9c6, "metal", band=0.26, edge=0.42, hi=0xffffff, edge_from=0.5, edge_to=0.56, ao_dist=0.06, ao_min=0.42)  # 어깨·투구 (밝게)
B.look("steel_warm", 0x9ea1a6, "metal", band=0.2, edge=0.36, hi=0xfff4e8, edge_from=0.5, edge_to=0.56, ao_dist=0.06, ao_min=0.42)  # 정강이·장갑 (따뜻한 회색)
B.look("tint_dark", 0xeeeeee, "tint", tint_base=0xb4b4b4, edge=0.2, hi=0xffffff, ao_min=0.6)  # 깃 줄기 명암 둘째 단
B.look("steel_dark", 0x535c6c, "metal", band=0.18, edge=0.32, hi=0xe8f0ff, edge_from=0.5, edge_to=0.56)
B.look("gold", 0xd9a033, "metal", band=0.3, edge=0.4, hi=0xfff4c8, ao_min=0.6, edge_from=0.5, edge_to=0.56)
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
# 등 방패 가운데 (게임 좌표): 등판 겉 (흉갑 뒤 x ≈ -0.225) 뒤로 방패 뒤판 두께 (0.03 × 1.15) + 1 cm
BACK_TARGET = Vector((-0.27, 0.0, 1.2))


def _shield_pos(key):
    """방패 노드 (안쪽 몸 허리 아래) 축 기준: 모델 허리 - 코드 허리 만큼 올림 (+ 앞 방패는 가슴이 두꺼운 만큼 앞으로, 등 방패는 등 뒤로)"""
    import json
    import os
    r = json.load(open(os.path.join(os.path.dirname(__file__), "..", "ref", "tank_rig.json")))
    sb = r["props"][key]
    q = Quaternion((sb["rot"][3], sb["rot"][0], sb["rot"][1], sb["rot"][2]))
    d = Vector(HERO["waist"]) - Vector(r["joints"]["waist"]["pos"])
    if key == "shield_back":  # 방패 가운데 = 등판 바로 뒤 (BACK_TARGET) — 안쪽 끈이 등판에 닿게
        d = BACK_TARGET - (Vector(r["joints"]["waist"]["pos"]) + Vector(sb["pos"]) * r["figure_scale"])
    else:
        d += Vector((0.09, 0, -0.06))
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
    "rim": [0.22, 3.0],
    "face_glow": 0.9,
    "label_lift": 0.22,  # 머리 위 이름표를 올림 (깃 끝 2.14 m — 코드 몸 키 1.84 기준 이름표 2.1 m 와 겹치지 않게)
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

    # ===== 투구 (v5 재혁 '구처럼 둥긂' → 각진 판금 투구): 팔각 단면 고리를 쌓은 경사 돔 (위에서 앞이 좁은 계란, 옆에서 이마가 나오고 뒤통수가 흘러내림),
    #        앞은 코처럼 튀어나온 쐐기 바이저 (세로 슬릿 5), 아래는 각지게 좁아지는 턱 가리개, 정수리 세로 능선 + 소켓·깃털, 판 이음선 리벳, 피벗 원판, 이마 금 띠·별, 넓은 목 테
    hc = N + Vector((0.035, 0, 0.19))
    k.helm_hc = hc
    # 고리: (z, 앞 반경, 뒤 반경, 옆 반경, 뒤쪽 z 내림) — 투구 가운데 hc 기준 m
    RINGS = [(-0.2, 0.13, 0.2, 0.155, -0.08), (-0.13, 0.19, 0.215, 0.19, -0.05), (-0.04, 0.25, 0.22, 0.205, -0.015), (0.04, 0.225, 0.22, 0.205, 0.0),
             (0.11, 0.195, 0.215, 0.192, 0.0), (0.165, 0.145, 0.205, 0.16, 0.0), (0.2, 0.07, 0.17, 0.105, 0.0), (0.218, 0.0, 0.105, 0.04, 0.0)]
    NS = 8

    def ring_pt(r, a):
        z, rf, rb, rs, dz = r
        c, s_ = math.cos(a), math.sin(a)
        x = c * (rf if c > 0 else rb)
        return Vector((x, s_ * rs, z + (dz * -c if c < 0 else 0.0)))

    def surf(z, a, out=0.0):
        """투구 겉면 점 (높이 z, 방향 a 라디안 — 0 = 앞): 고리 사이·팔각 꼭짓점 사이를 직선 보간 (평평한 판 위)"""
        for r0, r1 in zip(RINGS[:-1], RINGS[1:]):
            if r0[0] <= z <= r1[0]:
                t = (z - r0[0]) / (r1[0] - r0[0])
                rr = tuple(r0[i] + (r1[i] - r0[i]) * t for i in range(5))
                break
        else:
            rr = RINGS[0] if z < RINGS[0][0] else RINGS[-1]
        k8 = a / (2 * math.pi / NS)
        i0_ = math.floor(k8)
        f = k8 - i0_
        p0 = ring_pt(rr, i0_ * 2 * math.pi / NS)
        p1 = ring_pt(rr, (i0_ + 1) * 2 * math.pi / NS)
        p = p0 * (1 - f) + p1 * f
        d = Vector((p.x, p.y, 0)).normalized()
        return hc + p + d * out

    import bmesh
    bm = bmesh.new()
    vs = [[bm.verts.new(ring_pt(r, 2 * math.pi * i / NS) + hc) for i in range(NS)] for r in RINGS]
    for a_, b_ in zip(vs[:-1], vs[1:]):
        for i in range(NS):
            bm.faces.new((a_[i], a_[(i + 1) % NS], b_[(i + 1) % NS], b_[i]))
    bm.faces.new(vs[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    k._place(bm)
    k._finish("helmet", bm, "steel_bright", "neck", thick=0.026, bevel=0.006)
    # 바이저 세로 슬릿 5 (얼굴 재질: 안 어둠 + 눈 점) — 앞 쐐기 판 위
    k.face_frame = (hc + Vector((0, 0, 0.045)), 0.2, 0.12)
    for i, yy in enumerate((-0.12, -0.06, 0.0, 0.06, 0.12)):
        a_ = math.asin(max(-0.9, min(0.9, yy / 0.21)))
        top = surf(0.1, a_, 0.002)
        bot = surf(0.0, a_, 0.002)
        mid = (top + bot) / 2
        yaw = math.degrees(math.atan2(mid.y - hc.y, mid.x - hc.x))
        k.rbox("slit_%d" % i, tuple(mid), (0.01, 0.026, (top - bot).length + 0.008), "visor", "neck", rot=(0, -8, yaw), round_=0.3, face=True)
    # 숨구멍 (턱 가리개 앞 두 줄)
    for s_ in (-1, 1):
        for i in range(3):
            k.blob("vent_%d_%d" % (s_, i), surf(-0.1, s_ * (0.2 + i * 0.17), 0.001), (0.008,) * 3, "visor", "neck", **RIV)
    # 판 이음선 리벳 (옆·뒤 꼭짓점 줄) + 피벗 원판 (옆)
    for ai in (2, 3, 5, 6):
        a_ = 2 * math.pi * ai / NS
        for zz in (-0.1, 0.0, 0.1):
            k.blob("seam_rivet_%d_%d" % (ai, int((zz + 1) * 10)), surf(zz, a_, 0.004), (0.008,) * 3, "steel", "neck", **RIV)
    for s_ in (-1, 1):
        pv = surf(0.04, s_ * math.pi / 2, 0.008)
        k.disk("pivot_%d" % s_, tuple(pv), 0.055, 0.018, "gold", "neck", rot=(90, 0, 0), seg=8, edge=0.3)
        k.disk("pivot_in_%d" % s_, tuple(pv + Vector((0, s_ * 0.011, 0))), 0.03, 0.013, "steel_dark", "neck", rot=(90, 0, 0), seg=8, edge=0.3)
        for a in range(4):
            aa = math.radians(45 + 90 * a)
            k.blob("pivot_rivet_%d_%d" % (s_, a), tuple(pv + Vector((math.cos(aa) * 0.04, s_ * 0.01, math.sin(aa) * 0.04))), (0.007,) * 3, "steel", "neck", **RIV)
    # 이마 금 띠 (바이저 위, 팔각 고리를 따라 앞 반) + 리벳 + 이마 별
    band = [surf(0.125, a_, 0.008) for a_ in [math.radians(x) for x in (-100, -67.5, -45, -22.5, 0, 22.5, 45, 67.5, 100)]]
    k.sweep("brow_band", band, [(0.012, 0.02)] * len(band), "gold", "neck", sides=4, up=(0, 0, 1))
    for i, x in enumerate((-80, -45, -22.5, 22.5, 45, 80)):
        k.blob("band_rivet_%d" % i, surf(0.125, math.radians(x), 0.02), (0.007,) * 3, "steel", "neck", **RIV)
    k.star("brow_star", surf(0.155, 0.0, 0.006), 0.045, 0.016, "gold", "neck", rot=(0, 60, 0), points=4, inner=0.4)
    # 정수리 세로 능선 (앞 이마 → 정수리 → 뒤통수) + 깃 꽂이 (능선 위)
    comb = [surf(0.16, 0.0, -0.05), surf(0.2, 0.0, -0.012), hc + Vector((0.0, 0, 0.228)), surf(0.205, math.pi - 1e-3, 0.008), surf(0.1, math.pi - 1e-3, 0.006),
            surf(-0.05, math.pi - 1e-3, 0.004)]
    k.sweep("comb", comb, [(0.014, 0.045)] * len(comb), "steel", "neck", sides=4, up=(1, 0, 0))
    k.sweep("comb_trim", [c + Vector((0, 0, 0.0)) for c in comb], [(0.016, 0.008)] * len(comb), "gold", "neck", sides=4, up=(1, 0, 0), bevel=0)
    sk = hc + Vector((-0.04, 0, 0.245))
    k.disk("plume_socket", tuple(sk), 0.028, 0.05, "gold", "neck", rot=(0, -18, 0), seg=8, edge=0.25)
    k.torus("socket_ring", sk + Vector((0.005, 0, -0.018)), 0.034, 0.009, "steel_dark", "neck", seg=8, ring=4)
    # 깃털 8 가닥 (짧고 풍성하게, 부채, 명암 2단) — 소켓 안에서 시작, 위로 조금 솟았다 뒤·아래로
    base = sk + Vector((0.0, 0, 0.012))
    for i in range(8):
        dy = (i - 3.5) / 3.5  # -1 .. 1
        ln = 0.8 * (1.0 - 0.18 * abs(dy))
        ww = 0.03 * (1.0 - 0.25 * abs(dy))
        lift = 1.0 - 0.3 * abs(dy)
        P0 = base
        P1 = base + Vector((0.05, dy * 0.015, 0.1 * lift)) * ln
        P2 = base + Vector((-0.36, dy * 0.08, 0.08 * lift)) * ln
        P3 = base + Vector((-0.56, dy * 0.13, -0.24)) * ln
        pts, rad = [], []
        for t_i in range(9):
            t = t_i / 8
            u = 1 - t
            pts.append(P0 * u ** 3 + P1 * 3 * u * u * t + P2 * 3 * u * t * t + P3 * t ** 3)
            w = ww * 1.6 * (0.5 + 1.2 * math.sin(math.pi * min(1.0, t * 1.15)))
            rad.append((max(0.005, w * (1.0 - 0.88 * t ** 3)), 0.005))
        k.sweep("plume_%d" % i, pts, rad, "tint" if i % 2 == 0 else "tint_dark", "neck", sides=4, up=(0, 1, 0), bevel=0)
    # 목 (짧고 두꺼운 사슬) + 넓은 목 테 (고르짓, 어깨 위로 걸침 — 투구가 '놓인' 느낌) + 리벳
    k.sweep("neck_mail", [N + Vector((0, 0, -0.04)), N + Vector((0.01, 0, 0.06))], [(0.12, 0.13)] * 2, "cloth", "neck", sides=8)
    k.torus("gorget", N + Vector((0.0, 0, -0.035)), 1.0, 0.05, "steel", "torso", scale=(0.21, 0.25, 0.75), seg=8, ring=4)
    k.torus("gorget_trim", N + Vector((0.0, 0, 0.0)), 1.0, 0.014, "gold", "torso", scale=(0.205, 0.245, 1.0), seg=8, ring=4)
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        k.blob("gorget_rivet_%d" % i, N + Vector((math.cos(a) * 0.255 * 0.85, math.sin(a) * 0.3 * 0.85, -0.02)), (0.008,) * 3, "gold", "torso", **RIV)

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
    # 방패 멜빵 (가죽 + 금 버클): 오른어깨 → 가슴 → 왼허리, 등에서도 같은 사선 (방패 고리에 이어짐)
    for nm, sx in (("front", 1.0), ("back", -1.0)):
        st = [_on(pc, PR, (sx * 0.4, -0.8, 0.72), 0.012), _on(pc, PR, (sx * 0.97, -0.25, 0.32), 0.014), _on(pc, PR, (sx * 0.97, 0.3, -0.12), 0.014),
              _on(pc, PR, (sx * 0.55, 0.82, -0.5), 0.012)]
        k.sweep("baldric_" + nm, st, [(0.04, 0.012)] * 4, "leather", "torso", sides=4, up=(sx, 0, 0))
    # 흉갑 아래 곡선 장식 (가운데 능선에서 양옆으로 휘어 올라가는 금 홈 두 줄 — 돋을새김) + 위 판 경계 패널 라인
    for s_ in (-1, 1):
        for j, (z0, sp) in enumerate(((-0.42, 1.0), (-0.3, 0.75))):
            sc = []
            for t_i in range(7):
                t = t_i / 6
                yy = s_ * (0.06 + 0.62 * t) * sp
                zz = z0 + 0.32 * t * t - 0.05 * math.sin(math.pi * t)
                sc.append(_on(pc, PR, (math.sqrt(max(0.05, 1 - yy * yy)), yy, zz), 0.006))
            k.sweep("chest_scroll_%d_%d" % (s_, j), sc, [(0.009, 0.007)] * len(sc), "gold" if j == 0 else "steel_dark", "torso", sides=4, up=(1, 0, 0), bevel=0)
        pl = [_on(pc, PR, (math.cos(math.radians(a)), s_ * math.sin(math.radians(a)), 0.15), 0.022) for a in (15, 40, 65, 90)]
        k.sweep("panel_line_%d" % s_, pl, [(0.006, 0.006)] * 4, "steel_dark", "torso", sides=4, up=(0, 0, 1), bevel=0)
    # 허리 아래 앞 스커트 판 (뾰족한 쇠 판 둘, 허리 천 양옆 — 면진 판)
    for s_ in (-1, 1):
        nm = "skirt_%d" % s_
        k.panel(nm, (H.x, 0), 0.93, 0.2, 0.215, 0.26, s_ * 0.62, 0.5, "steel", "hips", depth=0.85, thick=0.022, seg=2, rows=2,
                blend=["hips", "thigh_R" if s_ < 0 else "thigh_L"])
        _pointed(k, nm, 0.07)
        k.blob("skirt_rivet_%d" % s_, (H.x + 0.19, s_ * 0.12, 0.9), (0.011,) * 3, "gold", "hips", **RIV)
    bk = _on(pc, PR, (0.97, 0.02, 0.1), 0.026)
    k.rbox("baldric_buckle", tuple(bk), (0.02, 0.06, 0.07), "gold", "torso", rot=(0, 0, 0), round_=0.25)
    k.rbox("baldric_buckle_in", tuple(bk + Vector((0.008, 0, 0))), (0.012, 0.03, 0.035), "leather_dark", "torso", round_=0.25)
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
        cg = [Vector((th.x + 0.13, th.y + sign * dd, th.z - 0.05 - t * 0.27)) for t, dd in ((0, 0.02), (0.33, 0.035), (0.66, 0.03), (1.0, 0.015))]
        k.sweep("cuisse_groove_" + side, cg, [(0.006, 0.006)] * 4, "gold", "thigh_" + side, sides=4, up=(1, 0, 0), bevel=0)
        k.blob("knee_" + side, kn + Vector((0.06, 0, 0.0)), (0.07, 0.095, 0.085), "steel", "knee_" + side, cuts=1)
        k.blob("knee_gem_" + side, kn + Vector((0.125, 0, 0.0)), (0.018, 0.035, 0.035), "tint", "knee_" + side, cuts=0)
        k.sweep("knee_wing_%s" % side, [kn + Vector((0.05, sign * 0.06, 0.03)), kn + Vector((0.02, sign * 0.115, -0.01))],
                [(0.015, 0.05), (0.008, 0.03)], "steel_dark", "knee_" + side, sides=4, up=(1, 0, 0))
        ank = ft + Vector((0, 0, 0.11))
        k.sweep("greave_" + side, [kn + Vector((0, 0, -0.04)), kn + (ank - kn) * 0.45, ank], [(0.1, 0.1), (0.115, 0.112), (0.1, 0.1)],
                "steel_warm", "knee_" + side, sides=8)
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
        k.shell("pauldron_" + side, pc2, PRR, "steel_bright", "shoulder_" + side, lambda p: p.z > -0.3, thick=0.035, rot=(sign * 24, 0, 0), cuts=2)
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
        k.sweep("bracer_" + side, [el + fwd * 0.035, (el + wr) / 2, wr], [(0.09, 0.09), (0.105, 0.105), (0.125, 0.125)], "steel_warm", "elbow_" + side, sides=8)
        k.torus("wrist_" + side, wr + fwd * 0.008, 0.115, 0.018, "gold", "elbow_" + side, rot=_rot_to(fwd), seg=8, ring=4)
        hcn = hd + fwd * 0.05
        k.rbox("fist_" + side, hcn, (0.17, 0.15, 0.17), "leather", "hand_" + side, rot=_rot_to(fwd), round_=0.45)
        k.rbox("knuckle_" + side, hcn + fwd * 0.05 + Vector((0.06, 0, 0)), (0.07, 0.16, 0.09), "steel_warm", "hand_" + side, rot=_rot_to(fwd), round_=0.3)
        k.rbox("gauntlet_back_" + side, hcn + Vector((0, -sign * 0.07, 0)), (0.12, 0.035, 0.13), "steel_warm", "hand_" + side, rot=_rot_to(fwd), round_=0.3)

    k.mirror(arm)

    # ===== 방패 (따로, v3 재혁: 히터 방패 — 평평한 윗변·곧은 옆·아래에서 둥글게 모여 뾰족) =====
    _heater(k)


SH_W, SH_TOP, SH_SIDE, SH_BOT = 0.34, 0.34, 0.0, -0.52  # 방패 반 폭·윗변 높이·옆이 곧은 끝·뾰족 끝 (방패 좌표 m, 게임에선 × FIGURE_SCALE)


def _outline(n_curve=6):
    """방패 윤곽 (방패 좌표 y, z — 면이 -x 를 봄): 윗변 → 오른쪽 옆 → 아래 곡선 → 끝 → 왼쪽"""
    pts = [(-SH_W, SH_TOP), (SH_W, SH_TOP), (SH_W, SH_SIDE)]
    for i in range(1, n_curve + 1):
        a = math.pi / 2 * i / n_curve
        pts.append((SH_W * math.cos(a) ** 0.85, SH_SIDE + (SH_BOT - SH_SIDE) * math.sin(a)))
    for i in range(n_curve - 1, 0, -1):
        a = math.pi / 2 * i / n_curve
        pts.append((-SH_W * math.cos(a) ** 0.85, SH_SIDE + (SH_BOT - SH_SIDE) * math.sin(a)))
    pts.append((-SH_W, SH_SIDE))
    return pts


def _heater(k):
    import bmesh
    S = "shield"
    ol = _outline()
    # 판: 윤곽을 가운데로 줄인 고리 3개 (가운데로 갈수록 앞 (-x) 으로 볼록) + 뒤 평면 → 두께 있는 면진 판
    bm = bmesh.new()
    rings = []
    for r_i, (f, bulge) in enumerate(((1.0, 0.0), (0.72, -0.025), (0.4, -0.04))):
        rings.append([bm.verts.new((bulge - 0.012, y * f, z * f + (1 - f) * 0.04)) for (y, z) in ol])
    cf = bm.verts.new((-0.048, 0.0, 0.04))
    back = [bm.verts.new((0.03, y, z)) for (y, z) in ol]
    n = len(ol)
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    for i in range(n):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % n], cf))
        bm.faces.new((back[(i + 1) % n], back[i], rings[0][i], rings[0][(i + 1) % n]))
    bm.faces.new(list(reversed(back)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    k._place(bm)
    k._finish("shield_face", bm, "tint", "waist", prop=S)
    # 두꺼운 테 (쇠, 윤곽을 따라 닫힌 관) + 안쪽 금 테
    rim = [(-0.012, y, z) for (y, z) in ol] + [(-0.012, ol[0][0], ol[0][1])]
    k.sweep("shield_rim", rim, [(0.035, 0.03)] * len(rim), "steel", "waist", sides=4, up=(1, 0, 0), prop=S, caps=False)
    gold = [(-0.03, y * 0.84, z * 0.84 + 0.16 * 0.04) for (y, z) in ol] + [(-0.03, ol[0][0] * 0.84, ol[0][1] * 0.84 + 0.0064)]
    k.sweep("shield_gold", gold, [(0.012, 0.01)] * len(gold), "gold", "waist", sides=4, up=(1, 0, 0), prop=S, caps=False)
    # 가운데 세로 능선 + 가로대 (금 十) + 돌기 + 리벳
    k.sweep("shield_ridge", [(-0.05, 0, SH_TOP - 0.06), (-0.06, 0, 0.05), (-0.05, 0, SH_BOT + 0.1)], [(0.016, 0.022)] * 3, "gold", "waist", sides=4, up=(1, 0, 0), prop=S)
    k.sweep("shield_bar", [(-0.05, -SH_W + 0.07, 0.12), (-0.06, 0, 0.12), (-0.05, SH_W - 0.07, 0.12)], [(0.016, 0.022)] * 3, "gold", "waist", sides=4, up=(1, 0, 0), prop=S)
    k.blob("shield_boss", (-0.07, 0, 0.12), (0.04, 0.06, 0.06), "steel", "waist", cuts=0, prop=S)
    for i, (y, z) in enumerate(ol):
        if i % 2 == 0:
            k.blob("shield_rivet_%d" % i, (-0.045, y * 0.92, z * 0.92 + 0.003), (0.012, 0.014, 0.014), "gold", "waist", prop=S, **RIV)
    # 안쪽: 팔 끈 둘 (가죽) + 손잡이 + 등 끈 고리 (금)
    k.sweep("shield_grip", [(0.035, 0, -0.12), (0.085, 0, -0.08), (0.085, 0, 0.04), (0.035, 0, 0.08)], [(0.018, 0.026)] * 4, "leather", "waist",
            sides=4, up=(1, 0, 0), prop=S)
    for zz in (-0.2, 0.18):
        k.rbox("shield_strap_%d" % int(zz * 100), (0.042, 0, zz), (0.014, SH_W * 1.5, 0.045), "leather_dark", "waist", round_=0.2, prop=S)
    for yy in (-0.22, 0.22):
        k.torus("shield_loop_%d" % int(yy * 100), (0.045, yy, SH_TOP - 0.05), 0.028, 0.007, "gold", "waist", rot=(0, 90, 0), seg=8, ring=4, prop=S)


def _pointed(k, name, depth=0.09):
    """앞 허리 천 아래 가운데를 뾰족하게 (방패꼴): 아래 가장자리 정점을 가운데로 갈수록 더 내림"""
    ob = next(r["obj"] for r in k.parts if r["obj"].name == name)
    vs = ob.data.vertices
    zmin = min(v.co.z for v in vs)
    ys = [v.co.x for v in vs]  # Blender X = 게임 y (좌우)
    w = max(abs(y) for y in ys)
    for v in vs:
        if v.co.z < zmin + 0.13:
            t = 1 - min(1.0, abs(v.co.x) / max(1e-6, w))
            v.co.z -= depth * t * (1 - (v.co.z - zmin) / 0.13)


def _back():
    import json
    import os
    r = json.load(open(os.path.join(os.path.dirname(__file__), "..", "ref", "tank_rig.json")))
    sb = r["props"]["shield_back"]
    p = BACK_TARGET
    q = Quaternion((sb["rot"][3], sb["rot"][0], sb["rot"][1], sb["rot"][2]))
    e = q.to_euler("XYZ")
    return ("waist", tuple(p), (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z)))


PREVIEW_PROPS = {"shield": _back()}
_HC = (HERO["neck"][0] + 0.035, 0.0, HERO["neck"][2] + 0.19)
PREVIEW_EXTRA = [("top", (0, 0, 1.0), 0, 89, 1.8), ("helm_side", _HC, 90, 5, 0.75), ("helm_back", _HC, 160, 12, 0.75), ("helm_top", _HC, 30, 60, 0.75)]
PREVIEW_POSES = {
    "punch": [("shoulder_R", (0, 1, 0), -95), ("shoulder_L", (0, 1, 0), -30), ("elbow_L", (0, 1, 0), -110),
              ("waist", (0, 0, 1), 25), ("thigh_R", (0, 1, 0), -35), ("knee_R", (0, 1, 0), 50)],
    "crouch": [("thigh_R", (0, 1, 0), -75), ("thigh_L", (0, 1, 0), -75), ("knee_R", (0, 1, 0), 115), ("knee_L", (0, 1, 0), 115),
               ("waist", (0, 1, 0), 30), ("shoulder_R", (0, 1, 0), -60), ("shoulder_L", (0, 1, 0), -60),
               ("elbow_R", (0, 1, 0), -90), ("elbow_L", (0, 1, 0), -90)],
    "slam": [("shoulder_R", (0, 1, 0), -170), ("shoulder_L", (0, 1, 0), -170), ("elbow_R", (0, 1, 0), -30),
             ("elbow_L", (0, 1, 0), -30), ("waist", (0, 1, 0), -20), ("neck", (0, 1, 0), -20)],
}
