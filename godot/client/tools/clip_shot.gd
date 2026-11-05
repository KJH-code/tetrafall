# W23 동작 클립 확인 그림 (contact sheet): 외부 몸 (--ext) 의 클립을 시각마다 한 칸씩 (칸 = 몸 하나, 행 = 클립) 나란히 한 장으로.
# 클립은 Ext.preview_clip (코드 구동 없이 클립 그대로 + 발 바닥 맞추기) — 진짜 게임 길과 같은 샘플링·발 바닥 맞추기 코드.
# xvfb-run -a -s "-screen 0 1900x1000x24" godot --path godot/client --resolution 1900x1000 -s res://tools/clip_shot.gd -- <out.png> "idle:0,1.2;atk1:0,0.15,0.3,0.4,0.6,0.8" [yaw 도, 기본 90 = 옆모습] [캐릭터 ninja]
# 시각 = 클립 안 초. 이름 뒤 '@' 면 공중 클립 (발 바닥 맞추기 안 함) 예: "jump@:0,0.2,0.4"
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var spec: String = a[1]
	var yaw: float = float(a[2]) if a.size() > 2 else 90.0
	var ch: String = a[3] if a.size() > 3 else "ninja"
	var Body = load("res://chars/body.gd")
	var Chars = load("res://chars/chars.gd")
	Body.use_ext = true
	var rows := []
	for r in spec.split(";"):
		var f := r.split(":")
		var nm := f[0]
		var air := nm.ends_with("@")
		var ts := []
		for t in f[1].split(","):
			ts.append(float(t))
		rows.append([nm.trim_suffix("@"), air, ts])
	var cols := 0
	for r in rows:
		cols = maxi(cols, (r[2] as Array).size())
	var cell := 1.55
	var vp := SubViewport.new()
	vp.own_world_3d = true
	var cw := int(OS.get_environment("SHOT_W")) if OS.get_environment("SHOT_W") != "" else 230
	var chh := int(cw * 1.3)
	vp.size = Vector2i(cols * cw, int(rows.size() * chh))
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.34, 0.46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	vp.add_child(light)
	light.look_at_from_position(Vector3(3, 4, 5), Vector3.ZERO, Vector3.UP)
	var bodies := []
	for ri in rows.size():
		var r: Array = rows[ri]
		for ci in (r[2] as Array).size():
			var b = Chars.make_body(ch, Color.html("e05050"))
			var t := Node3D.new()
			t.position = Vector3(ci * cell, -ri * 2.15, 0)
			t.rotation.y = deg_to_rad(yaw - 90.0)
			vp.add_child(t)
			t.add_child(b)
			bodies.append([b, r[0], r[1], r[2][ci]])
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows.size() * 2.15
	vp.add_child(cam)
	cam.current = true
	var cx := (cols - 1) * cell * 0.5
	var cy := -(rows.size() - 1) * 2.15 * 0.5 + 0.9
	cam.look_at_from_position(Vector3(cx, cy, 20), Vector3(cx, cy, 0), Vector3.UP)
	for k in 4:
		for e in bodies:
			if e[0].ext == null:
				push_error("외부 몸 없음")
			else:
				e[0].ext.preview_clip(e[1], e[3], e[2])
		await process_frame
	vp.get_texture().get_image().save_png(out)
	print("TF 저장 ", out, " 클립 ", bodies.size() and (bodies[0][0].ext.clipset.keys()))
	quit()
