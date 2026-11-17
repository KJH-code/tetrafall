# c10 관전 따라가기 카메라 (고도 판 전용 수치·순수 계산, 테스트 tests/test_feel.gd test_c10_spec_*).
# 예전: 대상 가슴 높이를 수평으로 봄 → 대상 둘레의 남의 몸·떨어지는 블록이 렌즈 앞을 덮고 바닥이 안 보였음 (저중력으로 뜬 대상은 하늘만).
# 지금: 3인칭 (C.TP_TILT) 처럼 조금 내려다보고 (tilt), 바라볼 점을 머리 위로 (look_up), 시선 위의 떨어지는 칸 앞으로도 당기고 (blocked),
# 그래도 렌즈 가까이 남는 떨어지는 칸은 옅게 그림 (cell_alpha — world/pieces_view.gd). C.SPECTATE_* (JS 에서 만든 값) 은 그대로 둠.
# 쓰는 곳: world/cam_rig.gd (관전 갈래·pull_in), world/pieces_view.gd (가까운 칸 옅게)
extends RefCounted

const SPEC := {
	"tilt": 0.45, # 마우스 pitch 에서 이만큼 더 내려다봄 (rad). 조작은 그대로 — pitch 0 이 이 각도
	"look_up": 1.4, # 바라볼 점 = 대상 발 + 이만큼 (m). C.SPECTATE_LOOK_UP 1.0 보다 높여 대상 발밑 바닥이 화면 가운데 아래에 옴
	"ease": 4.0, # 막힌 것이 사라져 다시 멀어지는 빠르기 (1/초, Cam.follow_dist — 당길 땐 바로)
	"fade": [1.2, 2.6], # 카메라에서 떨어지는 칸 가운데까지 거리 (m): [이 안은 fade_alpha, 이 밖은 그대로]
	"fade_alpha": 0.2, # 가장 옅을 때 알파 배율
}


# 궤도 pitch (Cam.orbit_eye 에 넣는 값): 3인칭 TP_TILT 와 같은 꼴. 바로 위 (−90도) 는 넘지 않음
static func orbit_pitch(pitch: float, tilt: float = float(SPEC.tilt)) -> float:
	return maxf(-PI / 2 + 0.05, pitch - tilt)


# 떨어지는 조각 (스냅샷 pieces) 의 칸 자리 모음: Vector3i → true
static func cells_of(pieces) -> Dictionary:
	var cells := {}
	if not pieces is Array:
		return cells
	for pc in pieces:
		for c in pc.cells:
			cells[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = true
	return cells


# 가림 검사: 격자 (solid: Callable(x, y, z) -> bool) 이거나 떨어지는 칸 (cells_of)
static func blocked(solid: Callable, cells: Dictionary) -> Callable:
	if cells.is_empty():
		return solid
	return func(x: float, y: float, z: float) -> bool:
		return solid.call(x, y, z) or cells.has(Vector3i(floori(x), floori(y), floori(z)))


# 카메라에서 dist (m) 떨어진 칸의 알파 배율: fade[0] 안 = fade_alpha, fade[1] 밖 = 1, 사이는 곧게
static func cell_alpha(dist: float, cfg: Dictionary = SPEC) -> float:
	var f: Array = cfg.fade
	var k := clampf((dist - float(f[0])) / (float(f[1]) - float(f[0])), 0.0, 1.0)
	return lerpf(float(cfg.fade_alpha), 1.0, k)
