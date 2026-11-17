# 아이템 그리기 순수 계산 (c10-u2, world/items_view.gd·world/shots.gd 가 씀 — 노드 없이 테스트로 고정): 종류별 묶기 · 자리·출렁임 · 받침 고리 줄 · 화면 화소 크기 · 놓인 폭탄 깜빡임
extends RefCounted

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const IL := preload("res://world/item_look.gd")


# 아이템 종류 → 묶음 이름: 표 (IL.KINDS) 에 있으면 그 종류, 아니면 상자 묶음
static func kind_of(type) -> String:
	var t := str(type)
	return t if IL.KINDS.has(t) else str(IL.BOX)


# 묶음 순서 (늘 같음): 표 순서 + 끝에 상자
static func order() -> Array:
	var out: Array = IL.KINDS.duplicate()
	out.append(IL.BOX)
	return out


# 스냅샷 items → [[묶음 이름, 그 묶음의 items 번호들], …] — 묶음은 order() 순서로 빠짐없이 (0개면 빈 목록 = 숨김), 번호는 스냅샷 순서 그대로
static func groups(list: Array) -> Array:
	var names := order()
	var by := {}
	for n in names:
		by[n] = []
	for i in list.size():
		var mine: Array = by[kind_of((list[i] as Dictionary).get("type", ""))]
		mine.append(i)
	var out := []
	for n in names:
		out.append([n, by[n]])
	return out


# i 번째 아이템의 모델 가운데 (게임 좌표): 칸 가운데, 칸 윗면 + 높이 + 출렁임 (예전 items_view 식 그대로 — 번호마다 엇갈림)
static func item_pos(it: Dictionary, i: int, now_ms: float) -> Vector3:
	return Vector3(it.x + 0.5, it.y + 0.5, it.z + WC.ITEM_BOB[0] + sin(now_ms / WC.ITEM_BOB[2] + i) * WC.ITEM_BOB[1])


# 받침 고리 한 줄 [x, y, z, 반지름, 색] (world/foot_rings.gd xform 이 받는 모양): 칸 윗면 바로 위, 아이템 빛 노랑
static func ring_row(it: Dictionary) -> Array:
	return [it.x + 0.5, it.y + 0.5, it.z + float(IL.RING.lift), float(IL.RING.r), Color(Co.color(C.GAME_LIGHT_ITEM), float(IL.RING.alpha))]


# 길이 size (칸) 가 거리 dist (칸) 에서 화면에 차지하는 화소 (세로 시야각 fov_deg, 화면 높이 screen_h)
static func px(size: float, dist: float, fov_deg: float, screen_h: float) -> float:
	return size / (2.0 * maxf(1e-6, dist) * tan(deg_to_rad(fov_deg) * 0.5)) * screen_h


# 놓인 폭탄 깜빡임 주기 (ms): 남은 시간이 짧을수록 빨리 (예전 shots.gd 식 그대로)
static func bomb_period(left: float) -> float:
	return float(IL.BOMB_BLINK[0]) + minf(1.0, left / C.BOMB_FUSE_MS) * float(IL.BOMB_BLINK[1])


# 지금 켜진 반 주기인가
static func bomb_on(now_ms: float, left: float) -> bool:
	return int(floor(now_ms / bomb_period(left))) % 2 == 0
