# 몸 색 칸 마스크 텍스처 굽기 (W34, relod.py 가 못 하는 모델용 — 판 LOD 가 stage 와 같은 UV·알베도를 쓰는 사냥꾼):
#  ext/<이름>.glb 의 한 메시 (기본 <이름>_lod0 = stage) 에서 꼭짓점 몸 색 칸 (둘째 UV 의 x, tint "mask") 을 그 메시 자신의 첫째 UV 위 그림 (한 채널, 칸 = 흰) 으로 옮겨 굽는다.
#  stage 의 LOD (meshopt 로 줄인 것) 는 같은 UV 값을 가진 꼭짓점의 부분집합이라 이 그림 하나로 모두 읽힌다. 셰이더 g3 가 skin_mask_tex 로 읽음 (꼭짓점 판정 대신).
#  가장자리: stage 꼭짓점 보간값 0.5 가 경계, 기울기를 --mask-soft 배 (기본 8) 로 가파르게 → 1~3 텍셀 부드러움.
# 실행: blender -b --factory-startup -P tools/blender/tripo/maskbake.py -- --glb <ext/이름.glb> --name hunter --out <폴더> [--node hunter_lod0] [--size 1024] [--mask-soft 8]
#   → <폴더>/<이름>_mask.png
import bpy, sys, os
import numpy as np


def arg(key, default=None):
    a = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    return a[a.index(key) + 1] if key in a else default


GLB = arg('--glb')
NAME = arg('--name')
OUT = arg('--out')
NODE = arg('--node', NAME + '_lod0')
SIZE = int(arg('--size', 1024))
SOFT = float(arg('--mask-soft', 8.0))
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
obj = bpy.data.objects[NODE]
scene = bpy.context.scene
for o in bpy.data.objects:
    o.select_set(False)
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
obj.data.uv_layers.active_index = 0

scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 1
scene.cycles.use_denoising = False
bk = scene.render.bake
bk.use_selected_to_active = False
bk.margin = 10
bk.margin_type = 'EXTEND'

im = bpy.data.images.new(NAME + '_mask', SIZE, SIZE, alpha=False, float_buffer=False)
im.generated_color = (0, 0, 0, 1)
im.colorspace_settings.name = 'Non-Color'
mat = bpy.data.materials.new('maskbake')
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
out = nt.nodes.new('ShaderNodeOutputMaterial')
tex = nt.nodes.new('ShaderNodeTexImage')
tex.image = im
nt.nodes.active = tex
uvn = nt.nodes.new('ShaderNodeUVMap')
uvn.uv_map = obj.data.uv_layers[1].name
sep = nt.nodes.new('ShaderNodeSeparateXYZ')
em = nt.nodes.new('ShaderNodeEmission')
nt.links.new(uvn.outputs['UV'], sep.inputs['Vector'])
nt.links.new(sep.outputs['X'], em.inputs['Color'])
nt.links.new(em.outputs['Emission'], out.inputs['Surface'])
obj.data.materials.clear()
obj.data.materials.append(mat)
bpy.ops.object.bake(type='EMIT')

a = np.zeros(SIZE * SIZE * 4, dtype=np.float32)
im.pixels.foreach_get(a)
a = a.reshape(SIZE, SIZE, 4)
mk = np.clip((a[:, :, 0] - 0.5) * SOFT + 0.5, 0.0, 1.0)
buf = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
buf[:, :, 0] = buf[:, :, 1] = buf[:, :, 2] = mk
buf[:, :, 3] = 1.0
im2 = bpy.data.images.new(NAME + '_mask_out', SIZE, SIZE, alpha=False, float_buffer=False)
im2.colorspace_settings.name = 'Non-Color'
im2.pixels.foreach_set(buf.ravel())
im2.update()
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'BW'
png = os.path.join(OUT, NAME + '_mask.png')
im2.save_render(png, scene=scene)
print('MASKBAKE coverage %.4f -> %s' % (mk.mean(), png))
