# 성능·모션 보고서 글 만들기 (W48, 순수 계산 — 노드·엔진 상태 없음, tests/test_w48.gd).
# 재혁이 F3 한 줄·hitches.txt·motion_qa.txt 를 한 번도 못 보낸 것 (절차가 번거로움) → 결과 화면 버튼·F4 한 번으로 채팅에 붙일 한 덩어리 글.
# core/report.gd 가 값을 모아 build(d) 에 넘기고, 이 파일이 글로 만들면서 개인정보를 지우고 MAX_CHARS 안으로 줄임.
extends RefCounted

const MAX_CHARS := 1500
const HITCH_LINES := 5 # 히치 원인 상위 줄 수
const POP_LINES := 5 # 모션 팝 상위 줄 수
# 보고서에 넣는 실행 인자 (이름만, 값은 아래 VALUE_OK 에 든 것만). 나머지 (--server·--room·--name·--profile·--rec·파일 경로 …) 는 개인정보 위험이라 뺌
const VALUE_OK := ["gfx", "rendering-method", "rendering-driver", "ext", "fixed-fps"]
const OPT_DENY := ["server", "room", "name", "profile", "rec", "replay", "lag-log", "shot", "motion-qa", "auto", "title", "boot-log"]
const ENV_USER_NAMES := ["USERNAME", "USER", "LOGNAME", "COMPUTERNAME"]


# ---- 개인정보 지우기 ----
# C:\Users\이름\AppData\Roaming → %APPDATA%, …\AppData\Local → %LOCALAPPDATA%, C:\Users\이름 → %USERPROFILE%, /home/이름·/Users/이름 → ~ (리눅스 홈은 $HOME 도 씀),
# 그리고 이 PC 사용자 이름·컴퓨터 이름 (환경 변수) 이 글 안에 그대로 있으면 <사용자> 로. 이름이 너무 짧으면 (3자 미만) 다른 글자와 겹치니 경로만.
static func sanitize(text: String, names: Array = []) -> String:
	var s := text
	var res := [
		["(?i)[A-Z]:[\\\\/]+Users[\\\\/]+[^\\\\/\\s\"']+[\\\\/]+AppData[\\\\/]+Roaming", "%APPDATA%"],
		["(?i)[A-Z]:[\\\\/]+Users[\\\\/]+[^\\\\/\\s\"']+[\\\\/]+AppData[\\\\/]+Local", "%LOCALAPPDATA%"],
		["(?i)[A-Z]:[\\\\/]+Users[\\\\/]+[^\\\\/\\s\"']+", "%USERPROFILE%"],
		["(?i)(?<![\\w.])/(?:home|Users)/[^/\\s\"']+", "~"],
	]
	for r in res:
		s = RegEx.create_from_string(r[0]).sub(s, r[1], true)
	for n in names:
		var nm := str(n)
		if nm.length() >= 3:
			s = s.replace(nm, "<사용자>")
	return s


# 이 PC 사용자·컴퓨터 이름 (환경 변수, 비어 있으면 뺌)
static func env_names() -> Array:
	var out := []
	for k in ENV_USER_NAMES:
		var v := OS.get_environment(k)
		if v != "" and not out.has(v):
			out.append(v)
	return out


# ---- 실행 인자 → 켜진 옵션 글 ----
# args: 사용자 인자 (-- 뒤) + 엔진 인자. 값이 있는 인자는 VALUE_OK 에 든 것만 값까지, 나머지는 이름만. 경로가 든 값·OPT_DENY 는 뺌
static func opt_list(args: Array) -> Array:
	var out := []
	var i := 0
	while i < args.size():
		var a := str(args[i])
		if a.begins_with("--"):
			var k := a.substr(2)
			var v := ""
			if i + 1 < args.size() and not str(args[i + 1]).begins_with("--"):
				v = str(args[i + 1])
				i += 1
			if k != "" and not OPT_DENY.has(k) and not k.contains("/") and not k.contains("\\"):
				if v != "" and VALUE_OK.has(k) and not v.contains("/") and not v.contains("\\") and not v.contains(":"):
					out.append("--%s %s" % [k, v])
				else:
					out.append("--" + k)
		i += 1
	return out


