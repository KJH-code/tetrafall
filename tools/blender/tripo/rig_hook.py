# 자동 리깅 갈고리 (해적 선장) 손질: blender -b --factory-startup -P tools/blender/tripo/rig_hook.py -- --out <폴더>
# 원본 src/hook_tripo_rigged.glb (Mixamo 식 뼈 65, 스킨 메시 하나, 캐릭터 왼손이 은색 갈고리) → 알베도 한 장 (2048 jpg) + 삼각 모자를 몸 색 칸 (회백 + UV2.x = 1 + 꼭짓점 색 흰) 으로 + 닫힌 1인칭 팔 hook_vm (ninja_vm.py).
#   뼈·가중치는 원본 그대로 (우리 관절 이름 대신 Mixamo 이름 — 로더 ALIASES 가 맞춤), 뼈대/메시 어긋남만 세계 좌표로 굽기.
# 그다음 LOD: node lods.mjs <out>/hook_rigged.glb <out>/hook.glb hook
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
import rig_tank as R  # noqa: E402  (GRAY·법선 합침 재사용)
import ninja_vm as VM  # noqa: E402  (1인칭 닫힌 팔)

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.join(HERE, "src", "hook_tripo_rigged.glb")
ATLAS = 2048
P = "mixamorig:"
HAT_REF = float(os.environ.get("HAT_REF", "60"))  # 모자 밝기 기준 백분위 (대부분 검정이라 92 로 하면 팀 색이 거의 검게 나옴)
LIFT = 0.8  # 알베도 밝기 끌어올림 (선형 거듭제곱, 1 = 그대로)
MIN_RED_CLUSTER = 20  # 목수건으로 칠할 빨강 덩어리의 최소 꼭짓점 수 (빨강이 원래 적음)
HAT_Z = float(os.environ.get("HAT_Z", "0.775"))  # 이보다 위 꼭짓점 = 모자


# 팔·손 뼈에 매인 꼭짓점은 그 뼈 (쉬는 자세 선분) 에서 이만큼 안이어야 함 (m). 원본은 코트 앞자락 (3360 꼭짓점, 손에서 최대 0.37 m) 이 오른손·손가락 뼈에 매여 있어서 팔을 들면 코트가 판자처럼 따라 올라옴.
# 왼손 (갈고리) 은 손 뼈 가까이 0.143 m 안에 갈고리만 있어서 (눈으로·수치로 확인) 넉넉히 둠
ARM_R = {"Arm": 0.08, "ForeArm": 0.06, "Hand": 0.09, "Finger": 0.06}
SIDE_R = 0.03  # 팔 뼈가 가장 세지 않은 꼭짓점이 팔 가중치를 지니려면 뼈 선분에서 이 안이어야 함 (m)
CORE_R = 0.045  # 손 뼈 (손목 → 가운뎃손가락 끝) 선분에서 이 안은 색과 상관없이 손 (주먹 안 어두운 칠·손목 가중치 섞임이 끊기지 않게)
SKIN_B = 0.2  # 살색 판정: 파랑/빨강 > 이 값 (금빛 테는 파랑이 거의 없음), 초록/파랑 > 1.25, 빨강 > 0.12 (선형)
ARM_R_HOOK = {"Hand": 0.2, "Finger": 0.2}


def arm_segments(arm):
    B = arm.data.bones

    def H(n):
        return Vector(B[P + n].head_local)
    seg = {}
    for sd in ("Left", "Right"):
        rr = dict(ARM_R)
        if sd == "Left":
            rr.update(ARM_R_HOOK)
        seg[P + sd + "Arm"] = (H(sd + "Arm"), H(sd + "ForeArm"), rr["Arm"])
        seg[P + sd + "ForeArm"] = (H(sd + "ForeArm"), H(sd + "Hand"), rr["ForeArm"])
        seg[P + sd + "Hand"] = (H(sd + "Hand"), H(sd + "HandMiddle4"), rr["Hand"])
        for f in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
            for i in range(1, 5):
                a = H("%sHand%s%d" % (sd, f, i))
                b = H("%sHand%s%d" % (sd, f, i + 1)) if i < 4 else a + (a - H("%sHand%s%d" % (sd, f, i - 1))) * 0.5
                seg[P + "%sHand%s%d" % (sd, f, i)] = (a, b, rr["Finger"])
    return seg


