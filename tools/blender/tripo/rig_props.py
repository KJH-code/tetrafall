# 방패·망치 소품 떼어 내기: blender -b --factory-startup -P tools/blender/tripo/rig_props.py -- --out <폴더> [--preview <폴더>]
# 원본 src/cellB_60k.glb (방패 + 망치 든 기사) 에서 UV 덩어리 (조각) 를 방패 판 평면 거리·위치로 골라 따로 내보냄 (줄이기는 lods.mjs 의 props 모드)
import bpy
import sys
import os
import math
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import rigkit as K  # noqa: E402

SRC = os.path.join(HERE, "src", "cellB_60k.glb")
BODY_H = 2.1  # 원본 정규화 키 (원본 기사 한 명 = 이 키 → 몸 쪽 1.9 m 와 같은 비율 0.905 를 곱함)
BODY_SCALE = 1.9 / 2.1
SHIELD_HEIGHT = 0.95  # 최종 방패 높이 m (몸 키 1.9 의 절반)
HAMMER_LENGTH = 0.75  # 최종 망치 길이 m
DTH, LAT = 0.24, 0.95  # 방패 판 평면에서 두께 쪽 거리·판 안쪽 반경 (정규화 단위)
TEX = 1024
HAMMER_ZMAX = 0.66  # 망치 조각 중심 높이 상한 (그 위는 쥔 장갑)
ARM_D = 0.14  # 판 평면에서 몸 쪽으로 이만큼 넘게 떨어진 조각 = 팔


