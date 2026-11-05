import bpy,bmesh,sys
a=sys.argv[sys.argv.index('--')+1:]
src,out,y0,y1,z0,z1=a[0],a[1],*map(float,a[2:6])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ob=[o for o in bpy.context.scene.objects if o.type=='MESH'][0]
bm=bmesh.new();bm.from_mesh(ob.data)
kill=[f for f in bm.faces if not (y0<=f.calc_center_median().y<=y1 and z0<=f.calc_center_median().z<=z1)]
bmesh.ops.delete(bm,geom=kill,context='FACES')
loose=[v for v in bm.verts if not v.link_faces];bmesh.ops.delete(bm,geom=loose,context='VERTS')
bm.to_mesh(ob.data);bm.free()
print('TRIS',len(ob.data.polygons))
vs=[v.co for v in ob.data.vertices]
print('BBOX',[(round(min(v[i] for v in vs),3),round(max(v[i] for v in vs),3)) for i in range(3)])
bpy.ops.export_scene.gltf(filepath=out,export_format='GLB',use_selection=False)
