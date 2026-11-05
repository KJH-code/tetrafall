import bpy,math,sys
from mathutils import Vector
f,out=sys.argv[-2],sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f)
ob=[o for o in bpy.context.scene.objects if o.type=='MESH'][0]
vs=[ob.matrix_world@v.co for v in ob.data.vertices]
mn=Vector([min(v[i] for v in vs) for i in range(3)]);mx=Vector([max(v[i] for v in vs) for i in range(3)])
c=(mn+mx)/2;h=(mx-mn).length
sc=bpy.context.scene;sc.render.engine='BLENDER_EEVEE_NEXT'
sc.render.resolution_x=600;sc.render.resolution_y=800
w=bpy.data.worlds.new('w');sc.world=w;w.use_nodes=True
w.node_tree.nodes['Background'].inputs[0].default_value=(.4,.42,.47,1)
for ang,e in ((0.6,3),(3.7,2)):
    l=bpy.data.lights.new('s','SUN');l.energy=e;o=bpy.data.objects.new('s',l);sc.collection.objects.link(o);o.rotation_euler=(.9,.2,ang)
cam=bpy.data.cameras.new('c');cam.lens=60;co=bpy.data.objects.new('c',cam);sc.collection.objects.link(co);sc.camera=co
for i,a in enumerate((0,90,180,270)):
    t=math.radians(a);r=h*2.3
    co.location=c+Vector((r*math.cos(t),r*math.sin(t),0))
    co.rotation_euler=(c-co.location).to_track_quat('-Z','Y').to_euler()
    sc.render.filepath=f'{out}_{i}.png';bpy.ops.render.render(write_still=True)
