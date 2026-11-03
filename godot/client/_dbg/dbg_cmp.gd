extends SceneTree
const T := preload("res://tests/test_baked.gd")
const P := preload("res://_dbg/dbg_parts.gd")

func _initialize() -> void:
	var t = T.new()
	var p = P.new()
	for ch in OS.get_cmdline_user_args():
		var g = t._body(ch, Color(0.8, 0.5, 0.2), OS.get_environment("MERGE") == "1", true)
		var o = t._body(ch, Color(0.8, 0.5, 0.2), false, false)
		print(ch, " shown ", T._show_parts(g), " / ", T._show_parts(o))
		var pa = p.lab_points(g)
		var pb = p.lab_points(o)
		print(" glb-only: ", p.miss_by(pa, pb))
		print(" old-only: ", p.miss_by(pb, pa))
		g.free(); o.free()
	quit()
