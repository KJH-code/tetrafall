# 입장 쪼개기 문 (W42): 방 입장·카운트다운 시작처럼 '큰 일이 한 프레임에 몰리는' 순간에, 큰 일 (어두운 무대 만들기·지형 만들기·맵 적용·몸 만들기·큰 캐릭터·초상) 이
# 한 프레임에 하나씩만 돌게 줄 세움. 일마다 'ok(이름) → 하고 → done(이름, 시작)' 으로 부르고, ok 가 거짓이면 다음 프레임에 다시 (그동안 화면은 전환 띠 뒤).
# 규칙: 그 프레임에 아직 큰 일이 없었으면 무조건 허용 (굶지 않음). 있었으면 (이미 쓴 ms + 이 일의 예상 ms) 가 CAP_MS 이하일 때만.
# 예상 ms = 처음엔 EST_DEFAULT 표, 돌릴 때마다 잰 값 (이동 평균). 프레임 = Engine.get_process_frames().
# 끄기: --no-entry-split (옛 방식: 한 프레임에 다 함). 순수 계산 (can) 은 노드 없이 테스트 (tests/test_w42.gd)
extends RefCounted

const Opts := preload("res://core/opts.gd")

const SMALL_MS := 4.0 # 이보다 작은 일 (카드 한 장·잔상 몸 하나) 은 문을 늘 통과하고 합에도 안 셈 — 잔일이 큰 일 (초상·몸) 을 영영 막지 않게
const CAP_MS := 12.0 # 한 프레임 큰 일 합 상한 (여기에 평소 프레임 일 ~8ms 가 더해져 소프트웨어 렌더 스크립트 목표 25ms 이하. W45: 16 → 12 — 일이 8ms 안팎 조각으로 쪼개져 둘이 겹쳐도 20 안쪽)
const EST_DEFAULT := {
	"world.theme": 6.0, # apply_theme 한 단계 (W45: 지형·바닥 / 위험 / 칸 모양 세 단계, 한 덩어리는 11~17)
	"world.dark.load": 22.0, # 무대 스크립트 컴파일
	"world.dark": 8.0, # 어두운 무대 앞부분 (바닥·거울·빛·안개)
	"world.dark.part": 8.0, # 어두운 무대 소품 · 빛 가루 (한 조각. W51: 소품은 6ms 안팎 조각으로 끊음 — 한 덩어리는 22~32)
	"world.scenery": 9.0, # 지형 (섬·먼 배경 메시) 한 단계 (W45: 세 단계로 쪼갬, 한 덩어리는 17~23)
	"world.grid": 8.0, # 쌓인 칸 다시 깔기·튀어나온 조각
	"body": 5.0, # 몸 하나 만들기 (코드 몸 부분 + 외부 모델 붙이기. W45 부터 붙이기는 "body.ext" 조각으로 프레임에 걸침)
	"body.ext": 1.5, # 외부 모델 붙이기 한 조각 (장면·재질·소품·모션 연결 한 단계)
	"ui.stage": 8.0, # 대기실 큰 캐릭터 몸 만들기 (W45: 자세 굳히기는 조각, 한 덩어리는 14)
	"ui.portrait": 8.0, # 초상 한 장 — 몸 만들기까지 (W45: 자세 굳히기는 조각 "ui.portrait.prime", 한 덩어리는 14)
	"ui.portrait.prime": 8.0, # 초상·큰 캐릭터 자세 굳히기 50번 한 조각 (W45, 새 모델 5~10ms · 코드 몸 4~6ms)
	"fx.ghost": 3.0, # 잔상 몸 풀 미리 만들기 (몸 종류마다 하나)
	"ui.hud": 6.0, # 판 HUD 카드 미리 만들기 (카드 하나 ~1ms 라 여러 장)
}

static var enabled_override = null # 테스트: bool
static var _enabled = null
static var frame := -1
static var spent := 0.0
static var est := {} # 이름 → 예상 ms (이동 평균)
static var log := {} # 이름 → [돌린 수, 미룬 수, 최대 ms, 합 ms, 최소 ms] (확인용 --sched-log, W45 가 합·최소 추가 — 평균·바닥을 봄)
static var entered := true # W45: 방 입장 첫 바퀴 (맵·무대·지형·칸) 가 끝났나 — world 가 정함. 초상·큰 캐릭터는 끝난 뒤에 (그 전엔 큰 일이 한 프레임씩 줄 서 있음)
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


# 큰 일 (표 기본값 8ms 이상) 은 기본값보다 작게는 안 잡음 — 변한 게 없어 0.1ms 로 끝난 때의 값이 평균에 섞여 진짜 큰 일 (지형 다시 깔기 12ms) 이 '잔일' 로 문을 통과하던 것
static func est_of(name: String) -> float:
	var d := float(EST_DEFAULT.get(name, 5.0))
	var e := float(est.get(name, d))
	return maxf(e, d) if d >= 8.0 else e


# 지금 돌려도 되나 (꺼져 있으면 늘 참). 미루면 log 에 셈
static func ok(name: String) -> bool:
	if not on():
		return true
	_roll()
	var r := can(spent, est_of(name))
	if not r:
		var e: Array = log.get(name, [0, 0, 0.0, 0.0, 1e9])
		e[1] += 1
		log[name] = e
	return r


# W45: 조각별 끄는 인자 (--no-scene-split 지형 · --no-theme-split 맵 적용 · --no-body-split 몸 만들기 · --no-portrait-split 초상·큰 캐릭터) — 전후 비교
static var _ns := {}


static func no_split(what: String) -> bool:
	if not _ns.has(what):
		_ns[what] = Opts.args().has("--no-%s-split" % what)
	return bool(_ns[what])


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
		var e: Array = log.get(name, [0, 0, 0.0, 0.0, 1e9])
		e[0] += 1
		e[2] = maxf(e[2], ms)
		e[3] = float(e[3]) + ms
		e[4] = minf(float(e[4]), ms)
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
	_ns = {}
	entered = true
