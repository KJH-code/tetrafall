# 자동 리깅 대포수 손질: blender -b --factory-startup -P tools/blender/tripo/rig_cannon.py -- --out <폴더> [--preview <폴더>]
# 원본 src/cannon_tripo_rigged.glb (Tripo 뼈 이름 78: BoneRoot·Hip·Pelvis·Spine01/02·L_Upperarm … — 로더 ALIASES 가 맞춤, 스킨 메시 하나, 손대포가 두 손에 붙어 있음) → 알베도 한 장 (2048 jpg) + 빨간 두건·다이너마이트 띠를 몸 색 칸 (회백 + UV2.x = 1 + 꼭짓점 색 흰) 으로.
#   뼈·가중치는 원본 그대로 (우리 관절 이름 대신 Mixamo 이름 — 로더 ALIASES 가 맞춤), 뼈대/메시 어긋남만 세계 좌표로 굽기.
# 그다음 LOD: node lods.mjs <out>/cannon_rigged.glb <out>/cannon.glb cannon
import bpy
import bmesh
import sys
import os
import math
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import rigkit as K  # noqa: E402
import rig_tank as R  # noqa: E402  (빨강 판정·상수 재사용)

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.join(HERE, "src", "cannon_tripo_rigged.glb")
ATLAS = 2048
HEIGHT = 0.977417  # 원본 모델 키 (m) — 게임이 쉬는 자세 상자 키로 나눠 소품을 맞춤
P = ""  # 이 규격은 접두어 없음
LIFT = 0.8  # 알베도 밝기 끌어올림 (선형 거듭제곱, 1 = 그대로)
MIN_RED_CLUSTER = int(os.environ.get('MIN_RED', '20'))  # 목수건으로 칠할 빨강 덩어리의 최소 꼭짓점 수 (빨강이 원래 적음)
HAT_Z = float(os.environ.get("HAT_Z", "9"))  # 이보다 위 꼭짓점 = 두건 전체 (기본 안 씀 — 빨강 덩어리만)


# 1인칭 팔 (cannon_vm): 원본 팔·손은 대포에 손가락이 녹아 붙어 있어서 (대포를 떼면 속이 빈 가시 껍질) 못 씀 → 닫힌 전용 팔을 새로 만듦 (탱크 W20 `tank_vm` 과 같은 길):
#   소매 (아래팔 8각 통) + 가죽 손목 띠 + 주먹 (눌린 구), 뼈 아래팔·손에 단단히 (가중치 1). 색은 몸 알베도의 한 점 (UV 를 그 점으로 몰아 같은 재질)
VM_SKIN_UV = (float(os.environ.get("VM_SKIN_U", "0.5")), float(os.environ.get("VM_SKIN_V", "0.5")))  # build 가 알베도에서 살색·가죽색 점을 찾아 채움
VM_UV = {}


# 손대포: 원본은 대포가 몸 메시에 붙어 있고 (자동 가중치로 왼손·손가락에 매임) 코드 자세가 한 팔만 들면 대포가 두 손 사이로 늘어남 (단단히 한 뼈에 다시 묶어도 몸과 이어진 삼각형이 가시로 늘어남)
#   → 대포 삼각형 (중심이 손 사이 타원·손 앞 원통 안) 을 몸에서 떼어 따로 소품 (cannon_gun.glb, 오른손 뼈 좌표) 으로 내보냄. 코드의 attach (닌자 단검과 같은 길) 가 오른손 뼈에 붙임
GUN_AX = [float(x) for x in os.environ.get("GUN_AX", "0.07,0.46,0.58,0.22,0.056,0.105,0.115").split(",")]  # x 범위·축 높이 z·손 끝 x (그 앞은 원통)·손 사이 타원 반지름 y·z·원통 반지름
GUN_BONE = os.environ.get("GUN_BONE", "R_Hand")


def is_skin(c):
    import colorsys
    r, g, b = [max(0.0, float(x)) ** (1 / 2.2) for x in c]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return 0.04 < h < 0.12 and s > 0.45 and v > 0.62


ARM_R = {"Forearm": 0.07, "Hand": 0.052, "Finger": 0.034}  # 손·아래팔 뼈 선분에서 이 안의 꼭짓점 = 주먹·팔 살 (대포 떼기에서 지킴 — 왼 주먹이 대포 축 위에 있어서 안 지키면 팔이 뚫림)


