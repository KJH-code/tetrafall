# 새 외부 모델 (--ext) vs 예전 몸 비용 재기 (W30, 히치 후보 B①~③·A): 캐릭터마다 load (처음)·몸 만들기 (처음·두 번째)·씬에 넣은 뒤 frame1들·
# 몸 하나가 늘리는 그리기·물체·삼각형, 그다음 같은 캐릭터 8명을 한꺼번에 넣었을 때 (그리기·삼각형·영상 메모리·프레임당 자세 CPU).
# 소프트웨어 GL (llvmpipe) 라 GPU ms 는 못 잼 — 읽기·만들기·자세 CPU ms 와 그리기·삼각형·메모리 숫자가 근거. frame1 ms 는 셰이더 첫 사용 비용의 '순서 있는 어림'
#   (먼저 나온 캐릭터가 공용 셰이더 갈래를 대신 물므로 --order 를 바꿔 두 번 돌려 볼 것).
# xvfb-run -a -s "-screen 0 960x540x24" godot --path godot/client --rendering-driver opengl3 --resolution 960x540 -s res://tools/ext_meas.gd -- [--ext|--no-ext] [--order tank,ninja,hunter,hook,bard] [--eight] [--level high|medium|low]
extends SceneTree

const C := preload("res://core/config.gd")
const Hitch := preload("res://core/hitch.gd")

var ids: Array = ["tank", "ninja", "hunter", "hook", "bard", "berserker", "builder", "cannon"]
var use_ext := true
var eight := false
var cur := -1
var phase := ""
var frames := 0
var times: Array = []
var last_us := 0
var body = null
var bodies: Array = []
var base := {}
var rows: Array = []
var Chars
var Body
var Ext
var out_dir := ""
var eight_done := {}
var host: Node3D
var warm := false
var warm_done := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	use_ext = not a.has("--no-ext")
	eight = a.has("--eight")
	warm = a.has("--warm")
	var lv := a.find("--level") # W31: 판 LOD 단계 (high·medium·low) — 판 몸이 고르는 LOD (Gfx.plan.level)
	if lv >= 0:
		load("res://world/gfx.gd").plan = {"level": str(a[lv + 1])}
	var i := a.find("--order")
	if i >= 0:
		ids = str(a[i + 1]).split(",")
	RenderingServer.set_default_clear_color(Color(0.45, 0.7, 0.95))
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
	Body.use_ext = use_ext
	Hitch.on = true
	phase = "base"


func _spans() -> String:
	var parts := []
	for t in Hitch.take():
		if float(t[2]) >= 0.0:
			parts.append("%s %s %.1f" % [t[0], t[1], t[2]])
	return ", ".join(parts)


