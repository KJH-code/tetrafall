# Tripo 기사 몸 리깅 공통 (rig_tank.py 가 씀): 정규화·뼈대 만들기·조각 단위 가중치
# Blender 좌표: 앞 -Y (glTF +Z), 왼쪽 +X, 위 +Z, m, 발바닥 0
import bpy
import bmesh
import math
from mathutils import Vector, Matrix

JOINTS = ["hips", "waist", "torso", "neck", "shoulder_R", "elbow_R", "hand_R", "shoulder_L", "elbow_L", "hand_L",
          "thigh_R", "knee_R", "foot_R", "thigh_L", "knee_L", "foot_L"]
PARENT = {"waist": "hips", "torso": "waist", "neck": "torso", "shoulder": "torso", "elbow": "shoulder", "hand": "elbow",
          "thigh": "hips", "knee": "thigh", "foot": "knee"}
CHILD = {"hips": "waist", "waist": "torso", "torso": "neck", "shoulder": "elbow", "elbow": "hand", "thigh": "knee", "knee": "foot"}


def select(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def normalize(ob, height, yaw_deg=-90.0):
    """앞 +X 인 원본을 앞 -Y 로 돌리고, 키 height, 발바닥 z=0, 가로 상자 가운데 x=0·y=0 으로."""
    me = ob.data
    me.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    me.transform(Matrix.Rotation(math.radians(yaw_deg), 4, "Z"))
    vs = [v.co for v in me.vertices]
    mn = Vector([min(v[i] for v in vs) for i in range(3)])
    mx = Vector([max(v[i] for v in vs) for i in range(3)])
    s = height / (mx.z - mn.z)
    c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    me.transform(Matrix.Scale(s, 4) @ Matrix.Translation(-c))
    return s


def make_armature(J, name="tank"):
    """J: 관절 이름 -> Vector (Blender 좌표). 뼈 = 관절 → 자식 관절 (손·발·목은 따로)."""
    arm = bpy.data.armatures.new(name + "_rig")
    ob = bpy.data.objects.new(name + "_rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    select([ob])
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for jn in JOINTS:
        base = jn.split("_")[0]
        side = jn[len(base):]
        b = arm.edit_bones.new(jn)
        b.head = J[jn]
        c = CHILD.get(base)
        if c is not None:
            b.tail = J[c + (side if c in ("elbow", "hand", "knee", "foot") else "")]
        elif base == "neck":
            b.tail = J[jn] + Vector((0, 0, 0.3))
        elif base == "hand":
            d = J[jn] - J["elbow" + side]
            b.tail = J[jn] + d.normalized() * 0.1
        elif base == "foot":
            b.tail = J[jn] + Vector((0, -0.15, -0.05))
        if (b.tail - b.head).length < 1e-3:
            b.tail = b.head + Vector((0, 0, 0.05))
        b.roll = 0.0
        eb[jn] = b
    for jn in JOINTS:
        base = jn.split("_")[0]
        side = jn[len(base):]
        p = PARENT.get(base)
        if p is not None:
            eb[jn].parent = eb[p + (side if p in ("shoulder", "elbow", "thigh", "knee") else "")]
            eb[jn].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.length_squared)))
    return (p - (a + ab * t)).length, t


def weld_islands(me):
    """위치로 붙인 (UV 이음선으로 갈라진 꼭짓점 합침) 덩어리 번호: 꼭짓점 인덱스 -> 덩어리 번호, 덩어리 수"""
    key = {}
    rep = []
    for v in me.vertices:
        k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
        rep.append(key.setdefault(k, v.index))
    parent = list(range(len(me.vertices)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for v in range(len(parent)):
        parent[find(v)] = find(rep[v])
    for p in me.polygons:
        vs = p.vertices
        for i in range(1, len(vs)):
            parent[find(vs[i])] = find(vs[0])
    ids = {}
    isl = [0] * len(parent)
    for v in range(len(parent)):
        isl[v] = ids.setdefault(find(v), len(ids))
    return isl, len(ids)


def albedo_only(mat):
    """재질을 알베도 한 장만 남김 (원본 Tripo 재질엔 법선·금속 질감 그림이 더 있어 glb 가 커짐 — 게임 툰 셰이더는 알베도만 씀)"""
    nt = mat.node_tree
    pr = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]
    keep = pr.inputs["Base Color"].links[0].from_node.name if pr.inputs["Base Color"].links else None
    for i in pr.inputs:
        if i.name != "Base Color":
            for l in list(i.links):
                nt.links.remove(l)
    pr.inputs["Metallic"].default_value = 0.0
    pr.inputs["Roughness"].default_value = 0.8
    for n in list(nt.nodes):
        if n.type == "TEX_IMAGE" and n.name != keep:
            nt.nodes.remove(n)
        elif n.type in ("NORMAL_MAP", "SEPARATE_COLOR", "MATH", "MIX", "BUMP"):
            nt.nodes.remove(n)
    for im in list(bpy.data.images):
        if im.users == 0:
            bpy.data.images.remove(im)
    return nt.nodes[keep].image if keep is not None else None


def fill_holes(bm, max_sides):
    """열린 가장자리 고리를 면으로 막음. 새 면의 UV·UV2·꼭짓점 색은 꼭짓점의 옛 모서리 값 (이웃 면) 을 베낌. 막은 고리 수"""
    _bm = bmesh
    before = set(f for f in bm.faces)
    edges = [e for e in bm.edges if e.is_boundary]
    if not edges:
        return 0
    r = _bm.ops.holes_fill(bm, edges=edges, sides=max_sides)
    new = [f for f in r["faces"]]
    uvl = bm.loops.layers.uv
    cols = bm.loops.layers.color
    for f in new:
        for l in f.loops:
            src = None
            for o in l.vert.link_loops:
                if o.face in before:
                    src = o
                    break
            if src is None:
                continue
            for layer in uvl.values():
                l[layer].uv = src[layer].uv
            for layer in cols.values():
                l[layer] = src[layer]
    return len(new)


