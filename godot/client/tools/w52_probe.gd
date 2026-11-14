# W52 닌자 dash 클립 날 곡선: 한 뼈의 회전을 클립 시각 따라 찍음. godot --headless -s res://tools/w52_probe.gd -- <캐릭터> <클립> <뼈> [t0 t1 dt]
extends SceneTree

const Clips := preload("res://chars/ext_clips.gd")
const Ext := preload("res://chars/external.gd")


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var ch := str(a[0]) if a.size() > 0 else "ninja"
	var nm := str(a[1]) if a.size() > 1 else "dash"
	var bone := str(a[2]) if a.size() > 2 else "mixamorig_RightArm"
	var info = Ext.load_char(ch)
	var cc: Dictionary = info.cfg.get("clips", {})
	var lib := Clips.load_lib(str(cc.get("file", "")))
	var d: Dictionary = lib[nm]
	var an: Animation = d.anim
	print("clip ", nm, " len ", d.len)
	var t0 := float(a[3]) if a.size() > 3 else 0.0
	var t1 := float(a[4]) if a.size() > 4 else float(d.len)
	var dt := float(a[5]) if a.size() > 5 else 0.02
	var prev := Quaternion.IDENTITY
	var t := t0
	while t <= t1 + 1e-6:
		var q: Quaternion = an.rotation_track_interpolate(int(d.rot[bone]), t)
		var ang := rad_to_deg(prev.angle_to(q)) if t > t0 else 0.0
		print("%.3f  %.4f %.4f %.4f %.4f  step %.1f" % [t, q.x, q.y, q.z, q.w, ang])
		prev = q
		t += dt
	quit()
