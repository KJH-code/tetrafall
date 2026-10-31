# 관전 궤도·3인칭 카메라 순수 계산 (shared/camera.js 그대로). 게임 좌표, 숫자는 float (64비트)
# 정답 자료: tools/fixtures.mjs → tests/fixtures/camera.json
extends RefCounted


# center {x,y,z} 를 바라보며 yaw·pitch 둘레를 돎 (pitch 음수 = 내려다봄 → 카메라는 위). dist 원하는 거리.
# solid_at: Callable(x, y, z) -> bool (없으면 가림 검사 안 함). 돌려줌 {x, y, z, dist} (막혔으면 dist 줄어듦)
static func orbit_eye(center: Dictionary, yaw: float, pitch: float, dist: float, solid_at = null, step := 0.1, margin := 0.3, min_dist := 0.6) -> Dictionary:
	var cp := cos(pitch)
	var dx := -cp * cos(yaw)
	var dy := -cp * sin(yaw)
	var dz := -sin(pitch)
	var d := dist
	if solid_at != null:
		var t := min_dist
		while t <= dist:
			if solid_at.call(center.x + dx * t, center.y + dy * t, center.z + dz * t):
				d = maxf(min_dist, t - margin)
				break
			t += step
	return {"x": center.x + dx * d, "y": center.y + dy * d, "z": center.z + dz * d, "dist": d}


# 3인칭 거리 따라가기: 가까워져야 하면 바로, 멀어질 땐 천천히. cur 이 null 이면 want
static func follow_dist(cur, want: float, dt: float, rate: float) -> float:
	if cur == null or want <= cur:
		return want
	return cur + (want - cur) * (1.0 - exp(-rate * dt))


# 전체 보기 거리 배율: 판이 기본(GRID_W)보다 크면 그만큼 멀리
static func overview_scale(side: float, base: float) -> float:
	return maxf(1.0, side / base)
