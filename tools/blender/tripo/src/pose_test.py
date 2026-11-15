import bpy,math,sys
from mathutils import Vector,Euler
f,out=sys.argv[-2],sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f)
arm=[o for o in bpy.context.scene.objects if o.type=='ARMATURE'][0]
ob=[o for o in bpy.context.scene.objects if o.type=='MESH'][0]
sc=bpy.context.scene;sc.render.engine='BLENDER_EEVEE_NEXT';sc.render.resolution_x=500;sc.render.resolution_y=700
w=bpy.data.worlds.new('w');sc.world=w;w.use_nodes=True;w.node_tree.nodes['Background'].inputs[0].default_value=(.4,.42,.47,1)
l=bpy.data.lights.new('s','SUN');l.energy=3;o=bpy.data.objects.new('s',l);sc.collection.objects.link(o);o.rotation_euler=(.9,.2,.6)
vs=[ob.matrix_world@v.co for v in ob.data.vertices]
mn=Vector([min(v[i] for v in vs) for i in range(3)]);mx=Vector([max(v[i] for v in vs) for i in range(3)])
print('BBOX',mn,mx)
c=(mn+mx)/2;h=(mx-mn).length
cam=bpy.data.cameras.new('c');cam.lens=60;co=bpy.data.objects.new('c',cam);sc.collection.objects.link(co);sc.camera=co
bpy.context.view_layer.objects.active=arm;bpy.ops.object.mode_set(mode='POSE')
pb=arm.pose.bones
def rot(n,e):
    b=pb['mixamorig:'+n];b.rotation_mode='XYZ';b.rotation_euler=Euler([math.radians(x) for x in e])
poses={'rest':{},'armup':{'LeftArm':(0,0,-80),'RightArm':(0,0,80),'LeftForeArm':(-60,0,0)},
 'squat':{'LeftUpLeg':(-90,0,0),'RightUpLeg':(-90,0,0),'LeftLeg':(110,0,0),'RightLeg':(110,0,0),'Spine':(25,0,0)},
 'stride':{'LeftUpLeg':(-45,0,0),'RightUpLeg':(35,0,0),'LeftLeg':(50,0,0),'RightArm':(-40,0,0),'LeftArm':(40,0,0),'LeftForeArm':(-70,0,0)}}
for k,p in poses.items():
    for b in pb:b.rotation_mode='XYZ';b.rotation_euler=(0,0,0);b.location=(0,0,0)
    for n,e in p.items():rot(n,e)
    bpy.context.view_layer.update()
    for i,a in enumerate((90,0)):
        t=math.radians(a);r=h*2.2
        co.location=c+Vector((r*math.cos(t-math.pi/2),r*math.sin(t-math.pi/2),0))
        co.rotation_euler=(c-co.location).to_track_quat('-Z','Y').to_euler()
        sc.render.filepath=f'{out}_{k}_{i}.png';bpy.ops.render.render(write_still=True)
