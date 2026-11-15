# 판 LOD 모습 확인 캡처 (W31): 새 모델 (탱크·닌자·갈고리·사냥꾼) 을 화질 단계 (high·medium·low = 판 LOD) 별로 세 가지 몸 색 (빨강·파랑·초록) 으로 나란히 놓고
# 가까이 (3인칭 ≈ 4m) · 멀리 (≈ 11m) 두 컷씩 저장 → <폴더>/<캐릭터>_<단계>_<near|far>.png. 전후 비교는 예전 커밋을 다른 폴더에 풀어 같은 명령으로.
# xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot/client --rendering-driver opengl3 --resolution 1280x720 -s res://tools/lod_shot.gd -- <폴더> [캐릭터,…] [단계,…]
extends SceneTree

var out := ""
var ids: Array = ["tank", "ninja", "hook", "hunter"]
var levels: Array = ["high", "medium", "low"]
var jobs: Array = []
var cur := 0
var frames := 0
var host: Node3D
var cam: Camera3D
var Chars
var Body
const COLORS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.9), Color(0.2, 0.75, 0.3)]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "user://lod_shot"
	if a.size() > 1 and a[1] != "":
		ids = a[1].split(",")
	if a.size() > 2 and a[2] != "":
		levels = a[2].split(",")
	DirAccess.make_dir_recursive_absolute(out)
	RenderingServer.set_default_clear_color(Color(0.55, 0.7, 0.9))
	cam = Camera3D.new()
	cam.fov = 60
	root.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	root.add_child(sun)
	host = Node3D.new()
	root.add_child(host)
	Chars = load("res://chars/chars.gd")
	Body = load("res://chars/body.gd")
	Body.use_ext = true
	for id in ids:
		for lv in levels:
			for view in ["near", "far"]:
				jobs.append([id, lv, view])


func _process(_d: float) -> bool:
	frames += 1
	if cur >= jobs.size():
		return true
	var j: Array = jobs[cur]
	if frames == 1:
		for c in host.get_children():
			c.free()
		load("res://world/gfx.gd").plan = {"level": j[1]}
		var dist := 4.0 if j[2] == "near" else 11.0
		for i in 3:
			var b = Chars.make_body(j[0], COLORS[i])
			host.add_child(b)
			b.position = Vector3((i - 1) * (1.1 if j[2] == "near" else 3.0), 0, 0)
			b.rotation.y = 0.35 * (i - 1)
		cam.position = Vector3(0, 1.25 if j[2] == "near" else 2.2, dist)
		cam.look_at(Vector3(0, 0.55 if j[2] == "near" else 0.5, 0))
	elif frames == 6:
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, j[0], j[1], j[2]])
		cur += 1
		frames = 0
	return false
