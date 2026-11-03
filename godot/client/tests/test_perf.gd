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


# W12 성능 재연 (core/replay.gd): 녹화 줄 "시각\t글자" 읽기 · 재기 시작 = 처음 playing 스냅샷 + warm 초
func test_replay_file_and_start() -> void:
	var R = load("res://core/replay.gd")
	var path := "user://w12_replay_test.rec"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("100.0\t{\"type\":\"welcome\"}")
	f.store_line("150.5\t{\"type\":\"state\",\"phase\":\"lobby\"}")
	f.store_line("깨진 줄")
	f.store_line("300.0\t{\"type\":\"state\",\"phase\":\"playing\",\"a\":\"x\ty\"}")
	f.close()
	var lines: Array = R.load_file(path)
	check(lines.size() == 3, "깨진 줄은 뺌: %d" % lines.size())
	check(lines[1][0] == 150.5 and str(lines[2][1]).ends_with("\"x\ty\"}"), "시각·글자 (탭은 첫 칸만 자름): %s" % str(lines))
	check(R.start_at(lines, 2.0) == 2300.0, "playing + 2초: %s" % R.start_at(lines, 2.0))
	check(R.start_at(lines.slice(0, 2), 1.0) == 1100.0, "playing 없으면 첫 줄 + warm")
	check(R.start_at([], 1.0) == 0.0, "빈 파일 0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# 재연 시각 다시 매기기: 한 시각에 몰린 스냅샷을 서버 시각 간격으로 펼침, 다른 메시지는 바로 앞 시각·순서 그대로
func test_replay_retime() -> void:
	var R = load("res://core/replay.gd")
	var lines := [[10.0, "{\"type\":\"rooms\"}"], [50.0, "{\"type\":\"state\",\"time\":0,\"phase\":\"lobby\"}"], [50.0, "{\"type\":\"pong\",\"t\":3}"],
		[400.0, "{\"type\":\"state\",\"time\":33.5,\"phase\":\"playing\"}"], [400.0, "{\"type\":\"state\",\"time\":66.5}"], [400.0, "{\"type\":\"event\"}"]]
	var got: Array = R.retime(lines)
	var at := got.map(func(l): return l[0])
	check(at == [10.0, 50.0, 50.0, 83.5, 116.5, 116.5], "펼친 시각: %s" % str(at))
	check(got.map(func(l): return l[1]) == lines.map(func(l): return l[1]), "글자·순서 그대로")
	check(R.server_time("{\"type\":\"pong\",\"time\":5}") == null and R.server_time("{\"type\":\"state\",\"time\":1e3,") == 1000.0, "스냅샷만·숫자")


# W12 몸 자세 LOD (world/pose_lod.gd): 가까움·내 몸 = 매 프레임, 멀면 60Hz (120fps 면 한 프레임 걸러, 60fps 면 매 프레임), 화면 밖 20Hz
func test_pose_lod_rule() -> void:
	var L = load("res://world/pose_lod.gd")
	var lod := {"near": 9.0, "far_hz": 60.0, "off_hz": 20.0, "margin": 2.5}
	check(L.interval_ms(3.0, true, false, lod) == 0.0, "가까움 매 프레임")
	check(L.interval_ms(30.0, false, true, lod) == 0.0, "내 몸은 화면 밖·멀어도 매 프레임")
	check(near(L.interval_ms(12.0, true, false, lod), 1000.0 / 60.0), "멀면 60Hz")
	check(near(L.interval_ms(3.0, false, false, lod), 50.0), "화면 밖 20Hz")
	# 프레임 빠르기마다 실제로 세는 빈도 (1초)
	for row in [[120.0, 1000.0 / 60.0, 60], [60.0, 1000.0 / 60.0, 120], [120.0, 50.0, 20], [60.0, 50.0, 20], [144.0, 0.0, 144], [30.0, 1000.0 / 60.0, 30]]:
		var fms: float = 1000.0 / row[0]
		var last = null
		var n := 0
		var f := 0
		for i in int(row[0]):
			var now := i * fms
			if L.due(now, last, row[1], fms):
				last = now
				n += 1
			f += 1
		var want: int = row[2] if row[2] != 120 else 60
		check(n == want, "%.0ffps 간격 %.1fms → 초당 %d번 (기대 %d)" % [row[0], row[1], n, want])
	check(L.due(5.0, null, 50.0, 8.0), "처음은 셈")


# W15 둘째 단: far2 밖은 far2_hz (기본 WC.POSE_LOD 10m 밖 30Hz — 120fps 면 4프레임에 한 번, 60fps 면 2프레임에 한 번). far2 없는 표는 예전 그대로
func test_pose_lod_far2() -> void:
	var L = load("res://world/pose_lod.gd")
	var WC = load("res://world/world_config.gd")
	var lod: Dictionary = WC.POSE_LOD
	check(float(lod.far2) == 10.0 and float(lod.far2_hz) == 30.0 and float(lod.near) == 3.0, "기본 3m 매 프레임 · 10m 까지 60Hz · 밖 30Hz")
	check(L.interval_ms(2.0, true, false, lod) == 0.0, "3m 안 매 프레임")
	check(near(L.interval_ms(9.9, true, false, lod), 1000.0 / 60.0), "10m 안 60Hz")
	check(near(L.interval_ms(10.5, true, false, lod), 1000.0 / 30.0), "10m 밖 30Hz")
	check(near(L.interval_ms(10.5, false, false, lod), 50.0), "화면 밖은 20Hz 그대로")
	check(L.interval_ms(30.0, true, true, lod) == 0.0, "내 몸은 늘 매 프레임")
	check(near(L.interval_ms(30.0, true, false, {"near": 3.0, "far_hz": 60.0, "off_hz": 20.0, "margin": 2.5}), 1000.0 / 60.0), "far2 없는 표 = 예전 (멀어도 60Hz)")
	for row in [[120.0, 30], [60.0, 30], [144.0, 29]]:
		var fms: float = 1000.0 / row[0]
		var last = null
		var n := 0
		for i in int(row[0]):
			if L.due(i * fms, last, 1000.0 / 30.0, fms):
				last = i * fms
				n += 1
		check(absi(n - int(row[1])) <= 1, "%.0ffps 30Hz → 초당 %d번" % [row[0], n])


# W15 SubViewport 다시 그리기 (거울·대기실 큰 캐릭터): 한 프레임에 한 번 정하고 (여러 번 불러도 같은 답), 60fps 이하면 매 프레임, 120fps 면 한 프레임 걸러
func test_subview_rate() -> void:
	var L = load("res://world/pose_lod.gd")
	var WC = load("res://world/world_config.gd")
	check(float(WC.SUBVIEW_HZ) == 60.0, "상한 60Hz")
	for row in [[120.0, 60], [60.0, 60], [30.0, 30], [144.0, 72], [240.0, 60]]:
		var fms: float = 1000.0 / row[0]
		var st := {}
		var n := 0
		for i in int(row[0]):
			var a: bool = L.frame_due(st, i, i * fms, fms, WC.SUBVIEW_HZ)
			var b: bool = L.frame_due(st, i, i * fms + 0.3, fms, WC.SUBVIEW_HZ) # 같은 프레임 두 번째 (title_scene 이 거울 카메라를 한 번 더 맞춤)
			check(a == b, "같은 프레임은 같은 답")
			if a:
				n += 1
		check(n == int(row[1]), "%.0ffps → 초당 %d번 그림 (기대 %d)" % [row[0], n, row[1]])


# W15 같은 스냅샷이면 다시 안 씀: 떨어지는 칸 (하늘 블록이면 반짝임 색만), 판 빛 무리 목록
func test_same_snapshot_skips() -> void:
	var PV = load("res://world/pieces_view.gd")
	var pv = PV.new()
	pv._ready()
	var st := {"pieces": [{"shape": "T", "cells": [[1, 1, 5], [2, 1, 5]], "sky": false}, {"shape": "I", "cells": [[4, 4, 9]], "sky": true}]}
	pv.update(st, 1, {}, 0.0)
	var mm: MultiMesh = pv.cells_mmi.multimesh
	var km: MultiMesh = pv.sky_mmi.multimesh
	check(mm.visible_instance_count == 2 and km.visible_instance_count == 1, "칸 2 + 하늘 칸 1")
	check(pv.writes == 1 and pv._sky_base.size() == 1, "처음 한 번 다 씀, 하늘 칸 색 기억")
	pv.update(st, 1, {}, 0.0)
	check(pv.writes == 1, "같은 스냅샷: 칸 다시 안 씀 (하늘 블록 반짝임 색만)")
	var st2 := st.duplicate(true)
	pv.update(st2, 1, {}, 0.0)
	check(pv.writes == 2, "새 스냅샷이면 다시")
	pv.update(st2, 1, {}, 0.9)
	check(pv.writes == 3, "하늘 시점으로 바뀌면 다시")
	pv.update(st2, 2, {}, 0.9)
	check(pv.writes == 4, "내 id 가 바뀌면 다시")
	pv.free()
	var W = load("res://world/world.gd")
	var h: Array = W.halos_of({"pieces": [{"shape": "T", "cells": [[1, 2, 3]]}, {"shape": "ghost", "cells": [[0, 0, 0]], "thrown": true}], "items": [{"x": 4, "y": 5, "z": 6}]}, {"T": 0x123456})
	check(h.size() == 2 and h[0] == [1.5, 2.5, 3.5, 0x123456, 1.0] and h[1][4] == 0.6, "빛 무리: 칸 + 아이템 (던진 칸 빼고) %s" % str(h))


# W15 투명할 땐 화면 전체 판을 안 그림 (색 a = 0 은 modulate 와 달리 그리기를 안 건너뜀): 타이틀 하얀 막·판 번쩍
func test_clear_overlays_hidden() -> void:
	var T = load("res://title/title.gd")
	var t = T.new()
	t._white(0.4)
	check(t.white.visible and is_equal_approx(t.white.color.a, 0.4), "나가기 동안 보임")
	t._white(0.0)
	check(not t.white.visible, "끝나면 숨김")
	for n in [t.white, t.haze, t.hint, t.layer, t.haze_layer]: # _ready 전이라 아직 자식이 아님
		n.free()
	t.free()


# 화면 안 판정: 실제 카메라 시야 면 — 앞은 안, 뒤·옆 멀리는 밖, 가장자리 바로 밖은 여유 (margin) 로 안
func test_pose_lod_in_view() -> void:
	var L = load("res://world/pose_lod.gd")
	# Camera3D.get_frustum 과 같은 계산 (러너 동안 root 가 트리 밖이라 카메라를 못 씀): 세로 시야 60°·16:9 원근 + 카메라 자리
	var tr := Transform3D(Basis.looking_at(Vector3.ZERO - Vector3(0, 5, 10), Vector3.UP), Vector3(0, 5, 10))
	var hv := deg_to_rad(30.0)
	var hh := atan(tan(hv) * 1280.0 / 720.0)
	var planes: Array = []
	for pl in [Plane(Vector3(0, 0, 1), -0.05), Plane(Vector3(0, 0, -1), 4000.0), Plane(Vector3(-cos(hh), 0, sin(hh)), 0.0), Plane(Vector3(cos(hh), 0, sin(hh)), 0.0), Plane(Vector3(0, cos(hv), sin(hv)), 0.0), Plane(Vector3(0, -cos(hv), sin(hv)), 0.0)]:
		planes.append(tr * pl)
	check(L.in_view(planes, Vector3.ZERO, 0.5), "바라보는 곳")
	check(not L.in_view(planes, Vector3(0, 5, 20), 2.5), "카메라 뒤")
	check(not L.in_view(planes, Vector3(40, 0, 0), 2.5), "옆 멀리")
	# 오른쪽 가장자리 바로 밖 (수평 시야 반각 ≈ 45.7°, 거리 ~11 에서 폭 ~11.5): 여유 없으면 밖, 2.5m 여유면 안
	var edge := Vector3(13.0, 0, 0)
	check(not L.in_view(planes, edge, 0.0) and L.in_view(planes, edge, 2.5), "가장자리 여유")


# 재연 --set: 글자 → 설정 값 (참·거짓·숫자·글자)
func test_replay_sets() -> void:
	var R = load("res://core/replay.gd")
	var got: Dictionary = R.parse_sets("outline=false,shadows=true,fov=80,gfx=medium,bad")
	check(got == {"outline": false, "shadows": true, "fov": 80.0, "gfx": "medium"}, "설정: %s" % str(got))


# 설정 '외곽선' (W12): 만든 재질 (툰·블록 칸·건축 블록) 의 외곽선을 곧바로 떼고 다시 붙임, 끈 동안 만든 재질도 켜면 붙음. 외곽선 재질은 나눠 씀
func test_outline_setting_toggles() -> void:
	var G3 = load("res://shaders/g3.gd")
	var a: ShaderMaterial = G3.toon_material(Color.RED)
	var b: ShaderMaterial = G3.toon_material(Color.BLUE)
	var nf: ShaderMaterial = G3.toon_material(Color.BLUE, {"no_fog": true})
	var pc: ShaderMaterial = G3.piece_material(null, false)
	check(a.next_pass != null and a.next_pass == b.next_pass, "같은 외곽선 재질 하나를 나눠 씀")
	check(nf.next_pass != a.next_pass and nf.next_pass.get_shader_parameter("no_fog") == true and a.next_pass.get_shader_parameter("no_fog") == false, "안개 안 받음은 따로")
	G3.set_outline_on(false)
	var c: ShaderMaterial = G3.toon_material(Color.GREEN)
	check(a.next_pass == null and pc.next_pass == null and c.next_pass == null, "끄면 이미 만든 것·새로 만든 것 모두 없음")
	G3.set_outline_on(true)
	check(a.next_pass != null and pc.next_pass != null and c.next_pass != null and nf.next_pass.get_shader_parameter("no_fog") == true, "켜면 다시 (안개 값 그대로)")
	check(G3.toon_material(Color.WHITE, {"opacity": 0.5}).next_pass == null and G3.toon_material(Color.WHITE, {"outline": false}).next_pass == null, "반투명·outline false 는 그대로 없음")


# 설정 '그림자': 켬 + 그래픽 낮춤 아님일 때만
func test_shadows_setting() -> void:
	var W = load("res://world/world.gd")
	check(W.shadows_wanted({"shadows": true, "lowGfx": false}), "켬")
	check(not W.shadows_wanted({"shadows": false, "lowGfx": false}), "설정 끔")
	check(not W.shadows_wanted({"shadows": true, "lowGfx": true}), "낮음")


# 렌더러 (W12): PC 기본은 아직 GL Compatibility (재혁 PC 숫자 뒤 결정) · 웹은 따로 GL Compatibility 로 못 박음 —
# PC 기본을 Forward+·Mobile 로 바꿔도 웹 내보내기는 그대로 (웹은 WebGL2 만)
func test_renderer_web_pinned() -> void:
	var cf := ConfigFile.new()
	check(cf.load("res://project.godot") == OK, "project.godot 읽기")
	check(str(cf.get_value("rendering", "renderer/rendering_method", "")) == "gl_compatibility", "PC 기본 렌더러 = gl_compatibility (시험은 start-lan-forward·mobile.bat)")
	check(str(cf.get_value("rendering", "renderer/rendering_method.web", "")) == "gl_compatibility", "웹 렌더러 = gl_compatibility 고정")


# HUD 글자 색·크기 (W12): 같은 값이면 덮어쓰지 않음 → '테마 바뀜' 알림 (글자 모양 다시 잡기·다시 배치) 이 값이 바뀔 때만
func test_hud_override_only_on_change() -> void:
	var H = load("res://ui/ui_style.gd")
	var ml = Engine.get_main_loop()
	var l := Label.new()
	var host: Node = ml.root if ml is SceneTree else null
	if host != null:
		host.add_child(l)
	var n := [0]
	l.theme_changed.connect(func(): n[0] += 1)
	l.add_theme_color_override("font_color", Color.RED)
	l.add_theme_color_override("font_color", Color.RED)
	var raw: int = n[0]
	n[0] = 0
	for i in 5:
		H.ov_color(l, "font_color", Color.BLUE)
		H.ov_font_size(l, "font_size", 30)
	check(l.get_theme_color("font_color") == Color.BLUE and l.get_theme_font_size("font_size") == 30, "값은 바뀜")
	if raw >= 2: # 트리 안이라 알림이 오는 경우: 그냥 덮어쓰기는 같은 값도 알림, ov_ 는 바뀔 때 한 번씩만
		check(n[0] == 2, "같은 값 5번 = 알림 2번 (색·크기 한 번씩), 실제 %d" % n[0])
	# 러너는 트리 밖 (알림 없음) 이라 값만 봄. 트리 안 확인 (W12 손 측정): 그냥 덮어쓰기 같은 값 5번 = 알림 5번, ov_ = 2번 · 한 번 11µs → 0.6µs
	l.free()


# W15 외곽선 껍질은 해 그림자 지도 (직교 투영) 에 안 그림 — 셰이더가 직교면 클립 밖으로 (게임 카메라는 다 원근)
func test_outline_not_in_shadow_map() -> void:
	var code: String = (load("res://shaders/outline.gdshader") as Shader).code
	check(code.contains("PROJECTION_MATRIX[3][3] > 0.5") and code.contains("POSITION = vec4(2.0, 2.0, 2.0, 1.0)"), "직교 투영이면 껍질 납작")
	var bad := []
	for f in ["res://world/cam_rig.gd", "res://chars/viewmodel.gd", "res://ui/char_stage.gd", "res://ui/portrait.gd", "res://title/title_scene.gd", "res://title/title_world.gd"]:
		if FileAccess.get_file_as_string(f).contains("PROJECTION_ORTHOGONAL"):
			bad.append(f)
	check(bad.is_empty(), "직교 카메라를 쓰면 외곽선이 안 보임: %s" % str(bad))
