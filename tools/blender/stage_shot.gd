# W19 확인 그림: 대기실 무대 빛 (흰 빛, 앰비언트 검정) 으로 몸을 나란히 그려 PNG 하나 (화면 필요 — xvfb-run).
# 실행 (레포 뿌리): xvfb-run -a -s "-screen 0 1600x1000x24" <godot> --path godot/client -s ../../tools/blender/stage_shot.gd -- <out.png> [stage|high|medium|low] [ext] [faces|turn]
#   stage = 대기실·초상 LOD (Portrait.still_body), high|medium|low = 판 화질 LOD · ext 면 Blender 몸만 (빨강·청록·노랑), 없으면 구운 몸 3 + Blender 3 · faces 면 얼굴 가까이 표정 3 (기합·맞음·기본)
extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var lod_mode: String = a[1] if a.size() > 1 else "stage"
	var Body = load("res://chars/body.gd")
	var Chars = load("res://chars/chars.gd")
	var P = load("res://ui/portrait.gd")
	var Gfx = load("res://world/gfx.gd")
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1500, 900)
	vp.transparent_bg = false
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
	var cols := [Color.html("e05050"), Color.html("40d0c0"), Color.html("e0c050")]
	var i := 0
	for ext in ([true] if a.size() > 2 and a[2] == "ext" else [false, true]):
		for c in cols:
			Body.use_ext = ext
			var b
			if lod_mode == "stage":
				b = P.still_body(Chars, "tank", c)
			else:
				Gfx.plan = {"level": lod_mode}
				b = Chars.make_body("tank", c)
				P.stage_light(b)
			var t := Node3D.new()
			t.position = Vector3(0, 0, (-1.4 + i * 1.4) if a.size() > 2 else (-3.5 + i * 1.4))
			t.rotation.y = deg_to_rad(25.0 if i % 2 == 0 else -20.0)
			if a.size() > 3 and a[3] == "turn": # 정면·옆·뒤 (등 방패 밀착 확인)
				t.rotation.y = deg_to_rad([0.0, 90.0, 180.0][i % 3])
			vp.add_child(t)
			t.add_child(b)
			for k in 20:
				b.pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "emote": -1}, k * 16.0)
			if a.size() > 3 and a[3] == "faces" and b.ext != null: # 표정 확인: 0 기본 · 1 맞음 · 2 기합
				if i == 1:
					b.was_stunned = true
				elif i == 2:
					b.cur_act = {"move": "x"}
				b.ext.sync()
				t.rotation.y = deg_to_rad(12.0)
			i += 1
	var cam := Camera3D.new()
	cam.fov = 24
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(11.0 if a.size() > 2 else 19.0, 1.3, 0), Vector3(0, 1.05, 0), Vector3.UP)
	if a.size() > 3 and a[3] == "faces":
		cam.fov = 13
		cam.look_at_from_position(Vector3(11.0, 1.75, 0), Vector3(0, 1.62, 0), Vector3.UP)
	cam.current = true
	for k in 8:
		await process_frame
	vp.get_texture().get_image().save_png(out)
	quit()
