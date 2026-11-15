# 새 모델 색그림 그림판가 영상 메모리에 얼마나 상주하는가 (W39 항목 2): 한 프로세스에 장면 하나를 만들고 영상 메모리·그림판 메모리·몸 만들기 ms 를 찍음.
# xvfb-run -a godot --path godot/client --rendering-driver opengl3 --resolution 960x540 -s res://tools/tex_meas.gd -- --scene menu|lobby|game8|game4|first8 [--warm] [--no-lazy-tex] [--level high|medium|low]
#   menu   = 메뉴에서 쉰 상태 (request_all + 미리 데우기만, 몸 없음)
#   lobby  = 대기실: 내 캐릭터 (ninja) 큰 몸 (stage) 한 명
#   game8  = 판 몸 8명 (닌자·탱크·사냥꾼·갈고리 ×2, 3인칭) · game4 = 4명 · first8 = 1인칭 (내 몸 = 1인칭 쌍둥이 stage·남 7명은 판 몸)
# 소프트웨어 렌더라 ms 는 어림 (읽기·몸 만들기 CPU), 영상 메모리는 Mesa 가 보고하는 값.
extends SceneTree

const Hitch := preload("res://core/hitch.gd")
var scene := "game8"
var warm := false
var Chars
var Body
var Ext
var host: Node3D
var frames := 0
var phase := "warm"
var built := false
var list: Array = []
var t_build := []


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--scene")
	if i >= 0:
		scene = str(a[i + 1])
	warm = a.has("--warm")
	i = a.find("--level")
	if i >= 0:
		load("res://world/gfx.gd").plan = {"level": str(a[i + 1])}
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 6.0)
	root.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.4, 0)
	root.add_child(sun)
	host = Node3D.new()
	root.add_child(host)
	Chars = load("res://chars/chars.gd")
	Body = load("res://chars/body.gd")
	Ext = load("res://chars/external.gd")
	Body.use_ext = true
	Hitch.on = true
	var four := ["ninja", "tank", "hunter", "hook"]
	match scene:
		"game8", "first8":
			list = four + four
		"game4":
			list = four
		"lobby":
			list = ["ninja"]


func _cached() -> String:
	var out := []
	for id in ["ninja", "tank", "hunter", "hook"]:
		for suf in ["", "_lod1", "_lod2", "_lod3"]:
			var p := "res://assets/models/ext/%s_%s_atlas%s.jpg" % [id, id, suf]
			if ResourceLoader.has_cached(p):
				out.append("%s%s" % [id, suf if suf != "" else "_stage"])
	return " ".join(out)


func _mon() -> String:
	return "영상 %.1fMB · 그림판 %.1fMB" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0]


func _process(_d: float) -> bool:
	frames += 1
	if phase == "warm":
		if warm:
			if frames == 1:
				Ext.request_all()
			if not Ext.warm_step(host, func(id, col): return Chars.make_body(id, col)):
				return false
		phase = "settle0"
		frames = 0
		return false
	if phase == "settle0":
		if frames > 6:
			print("TEX_MEAS [%s%s lazy=%s] 몸 만들기 전: %s · 올라와 있는 색그림: %s" % [scene, " warm" if warm else "", Ext.lazy_tex, _mon(), _cached()])
			phase = "build"
		return false
	if phase == "build":
		for k in list.size():
			var id: String = list[k]
			var t0 := Time.get_ticks_usec()
			var b
			if scene == "lobby":
				Ext.stage = true
				b = Chars.make_body(id, Color(0.9, 0.3, 0.3))
				Ext.stage = false
			elif scene == "first8" and k == 0:
				b = Body.new()
				b.build(id, Color(0.9, 0.3, 0.3), false) # 1인칭 쌍둥이 (판 몸 아님)
			else:
				b = Chars.make_body(id, Color.from_hsv(k / 8.0, 0.7, 0.9))
			t_build.append("%s %.1f" % [id, (Time.get_ticks_usec() - t0) / 1000.0])
			host.add_child(b)
			b.position = Vector3((k - 3.5) * 1.1, 0, 0)
		phase = "settle1"
		frames = 0
		return false
	if phase == "settle1":
		if frames > 10:
			print("TEX_MEAS [%s%s lazy=%s] 몸 %d명 뒤: %s · 색그림: %s · 몸 만들기 ms: %s" % [scene, " warm" if warm else "", Ext.lazy_tex, list.size(), _mon(), _cached(), ", ".join(t_build)])
			return true
	return false
