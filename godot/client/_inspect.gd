extends SceneTree
func _initialize():
	var s = load("res://assets/models/ext/tank.glb")
	var r = s.instantiate()
	_dump(r, 0)
	for sk in r.find_children("*", "Skeleton3D", true, false):
		print("SKEL ", sk.get_path(), " bones ", sk.get_bone_count())
		for i in sk.get_bone_count():
			print("  ", i, " ", sk.get_bone_name(i), " par ", sk.get_bone_parent(i), " rest ", sk.get_bone_rest(i).origin, " g ", sk.get_bone_global_rest(i).origin)
	for ap in r.find_children("*", "AnimationPlayer", true, false):
		print("ANIMS ", ap.get_animation_list())
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var m = mi.mesh
		print("MESH ", mi.name, " surf ", m.get_surface_count(), " skin ", mi.skin != null, " skel ", mi.skeleton, " aabb ", m.get_aabb(), " blend ", m.get_blend_shape_count() if m is ArrayMesh else -1)
		for i in m.get_surface_count():
			var mat = m.surface_get_material(i)
			print("   s", i, " ", mat, " ", mat.albedo_color if mat is BaseMaterial3D else "", " tex ", mat.albedo_texture if mat is BaseMaterial3D else "")
	quit()
func _dump(n, d):
	var extra = ""
	if n is Node3D: extra = str(n.position) + " " + str(n.scale)
	print("  ".repeat(d), n.name, " [", n.get_class(), "] ", extra)
	if d < 3 or not (n is BoneAttachment3D):
		for c in n.get_children(): _dump(c, d+1)
