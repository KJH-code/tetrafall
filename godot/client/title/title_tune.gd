# C8 (겉모습 3 — 타이틀 로고 색): 타이틀 로고·시작 안내의 고도 쪽 수치. core/config.gd (TITLE_THEMES) 는 JS 에서 만든 생성 파일이라 못 고침.
# 로고: 테마마다 [빛 배율, 바탕 빛 배율, 흰 심] — 쓰는 곳 title_scene.gd (letter.gdshader glow·base_glow·core_white).
# 안내: 'Enter' 글자 색 (hint_color) — 쓰는 곳 title.gd. 순수 계산만 (노드 없음). 테스트 tests/test_title.gd test_c8_*
extends RefCounted

const C := preload("res://core/config.gd")

# [빛 배율, 바탕 빛 배율, 흰 심 0~1]. 빛 배율·바탕 빛 배율은 예전 title_scene.gd LETTER_THEME (화산만 0.5·0.35 — 흑요석 글자는 빛 배수가 크면 주황 한 덩이로 뜸).
# 흰 심: 칸 앞면 가운데를 흰색 쪽으로 (가장자리는 테마 빛 그대로) — 메뉴 빛 로고 (흰 글자 + 테마 빛) 와 같은 읽힘.
# 화산은 칸 속이 어두워 칸 테두리 빛만 보였음 (로고 상자 밝은 화소 3.6%) → 흰 심을 크게. 나머지는 이미 밝은 로고라 0 (예전 화소 그대로)
const LETTER := {
	"meadow": [1.0, 1.0, 0.0],
	"desert": [1.0, 1.0, 0.0],
	"crystal": [1.0, 1.0, 0.0],
	"volcano": [0.5, 0.35, 0.9],
	"skycastle": [1.0, 1.0, 0.0],
	"mushroom": [1.0, 1.0, 0.0],
	"castle": [1.0, 1.0, 0.0],
}
const LETTER_DEFAULT := [1.0, 1.0, 0.0]
# 흰 심 자리 (letter.gdshader core_edge): 칸 앞면 가운데에서 변까지 0~1 — 이 두 값 사이에서 심이 빠짐 (바깥은 테마 빛 테)
const CORE_EDGE := Vector2(0.84, 0.99)
# 흰 심이 스스로 내는 빛 (letter.gdshader core_lit, 흰색 × 이 값)
const CORE_LIT := 0.95

# 시작 안내 'Enter' 글자 밝기 (sRGB 밝기, theme_tune.luma 와 같은 식) 하한: 테마 빛 색이 이보다 어두우면 빛깔은 두고 흰 쪽으로 섞어 올림
# (흰 ' / 클릭하여 시작' 옆에서 주황·분홍 'Enter' 가 어두워 보였음 — 화산 0.57·수정 0.62·성 0.73·하늘성 0.76. 초원·사막 0.83 과 같은 세기로 맞춤:
# 사진에서 'Enter' 최대 밝기 ÷ 흰 글자 최대 밝기가 7테마 모두 0.8 위)
const HINT_LUMA_MIN := 0.84
# 안내 글 뒤 어두운 받침 겹 [외곽선 굵기, 진하기] — 빛 겹 (title.gd HINT_GLOW) 보다 뒤. 밝은 배경 (하늘성 구름·사막 모래) 위에서도 다른 테마만큼 읽히게
const HINT_BACK := [20, 0.5]


# 테마의 [빛 배율, 바탕 빛 배율, 흰 심] (표에 없으면 기본)
static func letter(theme) -> Array:
	return LETTER.get(theme, LETTER_DEFAULT)


# 지금 흰 심 세기 (0~1): 표 값 × 로고 빛이 켜진 정도 (glow = title_calc.light().glow — 쌓이는 동안 TITLE_GLOW[0], 다 쌓이면 [1] 이상)
static func core(theme, glow: float) -> float:
	return float(letter(theme)[2]) * clampf(glow / float(C.TITLE_GLOW[1]), 0.0, 1.0)


# 색의 sRGB 밝기 (0~1, 값 그대로)
static func luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# 'Enter' 글자 색: 테마 빛 색 (edge) 의 빛깔은 그대로, 밝기가 lo 아래면 흰 쪽으로 섞어 lo 까지 (흰색과 섞으면 빛깔 각이 안 바뀜)
static func hint_color(edge: Color, lo: float = HINT_LUMA_MIN) -> Color:
	var l := luma(edge)
	if l >= lo:
		return edge
	var k := (lo - l) / (1.0 - l)
	return Color(edge.r + (1.0 - edge.r) * k, edge.g + (1.0 - edge.g) * k, edge.b + (1.0 - edge.b) * k, edge.a)