def cut_bridges(ob, arm):
    """오른손 (벨트 위에 얹힌 주먹) 과 코트·사슬이 한 덩어리로 이어져 있어서 팔을 움직이면 그 사이 삼각형이 가시처럼 늘어남 → 오른팔 뼈가 센 꼭짓점과 몸 쪽 꼭짓점을 잇는 삼각형을 지움 (주먹과 코트 사이 틈 — 주먹 안쪽·코트 위라 쉬는 자세에선 안 보임)"""
    import bmesh as _bm
    names = {g.index: g.name for g in ob.vertex_groups}
    me = ob.data
    armside = {}
    for v in me.vertices:
        w = sum(g.weight for g in v.groups if "Right" in names[g.group] and "Hand" in names[g.group])
        armside[v.index] = w
    bm = _bm.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    drop = []
    for f in bm.faces:
        ws = [armside[v.index] for v in f.verts]
        if max(ws) > 0.5 and min(ws) < 0.1:
            drop.append(f)
    _bm.ops.delete(bm, geom=drop, context="FACES_ONLY")
    bm.to_mesh(me)
    bm.free()
    print("TF 주먹-코트 이음 삼각형 지움", len(drop))


# 오른팔 시험 자세 (본 회전 도, 뼈 로컬 XYZ): 앞으로·위로·옆으로·휘두름 — 늘어난 이음 삼각형을 찾는 용
STRETCH_POSES = [
    {"RightArm": (-85, 0, 0), "RightForeArm": (-20, 0, 0)},
    {"RightArm": (-40, 0, 0), "RightForeArm": (-40, 0, 0), "Spine": (30, 0, 0)},
    {"RightArm": (0, 0, 80), "RightForeArm": (-60, 0, 0)},
    {"RightArm": (-160, 0, 0)},
    {"RightArm": (-20, 0, -40), "RightForeArm": (-90, 0, 0)},
    {"RightArm": (30, 0, 0)},
    # 게임 쉬는 자세 = 팔이 옆으로 곧게 내려옴 (모델은 손이 허리에 얹힌 채라 아래팔을 펴야 함): 팔꿈치·어깨를 양쪽으로
    {"RightForeArm": (70, 0, 0)}, {"RightForeArm": (-70, 0, 0)}, {"RightForeArm": (0, 0, 70)}, {"RightForeArm": (0, 0, -70)},
    {"RightForeArm": (0, 70, 0)}, {"RightForeArm": (0, -70, 0)},
    {"RightArm": (0, 0, -30)}, {"RightArm": (0, 0, 30)}, {"RightArm": (0, 40, 0)}, {"RightArm": (0, -40, 0)},
]


RANDOM_POSES = int(os.environ.get("RANDOM_POSES", "60"))


def _both_sides():
    out = []
    for p in STRETCH_POSES:
        out.append(p)
        out.append({n.replace("Right", "Left"): (e[0], -e[1], -e[2]) for n, e in p.items()})  # 왼쪽: 축 부호 맞바꿈 (Mixamo 좌우 뼈 축이 거울)
        out.append({n.replace("Right", "Left"): e for n, e in p.items()})
    # 무작위 자세 (고정 시드): 어깨·팔꿈치를 모든 축으로 — 게임 동작 (shFwd·shOut·shTwist·elbow) 이 어느 축으로 돌려도 늘어나는 이음을 놓치지 않게
    import random
    rng = random.Random(7)
    for sd in ("Left", "Right"):
        for _ in range(RANDOM_POSES):
            out.append({sd + "Arm": tuple(rng.uniform(-130, 130) for _ in range(3)), sd + "ForeArm": tuple(rng.uniform(-100, 100) for _ in range(3)),
                        sd + "Shoulder": tuple(rng.uniform(-20, 20) for _ in range(3))})
    return out


