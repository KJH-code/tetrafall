# 성능 표시 계산 (shared/perf.js 그대로): 프레임마다 {t, ms, sec, work} → FPS·평균·1% low·구간 평균·기타. 복사 한 줄·GPU 이름 줄이기
# 구간 재기 (prof): 다른 묶음이 무거운 곳을 var t0 := PerfCalc.begin() … PerfCalc.end("grid", t0) 로 감쌈 (키는 config PERF_SECTIONS). 꺼져 있으면 거의 0 비용
extends RefCounted

const C := preload("res://core/config.gd")

static var on := false
static var sec := {}


static func begin() -> float:
	return Time.get_ticks_usec() / 1000.0 if on else 0.0


static func end(key: String, t0: float) -> void:
	if on:
		sec[key] = float(sec.get(key, 0.0)) + Time.get_ticks_usec() / 1000.0 - t0


class PerfWindow:
	var frames: Array = []

	func push(t: float, ms: float, s := {}, work = null) -> void:
		frames.append({"t": t, "ms": ms, "sec": s, "work": ms if work == null else float(work)})
		var old := t - C.PERF_LOW_MS
		var cut := 0
		while cut < frames.size() and frames[cut].t < old:
			cut += 1
		if cut > 0:
			frames = frames.slice(cut)

	func summary(now: float) -> Dictionary:
		var recent := frames.filter(func(f): return f.t >= now - C.PERF_FPS_MS)
		var n := recent.size()
		var avg := 0.0
		var work := 0.0
		for f in recent:
			avg += f.ms
			work += f.work
		avg = avg / n if n > 0 else 0.0
		work = work / n if n > 0 else 0.0
		var sections := {}
		var measured := 0.0
		for k in C.PERF_SECTIONS:
			var v := 0.0
			for f in recent:
				v += float(f.sec.get(k, 0.0))
			sections[k] = v / n if n > 0 else 0.0
			measured += sections[k]
		var all := []
		for f in frames:
			all.append(f.ms)
		return {"fps": n * 1000.0 / C.PERF_FPS_MS, "avg": avg, "low": PerfCalcStatic.worst_avg(all, C.PERF_LOW_FRAC), "sections": sections, "work": work, "other": maxf(0.0, work - measured), "frames": n}


class PerfCalcStatic:
	# 가장 느린 frac 만큼 (적어도 1개) 의 평균 = "1% low"
	static func worst_avg(list: Array, frac: float) -> float:
		if list.is_empty():
			return 0.0
		var k := maxi(1, ceili(list.size() * frac))
		var s := list.duplicate()
		s.sort()
		s.reverse()
		var sum := 0.0
		for i in k:
			sum += s[i]
		return sum / k


static func worst_avg(list: Array, frac: float) -> float:
	return PerfCalcStatic.worst_avg(list, frac)


static func f1(v: float) -> String:
	return "%.1f" % (round(v * 10.0) / 10.0)


# 복사용 한 줄. extra: {draws, tris, players, rag, low, size, gpu, ping}
static func perf_line(s: Dictionary, extra := {}) -> String:
	var parts := ["FPS %d" % roundi(s.fps), "프레임 평균 %sms" % f1(s.avg), "1%% low %sms" % f1(s.low), "JS %sms" % f1(s.work)]
	for k in C.PERF_SECTIONS:
		parts.append("%s %s" % [C.PERF_SECTIONS[k], f1(s.sections.get(k, 0.0))])
	parts.append("기타 JS %s" % f1(s.other))
	if extra.get("draws") != null:
		parts.append("그리기 %d" % int(extra.draws))
	if extra.get("tris") != null:
		var t := int(extra.tris)
		parts.append("삼각형 %s" % ("%dk" % roundi(t / 1000.0) if t >= 1000 else str(t)))
	if extra.get("players") != null:
		parts.append("%d명 (래그돌 %d)" % [int(extra.players), int(extra.get("rag", 0) if extra.get("rag") != null else 0)])
	if extra.get("low") != null:
		parts.append("그래픽 낮춤 %s" % ("켬" if extra.low else "끔"))
	if str(extra.get("size", "")) != "":
		parts.append("화면 %s" % extra.size)
	if str(extra.get("gpu", "")) != "":
		parts.append("GPU %s" % extra.gpu)
	if str(extra.get("ping", "")) != "":
		parts.append("핑 %s" % extra.ping)
	return " · ".join(parts)


# 짧은 GPU 이름: "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002504) Direct3D11 vs_5_0 ps_5_0, D3D11)" → "NVIDIA GeForce RTX 3060"
static func short_gpu(name) -> String:
	var s := str(name if name != null else "")
	var re := RegEx.create_from_string("^ANGLE \\((.*)\\)$")
	var m := re.search(s)
	if m != null:
		var parts := m.get_string(1).split(", ")
		s = parts[1] if parts.size() >= 2 else parts[0]
	s = RegEx.create_from_string("(?i)\\(0x[0-9a-f]+\\)").sub(s, "", true)
	s = RegEx.create_from_string("(?i)\\s+(Direct3D|vs_|ps_|OpenGL|Vulkan|Metal)\\S*.*$").sub(s, "")
	s = RegEx.create_from_string("\\s+").sub(s, " ", true)
	s = RegEx.create_from_string("\\s+\\)").sub(s, ")", true)
	return s.strip_edges()
