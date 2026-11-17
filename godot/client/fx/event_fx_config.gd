# c9-u3 돌발 이벤트 세계 연출 수치 (fx/event_fx.gd 가 그림, 계산 fx/event_fx_math.gd, 테스트 tests/test_fx.gd test_c9_*).
# 이벤트 5종 (돌풍·빙판·저중력·블록 폭우·보급) 이 도는 동안 필드 안에 그 모습 — 위 띠 글을 안 읽어도 무슨 이벤트인지, 돌풍이 어느 쪽인지.
# 길이·높이·빠르기 단위는 칸 (= m)·초, 색은 0xRRGGBB, 알파 0~1. 눈으로 맞출 값은 전부 이 표
# 처음 받은 출발 값에서 사진 (tools/event_sheet.gd 견본 + 녹화 재생) 을 보고 고친 것: 돌풍 줄 수 28~48 → 40~72·길이 1.6~2.6 → 2.0~3.2·폭 0.05 → 0.06·알파 올림 (지형 많은 맵에서 화면에 두세 줄뿐이었음),
#   빙판 알파 0.32 → 0.42 (초원에서 민트색으로만 보임), 티끌 60 → 80·크기 0.08 → 0.16 + 꼬리 (별·먼지와 헷갈림), 폭우 높이 6~12 → 3.5~12·폭 0.04 → 0.07, 보급 기둥 폭 0.12 → 0.14·알파 0.6 → 0.75 (밝은 바닥)
extends RefCounted

const C := preload("res://core/config.gd")
const G3C := preload("res://shaders/g3_config.gd")

# 재질 모양: world/warm_scan.gd STD_KEYS 에 이미 있는 줄 (빛 안 받음·반투명·정점 색·뒷면 안 그림·안개 안 받음) — 판 들어올 때 미리 그려 둬 셰이더를 새로 안 만듦
const KEY := [0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0]

