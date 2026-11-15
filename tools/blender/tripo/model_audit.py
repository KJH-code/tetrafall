# W33 모델링 자동 검사: assets/models/ext/<id>.glb 의 메시마다 삼각형·열린 모서리·뒤집힌 법선 의심·UV 겹침/범위·스킨 (정점당 뼈 수, 가중치 합, 뼈 수)·텍스처 크기·마스크 (색 칸) 정점 비율을 JSON 한 줄로.
# blender -b --factory-startup -P tools/blender/tripo/model_audit.py -- <glb> [out.json]
import bpy
import bmesh
import sys
import json
import os


def audit_mesh(ob, arm):
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    # 열린 모서리는 위치가 같은 정점을 합친 뒤에 셈 (glTF 는 UV·법선 이음선마다 정점을 쪼개 놓아서 그냥 세면 이음선이 전부 '열림')
    bmw = bm.copy()
    bmesh.ops.remove_doubles(bmw, verts=bmw.verts, dist=1e-5)
    open_welded = sum(1 for e in bmw.edges if e.is_boundary)
    nonman_welded = sum(1 for e in bmw.edges if not e.is_manifold and not e.is_boundary)
    bmw.free()
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    open_edges = sum(1 for e in bm.edges if e.is_boundary)
    nonman = sum(1 for e in bm.edges if not e.is_manifold and not e.is_boundary)
    # 뒤집힌 면 의심: 면 법선이 (면 중심 - 메시 중심) 방향과 반대인 비율은 의미 약함 → 이웃 면과 법선이 90도 넘게 꺾인 모서리 수
    import math
    flipped = 0
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a, b = e.link_faces
            if a.normal.dot(b.normal) < -0.2:
                flipped += 1
    # UV
    uv_oob = 0
    area_tot = 0.0
    uvl = bm.loops.layers.uv.active
    uv_tris = []
    if uvl:
        for f in bm.faces:
            pts = [l[uvl].uv.copy() for l in f.loops]
            for p in pts:
                if p.x < -0.001 or p.x > 1.001 or p.y < -0.001 or p.y > 1.001:
                    uv_oob += 1
            for i in range(1, len(pts) - 1):
                a, b, c = pts[0], pts[i], pts[i + 1]
                ar = abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) * 0.5
                area_tot += ar
                uv_tris.append((a.x, a.y, b.x, b.y, c.x, c.y, ar))
    # UV 겹침: 격자 칸 (64x64) 에 삼각형 UV 면적 합 / 칸 면적 — 한 칸에 두 겹 이상 쌓인 칸 비율
    overlap = 0.0
    if uv_tris:
        N = 128
        grid = [0.0] * (N * N)
        for (ax, ay, bx, by, cx, cy, ar) in uv_tris:
            gx = int(((ax + bx + cx) / 3.0) * N)
            gy = int(((ay + by + cy) / 3.0) * N)
            if 0 <= gx < N and 0 <= gy < N:
                grid[gy * N + gx] += ar
        cell = 1.0 / (N * N)
        used = [g for g in grid if g > 0]
        over = [g for g in used if g > cell * 1.6]
        overlap = len(over) / max(1, len(used))
    # 스킨
    maxinf = 0
    badsum = 0
    nvg = len(ob.vertex_groups)
    bones = set(b.name for b in arm.data.bones) if arm else set()
    names = {vg.index: vg.name for vg in ob.vertex_groups}
    for v in me.vertices:
        ws = [(names[g.group], g.weight) for g in v.groups if g.weight > 1e-4]
        maxinf = max(maxinf, len(ws))
        s = sum(w for _, w in ws)
        if ws and abs(s - 1.0) > 0.02:
            badsum += 1
    unweighted = sum(1 for v in me.vertices if not [g for g in v.groups if g.weight > 1e-4])
    # 마스크 (팀 색 칸) = UV2.x (꼭짓점 단위, 0/1): 칸 비율과 '경계 삼각형' (세 꼭짓점이 갈린 삼각형 = 색 칸 경계가 삼각형 하나만큼 어긋나는 곳) 비율
    mask = None
    if len(me.uv_layers) > 1:  # 두 번째 UV 층 = UV2 (glTF 가져오면 이름이 바뀜)
        u2 = me.uv_layers[1].data
        vals = {}
        for p in me.polygons:
            for li in p.loop_indices:
                vals[me.loops[li].vertex_index] = u2[li].uv.x
        on = sum(1 for v in vals.values() if v > 0.5)
        mid = sum(1 for v in vals.values() if 0.05 < v < 0.95)
        split = 0
        on_tris = 0
        for p in me.polygons:
            vs = [vals[vi] > 0.5 for vi in p.vertices]
            if any(vs):
                on_tris += 1
            if any(vs) and not all(vs):
                split += 1
        mask = {"on_vert_frac": round(on / max(1, len(vals)), 4), "mid_vert_frac": round(mid / max(1, len(vals)), 4), "on_tris": on_tris,
                "boundary_tris": split, "boundary_frac_of_mask": round(split / max(1, on_tris), 4)}
    return {"tris": tris, "verts": len(me.vertices), "open_edges_raw": open_edges, "open_edges": open_welded, "nonmanifold_edges": nonman_welded, "sharp_flips": flipped,
            "uv_out_of_range": uv_oob, "uv_overlap_cells": round(overlap, 3), "max_influences": maxinf, "bad_weight_sum": badsum, "unweighted": unweighted,
            "vgroups": nvg, "mask": mask}


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    glb = a[0]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    arm = arm[0] if arm else None
    out = {"file": os.path.basename(glb), "bones": len(arm.data.bones) if arm else 0, "meshes": {}}
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH" and ob.name != "Icosphere":
            out["meshes"][ob.name] = audit_mesh(ob, arm)
    imgs = {}
    for im in bpy.data.images:
        imgs[im.name] = list(im.size)
    out["images"] = imgs
    s = json.dumps(out, ensure_ascii=False)
    print("TFA " + s)
    if len(a) > 1:
        open(a[1], "w").write(s)


main()
