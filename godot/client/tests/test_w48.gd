# W48 성능·모션 보고서: 글 (필드·길이 상한·개인정보 지우기)·프레임 통계·판 기록 (히치 원인·해상도 변경)·복사 (클립보드·파일·확인 실패)·꺼진 상태·F4 키·결과 화면/대기실 버튼·팝 카운터·비용
extends RefCounted

const Calc := preload("res://core/report_calc.gd")
const R := preload("res://core/report.gd")
const Hitch := preload("res://core/hitch.gd")
const Gfx := preload("res://world/gfx.gd")
const Keys := preload("res://core/keys.gd")
const Pops := preload("res://core/pop_count.gd")
const Build := preload("res://core/build_info.gd")

var errors: Array = []
const TEST_FILE := "user://test_w48_report.txt"


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _data() -> Dictionary:
	return {"version": "v0.1.19-godot-preview (abc1234)", "time": "2026-11-14 18:03", "os": "Windows 11", "gpu": "NVIDIA GeForce RTX 3060", "gpu_kind": "", "renderer": "opengl3 · GL Compatibility",
		"win": "1920×1080", "ui": "150%", "scale3d": 1.0, "scale_min": 0.8, "quality": "보통 (자동) MSAA 4×", "opts": ["--old-gait"], "has_round": true, "char": "ninja", "players": 4, "bots": 3,
		"map": "flat", "mode": "survival", "secs": 83.0, "partial": false, "frames": 4980, "fps": 118.0, "low_ms": 16.4, "low_fps": 61.0, "worst_ms": 48.0, "worst_t": 41.2,
		"proc_avg": 3.1, "proc_max": 21.0, "script": -1.0, "rcpu": 2.2, "rgpu": 4.0, "vram": 310.0, "hitch_n": 7, "hitch_worst": 48.0, "res_changes": 3,
		"hitch_lines": ["1. 해상도 변경 ×3 · 최악 48ms @ 41.2s (판 (playing), 80%)", "2. KO ×2 · 최악 30ms @ 12.0s (판 (playing), death)"],
		"pops": 4, "pop_by": {"ninja": 3, "tank": 1}, "pop_obs": {"ninja": 41.0, "tank": 20.0}, "pop_lines": ["ninja Spine2 52°/표본 @ 12.3s"]}


# 필드 구성: 버전·환경 (렌더러·GPU·해상도·UI·3D·화질)·판 (캐릭터·인원·맵·모드·길이)·프레임·히치·옵션·모션
func test_report_fields() -> void:
	var t := Calc.build(_data())
	for need in ["[Tetrafall 성능 보고]", "v0.1.19-godot-preview (abc1234)", "Windows 11", "GPU NVIDIA GeForce RTX 3060", "렌더러 opengl3 · GL Compatibility", "창 1920×1080", "UI 150%", "3D 100% (판 중 최저 80%)", "화질 보통 (자동) MSAA 4×",
			"캐릭터 ninja", "4명 (봇 3)", "맵 flat", "모드 survival", "83초", "평균 118 FPS", "1% low 61 FPS (16.4ms)", "최악 48ms @ 41.2s", "엔진 처리 평균 3.1ms", "GPU 4.0ms", "영상 메모리 310MB",
			"히치: 7회 · 최악 48ms · 해상도 변경 3회", "1. 해상도 변경 ×3", "옵션: --old-gait", "모션 팝", "ninja 3회/41초", "ninja Spine2"]:
		check(t.contains(need), "보고서에 '%s' 가 있어야 함:\n%s" % [need, t])
	check(t.length() <= Calc.MAX_CHARS, "길이 %d" % t.length())


func test_report_length_cap_keeps_important_lines() -> void:
	var d := _data()
	var lines := []
	for i in 40:
		lines.append("%d. 원인 %d ×%d · 최악 %dms @ %.1fs (판 (playing), %s)" % [i + 1, i, i, 50 + i, i * 1.5, "긴 설명 ".repeat(12)])
	d["hitch_lines"] = lines
	d["pop_lines"] = lines
	var t := Calc.build(d)
	check(t.length() <= Calc.MAX_CHARS, "긴 입력도 %d자 이하: %d" % [Calc.MAX_CHARS, t.length()])
	for need in ["[Tetrafall 성능 보고]", "환경:", "프레임:", "히치: 7회", "옵션:"]:
		check(t.contains(need), "줄여도 '%s' 는 남김" % need)
	check(t.find("환경:") < t.find("판:") and t.find("판:") < t.find("프레임:") and t.find("프레임:") < t.find("히치:"), "글 순서: 환경 → 판 → 프레임 → 히치")


