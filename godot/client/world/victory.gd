# 판 끝 연출 순서 (shared/victory.js 그대로) + 클로즈업할 승자 고르기 (client/main.js 판 끝). 순수 계산, 정답 자료 tests/fixtures/victory.json
# 판 끝 → 'slow' (마지막 킬 슬로모션) → 'closeup' (카메라가 승자 앞) → 'results' (RESULTS_HERO_MS) → 'lobby'
extends RefCounted

const C := preload("res://core/config.gd")


# star = 클로즈업할 승자가 있음, slow_left = 판 끝 순간 슬로모션 남은 ms. 반환 값은 판 끝부터 ms
static func plan(star: bool, slow_left := 0.0, reduced := false) -> Dictionary:
	if not star:
		return {"closeupAt": 0.0, "resultsAt": 0.0, "endAt": C.RESULTS_HERO_MS}
	var closeup := maxf(0.0, slow_left if is_finite(slow_left) else 0.0)
	var results: float = closeup + (C.VICTORY_CLOSEUP_REDUCED_MS if reduced else C.VICTORY_CLOSEUP_MS)
	return {"closeupAt": closeup, "resultsAt": results, "endAt": results + C.RESULTS_HERO_MS}


# t = 판 끝부터 ms
static func stage(p, t) -> String:
	if p == null or t == null or not (t >= 0):
		return "lobby"
	if t < p.closeupAt:
		return "slow"
	if t < p.resultsAt:
		return "closeup"
	if t < p.endAt:
		return "results"
	return "lobby"


# 승자 (모두의 카메라가 이 사람에게): 팀전이면 이긴 팀에서 살아 있는 사람 (없으면 아무 팀원), 아니면 winnerIds 중 살아 있는 사람 (없으면 첫째). 없으면 null
static func star_of(st: Dictionary):
	var rd = st.get("round", {})
	if typeof(rd) != TYPE_DICTIONARY:
		return null
	var players: Array = st.get("players", [])
	var wt = rd.get("winnerTeam")
	if wt != null:
		for p in players:
			if p.get("team") == wt and p.alive:
				return int(p.id)
		for p in players:
			if p.get("team") == wt:
				return int(p.id)
		return null
	var ws := []
	for id in rd.get("winnerIds", []) if rd.get("winnerIds") != null else []:
		for p in players:
			if int(p.id) == int(id):
				ws.append(p)
	for p in ws:
		if p.alive:
			return int(p.id)
	return int(ws[0].id) if not ws.is_empty() else null
