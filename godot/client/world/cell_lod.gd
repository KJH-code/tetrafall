# 블록 칸 LOD (W39 2026-11-10, PC 최적화 5차): 테마 칸 모양은 168~648 삼각형인데 화면에서 작을 때도 같음 → 먼 칸·하늘 블록은 낮은 모양 (108 삼각형 둥근 상자, 화질 낮음이 쓰는 것) 으로.
# 순수 계산 (tests/test_w39.gd), 적용은 world/pieces_view.gd (떨어지는 칸) · world/grid_view.gd (쌓인 칸). 거리는 시야각 70° 기준으로 환산 (world/outline_far.gd norm_dist, 시야각을 넓히면 같은 거리가 작게 보임).
# 수치 WC.CELL_LOD, 끄기 --no-cell-lod (WC.cell_lod).
extends RefCounted

const WC := preload("res://world/world_config.gd")
const OutFar := preload("res://world/outline_far.gd")


# 이 칸을 낮은 모양으로 그릴까: 지금 낮은 모양 (was_far) 이면 far − hyst 안으로 들어와야 다시 높이고, 아니면 far + hyst 를 넘어야 낮춤
static func far_state(dist: float, fov_deg: float, was_far: bool, cfg: Dictionary = WC.CELL_LOD) -> bool:
	var nd := OutFar.norm_dist(dist, fov_deg)
	var far := WC.cell_lod_far if cfg == WC.CELL_LOD else float(cfg.far)
	var h := float(cfg.hyst)
	return nd > far - h if was_far else nd > far + h


# 낮은 모양을 쓸 만한가: 낮은 모양이 칸 모양보다 삼각형이 적을 때만 (수정 테마 56 < 108 은 그대로)
static func worth(full_tris: int, low_tris: int, cfg: Dictionary = WC.CELL_LOD) -> bool:
	return WC.cell_lod and full_tris >= low_tris * float(cfg.min_ratio)


# 테스트가 카메라 자리를 정해 줌 ({pos: Vector3, fov: float}), null 이면 평소대로 (노드가 속한 뷰포트의 카메라)
static var test_cam = null


# 지금 카메라 {pos, fov}, 없으면 {} (카메라 없음 = LOD 안 함)
static func camera_of(node: Node) -> Dictionary:
	if test_cam != null:
		return test_cam
	if not node.is_inside_tree():
		return {}
	var cam := node.get_viewport().get_camera_3d()
	return {} if cam == null else {"pos": cam.global_position, "fov": cam.fov}
