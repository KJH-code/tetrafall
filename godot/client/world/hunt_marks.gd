# 사냥꾼 표식 알아보기 (shared/hunt-marks.js 그대로, 2026-10-31 재혁: 몇 개인지·붙은 순간·누가 달렸는지). 순수 계산 — 정답 자료 tests/fixtures/hunt_marks.json
# 화면에서 쓰는 곳: world/body_fx.gd (머리 위 칸·붙는 순간), G4 HUD (사냥꾼 히트마커·맞은 사람 가장자리·아래 판 칸)
extends RefCounted

const C := preload("res://core/config.gd")


# 보여 줄 표식: 내가 붙인 것이 있으면 그것 (mine), 없으면 가장 많은 것. 없으면 null
static func pick_mark(marks, my_id):
	var list: Array = marks if marks is Array else []
	for m in list:
		if my_id != null and m.get("by") != null and int(m.by) == int(my_id):
			var o: Dictionary = m.duplicate()
			o.mine = true
			return o
	var best = null
	for m in list:
		if best == null or m.n > best.n:
			best = m
	if best == null:
		return null
	var o: Dictionary = best.duplicate()
	o.mine = false
	return o


# 칸: 최대치만큼, 앞에서 n 개가 찬 칸. full = 최대치
static func mark_pips(n, mx: int = int(C.HUNTER_MARK_MAX)) -> Dictionary:
	var k := clampi(int(n), 0, mx)
	var pips := []
	for i in mx:
		pips.append(i < k)
	return {"pips": pips, "full": k >= mx, "n": k}


static func pip_text(n, mx: int = int(C.HUNTER_MARK_MAX)) -> String:
	var s := ""
	for on in mark_pips(n, mx).pips:
		s += "◆" if on else "◇"
	return s


# 붙는 순간 커졌다 줄어드는 배율 (age = 붙고 나서 ms)
static func pop_scale(age: float, U: Dictionary = C.HUNT_MARK_UI) -> float:
	if not (age >= 0) or age >= U.popMs:
		return 1.0
	var u: float = age / U.popMs
	return 1 + U.popScale * sin(PI * u) * (1 - u)


# 맞은 사람 화면 가장자리 빨강 진하기 (0~1)
static func edge_level(n: float, mx: float = C.HUNTER_MARK_MAX, pop_age: float = INF, blink := false, U: Dictionary = C.HUNT_MARK_UI) -> float:
	if not (n > 0) or blink:
		return 0.0
	var k: float = (minf(n, mx) - 1) / (mx - 1) if mx > 1 else 1.0
	var base: float = U.edge[0] + (U.edge[1] - U.edge[0]) * k
	var pulse := 0.0
	if pop_age >= 0 and pop_age < U.edgePulse[1]:
		pulse = U.edgePulse[0] * (1 - pop_age / U.edgePulse[1])
	return minf(1.0, base + pulse)


# 사라지기 직전 깜빡 (left = 남은 ms)
static func mark_blink(left: float, now: float) -> bool:
	return left < C.MARK_BLINK_MS and int(floor(now / C.MARK_BLINK_PERIOD_MS)) % 2 == 1