# ---- 프레임 통계 ----
# frames: 프레임 간격 ms 들. 돌려줌 {n, fps, low_ms, low_fps, worst_ms, avg_ms}. low = 가장 느린 1% (적어도 1개) 의 평균
static func frame_stats(frames: PackedFloat32Array) -> Dictionary:
	var n := frames.size()
	if n == 0:
		return {"n": 0, "fps": 0.0, "avg_ms": 0.0, "low_ms": 0.0, "low_fps": 0.0, "worst_ms": 0.0}
	var sum := 0.0
	for v in frames:
		sum += v
	var sorted := frames.duplicate()
	sorted.sort()
	var k := maxi(1, ceili(n * 0.01))
	var lo := 0.0
	for i in k:
		lo += sorted[n - 1 - i]
	lo /= k
	var avg := sum / n
	return {"n": n, "fps": 1000.0 / maxf(avg, 0.001), "avg_ms": avg, "low_ms": lo, "low_fps": 1000.0 / maxf(lo, 0.001), "worst_ms": sorted[n - 1]}


# ---- 글 만들기 ----
# d 의 칸은 core/report.gd collect() 참고. 없는 칸은 건너뜀 (그 줄이 안 나옴)
static func build(d: Dictionary, names: Array = []) -> String:
	var groups: Array = [] # [중요도 (작을수록 먼저 지킴), [줄…]]
	var head := "[Tetrafall 성능 보고] %s · %s" % [str(d.get("version", "dev")), str(d.get("time", ""))]
	var env := []
	env.append(str(d.get("os", "?")))
	var gpu := str(d.get("gpu", ""))
	env.append("GPU %s%s" % [gpu if gpu != "" else "모름", (" (%s)" % d.gpu_kind) if str(d.get("gpu_kind", "")) != "" else ""])
	env.append("렌더러 %s" % str(d.get("renderer", "?")))
	env.append("창 %s" % str(d.get("win", "?")))
	if d.get("ui") != null:
		env.append("UI %s" % str(d.ui))
	var s3 := "3D %d%%" % roundi(float(d.get("scale3d", 1.0)) * 100.0)
	if d.get("scale_min") != null and float(d.scale_min) < float(d.get("scale3d", 1.0)) - 0.005:
		s3 += " (판 중 최저 %d%%)" % roundi(float(d.scale_min) * 100.0)
	env.append(s3)
	if str(d.get("quality", "")) != "":
		env.append("화질 %s" % str(d.quality))
	var lines_env := ["환경: " + " · ".join(env)]
	var round_line := _round_line(d)
	var fl := _frame_lines(d)
	var hl := _hitch_lines(d)
	var pl := _pop_lines(d)
	var ol := []
	var opts: Array = d.get("opts", [])
	ol.append("옵션: " + (" ".join(opts) if not opts.is_empty() else "기본"))
	groups = [
		[0, [head]],
		[0, lines_env],
		[1, [round_line] if round_line != "" else []],
		[1, fl],
		[2, hl.slice(0, 2)], # 히치 요약 줄 + 맨 위 원인
		[3, ol],
		[4, pl.slice(0, 2)],
		[5, hl.slice(2)],
		[6, pl.slice(2)],
	]
	return fit(groups, names)


# 중요도 순으로 줄을 쌓되 MAX_CHARS 를 넘으면 중요도 낮은 줄부터 버림. 쌓은 뒤 글 순서는 groups 순서 그대로 (중요도 순서가 곧 글 순서는 아님: 옵션 줄은 중간)
static func fit(groups: Array, names: Array = []) -> String:
	var order := []
	for gi in groups.size():
		order.append(gi)
	order.sort_custom(func(a, b): return groups[a][0] < groups[b][0] or (groups[a][0] == groups[b][0] and a < b))
	var keep := {} # 줄 번호 (그룹, 줄) → 참
	var total := 0
	var count := 0
	for gi in order:
		for li in (groups[gi][1] as Array).size():
			var line := sanitize(str(groups[gi][1][li]), names)
			var add := line.length() + (1 if count > 0 else 0)
			if total + add > MAX_CHARS:
				continue # 이 줄은 안 들어감 (더 짧은 다음 줄은 들어갈 수도)
			total += add
			count += 1
			keep["%d:%d" % [gi, li]] = line
	var out := []
	for gi in groups.size():
		for li in (groups[gi][1] as Array).size():
			var k := "%d:%d" % [gi, li]
			if keep.has(k):
				out.append(keep[k])
	return "\n".join(out)


