# Tripo 탱크 기사 리깅: blender -b --factory-startup -P tools/blender/tripo/rig_tank.py -- [--debug <폴더>] [--out <폴더>]
# 원본 tools/blender/tripo/src/tank_tripo_15k.glb → 뼈대 16 (우리 관절 이름) + 조각 단위 단단한 가중치 + LOD 4 → tank.glb
import bpy
import bmesh
import sys
import os
import math
import json
from collections import defaultdict
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import rigkit as K  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.join(HERE, "src", "tank_tripo_15k.glb")
ATLAS = 2048  # 텍스처 크기 (원본 4096 → 줄임)
HEIGHT = 1.9  # 모델 키 (깃 끝 포함) m

# 관절 자리 (Blender 좌표, 왼쪽 값 — 오른쪽은 x 부호 반대). 앞 -Y.
JL = {
    "hips": (0.0, 0.00, 0.66), "waist": (0.0, -0.03, 0.80), "torso": (0.0, -0.05, 1.10), "neck": (0.0, -0.08, 1.50),
    "shoulder": (0.58, 0.10, 1.30), "elbow": (0.67, 0.12, 1.08), "hand": (0.66, 0.12, 0.82),
    "thigh": (0.29, 0.00, 0.66), "knee": (0.30, 0.00, 0.37), "foot": (0.32, 0.00, 0.10),
}


def joints():
    J = {}
    for n, p in JL.items():
        if n in ("hips", "waist", "torso", "neck"):
            J[n] = Vector(p)
        else:
            J[n + "_L"] = Vector(p)
            J[n + "_R"] = Vector((-p[0], p[1], p[2]))
    return J


# 뼈 캡슐 (머리, 꼬리, 반지름): 꼭짓점마다 캡슐 겉까지 거리로 가중치 (가까운 뼈가 거의 전부, 경계에서만 부드럽게)
CAPS = {
    "hips": ((0, 0.0, 0.55), (0, 0.0, 0.74), 0.30),
    "waist": ((0, -0.03, 0.74), (0, -0.04, 0.95), 0.32),
    "torso": ((0, -0.05, 0.95), (0, -0.07, 1.40), 0.38),
    "neck": ((0, -0.08, 1.45), (0, -0.09, 1.85), 0.20),
    "shoulder": ((0.58, 0.10, 1.30), (0.67, 0.12, 1.08), 0.22),
    "elbow": ((0.67, 0.12, 1.08), (0.66, 0.12, 0.82), 0.20),
    "hand": ((0.66, 0.12, 0.82), (0.66, 0.12, 0.58), 0.17),
    "thigh": ((0.29, 0.0, 0.66), (0.30, 0.0, 0.37), 0.20),
    "knee": ((0.30, 0.0, 0.37), (0.32, 0.0, 0.10), 0.20),
    "foot": ((0.32, 0.0, 0.10), (0.32, -0.20, 0.04), 0.17),
}
TAU = 0.025  # 경계 부드러움 폭 (m)
MAXB = 3
SMOOTH_ITERS = 4  # 다리 가중치 이웃 섞기 횟수 (0 = 끔)
SMOOTH_K = 0.5
SMOOTH_Z = 0.78  # 이 높이 아래만
VM_STEEL_PCT = 0.9  # 1인칭 팔 색: 팔 텍스처 저채도 텍셀의 밝기 백분위
VM_GLOVE_PCT = 0.65
VM_MIN_FACES = 60  # 1인칭 팔: 이보다 작은 조각은 버림
VM_HOLE_SIDES = 400  # 1인칭 팔: 이 변 수 이하 구멍은 막음
CUT = True  # 망토-팔 잇는 삼각형 떼기
LOOSE_HUE = 14  # 느슨한 빨강 색조 폭 (도)
GRAY = 0.8  # 몸 색 칸 회백 밝기 (가장 밝은 주름 = 이 값, 플레이어 색을 곱함)
MASK_DILATE = 0  # 몸 색 칸 표시를 빨강에서 넓히는 겹 수 (가장자리 흰 점 방지)
DILATE = 2  # 빨강 꼭짓점을 이웃으로 넓히는 횟수


