# W23 래그돌 비교 그림: 같은 캐릭터를 코드 몸 (왼쪽) 과 외부 몸 (--ext 모델, 오른쪽) 으로 만들어 같은 입력 (맞음·경직·낙사) 을 주고 시간 간격으로 화면을 저장.
# 몸 위치·경직·z 는 서버 스냅샷처럼 pose(p) 로만 주고, 래그돌은 진짜 (chars/ragdoll.gd) 가 돎. 수치 (골반·머리 높이, 팔다리 뼈 방향 오차) 는 CSV.
# xvfb-run -a -s "-screen 0 1400x800x24" godot --path godot/client --resolution 1400x800 -s res://tools/rag_shot.gd -- <폴더> [캐릭터 ninja] [hit|fall|ko|idle]
extends SceneTree

const Co := preload("res://core/coords.gd")
var out := ""
var ch := "ninja"
var scen := "hit"
var views := []   # [{vp, cam, root, body, ext}]
var t0 := 0.0
var times := []
var ti := 0
var csv := []
var fake_store
var x := 5.0
var vx := 0.0
var z := 0.0
var vz := 0.0
var lastf := 0.0
var hit_done := false
var stun := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "user://rag_shot"
	ch = a[1] if a.size() > 1 else "ninja"
	scen = a[2] if a.size() > 2 else "hit"
	DirAccess.make_dir_recursive_absolute(out)
	# 가짜 Store (바닥만): 래그돌이 바닥 상자를 만들고, 몸이 view_pos 를 부름
	var src := "extends Node\nvar state := {\"field\": {\"w\": 10, \"d\": 10, \"h\": 8}}\nvar grid := PackedByteArray()\nfunc view_pos(_id):\n\treturn Vector3.ZERO\n"
	var gs := GDScript.new()
	gs.source_code = src
	gs.reload()
	fake_store = gs.new()
	fake_store.name = "Store"
	root.add_child(fake_store)
	fake_store.grid.resize(10 * 10 * 8)
	_start.call_deferred()


func _make_view(use_ext: bool):
	var Body = load("res://chars/body.gd")
	var Chars = load("res://chars/chars.gd")
	Body.use_ext = use_ext
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(700, 760)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	vp.add_child(light)
	light.look_at_from_position(Vector3(3, 6, 4), Vector3.ZERO, Vector3.UP)
	var fl := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(10, 0.5, 10)
	fl.mesh = bm
	fl.position = Co.gxyz(5, 5, -0.25)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.55, 0.3)
	fl.material_override = fm
	vp.add_child(fl)
	var rt := Node3D.new()
	vp.add_child(rt)
	var b = Chars.make_body(ch, Color.html("e05050"))
	rt.add_child(b)
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	cam.current = true
	return {"vp": vp, "cam": cam, "root": rt, "body": b, "ext": b.ext != null}


func _start() -> void:
	views.append(_make_view(false))
	views.append(_make_view(true))
	for v in views:
		v.body.rag_test = true # 서브뷰포트 몸이라 래그돌 켜려면 필요
	print("외부 몸 있음: 왼쪽 %s 오른쪽 %s" % [views[0].ext, views[1].ext])
	t0 = Time.get_ticks_msec() / 1000.0
	times = [0.5, 1.0, 1.15, 1.3, 1.45, 1.6, 1.8, 2.0, 2.3, 2.6, 3.0, 3.5, 4.0, 4.5]
	if scen == "fall":
		times = [0.5, 1.0, 1.3, 1.5, 1.7, 1.9, 2.1, 2.3, 2.6, 3.0, 3.5]
	elif scen == "ko":
		times = [0.5, 1.0, 1.1, 1.2, 1.35, 1.5, 1.7, 2.0, 2.5, 3.0, 4.0]
	_loop.call_deferred()


