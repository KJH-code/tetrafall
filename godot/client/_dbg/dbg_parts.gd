extends SceneTree
const T := preload("res://tests/test_baked.gd")
const Body := preload("res://chars/body.gd")

func lab_points(b) -> Array:
	var out := []
	var bt = b.batch
	if bt == null:
		var o2 := []
		for mi in b.frame.find_children("*", "MeshInstance3D", true, false):
			if mi.layers == 0 or not T._shown(mi, b.frame):
				continue
			var m = mi.material_override
			var col: Color = (m as StandardMaterial3D).albedo_color if m is StandardMaterial3D else Color((m as ShaderMaterial).get_shader_parameter("albedo"))
			var rel := T._rel(mi, b.frame)
			for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				o2.append([rel * v, col, "P:" + str(b.frame.get_path_to(mi))])
		return o2
	var arr: Array = bt.mi.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	if b.baked:
		var sv: Array = bt.skinned()
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		for i in (sv[0] as PackedVector3Array).size():
			var bi: int = sv[1][i]
			if bt.shown(bt.pieces[bi]):
				out.append([sv[0][i], b.skin_color if uv2[i].x > 0.5 else cols[i], "B:" + str(b.frame.get_path_to(bt.pieces[bi]))])
	else:
		var got: PackedVector3Array = bt.skinned_vertices()
		var k := 0
		for p in bt.pieces:
			var n: int = p.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
			if bt.shown(p):
				for j in n:
					out.append([got[k + j], cols[k + j], "B:" + str(b.frame.get_path_to(p))])
			k += n
	for mi in b.frame.find_children("*", "MeshInstance3D", true, false):
		if mi.layers == 0 or mi == bt.mi or not T._shown(mi, b.frame):
			continue
		var m = mi.material_override
		var col: Color = (m as StandardMaterial3D).albedo_color if m is StandardMaterial3D else Color((m as ShaderMaterial).get_shader_parameter("albedo"))
		var rel := T._rel(mi, b.frame)
		for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			out.append([rel * v, col, "M:" + str(b.frame.get_path_to(mi))])
	return out

func miss_by(a: Array, b: Array) -> Dictionary:
	var res := {}
	for p in a:
		var ok := false
		for q in b:
			if (q[0] as Vector3).distance_to(p[0]) < 2e-3:
				var ca: Color = p[1]; var cb: Color = q[1]
				if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) < 0.02:
					ok = true; break
		if not ok:
			var key: String = p[2]
			if res.get(key, 0) < 2:
				var best = null; var bd := 1e9
				for q in b:
					var dd: float = (q[0] as Vector3).distance_to(p[0])
					if dd < bd: bd = dd; best = q
				print("   ", key.get_file(), " p=", p[0], " c=", p[1], " | nearest d=", bd, " c=", best[1], " ", str(best[2]).get_file())
			res[key] = res.get(key, 0) + 1
	return res

func _initialize() -> void:
	var t = T.new()
	var chs := OS.get_cmdline_user_args()
	for ch in chs:
		var glb := OS.get_environment("DBG") != "old"
		var g = t._body(ch, Color(0.8, 0.5, 0.2), true, glb)
		var o = t._body(ch, Color(0.8, 0.5, 0.2), false, glb)
		print(ch, " shown ", T._show_parts(g), " / ", T._show_parts(o))
		var pa := lab_points(g)
		var pb := lab_points(o)
		print(" glb-only: ", miss_by(pa, pb))
		print(" old-only: ", miss_by(pb, pa))
		g.free(); o.free()
	quit()
