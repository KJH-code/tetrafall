# 든 아이템 순수 계산 (c11-u2, world/held_view.gd 가 씀 — 노드 없이 테스트로 고정): 누구 것을 그리나 · 어깨 옆 자리 · 크기·도는 각도 · 인스턴스 변환. 수치 world/item_look.gd HELD
extends RefCounted

const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const IL := preload("res://world/item_look.gd")


# 이 사람이 든 것을 그리나: 판 중 (발밑 고리와 같은 단계 WC.FOOT_RING.phases — c11-fix F3: 판 끝 승자 클로즈업에서 얼굴 옆에 폭탄이 뜨지 않게. 서버는 든 것을 판 시작·부활 때만 비움) ·
# 살아 있음 · 블록 마스터 아님 · 1인칭의 나 (mine and hide_me) 아님 · 든 것이 표 (HELD.kinds) 에 있음
static func wanted(p: Dictionary, mine: bool, hide_me: bool, phase: String) -> bool:
	if not (WC.FOOT_RING.phases as Array).has(phase):
		return false
	if not p.get("alive", false) or p.get("master", false) or (mine and hide_me):
		return false
	var h = p.get("held")
	return h != null and (IL.HELD.kinds as Array).has(str(h))


# c11-fix F7: 관전에서 시선을 막아 옅어진 몸인가 (thin = world/cam_rig.gd thin: id → {k 남길 비율, …}, 1·3인칭에서는 빔). 그 사람의 든 아이템은 안 그림 —
# 몸은 디더로 옅어지는데 든 모델은 묶음 재질 하나를 나눠 써서 불투명하게 남아 대상을 가렸음 (몸은 옅게 남아 그 사람이 있다는 것은 보임)
static func thinned(thin: Dictionary, id: int) -> bool:
	var t = thin.get(id)
	return t is Dictionary and float(t.get("k", 1.0)) < 1.0


# 이 캐릭터의 [옆 거리, 높이] (칸): 표 HELD.by_char 에 있으면 그 값, 없으면 (모르는 캐릭터·캐릭터 끔) HELD.side·HELD.h
static func place(ch: String) -> Array:
	var t: Dictionary = IL.HELD.by_char
	return t[ch] if t.has(ch) else [IL.HELD.side, IL.HELD.h]


# 어깨 옆 자리 (게임 좌표, 모델 가운데): pos = 발 자리, yaw = 보는 쪽 (0 = +x, 반시계), ch = 캐릭터 id (몸 폭·어깨 높이가 달라 자리도 다름). 오른쪽 = (sin yaw, −cos yaw)
static func slot(pos: Vector3, yaw: float, ch := "") -> Vector3:
	var pl := place(ch)
	var side := float(pl[0])
	var fwd := float(IL.HELD.fwd)
	return Vector3(pos.x + sin(yaw) * side + cos(yaw) * fwd, pos.y - cos(yaw) * side + sin(yaw) * fwd, pos.z + float(pl[1]))


# 그릴 줄 [[종류, 자리 (게임 좌표)], …] — 스냅샷 순서. shown: id → 화면 위치 (게임 좌표 Vector3, Bodies.shown — 보간 자리), phase = 판 단계 (스냅샷 phase), thin = 옅어진 몸 (thinned)
static func rows(players: Array, my_id, hide_me: bool, shown: Dictionary, phase: String, thin: Dictionary = {}) -> Array:
	var out := []
	for p in players:
		var id := int(p.id)
		if not shown.has(id) or thinned(thin, id) or not wanted(p, my_id != null and id == int(my_id), hide_me, phase):
			continue
		out.append([str(p.held), slot(shown[id], float(p.get("yaw", 0.0)), str(p.get("char", "")))])
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