def cut_stretched(ob, arm, k=4.0, min_len=0.08):
    """시험 자세에서 k 배 넘게 (그리고 min_len m 넘게) 늘어난 모서리가 오른손·오른 아래팔 뼈 꼭짓점을 낀 삼각형을 지움 (주먹이 코트·사슬에 붙은 자리의 남은 가시). 다리 사이 치마는 안 건드림"""
    import bmesh as _bm
    from mathutils import Euler
    names = {g.index: g.name for g in ob.vertex_groups}
    me = ob.data
    rest = [v.co.copy() for v in me.vertices]
    top = {}
    for v in me.vertices:
        top[v.index] = names[max(v.groups, key=lambda g: g.weight).group] if v.groups else ""
    isarm = {i: (("Hand" in n or "ForeArm" in n or n.endswith("Arm") or "Shoulder" in n) and "Leg" not in n) for i, n in top.items()}
    bad_e = set()
    K.select([arm])
    bpy.ops.object.mode_set(mode="POSE")
    for p in _both_sides():
        for b in arm.pose.bones:
            b.rotation_mode = "XYZ"
            b.rotation_euler = (0, 0, 0)
        for n, e in p.items():
            arm.pose.bones[P + n].rotation_euler = Euler([math.radians(x) for x in e])
        bpy.context.view_layer.update()
        ev = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
        em = ev.to_mesh()
        for e in me.edges:
            i, j = e.vertices
            if not (isarm[i] or isarm[j]):
                continue
            l1 = (em.vertices[i].co - em.vertices[j].co).length
            if l1 > min_len and l1 > k * max((rest[i] - rest[j]).length, 0.01):
                bad_e.add(e.index)
        ev.to_mesh_clear()
    for b in arm.pose.bones:
        b.rotation_euler = (0, 0, 0)
    bpy.ops.object.mode_set(mode="OBJECT")
    bm = _bm.new()
    bm.from_mesh(me)
    bm.edges.ensure_lookup_table()
    drop = set()
    for ei in bad_e:
        for f in bm.edges[ei].link_faces:
            drop.add(f)
    _bm.ops.delete(bm, geom=list(drop), context="FACES_ONLY")
    bm.to_mesh(me)
    bm.free()
    print("TF 늘어난 오른팔 이음 모서리 %d → 삼각형 %d 지움" % (len(bad_e), len(drop)))


def skin_like(c):
    R_, G_, B_ = c
    return R_ > 0.12 and R_ > G_ > B_ * 1.25 and B_ / R_ > SKIN_B and G_ / R_ > 0.3


