# 프레임 예산 스케줄러 (W41 2026-11-10 렉 사냥): 메뉴·대기실에서 하는 미리 읽기·미리 그리기·첫 사용 값 만들기를 한 곳에 모아
# '한 프레임에 몰리지 않게' 조각으로 나눠 돌림. 순수 계산 (노드 없음, 시계는 인자 — 테스트 tests/test_w41.gd). 쓰는 곳은 world/world.gd (메뉴 prewarm).
#
# 규칙
#  - 작업 = 조각 하나를 실행하는 Callable (끝나면 true, 다음 프레임에 이어서 하려면 false). 우선순위 (작을수록 먼저) → 같으면 넣은 순서.
#  - 프레임마다 step() 이 예산 (budget_ms, 기본 3ms) 안에서 조각을 돌림. 한 조각이 예산보다 길어도 (예: 몸 만들기 20ms) 그 프레임의 첫 조각이면 돌림 —
#    그 대신 같은 프레임에 다른 조각을 더 붙이지 않음. 조각 시간은 직접 재서 (clock) 작업마다 예상 ms 를 갱신 (다음에 예산 판단에 씀).
#  - 쉬는 때: ① 직전 프레임이 frame_cap_ms 보다 길었음 (이미 느린데 일을 얹지 않음) ② 입력 (마우스 이동·키·클릭) 뒤 quiet_ms 안 ③ hold (판 중·전환 중)
#    ④ 작업의 not_before 전. 단 ①②는 '굶는 중' (마지막으로 돌린 지 starve_ms 넘음) 이면 한 조각은 돌림 — 계속 마우스를 움직여도 준비가 끝나긴 하게.
#  - cancel(id)·cancel_group(group)·clear() 로 취소 (판이 시작되면 아직 안 한 미리 하기를 버림).
extends RefCounted

const Hitch := preload("res://core/hitch.gd")

const BUDGET_MS := 3.0 # 프레임당 (조각 시간 합) 예산
const FRAME_CAP_MS := 12.0 # 직전 프레임이 (평소 프레임 × FRAME_REL + 이만큼) 보다 길면 이번엔 쉼 — 평소 자체가 느린 기계 (소프트웨어 렌더·내장 GPU) 에서 영영 못 돌지 않게 평소 값에 상대
const FRAME_REL := 1.5
const QUIET_MS := 150.0 # 입력 뒤 이만큼 쉼
const STARVE_MS := 2500.0 # 이만큼 못 돌았으면 쉬는 규칙을 어기고 한 조각
const MAX_PIECES := 4 # 한 프레임 조각 수 상한 (아주 작은 조각이 많아도)
const EST_DEFAULT_MS := 1.0
const WAIT := -1 # 조각이 돌려줄 수 있는 값: 지금은 할 일이 없음 (읽기 끝나길·world 가 보이길 기다림) — 조각으로 안 세고 이번 프레임엔 건너뜀 (낮은 우선순위가 굶지 않게)


# 게임 전체가 같이 쓰는 하나 (world.gd 가 프레임마다 step, ui·초상 등이 add)
static var main: Sched = Sched.new()


class Task:
	extends RefCounted
	var id := ""
	var prio := 0
	var group := ""
	var fn: Callable
	var est_ms := EST_DEFAULT_MS # 예상 (처음엔 넣은 값, 돌릴수록 잰 값의 이동 평균)
	var not_before := 0.0 # 이 시각 (ms) 전엔 안 돌림
	var seq := 0
	var runs := 0
	var spent_ms := 0.0
	var worst_ms := 0.0
	var first_ms := -1.0 # 처음 조각 ms ('처음 쓰는 값' 표용)


