# 닌자 목도리 꼬리 뼈 (W23): 몸 뒤로 늘어진 붉은 꼬리를 뼈 세 개 사슬 (mixamorig:Scarf1~3) 에 매어, 런타임이 줄처럼 흔들게 함 (chars/ext_cloth.gd).
# W21 은 꼬리를 몸통 뼈에 붙여서 늘 같은 모양으로 굳어 있었음 — 달리기·쓰러짐 (래그돌) 에서 뻣뻣해 보이던 까닭 중 하나.
# rig_ninja.py build 가 가중치 정리 뒤에 부름. 꼬리 = 몸 색 칸 (붉은) 꼭짓점 중 몸 뒤 (x < BACK_X) 로 늘어진 것.
import bpy
from mathutils import Vector

P = "mixamorig:"
BACK_X = -0.04  # 이보다 뒤 (원본 좌표, 앞 +X) 의 붉은 꼭짓점 = 꼬리
Z_TOP_CUT = 0.80  # 이보다 위는 목 둘레 (꼬리 아님)
N = 3


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def add_scarf(ob, arm, ring, key):
    me = ob.data
    tail = [v for v in me.vertices if key(v.co) in ring and v.co.x < BACK_X and v.co.z < Z_TOP_CUT]
    if len(tail) < 50:
        print("TF 목도리 꼬리 못 찾음", len(tail))
        return []
    zt = max(v.co.z for v in tail)
    zb = min(v.co.z for v in tail)
    # 사슬: 높이 N+1 단계마다 꼬리 꼭짓점의 평균 (x, y)
    joints = []
    for k in range(N + 1):
        z = zt - (zt - zb) * k / N
        near = [v.co for v in tail if abs(v.co.z - z) < (zt - zb) / N * 0.6]
        if not near:
            near = [min(tail, key=lambda v: abs(v.co.z - z)).co]
        joints.append(Vector((sum(c.x for c in near) / len(near), sum(c.y for c in near) / len(near), z)))
    # 맨 위는 목 뒤 (몸 가까이)
    names = [P + "Scarf%d" % (i + 1) for i in range(N)]
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    prev = eb[P + "Spine2"]
    for i, nm in enumerate(names):
        b = eb.new(nm)
        b.head = joints[i]
        b.tail = joints[i + 1]
        b.parent = prev
        b.use_connect = False
        prev = b
    bpy.ops.object.mode_set(mode="OBJECT")
    for nm in names:
        if nm not in ob.vertex_groups:
            ob.vertex_groups.new(name=nm)
    gi = {nm: ob.vertex_groups[nm] for nm in names}
    old_names = {g.index: g.name for g in ob.vertex_groups}
    span = max(1e-6, zt - zb)
    moved = 0
    for v in tail:
        s = (zt - v.co.z) / span * N  # 0 (위) ~ N (아래)
        a = smooth(0.0, 0.7, s)  # 위쪽은 원래 (몸통) 가중치와 섞임
        w = {}
        for i in range(N):
            hat = max(0.0, 1.0 - abs(s - (i + 0.5)))
            if s < 0.5 and i == 0:
                hat = 1.0
            if s > N - 0.5 and i == N - 1:
                hat = 1.0
            if hat > 0:
                w[names[i]] = hat
        tot = sum(w.values()) or 1.0
        old = {old_names[g.group]: g.weight for g in v.groups if old_names[g.group] not in gi}
        otot = sum(old.values()) or 1.0
        for g in list(v.groups):
            ob.vertex_groups[g.group].remove([v.index])
        for n2, val in old.items():
            if (1 - a) * val / otot > 0.002:
                ob.vertex_groups[n2].add([v.index], (1 - a) * val / otot, "REPLACE")
        for n2, val in w.items():
            if a * val / tot > 0.002:
                gi[n2].add([v.index], a * val / tot, "REPLACE")
        moved += 1
    print("TF 목도리 꼬리 뼈", names, "꼭짓점", moved, "높이 %.2f~%.2f" % (zb, zt))
    return names
