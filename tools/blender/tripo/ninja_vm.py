# 닌자 1인칭 팔 'ninja_vm' (W23): 원본 몸에서 아래팔·손 (소매·장갑) 을 팔꿈치 아래 평면으로 잘라 닫힌 메시로 만듦 — rig_ninja.py 가 build 끝에 부름.
# 예전 (W21) 은 로더가 '가장 센 뼈가 팔인 삼각형' 만 남겨서 팔꿈치 쪽 가장자리가 들쭉날쭉 열려 있었음 (가시·구멍·잘린 단면). 여기서는
#   ① 아래팔 축에 수직인 평면 (팔꿈치에서 CUT_T 만큼 손목 쪽) 으로 몸 전체를 자르고, 손이 든 덩어리만 남김 (이음선·가중치 섞임과 상관없는 깨끗한 단면)
#   ② 단면을 메우고, 끝을 조금 모아 (TAPER) 둥글게 닫음 — 화면 아래로 팔꿈치 끝이 보여도 구멍이 안 보임
#   ③ 좌우 팔을 한 오브젝트로, 같은 재질·UV·꼭짓점 색·가중치 (뼈 이름 그대로). 판 몸에선 안 그림 (로더 cfg vm_node)
import bpy
import bmesh
from mathutils import Vector

P = "mixamorig:"
CUT_T = 0.12  # 팔꿈치 → 손목 길이의 이 비율만큼 손목 쪽에서 자름 (팔꿈치 가중치 섞임을 피함)
TAPER = 0.55  # 끝 마개: 단면을 이만큼으로 오므림
CAP_LEN = 0.45  # 끝 마개 깊이 (단면 반지름 × 이 값)
THICK = 1.3  # 1인칭에선 팔·장갑을 아래팔 축에서 이만큼 부풀림 (코드 몸 1인칭 팔은 굵은 통, 모델 팔은 가늘어 화면에서 작아 보임 — 재혁 '크기 이상')


def _arm_groups(side):
    names = [P + side + "ForeArm", P + side + "Hand"]
    for f in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        for i in range(1, 5):
            names.append("%s%sHand%s%d" % (P, side, f, i))
    return set(names)


def _side(ob, arm, side, arm_only=False):
    """한쪽 팔: 새 bmesh (닫힌 아래팔 + 손), 못 만들면 None"""
    B = arm.data.bones
    elbow = Vector(B[P + side + "ForeArm"].head_local)
    wrist = Vector(B[P + side + "Hand"].head_local)
    ax = (wrist - elbow)
    ln = ax.length
    ax.normalize()
    p0 = elbow + ax * (ln * CUT_T)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)  # glTF 가져오기가 UV 이음선마다 꼭짓점을 둘로 나눔 → 합쳐야 이어진 덩어리를 찾음 (UV 는 모서리별이라 그대로)
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    r = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=p0, plane_no=ax, dist=1e-6, clear_inner=True, clear_outer=False)
    cut_edges = [e for e in r["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    # 손이 든 덩어리만 (손 뼈에 가장 센 꼭짓점에서 퍼짐)
    dl = bm.verts.layers.deform.active
    gi = ob.vertex_groups[P + side + "Hand"].index
    seed = None
    best = -1.0
    for v in bm.verts:
        w = v[dl].get(gi, 0.0)
        if w > best:
            best, seed = w, v
    ok = None
    if arm_only:  # 갈고리: 손이 벨트·코트에 닿아 이어져 있어서 (한 덩어리) 아래팔·손·손가락 뼈가 가장 센 꼭짓점만 (코트까지 번지지 않게)
        gnames = {ob.vertex_groups[P + n].index for n in [a[len(P):] for a in _arm_groups(side)]}
        ok = set()
        for v in bm.verts:
            if v[dl]:
                gi_top = max(v[dl].items(), key=lambda kv: kv[1])[0]
                if gi_top in gnames:
                    ok.add(v)
    keep = {seed}
    stack = [seed]
    while stack:
        v = stack.pop()
        for e in v.link_edges:
            o = e.other_vert(v)
            if o not in keep and (ok is None or o in ok):
                keep.add(o)
                stack.append(o)
    drop = [v for v in bm.verts if v not in keep]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    for v in bm.verts:  # 굵게: 아래팔 축 (팔꿈치 → 손목 연장선) 에서 바깥으로
        t = (v.co - elbow).dot(ax)
        a0 = elbow + ax * t
        v.co = a0 + (v.co - a0) * THICK
    # 단면 (경계 가장자리) 메우기
    bnd = [e for e in bm.edges if e.is_boundary]
    if not bnd:
        bm.free()
        return None
    # 경계가 여러 고리면 (손가락 사이 틈 등 원래 열린 곳) 단면 고리만: 평면 위 꼭짓점으로만 이뤄진 가장자리
    on_plane = [e for e in bnd if all(abs((v.co - p0).dot(ax)) < 1e-4 for v in e.verts)]
    res = bmesh.ops.holes_fill(bm, edges=on_plane, sides=64)
    if arm_only:  # 잘라낸 코트·벨트 자리 구멍도 메움 (손 아래 안쪽이라 화면엔 거의 안 보임)
        rest = [e for e in bm.edges if e.is_boundary and e not in on_plane]
        if rest:
            bmesh.ops.holes_fill(bm, edges=rest, sides=64)
    caps = res["faces"]
    # 둥근 끝: 마개 면을 팔꿈치 쪽 (-ax) 으로 밀어내며 오므림
    if caps:
        ext = bmesh.ops.extrude_face_region(bm, geom=caps)
        nv = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
        ctr = sum((v.co for v in nv), Vector()) / max(1, len(nv))
        rad = sum(((v.co - ctr).length for v in nv), 0.0) / max(1, len(nv))
        for v in nv:
            v.co = ctr + (v.co - ctr) * TAPER - ax * rad * CAP_LEN
        bmesh.ops.delete(bm, geom=caps, context="FACES_ONLY")  # 평평한 원래 마개는 지움 (오므린 마개가 닫음)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def make_vm(ob, arm, name="ninja_vm", arm_only=False):
    """닫힌 1인칭 팔 오브젝트 (이름 기본 'ninja_vm', 갈고리는 'hook_vm' — 좌우 한 메시). ob = 몸 (…_lod0), arm = 뼈대"""
    parts = []
    for side in ("Left", "Right"):
        bm = _side(ob, arm, side, arm_only)
        if bm is None:
            print("TF 1인칭 팔 못 만듦", side)
            continue
        parts.append(bm)
        print("TF 1인칭 팔", side, "삼각형 약", len(bm.faces))
    me = bpy.data.meshes.new(name)
    # 재질·UV·색 층은 clear_geometry 가 층 이름을 지우므로 bmesh 를 합쳐서 to_mesh
    big = bmesh.new()
    big.from_mesh(ob.data)
    big.clear()
    for bm in parts:
        tmp = bpy.data.meshes.new("_t")
        bm.to_mesh(tmp)
        bm.free()
        big.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    bmesh.ops.triangulate(big, faces=big.faces)
    big.to_mesh(me)
    big.free()
    for m in ob.data.materials:
        me.materials.append(m)
    vm = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(vm)
    for g in ob.vertex_groups:  # 뼈대 이름 (꼭짓점 그룹 이름은 메시 데이터에 있어서 새로 만듦, 번호 순서 그대로)
        vm.vertex_groups.new(name=g.name)
    md = vm.modifiers.new("Armature", "ARMATURE")
    md.object = arm
    vm.parent = arm
    vm.matrix_parent_inverse = ob.matrix_parent_inverse.copy()
    return vm
