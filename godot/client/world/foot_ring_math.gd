# 발밑 색 고리 (c7-u1) 순수 계산: 누구 고리를 어디에 얼마나 크게·진하게 그릴지. 그리기는 world/foot_rings.gd, 수치는 world_config.gd FOOT_RING, 테스트 tests/test_world.gd test_c7_foot_ring_*
extends RefCounted

const Co := preload("res://core/coords.gd")


# 발 아래 바닥 높이 (칸): 기둥 꼭대기 top 이 발 (feet_z) 보다 step 넘게 높으면 (머리 위 지붕 — 블록 밑에 서 있음) 발 아래로 내려가며 처음 만나는 단단한 칸 위.
# solid = Callable(z: int) -> bool (그 기둥의 z 칸이 단단한가). 없으면 바닥 0
static func ground_under(top: int, feet_z: float, solid: Callable, step: float) -> int:
	if float(top) <= feet_z + step:
		return top
	for z in range(int(floor(feet_z + step)) - 1, -1, -1):
		if solid.call(z):
			return z + 1
	return 0


# 고리를 놓을 표면 높이: 필드 밖이면 NAN (안 그림), 위험 액체가 바닥보다 높으면 그 표면
static func surface(col_top: float, in_field: bool, lava_on: bool, lava_z: float) -> float:
	if not in_field:
		return NAN
	return maxf(col_top, lava_z) if lava_on else col_top


# 공중이면 줄어듦: 표면에서 h 칸 위 → 반지름·알파 배율 (바닥이면 1, 하한 fade_min)
static func fade(h: float, cfg: Dictionary) -> float:
	return maxf(float(cfg.fade_min), 1.0 - float(cfg.fade) * maxf(0.0, h))


# 이 사람 고리를 그리나: 판 중 (cfg.phases) · 하늘 시점 아님 · 살아 있음 · 블록 마스터 아님 · 1인칭의 나 (mine and hide_me) 아님
static func wanted(p: Dictionary, phase: String, sky: bool, mine: bool, hide_me: bool, cfg: Dictionary) -> bool:
	if sky or not (cfg.phases as Array).has(phase):
		return false
	if not p.get("alive", false) or p.get("master", false):
		return false
	return not (mine and hide_me)


# 그릴 고리 목록. 한 줄 = [게임 x, y, z (표면 + lift), 반지름 (칸), Color (알파 포함)]. 3인칭의 나는 색 고리 뒤에 흰 안쪽 테 한 줄 더.
# shown: id → 화면 위치 (게임 좌표 Vector3, Bodies.shown) · colors: id → 0xRRGGBB (이름표와 같은 플레이어 색) · field: 판 크기 (칸)
# ground: Callable(cx: int, cy: int, feet_z: float) -> float 발 아래 바닥 높이
static func rings(st: Dictionary, my_id, hide_me: bool, sky: bool, shown: Dictionary, colors: Dictionary, field: Vector3i, ground: Callable, cfg: Dictionary) -> Array:
	var out := []
	var phase := str(st.get("phase", ""))
	var lava: Dictionary = st.get("lava", {}) if st.get("lava") is Dictionary else {}
	var lava_on: bool = lava.get("active", false)
	var lava_z := float(lava.get("z", 0.0)) if lava_on else 0.0
	for p in st.get("players", []):
		var id := int(p.id)
		var mine: bool = my_id != null and id == int(my_id)
		if not wanted(p, phase, sky, mine, hide_me, cfg) or not shown.has(id) or not colors.has(id):
			continue
		var pos: Vector3 = shown[id]
		var cx := int(floor(pos.x))
		var cy := int(floor(pos.y))
		var inside: bool = cx >= 0 and cy >= 0 and cx < field.x and cy < field.y
		var z := surface(float(ground.call(cx, cy, pos.z)) if inside else 0.0, inside, lava_on, lava_z)
		if is_nan(z):
			continue
		var k := fade(pos.z - z, cfg)
		var c: Color = Co.color(colors[id])
		out.append([pos.x, pos.y, z + float(cfg.lift), float(cfg.r) * k, Color(c.r, c.g, c.b, float(cfg.alpha) * k)])
		if mine:
			out.append([pos.x, pos.y, z + float(cfg.lift) + float(cfg.me_lift), float(cfg.r) * k * float(cfg.me_r), Color(1, 1, 1, float(cfg.me_alpha) * k)])
	return out