def build_islands(me):
    par = list(range(len(me.vertices)))

    def f(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    for p in me.polygons:
        v = p.vertices
        for i in range(1, len(v)):
            par[f(v[i])] = f(v[0])
    ids = {}
    isl = [ids.setdefault(f(i), len(ids)) for i in range(len(par))]
    return isl, len(ids)


def split(ob):
    me = ob.data
    isl, n = build_islands(me)
    P = np.array([[*v.co] for v in me.vertices])
    I = np.array(isl)
    cen = np.zeros((n, 3))
    cnt = np.bincount(I, minlength=n).astype(float)
    for k in range(3):
        cen[:, k] = np.bincount(I, weights=P[:, k], minlength=n) / cnt
    big = [i for i in range(n) if cnt[i] > 250 and cen[i][1] < -0.8 and cen[i][2] > 0.3]
    pts = P[np.isin(I, big)]
    c0 = pts.mean(0)
    _, _, vt = np.linalg.svd(pts - c0)
    nrm = vt[2]
    cls = []
    for i in range(n):
        c = cen[i]
        d = float(np.dot(c - c0, nrm))
        lat = np.linalg.norm(c - c0 - nrm * d)
        if abs(d) < DTH and lat < LAT and c[2] > 0.0 and not (c[2] < 0.3 and c[0] > -0.5) \
                and d < ARM_D:  # 방패를 쥔 팔 조각 (판 평면에서 몸 쪽으로 멀리) 은 뺌
            cls.append("shield")
        elif c[0] > 0.5 and 0.2 < c[2] < HAMMER_ZMAX:
            cls.append("hammer")
        else:
            cls.append("body")
    return isl, cls, nrm, c0


def keep_only(ob, isl, cls, want, name):
    """ob 를 복사해 want 종류 조각만 남김"""
    K.select([ob])
    bpy.ops.object.duplicate()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    kill = [v for v in bm.verts if cls[isl[v.index]] != want]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    return o


def transform_prop(o, R, scale, anchor):
    me = o.data
    me.transform(Matrix.Translation(-Vector(anchor)))
    me.transform(R.to_4x4())
    me.transform(Matrix.Scale(scale, 4))
    if R.determinant() < 0:
        me.flip_normals()


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = a[a.index("--out") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    K.normalize(ob, BODY_H)
    isl, cls, nrm, c0 = split(ob)
    img = K.albedo_only(ob.data.materials[0])
    img.scale(TEX, TEX)
    ob.data.materials[0].name = "tank_prop"
    img.name = "atlas"
    # ---- 방패: 바깥 면 → 소품 +Y (게임 -x), 긴 축 → +Z, 폭 → +X
    sh = keep_only(ob, isl, cls, "shield", "tank_shield")
    P = np.array([[*v.co] for v in sh.data.vertices])
    out_n = Vector((-nrm[0], -nrm[1], -nrm[2]))  # 판 법선은 몸 쪽을 향함 → 바깥은 반대
    c = P.mean(0)
    u, s_, vt = np.linalg.svd(P - c)
    cand = [Vector(vt[0]), Vector(vt[1])]
    up = max(cand, key=lambda v: abs(v.z))
    up = (up - out_n * up.dot(out_n)).normalized()
    if up.z < 0:
        up = -up
    w = out_n.cross(up).normalized()
    R = Matrix((w, out_n, up))  # 행 = 새 X·Y·Z 축이 가리키는 옛 방향
    q = np.array([[*(R @ Vector(p - c))] for p in P])
    height = q[:, 2].max() - q[:, 2].min()
    sc = SHIELD_HEIGHT / height
    mn, mx = q.min(0), q.max(0)
    anchor = c + np.array(R.inverted() @ Vector(((mn[0] + mx[0]) / 2, mn[1] + 0.0, (mn[2] + mx[2]) / 2)))
    transform_prop(sh, R, sc, anchor)
    # 뒷면 평면을 y=-0.03 에 (소품 y 방향 = 바깥)
    ys = [v.co.y for v in sh.data.vertices]
    sh.data.transform(Matrix.Translation((0, -0.03 - min(ys), 0)))
    xs = [v.co.x for v in sh.data.vertices]
    zs = [v.co.z for v in sh.data.vertices]
    print("TF 방패 상자 x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f 삼각형 %d" % (min(xs), max(xs), min(ys) - min(ys) - 0.03, max(ys) - min(ys) - 0.03, min(zs), max(zs), K_tri(sh)))
    # ---- 망치: 머리 → +Z, 손잡이 아래, 쥔 자리 원점
    ha = keep_only(ob, isl, cls, "hammer", "tank_hammer")
    H = np.array([[*v.co] for v in ha.data.vertices])
    # 머리 = 가장 두꺼운 덩어리: 바깥쪽 (몸에서 먼 쪽) 끝
    cen_h = H.mean(0)
    far = H[np.argmax(np.linalg.norm(H - np.array([0.1, -0.3, 0.9]), axis=1))]
    near = H[np.argmin(np.linalg.norm(H - np.array([0.1, -0.3, 0.9]), axis=1))]
    axis = Vector(far - near).normalized()  # 쥔 쪽 → 머리 방향
    z = axis
    xv = Vector((0, 0, 1)).cross(z)
    if xv.length < 1e-4:
        xv = Vector((1, 0, 0))
    xv.normalize()
    yv = z.cross(xv).normalized()
    R2 = Matrix((xv, yv, z))
    q = np.array([[*(R2 @ Vector(p - near))] for p in H])
    length = q[:, 2].max() - q[:, 2].min()
    sc2 = HAMMER_LENGTH / length
    transform_prop(ha, R2, sc2, near + (far - near) * 0.0)
    ha.data.transform(Matrix.Translation((0, 0, 0.12)))  # 손잡이 쥔 자리 = 원점 근처
    print("TF 망치 길이 %.3f 삼각형 %d" % (length * sc2, K_tri(ha)))
    for o, nm in ((sh, "tank_shield"), (ha, "tank_hammer")):
        mt = ob.data.materials[0].copy()
        mt.name = nm
        o.data.materials.clear()
        o.data.materials.append(mt)
    # 원본은 지움
    bpy.data.objects.remove(ob, do_unlink=True)
    os.makedirs(out, exist_ok=True)
    for o, nm in ((sh, "tank_shield_hi.glb"), (ha, "tank_hammer_hi.glb")):
        o.parent = None
        export(os.path.join(out, nm), [o])
    print("TF 끝", out)


def K_tri(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def export(path, objs):
    K.select(objs)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_texcoords=True, export_normals=True, export_tangents=False,
                              export_materials="EXPORT", export_image_format="JPEG", export_jpeg_quality=88,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_skins=False, export_animations=False, export_morph=False, export_attributes=False,
                              export_extras=False, export_cameras=False, export_lights=False)


main()