def caps():
    out = {}
    for n, (a, b, r) in CAPS.items():
        if n in ("hips", "waist", "torso", "neck"):
            out[n] = (Vector(a), Vector(b), r)
        else:
            out[n + "_L"] = (Vector(a), Vector(b), r)
            out[n + "_R"] = (Vector((-a[0], a[1], a[2])), Vector((-b[0], b[1], b[2])), r)
    return out


def weights_for(p, C):
    ds = {}
    for n, (a, b, r) in C.items():
        d, _ = K.seg_dist(p, a, b)
        ds[n] = d - r
    dmin = min(ds.values())
    w = {n: math.exp(-(d - dmin) / TAU) for n, d in ds.items()}
    top = sorted(w.items(), key=lambda t: -t[1])[:MAXB]
    tot = sum(v for _, v in top)
    return {n: v / tot for n, v in top if v / tot > 0.03}

# ---------- 빨강 (망토·앞 천·목도리) = 몸 색 칸 ----------

def red_amount(px):
    """텍스처 픽셀 (h, w, 4 선형) 마다 빨강 정도 0..1"""
    import numpy as np
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    mx = px[..., :3].max(-1)
    mn = px[..., :3].min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-5)
    d = (mx - mn) + 1e-9
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    near = np.minimum(hue, 360 - hue)  # 빨강에서 각도 차
    f = np.clip((22.0 - near) / 10.0, 0, 1) * np.clip((sat - 0.35) / 0.2, 0, 1) * (mx > 0.12)
    return f


def red_loose(px):
    """꼭짓점 판정용 느슨한 빨강 (망토 가장자리 어두운 곳까지)"""
    import numpy as np
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    mx = px[..., :3].max(-1)
    mn = px[..., :3].min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-5)
    d = (mx - mn) + 1e-9
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    near = np.minimum(hue, 360 - hue)
    return (near < LOOSE_HUE) & (sat > 0.22) & (mx > 0.05) & (r > 1.3 * g)


def sample(img_px, w, h, uv):
    x = min(w - 1, max(0, int(uv[0] * w)))
    y = min(h - 1, max(0, int(uv[1] * h)))
    return img_px[y, x]


