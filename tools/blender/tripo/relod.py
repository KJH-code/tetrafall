# 판 LOD 다시 굽기 (W31 2026-11-08, PC 최적화 2차): 이미 리깅해 둔 ext/<이름>.glb 의 stage (원본 1.7~1.9만 삼각형) 메시를
#  줄이고 (Decimate 접기) → 새 UV (Smart UV, 큰 조각 몇십 개) → stage 알베도를 새 UV 로 굽고 (Cycles CPU, 선택→활성) → 스킨 가중치는 stage 에서 Data Transfer
#  → 몸 색 칸 (UV2.x = 1, tint "mask") 은 stage 에서 꼭짓점으로 옮기고 알베도의 회백/빨강을 그 꼭짓점 색 칸에 맞춰 다시 칠함 → glb (뼈대 + 메시 하나) 로 내보냄.
# 이 glb 를 relod_merge.mjs 가 원래 glb 에 판 LOD 로 합침 (UV 이음선이 적어 meshopt 로 더 줄이는 LOD 둘도 거기서).
# W34: 몸 색 칸을 꼭짓점이 아니라 **마스크 텍스처** 로도 굽는다 — stage 마스크 (UV2.x) 를 새 UV 로 옮긴 그림 (한 채널, 칸 = 흰) 을 <이름>_mask_lod.png 로 저장. 셰이더 g3 (skin_mask_tex) 가
#  꼭짓점 UV2 대신 이 그림을 읽어서 알베도 (stage 에서 구운 회백 칸) 와 칸 경계가 텍셀 단위로 딱 맞음. 가장자리는 stage 꼭짓점 보간 기울기를 조금 가파르게 (MASK_SOFT) 해서 1~3 텍셀로 부드럽게.
# 실행: blender -b --factory-startup -P tools/blender/tripo/relod.py -- --glb <ext/이름.glb> --name ninja --out <폴더> [--tris 5000] [--size 1024] [--angle 66] [--margin 0.008] [--ray 0.04]
#   → <폴더>/<이름>_relod.glb (+ 확인용 <이름>_atlas_lod.png·마스크 png, 셰이더가 읽는 <이름>_mask_lod.png)
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils.bvhtree import BVHTree


def arg(key, default=None):
    a = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    return a[a.index(key) + 1] if key in a else default


GLB = arg('--glb')
NAME = arg('--name')
OUT = arg('--out')
TRIS = int(arg('--tris', 5000))
SIZE = int(arg('--size', 1024))
ANGLE = float(arg('--angle', 66))
MARGIN = float(arg('--margin', 0.008))
RAY = float(arg('--ray', 0.04))
MASK_SOFT = float(arg('--mask-soft', 8.0))  # 마스크 가장자리 기울기 (1 = stage 꼭짓점 보간 그대로)
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
stage = bpy.data.objects[NAME + '_lod0']
arm = stage.parent
scene = bpy.context.scene
view = bpy.context.view_layer


def select_only(*objs):
    for o in bpy.data.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    view.objects.active = objs[-1]


# ---- 1. 합친 사본 → 줄이기 ----
new = stage.copy()
new.data = stage.data.copy()
new.name = NAME + '_new'
new.data.name = NAME + '_new'
bpy.context.collection.objects.link(new)
new.modifiers.clear()
new.vertex_groups.clear()
bm = bmesh.new()
bm.from_mesh(new.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.to_mesh(new.data)
bm.free()
select_only(new)
bpy.ops.mesh.customdata_custom_splitnormals_clear()
n_weld = len(new.data.polygons)
md = new.modifiers.new('dec', 'DECIMATE')
md.decimate_type = 'COLLAPSE'
md.ratio = min(1.0, TRIS / n_weld)
md.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier='dec')
n_new = len(new.data.polygons)
print('RELOD tris stage', len(stage.data.polygons), 'weld', n_weld, 'new', n_new)
bpy.ops.object.shade_smooth()

# ---- 2. 몸 색 칸 (stage UV2.x) 을 새 꼭짓점으로, 가중치는 Data Transfer ----
sme = stage.data
uv2_layer = sme.uv_layers[1]
nl = len(sme.loops)
uv2 = np.zeros(nl * 2, dtype=np.float32)
uv2_layer.data.foreach_get('uv', uv2)
mask_loop = uv2.reshape(-1, 2)[:, 0]
sverts = np.zeros(len(sme.vertices) * 3, dtype=np.float32)
sme.vertices.foreach_get('co', sverts)
sverts = sverts.reshape(-1, 3)
tree = BVHTree.FromPolygons([tuple(v) for v in sverts], [tuple(p.vertices) for p in sme.polygons])
nme = new.data
mask_v = np.zeros(len(nme.vertices), dtype=np.float32)
for v in nme.vertices:
    loc, nor, pi, dist = tree.find_nearest(v.co)
    poly = sme.polygons[pi]
    best, bd = 0.0, 1e9
    for li in poly.loop_indices:
        d = (sverts[sme.loops[li].vertex_index] - np.array(loc)).dot(sverts[sme.loops[li].vertex_index] - np.array(loc))
        if d < bd:
            bd, best = d, mask_loop[li]
    mask_v[v.index] = 1.0 if best > 0.5 else 0.0
