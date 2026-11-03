extends SceneTree
const T := preload("res://tests/test_baked.gd")

func _initialize() -> void:
	var t = T.new()
	for ch in OS.get_cmdline_user_args():
		var g = t._body(ch, Color(0.8, 0.5, 0.2), true, true)
		var g0 = t._body(ch, Color(0.8, 0.5, 0.2), true, true)
		T._show_parts(g)
		var bt = g.batch
		var sk: Skeleton3D = bt.skel
		var glob: Array[Transform3D] = []
		for b in bt.pieces.size():
			var par := sk.get_bone_parent(b)
			glob.append((glob[par] if par >= 0 else Transform3D()) * sk.get_bone_pose(b))
		var binds := {}
		for k in bt.mi.skin.get_bind_count():
			binds[sk.find_bone(bt.mi.skin.get_bind_name(k))] = bt.mi.skin.get_bind_pose(k)
		for b in bt.pieces.size():
			var n: Node3D = bt.pieces[b]
			var rel := T._rel(n, g.frame)
			var e1: float = (glob[b].origin - rel.origin).length() + (glob[b].basis.x - rel.basis.x).length() + (glob[b].basis.y - rel.basis.y).length() + (glob[b].basis.z - rel.basis.z).length()
			var rest: Transform3D = binds[b].affine_inverse() if binds.has(b) else Transform3D()
			var n0: Node3D = g0.batch.pieces[b]
			var rel0 := T._rel(n0, g0.frame)
			var e2: float = (rest.origin - rel0.origin).length() + (rest.basis.x - rel0.basis.x).length()+ (rest.basis.y - rel0.basis.y).length()+ (rest.basis.z - rel0.basis.z).length()
			if e1 > 1e-3 or e2 > 1e-3:
				print(ch, " bone ", sk.get_bone_name(b), " ", g.frame.get_path_to(n), " pose-vs-node ", e1, " bind-vs-rest ", e2, " vis0 ", n0.visible, " scale ", n.scale, " parentscale ", (n.get_parent() as Node3D).scale)
		g.free(); g0.free()
	quit()
