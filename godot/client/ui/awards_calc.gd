# 판 끝 칭호 (고도 판 전용 — JS 에 없음): 그 판에 실려 온 이벤트 (kill·combo·counter·hit) 를 사람마다 세어
# 결과 판 승리 글 아래에 최대 MAX_LINES 줄 ("<칭호> · <이름> <수치 글>"). 순수 계산 — 화면은 results.gd, 테스트 tests/test_ui.gd
extends RefCounted

# 칭호 기준 수치 (클라 전용이라 생성 파일 core/config.gd 에 못 넣음 → 여기 표). 이 값 미만이면 안 뜸
const AWARD_MIN := {
	"kills": 2, # 해결사: 킬 수
	"fall": 2, # 밀어내기 왕: 낙사 킬
	"crush": 1, # 압사 장인: 압사 킬
	"combo": 5, # 콤보 장인: 가장 긴 연타 수
	"counter": 2, # 받아치기: 카운터히트 수
	"endure": 120, # 버티기: 끝까지 산 사람의 피해 %
	"sandbag": 1, # 샌드백: 맞은 hit 수 (가장 많이 맞은 사람 — 한 대도 안 맞았으면 없음)
}
const MAX_LINES := 3
const NONE := {"kills": 0, "fall": 0, "crush": 0, "self": 0, "deaths": 0, "combo": 0, "counter": 0, "hits": 0} # 이벤트가 하나도 없던 사람의 줄
# 우선순위 (앞이 먼저). 칭호마다 값이 가장 큰 사람 한 명, 동률이면 st.players 순서가 앞인 사람
const ORDER := ["closer", "crusher", "pusher", "combo", "counter", "perfect", "endure", "sandbag", "slip"]
const TITLES := {
	"closer": "해결사", "crusher": "압사 장인", "pusher": "밀어내기 왕", "combo": "콤보 장인", "counter": "받아치기",
	"perfect": "완벽한 승리", "endure": "버티기", "sandbag": "샌드백", "slip": "발이 미끄러짐",
}
# 수치 글 (%d = 그 칭호의 값)
const STAT_TEXT := {
	"closer": "%d킬", "crusher": "압사 %d킬", "pusher": "낙사 %d킬", "combo": "%d연타", "counter": "카운터 %d번",
	"perfect": "피해 %d%%", "endure": "피해 %d%%", "sandbag": "%d대 맞음", "slip": "첫 탈락이 자멸",
}


# 판 동안 이벤트로 사람마다 셈. 판 중에 들어온 (재접속) 사람은 그 전 이벤트를 못 받아 집계가 모자람 — ui_calc.gd KillTally 와 같은 한계
class Tally:
	var rows := {} # id (int) → {kills, fall, crush, self, deaths (죽은 횟수 — 자멸도 남에게 죽은 것도), combo, counter, hits}
	var first = null # 첫 탈락자 id (없으면 null)
	var first_self := false # 그 첫 탈락이 스스로 떨어진 것인지 (낙사 + 킬 없음 — '발이 미끄러짐'. 자동 블록 압사·용암은 아님)
	var masters := {} # 블록 마스터 판 중에 마스터 편이던 id (note_state) — 판이 끝나면 서버가 master 를 false 로 되돌려 결과 스냅샷만으론 모름
	var chains := {} # 맞는 사람 id → 지금 콤보 사슬 {n 지난 연타 수, by 친 사람 id (여럿이 섞였으면 null)}
	var round_key = null # 세고 있는 판 (at_round)
	var rev := 0 # 바뀔 때마다 +1 (화면이 다시 그릴지 봄)

	func reset() -> void:
		rows = {}
		first = null
		first_self = false
		masters = {}
		chains = {}
		rev += 1

	# 판이 바뀌었으면 (key 가 지난번과 다르면) 먼저 비움. 이벤트를 넣기 전에 부름
	func at_round(key) -> void:
		if key != round_key:
			round_key = key
			reset()

	func row(id: int) -> Dictionary:
		if not rows.has(id):
			rows[id] = NONE.duplicate()
		return rows[id]

	# JSON 숫자 (float) → int id. 숫자가 아니면 (null — 자멸의 killer 등) null
	static func _id(v):
		return int(v) if (v is float or v is int) else null

	# 판 중 스냅샷 (results.gd 가 스냅샷마다 부름): 블록 마스터 판이면 마스터 편 (마스터 + 죽어서 넘어간 사람) id 를 기억.
	# 판 끝 스냅샷에선 마스터도 master 가 false 라 (서버 EndRound) 판 중에 봐 둬야 '완벽한 승리' 에서 뺄 수 있음.
	# 판이 끝난 뒤에 들어온 사람은 못 봄 — 이벤트 집계와 같은 한계
	func note_state(st: Dictionary) -> void:
		if st.get("phase") != "playing" or st.get("mode") != "master":
			return
		for p in st.get("players", []):
			var id = _id(p.get("id"))
			if id != null and p.get("master", false) and not masters.has(id):
				masters[id] = true
				rev += 1

	# 서버 이벤트 하나: kill {killer(자멸이면 null), victim, cause} · combo {by, target, n} · counter {by} · hit {target, ok}. 다른 건 흘림
	func feed(e: Dictionary) -> void:
		match str(e.get("type", "")):
			"kill":
				var victim = _id(e.get("victim"))
				if victim == null:
					return
				var killer = _id(e.get("killer"))
				var own: bool = killer == null or killer == victim
				var cause := str(e.get("cause", ""))
				if first == null:
					first = victim
					first_self = own and cause == "fall" # 킬 없는 압사 (자동 블록)·용암은 '미끄러짐' 이 아님. self 집계는 KillTally·서버 ScoreDeath 와 같이 그대로
				row(victim).deaths += 1
				if own:
					row(victim).self += 1
				else:
					var k := row(killer)
					k.kills += 1
					if cause == "fall" or cause == "crush":
						k[cause] += 1
			"combo":
				# 서버의 n 은 맞는 쪽이 이어 맞은 수 (누가 쳤든 +1) — 마지막 타를 친 사람에게 통째로 주면 남의 타까지 그 사람 연타가 됨.
				# 그래서 맞는 사람마다 사슬을 따로 봄: n 이 지난 n + 1 이면 같은 사슬, 아니면 새 사슬. 사슬 안에서 친 사람이 하나일 때만 그 사람에게 n 을 줌
				# (다른 사람이 끼면 그 사슬은 그 뒤로 아무에게도 안 줌 — 거짓 '장인' 보다 덜 주는 쪽).
				# 한계: 사슬의 첫 타는 combo 이벤트가 없어 (n 은 2 부터 옴) 누가 쳤는지 모름 → 첫 타만 남이 쳤으면 1타 많게 셈
				var by = _id(e.get("by"))
				var target = _id(e.get("target"))
				if by == null or target == null:
					return
				var n := int(e.get("n", 0))
				var ch = chains.get(target)
				if ch != null and n == int(ch.n) + 1:
					ch.n = n
					if ch.by != by:
						ch.by = null
				else:
					ch = {"n": n, "by": by}
					chains[target] = ch
				if ch.by != null:
					var r := row(by)
					r.combo = maxi(int(r.combo), n)
			"counter":
				var by = _id(e.get("by"))
				if by == null:
					return
				row(by).counter += 1
			"hit":
				var target = _id(e.get("target"))
				if target == null or not bool(e.get("ok", false)):
					return
				row(target).hits += 1
			_:
				return
		rev += 1


