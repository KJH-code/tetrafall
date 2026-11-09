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
	s.base_ms = 10.0 # 평소 10ms
	check(s.step(100.0, 60.0) == 0, "직전 프레임이 평소보다 많이 느리면 쉼")
	check(s.base_ms == 10.0, "느린 프레임은 평소 값에 안 섞임")
	var slow := _sched(f) # 평소 자체가 느린 기계 (100ms): 110ms 는 쉴 이유 아님
	slow.add("q", 1, _piece(f, 1.0, [], "q"), 1.0, "", 0.0, 0.0)
	slow.step(0.0, 100.0)
	slow.add("r", 1, _piece(f, 1.0, [], "r"), 1.0, "", 0.0, 0.0)
	check(slow.step(200.0, 110.0) == 1, "평소가 느린 기계에선 계속 돎")
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
	check(rows.size() == 1 and rows[0].contains("처음 9.0ms") and rows[0].contains("둘째 1.0ms") and rows[0].contains("3번") and rows[0].contains("처음-둘째 8.0ms"), "처음·둘째 표: %s" % str(rows))


func test_frame_line() -> void:
	var l := Hitch.frame_line(1.5, 40.0, 12.0, 3.0, "메뉴", {"a": 5.0, "b": 0.1}, [["몸 만들기", "tank", 9.0], ["판 단계", "playing", -1.0]])
	var c := l.split("\t")
	check(c.size() == 7 and c[4] == "메뉴" and c[5] == "a 5.0" and c[6].contains("몸 만들기 tank 9.0ms") and c[6].contains("판 단계 playing"), "프레임 한 줄: %s" % l)


# 적응형 해상도: 판 시작 직후 스파이크 (로딩·첫 사용) 를 GPU 병목으로 안 봄 · 바꾼 직후 창 건너뜀
const AC := preload("res://world/adapt_calc.gd")
const WC := preload("res://world/world_config.gd")


func _feed(ctl, frames: Array) -> int:
	var changes := 0
	for f in frames:
		if ctl.push(f, -1.0, 0.0): # 일 시간 모름 → GPU 쪽으로 침
			changes += 1
	return changes


func test_adapt_ignores_spikes() -> void:
	var c = AC.Ctl.new(1.0, 16.667)
	var frames := []
	for i in 40:
		frames.append(10.0)
	for i in 8: # 판 시작 직후: 몸 만들기·첫 그리기로 80ms 프레임이 띄엄띄엄 (창 20프레임의 40%)
		frames.append(80.0)
		frames.append(10.0)
		frames.append(10.0)
	var ch := _feed(c, frames)
	check(ch == 0 and c.scale == 1.0, "스파이크만으로는 배율이 안 내려감: 변경 %d 배율 %s" % [ch, c.scale])
	check(c.spikes >= 6, "스파이크로 버린 프레임 수: %d" % c.spikes)
	# 끄고 (spike 배율을 아주 크게) 같은 입력이면 예전처럼 내려감 = 이 필터가 막은 것
	var cfg: Dictionary = WC.ADAPT.duplicate()
	cfg["spike"] = 1000.0
	var c2 = AC.Ctl.new(1.0, 16.667, cfg)
	_feed(c2, frames)
	check(c2.scale < 1.0, "필터 없으면 같은 입력에 내려감 (비교): %s" % c2.scale)


func test_adapt_sustained_slow_still_adapts() -> void:
	var c = AC.Ctl.new(1.0, 16.667)
	var frames := []
	for i in 200:
		frames.append(30.0) # 계속 30ms = GPU 병목 (스파이크 아님)
	_feed(c, frames)
	check(c.scale < 0.9, "계속 느리면 내려감: %s" % c.scale)


func test_adapt_settle_after_change() -> void:
	var c = AC.Ctl.new(1.0, 16.667)
	var frames := []
	for i in 20:
		frames.append(30.0)
	var ch1 := _feed(c, frames) # 첫 창 → 내림
	check(ch1 == 1, "첫 창에서 한 번 내림: %d" % ch1)
	var s1: float = c.scale
	_feed(c, frames) # 바로 다음 창은 건너뜀 (3D 버퍼 다시 만든 직후)
	check(c.scale == s1, "바꾼 직후 한 창은 판단 안 함: %s → %s" % [s1, c.scale])
	_feed(c, frames)
	check(c.scale < s1, "그다음 창은 다시 판단")


