# 갈고리 '이음' 삼각형 찾기 (W34): 쉬는 자세에선 작은데 (모서리 < 4 cm) 오른팔을 여러 방향으로 움직이면 3배·6 cm 넘게 늘어나는 삼각형 = 원본 코트-주먹 한 덩어리를 잇던 것 (팔을 움직이면 허공에서 가는 줄 모양으로 찢어져 보임).
# 메시마다 삼각형 번호 목록을 JSON 으로 → drop_shards.mjs (BRIDGE_JSON) 가 뺌.
# blender -b --factory-startup -P tools/blender/tripo/hook_bridge.py -- <hook.glb> <출력.json>
import bpy, math, json, itertools, sys
import numpy as np
from mathutils import Euler
E=sys.argv[sys.argv.index('--')+1]
OUT=sys.argv[sys.argv.index('--')+2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=E)
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
bpy.context.view_layer.objects.active=arm
bpy.ops.object.mode_set(mode='POSE')
pb=arm.pose.bones;P='mixamorig:'
def pose(d):
    for b in pb: b.rotation_mode='XYZ'; b.rotation_euler=(0,0,0)
    for n,e in d.items(): pb[P+n].rotation_euler=Euler([math.radians(x) for x in e])
    bpy.context.view_layer.update()
POS=[]
for ax in (-160,-110,-60,0,50):
    for az in (-80,-40,0,40,80):
        for fe in (0,-70):
            POS.append({"RightArm":(ax,0,az),"RightForeArm":(fe,0,0)})
POS.append({"RightArm":(-40,0,0),"RightForeArm":(-40,0,0),"Spine":(30,0,0),"Spine1":(15,0,0)})
res={}
for ob in [o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('hook_lod')]:
    me=ob.data
    tri=np.array([list(p.vertices) for p in me.polygons])
    def positions():
        dg=bpy.context.evaluated_depsgraph_get()
        e=ob.evaluated_get(dg); m=e.to_mesh()
        a=np.array([list(ob.matrix_world@v.co) for v in m.vertices]); e.to_mesh_clear(); return a
    def el(p): return np.max([np.linalg.norm(p[tri[:,i]]-p[tri[:,(i+1)%3]],axis=1) for i in range(3)],axis=0)
    pose({}); r0=el(positions())
    bad=set()
    for d in POS:
        pose(d); e=el(positions())
        idx=np.where((e>np.maximum(r0*3.0,0.06))&(r0<0.04))[0]
        bad.update(int(i) for i in idx)
    pose({}); rest=positions()
    c=np.array([rest[tri[i]].mean(0) for i in bad]) if bad else np.zeros((0,3))
    print('BRIDGE',ob.name,len(me.polygons),len(bad), (c.min(0).round(3),c.max(0).round(3)) if len(c) else '')
    res[ob.name]=sorted(bad)
json.dump(res,open(OUT,'w'))
