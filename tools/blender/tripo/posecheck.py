# 자동 리깅 몸 자세 확인 그림 (뼈 이름 = Mixamo 식): blender -b --factory-startup -P tools/blender/tripo/posecheck.py -- <리깅.glb> <출력 폴더> [메시 이름] [자세,자세…]
# 자세마다 앞·옆·뒤 PNG (Workbench, 텍스처 색 — 몸 색 칸은 회백으로 보임). 갈라짐·가시·소품이 몸을 뚫는지 눈으로 보는 용도
import bpy
import math
import os
import sys
from mathutils import Vector, Euler

a = sys.argv[sys.argv.index("--") + 1:]
src, out = a[0], a[1]
mesh_name = a[2] if len(a) > 2 else None
want = a[3].split(",") if len(a) > 3 else None
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
arm = [o for o in sc.objects if o.type == "ARMATURE"][0]
meshes = [o for o in sc.objects if o.type == "MESH"]
show = [m for m in meshes if mesh_name is None or m.name == mesh_name]
for m in meshes:
    m.hide_render = m not in show
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "TEXTURE"
sh.show_object_outline = True
sc.render.resolution_x = 460
sc.render.resolution_y = 520
sc.world = bpy.data.worlds.new("w")
sc.world.color = (.55, .6, .68)
cam = bpy.data.cameras.new("c")
cam.type = "ORTHO"
cam.ortho_scale = 1.5
co = bpy.data.objects.new("c", cam)
sc.collection.objects.link(co)
sc.camera = co
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
pb = arm.pose.bones
P = "mixamorig:"


def rot(n, e):
    b = pb[P + n]
    b.rotation_mode = "XYZ"
    b.rotation_euler = Euler([math.radians(x) for x in e])


POSES = {
    "rest": {},
    "armfwd": {"RightArm": (-85, 0, 0), "RightForeArm": (-20, 0, 0), "LeftArm": (-60, 0, 0), "LeftForeArm": (-70, 0, 0)},
    "overhead": {"RightArm": (-160, 0, 0), "LeftArm": (-150, 0, 0), "LeftForeArm": (-30, 0, 0), "Spine": (-10, 0, 0)},
    "smash": {"RightArm": (-40, 0, 0), "RightForeArm": (-40, 0, 0), "Spine": (30, 0, 0), "Spine1": (15, 0, 0)},
    "armup": {"LeftArm": (0, 0, -80), "RightArm": (0, 0, 80), "LeftForeArm": (-60, 0, 0)},
    "squat": {"LeftUpLeg": (-90, 0, 0), "RightUpLeg": (-90, 0, 0), "LeftLeg": (110, 0, 0), "RightLeg": (110, 0, 0), "Spine": (25, 0, 0)},
    "stride": {"LeftUpLeg": (-45, 0, 0), "RightUpLeg": (35, 0, 0), "LeftLeg": (50, 0, 0), "RightArm": (-40, 0, 0), "LeftArm": (40, 0, 0), "LeftForeArm": (-70, 0, 0)},
    "jump": {"LeftUpLeg": (-45, 0, 0), "LeftLeg": (70, 0, 0), "RightUpLeg": (20, 0, 0), "RightLeg": (50, 0, 0), "LeftArm": (0, 0, -55), "RightArm": (0, 0, 55)},
    "twist": {"Spine": (0, 35, 0), "Spine1": (0, 25, 0), "Spine2": (0, 20, 0), "RightArm": (-70, 0, 0), "LeftArm": (-70, 0, 0)},
}
for k, p in POSES.items():
    if want and k not in want:
        continue
    for b in pb:
        b.rotation_mode = "XYZ"
        b.rotation_euler = (0, 0, 0)
        b.location = (0, 0, 0)
    for n, e in p.items():
        rot(n, e)
    bpy.context.view_layer.update()
    for vn, loc, r in (("front", (6, 0, 0.5), (math.pi / 2, 0, math.pi / 2)), ("side", (0, -6, 0.5), (math.pi / 2, 0, 0)), ("back", (-6, 0, 0.5), (math.pi / 2, 0, -math.pi / 2))):
        co.location = loc
        co.rotation_euler = r
        sc.render.filepath = os.path.join(out, "%s_%s.png" % (k, vn))
        bpy.ops.render.render(write_still=True)
print("TF 자세 그림", out)