func test_no_round_yet() -> void:
	var d := _data()
	d["has_round"] = false
	d["frames"] = 0
	var t := Calc.build(d)
	check(t.contains("아직 판 기록 없음") and t.contains("환경:") and not t.contains("프레임:"), "판 기록 없으면 환경만 + 안내:\n" + t)


# 개인정보: C:\Users\이름 → %APPDATA%·%USERPROFILE%, 리눅스·맥 홈 → ~, 환경 변수 사용자 이름
func test_sanitize_paths_and_names() -> void:
	var s := Calc.sanitize("열기 C:\\Users\\홍길동\\AppData\\Roaming\\Godot\\app_userdata\\Tetrafall\\hitches.txt 와 d:/users/Jaehyuk/Documents/x.txt 와 C:\\Users\\kim\\AppData\\Local\\Temp")
	check(s.contains("%APPDATA%\\Godot\\app_userdata\\Tetrafall\\hitches.txt"), "AppData\\Roaming → %APPDATA%: " + s)
	check(s.contains("%USERPROFILE%/Documents/x.txt"), "Users\\이름 → %USERPROFILE%: " + s)
	check(s.contains("%LOCALAPPDATA%\\Temp"), "AppData\\Local → %LOCALAPPDATA%: " + s)
	check(not s.contains("홍길동") and not s.contains("Jaehyuk") and not s.contains("kim"), "이름이 남음: " + s)
	var u := Calc.sanitize("/home/jhkim/.local/share/godot 그리고 /Users/mac/Library", [])
	check(u == "~/.local/share/godot 그리고 ~/Library", "리눅스·맥 홈 → ~: " + u)
	check(Calc.sanitize("user://last_report.txt res://core/x.gd") == "user://last_report.txt res://core/x.gd", "user:// res:// 는 그대로")
	var n := Calc.sanitize("컴퓨터 JHPC-77 에서 sneaky 가 했다", ["JHPC-77", "ab"])
	check(not n.contains("JHPC-77") and n.contains("<사용자>") and n.contains("sneaky"), "환경 변수 이름은 3자 이상만 바꿈: " + n)


func test_build_has_no_personal_info() -> void:
	var d := _data()
	d["hitch_lines"] = ["1. 방 입장 ×1 · 최악 80ms @ 1.0s (대기실, C:\\Users\\홍길동\\AppData\\Roaming\\x 홍길동PC)"]
	d["opts"] = Calc.opt_list(["--server", "wss://my-secret.trycloudflare.com", "--room", "ABCD", "--name", "홍길동", "--old-gait", "--shot", "C:\\Users\\홍길동\\a.png"])
	var t := Calc.build(d, ["홍길동PC"])
	for bad in ["홍길동", "C:\\Users", "trycloudflare", "ABCD", "a.png", "/home/"]:
		check(not t.contains(bad), "'%s' 가 보고서에 남음:\n%s" % [bad, t])
	check(t.contains("%APPDATA%") and t.contains("--old-gait"), "경로는 %APPDATA% 로, 켜진 옵션은 남음")


func test_opt_list() -> void:
	var o := Calc.opt_list(["--old-gait", "--server", "ws://x", "--room", "ABCD", "--gfx", "low", "--name", "재혁", "--lag-log", "C:\\x.txt", "--no-w43", "--rendering-method", "forward_plus", "--fixed-fps", "C:\\p", "--profile", "a"])
	check(o == ["--old-gait", "--gfx low", "--no-w43", "--rendering-method forward_plus", "--fixed-fps"], "옵션 이름만 (값은 gfx·렌더러만): %s" % str(o))
	check(Calc.opt_list([]).is_empty(), "인자 없으면 빈 목록 → '옵션: 기본'")
	check(Calc.build(_data().merged({"opts": []}, true)).contains("옵션: 기본"), "옵션 없으면 '기본'")