# 히치 로거 강화: 이벤트 태그 (캐릭터·종류) · 원인 상위 n 요약 · 한 판 몫만
func test_event_tag() -> void:
	check(Hitch.event_tag({"type": "ult"}, "hook") == ["필살기", "hook ult"], "필살기는 캐릭터와 함께: %s" % str(Hitch.event_tag({"type": "ult"}, "hook")))
	check(Hitch.event_tag({"type": "skill"}, "ninja") == ["스킬", "ninja skill"], "스킬")
	check(Hitch.event_tag({"type": "quakeRise"}) == ["이벤트", "quakeRise"], "그 밖 이벤트는 종류 그대로")
	check(Hitch.event_tag({"type": "death"})[0] == "KO", "KO 는 기존 표")
	check(Hitch.event_tag({}).is_empty(), "종류 없으면 안 닮")


func test_top_report() -> void:
	var log := Hitch.Log.new()
	for i in 60:
		log.push(i * 0.01, 8.0, {})
	log.push(1.0, 90.0, {"tags": [["몸 만들기", "tank", 60.0]], "screen": "대기실"})
	var from := log.count
	log.push(2.0, 50.0, {"tags": [["필살기", "hook ult", -1.0]], "screen": "판 (playing)"})
	log.push(3.0, 120.0, {"tags": [["필살기", "tank ult", -1.0]], "screen": "판 (playing)"})
	log.push(4.0, 70.0, {"tags": [["블록 낙하 시작", "T", -1.0]], "screen": "판 (playing)"})
	var all := log.top_report(0, 5)
	check(all.size() == 3 and all[0].contains("필살기 ×2") and all[0].contains("최악 120ms") and all[0].contains("@ 3.0s"), "전체 상위: %s" % str(all))
	var one := log.top_report(from, 5)
	check(one.size() == 2 and not str(one).contains("몸 만들기"), "한 판 몫만 (그 전 히치 뺌): %s" % str(one))
	check(log.top_report(log.count, 5).is_empty(), "히치 없으면 빈 목록")


# 재질 미리 그리기 수집: 재질 중복 없이·이미 한 것 제외·MultiMesh 표시·몸 제외
const WS := preload("res://world/warm_scan.gd")


func test_warm_scan_collect() -> void:
	var root := Node3D.new()
	var m1 := StandardMaterial3D.new()
	var m2 := ShaderMaterial.new()
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	a.material_override = m1
	root.add_child(a)
	var b := MeshInstance3D.new() # 같은 재질 두 번 → 한 번만
	b.mesh = BoxMesh.new()
	b.material_override = m1
	root.add_child(b)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	var c := MultiMeshInstance3D.new()
	c.multimesh = mm
	c.material_override = m2
	root.add_child(c)
	var surf := MeshInstance3D.new() # 표면 재질
	var bm := BoxMesh.new()
	var m3 := StandardMaterial3D.new()
	bm.material = m3
	surf.mesh = bm
	root.add_child(surf)
	var done := {}
	var list := WS.collect(root, done)
	check(list.size() == 3, "재질 셋 (중복·표면 포함): %d" % list.size())
	var multi := 0
	for e in list:
		multi += 1 if e[1] else 0
	check(multi == 1, "MultiMesh 재질 표시")
	check(WS.collect(root, done).is_empty(), "이미 한 재질은 다시 안 모음")
	var host := Node3D.new()
	var sp := WS.spawn(host, list, null)
	check(sp.get_child_count() == list.size() * 2, "재질마다 보통 + MultiMesh 하나씩: %d" % sp.get_child_count())
	host.free()
	root.free()


func test_wait_does_not_starve_lower_priority() -> void:
	var f := Fake.new()
	var s := _sched(f)
	var log := []
	s.add("blocked", 1, func(): return PS.WAIT, 1.0, "", 0.0, 0.0)
	s.add("low", 9, _piece(f, 1.0, log, "low"), 1.0, "", 0.0, 0.0)
	var n := s.step(1000.0)
	check(log == ["low"] and n == 1, "기다리는 작업이 낮은 우선순위를 막지 않음: %s" % str(log))
	check(s.has("blocked") and s.pieces_run == 1, "기다림은 조각으로 안 셈")
