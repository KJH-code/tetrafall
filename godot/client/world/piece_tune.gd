# C7 (겉모습 2 — 바닥 읽힘): 테트리미노 칸 모습의 고도 쪽 덧값. C.WORLD_THEMES.*.piece 는 JS 정답 테스트가 묶고 있어 그대로 두고 (world/theme_tune.gd 머리 주석),
# 여기 값은 칸 셰이더 (shaders/piece_common.gdshaderinc) 의 uniform 으로만 들어감 — G3.piece_material 이 넣음. 표에 없는 테마는 0 = 예전 화소 그대로.
#   faceLift   면 그림을 흰 쪽으로 (0..1): 면 색 = 조각 색 × mix(그림, 1, faceLift). 그림이 어두운 테마 (화산 흑요석, 가운데 선형 밝기 0.2) 는 면이 검정으로 꺼져 조각 색이 안 읽힘.
#              금 (crack) 은 그림 그대로 봄 → 빛나는 금은 남음. 갤러리 사진으로 0.25~0.4 안에서 맞춘 값
#   accentTint [accent0, accent1] 부품 색을 조각 색 쪽으로 (0..1, 선형). 버섯 받침 (accent1) 이 갓과 같은 계열로 — 흰 점 (accent0) 은 그대로
# 순수 계산만. 테스트 tests/test_shadow.gd test_c7_face_luma_floor·test_c7_piece_tune_keys
extends RefCounted

const KEYS := ["faceLift", "accentTint"]

const PIECE_TUNE := {
	"volcano": {"faceLift": 0.3},
	"mushroom": {"accentTint": [0.0, 0.35]},
}


static func face_lift(theme_id) -> float:
	return float(PIECE_TUNE.get(theme_id, {}).get("faceLift", 0.0))


static func accent_tint(theme_id) -> Vector2:
	var a: Array = PIECE_TUNE.get(theme_id, {}).get("accentTint", [0.0, 0.0])
	return Vector2(a[0], a[1])


# 면 가운데 밝기 (선형): 그림 밝기 m 에 faceLift 를 먹인 값 — 셰이더의 mix(tex, 1, face_lift) 와 같은 식
static func lifted(m: float, lift: float) -> float:
	return lerpf(m, 1.0, lift)