def trim_arm_weights(ob, arm, vcol=None):
    """팔 뼈 가중치를 뼈 가까이 (ARM_R) 인 꼭짓점에만 남김. 남는 게 거의 없는 꼭짓점 (코트 앞자락) 은 가장 가까운 '깨끗한' 꼭짓점의 가중치를 베낌 (허리·다리 뼈로 따라가게)"""
    from mathutils import kdtree
    seg = arm_segments(arm)
    B = arm.data.bones
    core = (Vector(B[P + "RightHand"].head_local), Vector(B[P + "RightHandMiddle4"].head_local))
    names = {g.index: g.name for g in ob.vertex_groups}
    me = ob.data
    plan = {}
    for v in me.vertices:
        ws = {names[g.group]: g.weight for g in v.groups}
        keep = {}
        top_n = max(ws, key=ws.get) if ws else ""
        for n, w in ws.items():
            if n in seg:
                a, b, r = seg[n]
                d = K.seg_dist(v.co, a, b)[0]
                if d > r:
                    continue
                # 치맛자락·코트가 팔 곁에 걸쳐 팔 뼈 가중치를 일부 받은 꼭짓점은 그 뼈에서 뺌 (안 빼면 팔을 들 때 코트 판이 따라 올라옴): 팔 뼈 가중치는 그 쪽 팔 뼈가 가장 센 꼭짓점 (또는 뼈 바로 곁 SIDE_R) 에만
                sd = "Left" if "Left" in n else "Right"
                if ("Arm" in n or "Hand" in n) and not (sd in top_n and ("Arm" in top_n or "Hand" in top_n)) and d > SIDE_R:
                    continue
                # 오른손: 코트·사슬이 손 옆에 붙어 있어서 거리만으론 못 가름 → 손·손가락 뼈는 살색 꼭짓점 (또는 손 바로 곁) 에만 (왼손 갈고리는 위 규칙만)
                if vcol is not None and "Right" in n and "Hand" in n and K.seg_dist(v.co, core[0], core[1])[0] > CORE_R and not skin_like(vcol[v.index]):
                    continue
            keep[n] = w
        if len(keep) != len(ws):
            plan[v.index] = keep
    clean = [v for v in me.vertices if v.index not in plan and v.groups and not any(names[g.group] in seg for g in v.groups)]
    kd = kdtree.KDTree(len(clean))
    for i, v in enumerate(clean):
        kd.insert(v.co, i)
    kd.balance()
    nearest = 0
    for vi, keep in plan.items():
        v = me.vertices[vi]
        tot = sum(keep.values())
        if tot < 0.3:
            _, ci, _ = kd.find(v.co)
            src = clean[ci]
            keep = {names[g.group]: g.weight for g in src.groups}
            tot = sum(keep.values())
            nearest += 1
        for g in list(v.groups):
            ob.vertex_groups[g.group].remove([vi])
        for n, w in keep.items():
            ob.vertex_groups[n].add([vi], w / tot, "REPLACE")
    print("TF 팔 가중치 정리한 꼭짓점 %d (가까운 몸 가중치 베낌 %d)" % (len(plan), nearest))


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
    ob.name = "hook_lod0"
    ob.data.name = "hook_lod0"
    me = ob.data
    img = K.albedo_only(me.materials[0])
    me.materials[0].name = "hook"
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    print("TF 텍스처", W, H)
    uv0 = me.uv_layers.active.data
    acc3, cn3 = {}, {}
    for l in me.loops:
        u, v_ = uv0[l.index].uv
        c = px[min(H - 1, max(0, int(v_ * H))), min(W - 1, max(0, int(u * W))), :3]
        acc3[l.vertex_index] = acc3.get(l.vertex_index, 0) + c
        cn3[l.vertex_index] = cn3.get(l.vertex_index, 0) + 1
    vcol = {i: tuple(acc3[i] / cn3[i]) for i in acc3}
    trim_arm_weights(ob, arm, vcol)
    if not os.environ.get("NOCUT"):
        cut_bridges(ob, arm)
        cut_stretched(ob, arm)
    img.name = "hook_atlas"
    n_loops = len(me.loops)
    uvs = np.empty(n_loops * 2, dtype=np.float32)
    me.uv_layers.active.data.foreach_get("uv", uvs)
    uvs = uvs.reshape(-1, 2)
    # 삼각 모자 (챙·위·깃털·붉은 꽃·금 테) = 몸 색 칸: 위에서 내려다보는 판 카메라에 가장 잘 보이는 자리. 갈고리 손은 은색 그대로
    hatk = {key(v.co) for v in me.vertices if v.co.z > HAT_Z}
    print("TF W 모자 꼭짓점", len(hatk))
    redk = hatk

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
    # 모자 칸 전체 → 밝기만 남긴 회백 (밝기 기준은 칸 안 92 백분위)
    use = polys_texels(hatk).astype(np.float32)
    ref = np.percentile(lum[use > 0.5], HAT_REF)
    gray = np.clip(lum / ref * R.GRAY, 0, 1)
    for c in range(3):
        new[..., c] = new[..., c] * (1 - use) + gray * use
    # 어두운 칠 (검은 팔·장갑·안감) 을 조금 끌어올림 (선형 값 거듭제곱 LIFT < 1) — 대기실·판 빛에서 팔이 시커멓게 뭉치지 않게
    new[..., :3] = np.power(np.clip(new[..., :3], 0.0, 1.0), LIFT)
    img.pixels = new.ravel()
    img.scale(ATLAS, ATLAS)
    img.name = "hook_atlas"
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
    vm = VM.make_vm(ob, arm, "hook_vm", True)
    export(os.path.join(out, "hook_rigged.glb"), [ob, vm, arm])
    print("TF 내보냄", out)


if __name__ == "__main__":
    main()