def build(args):
    import numpy as np
    out = args.get("out") or os.path.join(REPO, "godot", "client", "assets", "models", "ext")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    ob.name = "tank_lod0"
    ob.data.name = "tank_lod0"
    K.normalize(ob, HEIGHT)
    me = ob.data
    img = K.albedo_only(me.materials[0])
    me.materials[0].name = "tank"
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    red = red_amount(px)
    red_l = red_loose(px)
    print("TF 텍스처", W, H, "빨강 %.1f%%" % (red.mean() * 100))
    # 빨강 칸 → 회백 (밝기 모양 유지) : 플레이어 색을 곱하면 그 색의 천이 됨
    lum = px[..., 0] * 0.2126 + px[..., 1] * 0.7152 + px[..., 2] * 0.0722
    ref = np.percentile(lum[red > 0.5], 92) if (red > 0.5).any() else 1.0
    gray = np.clip(lum / ref * GRAY, 0, 1)
    new = px.copy()
    for c in range(3):
        new[..., c] = px[..., c] * (1 - red) + gray * red
    img.pixels = new.ravel()
    img.scale(ATLAS, ATLAS)
    img.name = "tank_atlas"
    # 꼭짓점·면: 빨강 판정은 원래 텍스처로
    uvl = me.uv_layers.active
    n_loops = len(me.loops)
    uvs = np.empty(n_loops * 2, dtype=np.float32)
    uvl.data.foreach_get("uv", uvs)
    uvs = uvs.reshape(-1, 2)
    xs = np.clip((uvs[:, 0] * W).astype(int), 0, W - 1)
    ys = np.clip((uvs[:, 1] * H).astype(int), 0, H - 1)
    loop_red = red[ys, xs]
    loop_redl = red_l[ys, xs].astype(np.float32)
    # 꼭짓점 (위치로 합친 이웃 평균) 이 빨강인가
    isl_pos = {}
    cnt = {}
    for l in me.loops:
        v = me.vertices[l.vertex_index]
        k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
        isl_pos.setdefault(k, 0.0)
        cnt.setdefault(k, 0)
    for li, l in enumerate(me.loops):
        v = me.vertices[l.vertex_index]
        k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
        isl_pos[k] += loop_red[li]
        cnt[k] += 1
    # 빨강 꼭짓점 (위치로 합친 키) 을 이웃 쪽으로 DILATE 번 넓힘: 망토 가장자리 짙은 테두리 (채도 낮음) 가 팔에 끌려가 가시가 되는 것을 막음
    nbr = {}
    for e in me.edges:
        ka = tuple(round(c * 1e4) for c in me.vertices[e.vertices[0]].co)
        kb = tuple(round(c * 1e4) for c in me.vertices[e.vertices[1]].co)
        nbr.setdefault(ka, set()).add(kb)
        nbr.setdefault(kb, set()).add(ka)
    redk = {k for k in isl_pos if isl_pos[k] / cnt[k] > 0.5}
    redk1 = None
    for di in range(DILATE):
        add = set()
        for k in redk:
            add |= nbr.get(k, set())
        redk |= add
        if di == MASK_DILATE - 1:
            redk1 = set(redk)
    if redk1 is None:
        redk1 = {k for k in isl_pos if isl_pos[k] / cnt[k] > 0.5}
    # 몸 색 칸 표시 UV2: 위치로 합친 꼭짓점이 빨강 (MASK_DILATE 겹 넓힘) 이면 그 꼭짓점의 모든 모서리 1 — 가장자리 찢긴 삼각형이 반쪽만 칠해지지 않게
    u2 = me.uv_layers.new(name="UV2")
    u2vals = np.zeros((n_loops, 2), dtype=np.float32)
    for li, l in enumerate(me.loops):
        v = me.vertices[l.vertex_index]
        k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
        u2vals[li, 0] = 1.0 if k in redk1 else 0.0
    u2.data.foreach_set("uv", u2vals.ravel())
    # 몸 색 칸 표시 꼭짓점 색 (흰) — 툰 셰이더가 꼭짓점 색 있는 표면만 칸을 읽음
    ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    ca.data.foreach_set("color", [1.0] * (n_loops * 4))
    me.color_attributes.active_color = ca
    # 가중치
    C = caps()
    J = joints()
    arm = K.make_armature(J, "tank")
    for n in K.JOINTS:
        ob.vertex_groups.new(name=n)
    wcache = {}
    top_hips = 0
    for v in me.vertices:
        k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
        if k in wcache:
            w = wcache[k]
        else:
            isred = k in redk
            z = v.co.z
            if isred and z > 0.40:  # 망토·천·목도리: 몸통 뼈, 아래로 갈수록 허리·골반
                if z >= 1.05:
                    w = {"torso": 1.0}
                elif z >= 0.80:
                    t = (z - 0.80) / 0.25
                    w = {"torso": t, "waist": 1 - t}
                elif z >= 0.60:
                    t = (z - 0.60) / 0.20
                    w = {"waist": t, "hips": 1 - t}
                else:
                    w = {"hips": 1.0}
            elif isred:  # 망토 아래 찢긴 끝 = 골반 (다리를 따라가면 가시)
                w = {"hips": 1.0}
            else:
                w = weights_for(v.co, C)
            wcache[k] = w
    smooth_leg_weights(wcache, nbr)
    # 망토와 팔·다리를 잇는 삼각형 (원본이 한 덩어리로 붙어 있음) 은 팔을 들면 가시처럼 늘어나서 뗌 — 망토 안쪽·팔 뒤라 쉬는 자세에선 거의 안 보임
    limb = ("shoulder", "elbow", "hand")
    domin = {}
    for v in me.vertices:
        k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
        w = wcache[k]
        domin[v.index] = max(w, key=w.get).split("_")[0]
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    kill = []
    for f in bm.faces:
        ks = [tuple(round(c * 1e4) for c in vv.co) for vv in f.verts]
        rs = [kk in redk for kk in ks]
        if any(rs) and not all(rs) and any((not r_) and domin[vv.index] in limb for r_, vv in zip(rs, f.verts)) and any(r_ for r_ in rs):
            # 빨강 쪽 꼭짓점이 몸통 뼈에 매인 경우만
            if any(r_ and domin[vv.index] not in limb for r_, vv in zip(rs, f.verts)):
                kill.append(f)
    if CUT:
        bmesh.ops.delete(bm, geom=kill, context="FACES")
    loose = [vv for vv in bm.verts if not vv.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    print("TF 잇는 삼각형 뗌", len(kill))
    domin_key = {}
    for k, w in wcache.items():
        domin_key[k] = max(w, key=w.get)
    samples = []
    for li, l in enumerate(me.loops):
        v = me.vertices[l.vertex_index]
        dk = domin_key.get(tuple(round(c * 1e4) for c in v.co), "")
        if dk.startswith("elbow") or dk.startswith("hand"):
            samples.append((tuple(uvs[li]), dk))
    vmob = make_vm_arms(samples, J, arm, list(me.materials), px, W, H)
    bm.to_mesh(me)
    bm.free()
    weld_normals(me)
    for v in me.vertices:
        k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
        for n, val in wcache[k].items():
            ob.vertex_groups[n].add([v.index], val, "REPLACE")
    ob.parent = arm
    m = ob.modifiers.new("rig", "ARMATURE")
    m.object = arm
    # 몸 색 칸 넓이 (삼각형 넓이 기준)
    u2d = me.uv_layers["UV2"].data
    tot = sum(p.area for p in me.polygons)
    mk = sum(p.area for p in me.polygons if sum(u2d[li].uv[0] > 0.5 for li in p.loop_indices) * 2 > len(p.loop_indices))
    print("TF 몸 색 칸 넓이 %.1f%%" % (mk / tot * 100))
    return ob, arm, img, vmob



def smooth_leg_weights(wcache, nbr, iters=SMOOTH_ITERS):
    """엉덩이~발 (z < SMOOTH_Z) 꼭짓점 가중치를 이웃과 섞어서 (라플라시안) 떠 있는 판 조각이 따로 놀아 갈라지는 것을 줄임. 팔·몸통·망토는 그대로"""
    keys = [k for k in wcache if k[2] / 1e4 < SMOOTH_Z and abs(k[0] / 1e4) > 0.1]
    for _ in range(iters):
        new = {}
        for k in keys:
            ns = [n for n in nbr.get(k, ()) if n in wcache and n[2] / 1e4 < SMOOTH_Z + 0.05]
            if not ns:
                continue
            acc = {}
            for n in ns:
                for b, val in wcache[n].items():
                    acc[b] = acc.get(b, 0.0) + val / len(ns)
            mix = {}
            for b in set(acc) | set(wcache[k]):
                mix[b] = SMOOTH_K * wcache[k].get(b, 0.0) + (1 - SMOOTH_K) * acc.get(b, 0.0)
            top = sorted(mix.items(), key=lambda t: -t[1])[:MAXB]
            tot = sum(v for _, v in top)
            new[k] = {b: v / tot for b, v in top if v / tot > 0.03}
        wcache.update(new)


def _texel(px, W, H, uv):
    x = min(W - 1, max(0, int(uv[0] * W)))
    y = min(H - 1, max(0, int(uv[1] * H)))
    return px[y, x, :3]


def pick_uv(samples, px, W, H, score):
    """samples: [(uv, key)] → 점수 (텍셀 색) 가 가장 높은 uv"""
    best, bs = None, -1e9
    for uv, _k in samples:
        c = _texel(px, W, H, uv)
        sc = score(c)
        if sc > bs:
            best, bs = uv, sc
    return best


def make_vm_arms(arm_samples, J, arm, mats, px, W, H):
    """1인칭 전용 닫힌 팔 메시 'tank_vm' (손으로 만든 닫힌 덩어리): 팔꿈치 아래 = 앞팔 보호대 (8각 관) + 금 띠 + 주먹 덩어리 + 손등판.
    색은 원본 팔 조각 텍스처에서 고른 텍셀 (강철·금·가죽 장갑) 한 점씩 — 꼭짓점 UV 를 그 점에 모음. 뼈: 보호대·띠 = elbow, 주먹·손등 = hand (단단히)."""
    import numpy as np
    mean = np.mean([_texel(px, W, H, uv) for uv, _k in arm_samples], axis=0)

    def sat(c):
        mx, mn = float(max(c)), float(min(c))
        return (mx - mn) / max(mx, 1e-5)
    low = []
    for uv, k in arm_samples:
        c = _texel(px, W, H, uv)
        if sat(c) < 0.28:
            low.append((float(c @ np.array([0.2126, 0.7152, 0.0722])), uv, k))
    low.sort(key=lambda t: t[0])

    def pct(p_):
        return low[min(len(low) - 1, int(len(low) * p_))][1]
    steel = pct(VM_STEEL_PCT)   # 앞팔 보호대: 중간 밝기 강철
    plate = pct(0.97)           # 손등판: 밝은 강철
    glove = pct(VM_GLOVE_PCT)   # 주먹: 어두운 장갑
    gold = pick_uv(arm_samples, px, W, H, lambda c: sat(c) * float(c.max()) if (c[0] > c[1] > c[2]) else -1)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    bm.loops.layers.uv.new("UV2")
    groups = {}

    def part(geom_fn, bone, uvp):
        before = set(bm.verts)
        geom_fn()
        for v in bm.verts:
            if v not in before:
                groups[v] = bone
        bm.verts.index_update()
        newf = [f for f in bm.faces if all(v not in before for v in f.verts)]
        for f in newf:
            for l in f.loops:
                l[uvl].uv = uvp
    for side, sg in (("L", 1), ("R", -1)):
        el, ha = J["elbow_" + side], J["hand_" + side]
        mid_x = (el.x + ha.x) / 2

        def cone(r1, r2, z0, z1, x0, x1, y=0.12):
            m = Matrix.Translation(((x0 + x1) / 2, y, (z0 + z1) / 2))
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=r1, radius2=r2, depth=abs(z1 - z0), matrix=m)

        def cube(cx, cy, cz, sx, sy, sz):
            m = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1))
            bmesh.ops.create_cube(bm, size=1.0, matrix=m)
        part(lambda: cone(0.15, 0.18, 0.84, 1.10, ha.x, el.x), "elbow_" + side, steel)  # 앞팔 보호대 (아래 좁고 위 넓게: cone radius1 = 아래)
        part(lambda: cone(0.19, 0.205, 0.935, 1.03, mid_x + 0.01 * sg, mid_x + 0.012 * sg), "elbow_" + side, gold)  # 금 띠
        part(lambda: cube(ha.x, ha.y - 0.02, 0.665, 0.26, 0.27, 0.27), "hand_" + side, glove)  # 주먹
        part(lambda: cube(ha.x, ha.y - 0.15, 0.72, 0.28, 0.07, 0.16), "hand_" + side, plate)  # 손등판 (앞 = -Y)
    me = bpy.data.meshes.new("tank_vm")
    bm.to_mesh(me)
    vm = bpy.data.objects.new("tank_vm", me)
    bpy.context.scene.collection.objects.link(vm)
    for n in K.JOINTS:
        vm.vertex_groups.new(name=n)
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        vm.vertex_groups[groups[v]].add([v.index], 1.0, "REPLACE")
    bm.free()
    for mt in mats:
        me.materials.append(mt)
    vm.parent = arm
    md = vm.modifiers.new("rig", "ARMATURE")
    md.object = arm
    print("TF 1인칭 팔 삼각형", sum(len(p.vertices) - 2 for p in me.polygons))
    return vm


