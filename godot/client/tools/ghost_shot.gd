# 반투명 몸 (유령화·무적) 확인 (W35): 캐릭터마다 ghost (유령화) 또는 shield (무적 깜빡) 몸을 옆에서 비스듬히 찍어 PNG 한 장에 나란히
# xvfb-run -a -s "-screen 0 1280x520x24" godot --path godot/client --rendering-driver opengl3 --resolution 1280x520 -s res://tools/ghost_shot.gd -- <저장 png> [캐릭터,캐릭터…] [ghost|shield|none] [--no-ext]
extends SceneTree

var out := ""
var bodies: Array = []
var frames := 0
var mode := "ghost"
var cam := Camera3D.new()


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "user://ghost.png"
	var ids: Array = (a[1].split(",") if a.size() > 1 and not a[1].begins_with("--") else ["tank", "ninja", "hunter", "hook", "bard", "berserker", "cannon", "builder"])
	mode = a[2] if a.size() > 2 and not a[2].begins_with("--") else "ghost"
	RenderingServer.set_default_clear_color(Color(0.55, 0.65, 0.8))
	var Chars = load("res://chars/chars.gd")
	var P = load("res://ui/portrait.gd")
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.look_at_from_position(Vector3(3, 5, 4), Vector3.ZERO)
	for i in ids.size():
		var b = P.still_body(Chars, str(ids[i]), Color(0.9, 0.3, 0.3))
		b.position = Vector3((i - (ids.size() - 1) / 2.0) * 1.5, 0, 0)
		b.rotation.y = 0.9
		root.add_child(b)
		bodies.append(b)
	root.add_child(cam)
	cam.fov = 30
	cam.look_at_from_position(Vector3(0, 1.1, 8.5 + ids.size() * 0.5), Vector3(0, 0.9, 0))
	cam.current = true


func _process(_d: float) -> bool:
	frames += 1
	for b in bodies:
		var p := {"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "noIdle": true}
		if mode == "ghost":
			p.ghostLeft = 1000.0
		elif mode == "shield":
			p.shieldLeft = 1000.0
		b.pose(p, float(Time.get_ticks_msec()))
	if frames < 12:
		return false
	var wrapped := 0
	var total := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m = (mi as MeshInstance3D).material_override
		if m != null and mi.visible:
			total += 1
			if m is ShaderMaterial and m.shader.resource_path.ends_with("ghost_depth.gdshader"):
				wrapped += 1
	print("[ghost_shot] 보이는 메시 ", total, " 중 prepass ", wrapped)
	root.get_texture().get_image().save_png(out)
	print("[ghost_shot] ", out, " (", mode, ")")
	return true
