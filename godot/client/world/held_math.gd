# 든 아이템 순수 계산 (c11-u2, world/held_view.gd 가 씀 — 노드 없이 테스트로 고정): 누구 것을 그리나 · 어깨 옆 자리 · 크기·도는 각도 · 인스턴스 변환. 수치 world/item_look.gd HELD
extends RefCounted

const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const IL := preload("res://world/item_look.gd")


# 이 사람이 든 것을 그리나: 살아 있음 · 블록 마스터 아님 · 1인칭의 나 (mine and hide_me) 아님 · 든 것이 표 (HELD.kinds) 에 있음
static func wanted(p: Dictionary, mine: bool, hide_me: bool) -> bool:
	if not p.get("alive", false) or p.get("master", false) or (mine and hide_me):
		return false
	var h = p.get("held")
	return h != null and (IL.HELD.kinds as Array).has(str(h))


# 어깨 옆 자리 (게임 좌표, 모델 가운데): pos = 발 자리, yaw = 보는 쪽 (0 = +x, 반시계). 오른쪽 = (sin yaw, −cos yaw)
static func slot(pos: Vector3, yaw: float) -> Vector3:
	var side := float(IL.HELD.side)
	var fwd := float(IL.HELD.fwd)
	return Vector3(pos.x + sin(yaw) * side + cos(yaw) * fwd, pos.y - cos(yaw) * side + sin(yaw) * fwd, pos.z + float(IL.HELD.h))


# 그릴 줄 [[종류, 자리 (게임 좌표)], …] — 스냅샷 순서. shown: id → 화면 위치 (게임 좌표 Vector3, Bodies.shown — 보간 자리)
static func rows(players: Array, my_id, hide_me: bool, shown: Dictionary) -> Array:
	var out := []
	for p in players:
		var id := int(p.id)
		if not shown.has(id) or not wanted(p, my_id != null and id == int(my_id), hide_me):
			continue
		out.append([str(p.held), slot(shown[id], float(p.get("yaw", 0.0)))])
	return out


# 모델 (긴 변 IL.SIZE) 을 줄이는 배율
static func shrink() -> float:
	return float(IL.HELD.size) / float(IL.SIZE)


# 지금 도는 각도 (rad): 바닥 아이템 빠르기 × HELD.spin, 시계는 서버 시각 (ms)
static func spin_at(now_ms: float) -> float:
	return fmod(now_ms / 1000.0 * float(WC.ITEM_BOB[3]) * float(IL.HELD.spin), TAU)


# 한 줄의 인스턴스 변환 (고도 좌표): 세로축으로 angle 돌리고 shrink 만큼 줄여 그 자리에
static func xform(row: Array, angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * shrink()), Co.gpos(row[1]))