def arm_verts(ob, arm):
    """아래팔·손·손가락 뼈가 가장 센 꼭짓점 중 그 뼈 선분 ARM_R 안인 것 (번호 집합)"""
    B = arm.data.bones

    def H(n):
        return Vector(B[n].head_local)
    seg = {}
    for sd in ("L", "R"):
        seg["%s_Forearm" % sd] = (H(sd + "_Forearm"), H(sd + "_Hand"), ARM_R["Forearm"])
        seg["%s_Hand" % sd] = (H(sd + "_Hand"), H(sd + "_Mid1"), ARM_R["Hand"])
        for f in ("Thumb", "Index", "Mid", "Ring", "Pinky"):
            for i in range(1, 4):
                a = H("%s_%s%d" % (sd, f, i))
                b = H("%s_%s%d" % (sd, f, i + 1)) if i < 3 else a + (a - H("%s_%s%d" % (sd, f, i - 1))) * 0.5
                seg["%s_%s%d" % (sd, f, i)] = (a, b, ARM_R["Finger"])
    names = {g.index: g.name for g in ob.vertex_groups}
    ok = set()
    for v in ob.data.vertices:
        if not v.groups:
            continue
        g = max(v.groups, key=lambda g: g.weight)
        n = names[g.group]
        if n in seg and K.seg_dist(v.co, seg[n][0], seg[n][1])[0] <= seg[n][2]:
            ok.add(v.index)
    return ok


def split_gun(ob, arm):
    """몸에서 대포 삼각형을 떼어 새 오브젝트로 (GUN_BONE 뼈 쉬는 자리 기준 좌표, 키 비율). 몸에는 대포 삼각형이 없어짐"""
    me = ob.data
    x0, x1, zc, xh, ry, rz, rr = GUN_AX

    def inside(c):
        if not (x0 <= c.x <= x1):
            return False
        if c.x > 0.09 and abs(c.y) < 0.1 and 0.38 < c.z < 0.7 and c.x < xh:
            return True  # 대포 개머리 아랫부분 (배 앞에 매달린 납작한 판)
        dz = c.z - zc
        return (c.x < xh and (c.y / ry) ** 2 + (dz / rz) ** 2 <= 1.0) or (c.x >= xh and c.y * c.y + dz * dz <= rr * rr)
    keep = arm_verts(ob, arm)
    gun_f = [p.index for p in me.polygons if inside(p.center) and not (p.center.x < xh and all(v in keep for v in p.vertices))]
    g = ob.copy()
    g.data = ob.data.copy()
    g.name = "cannon_gun"
    g.data.name = "cannon_gun"
    bpy.context.scene.collection.objects.link(g)

    def cut(o, drop_faces):
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i in drop_faces], context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
    gs = set(gun_f)
    cut(g, [i for i in range(len(me.polygons)) if i not in gs])
    cut(ob, gun_f)
    # 소품: 뼈대·가중치 없이, 뼈 지역 좌표 (Blender 뼈 축) 를 glTF 좌표로 (내보내기가 Blender (x,y,z) → glTF (x,z,-y) 로 바꾸니 미리 (bx, -bz, by)), 키 비율로 나눔
    g.parent = None
    g.vertex_groups.clear()
    for m in list(g.modifiers):
        g.modifiers.remove(m)
    bone = arm.data.bones[GUN_BONE]
    inv = (arm.matrix_world @ bone.matrix_local).inverted()
    for v in g.data.vertices:
        b = inv @ v.co
        v.co = Vector((b.x, -b.z, b.y)) / HEIGHT
    for nm in list(g.data.uv_layers.keys()):
        if nm == "UV2":
            g.data.uv_layers.remove(g.data.uv_layers[nm])
    for ca in list(g.data.color_attributes):
        g.data.color_attributes.remove(ca)
    g.matrix_world = Matrix.Identity(4)
    print("TF 대포 소품 삼각형 %d (몸 %d)" % (len(g.data.polygons), len(ob.data.polygons)))
    return g


