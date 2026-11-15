# G6 성능 표시 계산이 JS (shared/perf.js) 와 같은지 (tools/fixtures-fx.mjs → perf.json): FPS·평균·1% low·구간·기타, 복사 한 줄, GPU 이름 줄이기
extends RefCounted

const PC := preload("res://ui/perf_calc.gd")
const NetScript := preload("res://core/net.gd")

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


# 끊긴 동안 성능 판·복사 한 줄의 핑 자리 (사이클 5 리뷰 F4): perf.gd 는 Net.ping_value (핑 값만 — 다시 붙는 중이면 '끊김') 를 씀.
# 예전엔 ping_text 에서 '핑 ' 을 지워 '핑 연결 끊김 · 다시 연결 중 3' 이 됐음
func test_perf_ping_while_reconnecting() -> void:
	var n = NetScript.new() # 트리에 안 넣음 (접속 안 함)
	var s := PC.PerfWindow.new().summary(1000.0)
	for t in [0, 3]:
		n.reconnecting = true
		n.tries = t
		check(n.ping_value() == NetScript.PING_LOST and NetScript.PING_LOST == "끊김", "다시 붙는 중 핑 값: %s" % n.ping_value())
		var line := PC.perf_line(s, {"ping": n.ping_value()})
		check(line.ends_with(" · 핑 끊김") and not line.contains("핑 연결 끊김") and not line.contains("다시 연결 중"), "복사 한 줄: %s" % line)
	n.reconnecting = false
	check(n.ping_value() == "…" and n.ping_text() == "핑 " + n.ping_value(), "붙어 있으면 핑 글 = '핑 ' + 값: %s / %s" % [n.ping_text(), n.ping_value()])
	var src := FileAccess.get_file_as_string("res://ui/perf.gd")
	check(src.contains("Net.ping_value()") and not src.contains("ping_text"), "perf.gd 는 ping_value 를 씀 (ping_text 를 고쳐 쓰지 않음)")
	n.free()