def debug_colors(ob):
    me = ob.data
    ca = me.color_attributes.new("dbg", "FLOAT_COLOR", "POINT")
    cols = {"hips": (1, .5, 0), "waist": (1, 1, 0), "torso": (0, .8, 0), "neck": (0, .6, 1), "shoulder": (1, 0, 0), "elbow": (1, 0, 1),
            "hand": (.5, 0, 1), "thigh": (0, 1, 1), "knee": (0, 0, 1), "foot": (.6, .3, 0)}
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight)
        ca.data[v.index].color = (*cols[ob.vertex_groups[best.group].name.split("_")[0]], 1)
    me.color_attributes.active_color = ca


def weld_normals(me):
    """UV 이음선으로 갈라진 같은 위치 꼭짓점의 법선을 하나로 (외곽선 껍질이 이음선에서 갈라지지 않게)"""
    acc = {}
    for p in me.polygons:
        for vi in p.vertices:
            v = me.vertices[vi]
            k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
            acc[k] = acc.get(k, Vector()) + p.normal * p.area
    nv = []
    for v in me.vertices:
        k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
        n = acc.get(k, Vector((0, 0, 1)))
        nv.append(n.normalized() if n.length > 1e-9 else Vector((0, 0, 1)))
    me.normals_split_custom_set_from_vertices(nv)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def posed(arm, pose):
    """pose: [(뼈, 축 (Blender 세계), 도)] — 부모 먼저"""
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    order = {n: i for i, n in enumerate(K.JOINTS)}
    for name, axis, deg in sorted(pose, key=lambda t: order[t[0]]):
        pb = arm.pose.bones[name]
        head = pb.matrix.to_translation()
        R = Matrix.Translation(head) @ Matrix.Rotation(math.radians(deg), 4, Vector(axis).normalized()) @ Matrix.Translation(-head)
        pb.matrix = R @ pb.matrix
        bpy.context.view_layer.update()


