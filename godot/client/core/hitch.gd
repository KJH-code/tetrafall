# 히치 (순간 끊김) 로거 — W30 (2026-11-07, 재혁 PC 새 외부 모델 랙: 지속 저FPS 인지 순간 끊김인지, 언제인지 모름 → 재혁이 다음 판 뒤 한 줄만 붙여 주면 원인이 보이게).
# 프레임 시간이 (최근 프레임 중앙값 × FACTOR) 와 MIN_MS 중 큰 값을 넘으면 히치 한 번으로 적음: 시각·프레임 ms·그 사이 '무슨 일이 있었나' 태그·가장 긴 구간·원인 추정.
# 꺼져 있으면 (on = false) tag/span/t 는 비교 한 번뿐 — 비용 0. 켜는 곳: ui/perf.gd (F3 패널을 켰을 때, 또는 실행 인자 --hitch). 기록 파일 user://hitches.txt (한 줄에 히치 하나).
#
# 태그 달기 (일어나는 쪽):  Hitch.tag("KO", "누구")                  — 한 순간 일 (프레임 사이에 모임)
#                           var t := Hitch.t() … Hitch.span("몸 만들기", "ninja", t)  — 시간이 걸린 일 (SPAN_MIN_MS 이상일 때만 적음)
# 같은 프레임 간격에 든 태그는 그 간격의 히치에 붙음 (perf.gd 가 프레임마다 take 로 가져감).
# 이 파일은 순수 계산 (노드 없음) — tests/test_hitch.gd
extends RefCounted

const FACTOR := 2.0 # 평범한 프레임 평균의 이 배 넘으면 히치
const MIN_MS := 20.0 # 평균이 아주 낮아도 (240fps) 이 이상만 히치 (60Hz 한 프레임 16.7ms 를 넘겨야 눈에 띔)
const BASE_N := 120 # 기준 (중앙값) 낼 최근 프레임 수
const BASE_MIN := 30 # 이만큼 모이기 전엔 MIN_MS 만 봄
const KEEP := 400 # 메모리에 남길 히치 수
const WATCH_FRAMES := 3 # 새 캐릭터 첫 등장 뒤 이만큼의 프레임은 '첫 그리기 지연 의심'
const SPAN_MIN_MS := 1.0
const FILE := "user://hitches.txt" # 기록 파일 (한 줄에 히치 하나)
const MAX_TAGS := 80 # 한 프레임 간격에 모을 태그 상한
# 원인 이름 → 설명 순서 (태그 종류 우선순위: 앞일수록 먼저 원인으로 침)
const KIND_ORDER := ["해상도 변경", "몸 불러오기", "몸 만들기", "외부 몸 연결", "미리 그리기", "초상·큰 캐릭터", "래그돌 만들기", "방 입장", "판 단계", "KO", "부활", "필살기", "스킬", "새 캐릭터"]

# 서버 이벤트 종류 → 태그 이름 (core/store.gd 가 스냅샷마다 달아 줌). 모르는 종류는 안 적음
const EVENT_KIND := {"death": "KO", "respawn": "부활", "skill": "스킬", "ult": "필살기", "pickup": "아이템", "roundStart": "판 단계", "roundEnd": "판 단계"}

static var on := false
static var _tags: Array = []
static var _seen := {}


static func t() -> int:
	return Time.get_ticks_usec() if on else 0


static func tag(kind: String, detail: String = "", ms: float = -1.0) -> void:
	if on and _tags.size() < MAX_TAGS:
		_tags.append([kind, detail, ms])


static func span(kind: String, detail: String, t0: int) -> void:
	if on:
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ms >= SPAN_MIN_MS:
			tag(kind, detail, ms)


# 처음이면 참 (로거를 켠 뒤 처음 — 새 캐릭터 첫 등장). 꺼져 있으면 늘 거짓
static func first(kind: String, key: String) -> bool:
	if not on:
		return false
	var k := kind + ":" + key
	if _seen.has(k):
		return false
	_seen[k] = true
	return true


static func take() -> Array:
	var o := _tags
	_tags = []
	return o


static func reset() -> void:
	_tags = []
	_seen = {}


