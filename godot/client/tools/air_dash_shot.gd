# W34 공중 대시 자세 확인 캡처: 4명 (또는 인자) 을 옆에서 (몸 기울임 포함, 게임과 같은 길) 큰 칸으로 한 장에 — 무기 (해머·소총) 가 팔을 따라 어떻게 놓이는지.
# 넷째 인자 = 손목 시험 JSON (cfg.dash_wrist 덮어쓰기, 예: '{"hand_R":[0,60,0]}')
# xvfb-run -a -s "-screen 0 1600x500x24" godot --path godot/client --rendering-driver opengl3 --resolution 1600x500 -s res://tools/air_dash_shot.gd -- <out.png> [캐릭터,…] [yaw 기본 90 = 옆]
extends SceneTree

const C := preload("res://core/config.gd")


func _initialize() -> void:
	_run.call_deferred()


func _st() -> Dictionary:
	return {"air": true, "walking": false, "hs": C.MOVE_SPEED, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0,
		"holding": false, "hit": null, "act": null, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false, "sniffAt": null, "idle": 0.0,
		"airDash": 1.0, "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://air_dash.png"
	var ids: PackedStringArray = (a[1] if a.size() > 1 else "tank,ninja,hunter,hook").split(",")
	var yaw: float = float(a[2]) if a.size() > 2 else 90.0
	var Body = load("res://chars/body.gd")
	var Chars = load("res://chars/chars.gd")
	if not a.has("--code"):
		Body.use_ext = true
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 500)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var sun := DirectionalLight3D.new()
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(3, 4, 5), Vector3.ZERO, Vector3.UP)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.29, 0.34, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.25, 0.3)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	var bodies := []
	var wr = JSON.parse_string(a[3]) if a.size() > 3 else null
	for i in ids.size():
		var b = Chars.make_body(ids[i], Color.html("e05050"))
		var t := Node3D.new()
		t.position = Vector3(i * 2.6, 0, 0)
		t.rotation.y = deg_to_rad(yaw - 90.0)
		vp.add_child(t)
		t.add_child(b)
		if wr is Dictionary and b.ext != null:
			b.ext.info.cfg["dash_wrist"] = wr
		bodies.append(b)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.4
	vp.add_child(cam)
	cam.current = true
	var cx := (ids.size() - 1) * 1.3
	cam.look_at_from_position(Vector3(cx, 1.1, 20), Vector3(cx, 1.1, 0), Vector3.UP)
	var dt := 0.05
	for k in 14:
		for i in ids.size():
			var st := _st()
			var b = bodies[i]
			b.hs = float(st.hs)
			b.air_dash_t = C.FIGURE_AIR_DASH.s
			b.set_meta("air", true)
			b.set_meta("walking", false)
			b._figure_anim(st, dt)
			b._apply(dt)
			b._sync_bones()
			if b.ext != null:
				b.ext.sync(st)
		await process_frame
	vp.get_texture().get_image().save_png(out)
	print("TF 저장 ", out)
	quit()
