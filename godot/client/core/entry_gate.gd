# 입장 쪼개기 문 (W42): 방 입장·카운트다운 시작처럼 '큰 일이 한 프레임에 몰리는' 순간에, 큰 일 (어두운 무대 만들기·지형 만들기·맵 적용·몸 만들기·큰 캐릭터·초상) 이
# 한 프레임에 하나씩만 돌게 줄 세움. 일마다 'ok(이름) → 하고 → done(이름, 시작)' 으로 부르고, ok 가 거짓이면 다음 프레임에 다시 (그동안 화면은 전환 띠 뒤).
# 규칙: 그 프레임에 아직 큰 일이 없었으면 무조건 허용 (굶지 않음). 있었으면 (이미 쓴 ms + 이 일의 예상 ms) 가 CAP_MS 이하일 때만.
# 예상 ms = 처음엔 EST_DEFAULT 표, 돌릴 때마다 잰 값 (이동 평균). 프레임 = Engine.get_process_frames().
# 끄기: --no-entry-split (옛 방식: 한 프레임에 다 함). 순수 계산 (can) 은 노드 없이 테스트 (tests/test_w42.gd)
extends RefCounted

const Opts := preload("res://core/opts.gd")

const SMALL_MS := 4.0 # 이보다 작은 일 (카드 한 장·잔상 몸 하나) 은 문을 늘 통과하고 합에도 안 셈 — 잔일이 큰 일 (초상·몸) 을 영영 막지 않게
const CAP_MS := 16.0 # 한 프레임 큰 일 합 상한 (여기에 평소 프레임 일 ~8ms 가 더해져 소프트웨어 렌더 스크립트 목표 25ms 이하)
const EST_DEFAULT := {
	"world.theme": 14.0, # apply_theme (G3 재질·칸 모양·위험·튀어나온 조각)
	"world.dark.load": 22.0, # 무대 스크립트 컴파일
	"world.dark": 8.0, # 어두운 무대 앞부분 (바닥·거울·빛·안개)
	"world.dark.part": 11.0, # 어두운 무대 소품 · 빛 가루 (한 조각)
	"world.scenery": 17.0, # 지형 (섬·먼 배경 메시)
	"world.grid": 8.0, # 쌓인 칸 다시 깔기·튀어나온 조각
	"body": 12.0, # 몸 하나 만들기
	"ui.stage": 14.0, # 대기실 큰 캐릭터 몸 만들기
	"ui.portrait": 14.0, # 초상 한 장
	"fx.ghost": 3.0, # 잔상 몸 풀 미리 만들기 (몸 종류마다 하나)
	"ui.hud": 6.0, # 판 HUD 카드 미리 만들기 (카드 하나 ~1ms 라 여러 장)
}

static var enabled_override = null # 테스트: bool
static var _enabled = null
static var frame := -1
static var spent := 0.0
static var est := {} # 이름 → 예상 ms (이동 평균)
static var log := {} # 이름 → [돌린 수, 미룬 수, 최대 ms] (확인용 --sched-log)
static var frame_peak := 0.0 # 한 프레임에 쓴 큰 일 합의 최대 (확인용)
static var _clock: Callable # 테스트 가짜 프레임 번호 () → int


static func on() -> bool:
	if enabled_override != null:
		return bool(enabled_override)
	if _enabled == null:
		_enabled = not Opts.args().has("--no-entry-split")
	return _enabled


# 순수 계산: 이미 쓴 spent_ms 인 프레임에 est_ms 짜리 일을 더 돌려도 되나
static func can(spent_ms: float, est_ms: float, cap_ms := CAP_MS) -> bool:
	return spent_ms <= 0.0 or est_ms < SMALL_MS or spent_ms + est_ms <= cap_ms


static func _roll() -> void:
	var f: int = int(_clock.call()) if _clock.is_valid() else Engine.get_process_frames()
	if f != frame:
		frame = f
		spent = 0.0


static func est_of(name: String) -> float:
	return float(est.get(name, EST_DEFAULT.get(name, 5.0)))


# 지금 돌려도 되나 (꺼져 있으면 늘 참). 미루면 log 에 셈
static func ok(name: String) -> bool:
	if not on():
		return true
	_roll()
	var r := can(spent, est_of(name))
	if not r:
		var e: Array = log.get(name, [0, 0, 0.0])
		e[1] += 1
		log[name] = e
	return r


static func t() -> int:
	return Time.get_ticks_usec()


# 돌렸음: 걸린 ms 를 이 프레임 합·예상에 반영
static func done(name: String, t0_us: int) -> float:
	var ms := (Time.get_ticks_usec() - t0_us) / 1000.0
	if on():
		_roll()
		if ms >= SMALL_MS:
			spent += ms
		frame_peak = maxf(frame_peak, spent)
		est[name] = ms if not est.has(name) else lerpf(float(est[name]), ms, 0.5)
		var e: Array = log.get(name, [0, 0, 0.0])
		e[0] += 1
		e[2] = maxf(e[2], ms)
		log[name] = e
	return ms


static func reset() -> void:
	frame = -1
	spent = 0.0
	est = {}
	log = {}
	frame_peak = 0.0
	_enabled = null
	enabled_override = null
	_clock = Callable()
