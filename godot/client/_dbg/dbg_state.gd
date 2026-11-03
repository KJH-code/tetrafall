extends SceneTree
const T := preload("res://tests/test_baked.gd")
const P := preload("res://_dbg/dbg_parts.gd")
const C := preload("res://core/config.gd")

func _initialize() -> void:
	var t = T.new()
	var pp = P.new()
	var a := OS.get_cmdline_user_args()
	var ch: String = a[0]
	var st: Dictionary = JSON.parse_string(a[1])
	var merge := OS.get_environment("MERGE") == "1"
	var g = t._body(ch, Color(0.8, 0.5, 0.2), merge, true)
	var o = t._body(ch, Color(0.8, 0.5, 0.2), false, false)
	var p: Dictionary = {"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.3}
	p.merge(st, true)
	for i in 40:
		for b in [g, o]:
			b.dizzy = C.BERSERK_DIZZY_S
			b.pose(p, i * 16.0)
	var pa = pp.lab_points(g)
	var pb = pp.lab_points(o)
	print(" glb-only: ", pp.miss_by(pa, pb))
	print(" old-only: ", pp.miss_by(pb, pa))
	g.free(); o.free()
	quit()