def find_uv_colors(me, ob, px, W, H, uvs):
    """알베도에서 살색 (아래팔·위팔 꼭짓점 중 살색인 것) 과 가죽색 (아래팔 꼭짓점 중 살색이 아닌 것) 의 중앙값 색을 가진 텍셀의 UV 를 VM_UV 에 채움"""
    import numpy as np
    names = {g.index: g.name for g in ob.vertex_groups}
    dom = {}
    for v in me.vertices:
        if v.groups:
            g = max(v.groups, key=lambda g: g.weight)
            dom[v.index] = names[g.group]
    xs = np.clip((uvs[:, 0] * W).astype(int), 0, W - 1)
    ys = np.clip((uvs[:, 1] * H).astype(int), 0, H - 1)
    sk, lt = [], []
    for li, l in enumerate(me.loops):
        n = dom.get(l.vertex_index, "")
        c = px[ys[li], xs[li], :3]
        if n.endswith("_Upperarm") or n.endswith("_Forearm"):
            (sk if is_skin(c) else lt).append(li)
    for nm, ls in (("skin", sk), ("leather", lt)):
        cols = np.array([px[ys[li], xs[li], :3] for li in ls])
        med = np.median(cols, axis=0)
        li = ls[int(np.argmin(((cols - med) ** 2).sum(1)))]
        VM_UV[nm] = (float(uvs[li, 0]), float(uvs[li, 1]))
        print("TF 1인칭 %s색 UV" % nm, VM_UV[nm], px[ys[li], xs[li], :3].round(3), len(ls))


def tube(bm, a, b, ra, rb, n, uv, layer, cap=True):
    """a→b 축 원통 (끝 반지름 ra·rb), 끝 마개 오므림. 새 면의 UV 를 uv 한 점으로"""
    ax = (b - a).normalized()
    ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    u = ax.cross(ref).normalized()
    w = ax.cross(u).normalized()
    ring = []
    for c, r in ((a, ra), (b, rb)):
        ring.append([bm.verts.new(c + (u * math.cos(2 * math.pi * i / n) + w * math.sin(2 * math.pi * i / n)) * r) for i in range(n)])
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new([ring[0][i], ring[0][j], ring[1][j], ring[1][i]]))
    if cap:
        faces.append(bm.faces.new(ring[0][::-1]))
        faces.append(bm.faces.new(ring[1]))
    for f in faces:
        for l in f.loops:
            l[layer].uv = uv
    return faces, ring


def make_vm(ob, arm):
    B = arm.data.bones

    def H(n):
        return Vector(B[n].head_local)
    bm = bmesh.new()
    layer = bm.loops.layers.uv.new("UVMap")
    skin, leather = VM_UV["skin"], VM_UV["leather"]
    groups = {}  # 꼭짓점 → (뼈 이름)
    for sd in ("L", "R"):
        e, h, m = H(sd + "_Forearm"), H(sd + "_Hand"), H(sd + "_Mid1")
        d = h - e
        # 소매 (팔꿈치 쪽 20% 에서 손목 앞까지), 손목 띠, 주먹
        f1, r1 = tube(bm, e + d * 0.2, h - d * 0.12, 0.075, 0.062, 8, skin, layer)
        for ring in r1:
            for v in ring:
                groups[v] = sd + "_Forearm"
        f2, r2 = tube(bm, h - d * 0.2, h + d * 0.08, 0.082, 0.082, 8, leather, layer)
        for ring in r2:
            for v in ring:
                groups[v] = sd + "_Forearm"
        # 주먹: 눌린 구 (손 뼈 → 가운데 손가락 뼈 사이)
        c = (h + m) / 2 + (m - h).normalized() * 0.01
        ico = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        axis = (m - h).normalized()
        for v in ico["verts"]:
            p = v.co.copy()
            v.co = c + Vector((p.x * 0.075 * (1 if abs(axis.x) < 0.5 else 1.1), p.y * 0.065, p.z * 0.07)) + axis * (p.dot(axis) * 0.03)
            groups[v] = sd + "_Hand"
        for v in ico["verts"]:
            for f in v.link_faces:
                for l in f.loops:
                    l[layer].uv = skin
    bm.normal_update()
    me = bpy.data.meshes.new("cannon_vm")
    bm.to_mesh(me)
    vmob = bpy.data.objects.new("cannon_vm", me)
    bpy.context.scene.collection.objects.link(vmob)
    vgs = {}
    # 꼭짓점 가중치: bm 꼭짓점 번호 = me 꼭짓점 번호 (to_mesh 가 순서 유지)
    bm.verts.ensure_lookup_table()
    for v, gname in groups.items():
        if gname not in vgs:
            vgs[gname] = vmob.vertex_groups.new(name=gname)
        vgs[gname].add([v.index], 1.0, "REPLACE")
    bm.free()
    mat = ob.data.materials[0]
    me.materials.append(mat)
    vmob.parent = arm
    vmob.matrix_parent_inverse = Matrix.Identity(4)
    mod = vmob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    for p in me.polygons:
        p.use_smooth = False
    print("TF 1인칭 팔 삼각형", sum(len(p.vertices) - 2 for p in me.polygons))
    return vmob


