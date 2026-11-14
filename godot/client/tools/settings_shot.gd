# 설정 창 캡처 + 안 넘치는지 검사 (W49): 창 크기마다·UI 배율 (auto 또는 1·2 …) 마다 한 장, 설정 창 상자가 화면 (UI 좌표) 안인지 출력.
# xvfb-run -a -s "-screen 0 2880x1800x24" godot --path godot/client --rendering-driver opengl3 --resolution 960x540 -s res://tools/settings_shot.gd -- <출력.png> [UI 배율 auto|1|2 …] [motion|keys = 그 탭 열기]
extends SceneTree

var st: Control
var frames := 0
var out := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var sc = a[1] if a.size() > 1 else "auto"
	var v = root.get_node("View")
	v.settings["uiScale"] = sc if sc == "auto" else float(sc)
	change_scene_to_file.call_deferred("res://main.tscn")


func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		root.get_node("View").apply_ui_scale()
	if frames == 58: # main 이 켜진 뒤 한 번 더 (UI 배율 설정이 main 시작에 덮이지 않게)
		var v2 = root.get_node("View")
		var a2 := OS.get_cmdline_user_args()
		v2.settings["uiScale"] = a2[1] if a2.size() > 1 and a2[1] == "auto" else (float(a2[1]) if a2.size() > 1 else "auto")
		v2.apply_ui_scale()
	if frames == 60:
		st = _find(root)
		st.visible = true
		var a := OS.get_cmdline_user_args()
		for t in ["motion", "keys"]:
			if a.has(t):
				st.open_tab(t)
	if frames == 75:
		var box: Control = st.box
		var vr := root.get_visible_rect()
		var r := box.get_global_rect()
		var ok := r.position.x >= -0.5 and r.position.y >= -0.5 and r.end.x <= vr.size.x + 0.5 and r.end.y <= vr.size.y + 0.5
		print("SHOT win=%s ui=%s box=%s ok=%s" % [str(root.size), str(vr.size), str(r), str(ok)])
		if OS.get_cmdline_user_args().has("rows"):
			for c in st.box.get_child(0).get_children():
				print("ROW %s h=%.0f vis=%s" % [c.get_class() + ":" + str(c.get("text") if c is Label else ""), (c as Control).size.y, str((c as Control).visible)])
		root.get_texture().get_image().save_png(out)
		return true
	return false


func _find(n: Node) -> Control:
	if n.get_script() != null and str(n.get_script().resource_path) == "res://ui/settings.gd":
		return n
	for c in n.get_children():
		var r := _find(c)
		if r != null:
			return r
	return null