static func _round_line(d: Dictionary) -> String:
	if not bool(d.get("has_round", false)):
		return "판: 아직 판 기록 없음 (한 판 하고 다시 눌러 주세요)"
	var parts := []
	var kind := ""
	if bool(d.get("tutorial", false)):
		kind = "튜토리얼 · "
	elif bool(d.get("practice", false)):
		kind = "연습 · "
	parts.append("%s캐릭터 %s" % [kind, str(d.get("char", "?"))])
	var pn := int(d.get("players", 0))
	if pn > 0:
		parts.append("%d명%s" % [pn, (" (봇 %d)" % int(d.bots)) if int(d.get("bots", 0)) > 0 else ""])
	parts.append("맵 %s" % str(d.get("map", "?")))
	parts.append("모드 %s" % str(d.get("mode", "?")))
	parts.append("%d초%s" % [roundi(float(d.get("secs", 0.0))), " (진행 중)" if bool(d.get("partial", false)) else ""])
	return "판: " + " · ".join(parts)


static func _frame_lines(d: Dictionary) -> Array:
	if int(d.get("frames", 0)) <= 0:
		return []
	var out := []
	out.append("프레임: 평균 %d FPS · 1%% low %d FPS (%.1fms) · 최악 %dms @ %.1fs · %d프레임" % [roundi(float(d.fps)), roundi(float(d.low_fps)), float(d.low_ms), roundi(float(d.worst_ms)), float(d.worst_t), int(d.frames)])
	var cpu := []
	if float(d.get("proc_avg", -1.0)) >= 0.0:
		cpu.append("엔진 처리 평균 %.1fms (최대 %.0f)" % [float(d.proc_avg), float(d.get("proc_max", 0.0))])
	if float(d.get("script", -1.0)) >= 0.0:
		cpu.append("스크립트 %.1fms" % float(d.script))
	if float(d.get("rcpu", -1.0)) >= 0.0:
		cpu.append("렌더 CPU %.1fms" % float(d.rcpu))
	if float(d.get("rgpu", -1.0)) >= 0.0:
		cpu.append("GPU %.1fms" % float(d.rgpu))
	if float(d.get("vram", -1.0)) >= 0.0:
		cpu.append("영상 메모리 %dMB" % roundi(float(d.vram)))
	if not cpu.is_empty():
		out.append("부하: " + " · ".join(cpu))
	return out


static func _hitch_lines(d: Dictionary) -> Array:
	if int(d.get("frames", 0)) <= 0:
		return []
	var out := []
	var n := int(d.get("hitch_n", 0))
	var s := "히치: %d회" % n
	if n > 0:
		s += " · 최악 %dms" % roundi(float(d.get("hitch_worst", 0.0)))
	s += " · 해상도 변경 %d회" % int(d.get("res_changes", 0))
	out.append(s)
	for l in d.get("hitch_lines", []):
		out.append("  " + str(l))
	return out


static func _pop_lines(d: Dictionary) -> Array:
	if d.get("pops") == null:
		return []
	var by: Dictionary = d.get("pop_by", {})
	var obs: Dictionary = d.get("pop_obs", {})
	var keys := {}
	for k in by:
		keys[k] = true
	for k in obs:
		keys[k] = true
	var ks := keys.keys()
	ks.sort_custom(func(a, b): return int(by.get(a, 0)) > int(by.get(b, 0)) or (int(by.get(a, 0)) == int(by.get(b, 0)) and str(a) < str(b)))
	var parts := []
	for k in ks:
		parts.append("%s %d회/%d초" % [k, int(by.get(k, 0)), roundi(float(obs.get(k, 0.0)))])
	var out := []
	out.append("모션 팝 (몸마다 번갈아 지켜본 표본): %d회 · %s" % [int(d.pops), ", ".join(parts)] if not parts.is_empty() else "모션 팝: %d회" % int(d.pops))
	for l in d.get("pop_lines", []):
		out.append("  " + str(l))
	return out