def key(co):
    return (round(co.x * 1e4), round(co.y * 1e4), round(co.z * 1e4))


def build(args):
    import numpy as np
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o, do_unlink=True)
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
    # 원본은 뼈대 노드가 -0.488 m 내려가 있고 메시는 올라가 있음 (로더 상자 계산이 어긋나 모델이 떠 보임) → 둘 다 세계 좌표로 굽고 변환을 항등으로
    mw = ob.matrix_world.copy()
    ob.parent = None
    ob.data.transform(mw)
    ob.matrix_world = Matrix.Identity(4)
    K.select([arm])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.parent = arm
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.name = "cannon_lod0"
    ob.data.name = "cannon_lod0"
    me = ob.data
    img = K.albedo_only(me.materials[0])
    me.materials[0].name = "cannon"
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    red = R.red_amount(px)
    print("TF 텍스처", W, H, "빨강 %.1f%%" % (red.mean() * 100))
    img.name = "cannon_atlas"
    n_loops = len(me.loops)
    uvs = np.empty(n_loops * 2, dtype=np.float32)
    me.uv_layers.active.data.foreach_get("uv", uvs)
    uvs = uvs.reshape(-1, 2)
    xs = np.clip((uvs[:, 0] * W).astype(int), 0, W - 1)
    ys = np.clip((uvs[:, 1] * H).astype(int), 0, H - 1)
    loop_red = red[ys, xs]
    find_uv_colors(me, ob, px, W, H, uvs)
    acc, cnt = {}, {}
    for li, l in enumerate(me.loops):
        k = key(me.vertices[l.vertex_index].co)
        acc[k] = acc.get(k, 0.0) + loop_red[li]
        cnt[k] = cnt.get(k, 0) + 1
    redk = {k for k in acc if acc[k] / cnt[k] > 0.5}
    nbr = {}
    for e in me.edges:
        ka, kb = key(me.vertices[e.vertices[0]].co), key(me.vertices[e.vertices[1]].co)
        nbr.setdefault(ka, set()).add(kb)
        nbr.setdefault(kb, set()).add(ka)
    # 작은 빨강 덩어리 (허리 주머니·갑옷 리벳의 붉은 점) 는 몸 색 칸에서 뺌 — 목도리·허리 천·망토 안감 같은 큰 덩어리만 (이웃 이어진 꼭짓점 수 MIN_RED_CLUSTER 이상)
    seen_c, keep_k = set(), set()
    for k0 in redk:
        if k0 in seen_c:
            continue
        comp, st = [], [k0]
        seen_c.add(k0)
        while st:
            k = st.pop()
            comp.append(k)
            for n in nbr.get(k, ()):
                if n in redk and n not in seen_c:
                    seen_c.add(n)
                    st.append(n)
        if len(comp) >= MIN_RED_CLUSTER:
            keep_k.update(comp)
    print("TF 빨강 꼭짓점 %d → 큰 덩어리만 %d" % (len(redk), len(keep_k)))
    scarfk = keep_k
    # 모자 (챙·위·깃털·띠) 도 몸 색 칸: 위에서 내려다보는 판 카메라에 가장 잘 보이는 자리 (목수건은 작고 앞에서만 보임)
    hatk = {key(v.co) for v in me.vertices if v.co.z > HAT_Z}
    print("TF 목수건 꼭짓점 %d·모자 꼭짓점 %d" % (len(scarfk), len(hatk)))
    redk = scarfk | hatk

    def polys_texels(vset):
        """꼭짓점이 모두 vset 인 삼각형의 UV 칸 (+3 텍셀 넓힘)"""
        inside = np.zeros((H, W), dtype=bool)
        for p in me.polygons:
            if all(key(me.vertices[v].co) in vset for v in p.vertices):
                li = list(p.loop_indices)
                for j in range(1, len(li) - 1):
                    tri = uvs[[li[0], li[j], li[j + 1]]] * np.array([W, H])
                    x0, y0 = np.floor(tri.min(0)).astype(int) - 1
                    x1, y1 = np.ceil(tri.max(0)).astype(int) + 1
                    x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, W - 1), min(y1, H - 1)
                    gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
                    (ax, ay), (bx, by), (cx, cy) = tri
                    d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
                    if abs(d) < 1e-9:
                        continue
                    w1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / d
                    w2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / d
                    inside[y0:y1 + 1, x0:x1 + 1] |= (w1 >= -0.05) & (w2 >= -0.05) & (1 - w1 - w2 >= -0.05)
        for _ in range(3):
            d = inside.copy()
            d[1:] |= inside[:-1]
            d[:-1] |= inside[1:]
            d[:, 1:] |= inside[:, :-1]
            d[:, :-1] |= inside[:, 1:]
            inside = d
        return inside

    lum = px[..., 0] * 0.2126 + px[..., 1] * 0.7152 + px[..., 2] * 0.0722
    new = px.copy()
    # 목수건: 빨강만 (그 칸 안), 모자: 칸 전체 — 둘 다 밝기만 남긴 회백 (밝기 기준은 각자 따로)
    for vset, amount in ((scarfk, red), (hatk, np.ones((H, W), dtype=np.float32))):
        use = amount * polys_texels(vset)
        if not (use > 0.5).any():
            continue
        ref = np.percentile(lum[use > 0.5], 92)
        gray = np.clip(lum / ref * R.GRAY, 0, 1)
        for c in range(3):
            new[..., c] = new[..., c] * (1 - use) + gray * use
    # 어두운 칠 (검은 팔·장갑·안감) 을 조금 끌어올림 (선형 값 거듭제곱 LIFT < 1) — 대기실·판 빛에서 팔이 시커멓게 뭉치지 않게
    new[..., :3] = np.power(np.clip(new[..., :3], 0.0, 1.0), LIFT)
    img.pixels = new.ravel()
    img.scale(ATLAS, ATLAS)
    img.name = "cannon_atlas"
    # 몸 색 칸 표시 UV2 (꼭짓점 단위) + 꼭짓점 색 (흰)
    u2 = me.uv_layers.new(name="UV2")
    u2v = np.zeros((n_loops, 2), dtype=np.float32)
    for li, l in enumerate(me.loops):
        if key(me.vertices[l.vertex_index].co) in redk:
            u2v[li, 0] = 1.0
    u2.data.foreach_set("uv", u2v.ravel())
    ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    ca.data.foreach_set("color", [1.0] * (n_loops * 4))
    me.color_attributes.active_color = ca
    R.weld_normals(me)  # 이음선 법선 합침 (외곽선 껍질·meshopt 줄이기)
    tot = sum(p.area for p in me.polygons)
    u2d = me.uv_layers["UV2"].data
    mk = sum(p.area for p in me.polygons if sum(u2d[li].uv[0] > 0.5 for li in p.loop_indices) * 2 > len(p.loop_indices))
    print("TF 몸 색 칸 넓이 %.1f%%" % (mk / tot * 100))
    return ob, arm


def export(path, objs):
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
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = a[a.index("--out") + 1] if "--out" in a else os.path.join(REPO, "godot", "client", "assets", "models", "ext")
    ob, arm = build(a)
    gun = split_gun(ob, arm)
    objs = [ob, arm]
    if not os.environ.get('NO_VM'):
        objs.insert(1, make_vm(ob, arm))
    export(os.path.join(out, "cannon_rigged.glb"), objs)
    K.select([gun])
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "cannon_gun.glb"), export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_texcoords=True, export_normals=True, export_materials="EXPORT", export_image_format="JPEG",
                              export_jpeg_quality=88, export_skins=False, export_animations=False, export_extras=False)
    print("TF 내보냄", out)


if __name__ == "__main__":
    main()