# common: fade_in·fade_out 들어올 때·끝날 때 알파가 흐려지는 시간 · near 카메라에서 이 안의 줄·티끌·기둥은 알파 0 (눈앞을 가리지 않게), near_soft 그 밖 이만큼에 걸쳐 다시 진해짐
#   (바닥에 붙는 빙판 판·반짝 줄·보급 고리는 안 뺌: 1인칭 눈높이 EYE_HEIGHT 1.45 가 near 보다 낮아 내 발밑 칸이 늘 비게 됨)
#   order_floor 빙판 판 순서 (그림자 칸 0·착지 테 1·발밑 고리 7 아래) · order_air 줄·티끌·기둥·보급 고리 (발밑 고리 7·예고 고리 9·이름표 11 아래)
#   low_k 그래픽 낮춤이면 줄·티끌 수 × 이 값 · margin 줄이 필드 밖 이만큼까지 흐르고 넘으면 반대편에서 다시 나옴
#   thin 줄·기둥 폭, thin_mote 티끌 크기가 카메라 거리 × 이 값보다 작아지지 않게 (멀리서·관전에서도 한두 화소는 되게 — 가까이선 표의 폭 그대로)
# 높이 (z) 는 전부 그 자리 바닥 (기둥 꼭대기·위험 액체 표면) 위 — 지형이 높은 맵·액체가 차오른 판에서도 사람 눈높이에 보이게
# wind 돌풍: n 줄 수 (판 size[0] 일 때 n[0] ~ size[1] 일 때 n[1], 사이는 선형) · len 줄 길이 · width 폭 · z 높이 · follow 흐르며 바닥 높이를 따라가는 빠르기 (초당 배율) · speed 흐르는 빠르기 (± jitter 비율) · edge 가장자리에서 이만큼에 걸쳐 흐려짐
#   2단: 가운데 core (폭 비율) 는 core_color·core_alpha 흰 심, 바깥은 color·alpha 연하늘. prof 줄 길이 따라 알파 [[자리 −0.5 꼬리 ~ 0.5 머리, 배율]]
# ice 빙판: 위험 액체에 안 잠긴 칸 윗면마다 칸보다 inset 작은 판, lift 띄움 (그림자 칸 SHADOW_LIFT 0.03 아래) · spread 가운데에서 바깥으로 퍼지는 시간
#   glint 반짝 줄: every 칸 중 1칸꼴 (칸 좌표 해시), 대각선 두 방향, 판 위 lift 더, order 판 바로 위 (0 아래). 그래픽 낮춤이면 끔
# lowgrav 저중력: 바닥에서 오르는 마름모 티끌. 판 ref 일 때 n 개, 넓이에 비례, 최소 min · size 마름모 크기 · tail 아래로 흐려지는 꼬리 길이 (× size, 오르는 쪽이 읽히게), tail_w 꼬리 폭 (× size), tail_alpha 꼬리 머리 알파 배율 · speed 오르는 빠르기 · z 높이 되풀이 · colors 두 색을 번갈아 · sway [옆 흔들림 폭, 빠르기 rad/초]
# rain 블록 폭우: 필드 위 높이 z 에서 내려오는 세로 줄 n 개. 2단: 바깥 잉크 (외곽선 색, alpha) + 가운데 흰 심 (core_alpha)
# supply 보급: 새 아이템 자리마다 빛 기둥 (높이 h·폭 width, 흰 심 + 아이템 빛 노랑, alpha → life 초에 0, 먹히면 바로 지움) + 바닥 2단 고리 한 번 (world/ring_look.gd aura 메시, ring.ms 동안 r → r × grow)
#   arm 보급 이벤트 뒤 이 시간 안에 새로 나타난 아이템을 보급품으로 봄 (보통은 같은 스냅샷)
const EVENT_FX := {
	"common": {"fade_in": 0.4, "fade_out": 0.6, "near": 1.5, "near_soft": 2.0, "order_floor": -2, "order_air": 3, "low_k": 0.4, "margin": 1.0, "thin": 0.006, "thin_mote": 0.01},
	"wind": {"n": [40, 72], "size": [10, 19], "len": [2.0, 3.2], "width": 0.06, "z": [0.4, 3.6], "speed": 6.0, "jitter": 0.15, "edge": 1.0, "follow": 8.0,
		"core": 0.4, "core_color": 0xffffff, "core_alpha": 0.7, "color": 0xcfe8ff, "alpha": 0.42, "prof": [[-0.5, 0.0], [0.15, 1.0], [0.5, 0.4]]},
	"ice": {"inset": 0.06, "lift": 0.015, "color": 0xbfe9ff, "alpha": 0.42, "spread": 0.5,
		"glint": {"every": 4, "len": 0.5, "width": 0.05, "color": 0xffffff, "alpha": 0.5, "lift": 0.004, "order": -1}},
	"lowgrav": {"n": 80, "ref": 19, "min": 40, "size": 0.16, "tail": 2.5, "tail_w": 0.4, "tail_alpha": 0.55, "speed": 0.5, "jitter": 0.3, "z": [0.0, 6.0], "edge": 0.5, "colors": [0xd8c8ff, 0xc8e8ff], "alpha": 0.7, "sway": [0.12, 1.4]},
	"rain": {"n": 40, "z": [3.5, 12.0], "len": 1.2, "width": 0.07, "speed": 8.0, "jitter": 0.15, "edge": 1.0,
		"core": 0.5, "core_color": 0xffffff, "core_alpha": 0.5, "color": G3C.OUTLINE_COLOR, "alpha": 0.45, "prof": [[-0.5, 1.0], [0.5, 0.0]]},
	"supply": {"h": 6.0, "width": 0.14, "core": 0.4, "core_color": 0xffffff, "color": int(C.GAME_LIGHT_ITEM), "alpha": 0.75, "life": 4.0, "arm": 0.5, "max": 8, "prof": [[-0.5, 1.0], [0.5, 0.0]],
		"ring": {"r": 0.58, "grow": 2.4, "ms": 700.0, "alpha": 0.85, "lift": 0.04}},
}
# 스냅샷 roundEvent 로 도는 종류 (보급은 게임 이벤트로 한 번). 이 밖의 종류는 아무것도 안 그림
const RUNNING := ["wind", "ice", "lowgrav", "rain"]