func test_frame_stats() -> void:
	var f := PackedFloat32Array()
	for i in 99:
		f.append(10.0)
	f.append(110.0)
	var s := Calc.frame_stats(f)
	check(s.n == 100 and absf(s.avg_ms - 11.0) < 0.01 and absf(s.worst_ms - 110.0) < 0.01, "평균·최악: %s" % str(s))
	check(absf(s.low_ms - 110.0) < 0.01 and absf(s.low_fps - 9.09) < 0.01, "1%% low = 가장 느린 1개: %s" % str(s))
	check(Calc.frame_stats(PackedFloat32Array()).n == 0, "빈 목록")


func _rep() -> Node:
	var rep: Node = R.new()
	R.file_path = TEST_FILE
	return rep


func _cleanup() -> void:
	R.file_path = R.FILE
	R.clipboard_set = Callable()
	R.clipboard_get = Callable()
	R.enabled = true
	if FileAccess.file_exists(TEST_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))


# 판 기록: 프레임·히치 (태그 원인)·해상도 변경 횟수 → 판이 끝나면 글을 만들어 user://last_report.txt 에
func test_round_records_and_writes_file() -> void:
	var rep := _rep()
	Hitch.reset()
	Hitch.on = true
	rep.ctx = {"char": "ninja", "players": 4, "bots": 3, "map": "flat", "mode": "survival", "practice": false, "tutorial": false}
	rep._start_round()
	check(rep.playing and rep.frames.is_empty(), "판 시작")
	var t_us: int = rep.start_us
	for i in 300:
		t_us += 16700
		var tags := []
		var ms := 16.7
		if i == 150:
			ms = 90.0
			tags = [["해상도 변경", "80%", -1.0]]
		rep.tick(t_us, ms, tags)
	Gfx.res_changes = 3
	var cur: String = rep.current_text()
	check(cur.contains("진행 중") and cur.contains("히치: 1회"), "도중에 누르면 지금까지 (진행 중):\n" + cur)
	rep._end_round()
	check(not rep.playing and rep.last_text != "", "판이 끝나면 글을 만들어 둠")
	var t: String = rep.last_text
	check(t.contains("히치: 1회 · 최악 90ms") and t.contains("1. 해상도 변경 ×1") and t.contains("최악 90ms @ "), "히치 원인 상위:\n" + t)
	check(t.contains("300프레임") and t.contains("캐릭터 ninja") and t.contains("4명 (봇 3)"), "프레임 수·판 정보:\n" + t)
	check(t.contains("해상도 변경 3회"), "해상도 변경 횟수 (Gfx.res_changes):\n" + t)
	check(FileAccess.file_exists(TEST_FILE) and FileAccess.get_file_as_string(TEST_FILE).strip_edges() == t.strip_edges(), "user://last_report.txt 에 같은 글")
	check(rep.current_text() == t, "판이 끝난 뒤엔 그 판 글")
	Gfx.res_changes = 0
	Hitch.on = false
	_cleanup()
	rep.free()


# 새 판이 시작되면 지난 판 기록은 버림 (히치·프레임이 섞이지 않게)
func test_round_reset() -> void:
	var rep := _rep()
	Hitch.on = true
	rep.ctx = {"char": "tank", "players": 2, "bots": 1, "map": "pyramid", "mode": "kills", "practice": false, "tutorial": false}
	rep._start_round()
	for i in 100:
		rep.tick(rep.start_us + i * 16700, 90.0 if i == 50 else 16.7, [])
	rep._end_round()
	rep._start_round()
	check(rep.frames.is_empty() and rep.light_log.count == 0 and rep.worst_ms == 0.0, "새 판은 빈 기록")
	rep._end_round()
	Hitch.on = false
	_cleanup()
	rep.free()


func test_copy_clipboard_and_signal() -> void:
	var rep := _rep()
	rep.last_text = "보고서 시험 글"
	var box := {"clip": "", "got": []}
	R.clipboard_set = func(t): box.clip = t
	R.clipboard_get = func(): return box.clip
	rep.copied.connect(func(ok, text): box.got = [ok, text])
	var r: Dictionary = rep.copy_now()
	check(box.clip == "보고서 시험 글" and r.ok and r.text == "보고서 시험 글", "클립보드에 들어가고 ok: %s" % str(r))
	check(box.got == [true, "보고서 시험 글"], "copied 신호: %s" % str(box.got))
	check(FileAccess.get_file_as_string(TEST_FILE).strip_edges() == "보고서 시험 글", "복사하면 파일도 갱신")
	R.clipboard_get = func(): return "다른 글" # 클립보드에 안 들어간 경우 → ok=false (화면이 글 칸을 띄움)
	r = rep.copy_now()
	check(not r.ok and box.got[0] == false, "확인 실패면 ok=false: %s" % str(r))
	R.inst = rep
	check(R.request_copy().text == "보고서 시험 글", "R.request_copy 는 인스턴스로")
	R.inst = null
	check(R.request_copy().text == "" and not R.request_copy().ok, "인스턴스가 없으면 빈 결과 (버튼이 죽지 않음)")
	_cleanup()
	rep.free()


