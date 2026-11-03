# 몸 자세 LOD (W12 2026-11-03 성능): 8명 판 스크립트 시간의 대부분이 몸 자세 (figureAnim·래그돌 잡기·묶음 뼈 맞추기) 라
# 화면 밖·먼 사람은 덜 자주 셈 (world/bodies.gd). 자리·방향·이름표는 매 프레임 — 팔다리 자세만 늦게 바뀜. 수치 WC.POSE_LOD, 테스트 tests/test_perf.gd
extends RefCounted

const WC := preload("res://world/world_config.gd")


# 자세를 다시 셀 최소 간격 (ms): 0 = 매 프레임
static func interval_ms(dist: float, on_screen: bool, always: bool, lod := WC.POSE_LOD) -> float:
	if always:
		return 0.0
	if not on_screen:
		return 1000.0 / float(lod.off_hz)
	if dist > float(lod.get("far2", INF)): # W15 둘째 단: 아주 멀면 30Hz
		return 1000.0 / float(lod.far2_hz)
	if dist > float(lod.near):
		return 1000.0 / float(lod.far_hz)
	return 0.0


# 이번 프레임에 셀 차례인가: 지난번 (last_ms, null = 처음) 부터 간격 − 반 프레임 지났으면 (60Hz 간격이면 60fps 에선 매 프레임, 120fps 에선 한 프레임 걸러)
static func due(now_ms: float, last_ms, interval: float, frame_ms: float) -> bool:
	if interval <= 0.0 or last_ms == null:
		return true
	return now_ms - float(last_ms) >= interval - frame_ms * 0.5


# 공 (가운데 c, 반지름 r) 이 시야 (Camera3D.get_frustum 의 면들, 법선이 바깥) 안에 걸치는가
static func in_view(planes: Array, c: Vector3, r: float) -> bool:
	for pl in planes:
		if (pl as Plane).distance_to(c) > r:
			return false
	return true