func _mon() -> Dictionary:
	return {"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"tris": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"tex": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, "obj": Performance.get_monitor(Performance.OBJECT_COUNT)}


static func _med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	var dt_ms := (now - last_us) / 1000.0
	last_us = now
	frames += 1
	match phase:
		"base":
			if warm and not warm_done: # --warm: 메뉴 미리 데우기 (External.request_all + warm_step) 를 먼저 돌린 뒤 같은 표
				if frames == 1:
					print("EXT_MEAS request_all -> %d files" % Ext.request_all())
				warm_done = Ext.warm_step(host, func(id, col): return Chars.make_body(id, col))
				if warm_done:
					print("EXT_MEAS warm done after %d frames" % frames)
					frames = 0
				return false
			if frames > 8:
				base = _mon()
				print("EXT_MEAS start ext=%s empty scene: 그리기 %d 물체 %d 삼각형 %d 영상 %.1fMB" % [use_ext, base.draws, base.objs, base.tris, base.vram])
				cur = 0
				phase = "make"
				frames = 0
		"make":
			if cur >= ids.size():
				phase = "eight_start" if eight else "done"
				cur = 0
				frames = 0
				return false
			var id: String = ids[cur]
			var color := Color(0.85, 0.2, 0.2)
			# ① load (처음): 외부 모델이 있고 켰을 때만 의미 (없는 캐릭터는 0)
			var t0 := Time.get_ticks_usec()
			var had_ext := false
			if use_ext:
				had_ext = Ext.has_char(id)
			var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
			var load_sp := _spans()
			# ② 몸 build1·두 번째
			t0 = Time.get_ticks_usec()
			body = Chars.make_body(id, color)
			var b1 := (Time.get_ticks_usec() - t0) / 1000.0
			Hitch.take()
			t0 = Time.get_ticks_usec()
			var tmp = Chars.make_body(id, color)
			var b2 := (Time.get_ticks_usec() - t0) / 1000.0
			tmp.free()
			Hitch.take()
			rows.append({"id": id, "ext": had_ext, "load": load_ms, "load_sp": load_sp, "b1": b1, "b2": b2})
			root.add_child(body)
			body.position = Vector3(0, 0, 0)
			times = []
			frames = 0
			phase = "frames"
		"frames":
			times.append(dt_ms)
			if frames >= 24:
				var r: Dictionary = rows[-1]
				var m := _mon()
				r["first"] = times[0]
				r["second"] = times[1]
				r["third"] = times[2]
				r["steady"] = _med(times.slice(6))
				r["draws"] = m.draws - base.draws
				r["objs"] = m.objs - base.objs
				r["tris"] = m.tris - base.tris
				r["vram"] = m.vram - base.vram
				print("EXT_MEAS %-9s ext %s | load %6.1f | build1 %6.1f build2 %5.1f | frame1 %7.1f frame2 %6.1f frame3 %6.1f steady %6.1f ms(llvmpipe) | draws +%d objs +%d tris +%d vram +%.1fMB | %s" % [r.id, "O" if r.ext else "-", r.load, r.b1, r.b2, r.first, r.second, r.third, r.steady, r.draws, r.objs, r.tris, r.vram, r.load_sp])
				body.queue_free()
				body = null
				cur += 1
				phase = "make"
				frames = 0
		"eight_start":
			if cur >= ids.size():
				phase = "done"
				return false
			var id2: String = ids[cur]
			bodies = []
			var t1 := Time.get_ticks_usec()
			for k in 8:
				var bb = Chars.make_body(id2, Color.from_hsv(k / 8.0, 0.7, 0.9))
				root.add_child(bb)
				bb.position = Vector3((k - 3.5) * 1.1, 0, 0)
				bodies.append(bb)
			var mk := (Time.get_ticks_usec() - t1) / 1000.0
			Hitch.take()
			rows.append({"eight": id2, "make8": mk})
			times = []
			frames = 0
			phase = "eight_frames"
		"eight_frames":
			times.append(dt_ms)
			if frames == 24:
				# 자세 계산 CPU: pose() 를 60번 부름 (서 있는 몸)
				var st := {"id": 1, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "alive": true, "char": rows[-1].eight, "vx": 0.0, "vy": 0.0, "vz": 0.0, "grounded": true}
				var pose_ms := -1.0
				if bodies[0].has_method("pose"):
					var t2 := Time.get_ticks_usec()
					for f in 60:
						for bb in bodies:
							bb.pose(st, 1000.0 + f * 16.0)
					pose_ms = (Time.get_ticks_usec() - t2) / 1000.0 / 60.0
				var m := _mon()
				print("EXT_MEAS 8명 %-9s | make8 %7.1fms | draws +%d objs +%d tris +%d vram +%.1fMB(tex %.1f) | pose8 %.2fms/프레임 | frame median %.1fms" % [rows[-1].eight, rows[-1].make8, m.draws - base.draws, m.objs - base.objs, m.tris - base.tris, m.vram - base.vram, m.tex, pose_ms, _med(times.slice(6))])
				for bb in bodies:
					bb.queue_free()
				cur += 1
				phase = "eight_start"
				frames = 0
		"done":
			return true
	return false
