# 대기실 캐릭터 바꾸기 연속 캡처 (W27): 이전 캐릭터 → 새 캐릭터, 바꾼 순간부터 3초, 프레임마다 팔 내림 (1 = 아래, 0 = 수평 T) 기록 + 0.1초마다 그림
# xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot/client --rendering-driver opengl3 --resolution 1280x720 -s res://tools/switch_shot.gd -- <폴더> <새 캐릭터> [이전 캐릭터 bard]
extends SceneTree
var stage
var frames := 0
var t0 := 0
var out := ""
var next_shot := 0
var log_lines: Array = []
func _initialize() -> void:
	RenderingServer.set_default_clear_color(Color(0.1, 0.1, 0.14))
	var a := OS.get_cmdline_user_args()
	out = a[0]
	if a.size() > 3 and a[3] == "noext":
		load("res://chars/body.gd").use_ext = false
	DirAccess.make_dir_recursive_absolute(out)
	root.add_child(load("res://ui/portrait.gd").new())
	stage = load("res://ui/char_stage.gd").new()
	stage.size = Vector2(180, 260)
	root.add_child(stage)
func _down() -> float:
	var b = stage.body
	if b == null or b.ext == null:
		return -9.0
	var worst := 1.0
	for side in ["Left", "Right"]:
		var p = b.ext.bone_point(side + "Arm")
		var f = b.ext.bone_point(side + "ForeArm")
		if p == null or f == null:
			return -9.0
		worst = minf(worst, -((f as Vector3) - (p as Vector3)).normalized().y)
	return worst
func _process(_d: float) -> bool:
	frames += 1
	var a := OS.get_cmdline_user_args()
	if frames == 1:
		stage.show_char(a[2] if a.size() > 2 else "bard", Color(0.85, 0.2, 0.2))
	if frames == 30:
		stage.show_char(a[1], Color(0.85, 0.2, 0.2))
		t0 = Time.get_ticks_msec()
		print("SWITCH to ", a[1])
	if frames >= 30 and t0 > 0:
		var el := Time.get_ticks_msec() - t0
		log_lines.append("%d %.2f %s" % [el, _down(), "taunt" if Time.get_ticks_msec() - stage.picked_at < 1500 else ""])
		if el >= next_shot:
			stage.vp.get_texture().get_image().save_png("%s/%s_%04d.png" % [out, a[1], next_shot])
			next_shot += 100
		if el > 3000:
			var mn := 9.0
			for l in log_lines:
				mn = minf(mn, float(l.split(" ")[1]))
			for l in log_lines: print("LOG ", l)
			print("MIN_DOWN ", a[1], " ", mn, " frames ", log_lines.size())
			return true
	return false
