# W19 Blender 캐릭터 제작 공통 (Blender 4.5, 화면 없이) — 고퀄 스타일화 (스매시 레전드 급 목표) 판.
# 실행 (레포 뿌리): blender -b --factory-startup -P tools/blender/build_character.py -- tank [--preview <폴더>] [--out <폴더>] [--parts] [--fast]
# 나오는 것 (<out> 기본 godot/client/assets/models/ext):
#   <id>.glb        몸 + 뼈대 (LOD 메시 4개 <id>_lod0..3 — 같은 뼈·같은 UV·같은 텍스처, 고도 external.gd 가 화면·화질로 하나만 그림)
#                   재질 2: <id> (구운 알베도 아틀라스 + 몸 색 칸 표시 UV2) · <id>_face (얼굴 텍스처, 외곽선 없음)
#   <id>_<소품>.glb 방패 등 따로 (자기 구운 텍스처)
#   <id>_face_<표정>.png  얼굴 표정 (idle·hit·attack — 고도가 albedo_tex 를 바꿔 끼움)
#   <id>.json       고도 조정 값 + 통계
# 흐름: 부품 (낮은 우리 → 서브디비전 2 → 매끈) → 가중치 → 합치기 → UV 펼침 → Cycles 굽기 (색 + AO + 위쪽 빛 + 모서리 빛 + 쇠 광택 띠 + 붓 얼룩)
#       → 얼굴 (평면 투영 UV, 손칠 텍스처) → LOD (Decimate) → 내보내기
# 좌표: 부품은 게임 좌표 (앞 +x, 왼쪽 +y, 위 +z, m, 발바닥 0), Blender 로는 (X, Y, Z) = (y, -x, z) (glTF 앞 +Z)
import bpy
import bmesh
import json
import math
import os
import sys
import importlib.util

sys.dont_write_bytecode = True
from mathutils import Vector, Matrix, Euler, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
if __name__ == "__main__":  # chars/<id>.py 가 import build_character 하면 이 모듈 (LOOKS 하나) 을 받게
    sys.modules.setdefault("build_character", sys.modules[__name__])
import face_paint  # noqa: E402

JOINTS = ["hips", "waist", "torso", "neck", "shoulder_R", "elbow_R", "hand_R", "shoulder_L", "elbow_L", "hand_L",
          "thigh_R", "knee_R", "foot_R", "thigh_L", "knee_L", "foot_L"]
PARENT = {"waist": "hips", "torso": "waist", "neck": "torso", "shoulder": "torso", "elbow": "shoulder", "hand": "elbow",
          "thigh": "hips", "knee": "thigh", "foot": "knee"}
CHILD = {"hips": "waist", "waist": "torso", "torso": "neck", "shoulder": "elbow", "elbow": "hand", "thigh": "knee", "knee": "foot"}
G2B = Matrix(((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))  # 게임 → Blender

# LOD (몸 삼각형 목표): lod0 = 대기실 큰 캐릭터·초상·1인칭 팔 (한 명만 크게), lod1 = 판 화질 높음, lod2 = 보통, lod3 = 낮음
LOD_TRIS = {"lod0": 38000, "lod1": 17000, "lod2": 10000, "lod3": 6000}
ATLAS = 1024
FACE_PX = 512
PREVIEW_TINT = 0xd94a3a  # 미리보기에서만 몸 색 칸 색 (게임에선 플레이어 색을 곱함)


def G(x, y=None, z=None):
    if y is None:
        x, y, z = x
    return Vector((y, -x, z))


def GDIR(v):
    return G(v[0], v[1], v[2])


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h):
    return ((h >> 16 & 255) / 255.0, (h >> 8 & 255) / 255.0, (h & 255) / 255.0)


def lin(h):
    return [srgb_to_lin(c) for c in hexcol(h)] + [1.0]


# ---------- 재질 '느낌' (굽기 노드 값) ----------
# kind: metal (쇠·금 — 광택 띠·센 모서리 빛) · cloth (천 — 부드러운 그늘·붓 얼룩) · skin · tint (몸 색 칸: 밝은 회백 → 고도가 플레이어 색을 곱함)
LOOKS = {}


def look(name, color, kind="cloth", **kw):
    LOOKS[name] = dict(color=color, kind=kind, **kw)


# ---------- 부품 ----------