static func _name(p: Dictionary) -> String:
	return str(p.get("nick", "")) if str(p.get("nick", "")) != "" else str(p.get("name", "?"))


# 이 칭호에서 그 사람의 값. 기준 미달·해당 없음이면 -1
static func _value(award: String, p: Dictionary, r: Dictionary, tally: Tally, winner: bool) -> int:
	match award:
		"closer":
			return int(r.kills) if int(r.kills) >= int(AWARD_MIN.kills) else -1
		"crusher":
			return int(r.crush) if int(r.crush) >= int(AWARD_MIN.crush) else -1
		"pusher":
			return int(r.fall) if int(r.fall) >= int(AWARD_MIN.fall) else -1
		"combo":
			return int(r.combo) if int(r.combo) >= int(AWARD_MIN.combo) else -1
		"counter":
			return int(r.counter) if int(r.counter) >= int(AWARD_MIN.counter) else -1
		"perfect": # 승자가 판 중 죽은 적 없고 (부활하면 피해가 0 으로 돌아오니 deaths 로 봄) 한 대도 안 맞고 피해 0.
			# 블록 마스터의 마스터 편은 필드에 없어 맞을 수 없으니 뺌 — 판 끝 스냅샷은 master 가 이미 false 라 판 중에 기억한 tally.masters 로
			var was_master: bool = p.get("master", false) or tally.masters.has(int(p.id))
			var clean: bool = winner and not was_master and int(r.deaths) == 0 and float(p.get("damage", 0)) == 0.0 and int(r.hits) == 0
			return 0 if clean else -1
		"endure":
			var dmg := int(p.get("damage", 0))
			return dmg if p.get("alive", false) and dmg >= int(AWARD_MIN.endure) else -1
		"sandbag":
			return int(r.hits) if int(r.hits) >= int(AWARD_MIN.sandbag) else -1
		"slip":
			return 1 if tally.first != null and tally.first_self and tally.first == int(p.id) else -1
	return -1


# 결과 판에 띄울 칭호 줄 (최대 MAX_LINES). 우선순위 순으로 칭호마다 값이 가장 큰 사람 한 명 — 동률이면 st.players 순서가 앞인 사람.
# 한 사람은 한 줄만: 값이 가장 큰 사람(들)이 이미 위 칭호를 받았으면 그 칭호는 건너뜀 (2등에게 넘기지 않음 — '왕'·'장인' 이 거짓이 안 되게)
static func pick(tally: Tally, st: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ps: Array = st.get("players", []).filter(func(p): return not p.get("spectator", false) and not p.get("dummy", false))
	var rnd: Dictionary = st.get("round", {})
	var ids: Array = rnd.get("winnerIds", [])
	if ids.is_empty() and rnd.get("winnerId") != null:
		ids = [rnd.winnerId]
	var winners := {}
	for id in ids:
		winners[int(id)] = true
	var wt = rnd.get("winnerTeam") # 팀전: 서버가 winnerIds 는 비우고 winnerTeam 만 실음 → 그 팀 사람이 승자
	if wt != null:
		for p in ps:
			if p.get("team") != null and str(p.get("team")) == str(wt):
				winners[int(p.id)] = true
	var used := {}
	for award in ORDER:
		if out.size() >= MAX_LINES:
			break
		var best := -1
		var vals: Array = []
		for p in ps:
			var id := int(p.id)
			var v := _value(award, p, tally.rows.get(id, NONE), tally, winners.has(id))
			vals.append(v)
			best = maxi(best, v)
		if best < 0:
			continue
		for i in ps.size():
			if vals[i] == best and not used.has(int(ps[i].id)):
				used[int(ps[i].id)] = true
				var stat: String = STAT_TEXT[award]
				out.append("%s · %s %s" % [TITLES[award], _name(ps[i]), (stat % best) if stat.contains("%d") else stat])
				break
	return out
