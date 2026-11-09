# 구간 시간 재기 (성능 비교, G3 2026-10-31): --perf-log 일 때만 켬 (Prof.on). 꺼져 있으면 now()·lap()·add() 가 거의 비용 없음.
#   한 함수 안 여러 구간: Prof.begin() 뒤 Prof.lap("이름") 을 구간 끝마다 (직전 lap 부터 잰 시간)
#   함수 통째: var t := Prof.now() … 끝에 Prof.add("이름", t)
# 합은 autopilot 이 찍기 전 N 초만 모아 '성능 구간' 줄로 (큰 순서)
extends RefCounted

static var on := false
static var hitch := false # W30: 히치 로거 (core/hitch.gd) 가 켜지면 참 — 구간을 프레임마다 모음 (frame). sums 는 on 일 때만
static var sums := {} # 이름 → [합 µs, 번]
static var frame := {} # W30: 이번 프레임 (perf.gd 가 매 프레임 가져가며 비움) 이름 → 합 µs
static var _lap := 0
# W41 --first-use: 구간 이름마다 처음·둘째 부름 µs + 번 + 가장 큰 µs — '처음 쓰는 값' (처음 − 둘째) 표. 켜면 on·hitch 도 켜짐 (autopilot)
static var track := false
static var firsts := {} # 이름 → [처음 µs, 둘째 µs, 번, 최대 µs, 합 µs]


static func set_hitch(v: bool) -> void:
	hitch = v
	if not hitch:
		frame = {}


# 지난 프레임 구간 합 (이름 → µs) 을 가져가고 비움
static func take_frame() -> Dictionary:
	var f := frame
	frame = {}
	return f


static func now() -> int:
	return Time.get_ticks_usec() if (on or hitch) else 0


static func begin() -> void:
	if on or hitch:
		_lap = Time.get_ticks_usec()


static func lap(name: String) -> void:
	if not (on or hitch):
		return
	var t := Time.get_ticks_usec()
	add_us(name, t - _lap)
	_lap = t


static func add(name: String, t0: int) -> void:
	if on or hitch:
		add_us(name, Time.get_ticks_usec() - t0)


static func add_us(name: String, us: int) -> void:
	if track:
		var f: Array = firsts.get(name, [us, -1, 0, 0, 0])
		if f[2] == 1:
			f[1] = us
		f[2] += 1
		f[3] = maxi(f[3], us)
		f[4] += us
		firsts[name] = f
	if on:
		var s: Array = sums.get(name, [0, 0])
		s[0] += us
		s[1] += 1
		sums[name] = s
	if hitch:
		frame[name] = int(frame.get(name, 0)) + us


static func reset() -> void:
	sums = {}


# 프레임당 평균 ms, 큰 순서 "이름 1.2ms · …"
static func report(frames: int) -> String:
	var rows := []
	for k in sums:
		rows.append([k, sums[k][0] / 1000.0 / maxf(1, frames)])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return " · ".join(rows.map(func(r): return "%s %.2fms" % [r[0], r[1]]))


# '처음 쓰는 값' 표 (W41): 처음 − 둘째 부름 (둘째가 없으면 처음 그대로) 이 큰 순서. 줄 = "이름 | 처음 ms | 둘째 ms | 번 | 최대 ms | 평균 ms | 처음-둘째 ms"
static func first_report(min_ms := 1.0) -> Array:
	var rows := []
	for k in firsts:
		var f: Array = firsts[k]
		var second: float = f[1] / 1000.0 if f[1] >= 0 else 0.0
		var d: float = f[0] / 1000.0 - second
		if f[3] / 1000.0 >= min_ms: # 가장 큰 부름이 문턱 넘는 것 (처음-둘째 가 음수여도 — 매번 느린 구간도 보이게)
			rows.append([k, f[0] / 1000.0, second if f[1] >= 0 else -1.0, f[2], f[3] / 1000.0, f[4] / 1000.0 / maxf(1, f[2]), d])
	rows.sort_custom(func(a, b): return a[6] > b[6])
	return rows.map(func(r): return "%s | 처음 %.1fms | 둘째 %s | %d번 | 최대 %.1fms | 평균 %.2fms | 처음-둘째 %.1fms" % [r[0], r[1], ("%.1fms" % r[2]) if r[2] >= 0.0 else "-", r[3], r[4], r[5], r[6]])
