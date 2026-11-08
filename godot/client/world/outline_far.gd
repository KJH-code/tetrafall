# 외곽선 거리 (W31 2026-11-08, PC 최적화 2차): 먼 몸은 외곽선 껍질 (next_pass, 몸을 한 번 더 그림) 을 뗌. 순수 계산 (tests/test_outline.gd), 적용은 chars/body.gd set_outline_far + world/bodies.gd.
# 거리는 시야각 70° 기준으로 맞춤 (시야각을 넓히면 같은 거리가 더 작게 보이므로 거리 × tan(fov/2) / tan(35°)). 수치 WC.OUTLINE_FAR (taper_from 8m ~ gone 16m, 몸 자세 LOD far2 10m 가 그 사이)
extends RefCounted

const WC := preload("res://world/world_config.gd")
const TAN35 := 0.7002075382097097


# 카메라 거리 (m) + 세로 시야각 (도) → 시야각 70° 로 환산한 거리
static func norm_dist(dist: float, fov_deg: float) -> float:
	return dist * tan(deg_to_rad(clampf(fov_deg, 10.0, 170.0)) * 0.5) / TAN35


# 외곽선 굵기 배율 (셰이더 outline.gdshader 의 mix·smoothstep 과 같은 식): taper_from 안은 1, gone 에서 min_k
static func thickness_k(nd: float, cfg: Dictionary = WC.OUTLINE_FAR) -> float:
	return lerpf(1.0, float(cfg.min_k), smoothstep(float(cfg.taper_from), float(cfg.gone), nd))


# 껍질을 뗄까: 지금 뗀 상태 (was_far) 면 gone − hyst 안으로 들어와야 다시 붙이고, 아니면 gone + hyst 를 넘어야 뗌. mine (내 몸) 은 늘 붙임
static func far_state(dist: float, fov_deg: float, was_far: bool, mine := false, cfg: Dictionary = WC.OUTLINE_FAR) -> bool:
	if mine:
		return false
	var nd := norm_dist(dist, fov_deg)
	var gone := float(cfg.gone)
	var h := float(cfg.hyst)
	return nd > gone - h if was_far else nd > gone + h
