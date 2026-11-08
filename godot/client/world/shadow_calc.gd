# 해 그림자 비용 줄이기 계산 (W32): 순수 계산 (테스트 tests/test_shadow.gd). 적용은 chars/body.gd set_shadow_off (몸마다) + world/bodies.gd (매 프레임 판정) + world/world.gd (그림자 거리).
# 몸의 그림자를 끄는 경우 둘: ① 너무 멀다 (시야각 70° 기준 환산 거리 > WC.SHADOW.far — 그림자 지도에서 몇 픽셀 안 되는 크기) ② 몸도 그 몸 그림자가 떨어지는 자리도 시야 밖.
extends RefCounted

const WC := preload("res://world/world_config.gd")
const OutFar := preload("res://world/outline_far.gd")


# 그림자를 끌까: 지금 끈 상태 (was_off) 면 far − hyst 안으로 들어와야 다시 켬. 내 몸 (mine) 은 늘 켬
static func far_off(dist: float, fov_deg: float, was_off: bool, mine := false, cfg: Dictionary = WC.SHADOW) -> bool:
	if mine:
		return false
	var nd := OutFar.norm_dist(dist, fov_deg)
	var far := float(cfg.far)
	var h := float(cfg.hyst)
	return nd > far - h if was_off else nd > far + h


# 해가 있는 쪽 (단위 벡터, 월드 좌표 y 위) 으로 c 에서 올려다보는 해 → c 의 그림자가 바닥 (y = floor_y) 에 떨어지는 점. 해가 지평선 쪽이면 (to_sun.y 작음) 아주 멀리 → 제한
static func shadow_spot(c: Vector3, to_sun: Vector3, floor_y := 0.0) -> Vector3:
	var sy := maxf(to_sun.y, 0.2) # 해가 너무 낮으면 그림자 길이를 5배로 묶음 (판 밖으로 날아가는 점 방지)
	var t := (c.y - floor_y) / sy
	return c - to_sun * maxf(t, 0.0)


# 몸이 보이거나 그 그림자가 보이는가 (planes = Camera3D.get_frustum, r = 몸 공 반지름 + 여유). 둘 다 시야 밖이면 그림자를 꺼도 화면이 안 바뀜
static func visible_or_shadow(planes: Array, c: Vector3, to_sun: Vector3, r: float, floor_y := 0.0) -> bool:
	if planes.is_empty():
		return true
	if _in_view(planes, c, r):
		return true
	return _in_view(planes, shadow_spot(c, to_sun, floor_y), r)


static func _in_view(planes: Array, c: Vector3, r: float) -> bool:
	for pl in planes:
		if (pl as Plane).distance_to(c) > r:
			return false
	return true


# 그림자 거리: 카메라에서 판 가장 먼 모퉁이까지 (게임 좌표 cam = (x, y, 높이)) + pad 를 step 단위로 올림, 판 크기로 정한 값 (full) 보다는 안 커지고 reach_min 보다는 안 작아짐.
# 카메라가 판 가운데 가까이면 줄고, 구석에서 맞은편을 보면 full 그대로. 그림자 거리 안쪽만 그림자 지도에 들어가서 (거리 밖 물체는 그림자 패스에서 빠짐) 삼각형·그림자 지도 픽셀 밀도에 이득
static func reach(cam: Vector3, field_w: float, field_d: float, full: float, cfg: Dictionary = WC.SHADOW) -> float:
	var far_d := 0.0
	for cx in [0.0, field_w]:
		for cy in [0.0, field_d]:
			far_d = maxf(far_d, Vector2(cam.x - cx, cam.y - cy).length())
	var need: float = sqrt(far_d * far_d + cam.z * cam.z) + float(cfg.reach_pad) # 위에서 보는 카메라는 높이도 거리에 듦
	var step := float(cfg.reach_step)
	need = ceilf(need / step) * step
	return clampf(need, minf(float(cfg.reach_min), full), full)


# 프레임마다 부르는 판: 늘려야 하면 곧바로, 줄이는 건 한 단계 (step) 반 넘게 여유가 생길 때만 (카메라가 경계에서 떨 때 그림자 거리가 따라 떨면 그림자 지도 픽셀이 흔들림). cur < 0 = 처음
static func reach_next(cur: float, cam: Vector3, field_w: float, field_d: float, full: float, cfg: Dictionary = WC.SHADOW) -> float:
	var want := reach(cam, field_w, field_d, full, cfg)
	if cur < 0.0 or cur > full or want > cur:
		return want
	if want <= cur - float(cfg.reach_step) * 1.5:
		return want
	return cur