X = (1, 0, 0)
POSES = {
    "rest": [],
    "walk": [("thigh_L", X, -32), ("knee_L", X, 30), ("thigh_R", X, 32), ("shoulder_L", X, 28), ("shoulder_R", X, -28), ("elbow_L", X, -25), ("elbow_R", X, -10)],
    "punch": [("shoulder_R", X, -95), ("elbow_R", X, -20), ("torso", (0, 0, 1), -12), ("shoulder_L", X, 25), ("elbow_L", X, -60)],
    "crouch": [("hips", X, 0), ("thigh_L", X, -75), ("knee_L", X, 105), ("thigh_R", X, -75), ("knee_R", X, 105), ("torso", X, -20)],
    "jump": [("shoulder_L", (0, 1, 0), 55), ("shoulder_R", (0, 1, 0), -55), ("thigh_L", X, -45), ("knee_L", X, 70), ("thigh_R", X, 20), ("knee_R", X, 50)],
}


def render_poses(arm, lod, outdir, tag):
    import math as m
    sc = bpy.context.scene
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o is not lod
            o.hide_viewport = o is not lod
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "VERTEX" if "--dbg" in sys.argv else "TEXTURE"
    sh.show_object_outline = True
    sc.render.resolution_x = 520
    sc.render.resolution_y = 560
    sc.world = bpy.data.worlds.new("w")
    sc.world.color = (.55, .6, .68)
    cam = bpy.data.cameras.new("c")
    cam.type = "ORTHO"
    cam.ortho_scale = 2.6
    co = bpy.data.objects.new("c", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    shots = []
    for pn, pose in POSES.items():
        posed(arm, pose)
        for vn, loc, rot in (("front", (0, -6, 1.0), (m.pi / 2, 0, 0)), ("side", (6, 0, 1.0), (m.pi / 2, 0, m.pi / 2)), ("back", (0, 6, 1.0), (m.pi / 2, 0, m.pi))):
            co.location = loc
            co.rotation_euler = rot
            p = os.path.join(outdir, "%s_%s_%s.png" % (tag, pn, vn))
            sc.render.filepath = p
            bpy.ops.render.render(write_still=True)
            shots.append((pn, vn, p))
    posed(arm, [])
    return shots


def export_glb(path, objs):
    K.select(objs)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_texcoords=True, export_normals=True, export_tangents=False,
                              export_materials="EXPORT", export_image_format="JPEG", export_jpeg_quality=88,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_skins=True, export_influence_nb=4, export_def_bones=False, export_leaf_bone=False,
                              export_animations=False, export_morph=False, export_attributes=False,
                              export_extras=False, export_cameras=False, export_lights=False)


def main():
    """몸 하나 (lod0) 리깅해서 <out>/tank_rigged.glb 로. LOD 3개는 lods.mjs 가 더함 (README 참고)."""
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = {"out": a[a.index("--out") + 1] if "--out" in a else None, "preview": a[a.index("--preview") + 1] if "--preview" in a else None}
    ob, arm, img, vmob = build(args)
    print("TF 삼각형", tri_count(ob))
    out = args["out"] or os.path.join(REPO, "godot", "client", "assets", "models", "ext")
    export_glb(os.path.join(out, "tank_rigged.glb"), [ob, vmob, arm])
    print("TF 내보냄", out)
    if args["preview"]:
        os.makedirs(args["preview"], exist_ok=True)
        if "--dbg" in a:
            debug_colors(ob)
            bpy.context.scene.display.shading.color_type = "VERTEX"
        render_poses(arm, ob, args["preview"], "lod0")


if __name__ == "__main__":
    main()
