# 자동 리깅 닌자 손질: blender -b --factory-startup -P tools/blender/tripo/rig_ninja.py -- --out <폴더> [--preview <폴더>]
# 원본 src/ninja_tripo_rigged.glb (Mixamo 식 뼈 65, 스킨 메시 하나) → 알베도 한 장 (2048 jpg) + 붉은 목도리·허리띠를 몸 색 칸 (회백 + UV2.x = 1 + 꼭짓점 색 흰) 으로
#   + 허공으로 뻗는 목도리 꼬리 가중치를 몸통 뼈로 + 1인칭 팔 'ninja_vm' (--vm). 뼈는 원본 그대로 (우리 관절 이름 대신 Mixamo 이름 — 로더 ALIASES 가 맞춤).
# 그다음 LOD: node lods.mjs <out>/ninja_rigged.glb <out>/ninja.glb ninja
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
import ninja_vm as VM  # noqa: E402  (1인칭 닫힌 팔)
import ninja_scarf as SC  # noqa: E402  (목도리 꼬리 뼈)

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.join(HERE, "src", "ninja_tripo_rigged.glb")
ATLAS = 2048
P = "mixamorig:"
CENTER_Y = 0.078  # 몸 가운데 (원본 좌표, 뼈 Hips y)
LIFT = 0.488  # 원본 뼈대 노드가 내려가 있던 높이 (아래 값은 원본 메시 좌표 − LIFT = 발바닥 0 좌표)
TAIL_Z = 1.15 - LIFT  # 이보다 위 빨강 = 목도리 (몸통 뼈)
TAIL_SIDE = 0.2  # 몸 가운데에서 이만큼 옆으로 나간 빨강 = 날리는 꼬리 (몸통 뼈)
NECK_Z0, NECK_Z1 = 1.28 - LIFT, 1.34 - LIFT  # 목도리 윗부분은 목 뼈로 섞임


# 팔·손 뼈에 매인 꼭짓점은 그 뼈 (쉬는 자세 선분) 에서 이만큼 안이어야 함 (m). 허리춤 천이 손 옆에 붙어 있어서 자동 가중치가 천 일부를 손에 매어 놓음 → 팔을 뻗으면 천이 따라와 가시처럼 늘어남
ARM_R = {"Arm": 0.08, "ForeArm": 0.06, "Hand": 0.05, "Finger": 0.035}


def arm_segments(arm):
    B = arm.data.bones

    def H(n):
        return Vector(B[P + n].head_local)
    seg = {}
    for sd in ("Left", "Right"):
        seg[P + sd + "Arm"] = (H(sd + "Arm"), H(sd + "ForeArm"), ARM_R["Arm"])
        seg[P + sd + "ForeArm"] = (H(sd + "ForeArm"), H(sd + "Hand"), ARM_R["ForeArm"])
        seg[P + sd + "Hand"] = (H(sd + "Hand"), H(sd + "HandMiddle4"), ARM_R["Hand"])
        for f in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
            for i in range(1, 5):
                a = H("%sHand%s%d" % (sd, f, i))
                b = H("%sHand%s%d" % (sd, f, i + 1)) if i < 4 else a + (a - H("%sHand%s%d" % (sd, f, i - 1))) * 0.5
                seg[P + "%sHand%s%d" % (sd, f, i)] = (a, b, ARM_R["Finger"])
    return seg