for vg in stage.vertex_groups:
    new.vertex_groups.new(name=vg.name)
dt = new.modifiers.new('wt', 'DATA_TRANSFER')
dt.object = stage
dt.use_vert_data = True
dt.data_types_verts = {'VGROUP_WEIGHTS'}
dt.vert_mapping = 'POLYINTERP_NEAREST'
dt.layers_vgroup_select_src = 'ALL'
dt.layers_vgroup_select_dst = 'NAME'
select_only(new)
bpy.ops.object.modifier_apply(modifier='wt')
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)

# ---- 3. 새 UV: Smart UV 로 큰 조각 → 넓이 맞춤 → 포장 ----
for l in list(nme.uv_layers):
    nme.uv_layers.remove(l)
nme.uv_layers.new(name='UVMap')
select_only(new)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(ANGLE), island_margin=0.0, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
bpy.ops.uv.average_islands_scale()
bpy.ops.uv.pack_islands(margin=MARGIN, rotate=True)
bpy.ops.object.mode_set(mode='OBJECT')
# 둘째 UV = 몸 색 칸 (x = 0/1, y = 0), 셋째 필요 없음. 꼭짓점 색 = 흰
u2 = nme.uv_layers.new(name='UVMap.001')
loop_v = np.zeros(len(nme.loops), dtype=np.int32)
nme.loops.foreach_get('vertex_index', loop_v)
arr = np.zeros((len(nme.loops), 2), dtype=np.float32)
arr[:, 0] = mask_v[loop_v]
u2.data.foreach_set('uv', arr.ravel())
for c in list(nme.color_attributes):
    nme.color_attributes.remove(c)
ca = nme.color_attributes.new(name='Color', type='BYTE_COLOR', domain='CORNER')
ca.data.foreach_set('color', np.ones(len(nme.loops) * 4, dtype=np.float32))
nme.color_attributes.active_color = ca
nme.color_attributes.render_color_index = 0
nme.uv_layers.active_index = 0

# ---- 4. 굽기: stage 알베도 → 새 UV (선택→활성), 몸 색 칸 마스크 둘 (stage 쪽·새 쪽) ----
# 저장 (save_render) 이 장면 색 관리 (기본 AgX) 를 거치면 색이 바램 → 표준 + 보정 없음
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.view_settings.exposure = 0.0
scene.view_settings.gamma = 1.0
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 1
scene.cycles.use_denoising = False
bk = scene.render.bake
bk.use_selected_to_active = True
bk.cage_extrusion = RAY
bk.max_ray_distance = 0.0
bk.margin = 10
bk.margin_type = 'EXTEND'
bk.use_pass_direct = False
bk.use_pass_indirect = False
bk.use_pass_color = True


def make_image(name, color=(0, 0, 0, 1), data=False):
    im = bpy.data.images.new(name, SIZE, SIZE, alpha=False, float_buffer=False)
    im.generated_color = color
    if data:
        im.colorspace_settings.name = 'Non-Color'
    return im


def bake_material(obj, image, emit_uv2=False):
    mat = bpy.data.materials.new(obj.name + '_bake')
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = image
    nt.nodes.active = tex
    if emit_uv2:
        uvn = nt.nodes.new('ShaderNodeUVMap')
        uvn.uv_map = 'UVMap.001'
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        em = nt.nodes.new('ShaderNodeEmission')
        nt.links.new(uvn.outputs['UV'], sep.inputs['Vector'])
        for ch in ('Color',):
            nt.links.new(sep.outputs['X'], em.inputs[ch])
        nt.links.new(em.outputs['Emission'], out.inputs['Surface'])
    return mat


albedo_src_mat = stage.data.materials[0]
im_alb = make_image(NAME + '_alb')
im_ms = make_image(NAME + '_mask_src', data=True)
im_mn = make_image(NAME + '_mask_new', data=True)
# 4a. 알베도
new.data.materials.clear()
new.data.materials.append(bake_material(new, im_alb))
select_only(stage, new)
bpy.ops.object.bake(type='DIFFUSE')
# 4b. stage 몸 색 칸 마스크 (stage 재질을 잠깐 방출 재질로)
stage.data.materials[0] = bake_material(stage, make_image('tmp', data=True), emit_uv2=True)
new.data.materials.clear()
new.data.materials.append(bake_material(new, im_ms))
select_only(stage, new)
bpy.ops.object.bake(type='EMIT')
stage.data.materials[0] = albedo_src_mat
# 4c. 새 메시 자신의 마스크 (꼭짓점 보간 그대로 = 셰이더가 UV2.x > 0.5 로 볼 모양)
new.data.materials.clear()
new.data.materials.append(bake_material(new, im_mn, emit_uv2=True))
bk.use_selected_to_active = False
select_only(new)
bpy.ops.object.bake(type='EMIT')
bk.use_selected_to_active = True


