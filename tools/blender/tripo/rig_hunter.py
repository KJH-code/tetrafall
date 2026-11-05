# 자동 리깅 사냥꾼 손질: blender -b --factory-startup -P tools/blender/tripo/rig_hunter.py -- --out <폴더> [--preview <폴더>]
# 원본 src/hunter_tripo_rigged.glb (Mixamo 식 뼈 65, 스킨 메시 하나, 소총이 몸에 붙어 있음) → 알베도 한 장 (2048 jpg) + 붉은 목수건을 몸 색 칸 (회백 + UV2.x = 1 + 꼭짓점 색 흰) 으로.
#   뼈·가중치는 원본 그대로 (우리 관절 이름 대신 Mixamo 이름 — 로더 ALIASES 가 맞춤), 뼈대/메시 어긋남만 세계 좌표로 굽기.
# 그다음 LOD: node lods.mjs <out>/hunter_rigged.glb <out>/hunter.glb hunter
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
SRC = os.path.join(HERE, "src", "hunter_tripo_rigged.glb")
ATLAS = 2048
P = "mixamorig:"
LIFT = 0.8  # 알베도 밝기 끌어올림 (선형 거듭제곱, 1 = 그대로)
MIN_RED_CLUSTER = 20  # 목수건으로 칠할 빨강 덩어리의 최소 꼭짓점 수 (빨강이 원래 적음)
HAT_Z = float(os.environ.get("HAT_Z", "0.82"))  # 이보다 위 꼭짓점 = 모자


def mirror_lr(ob, arm):
    """좌우 뒤집기 (MIRROR=1 일 때만, 지금은 안 씀): 몸을 Y 로 뒤집고 뼈·가중치 이름 Left↔Right 맞바꿈. 원본은 소총이 Mixamo Left* 뼈에 매였지만 게임에서 그 뼈가 R 관절로 매칭돼 (뼈 이름 매칭 + 캐릭터 방향) 이미 오른팔이라 뒤집으면 오히려 반대가 됨"""
    K.select([ob, arm])
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    # 메시: 꼭짓점 Y 뒤집기 + 면 뒤집기 (법선은 아래 weld_normals 가 다시 계산)
    me = ob.data
    for v in me.vertices:
        v.co.y = -v.co.y
    me.flip_normals()
    # 뼈대: 편집 모드에서 머리·꼬리 Y 뒤집기 (롤은 부호 반대로)
    bpy.ops.object.mode_set(mode="EDIT")
    for eb in arm.data.edit_bones:
        h, t = eb.head.copy(), eb.tail.copy()
        eb.head = (h.x, -h.y, h.z)
        eb.tail = (t.x, -t.y, t.z)
        eb.roll = -eb.roll
    bpy.ops.object.mode_set(mode="OBJECT")

    def swap(n):
        if n.startswith(P + "Left"):
            return P + "Right" + n[len(P) + 4:]
        if n.startswith(P + "Right"):
            return P + "Left" + n[len(P) + 5:]
        return n
    for g in ob.vertex_groups:
        g.name = "TMPG_" + swap(g.name)
    for b in arm.data.bones:
        b.name = "TMPB_" + swap(b.name)
    for g in ob.vertex_groups:
        g.name = g.name[5:]
    for b in arm.data.bones:
        b.name = b.name[5:]
    print("TF 좌우 뒤집음", len(arm.data.bones))


# 1인칭 팔 (hunter_vm): 판 몸 stage 메시에서 아래팔·손 뼈가 가장 센 꼭짓점의 삼각형만, 그 뼈 선분에서 이만큼 안인 것만 (소총이 화면 가운데를 가로지르지 않게 소총 꼭짓점은 뺌)
VM_R = {"ForeArm": 0.075, "Hand": 0.06, "Finger": 0.04}


def make_vm(ob, arm):
    B = arm.data.bones

    def H(n):
        return Vector(B[P + n].head_local)
    seg = {}
    for sd in ("Left", "Right"):
        seg[P + sd + "ForeArm"] = (H(sd + "ForeArm"), H(sd + "Hand"), VM_R["ForeArm"])
        seg[P + sd + "Hand"] = (H(sd + "Hand"), H(sd + "HandMiddle4"), VM_R["Hand"])
        for f in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
            for i in range(1, 5):
                a = H("%sHand%s%d" % (sd, f, i))
                b = H("%sHand%s%d" % (sd, f, i + 1)) if i < 4 else a + (a - H("%sHand%s%d" % (sd, f, i - 1))) * 0.5
                seg[P + "%sHand%s%d" % (sd, f, i)] = (a, b, VM_R["Finger"])
    names = {g.index: g.name for g in ob.vertex_groups}
    ok = set()
    for v in ob.data.vertices:
        if not v.groups:
            continue
        g = max(v.groups, key=lambda g: g.weight)
        n = names[g.group]
        if n in seg and K.seg_dist(v.co, seg[n][0], seg[n][1])[0] <= seg[n][2]:
            ok.add(v.index)
    vm = ob.copy()
    vm.data = ob.data.copy()
    vm.name = "hunter_vm"
    vm.data.name = "hunter_vm"
    bpy.context.scene.collection.objects.link(vm)
    vm.parent = arm
    vm.matrix_parent_inverse = Matrix.Identity(4)
    bm = bmesh.new()
    bm.from_mesh(vm.data)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    drop = [f for f in bm.faces if not all(v.index in ok for v in f.verts)]
    bmesh.ops.delete(bm, geom=drop, context="FACES_ONLY")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(vm.data)
    bm.free()
    print("TF 1인칭 팔 삼각형", len(vm.data.polygons))
    return vm


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
    if os.environ.get("MIRROR"):  # 기본은 뒤집지 않음 — 원본 소총이 이미 게임의 오른팔 (R 관절) 쪽 (눈으로 확인: 탕·조준에서 소총이 뻗은 오른팔을 따라감)
        mirror_lr(ob, arm)
    ob.name = "hunter_lod0"
    ob.data.name = "hunter_lod0"
    me = ob.data
    img = K.albedo_only(me.materials[0])
    me.materials[0].name = "hunter"
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    red = R.red_amount(px)
    print("TF 텍스처", W, H, "빨강 %.1f%%" % (red.mean() * 100))
    img.name = "hunter_atlas"
    n_loops = len(me.loops)
    uvs = np.empty(n_loops * 2, dtype=np.float32)
    me.uv_layers.active.data.foreach_get("uv", uvs)
    uvs = uvs.reshape(-1, 2)
    xs = np.clip((uvs[:, 0] * W).astype(int), 0, W - 1)
    ys = np.clip((uvs[:, 1] * H).astype(int), 0, H - 1)
    loop_red = red[ys, xs]
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
    img.name = "hunter_atlas"
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
    vm = make_vm(ob, arm)
    export(os.path.join(out, "hunter_rigged.glb"), [ob, vm, arm])
    print("TF 내보냄", out)


if __name__ == "__main__":
    main()
