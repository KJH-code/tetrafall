# W19 Blender 캐릭터 제작 공통 (Blender 4.5, 화면 없이). 캐릭터 모양은 chars/<id>.py 의 build(k) 가 부품을 부름.
# 실행 (레포 뿌리): blender -b --factory-startup -P tools/blender/build_character.py -- tank [--preview <폴더>] [--out <폴더>] [--blend <파일>]
# 나오는 것: <out>/<id>.glb (몸 + 뼈대, 스킨 메시 하나·재질 하나) · <out>/<id>_<소품>.glb (방패 등 따로) · <out>/<id>.json (고도 조정 값) · 미리보기 PNG
#
# 규격 (README.md 2절):
#  - 좌표: 부품은 게임 좌표 (앞 +x, 왼쪽 +y, 위 +z, m, 발바닥 z = 0) 로 적고, Blender 로는 (X, Y, Z) = (y, -x, z) (앞 -Y — glTF 앞 +Z)
#  - 뼈 = 우리 관절 이름 그대로 (hips waist torso neck shoulder_R elbow_R hand_R … foot_L, R = 캐릭터 오른쪽 = Blender -X), 자리 = ref/<id>_rig.json (고도 몸 쉬는 자세)
#  - 색: 꼭짓점 색 (COLOR_0) + 몸 색 칸 표시 (둘째 UV = 고도 UV2, x = 1 이면 플레이어 색 — 툰 셰이더 skin_tint). 재질 1개 → 고도에서 몸 하나 = 툰 1 + 외곽선 1
#  - 가중치: 딱딱한 부품 (갑옷·투구·장갑·장화) 은 뼈 하나 100%, 부드러운 부품 (소매·허벅지·몸통) 은 부품 하나씩 자동 가중치 (bone heat) 뒤 허락한 뼈만 남기고 정규화
import bpy
import bmesh
import json
import math
import os
import sys
import importlib.util

sys.dont_write_bytecode = True  # chars/<id>.py 를 부를 때 __pycache__ 를 레포에 안 남김
from mathutils import Vector, Matrix, Euler, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

JOINTS = ["hips", "waist", "torso", "neck", "shoulder_R", "elbow_R", "hand_R", "shoulder_L", "elbow_L", "hand_L",
          "thigh_R", "knee_R", "foot_R", "thigh_L", "knee_L", "foot_L"]
PARENT = {"waist": "hips", "torso": "waist", "neck": "torso", "shoulder": "torso", "elbow": "shoulder", "hand": "elbow",
          "thigh": "hips", "knee": "thigh", "foot": "knee"}
CHILD = {"hips": "waist", "waist": "torso", "torso": "neck", "shoulder": "elbow", "elbow": "hand", "thigh": "knee", "knee": "foot"}
PREVIEW_SKIN = 0xd63c3c  # 미리보기에서만 몸 색 칸을 칠하는 색 (게임에선 플레이어 색)


# ---------- 좌표·색 ----------

def G(x, y=None, z=None):
    """게임 좌표 → Blender 좌표"""
    if y is None:
        x, y, z = x
    return Vector((y, -x, z))


def GDIR(v):
    return G(v[0], v[1], v[2])


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin_to_srgb(c):
    c = max(0.0, c)
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def hexcol(h):
    return ((h >> 16 & 255) / 255.0, (h >> 8 & 255) / 255.0, (h & 255) / 255.0)


# ---------- 부품 만들기 (bmesh) ----------