def px(im):
    a = np.zeros(SIZE * SIZE * 4, dtype=np.float32)
    im.pixels.foreach_get(a)
    return a.reshape(SIZE, SIZE, 4)


alb = px(im_alb)
ms = px(im_ms)[:, :, 0] > 0.5
mn = px(im_mn)[:, :, 0] > 0.5
# 마스크 어긋남 (새 꼭짓점 색 칸 경계가 stage 와 한 삼각형만큼 다름): stage 에선 회백인데 새 셰이더가 색을 안 입히는 곳 (fix) 은 그대로 회백으로 둠 (빨강으로 되돌리면 파랑 팀에서 빨강 점이 보임),
# 반대로 새 셰이더가 입히는데 stage 에선 아닌 곳 (spill) 은 곱해져 어두운 팀 색. 둘 다 넓이만 재서 찍음 (테스트 한도 MASK_MISMATCH_MAX)
fix = ms & ~mn
spill = mn & ~ms
print('RELOD mask px: stage %.4f new %.4f missing %.4f spill %.4f' % (ms.mean(), mn.mean(), fix.mean(), spill.mean()))
im_alb.pixels.foreach_set(alb.ravel())
im_alb.update()
scene.render.image_settings.file_format = 'JPEG'
scene.render.image_settings.quality = 90
im_alb.name = NAME + '_atlas_lod'
png = os.path.join(OUT, NAME + '_atlas_lod.png')
scene.render.image_settings.file_format = 'PNG'
im_alb.save_render(png, scene=scene)
for im, nm in ((im_ms, 'mask_src'), (im_mn, 'mask_new')):
    im.save_render(os.path.join(OUT, '%s_%s.png' % (NAME, nm)), scene=scene)
# 셰이더가 읽는 몸 색 칸 마스크 (한 채널): stage 꼭짓점 보간값 0.5 가 경계, 기울기를 MASK_SOFT 배로
mk = np.clip((px(im_ms)[:, :, 0] - 0.5) * MASK_SOFT + 0.5, 0.0, 1.0)
im_mk = make_image(NAME + '_mask_lod', data=True)
buf = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
buf[:, :, 0] = buf[:, :, 1] = buf[:, :, 2] = mk
buf[:, :, 3] = 1.0
im_mk.pixels.foreach_set(buf.ravel())
im_mk.update()
scene.render.image_settings.color_mode = 'BW'
im_mk.save_render(os.path.join(OUT, NAME + '_mask_lod.png'), scene=scene)
scene.render.image_settings.color_mode = 'RGB'
print('RELOD mask texture: coverage %.4f' % mk.mean())
scene.render.image_settings.file_format = 'JPEG'
jpg = os.path.join(OUT, NAME + '_atlas_lod.jpg')
im_alb.save_render(jpg, scene=scene)

# ---- 5. 최종 재질 + 뼈대 + 내보내기 ----
mat = bpy.data.materials.new(NAME + '_lod')
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes['Principled BSDF']
tex = nt.nodes.new('ShaderNodeTexImage')
fin = bpy.data.images.load(jpg)
fin.name = NAME + '_atlas_lod'
fin.pack()
tex.image = fin
nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value = 1.0
bsdf.inputs['Metallic'].default_value = 0.0
new.data.materials.clear()
new.data.materials.append(mat)
am = new.modifiers.new('Armature', 'ARMATURE')
am.object = arm
new.parent = arm
select_only(arm, new)
for o in list(bpy.data.objects):
    if o not in (arm, new):
        bpy.data.objects.remove(o, do_unlink=True)
new.name = NAME + '_lod1'
new.data.name = NAME + '_lod1'
select_only(arm, new)
out_glb = os.path.join(OUT, NAME + '_relod.glb')
bpy.ops.export_scene.gltf(filepath=out_glb, export_format='GLB', use_selection=True, export_animations=False, export_skins=True, export_apply=False,
                          export_image_format='JPEG', export_jpeg_quality=90, export_vertex_color='ACTIVE', export_all_vertex_colors=False, export_texcoords=True, export_normals=True, export_yup=True)
print('RELOD attrs', [(a.name, a.domain, a.data_type) for a in new.data.attributes if not a.name.startswith('.')], [c.name for c in new.data.color_attributes])
print('RELOD done', out_glb)