# 꺼짐: enabled=false 면 프레임 처리가 아무것도 안 하고 태그도 안 가져가고 Hitch.on 도 안 켬
func test_disabled_costs_nothing() -> void:
	var rep := _rep()
	R.enabled = false
	Hitch.on = false
	Hitch.reset()
	rep._process(0.016)
	rep._process(0.016)
	check(rep.frames.is_empty() and rep.prev_us == 0 and not rep.playing, "꺼진 보고서는 기록 안 함")
	Hitch.on = true
	Hitch.tag("KO", "x")
	rep._process(0.016)
	check(Hitch.pending(), "꺼진 보고서는 태그도 안 가져감")
	Hitch.take()
	Hitch.on = false
	_cleanup()
	rep.free()


# Hitch.on 만 (F3 없이) 이면 태그만 모음: take 는 보고서 몫, full 이 켜졌을 땐 보고서가 안 가져감 (perf.gd 몫)
func test_tags_belong_to_perf_when_full() -> void:
	var rep := _rep()
	Hitch.on = true
	Hitch.full = true
	Hitch.reset()
	Hitch.tag("KO", "x")
	rep._process(0.016)
	check(Hitch.pending(), "F3 (full) 가 켜져 있으면 태그는 perf.gd 가 가져감")
	Hitch.full = false
	rep._process(0.016)
	check(not Hitch.pending(), "full 이 아니면 보고서가 가져감 (쌓이지 않음)")
	Hitch.on = false
	Hitch.reset()
	_cleanup()
	rep.free()


# 방 밖 (Store 비어 있음) 이면 판 기록을 시작하지 않음
func test_no_round_outside_room() -> void:
	var rep := _rep()
	for i in 5:
		rep._process(0.016)
	check(not rep.playing and rep.frames.is_empty(), "방 밖에선 기록 안 함")
	_cleanup()
	rep.free()


func test_key_report_f4() -> void:
	check(Keys.default_binds().get("report") == "F4" and Keys.key_label("F4") == "F4", "기본 키 F4")
	check("report" in Keys.GODOT_ONLY, "고도 전용 표시")
	var ids := Keys.ACTIONS.map(func(a): return a.id)
	check(ids.has("report") and ids.count("report") == 1, "키 설정 표에 한 번")
	var pi := preload("res://core/player_input.gd").new()
	pi.by_code = {"F4": ["report"]}
	var got := []
	pi.ui_action.connect(func(id, pressed): got.append([id, pressed]))
	pi.press("report")
	check(got == [["report", true]], "press('report') 가 ui_action 으로: %s" % str(got))
	pi.free()


# 결과 화면·대기실에 '성능 보고 복사' 버튼 (UI 배율은 창 content scale 이 따라감 — 같은 UI 뿌리 안)
func test_buttons_on_results_and_lobby() -> void:
	for path in ["res://ui/results.gd", "res://ui/lobby.gd"]:
		var n: Node = load(path).new()
		n._ready()
		var found := []
		_buttons(n, found)
		check(found.any(func(b): return b.text == "성능 보고 복사"), "%s 에 '성능 보고 복사' 버튼" % path)
		n.free()


func _buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_buttons(c, out)


# 화면 쪽: 확인 안 되면 글 칸이 뜸, 되면 토스트만
func test_report_ui_toast_and_box() -> void:
	var rep := _rep()
	R.inst = rep
	var ui: Node = load("res://ui/report_ui.gd").new()
	ui._ready()
	rep.last_text = "화면 시험"
	R.clipboard_set = func(_t): pass
	R.clipboard_get = func(): return "화면 시험"
	rep.copy_now()
	check(ui.toast.visible and ui.toast_label.text.contains("복사됨") and not ui.box.visible, "복사 확인되면 토스트만")
	R.clipboard_get = func(): return ""
	rep.copy_now()
	check(ui.box.visible and ui.edit.text == "화면 시험", "확인 안 되면 글 칸")
	R.inst = null
	ui.free()
	_cleanup()
	rep.free()


