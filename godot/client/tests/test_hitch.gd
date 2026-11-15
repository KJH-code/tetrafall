# W30 히치 로거 (core/hitch.gd): 기준선·원인 태그·첫 그리기 지연 의심·요약/복사 줄·꺼지면 비용 0·구간 모으기 (core/prof.gd)
extends RefCounted

const Hitch := preload("res://core/hitch.gd")
const Prof := preload("res://core/prof.gd")
const PC := preload("res://ui/perf_calc.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _warm(log, n := 60, ms := 8.0) -> void:
	for i in n:
		log.push(i * 0.008, ms, {})


func test_threshold() -> void:
	var log := Hitch.Log.new()
	check(log.threshold() == Hitch.MIN_MS, "표본 모이기 전엔 MIN_MS: %s" % log.threshold())
	_warm(log, 60, 8.0)
	check(log.threshold() == Hitch.MIN_MS, "평균 8ms → 2배 16 < 20 이라 20: %s" % log.threshold())
	var l2 := Hitch.Log.new()
	_warm(l2, 60, 30.0)
	check(absf(l2.threshold() - 60.0) < 0.01, "평균 30ms → 60: %s" % l2.threshold())
	check(l2.push(5.0, 50.0, {}).is_empty(), "지속 저FPS (30ms) 의 50ms 는 히치 아님")
	check(not l2.push(5.1, 70.0, {}).is_empty(), "평균 2배 넘는 70ms 는 히치")


func test_hitch_not_in_baseline() -> void:
	var log := Hitch.Log.new()
	_warm(log)
	var a := log.avg()
	for i in 5:
		log.push(1.0 + i, 90.0, {})
	check(absf(log.avg() - a) < 0.001, "히치 몇 번은 기준(중앙값)을 안 흔듦")
	check(log.count == 5 and log.worst == 90.0, "횟수·최악")


func test_cause_priority() -> void:
	var log := Hitch.Log.new()
	_warm(log)
	var r := log.push(2.0, 80.0, {"tags": [["판 단계", "playing", -1.0], ["몸 불러오기", "ninja 파일", 60.0]]})
	check(r.cause == "몸 불러오기", "잰 일이 크면 그것: %s" % r.cause)
	r = log.push(3.0, 60.0, {"tags": [["KO", "death", -1.0], ["판 단계", "playing", -1.0]]})
	check(r.cause == "판 단계", "우선순위 표: %s" % r.cause)
	r = log.push(4.0, 60.0, {"sec": {"몸 figureAnim": 40.0, "ui": 3.0}})
	check(r.cause == "스크립트 구간" and "figureAnim" in r.detail, "가장 긴 구간: %s %s" % [r.cause, r.detail])
	r = log.push(5.0, 60.0, {"script": 40.0})
	check(r.cause.begins_with("스크립트"), "스크립트 비중: %s" % r.cause)
	r = log.push(6.0, 60.0, {"script": 3.0, "rcpu": 45.0})
	check(r.cause.begins_with("렌더 CPU"), "렌더 CPU 비중: %s" % r.cause)
	r = log.push(7.0, 60.0, {"script": 3.0, "rcpu": 3.0})
	check(r.cause.begins_with("원인 불명"), "불명: %s" % r.cause)


func test_new_char_shader_window() -> void:
	var log := Hitch.Log.new()
	_warm(log)
	var r := log.push(2.0, 8.0, {"tags": [["새 캐릭터", "ninja", -1.0]]})
	check(r.is_empty(), "등장 프레임이 짧으면 기록 없음")
	r = log.push(2.1, 90.0, {"script": 4.0, "rcpu": 70.0})
	check(r.cause == "첫 그리기 지연 의심" and "ninja" in r.detail, "다음 프레임 히치 = 셰이더 의심: %s %s" % [r.cause, r.detail])
	for i in Hitch.WATCH_FRAMES:
		log.push(3.0 + i, 8.0, {})
	r = log.push(9.0, 90.0, {"script": 4.0, "rcpu": 70.0})
	check(not r.cause.begins_with("첫 그리기"), "창이 지나면 아님: %s" % r.cause)


func test_summary_and_line() -> void:
	var log := Hitch.Log.new()
	check(log.summary() == "히치 0회", "없음: " + log.summary())
	_warm(log)
	log.push(1.0, 120.0, {"tags": [["몸 불러오기", "tank", 100.0]]})
	log.push(2.0, 90.0, {"tags": [["몸 불러오기", "hook", 70.0]]})
	log.push(3.0, 50.0, {"tags": [["KO", "death", -1.0]]})
	var s := log.summary()
	check(s == "히치 3회 · 최악 120ms · 원인 상위: 몸 불러오기 2, KO 1", s)
	var ln := Hitch.line(log.records[0])
	check("몸 불러오기" in ln and "120.0ms" in ln and "tank" in ln, ln)
	check(PC.perf_line({"fps": 60.0, "avg": 16.0, "low": 20.0, "work": 5.0, "other": 1.0, "sections": {}}, {"hitch": s}).ends_with(s), "복사 줄 끝에 히치 요약")


func test_off_is_free() -> void:
	Hitch.on = false
	Hitch.reset()
	check(Hitch.t() == 0, "꺼지면 시각 안 잼")
	Hitch.tag("KO", "x")
	Hitch.span("몸 만들기", "x", 0)
	check(Hitch.take().is_empty() and not Hitch.first("새 캐릭터", "a"), "꺼지면 아무것도 안 모음")
	Hitch.on = true
	Hitch.tag("KO", "x")
	check(Hitch.first("새 캐릭터", "a") and not Hitch.first("새 캐릭터", "a"), "처음 한 번만")
	check(Hitch.take().size() == 1 and Hitch.take().is_empty(), "take 는 비움")
	var t := Hitch.t()
	check(t > 0, "켜면 잼")
	Hitch.span("몸 만들기", "x", t - 5000)
	var tg := Hitch.take()
	check(tg.size() == 1 and tg[0][2] >= 5.0, "span ms: %s" % [tg])
	Hitch.on = false
	Hitch.reset()


func test_prof_frame() -> void:
	Prof.set_hitch(false)
	Prof.add_us("a", 500)
	check(Prof.take_frame().is_empty(), "꺼지면 안 모음")
	Prof.set_hitch(true)
	var t := Prof.now()
	check(t > 0, "켜면 now 잼")
	Prof.add_us("a", 500)
	Prof.add_us("a", 700)
	var f := Prof.take_frame()
	check(f.get("a") == 1200 and Prof.take_frame().is_empty(), "프레임 합 %s" % [f])
	Prof.set_hitch(false)
	Prof.sums = {}