class Sched:
	extends RefCounted
	var budget_ms := BUDGET_MS
	var frame_cap_ms := FRAME_CAP_MS
	var quiet_ms := QUIET_MS
	var starve_ms := STARVE_MS
	var max_pieces := MAX_PIECES
	var enabled := true
	var tasks: Array = []
	var finished: Array = [] # [id, 조각 수, 합 ms, 가장 긴 조각 ms] (끝난 것, 확인용)
	var pieces_run := 0 # 지금까지 돌린 조각 수
	var frames_busy := 0 # 조각을 돌린 프레임 수
	var worst_frame_ms := 0.0 # 한 프레임에 돌린 조각 시간 합의 최대
	var clock: Callable # () → 지금 ms (테스트가 가짜 시계를 끼움). 비어 있으면 엔진 시계
	var base_ms := 0.0 # 평소 프레임 간격 (쉬지 않은 프레임의 느린 이동 평균)
	var _seq := 0
	var _last_input := -1e12
	var _last_run := 0.0
	var _started := false
	var _ids := {} # 이름 → Task

	func now_ms() -> float:
		return float(clock.call()) if clock.is_valid() else Time.get_ticks_usec() / 1000.0

	# 작업 하나 넣음. 같은 id 가 이미 있으면 안 넣고 false. after_ms = 지금부터 이만큼 뒤에 시작 (넣은 시각 기준)
	func add(id: String, prio: int, fn: Callable, est_ms := EST_DEFAULT_MS, group := "", after_ms := 0.0, at := -1.0) -> bool:
		if _ids.has(id):
			return false
		var t := Task.new()
		t.id = id
		t.prio = prio
		t.fn = fn
		t.est_ms = est_ms
		t.group = group
		var n := at if at >= 0.0 else now_ms()
		t.not_before = n + after_ms
		_seq += 1
		t.seq = _seq
		tasks.append(t)
		_ids[id] = t
		if not _started:
			_started = true
			_last_run = n
		return true

	func has(id: String) -> bool:
		return _ids.has(id)

	func pending() -> int:
		return tasks.size()

	func cancel(id: String) -> bool:
		if not _ids.has(id):
			return false
		tasks.erase(_ids[id])
		_ids.erase(id)
		return true

	func cancel_group(group: String) -> int:
		var n := 0
		for t in tasks.duplicate():
			if t.group == group:
				cancel(t.id)
				n += 1
		return n

	func clear() -> void:
		tasks = []
		_ids = {}

	# 입력이 있었음 (마우스 이동·키·클릭). 이후 quiet_ms 동안은 안 돌림 (굶는 중이면 빼고)
	func note_input(at_ms: float) -> void:
		_last_input = at_ms

	func _best(at: float, skip: Dictionary = {}) -> Task:
		var best: Task = null
		for t in tasks:
			if t.not_before > at or skip.has(t.id):
				continue
			if best == null or t.prio < best.prio or (t.prio == best.prio and t.seq < best.seq):
				best = t
		return best

	# 프레임마다 한 번. at = 지금 ms, prev_frame_ms = 직전 프레임 간격 (0 이면 모름), hold = 지금은 아무것도 안 돌림.
	# 돌린 조각 수를 돌려줌
	func step(at: float, prev_frame_ms := 0.0, hold := false) -> int:
		if not enabled or tasks.is_empty() or hold:
			return 0
		var starving := at - _last_run >= starve_ms
		var slow := base_ms > 0.0 and prev_frame_ms > base_ms * FRAME_REL + frame_cap_ms
		if prev_frame_ms > 0.0 and not slow:
			base_ms = prev_frame_ms if base_ms <= 0.0 else lerpf(base_ms, prev_frame_ms, 0.05)
		var resting := slow or (at - _last_input < quiet_ms)
		if resting and not starving:
			return 0
		var spent := 0.0
		var n := 0
		var limit := 1 if resting else max_pieces # 굶어서 억지로 돌릴 땐 한 조각만
		var skip := {}
		while n < limit:
			var t := _best(at, skip)
			if t == null:
				break
			if n > 0 and spent + t.est_ms > budget_ms:
				break
			var t0 := now_ms()
			var r = t.fn.call()
			var ms := now_ms() - t0
			if typeof(r) == TYPE_INT and int(r) == WAIT:
				skip[t.id] = true # 기다리는 중: 조각으로 안 세고 다음 작업으로
				continue
			var done: bool = bool(r)
			spent += ms
			n += 1
			t.runs += 1
			t.spent_ms += ms
			t.worst_ms = maxf(t.worst_ms, ms)
			if t.first_ms < 0.0:
				t.first_ms = ms
			t.est_ms = ms if t.runs == 1 else lerpf(t.est_ms, ms, 0.4)
			if done:
				finished.append([t.id, t.runs, t.spent_ms, t.worst_ms])
				cancel(t.id)
			if spent >= budget_ms:
				break
		if n > 0:
			_last_run = at
			pieces_run += n
			frames_busy += 1
			worst_frame_ms = maxf(worst_frame_ms, spent)
			if Hitch.on and spent >= 1.0:
				Hitch.tag("미리 하기", "%d조각 %.1fms" % [n, spent], spent)
		return n