# 가벼운 팝 카운터: 합성 뼈대 (보고서가 보는 12뼈) — 매끈한 움직임은 0, 한 표본 90° 튐은 1, 시간 간격이 길면 각을 줄여 셈, 몸마다 관측 초
func _skel() -> Skeleton3D:
	var sk := Skeleton3D.new()
	for n in Pops.BONES:
		sk.add_bone("mixamorig_" + n)
	return sk


func test_pops_smooth_vs_pop() -> void:
	var sk := _skel()
	var p := Pops.new()
	var t := 0.0
	for i in 120: # 매끈: 표본마다 5°
		for b in sk.get_bone_count():
			sk.set_bone_pose_rotation(b, Quaternion(Vector3.UP, deg_to_rad(5.0 * i)))
		p.sample_skel(sk, 1.0 / 60.0, t, "ninja")
		t += 1.0 / 60.0
	check(p.total == 0, "매끈한 회전은 팝 0: %d" % p.total)
	check(absf(float(p.obs.get("ninja", 0.0)) - 119.0 / 60.0) < 0.001, "관측 초 (첫 표본은 기준이라 뺌): %s" % str(p.obs))
	sk.set_bone_pose_rotation(0, Quaternion(Vector3.UP, deg_to_rad(5.0 * 120 + 90.0))) # Hips 한 표본에 90°
	p.sample_skel(sk, 1.0 / 60.0, t, "ninja")
	check(p.total == 1 and p.by.get("ninja") == 1, "90° 튐 = 팝 1: total %d by %s" % [p.total, str(p.by)])
	check(p.top.size() == 1 and p.top[0].bone == "Hips" and p.top[0].sev > 60.0, "상위 목록에 Hips: %s" % str(p.top))
	var d := {}
	p.into(d)
	check(d.pops == 1 and d.pop_by.ninja == 1 and d.pop_lines.size() == 1 and d.pop_lines[0].contains("ninja Hips"), "보고서 칸: %s" % str(d))
	check(Calc.build(_data().merged(d, true)).contains("ninja Hips"), "보고서 글에 팝 줄")
	sk.free()


func test_pops_gap_scaling_and_no_bodies() -> void:
	var sk := _skel()
	var p := Pops.new()
	for b in sk.get_bone_count():
		sk.set_bone_pose_rotation(b, Quaternion.IDENTITY)
	p.sample_skel(sk, 0.0, 0.0, "tank")
	for b in sk.get_bone_count():
		sk.set_bone_pose_rotation(b, Quaternion(Vector3.UP, deg_to_rad(60.0)))
	p.sample_skel(sk, 1.0 / 20.0, 0.1, "tank") # 60° 인데 표본 간격 3배 → 20°/표본 몫 = 임계 아래
	check(p.total == 0, "간격이 길면 1/60초 몫으로 줄여 셈: %d" % p.total)
	var d := {}
	Pops.new().into(d)
	check(not d.has("pops"), "새 모델 몸이 없던 판은 모션 줄 없음")
	check(not Calc.build(_data().merged({"pops": null}, true)).contains("모션 팝"), "pops 없으면 줄 없음")
	sk.free()


# 비용: 프레임마다 도는 일 (Report.tick = 프레임 기록 + 히치 판정 + 팝 한 몸) 의 평균. 느린 CI 에서도 안 깨질 넉넉한 상한 (측정값은 줄로 찍음 — 보고서에 적는 값은 tools/report_cost.gd)
func test_per_frame_cost_is_small() -> void:
	var rep := _rep()
	Hitch.on = true
	rep.ctx = {"char": "ninja", "players": 4, "bots": 3, "map": "flat", "mode": "survival"}
	rep._start_round()
	var n := 3000
	var t0 := Time.get_ticks_usec()
	for i in n:
		rep.tick(rep.start_us + i * 16700, 16.7 + (i % 7) * 0.1, [])
	var per := (Time.get_ticks_usec() - t0) / float(n)
	check(per < 150.0, "프레임당 %.1fµs (상한 150µs)" % per)
	print("    [W48] Report.tick 평균 %.2fµs/프레임" % per)
	rep._end_round()
	Hitch.on = false
	_cleanup()
	rep.free()


func test_build_info() -> void:
	check(Build.text() != "" and Build.TAG != "", "빌드 정보 글: %s" % Build.text())