# ---- 기록 (순수 계산) ----
class Log:
	var base: Array = [] # 최근 프레임 ms (히치 포함 — 기준은 중앙값)
	var records: Array = [] # 히치 {t, ms, thr, avg, tags, sec, top, script, rcpu, screen, cause, detail}
	var count := 0
	var worst := 0.0
	var causes := {} # 원인 → 횟수
	var watch := {} # 새 캐릭터 → 남은 프레임
	var frames := 0

	func avg() -> float:
		if base.size() < BASE_MIN:
			return 0.0
		var sorted := base.duplicate() # 중앙값: 히치가 섞여도 안 흔들리고, 계속 느린 기계 (30ms) 에선 그 30ms 가 기준
		sorted.sort()
		return float(sorted[sorted.size() / 2])

	func threshold() -> float:
		return maxf(FACTOR * avg(), MIN_MS)

	# ctx: {tags: [[kind, detail, ms]], sec: {구간: ms}, script, rcpu, screen}. 히치면 기록을 돌려주고, 아니면 {}
	func push(t_s: float, ms: float, ctx: Dictionary = {}) -> Dictionary:
		frames += 1
		var a := avg()
		var thr := threshold()
		var tags: Array = ctx.get("tags", [])
		var watched: Array = []
		for k in watch.keys():
			watched.append(k)
		var rec := {}
		if ms > thr:
			rec = {"t": t_s, "ms": ms, "thr": thr, "avg": a, "tags": tags, "sec": ctx.get("sec", {}), "script": float(ctx.get("script", 0.0)), "rcpu": float(ctx.get("rcpu", 0.0)), "screen": str(ctx.get("screen", "")), "watched": watched}
			var c: Array = cause_of(rec)
			rec["cause"] = c[0]
			rec["detail"] = c[1]
			count += 1
			worst = maxf(worst, ms)
			causes[c[0]] = int(causes.get(c[0], 0)) + 1
			records.append(rec)
			if records.size() > KEEP:
				records.pop_front()
		base.append(ms)
		if base.size() > BASE_N:
			base.pop_front()
		for k in watch.keys():
			watch[k] -= 1
			if watch[k] <= 0:
				watch.erase(k)
		for tg in tags:
			if tg[0] == "새 캐릭터":
				watch[str(tg[1])] = WATCH_FRAMES
		return rec

	# '히치 N회 · 최악 xxms · 원인 상위: A n, B m' (없으면 '히치 0회')
	func summary() -> String:
		if count == 0:
			return "히치 0회"
		var ks := causes.keys()
		ks.sort_custom(func(a, b): return causes[a] > causes[b])
		return "히치 %d회 · 최악 %dms · 원인 상위: %s" % [count, roundi(worst), ", ".join(ks.slice(0, 3).map(func(k): return "%s %d" % [k, causes[k]]))]


	# 원인 추정: [이름, 설명]. 순서: ① 시간 잰 일 중 가장 긴 것 ② 새 캐릭터 첫 등장 직후 (첫 그리기 지연 의심) ③ 일어난 일 (우선순위) ④ 가장 긴 구간 ⑤ 스크립트/렌더 CPU 비중 ⑥ 불명
	static func cause_of(rec: Dictionary) -> Array:
		var best = null
		for t in rec.tags:
			if float(t[2]) >= 0.0 and (best == null or float(t[2]) > float(best[2])):
				best = t
		var ms: float = rec.ms
		if best != null and float(best[2]) >= ms * 0.25:
			return [str(best[0]), "%s %.1fms" % [best[1], best[2]]]
		var watched: Array = rec.get("watched", [])
		if not watched.is_empty() and float(rec.rcpu) + 1.0 >= float(rec.script):
			return ["첫 그리기 지연 의심", "새 캐릭터 " + ",".join(watched)]
		for k in KIND_ORDER:
			for t in rec.tags:
				if t[0] == k:
					return [k, str(t[1])]
		if not rec.tags.is_empty():
			return [str(rec.tags[0][0]), str(rec.tags[0][1])]
		var top := ""
		var topv := 0.0
		for k in rec.sec:
			if float(rec.sec[k]) > topv:
				topv = float(rec.sec[k])
				top = str(k)
		if top != "" and topv >= ms * 0.4:
			return ["스크립트 구간", "%s %.1fms" % [top, topv]]
		if float(rec.script) >= ms * 0.5:
			return ["스크립트 (구간 불명)", "%.1fms" % rec.script]
		if float(rec.rcpu) >= ms * 0.5:
			return ["렌더 CPU (그리기 의심)", "%.1fms" % rec.rcpu]
		return ["원인 불명 (GPU 대기·화면 동기·OS?)", ""]


# 히치 한 줄 (파일·복사)
static func line(rec: Dictionary) -> String:
	var tg := []
	var merged := {}
	for t in rec.tags:
		var k := "%s%s" % [t[0], (" " + str(t[1])) if str(t[1]) != "" else ""]
		var m: Array = merged.get(k, [0, 0.0])
		m[0] += 1
		m[1] += maxf(0.0, float(t[2]))
		merged[k] = m
	for k in merged:
		var m: Array = merged[k]
		tg.append("%s%s%s" % [k, (" ×%d" % m[0]) if m[0] > 1 else "", (" %.1fms" % m[1]) if m[1] > 0.0 else ""])
	var secs: Array = rec.sec.keys()
	secs.sort_custom(func(a, b): return rec.sec[a] > rec.sec[b])
	return "%7.1fs  %6.1fms (기준 %.1f, 기준선 %.1f)  %s  원인: %s%s  | 스크립트 %.1f 렌더CPU %.1f | 구간: %s | 태그: %s" % [
		rec.t, rec.ms, rec.avg, rec.thr, rec.screen, rec.cause, (" (%s)" % rec.detail) if str(rec.detail) != "" else "", rec.script, rec.rcpu,
		", ".join(secs.slice(0, 3).map(func(k): return "%s %.1f" % [k, rec.sec[k]])) if not secs.is_empty() else "-",
		", ".join(tg) if not tg.is_empty() else "-"]