class Kit:
    """캐릭터 하나를 만드는 도구 상자. chars/<id>.py 의 build(k) 가 씀. 부품은 낮은 우리 (cage) 를 서브디비전해서 매끈하게"""

    def __init__(self, char_id, rig, sub=2):
        self.id = char_id
        self.rig = rig
        self.sub = sub
        self.J = {j: Vector(rig["joints"][j]["pos"]) for j in JOINTS}
        self.parts = []  # [{obj, bone, blend, look, prop, face}]
        self.props = {}

    def j(self, name):
        return self.J[name].copy()

    # -- 마무리: 두께·서브디비전 적용, 매끈 음영
    def _obj(self, name, bm):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob

    def _finish(self, name, bm, look_, bone, sub=None, thick=None, fit=None, blend=None, prop=None, face=None, crease=None):
        ob = self._obj(name, bm)
        if crease:
            # 날카롭게 남길 모서리 (서브디비전 주름): bmesh 에서 표시한 edge 의 crease 속성
            pass
        if thick:
            m = ob.modifiers.new("solid", "SOLIDIFY")
            m.thickness = thick
            m.offset = -1.0
            m.use_even_offset = True
            m.use_rim = True
        lv = self.sub if sub is None else sub
        if lv > 0:
            m = ob.modifiers.new("sub", "SUBSURF")
            m.levels = lv
            m.render_levels = lv
            m.uv_smooth = "PRESERVE_BOUNDARIES"
        _apply_mods(ob)
        if fit is not None:  # 서브디비전으로 줄어든 크기를 원래 상자 (게임 좌표 중심·반지름) 로
            c, r = fit
            vs = [v.co for v in ob.data.vertices]
            lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
            hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
            mid = (lo + hi) / 2
            want = Vector(r)
            have = (hi - lo) / 2
            for v in ob.data.vertices:
                d = v.co - mid
                v.co = mid + Vector((d.x * want.x / max(1e-6, have.x), d.y * want.y / max(1e-6, have.y), d.z * want.z / max(1e-6, have.z)))
        for p in ob.data.polygons:
            p.use_smooth = True
        rec = {"obj": ob, "bone": bone, "blend": blend, "look": look_, "prop": prop, "face": face}
        if prop is None:
            self.parts.append(rec)
        else:
            self.props.setdefault(prop, []).append(rec)
        return ob

    @staticmethod
    def _xf(pos, rot, scale):
        sx, sy, sz = scale if isinstance(scale, (tuple, list)) else (scale,) * 3
        return Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4() \
            @ Matrix.Diagonal((sx, sy, sz, 1.0))

    def _place(self, bm, pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
        bm.transform(G2B @ self._xf(pos, rot, scale))

    def blob(self, name, pos, radii, look_, bone, rot=(0, 0, 0), cuts=1, **kw):
        """둥근 덩어리: 정육면체 우리를 구로 부풀림 → 서브디비전 (극점 없는 매끈한 구·타원)"""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=2.0)
        if cuts:
            bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=cuts, use_grid_fill=True)
        for v in bm.verts:
            v.co = v.co.normalized()
        # 축척 전 우리를 조금 크게 (서브디비전이 줄임) — fit 로 정확히 맞춤
        sc = Vector(radii)
        self._place(bm, pos, rot, (sc.x, sc.y, sc.z))
        ob = self._finish(name, bm, look_, bone, **kw)
        if rot == (0, 0, 0):  # 축 정렬이면 상자로 정확히 맞춤
            c = G(pos)
            rb = Vector((radii[1], radii[0], radii[2]))
            _fit(ob, c, rb)
        return ob

    def rbox(self, name, pos, size, look_, bone, rot=(0, 0, 0), round_=0.35, **kw):
        """둥근 상자: 모서리 깎은 상자 우리 → 서브디비전 (round_ = 짧은 변 대비 둥근 정도)"""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        off = min(size) * round_ * 0.5
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=off, segments=1, profile=0.5, affect="EDGES", clamp_overlap=True)
        self._place(bm, pos, rot)
        return self._finish(name, bm, look_, bone, **kw)

    def sweep(self, name, pts, radii, look_, bone, sides=8, up=(0, 0, 1), caps=True, **kw):
        """꺾은선 pts (게임 좌표) 를 따라 타원 단면 관 (radii = [(가로, 세로)] 점마다, 세로 = up 쪽). 끝은 둥근 마개"""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        bm = bmesh.new()
        rings = []
        upv = Vector(up)
        for i, p in enumerate(pts):
            t = (pts[min(n - 1, i + 1)] - pts[max(0, i - 1)]).normalized()
            side = t.cross(upv)
            if side.length < 1e-4:
                side = t.cross(Vector((1, 0, 0)))
            side.normalize()
            vup = side.cross(t).normalized()
            rw, rh = radii[i]
            ring = []
            for k in range(sides):
                a = 2 * math.pi * k / sides
                ring.append(bm.verts.new(p + side * math.cos(a) * rw + vup * math.sin(a) * rh))
            rings.append((ring, t, p))
        for i in range(n - 1):
            r0, r1 = rings[i][0], rings[i + 1][0]
            for k in range(sides):
                bm.faces.new((r0[k], r1[k], r1[(k + 1) % sides], r0[(k + 1) % sides]))
        if caps:
            for (ring, t, p), sgn, rr in ((rings[0], -1, radii[0]), (rings[-1], 1, radii[-1])):
                tip = bm.verts.new(p + t * sgn * min(rr) * 0.75)
                for k in range(sides):
                    a, b = ring[k], ring[(k + 1) % sides]
                    bm.faces.new((a, b, tip) if sgn > 0 else (b, a, tip))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        self._place(bm)
        return self._finish(name, bm, look_, bone, **kw)

    def torus(self, name, pos, R, r, look_, bone, rot=(0, 0, 0), scale=(1, 1, 1), seg=16, ring=6, arc=None, **kw):
        """고리 (축 = 게임 z), scale 로 타원. arc = (시작, 끝 각) 이면 호만 (끝 막음)"""
        bm = bmesh.new()
        vs = []
        cnt = seg if arc is None else seg + 1
        for i in range(cnt):
            a = 2 * math.pi * i / seg if arc is None else arc[0] + (arc[1] - arc[0]) * i / seg
            row = []
            for k in range(ring):
                b = 2 * math.pi * k / ring
                rr = R + r * math.cos(b)
                row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b))))
            vs.append(row)
        for i in range(seg):
            for k in range(ring):
                a0, a1 = vs[i], vs[(i + 1) % cnt]
                bm.faces.new((a0[k], a1[k], a1[(k + 1) % ring], a0[(k + 1) % ring]))
        if arc is not None:
            bm.faces.new(vs[0])
            bm.faces.new(list(reversed(vs[-1])))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.transform(G2B @ self._xf(pos, rot, scale))
        return self._finish(name, bm, look_, bone, **kw)

    def disk(self, name, pos, r, h, look_, bone, rot=(0, 0, 0), seg=16, edge=0.25, **kw):
        """두툼한 원판 (축 = 게임 z): 윗·아랫 면 가장자리에 고리를 더 둬서 서브디비전 뒤에도 모서리가 살아 있음"""
        bm = bmesh.new()
        rings = [(r * (1 - edge * 0.6), h / 2), (r, h / 2 * (1 - edge)), (r, -h / 2 * (1 - edge)), (r * (1 - edge * 0.6), -h / 2)]
        vs = []
        for rr, z in rings:
            vs.append([bm.verts.new((rr * math.cos(2 * math.pi * k / seg), rr * math.sin(2 * math.pi * k / seg), z)) for k in range(seg)])
        for i in range(len(vs) - 1):
            for k in range(seg):
                bm.faces.new((vs[i][k], vs[i + 1][k], vs[i + 1][(k + 1) % seg], vs[i][(k + 1) % seg]))
        top = bm.verts.new((0, 0, h / 2))
        bot = bm.verts.new((0, 0, -h / 2))
        for k in range(seg):
            bm.faces.new((vs[0][(k + 1) % seg], vs[0][k], top))
            bm.faces.new((vs[-1][k], vs[-1][(k + 1) % seg], bot))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.transform(G2B @ self._xf(pos, rot, (1, 1, 1)))
        return self._finish(name, bm, look_, bone, **kw)

    def shell(self, name, pos, radii, look_, bone, keep, thick=0.03, rot=(0, 0, 0), cuts=2, **kw):
        """구 껍데기 (갑옷 판·투구): 정육면체 구 우리에서 keep(단위 구 위 점) 이 참인 면만, 두께 → 서브디비전 (가장자리 둥근 두께)"""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=2.0)
        bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=cuts, use_grid_fill=True)
        for v in bm.verts:
            v.co = v.co.normalized()
        dead = [f for f in bm.faces if not keep(f.calc_center_median().normalized())]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        # 서브디비전이 줄이는 만큼 우리를 키움
        bm.transform(G2B @ self._xf(pos, rot, tuple(r * 1.06 for r in radii)))
        return self._finish(name, bm, look_, bone, thick=thick, **kw)

    def panel(self, name, center, z_top, length, r_top, r_bot, ang, width, look_, bone, depth=1.0, thick=0.025,
              seg=4, rows=2, round_bottom=0.0, **kw):
        """늘어진 천·판 (원뿔 껍데기 조각): ang = 가운데 방향 (0 = 앞 +x), width = 각, 아래로 벌어짐, 두께 안쪽"""
        bm = bmesh.new()
        grid = []
        for ri in range(rows + 1):
            t = ri / rows
            z = z_top - length * t
            rr = r_top + (r_bot - r_top) * t
            row = []
            for i in range(seg + 1):
                u = i / seg
                a = ang - width / 2 + width * u
                zz = z + (round_bottom * (abs(u - 0.5) * 2) ** 2 if ri == rows and round_bottom > 0 else 0)
                row.append(bm.verts.new((center[0] + math.cos(a) * rr * depth, center[1] + math.sin(a) * rr, zz)))
            grid.append(row)
        for ri in range(rows):
            for i in range(seg):
                bm.faces.new((grid[ri][i], grid[ri + 1][i], grid[ri + 1][i + 1], grid[ri][i + 1]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        f0 = bm.faces[0]
        c = f0.calc_center_median()
        if f0.normal.dot(Vector((c.x - center[0], c.y - center[1], 0))) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
        self._place(bm)
        return self._finish(name, bm, look_, bone, thick=thick, **kw)

    def star(self, name, pos, r, h, look_, bone, rot=(0, 0, 0), points=5, inner=0.48, **kw):
        """별 (축 = 게임 z, 두께 h): 서브디비전으로 끝이 둥근 별"""
        bm = bmesh.new()
        n = points * 2
        top, bot = [], []
        for i in range(n):
            a = math.pi / 2 + 2 * math.pi * i / n
            rr = r if i % 2 == 0 else r * inner
            top.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), h / 2)))
            bot.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), -h / 2)))
        ct = bm.verts.new((0, 0, h / 2 + h * 0.3))
        cb = bm.verts.new((0, 0, -h / 2))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((top[i], top[j], ct))
            bm.faces.new((bot[j], bot[i], cb))
            bm.faces.new((top[j], top[i], bot[i], bot[j]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.transform(G2B @ self._xf(pos, rot, (1, 1, 1)))
        return self._finish(name, bm, look_, bone, sub=1, **kw)

    def mirror(self, fn):
        for side, sign in (("R", -1), ("L", 1)):
            fn(side, sign)


def _fit(ob, c, r):
    vs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    mid = (lo + hi) / 2
    have = (hi - lo) / 2
    for v in ob.data.vertices:
        d = v.co - mid
        v.co = c + Vector((d.x * r.x / max(1e-6, have.x), d.y * r.y / max(1e-6, have.y), d.z * r.z / max(1e-6, have.z)))


def _apply_mods(ob):
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def _select(objs, active=None):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


# ---------- 뼈대·가중치 (예전 그대로) ----------

def make_armature(k, name):
    J = k.J
    arm = bpy.data.armatures.new(name + "_rig")
    ob = bpy.data.objects.new(name + "_rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    _select([ob])
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for jn in JOINTS:
        base = jn.split("_")[0]
        side = jn[len(base):]
        b = arm.edit_bones.new(jn)
        b.head = G(J[jn])
        c = CHILD.get(base)
        if c is not None:
            b.tail = G(J[c + (side if c in ("elbow", "hand", "knee", "foot") else "")])
        elif base == "neck":
            b.tail = G(J[jn] + Vector((0, 0, 0.3)))
        elif base == "hand":
            d = J[jn] - J["elbow" + side]
            b.tail = G(J[jn] + d.normalized() * 0.1)
        elif base == "foot":
            b.tail = G(J[jn] + Vector((0.15, 0, -0.05)))
        if (b.tail - b.head).length < 1e-3:
            b.tail = b.head + Vector((0, 0, 0.05))
        b.roll = 0.0
        b.use_deform = True
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


def skin_parts(recs, arm):
    """딱딱한 부품 = 뼈 하나 1.0, blend 부품 = 그 부품만 자동 가중치 뒤 허락 뼈만 (정점당 3, 정규화)"""
    fails = []
    for rec in recs:
        ob = rec["obj"]
        for n in JOINTS:
            ob.vertex_groups.new(name=n)
        allow = rec["blend"]
        if allow:
            _select([ob, arm], arm)
            bpy.ops.object.parent_set(type="ARMATURE_AUTO")
            ob.parent = None
            for m in list(ob.modifiers):
                ob.modifiers.remove(m)
            if not _clean_weights(ob, allow, rec["bone"]):
                fails.append(ob.name)
        else:
            ob.vertex_groups[rec["bone"]].add(range(len(ob.data.vertices)), 1.0, "REPLACE")
    return fails


def _clean_weights(ob, allow, owner, limit=3, floor=0.04):
    idx = {vg.index: vg.name for vg in ob.vertex_groups}
    gi = {vg.name: vg.index for vg in ob.vertex_groups}
    any_auto = False
    for v in ob.data.vertices:
        w = {idx[g.group]: g.weight for g in v.groups if idx[g.group] in allow and g.weight > floor}
        if w:
            any_auto = True
        top = sorted(w.items(), key=lambda t: -t[1])[:limit]
        s = sum(x for _, x in top)
        for g in list(v.groups):
            ob.vertex_groups[g.group].remove([v.index])
        if s <= 0:
            ob.vertex_groups[gi[owner]].add([v.index], 1.0, "REPLACE")
        else:
            for n, x in top:
                ob.vertex_groups[gi[n]].add([v.index], x / s, "REPLACE")
    return any_auto


def join(objs, name):
    _select(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def bind(ob, arm):
    ob.parent = arm
    m = ob.modifiers.new("rig", "ARMATURE")
    m.object = arm


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# ---------- 색 칸 표시·UV ----------

def mark(ob, tint):
    """꼭짓점 색 하양 (COLOR_0 — 고도 툰 셰이더 use_vertex_color 로 몸 색 칸을 읽음) + 둘째 UV x = 1 이면 몸 색 칸"""
    me = ob.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for d in me.color_attributes["Col"].data:
        d.color = (1, 1, 1, 1)
    while len(me.uv_layers) < 2:
        me.uv_layers.new(name="UVMap" if len(me.uv_layers) == 0 else "Skin")
    for d in me.uv_layers[1].data:
        d.uv = (1.0 if tint else 0.0, 0.0)
    me.uv_layers.active_index = 0


def face_uv(ob, k):
    """얼굴: 정면 평면 투영 (머리 가운데 기준, 얼굴 텍스처 칸 [-1,1]) — 뒤쪽 면은 맨살 구석 (0.02, 0.02)"""
    fc = k.face_frame  # (가운데 게임 좌표, 반 폭 y, 반 높이 z)
    c, W, H = fc
    me = ob.data
    uv = me.uv_layers[0].data
    for p in me.polygons:
        cen = Vector((0, 0, 0))
        for li in p.loop_indices:
            cen += me.vertices[me.loops[li].vertex_index].co
        cen /= len(p.loop_indices)
        gx = -cen.y  # Blender → 게임 x
        front = gx > c.x + 0.02
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            gy, gz = co.x, co.z
            if front:
                uv[li].uv = (0.5 + (gy - c.y) / (2 * W), 0.5 + (gz - c.z) / (2 * H))
            else:
                uv[li].uv = (0.02, 0.02)


# ---------- 굽기 ----------

def bake_material(name, lk, target_img, preview_tint=False):
    """Cycles 굽기용 발광 재질: 색 × AO × 위쪽 빛 + 모서리 빛 + (쇠) 광택 띠 + 붓 얼룩"""
    m = bpy.data.materials.new("bake_" + name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    N = nt.nodes.new
    L = nt.links.new
    out = N("ShaderNodeOutputMaterial")
    em = N("ShaderNodeEmission")
    L(em.outputs[0], out.inputs[0])
    kind = lk["kind"]
    col = lk["color"]
    if kind == "tint":
        col = PREVIEW_TINT if preview_tint else 0xeeeeee
    base = N("ShaderNodeRGB")
    base.outputs[0].default_value = lin(col)
    geo = N("ShaderNodeNewGeometry")
    ao = N("ShaderNodeAmbientOcclusion")
    ao.samples = 12
    ao.inputs["Distance"].default_value = lk.get("ao_dist", 0.12)
    # AO → 0.5..1
    aof = N("ShaderNodeMapRange")
    aof.inputs["From Min"].default_value = 0.0
    aof.inputs["From Max"].default_value = 1.0
    aof.inputs["To Min"].default_value = lk.get("ao_min", 0.5)
    aof.inputs["To Max"].default_value = 1.0
    L(ao.outputs["AO"], aof.inputs["Value"])
    # 위쪽 빛: 법선 z → 0.86..1.1
    sep = N("ShaderNodeSeparateXYZ")
    L(geo.outputs["Normal"], sep.inputs[0])
    up = N("ShaderNodeMapRange")
    up.inputs["From Min"].default_value = -1.0
    up.inputs["From Max"].default_value = 1.0
    up.inputs["To Min"].default_value = 0.84
    up.inputs["To Max"].default_value = 1.12
    L(sep.outputs["Z"], up.inputs["Value"])
    # 붓 얼룩 (천·피부는 조금 더)
    nz = N("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 9.0
    nz.inputs["Detail"].default_value = 2.0
    nzr = N("ShaderNodeMapRange")
    amt = 0.08 if kind in ("cloth", "tint", "leather") else 0.04
    nzr.inputs["From Min"].default_value = 0.3
    nzr.inputs["From Max"].default_value = 0.7
    nzr.inputs["To Min"].default_value = 1 - amt
    nzr.inputs["To Max"].default_value = 1 + amt
    L(nz.outputs["Fac"], nzr.inputs["Value"])
    m1 = N("ShaderNodeMath")
    m1.operation = "MULTIPLY"
    L(aof.outputs[0], m1.inputs[0])
    L(up.outputs[0], m1.inputs[1])
    m2 = N("ShaderNodeMath")
    m2.operation = "MULTIPLY"
    L(m1.outputs[0], m2.inputs[0])
    L(nzr.outputs[0], m2.inputs[1])
    shade = N("ShaderNodeMix")
    shade.data_type = "RGBA"
    shade.blend_type = "MULTIPLY"
    shade.inputs["Factor"].default_value = 1.0
    L(base.outputs[0], shade.inputs[6])
    comb = N("ShaderNodeCombineXYZ")
    L(m2.outputs[0], comb.inputs[0])
    L(m2.outputs[0], comb.inputs[1])
    L(m2.outputs[0], comb.inputs[2])
    L(comb.outputs[0], shade.inputs[7])
    # 모서리 빛 (볼록한 곳 — pointiness) + 쇠 광택 띠 (법선 z 0.15..0.55)
    pt = N("ShaderNodeMapRange")
    pt.inputs["From Min"].default_value = lk.get("edge_from", 0.52)
    pt.inputs["From Max"].default_value = lk.get("edge_to", 0.6)
    pt.inputs["To Min"].default_value = 0.0
    pt.inputs["To Max"].default_value = lk.get("edge", 0.35 if kind == "metal" else 0.15)
    L(geo.outputs["Pointiness"], pt.inputs["Value"])
    hl = pt
    if kind == "metal":
        band = N("ShaderNodeMapRange")
        band.interpolation_type = "SMOOTHSTEP"
        band.inputs["From Min"].default_value = 0.0
        band.inputs["From Max"].default_value = 0.22
        band.inputs["To Min"].default_value = lk.get("band", 0.45)
        band.inputs["To Max"].default_value = 0.0
        dz = N("ShaderNodeMath")
        dz.operation = "ABSOLUTE"
        sub = N("ShaderNodeMath")
        sub.operation = "SUBTRACT"
        L(sep.outputs["Z"], sub.inputs[0])
        sub.inputs[1].default_value = 0.42
        L(sub.outputs[0], dz.inputs[0])
        L(dz.outputs[0], band.inputs["Value"])
        add = N("ShaderNodeMath")
        add.operation = "ADD"
        L(pt.outputs[0], add.inputs[0])
        L(band.outputs[0], add.inputs[1])
        # 아래 보는 면은 어둡게 (쇠 반사 느낌)
        hl = add
    light = N("ShaderNodeMix")
    light.data_type = "RGBA"
    light.blend_type = "ADD"
    L(hl.outputs[0], light.inputs["Factor"])
    L(shade.outputs[2], light.inputs[6])
    lc = N("ShaderNodeRGB")
    lc.outputs[0].default_value = lin(lk.get("hi", 0xffffff))
    L(lc.outputs[0], light.inputs[7])
    L(light.outputs[2], em.inputs["Color"])
    im = N("ShaderNodeTexImage")
    im.image = target_img
    nt.nodes.active = im
    return m


def bake_atlas(ob, img, recs_by_slot, preview_tint=False):
    """ob 의 재질 칸마다 굽기 재질 → EMIT 굽기 → img"""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 16
    sc.render.bake.margin = 6
    sc.render.bake.use_clear = True
    # 재질 칸을 제자리에서 바꿈 (clear 하면 면의 재질 번호가 0 으로 돌아감)
    for i, (nm, lk) in enumerate(recs_by_slot):
        ob.data.materials[i] = bake_material(nm, lk, img, preview_tint)
    _select([ob])
    bpy.ops.object.bake(type="EMIT", margin=6, use_clear=True)


def export_material(name, img):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def new_image(name, n):
    im = bpy.data.images.new(name, n, n, alpha=False)
    im.colorspace_settings.name = "sRGB"
    return im


def save_png(img, path):
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()


# ---------- 몸 하나 만들기 (부품 → 합침 → 굽기 → 얼굴 → LOD) ----------

def build_body(k, cid, out, preview_tint=False, fast=False):
    arm = make_armature(k, cid)
    body_recs = [r for r in k.parts if not r["face"]]
    face_recs = [r for r in k.parts if r["face"]]
    for r in k.parts:
        mark(r["obj"], LOOKS[r["look"]]["kind"] == "tint")
    fails = skin_parts(k.parts, arm)
    # 재질 칸 = look 마다 하나 (굽기 뒤 하나로 바꿈)
    looks = []
    for r in body_recs:
        if r["look"] not in looks:
            looks.append(r["look"])
        r["obj"].data.materials.clear()
        for lname in looks:
            pass
    slot = {n: i for i, n in enumerate(looks)}
    for r in body_recs:
        me = r["obj"].data
        for lname in looks:
            me.materials.append(bpy.data.materials.get("slot_" + lname) or bpy.data.materials.new("slot_" + lname))
        for p in me.polygons:
            p.material_index = slot[r["look"]]
    body = join([r["obj"] for r in body_recs], cid + "_body")
    # UV 펼치기 (몸 전체 한 장)
    _select([body])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.004, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    atlas = new_image(cid + "_atlas", ATLAS if not fast else 256)
    bake_atlas(body, atlas, [(n, LOOKS[n]) for n in looks], preview_tint)
    body.data.materials.clear()
    body.data.materials.append(export_material(cid, atlas))
    for p in body.data.polygons:
        p.material_index = 0
    # 얼굴: 평면 투영 UV + 표정 텍스처 (기본을 재질에, 셋 다 PNG)
    faces = {}
    for kind in ("idle", "hit", "attack"):
        im = new_image("%s_face_%s" % (cid, kind), FACE_PX)
        im.pixels = face_paint.paint_face(kind, FACE_PX).ravel()
        faces[kind] = im
    if face_recs:
        fo = join([r["obj"] for r in face_recs], cid + "_faceobj")
        face_uv(fo, k)
        fo.data.materials.clear()
        fo.data.materials.append(export_material(cid + "_face", faces["idle"]))
        body = join([body, fo], cid + "_body")
    bind(body, arm)
    # LOD: 같은 몸을 Decimate (UV·가중치·몸 색 칸 그대로)
    full = tri_count(body)
    lods = {}
    for ln, target in LOD_TRIS.items():
        _select([body])
        bpy.ops.object.duplicate()
        lo = bpy.context.view_layer.objects.active
        lo.name = "%s_%s" % (cid, ln)
        lo.data.name = lo.name
        for m in list(lo.modifiers):
            lo.modifiers.remove(m)
        if full > target:
            d = lo.modifiers.new("dec", "DECIMATE")
            d.ratio = target / full
            d.use_collapse_triangulate = True
            _apply_mods(lo)
        bind(lo, arm)
        lods[ln] = lo
    body.hide_render = True
    body.hide_set(True)
    return {"arm": arm, "body": body, "lods": lods, "atlas": atlas, "faces": faces, "fails": fails, "full": full}


def preview_tint_swap(res, props, fast):
    """미리보기용: 몸 색 칸을 빨강으로 구운 아틀라스를 만들어 내보내기 재질에 잠깐 끼움 → [(재질, 원래 그림)]"""
    out = []
    objs = [res["lods"]["lod0"]] + list(props.values())
    for ob in objs:
        mat = ob.data.materials[0]
        tex = mat.node_tree.nodes["Image Texture"]
        orig = tex.image
        n = orig.size[0]
        img = new_image(orig.name + "_preview", n)
        # 굽기 재질 칸 다시: 재질 칸 번호를 look 별로 돌려놓을 수 없으니 Skin UV (몸 색 칸) 로 칠함: 원래 그림 × 빨강 (몸 색 칸 면만)
        import numpy as np
        px = np.array(orig.pixels[:], dtype=np.float32).reshape(n, n, 4)
        mask = np.zeros((n, n), dtype=bool)
        me = ob.data
        uv0, uv1 = me.uv_layers[0].data, me.uv_layers[1].data
        for p in me.polygons:
            if uv1[p.loop_indices[0]].uv[0] > 0.5:
                us = [uv0[li].uv for li in p.loop_indices]
                x0 = int(max(0, min(u[0] for u in us) * n - 2))
                x1 = int(min(n, max(u[0] for u in us) * n + 2))
                y0 = int(max(0, min(u[1] for u in us) * n - 2))
                y1 = int(min(n, max(u[1] for u in us) * n + 2))
                mask[y0:y1, x0:x1] = True
        tint = np.array([srgb_to_lin(c) for c in hexcol(PREVIEW_TINT)] + [1.0], dtype=np.float32)
        px2 = px.copy()
        px2[mask] = px[mask] * tint
        img.pixels = px2.ravel()
        tex.image = img
        out.append((mat, orig))
    return out


def build_prop(k, cid, pn, recs, fast=False, preview_tint=False):
    for r in recs:
        mark(r["obj"], LOOKS[r["look"]]["kind"] == "tint")
    looks = []
    for r in recs:
        if r["look"] not in looks:
            looks.append(r["look"])
    slot = {n: i for i, n in enumerate(looks)}
    for r in recs:
        me = r["obj"].data
        me.materials.clear()
        for lname in looks:
            me.materials.append(bpy.data.materials.get("slot_" + lname) or bpy.data.materials.new("slot_" + lname))
        for p in me.polygons:
            p.material_index = slot[r["look"]]
    po = join([r["obj"] for r in recs], "%s_%s" % (cid, pn))
    _select([po])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.006, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = new_image("%s_%s_atlas" % (cid, pn), 512 if not fast else 128)
    bake_atlas(po, img, [(n, LOOKS[n]) for n in looks], preview_tint)
    po.data.materials.clear()
    po.data.materials.append(export_material("%s_%s" % (cid, pn), img))
    return po


# ---------- 내보내기 ----------

def export_glb(path, objs):
    _select(objs)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_texcoords=True, export_normals=True, export_tangents=False,
                              export_materials="EXPORT", export_image_format="JPEG", export_jpeg_quality=92,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_skins=True, export_influence_nb=4, export_def_bones=False, export_leaf_bone=False,
                              export_animations=False, export_morph=False, export_attributes=False,
                              export_extras=False, export_cameras=False, export_lights=False)


# ---------- 미리보기 (Workbench 텍스처 색 + 외곽선) ----------

def _cam(scene, target, yaw_deg, pitch_deg, dist, ortho):
    cam = bpy.data.objects.get("tf_cam")
    if cam is None:
        cam = bpy.data.objects.new("tf_cam", bpy.data.cameras.new("tf_cam"))
        scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    eye = Vector(target) + Vector((math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch))) * dist
    pos, tgt = G(eye), G(Vector(target))
    cam.location = pos
    cam.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def render_setup(scene, res=480):
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_object_outline = True
    sh.object_outline_color = (0.12, 0.08, 0.12)
    sh.show_cavity = False
    sh.show_shadows = False
    sh.show_specular_highlight = False
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.78, 0.82, 0.88)
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"


def pose_bones(arm, pose):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    order = {n: i for i, n in enumerate(JOINTS)}
    for name, axis, deg in sorted(pose, key=lambda t: order[t[0]]):
        pb = arm.pose.bones[name]
        head = pb.matrix.to_translation()
        R = Matrix.Translation(head) @ Matrix.Rotation(math.radians(deg), 4, GDIR(axis).normalized()) @ Matrix.Translation(-head)
        pb.matrix = R @ pb.matrix
        bpy.context.view_layer.update()


def contact_sheet(paths, cols, out):
    import numpy as np
    imgs = [bpy.data.images.load(p) for p in paths]
    w, h = imgs[0].size
    rows = (len(imgs) + cols - 1) // cols
    sheet = np.ones((rows * h, cols * w, 4), dtype=np.float32)
    for i, im in enumerate(imgs):
        px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
        r, c = i // cols, i % cols
        y0 = (rows - 1 - r) * h
        sheet[y0:y0 + h, c * w:(c + 1) * w] = px
    out_im = bpy.data.images.new("sheet", cols * w, rows * h, alpha=True)
    out_im.pixels = sheet.ravel()
    out_im.filepath_raw = out
    out_im.file_format = "PNG"
    out_im.save()


def render_previews(scene, k, res, props, mod, outdir, cid, lod="lod0"):
    os.makedirs(outdir, exist_ok=True)
    render_setup(scene)
    arm = res["arm"]
    for ln, lo in res["lods"].items():
        lo.hide_render = ln != lod
    shows = getattr(mod, "PREVIEW_PROPS", {})
    for pn, po in props.items():
        if pn in shows:
            jn, pos, rot = shows[pn]
            po.parent = arm
            po.parent_type = "BONE"
            po.parent_bone = jn
            bpy.context.view_layer.update()
            world = G2B @ Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4() \
                @ Matrix.Diagonal((k.rig["figure_scale"],) * 3 + (1,)) @ G2B.inverted()
            po.matrix_world = world
        else:
            po.hide_render = True
    c = Vector((0, 0, 1.02))
    shots = []
    for nm, yaw, pitch in (("front", 0, 6), ("q34", 35, 10), ("side", 90, 4), ("back", 180, 10)):
        pose_bones(arm, [])
        _cam(scene, c, yaw, pitch, 6, 2.5)
        p = os.path.join(outdir, "%s_%s.png" % (cid, nm))
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        shots.append(p)
    head = k.face_frame[0].copy()
    for nm, yaw in (("face", 12), ("face34", 40)):
        pose_bones(arm, [])
        _cam(scene, head, yaw, 4, 4, 0.8)
        p = os.path.join(outdir, "%s_%s.png" % (cid, nm))
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        shots.append(p)
    for nm, pose in getattr(mod, "PREVIEW_POSES", {}).items():
        pose_bones(arm, pose)
        _cam(scene, c, 35, 12, 6, 2.6)
        p = os.path.join(outdir, "%s_pose_%s.png" % (cid, nm))
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        shots.append(p)
    pose_bones(arm, [])
    contact_sheet(shots, 4, os.path.join(outdir, "%s_sheet.png" % cid))
    for pn, po in props.items():
        po.parent = None
        po.matrix_world = Matrix.Identity(4)
        po.hide_render = False
    for lo in res["lods"].values():
        lo.hide_render = False


# ---------- 흐름 ----------

def load_char_module(char_id):
    p = os.path.join(HERE, "chars", char_id + ".py")
    spec = importlib.util.spec_from_file_location("tf_char_" + char_id, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"char": "tank", "out": os.path.join(REPO, "godot", "client", "assets", "models", "ext"), "preview": None, "parts": False, "fast": False}
    i = 0
    pos = []
    while i < len(argv):
        a = argv[i]
        if a in ("--out", "--preview"):
            out[a[2:]] = argv[i + 1]
            i += 2
            continue
        if a in ("--parts", "--fast"):
            out[a[2:]] = True
            i += 1
            continue
        pos.append(a)
        i += 1
    if pos:
        out["char"] = pos[0]
    return out


def main():
    args = parse_args()
    cid = args["char"]
    rig = json.load(open(os.path.join(HERE, "ref", cid + "_rig.json")))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    k = Kit(cid, rig)
    mod = load_char_module(cid)
    mod.build(k)
    if args["parts"]:
        rows = sorted(((tri_count(r["obj"]), r["obj"].name) for r in k.parts), reverse=True)
        print("TF 부품 삼각형 (많은 순): " + ", ".join("%s %d" % (n, t) for t, n in rows))
    props = {pn: build_prop(k, cid, pn, recs, args["fast"]) for pn, recs in k.props.items()}
    res = build_body(k, cid, args["out"], fast=args["fast"])
    lods = res["lods"]
    tris = {ln: tri_count(lo) for ln, lo in lods.items()}
    ptris = {pn: tri_count(po) for pn, po in props.items()}
    # 상자 (게임 좌표): 고도는 상자 바닥 = 발바닥, 키 = PLAYER_HEIGHT × FIGURE_SCALE × height → 크기 1 이 되게
    vs = [lo_.matrix_world @ v.co for lo_ in lods.values() for v in lo_.data.vertices]  # 고도는 모든 LOD 메시를 합친 상자로 크기를 잼
    bx = [(-v.y, v.x, v.z) for v in vs]
    lo = [min(p[i] for p in bx) for i in range(3)]
    hi = [max(p[i] for p in bx) for i in range(3)]
    target = rig["player_height"] * rig["figure_scale"]
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    out = args["out"]
    cfg = {"_": "W19 Blender 로 만든 몸 (tools/blender/build_character.py %s) — 다시 만들면 덮어씀. 키는 chars/chars_config.gd EXT_DEFAULTS" % cid,
           "height": round((hi[2] - lo[2]) / target, 5), "offset": [round(cx, 5), round(lo[2], 5), round(-cy, 5)], "tint": "mask",
           "lods": {"stage": "%s_lod0" % cid, "high": "%s_lod1" % cid, "medium": "%s_lod2" % cid, "low": "%s_lod3" % cid},
           "faces": {kind: "res://assets/models/ext/%s_face_%s.png" % (cid, kind) for kind in ("idle", "hit", "attack")}}
    cfg.update(getattr(mod, "CFG", {}))
    cfg["stats"] = {"tris": tris, "full_tris": res["full"], "prop_tris": ptris, "bones": len(res["arm"].data.bones),
                    "atlas": ATLAS, "face_px": FACE_PX, "box_min": [round(x, 4) for x in lo], "box_max": [round(x, 4) for x in hi],
                    "auto_weight_fail": res["fails"]}
    print("TF 삼각형 LOD %s (서브디비전 원본 %d), 소품 %s, 뼈 %d, 상자 %s ~ %s, 자동 가중치 실패 %s" % (
        tris, res["full"], ptris, len(res["arm"].data.bones), cfg["stats"]["box_min"], cfg["stats"]["box_max"], res["fails"]))
    if args["preview"]:
        # 미리보기: 몸 색 칸을 빨강 (PREVIEW_TINT) 으로 다시 구운 아틀라스로 그림 (내보내는 아틀라스는 하양 그대로 — 고도가 플레이어 색을 곱함)
        save_png(res["atlas"], os.path.join(args["preview"], "%s_atlas.png" % cid))
        swaps = preview_tint_swap(res, props, args["fast"])
        render_previews(scene, k, res, props, mod, args["preview"], cid)
        for mat, img in swaps:
            mat.node_tree.nodes["Image Texture"].image = img
    os.makedirs(out, exist_ok=True)
    for kind, im in res["faces"].items():
        save_png(im, os.path.join(out, "%s_face_%s.png" % (cid, kind)))
    export_glb(os.path.join(out, cid + ".glb"), list(lods.values()) + [res["arm"]])
    for pn, po in props.items():
        po.parent = None
        export_glb(os.path.join(out, "%s_%s.glb" % (cid, pn)), [po])
    with open(os.path.join(out, cid + ".json"), "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent="\t")
        f.write("\n")
    print("TF 끝 %s" % out)


if __name__ == "__main__":
    main()