class Kit:
    """캐릭터 하나를 만드는 도구 상자. chars/<id>.py 의 build(k) 가 씀"""

    def __init__(self, char_id, rig):
        self.id = char_id
        self.rig = rig
        self.J = {j: Vector(rig["joints"][j]["pos"]) for j in JOINTS}  # 게임 좌표
        self.parts = []  # [{obj, bone, blend (허락 뼈 목록 또는 None), skin, prop}]
        self.props = {}  # 소품 이름 → [obj]
        self.prop_cfg = {}

    # 관절 자리 (게임 좌표 Vector)
    def j(self, name):
        return self.J[name].copy()

    def _new_obj(self, name, bm):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob

    def _place(self, bm, pos, rot, scale):
        """bmesh 정점을 크기 → 회전 (게임 오일러 XYZ, 도) → 자리 (게임 좌표) 로"""
        sx, sy, sz = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
        m_game = Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4() \
            @ Matrix.Diagonal((sx, sy, sz, 1.0))
        # 게임 → Blender (X, Y, Z) = (y, -x, z)
        g2b = Matrix(((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
        bm.transform(g2b @ m_game)

    def sphere(self, name, pos, radii, color, bone, rot=(0, 0, 0), seg=16, rings=10, **kw):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
        self._place(bm, pos, rot, radii)
        return self._add(name, bm, color, bone, **kw)

    def rbox(self, name, pos, size, color, bone, rot=(0, 0, 0), bevel=0.3, segs=2, **kw):
        """둥근 상자: size = 게임 x·y·z 폭, bevel = 가장 짧은 변 대비 깎는 비율"""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        sx, sy, sz = size
        for v in bm.verts:
            v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
        off = min(size) * bevel
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=off, segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
        self._place(bm, pos, rot, (1, 1, 1))
        return self._add(name, bm, color, bone, **kw)

    def capsule(self, name, a, b, r_a, r_b, color, bone, seg=12, rings=4, **kw):
        """a → b (게임 좌표) 캡슐: 두 끝 반구 + 원뿔 몸 (r_a·r_b 다르면 굵기가 변함)"""
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        bm = bmesh.new()
        # 위도 고리: 아래 반구 (b 쪽 → 0) … 위 반구 (a 쪽). 로컬 z = 0 (a) … -L (b)
        ring_list = []
        for i in range(rings + 1):  # a 반구 (위)
            t = math.pi / 2 * (1 - i / rings)
            ring_list.append((r_a * math.cos(t), r_a * math.sin(t)))
        for i in range(rings + 1):  # b 반구 (아래)
            t = math.pi / 2 * i / rings
            ring_list.append((r_b * math.cos(t), -L - r_b * math.sin(t)))
        verts = []
        top = bm.verts.new((0, 0, r_a))
        bot = bm.verts.new((0, 0, -L - r_b))
        for (rr, zz) in ring_list[1:-1]:
            ring = []
            for k in range(seg):
                ang = 2 * math.pi * k / seg
                ring.append(bm.verts.new((rr * math.cos(ang), rr * math.sin(ang), zz)))
            verts.append(ring)
        for k in range(seg):
            bm.faces.new((top, verts[0][k], verts[0][(k + 1) % seg]))
            bm.faces.new((bot, verts[-1][(k + 1) % seg], verts[-1][k]))
        for i in range(len(verts) - 1):
            for k in range(seg):
                r0, r1 = verts[i], verts[i + 1]
                bm.faces.new((r0[k], r1[k], r1[(k + 1) % seg], r0[(k + 1) % seg]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        # 로컬 -z 를 d 방향으로
        q = Vector((0, 0, -1)).rotation_difference(d.normalized()) if L > 1e-6 else Quaternion()
        m = Matrix.Translation(a) @ q.to_matrix().to_4x4()
        g2b = Matrix(((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
        bm.transform(g2b @ m)
        return self._add(name, bm, color, bone, **kw)

    def torus(self, name, pos, R, r, color, bone, rot=(0, 0, 0), scale=(1, 1, 1), seg=20, ring=6, **kw):
        """고리 (축 = 게임 z), scale 로 타원"""
        bm = bmesh.new()
        vs = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            row = []
            for k in range(ring):
                b = 2 * math.pi * k / ring
                rr = R + r * math.cos(b)
                row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b))))
            vs.append(row)
        for i in range(seg):
            for k in range(ring):
                a0, a1 = vs[i], vs[(i + 1) % seg]
                bm.faces.new((a0[k], a1[k], a1[(k + 1) % ring], a0[(k + 1) % ring]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        self._place(bm, pos, rot, scale)
        return self._add(name, bm, color, bone, **kw)

    def cylinder(self, name, pos, r, h, color, bone, rot=(0, 0, 0), scale=(1, 1, 1), seg=20, bevel=0.0, **kw):
        """원기둥 (축 = 게임 z, 가운데 pos), bevel = 윗·아랫 모서리 깎기 (m)"""
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=h)
        if bevel > 0:
            rim = [e for e in bm.edges if all(abs(abs(v.co.z) - h / 2) < 1e-5 for v in e.verts) and not e.is_boundary
                   and len(e.link_faces) == 2 and abs(e.link_faces[0].normal.z) != abs(e.link_faces[1].normal.z)]
            bmesh.ops.bevel(bm, geom=rim, offset=bevel, segments=2, profile=0.5, affect="EDGES", clamp_overlap=True)
        self._place(bm, pos, rot, scale)
        return self._add(name, bm, color, bone, **kw)

    def shell(self, name, pos, radii, color, bone, keep, thick=0.02, rot=(0, 0, 0), seg=20, rings=12, **kw):
        """구 껍데기: keep(로컬 단위 구 위 점 Vector) 이 참인 면만 남기고 두께 (닫힌 입체 → 외곽선이 둘레에 생김)"""
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
        # 로컬 좌표는 게임 축 그대로 (x 앞, y 왼쪽, z 위) — 아직 안 옮김
        dead = [f for f in bm.faces if not keep(f.calc_center_median())]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        self._place(bm, pos, rot, radii)
        ob = self._add(name, bm, color, bone, **kw)
        mod = ob.modifiers.new("solid", "SOLIDIFY")
        mod.thickness = thick
        mod.offset = -1.0
        mod.use_even_offset = True
        _apply_mods(ob)
        return ob

    def _add(self, name, bm, color, bone, blend=None, skin=False, prop=None, smooth=True):
        ob = self._new_obj(name, bm)
        for p in ob.data.polygons:
            p.use_smooth = smooth
        ob["tf_bone"] = bone
        ob["tf_skin"] = bool(skin)
        _paint(ob, PREVIEW_SKIN if skin else color, skin)
        rec = {"obj": ob, "bone": bone, "blend": blend, "skin": skin, "prop": prop}
        if prop is None:
            self.parts.append(rec)
        else:
            self.props.setdefault(prop, []).append(rec)
        return ob

    def mirror(self, fn, *args, **kw):
        """오른쪽 (R) 부품을 만드는 fn(side, sign) 을 R·L 둘 다 (sign: R = -1, L = +1 — 게임 y)"""
        for side, sign in (("R", -1), ("L", 1)):
            fn(side, sign)


def _apply_mods(ob):
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def _paint(ob, color, skin):
    """꼭짓점 색 (선형 = Blender 화면에 맞는 값 — 내보낼 때 고도 import 에 맞춰 바꿈) + 몸 색 칸 UV (둘째 UV x = 1)"""
    me = ob.data
    lin = [srgb_to_lin(c) for c in hexcol(color)] + [1.0]
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    attr = me.color_attributes["Col"]
    for d in attr.data:
        d.color = lin
    while len(me.uv_layers) < 2:
        me.uv_layers.new(name="UVMap" if len(me.uv_layers) == 0 else "Skin")
    for d in me.uv_layers[0].data:
        d.uv = (0.0, 0.0)
    for d in me.uv_layers[1].data:
        d.uv = (1.0 if skin else 0.0, 0.0)


# ---------- 뼈대 ----------

def make_armature(k, name):
    J = k.J
    arm = bpy.data.armatures.new(name + "_rig")
    ob = bpy.data.objects.new(name + "_rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
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


def skin_parts(k, arm):
    """부품마다 가중치 → 부품 합치기. 딱딱한 부품 = 뼈 하나 1.0, blend 부품 = 그 부품만 자동 가중치 (bone heat) 뒤 허락 뼈만 남겨 정규화"""
    auto_fail = []
    for rec in k.parts:
        ob = rec["obj"]
        for n in JOINTS:
            ob.vertex_groups.new(name=n)
        allow = rec["blend"]
        if allow:
            for o in bpy.context.selected_objects:
                o.select_set(False)
            ob.select_set(True)
            arm.select_set(True)
            bpy.context.view_layer.objects.active = arm
            bpy.ops.object.parent_set(type="ARMATURE_AUTO")
            ob.parent = None
            for m in list(ob.modifiers):
                ob.modifiers.remove(m)
            ok = _clean_weights(ob, allow, rec["bone"])
            if not ok:
                auto_fail.append(ob.name)
        else:
            ob.vertex_groups[rec["bone"]].add(range(len(ob.data.vertices)), 1.0, "REPLACE")
    return auto_fail


def _clean_weights(ob, allow, owner, limit=3, floor=0.04):
    """허락 뼈만 남기고 (작은 값 버림·최대 limit 개) 정규화. 가중치가 하나도 없는 정점은 owner 1.0. 자동 가중치가 다 비었으면 False"""
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
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def bind(ob, arm):
    ob.parent = arm
    mod = ob.modifiers.new("rig", "ARMATURE")
    mod.object = arm


def material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return m


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# ---------- 내보내기 ----------

def set_skin_preview(objs, on):
    """미리보기: 몸 색 칸을 PREVIEW_SKIN 으로 / 내보내기: 하양 (고도 skin_tint 가 플레이어 색으로 칠함)"""
    col = [srgb_to_lin(c) for c in hexcol(PREVIEW_SKIN)] + [1.0] if on else [1.0, 1.0, 1.0, 1.0]
    for ob in objs:
        me = ob.data
        uv = me.uv_layers[1].data
        attr = me.color_attributes["Col"]
        for li, lp in enumerate(me.loops):
            if uv[li].uv[0] > 0.5:
                attr.data[li].color = col


def to_godot_colors(objs, forward=True):
    """툰 셰이더는 COLOR 를 sRGB 값으로 곱함 (toon_common c *= COLOR, 재질 색과 같은 공간). Blender 4.5 내보내기 → 고도 4.7 import 를 거치면
    COLOR = 이 속성 값 그대로라 (테스트 test_blender_tank_info 가 쇠 색 a3adb8 로 확인) 내보내기 전에 선형 → sRGB 로 바꿔 둠. forward=False 면 되돌림"""
    for ob in objs:
        attr = ob.data.color_attributes["Col"]
        for d in attr.data:
            c = list(d.color)
            if forward:
                d.color = [lin_to_srgb(x) for x in c[:3]] + [c[3]]
            else:
                d.color = [srgb_to_lin(x) for x in c[:3]] + [c[3]]


def export_glb(path, objs):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_texcoords=True, export_normals=True, export_tangents=False,
                              export_materials="EXPORT", export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_skins=True, export_influence_nb=4, export_def_bones=False, export_leaf_bone=False,
                              export_animations=False, export_morph=False, export_attributes=False,
                              export_extras=False, export_cameras=False, export_lights=False)


# ---------- 미리보기 렌더 (Workbench, 꼭짓점 색 + 외곽선) ----------

def _cam(scene, target, yaw_deg, pitch_deg, dist, ortho):
    cam = bpy.data.objects.get("tf_cam")
    if cam is None:
        cam = bpy.data.objects.new("tf_cam", bpy.data.cameras.new("tf_cam"))
        scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    # 게임 좌표: yaw 0 = 앞 (+x) 에서 봄
    eye = Vector(target) + Vector((math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch))) * dist
    pos = G(eye)
    tgt = G(Vector(target))
    cam.location = pos
    cam.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def render_setup(scene, res=420):
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.film_transparent = False
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "VERTEX"
    sh.show_object_outline = True
    sh.object_outline_color = (0.05, 0.05, 0.08)
    sh.show_cavity = False
    sh.show_shadows = False
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.78, 0.82, 0.88)
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"


def pose_bones(arm, pose):
    """pose = [(뼈, 게임 축 (x, y, z), 도)] — 뼈 머리를 중심으로 세상 축 둘레 돌림 (부모 먼저 적용)"""
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
        y0 = (rows - 1 - r) * h  # Blender 그림은 아래부터
        a = px[:, :, 3:4]
        px = px * a + np.array([0.78, 0.82, 0.88, 1.0], dtype=np.float32) * (1 - a)  # 투명 바탕 → 미리보기 바탕색
        px[:, :, 3] = 1.0
        sheet[y0:y0 + h, c * w:(c + 1) * w] = px
    out_im = bpy.data.images.new("sheet", cols * w, rows * h, alpha=True)
    out_im.pixels = sheet.ravel()
    out_im.filepath_raw = out
    out_im.file_format = "PNG"
    out_im.save()


# ---------- 흐름 ----------

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_char_module(char_id):
    p = os.path.join(HERE, "chars", char_id + ".py")
    spec = importlib.util.spec_from_file_location("tf_char_" + char_id, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"char": "tank", "out": os.path.join(REPO, "godot", "client", "assets", "models", "ext"), "preview": None, "blend": None}
    i = 0
    pos = []
    while i < len(argv):
        a = argv[i]
        if a in ("--out", "--preview", "--blend"):
            out[a[2:]] = argv[i + 1]
            i += 2
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
    clear_scene()
    scene = bpy.context.scene
    k = Kit(cid, rig)
    mod = load_char_module(cid)
    mod.build(k)
    arm = make_armature(k, cid)
    fails = skin_parts(k, arm)
    body = join([r["obj"] for r in k.parts], cid + "_body")
    bind(body, arm)
    mat = material(cid)
    body.data.materials.append(mat)
    props = {}
    for pn, recs in k.props.items():
        po = join([r["obj"] for r in recs], cid + "_" + pn)
        po.data.materials.append(material(cid + "_" + pn))
        props[pn] = po
    tris = tri_count(body)
    ptris = {pn: tri_count(po) for pn, po in props.items()}
    # 모델 상자 (게임 좌표): 고도 external.gd 는 상자 바닥 = 발바닥, 상자 가운데 = 몸 자리, 키 = PLAYER_HEIGHT × FIGURE_SCALE × height 로 맞춤 →
    # 크기 1·자리 그대로가 되게 height·offset 을 적음 (관절 자리 = 고도 몸 관절 자리)
    vs = [body.matrix_world @ v.co for v in body.data.vertices]
    bx = [(v.y * -1, v.x, v.z) for v in vs]  # Blender → 게임 (x = -Y, y = X)
    lo = [min(p[i] for p in bx) for i in range(3)]
    hi = [max(p[i] for p in bx) for i in range(3)]
    target = rig["player_height"] * rig["figure_scale"]
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    cfg = {"_": "W19 Blender 로 만든 몸 (tools/blender/build_character.py %s) — 다시 만들면 덮어씀. 키는 chars/chars_config.gd EXT_DEFAULTS" % cid,
           "height": round((hi[2] - lo[2]) / target, 5), "offset": [round(cx, 5), round(lo[2], 5), round(-cy, 5)], "tint": "mask"}
    cfg.update(getattr(mod, "CFG", {}))
    cfg["stats"] = {"tris": tris, "prop_tris": ptris, "bones": len(arm.data.bones), "verts": len(body.data.vertices),
                    "box_min": [round(x, 4) for x in lo], "box_max": [round(x, 4) for x in hi], "auto_weight_fail": fails}
    print("TF 삼각형 몸 %d, 소품 %s, 뼈 %d, 상자 %s ~ %s, 자동 가중치 실패 %s" % (tris, ptris, len(arm.data.bones), cfg["stats"]["box_min"], cfg["stats"]["box_max"], fails))
    # 미리보기
    if args["preview"]:
        render_previews(scene, k, arm, body, props, mod, args["preview"], cid)
    # 내보내기: 몸 색 칸 하양, 색은 고도 import 에 맞춰
    allo = [body] + list(props.values())
    set_skin_preview(allo, False)
    to_godot_colors(allo, True)
    out = args["out"]
    export_glb(os.path.join(out, cid + ".glb"), [body, arm])
    for pn, po in props.items():
        po.parent = None
        export_glb(os.path.join(out, "%s_%s.glb" % (cid, pn)), [po])
    with open(os.path.join(out, cid + ".json"), "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent="\t")
        f.write("\n")
    to_godot_colors(allo, False)
    if args["blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=args["blend"])
    print("TF 끝 %s" % out)


def render_previews(scene, k, arm, body, props, mod, outdir, cid):
    os.makedirs(outdir, exist_ok=True)
    render_setup(scene)
    # 방패 등 소품은 미리보기에서 제자리 (mod.PREVIEW_PROPS: 소품 → (관절, 게임 자리, 게임 회전 도)) 에 붙여 보임
    shows = getattr(mod, "PREVIEW_PROPS", {})
    for pn, po in props.items():
        if pn in shows:
            jn, pos, rot = shows[pn]
            po.parent = arm
            po.parent_type = "BONE"
            po.parent_bone = jn
            bpy.context.view_layer.update()
            # 뼈 쉬는 자세 기준 자리: 게임 좌표 pos·rot → 세상 → 뼈 꼬리 기준 (Blender 뼈 부모는 꼬리 자리)
            g2b = Matrix(((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
            world = g2b @ Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((k.rig["figure_scale"],) * 3 + (1,)) @ g2b.inverted()
            po.matrix_world = world
        else:
            po.hide_render = True
    c = Vector((0, 0, 1.0))
    shots = []
    for nm, yaw, pitch in (("front", 0, 8), ("q34", 40, 12), ("side", 90, 5), ("back", 180, 10)):
        pose_bones(arm, [])
        _cam(scene, c, yaw, pitch, 6, 2.5)
        p = os.path.join(outdir, "%s_%s.png" % (cid, nm))
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        shots.append(p)
    head = k.j("neck") + Vector((0, 0, 0.2))
    for nm, yaw in (("head", 25), ("head_back", 150)):
        pose_bones(arm, [])
        _cam(scene, head, yaw, 8, 4, 0.75)
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
    # 소품은 다시 떼어 둠
    for pn, po in props.items():
        mw = po.matrix_world.copy()
        po.parent = None
        po.matrix_world = Matrix.Identity(4)
        po.hide_render = False


if __name__ == "__main__":
    main()
