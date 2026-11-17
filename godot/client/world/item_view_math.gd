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


# ---- c10-fix F3 나옴·사라짐 신호 (수치 IL.SIGNAL) ----

# 아이템 열쇠: 스냅샷 items 에는 id 가 없음 → (종류, 칸 x, 칸 y). 높이 z 는 기둥 꼭대기를 따라 바뀌니 뺌
static func item_key(it: Dictionary) -> String:
	return "%s:%d:%d" % [str(it.get("type", "")), int(it.get("x", 0)), int(it.get("y", 0))]


# 스냅샷 items → {열쇠: [칸 x, 칸 y, 높이 z, 종류]} (같은 열쇠는 처음 것)
static func seen_of(list) -> Dictionary:
	var out := {}
	if list is Array:
		for it in list:
			if it is Dictionary:
				var k := item_key(it)
				if not out.has(k):
					out[k] = [int(it.get("x", 0)), int(it.get("y", 0)), float(it.get("z", 0)), str(it.get("type", ""))]
	return out


# 스냅샷에서 신호 판단에 쓰는 값 [판 번호, 판 단계, 서버 시각 ms, 연습·튜토리얼인가]
static func meta_of(st: Dictionary) -> Array:
	var rd = st.get("round")
	return [int(rd.get("n", 0)) if rd is Dictionary else 0, str(st.get("phase", "")), float(st.get("time", 0.0)), st.get("practice") != null or str(st.get("mode", "")) == "practice"]


# 앞 스냅샷 (prev — 없으면 빈 배열) 과 이번 스냅샷 사이에 신호를 내도 되는가: 둘 다 판 중 (playing)·같은 판·연습·튜토리얼 아님·서버 시각이 앞으로 gap_ms 안.
# 첫 스냅샷·판이 바뀜 (판 끝·새 판)·재접속 (시각이 뜀)·튜토리얼 단계 깔기는 거짓 → 그때 나타나고 없어진 아이템은 조용히 받아들임
static func signal_ok(prev: Array, cur: Array, gap_ms: float) -> bool:
	if prev.size() < 4 or cur.size() < 4:
		return false
	if str(prev[1]) != "playing" or str(cur[1]) != "playing" or int(prev[0]) != int(cur[0]) or bool(prev[3]) or bool(cur[3]):
		return false
	var d := float(cur[2]) - float(prev[2])
	return d > 0.0 and d <= gap_ms


# 앞·이번 아이템 (seen_of) 을 견줌 → {"born": 새로 나온 줄들, "gone": 없어진 줄들} (한 줄 = [칸 x, 칸 y, 높이 z, 종류], 열쇠 순서).
# 새로 나온 것이 born_max 보다 많으면 born 은 비움 (보급 이벤트·단계 깔기 — IL.SIGNAL 주석)
static func item_diff(prev: Dictionary, cur: Dictionary, born_max: int) -> Dictionary:
	var born := []
	var gone := []
	var ks := cur.keys()
	ks.sort()
	for k in ks:
		if not prev.has(k):
			born.append(cur[k])
	ks = prev.keys()
	ks.sort()
	for k in ks:
		if not cur.has(k):
			gone.append(prev[k])
	if born.size() > born_max:
		born = []
	return {"born": born, "gone": gone}


# 나옴 신호: 나온 뒤 age_ms → [기둥 알파 배율, 고리 반지름, 고리 알파 배율]. 기둥은 hold 까지 그대로였다가 0 으로, 고리는 ring[0] → ring[1] (ease-out) 로 퍼지며 흐려짐. 끝났으면 다 0
static func born_at(age_ms: float, k: Dictionary) -> Array:
	var u := age_ms / float(k.ms)
	if u < 0.0 or u >= 1.0:
		return [0.0, 0.0, 0.0]
	var hold := float(k.hold)
	var e := 1.0 - (1.0 - u) * (1.0 - u)
	return [1.0 if u <= hold else 1.0 - (u - hold) / (1.0 - hold), lerpf(float(k.ring[0]), float(k.ring[1]), e), 1.0 - u]


# 사라짐 신호: 없어진 뒤 age_ms → [고리 반지름, 고리 알파 배율, 빛 줄 알파 배율] (ring[0] → ring[1] ease-out, 1 → 0, 빛 줄은 (1 − u)² 로 더 빨리). 끝났으면 0
static func gone_at(age_ms: float, k: Dictionary) -> Array:
	var u := age_ms / float(k.ms)
	if u < 0.0 or u >= 1.0:
		return [0.0, 0.0, 0.0]
	return [lerpf(float(k.ring[0]), float(k.ring[1]), 1.0 - (1.0 - u) * (1.0 - u)), 1.0 - u, (1.0 - u) * (1.0 - u)]


# 사라짐 고리 색: 아이템 빛 노랑에 그 종류 주색을 mix 만큼 (표에 없는 종류는 노랑 그대로)
static func gone_color(type: String, mix: float) -> Color:
	var y := Co.color(C.GAME_LIGHT_ITEM)
	return y.lerp(Co.color(IL.MAIN[type]), mix) if IL.MAIN.has(type) else y


# 신호 고리 한 줄 [x, y, z, 반지름, 색] (FR.xform 이 받는 모양): 칸 가운데, 칸 윗면 + lift
static func signal_ring_row(sig: Dictionary, r: float, col: Color, lift: float) -> Array:
	return [float(sig.x) + 0.5, float(sig.y) + 0.5, float(sig.z) + lift, r, col]

