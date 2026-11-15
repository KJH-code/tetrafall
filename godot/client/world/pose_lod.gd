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
	if dist > float(lod.get("far3", INF)): # W32 셋째 단: 더 멀면 15Hz (외곽선 껍질도 없는 거리)
		return 1000.0 / float(lod.far3_hz)
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


# 한 프레임에 한 번 정하는 '이번 프레임에 다시 그릴까' (W15: 거울·큰 캐릭터 SubViewport). st = {frame, last, draw} (호출하는 쪽이 들고 있음).
# 같은 프레임에 여러 번 불려도 처음 답 그대로. hz 간격 − 반 프레임 지났으면 그림 (due 와 같은 규칙)
static func frame_due(st: Dictionary, frame: int, now_ms: float, frame_ms: float, hz: float) -> bool:
	if st.get("frame", -1) == frame:
		return st.draw
	st.frame = frame
	st.draw = due(now_ms, st.get("last"), 1000.0 / hz if hz > 0.0 else 0.0, frame_ms)
	if st.draw:
		st.last = now_ms
	return st.draw
