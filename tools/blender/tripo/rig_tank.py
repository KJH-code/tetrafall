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
    return ob, arm, img


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
    ob, arm, img = build(args)
    print("TF 삼각형", tri_count(ob))
    out = args["out"] or os.path.join(REPO, "godot", "client", "assets", "models", "ext")
    export_glb(os.path.join(out, "tank_rigged.glb"), [ob, arm])
    print("TF 내보냄", out)
    if args["preview"]:
        os.makedirs(args["preview"], exist_ok=True)
        if "--dbg" in a:
            debug_colors(ob)
            bpy.context.scene.display.shading.color_type = "VERTEX"
        render_poses(arm, ob, args["preview"], "lod0")


if __name__ == "__main__":
    main()