def trim_arm_weights(ob, arm):
    """팔 뼈 가중치를 뼈 가까이 (ARM_R) 인 꼭짓점에만 남김 — 나머지는 지우고 합이 1 이 되게 (남는 게 없으면 몸통)"""
    seg = arm_segments(arm)
    names = {g.index: g.name for g in ob.vertex_groups}
    cut = 0
    for v in ob.data.vertices:
        ws = {names[g.group]: g.weight for g in v.groups}
        keep = {}
        for n, w in ws.items():
            if n in seg:
                a, b, r = seg[n]
                if K.seg_dist(v.co, a, b)[0] > r:
                    continue
            keep[n] = w
        if len(keep) == len(ws):
            continue
        cut += 1
        tot = sum(keep.values())
        if tot < 0.05:
            keep = {P + ("Spine2" if v.co.z > 0.78 else "Spine"): 1.0}
            tot = 1.0
        for g in list(v.groups):
            ob.vertex_groups[g.group].remove([v.index])
        for n, w in keep.items():
            ob.vertex_groups[n].add([v.index], w / tot, "REPLACE")
    print("TF 팔 가중치 정리한 꼭짓점", cut)


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
    ob.name = "ninja_lod0"
    ob.data.name = "ninja_lod0"
    me = ob.data
    img = K.albedo_only(me.materials[0])
    me.materials[0].name = "ninja"
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    red = R.red_amount(px)
    print("TF 텍스처", W, H, "빨강 %.1f%%" % (red.mean() * 100))
    lum = px[..., 0] * 0.2126 + px[..., 1] * 0.7152 + px[..., 2] * 0.0722
    ref = np.percentile(lum[red > 0.5], 92) if (red > 0.5).any() else 1.0
    gray = np.clip(lum / ref * R.GRAY, 0, 1)
    new = px.copy()
    for c in range(3):
        new[..., c] = px[..., c] * (1 - red) + gray * red
    img.pixels = new.ravel()
    img.scale(ATLAS, ATLAS)
    img.name = "ninja_atlas"
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
    ring = set(redk)
    for k in redk:
        ring |= nbr.get(k, set())
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
    trim_arm_weights(ob, arm)
    # 날리는 목도리 꼬리·목도리: 팔·손에 매이지 않게 몸통 (위로 갈수록 목) 뼈로
    names = {g.index: g.name for g in ob.vertex_groups}
    fixed = 0
    seen = set()
    for v in me.vertices:
        k = key(v.co)
        if k not in ring:
            continue
        side = abs(v.co.y - CENTER_Y)
        if not (v.co.z > TAIL_Z or (k in redk and side > TAIL_SIDE)):
            continue
        t = min(1.0, max(0.0, (v.co.z - NECK_Z0) / (NECK_Z1 - NECK_Z0)))
        w = {P + "Spine2": 1.0 - t, P + "Neck": t}
        for g in list(v.groups):
            ob.vertex_groups[g.group].remove([v.index])
        for n, val in w.items():
            if val > 0.001:
                ob.vertex_groups[n].add([v.index], val, "REPLACE")
        if k not in seen:
            seen.add(k)
            fixed += 1
    print("TF 목도리 가중치 고침 꼭짓점", fixed)
    SC.add_scarf(ob, arm, ring, key)
    R.weld_normals(me)  # 이음선 법선 합침 (외곽선 껍질·meshopt 줄이기)
    tot = sum(p.area for p in me.polygons)
    u2d = me.uv_layers["UV2"].data
    mk = sum(p.area for p in me.polygons if sum(u2d[li].uv[0] > 0.5 for li in p.loop_indices) * 2 > len(p.loop_indices))
    print("TF 몸 색 칸 넓이 %.1f%%" % (mk / tot * 100))
    vm = VM.make_vm(ob, arm)
    return ob, arm, vm


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


def make_dagger(path):
    """손에 쥐는 단검 소품 (잡는 데 = 원점, 칼날 = +Z (glTF +Y = 손 뼈 방향)). 3 조각 (칼날·손잡이·날밑) = 재질 3 (조각마다 색 하나)"""
    bpy.ops.wm.read_factory_settings(use_empty=True)

    def mat(name, rgb, rough):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        pr = m.node_tree.nodes["Principled BSDF"]
        pr.inputs["Base Color"].default_value = (*rgb, 1.0)
        pr.inputs["Roughness"].default_value = rough
        return m

    def obj(name, bm, m):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(m)
        return ob
    # 칼날: 납작한 마름모 뿔 (밑 4점 → 끝 1점)
    bm = bmesh.new()
    base = [bm.verts.new(p) for p in ((-0.016, -0.0035, 0.036), (0.016, -0.0035, 0.036), (0.016, 0.0035, 0.036), (-0.016, 0.0035, 0.036))]
    tip = bm.verts.new((0.0, 0.0, 0.17))
    bm.faces.new(base[::-1])
    for i in range(4):
        bm.faces.new((base[i], base[(i + 1) % 4], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    blade = obj("dagger_blade", bm, mat("dagger_blade", (0.78, 0.82, 0.88), 0.4))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.0115, radius2=0.0115, depth=0.07, matrix=Matrix.Translation((0, 0, 0.0)))
    grip = obj("dagger_grip", bm, mat("dagger_grip", (0.20, 0.12, 0.08), 0.9))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0, 0, 0.037)) @ Matrix.Diagonal((0.05, 0.016, 0.008, 1)))
    guard = obj("dagger_guard", bm, mat("dagger_guard", (0.35, 0.36, 0.40), 0.5))
    export(path, [blade, grip, guard])
    print("TF 단검", path)


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = a[a.index("--out") + 1] if "--out" in a else os.path.join(REPO, "godot", "client", "assets", "models", "ext")
    if "--dagger" in a:  # 소품 (손에 쥔 단검) 만: --dagger <출력.glb>
        make_dagger(a[a.index("--dagger") + 1])
        return
    ob, arm, vm = build(a)
    export(os.path.join(out, "ninja_rigged.glb"), [ob, vm, arm])
    print("TF 내보냄", out)


if __name__ == "__main__":
    main()