func _loop() -> void:
	while true:
		await process_frame
		var now := Time.get_ticks_msec() / 1000.0
		var t := now - t0
		var dt := clampf(now - lastf, 0.0, 0.1) if lastf > 0.0 else 0.0
		lastf = now
		stun = false
		if scen == "hit" or scen == "ko":
			if t >= 1.0 and not hit_done:
				hit_done = true
				vx = -6.0 if scen == "hit" else -9.0
				for v in views:
					var b = v.body
					b.seq += 1
					b.hit = {"id": b.seq, "t0": now, "stop": 0.08, "dir": Vector2(-1, 0), "pow": 1.5 if scen == "hit" else 3.0}
			if hit_done:
				x += vx * dt
				vx *= exp(-5.0 * dt)
				stun = t < (2.1 if scen == "hit" else 3.3)
		elif scen == "fall":
			if t >= 1.0:
				vx = 3.0
			x += vx * dt
			if x > 10.0:
				vz -= 20.0 * dt
				z += vz * dt
				stun = true
		var p := {"id": -1, "alive": true, "x": x, "y": 5.0, "z": z, "yaw": 0.0, "stunned": stun, "emote": -1}
		for v in views:
			v.root.position = Co.gxyz(x, 5.0, z)
			v.body.pose(p, now * 1000.0)
			v.cam.global_position = Co.gxyz(x + 2.0, -0.2, 1.8)
			v.cam.look_at(Co.gxyz(x - 0.5, 5.0, 0.8), Vector3.UP)
		if scen != "idle":
			csv.append(_measure(t))
		if ti < times.size() and t >= float(times[ti]):
			for i in 2:
				views[i].vp.get_texture().get_image().save_png("%s/%s_%s_%02d_%s.png" % [out, ch, scen, ti, "code" if i == 0 else "ext"])
			ti += 1
		if t > float(times[times.size() - 1]) + 0.2:
			break
	var f := FileAccess.open("%s/%s_%s.csv" % [out, ch, scen], FileAccess.WRITE)
	f.store_string("t,code_hips_z,code_neck_z,ext_hips_z,ext_neck_z,ext_arm_err_deg,ext_leg_err_deg\n")
	for r in csv:
		f.store_string(r + "\n")
	f.close()
	quit()


# 높이 (게임 z): 코드 몸 골반·목 관절 / 외부 몸 뼈, 오른팔·오른다리 뼈 방향 − 관절 방향 오차 (도)
func _measure(t: float) -> String:
	var c = views[0].body
	var e = views[1].body
	var chz: float = Co.game(c.hips.global_position).z
	var cnz: float = Co.game(c.neck.global_position).z
	var ehz := 0.0
	var enz := 0.0
	var arm := 0.0
	var leg := 0.0
	if e.ext != null:
		var X = e.ext
		var sk: Skeleton3D = X.sk
		var m: Dictionary = X.info.map
		ehz = Co.game((sk.global_transform * sk.get_bone_global_pose(int(m.hips))).origin).z
		enz = Co.game((sk.global_transform * sk.get_bone_global_pose(int(m.get("neck", m.hips)))).origin).z
		arm = _err(X, "shoulder_R", "elbow_R")
		leg = _err(X, "thigh_R", "knee_R")
	return "%.3f,%.3f,%.3f,%.3f,%.3f,%.1f,%.1f" % [t, chz, cnz, ehz, enz, arm, leg]


func _err(X, ja: String, jb: String) -> float:
	var sk: Skeleton3D = X.sk
	var m: Dictionary = X.info.map
	var ba: Vector3 = (sk.global_transform * sk.get_bone_global_pose(int(m[ja]))).origin
	var bb: Vector3 = (sk.global_transform * sk.get_bone_global_pose(int(m[jb]))).origin
	var da: Vector3 = X._joint(jb).global_position - X._joint(ja).global_position
	var db: Vector3 = bb - ba
	if da.length() < 1e-6 or db.length() < 1e-6:
		return 0.0
	return rad_to_deg(da.angle_to(db))
