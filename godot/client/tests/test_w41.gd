# W41 렉 사냥: 프레임 예산 스케줄러 (world/prewarm_sched.gd) · 프로파일 처음·둘째 표 (core/prof.gd) · 프레임 로그 줄 (core/hitch.gd)
extends RefCounted

const PS := preload("res://world/prewarm_sched.gd")
const Prof := preload("res://core/prof.gd")
const Hitch := preload("res://core/hitch.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 가짜 시계: 조각이 cost 만큼 시계를 흘림
class Fake:
	extends RefCounted
	var t := 0.0
	func now() -> float:
		return t


func _sched(f: Fake) -> PS.Sched:
	var s := PS.Sched.new()
	s.clock = Callable(f, "now")
	return s


func _piece(f: Fake, cost: float, log: Array, name: String, done := true) -> Callable:
	return func():
		f.t += cost
		log.append(name)
		return done


func test_budget_and_priority() -> void:
	var f := Fake.new()
	var s := _sched(f)
	var log := []
	s.add("c", 5, _piece(f, 1.0, log, "c"), 1.0, "", 0.0, 0.0)
	s.add("a", 1, _piece(f, 1.0, log, "a"), 1.0, "", 0.0, 0.0)
	s.add("b", 1, _piece(f, 1.0, log, "b"), 1.0, "", 0.0, 0.0)
	var n := s.step(1000.0)
	check(log == ["a", "b", "c"], "우선순위 → 넣은 순서: %s" % str(log))
	check(n == 3 and s.pending() == 0, "예산 3ms 안에 1ms 조각 셋")
	# 예산 초과: 2ms 조각 셋 = 첫 조각 후 예상 2+2 > 3 이라 한 프레임에 하나씩 (예상은 첫 실행 뒤 갱신)
	var s2 := _sched(f)
	var l2 := []
	for i in 3:
		s2.add("x%d" % i, 1, _piece(f, 2.0, l2, "x%d" % i), 2.0, "", 0.0, 0.0)
	check(s2.step(1000.0) == 1 and l2.size() == 1, "예산 넘으면 한 프레임 한 조각: %s" % str(l2))
	check(s2.step(1016.0) == 1 and s2.step(1032.0) == 1 and s2.pending() == 0, "프레임마다 하나씩 끝까지")
	check(s2.worst_frame_ms <= 2.0 + 0.001, "한 프레임 조각 합 ≤ 조각 하나: %s" % s2.worst_frame_ms)


func test_big_piece_runs_alone() -> void:
	var f := Fake.new()
	var s := _sched(f)
	var log := []
	s.add("big", 1, _piece(f, 40.0, log, "big"), 40.0, "", 0.0, 0.0)
	s.add("small", 2, _piece(f, 0.5, log, "small"), 0.5, "", 0.0, 0.0)
	s.step(1000.0)
	check(log == ["big"], "예산보다 큰 조각도 첫 조각이면 돌고 같은 프레임에 다른 조각은 안 붙음: %s" % str(log))
	s.step(1016.0)
	check(log == ["big", "small"], "다음 프레임에 작은 것")


func test_multi_step_task() -> void:
	var f := Fake.new()
	var s := _sched(f)
	var n := [0]
	s.add("m", 1, func():
		n[0] += 1
		f.t += 0.5
		return n[0] >= 3, 0.5, "", 0.0, 0.0)
	var frames := 0
	while s.pending() > 0 and frames < 10:
		s.step(1000.0 + frames * 16.0)
		frames += 1
	check(n[0] == 3, "false 를 돌려주면 이어서 (3번): %d" % n[0])
	check(s.finished.size() == 1 and s.finished[0][1] == 3, "끝난 표에 조각 수")


func test_input_rest_and_starve() -> void:
	var f := Fake.new()
	var s := _sched(f)
	var log := []
	s.add("a", 1, _piece(f, 1.0, log, "a"), 1.0, "", 0.0, 0.0)
	s.note_input(1000.0)
	check(s.step(1050.0) == 0, "입력 뒤 quiet 동안은 쉼")
	check(s.step(1000.0 + PS.QUIET_MS + 1.0) == 1, "quiet 지나면 돎")
	var s2 := _sched(f)
	var l2 := []
	s2.add("a", 1, _piece(f, 1.0, l2, "a"), 1.0, "", 0.0, 0.0)
	s2.add("b", 1, _piece(f, 1.0, l2, "b"), 1.0, "", 0.0, 0.0)
	# 계속 입력 중이어도 굶으면 (starve) 한 조각씩
	var t := 0.0
	var ran := 0
	for i in 400:
		t += 16.0
		s2.note_input(t)
		ran += s2.step(t)
	check(l2 == ["a", "b"], "계속 마우스를 움직여도 결국 끝남: %s" % str(l2))
	check(ran == 2, "굶을 땐 프레임당 한 조각")


func test_frame_cap_hold_cancel_after() -> void:
	var f := Fake.new()
	var s := _sched(f)
	var log := []
	s.add("a", 1, _piece(f, 1.0, log, "a"), 1.0, "g", 0.0, 0.0)
	s.add("late", 1, _piece(f, 1.0, log, "late"), 1.0, "g2", 500.0, 0.0)
	check(s.step(100.0, 60.0) == 0, "직전 프레임이 느리면 쉼")
	check(s.step(100.0, 10.0, true) == 0, "hold 면 쉼")
	check(s.step(100.0, 10.0) == 1 and log == ["a"], "not_before 전 작업은 안 돎")
	check(s.step(600.0) == 1 and log == ["a", "late"], "시각 지나면 돎")
	s.add("x", 1, _piece(f, 1.0, log, "x"), 1.0, "g", 0.0, 0.0)
	s.add("y", 1, _piece(f, 1.0, log, "y"), 1.0, "g", 0.0, 0.0)
	check(s.cancel_group("g") == 2 and s.pending() == 0, "그룹 취소")
	check(not s.add("z", 1, _piece(f, 1.0, log, "z"), 1.0, "", 0.0, 0.0) or true, "")
	check(s.add("z", 1, _piece(f, 1.0, log, "z")) == false, "같은 id 는 안 넣음")
	check(s.cancel("z") and not s.cancel("z"), "id 취소")


func test_prof_first_second() -> void:
	Prof.track = true
	Prof.firsts = {}
	Prof.add_us("t", 9000)
	Prof.add_us("t", 1000)
	Prof.add_us("t", 500)
	var rows := Prof.first_report(1.0)
	Prof.track = false
	Prof.firsts = {}
	check(rows.size() == 1 and rows[0].contains("처음 9.0ms") and rows[0].contains("둘째 1.0ms") and rows[0].contains("3번") and rows[0].contains("처음−둘째 8.0ms"), "처음·둘째 표: %s" % str(rows))


func test_frame_line() -> void:
	var l := Hitch.frame_line(1.5, 40.0, 12.0, 3.0, "메뉴", {"a": 5.0, "b": 0.1}, [["몸 만들기", "tank", 9.0], ["판 단계", "playing", -1.0]])
	var c := l.split("\t")
	check(c.size() == 7 and c[4] == "메뉴" and c[5] == "a 5.0" and c[6].contains("몸 만들기 tank 9.0ms") and c[6].contains("판 단계 playing"), "프레임 한 줄: %s" % l)
