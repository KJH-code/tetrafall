# G6 성능 표시 계산이 JS (shared/perf.js) 와 같은지 (tools/fixtures-fx.mjs → perf.json): FPS·평균·1% low·구간·기타, 복사 한 줄, GPU 이름 줄이기
# + W6 (재혁 PC 랙 진단) 고도만의 칸: 화면 상태·스크립트·물리·렌더 CPU/GPU·물체·SubViewport·영상 메모리·화질·렌더러, 평균, Ctrl+C, 스크립트 시간 탐침
extends RefCounted

const PC := preload("res://ui/perf_calc.gd")
const Perf := preload("res://ui/perf.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func near(a: float, b: float, eps := 1e-6) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))


func js():
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/perf.json"))


func test_window_matches_js() -> void:
	var d = js()
	var w := PC.PerfWindow.new()
	var k := 0
	for i in d.frames.size():
		var f: Array = d.frames[i]
		w.push(f[0], f[1], f[2], f[3])
		if k < d.sums.size() and int(d.sums[k][0]) == i:
			var got := w.summary(f[0])
			var want: Dictionary = d.sums[k][1]
			var same := true
			for key in ["fps", "avg", "low", "work", "other", "frames"]:
				same = same and near(float(got[key]), float(want[key]))
			for key in want.sections:
				same = same and near(float(got.sections[key]), float(want.sections[key]))
			check(same, "요약 %d: %s vs JS %s" % [i, got, want])
			k += 1
	check(k == d.sums.size(), "요약 %d개" % k)


func test_worst_gpu_line_match_js() -> void:
	var d = js()
	for r in d.worst:
		check(near(PC.worst_avg(r[0], r[1]), r[2]), "1%% low %s: %s vs JS %s" % [r, PC.worst_avg(r[0], r[1]), r[2]])
	for r in d.gpus:
		check(PC.short_gpu(r[0]) == r[1], "GPU '%s' → '%s' vs JS '%s'" % [r[0], PC.short_gpu(r[0]), r[1]])
	for r in d.lines:
		check(PC.perf_line(r[0], r[1]) == r[2], "한 줄\n  %s\n  vs JS %s" % [PC.perf_line(r[0], r[1]), r[2]])


func test_prof_off_is_free() -> void:
	PC.on = false
	PC.sec = {}
	var t0 := PC.begin()
	PC.end("grid", t0)
	check(t0 == 0.0 and PC.sec.is_empty(), "꺼지면 안 잼")
	PC.on = true
	t0 = PC.begin()
	PC.end("grid", t0)
	check(PC.sec.has("grid"), "켜면 잼")
	PC.on = false
	PC.sec = {}


func test_perf_line_godot_fields() -> void:
	var s := {"fps": 60.0, "avg": 16.6, "low": 33.3, "work": 5.0, "other": 1.0, "sections": {}}
	var base := PC.perf_line(s, {"draws": 10, "tris": 1200, "players": 2, "rag": 1, "low": false, "size": "1280×720", "gpu": "X", "ping": "20ms"})
	check(base.begins_with("FPS 60 · ") and not base.contains("스크립트"), "고도 칸이 없으면 JS 줄 그대로")
	var full := PC.perf_line(s, {"draws": 10, "players": 2, "screen": "메뉴", "script": 1.24, "phys": 0.5, "rcpu": 3.0, "rgpu": 7.25, "objs": 219, "svp": PC.svp_text([[1280, 720, 4], [640, 360, 1]]),
		"vram": 91.2, "gfx": "높음 · 3D 100% · MSAA 4×", "renderer": "opengl3 · GL Compatibility", "vendor": "NVIDIA Corporation", "hint": ""})
	check(full.begins_with("메뉴 · FPS 60"), "화면 상태가 맨 앞: %s" % full)
	for want in ["스크립트 1.2ms", "물리 0.5ms", "렌더 CPU 3.0ms", "렌더 GPU 7.3ms", "물체 219", "SubViewport 2 (1280×720 4×, 640×360)", "영상 메모리 91MB", "화질 높음 · 3D 100% · MSAA 4×", "렌더러 opengl3 · GL Compatibility", "제조사 NVIDIA Corporation"]:
		check(full.contains(want), "한 줄에 '%s': %s" % [want, full])
	check(not full.contains("안내"), "안내 없으면 칸 없음")
	check(PC.svp_text([]) == "0", "SubViewport 없음")


func test_screen_mean_copy_key() -> void:
	check(PC.screen_name(true, false, "") == "첫 화면" and PC.screen_name(false, false, "") == "메뉴", "타이틀·메뉴")
	check(PC.screen_name(false, true, "lobby") == "대기실" and PC.screen_name(false, true, "playing") == "판 (playing)", "대기실·판")
	check(PC.screen_name(false, true, "playing", true) == "연습" and PC.screen_name(false, true, "playing", true, true) == "튜토리얼", "연습·튜토리얼")
	var m := PC.recent_mean([[0.0, 9.0, 9.0], [900.0, 2.0, 4.0], [1500.0, 4.0, 8.0]], 1600.0, 1000.0, 2)
	check(m == [3.0, 6.0], "최근 1초 평균 (오래된 표본 뺌): %s" % str(m))
	check(PC.recent_mean([], 0.0, 1000.0, 2) == [0.0, 0.0], "표본 없음 0")
	check(PC.is_copy_key(KEY_C, true, true, false, false), "Ctrl+C 복사")
	check(not PC.is_copy_key(KEY_C, false, true, false, false) and not PC.is_copy_key(KEY_C, true, true, true, false) and not PC.is_copy_key(KEY_C, true, true, false, true), "Ctrl 없음·반복·글자 칸이면 아님")


# 스크립트 시간 탐침: 맨 앞 (priority −) 과 맨 뒤 (+) 사이 시간 = 그 프레임 _process 합. 물리 틱은 여러 번이면 더함
func test_script_time_probe() -> void:
	var a = Perf.Probe.new(false)
	var b = Perf.Probe.new(true)
	check(a.process_priority < 0 and b.process_priority > 0 and a.process_physics_priority < 0 and b.process_physics_priority > 0, "맨 앞·맨 뒤")
	b.peer = a
	var got := []
	b.sink = func(s_us: int, p_us: int): got.append([s_us, p_us])
	for i in 2:
		a._physics_process(0.0)
		var t := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t < 1000:
			pass
		b._physics_process(0.0)
	a._process(0.0)
	var t2 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t2 < 3000:
		pass
	b._process(0.0)
	check(got.size() == 1 and got[0][0] >= 3000 and got[0][0] < 50000, "스크립트 ≥3ms: %s" % str(got))
	check(got.size() == 1 and got[0][1] >= 2000, "물리 두 틱 합 ≥2ms: %s" % str(got))
	check(b.phys_us == 0, "프레임마다 물리 합 비움")
	a.free()
	b.free()
