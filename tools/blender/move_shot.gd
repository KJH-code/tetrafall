# W20 확인 그림: 대기실 무대 빛으로 탱크 3인칭 몸을 동작별 자세 (act 를 그 단계에 멈춤) 로 나란히 한 장. 방패·해머가 손·등·앞에 붙는지 눈으로 봄.
# SHOT_CHAR=<캐릭터 id> 환경 변수로 다른 캐릭터 (기본 tank).
# 실행 (레포 뿌리): xvfb-run -a -s "-screen 0 1700x900x24" <godot> --path godot/client -s ../../tools/blender/move_shot.gd -- <out.png> [yaw 도, 기본 35] [stage|high]
extends SceneTree
const MOVES := [["", "", 0.0], ["주먹", "strike", 0.5], ["어깨 박치기", "strike", 0.5], ["방패 올려치기", "wind", 0.9], ["방패 올려치기", "strike", 0.6], ["방패 내려치기", "strike", 0.5]]
# SHOT_FOV (기본 26)·SHOT_DIST (기본 19) 로 확대, 동작 수만큼 가운데 정렬.
# SHOT_MOVES="동작:strike|wind:u;…" 로 동작 목록을 바꿈 (닌자 예: SHOT_MOVES=";베기:strike:0.5;반대 베기:strike:0.5;표창:strike:0.5;ninjaDash:strike:0.5;공중 베기:wind:0.9")
func _moves() -> Array:
	var env := OS.get_environment("SHOT_MOVES")
	if env == "":
		return MOVES
	var out := []
	for e in env.split(";"):
		var f := e.split(":")
		out.append([f[0], f[1] if f.size() > 1 else "", float(f[2]) if f.size() > 2 else 0.0])
	return out
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var yaw: float = float(a[1]) if a.size() > 1 else 35.0
	var Body = load("res://chars/body.gd")
	var Chars = load("res://chars/chars.gd")
	var P = load("res://ui/portrait.gd")
	Body.use_ext = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1900, 700)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.15, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	vp.add_child(light)
	light.look_at_from_position(Vector3(3, 4, 2), Vector3.ZERO, Vector3.UP)
	var bodies := []
	var MV := _moves()
	for i in MV.size():
		var b = P.still_body(Chars, OS.get_environment("SHOT_CHAR") if OS.get_environment("SHOT_CHAR") != "" else "tank", Color.html("e05050"))
		var t := Node3D.new()
		t.position = Vector3(0, 0, (i - (MV.size() - 1) / 2.0) * 2.1)
		t.rotation.y = deg_to_rad(yaw)
		vp.add_child(t)
		t.add_child(b)
		bodies.append(b)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("SHOT_FOV")) if OS.get_environment("SHOT_FOV") != "" else 26.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(float(OS.get_environment("SHOT_DIST")) if OS.get_environment("SHOT_DIST") != "" else 19.0, 1.4, 0), Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	for k in 14:
		for i in bodies.size():
			var m: Array = MV[i]
			if str(m[0]) != "":
				var tt := Time.get_ticks_msec() / 1000.0
				var u: float = m[2]
				var rec := {"id": 9000 + i, "move": m[0], "t0": tt - 0.3, "windup": 0.3, "struck": null, "rec": 0.5, "broken": null, "air": false}
				if m[1] == "wind":
					rec.t0 = tt - u * 0.3
				else:
					rec.struck = tt - u * 0.2
				bodies[i].act = rec
			bodies[i].pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "emote": -1}, k * 16.0)
		await process_frame
	vp.get_texture().get_image().save_png(out)
	quit()
