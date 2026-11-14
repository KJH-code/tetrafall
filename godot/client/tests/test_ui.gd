# G4 화면 계산이 JS 와 같은 값인지 (tools/fixtures.mjs 가 뽑은 tests/fixtures/ui.json):
# 아래 판 배치·대기실 판 폭·이름표 · 킬 세기·위 띠·Tab 표·연속 킬·부활 초·HP · 화면 전환 · 큰 캐릭터·랜덤 뽑기 · 나가기
extends RefCounted

const U := preload("res://ui/ui_calc.gd")
const Awards := preload("res://ui/awards_calc.gd")

var errors: Array = []
var fx: Dictionary = {}


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui.json"))
	fx = d if d is Dictionary else {}


# JSON 값끼리 같은지 (숫자는 float 오차, 사전은 JS 쪽 키 기준 — JS 에서 undefined 인 키는 원래 없음)
static func same(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 1e-9
	if a is Dictionary and b is Dictionary:
		for k in b:
			if not a.has(k) or not same(a[k], b[k]):
				return false
		for k in a:
			if not b.has(k) and a[k] != null and a[k] != false:
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same(a[i], b[i]):
				return false
		return true
	return a == b


func expect(got, want, what: String) -> void:
	if not same(got, want):
		errors.append("%s: %s / JS %s" % [what, str(got), str(want)])


func test_fixture_loaded() -> void:
	check(fx.has("cards") and fx.has("reels"), "ui.json (node godot/client/tools/fixtures.mjs)")


func test_hud_layout() -> void:
	for c in fx.get("cards", []):
		expect(U.card_layout(int(c[0]), c[1]), c[2], "card_layout(%d, %d)" % [int(c[0]), int(c[1])])
	for d in fx.get("dock", []):
		expect(U.lobby_dock(d[0]), d[1], "lobby_dock(%d)" % int(d[0]))
	for l in fx.get("labels", []):
		expect(U.label_sizes(l[0]), l[1], "label_sizes(%s)" % str(l[0]))


# 대기실 판 자리 (고도 판 전용, lobby.gd _place): 오른쪽 끝·위에 붙고, 자리보다 크면 통째로 줄여 화면 안에
func test_lobby_place() -> void:
	var m: float = U.C.HUD_CARD_MARGIN
	# [화면, 내용 높이, 배율 1 인지] — 내용 폭은 lobby_dock 폭 그대로 (lobby.gd 가 그렇게 잡음)
	for row in [[Vector2(960, 540), 660.0, false], [Vector2(1280, 720), 660.0, false], [Vector2(1280, 720), 600.0, true], [Vector2(1920, 1080), 660.0, true], [Vector2(1920, 1080), 900.0, true], [Vector2(2560, 1440), 660.0, true]]:
		var view: Vector2 = row[0]
		var w: float = U.lobby_dock(view.x).w
		var content := Vector2(w, row[1])
		var at := U.lobby_place(view, content)
		var tag := "lobby_place(%s, %s) = %s" % [str(view), str(content), str(at)]
		check(is_equal_approx(at.y, U.LOBBY_TOP), "위에 붙음: " + tag) # 큰 화면에서도 세로 가운데로 안 내려옴
		check(is_equal_approx(at.x + content.x * at.scale, view.x - m), "오른쪽 끝에 붙음: " + tag)
		check(at.x >= 0.0 and at.y + content.y * at.scale <= view.y - m + 1e-6, "화면 안: " + tag)
		check((at.scale == 1.0) == row[2], "배율 1 %s: %s" % [str(row[2]), tag])
		check(at.scale > U.LOBBY_SCALE_MIN and at.scale <= 1.0, "배율 범위: " + tag)
		if not row[2]: # 줄일 땐 딱 자리만큼 (아래 여백까지)
			check(is_equal_approx(at.y + content.y * at.scale, view.y - m), "줄인 판 아래 끝 = 화면 아래 여백: " + tag)
	# 960×540 실제 값: 자리 높이 540 - 84 - 12 = 444 → 660 짜리 판은 444/660 배
	var small := U.lobby_place(Vector2(960, 540), Vector2(380, 660))
	check(is_equal_approx(small.scale, 444.0 / 660.0) and is_equal_approx(small.x, 960.0 - 12.0 - 380.0 * 444.0 / 660.0), "960×540: %s" % str(small))
	# 내용이 판 폭보다 넓어도 (긴 줄) 폭에 맞춰 줄여 오른쪽으로 안 넘침
	var wide := U.lobby_place(Vector2(1920, 1080), Vector2(940, 400))
	check(is_equal_approx(wide.scale, 0.5) and is_equal_approx(wide.x, 1920.0 - m - 470.0), "넓은 내용: %s" % str(wide))
	# 크기를 아직 모르면 (0) 줄이지 않음, 아주 큰 내용도 배율 아래 끝에서 멈춤
	check(U.lobby_place(Vector2(960, 540), Vector2(380, 0)).scale == 1.0, "높이 0")
	check(U.lobby_place(Vector2(960, 540), Vector2(380, 1.0e6)).scale == U.LOBBY_SCALE_MIN, "아주 큰 내용")


# 방 옵션 꼬리 (손님 대기실 줄·공개 방 목록): 켠 것만, 순서 고정.
# 서버가 보내는 모양: skyStairs 는 늘 true/false, hpMode 는 공개 목록에선 늘 true/false (Rooms.cs PublicList)·스냅샷에선 켰을 때만,
# roundEvents 는 둘 다 켰을 때만 → 키가 없든 false 든 끔
func test_room_opts() -> void:
	check(U.room_opts({}) == "", "옵션 없음: '%s'" % U.room_opts({}))
	check(U.room_opts({"skyStairs": false, "hpMode": false}) == "", "전부 끔")
	check(U.room_opts({"skyStairs": true}) == " · 하늘 계단", "하늘 계단")
	check(U.room_opts({"skyStairs": false, "hpMode": true}) == " · 체력전", "체력전")
	check(U.room_opts({"roundEvents": true, "mode": "kills"}) == " · 돌발 이벤트", "돌발 이벤트")
	check(U.room_opts({"roundEvents": true, "hpMode": true, "skyStairs": true}) == " · 하늘 계단 · 체력전 · 돌발 이벤트", "전부: '%s'" % U.room_opts({"roundEvents": true, "hpMode": true, "skyStairs": true}))
	# 생존·킬 점수전은 셋 다 먹음
	for mode in ["survival", "kills"]:
		var all := U.room_opts({"mode": mode, "roundEvents": true, "hpMode": true, "skyStairs": true})
		check(all == " · 하늘 계단 · 체력전 · 돌발 이벤트", "%s 전부: '%s'" % [mode, all])
	# 블록 마스터 방: 하늘 계단·돌발 이벤트는 켜져 있어도 판에서 안 돎 (서버 StartRound sky · RoundEventsRun) → 안 붙임. 체력전은 먹음
	var master := U.room_opts({"mode": "master", "roundEvents": true, "hpMode": true, "skyStairs": true})
	check(master == " · 체력전", "마스터 전부 켬: '%s'" % master)
	check(U.room_opts({"mode": "master", "roundEvents": true, "skyStairs": true}) == "", "마스터 하늘 계단 + 돌발 이벤트: '%s'" % U.room_opts({"mode": "master", "roundEvents": true, "skyStairs": true}))
	check(U.room_opts({"mode": "master", "roundEvents": true, "skyStairs": false, "hpMode": false}) == "", "마스터 돌발 이벤트만")
	# 표의 안 먹는 모드는 실제 모드 id
	for o in U.ROOM_OPTS:
		for m in o[2]:
			check(U.C.MODE_NAMES.has(m), "ROOM_OPTS %s: 모르는 모드 %s" % [o[0], m])


func test_kills_hud() -> void:
	var t := U.KillTally.new()
	for row in fx.get("tally", []):
		expect(t.add(row[0]), row[1], "KillTally.add(%s)" % str(row[0]))
	for row in fx.get("stats", []):
		expect(t.stats(row[0]), row[1], "stats(%s)" % str(row[0].id))
	var players := []
	for row in fx.get("stats", []):
		players.append(row[0])
	for row in fx.get("top", []):
		expect(U.top_bar(players, row[0]), row[1], "top_bar(me %s)" % str(row[0]))
	for row in fx.get("rows", []):
		expect(U.score_rows(players, t, row[0]), row[1], "score_rows(team %s)" % str(row[0]))
	for row in fx.get("streak", []):
		expect(U.streak_text(int(row[0])), row[1], "streak_text(%d)" % int(row[0]))
	for row in fx.get("progress", []):
		expect(U.progress(row[0], row[1]), row[2], "progress(%s, %s)" % [str(row[0]), str(row[1])])
	for row in fx.get("respawn", []):
		expect(U.respawn_secs(row[0]), row[1], "respawn_secs(%s)" % str(row[0]))
	for row in fx.get("hp", []):
		expect(U.hp_frac(row[0], row[1]), row[2], "hp_frac(%s, %s)" % [str(row[0]), str(row[1])])
	for row in fx.get("hpView", []):
		expect(U.hp_view(row[0], row[1]), row[2], "hp_view(%s, %s)" % [str(row[0]), str(row[1])])
	for row in fx.get("hpColor", []):
		expect(U.hp_rgb(row[0]), row[1], "hp_rgb(%s)" % str(row[0]))


func test_wipe() -> void:
	for s in fx.get("screens", []):
		expect(U.screen_of(s[0], s[1], s[2], s[3]), s[4], "screen_of%s" % str(s.slice(0, 4)))
	for k in fx.get("kinds", []):
		expect(U.wipe_kind(k[0], k[1]), k[2], "wipe_kind(%s, %s)" % [str(k[0]), str(k[1])])
	for p in fx.get("plans", []):
		expect(U.wipe_plan(p[0], p[1]), p[2], "wipe_plan(%s, %s)" % [str(p[0]), str(p[1])])


func test_char_select() -> void:
	for y in fx.get("yaw", []):
		expect(U.stage_yaw(y[0]), y[1], "stage_yaw(%s)" % str(y[0]))
	for t in fx.get("taunt", []):
		expect(U.taunt_at(t[0]), t[1], "taunt_at(%s)" % str(t[0]))
	for r in fx.get("reels", []):
		var used: Array = r[1]
		var k := [0]
		var rnd := func():
			var v = used[k[0]]
			k[0] += 1
			return v
		expect(U.random_reel(U.C.CHARACTERS, r[0], rnd), r[2], "random_reel(%s)" % str(r[0]))
		check(k[0] == used.size(), "random_reel 난수 %d 번 / JS %d 번" % [k[0], used.size()])


func test_leave() -> void:
	for l in fx.get("leave", []):
		expect(U.leave_needs_confirm(l[0], l[1], l[2]), l[3], "leave_needs_confirm%s" % str(l.slice(0, 3)))


# ---------- 판 끝 칭호 (고도 판 전용, ui/awards_calc.gd) ----------

# 서버 이벤트 모양 그대로 (JSON 이라 id 는 float, 자멸이면 killer null)
static func _kill(killer, victim, cause: String) -> Dictionary:
	return {"type": "kill", "killer": killer, "victim": victim, "cause": cause}


# 결과 스냅샷에서 칭호가 읽는 부분만: rows = [id, 피해 %, 살았나] (이름 P<id>), winner = 승자 id (없으면 null)
static func _award_state(rows: Array, winner = null) -> Dictionary:
	var ps: Array = []
	for r in rows:
		ps.append({"id": float(r[0]), "name": "P%d" % int(r[0]), "nick": "", "damage": float(r[1]), "alive": r[2]})
	return {"players": ps, "round": {"n": 1.0, "winnerId": winner, "winnerIds": [] if winner == null else [winner]}}


static func _award_feed(t, events: Array) -> void:
	for e in events:
		t.feed(e)


func test_awards_tally_kills_causes() -> void:
	var t := Awards.Tally.new()
	_award_feed(t, [
		_kill(null, 4.0, "fall"), # 첫 탈락 = 자멸
		_kill(1.0, 2.0, "fall"), _kill(1.0, 3.0, "crush"), _kill(1.0, 5.0, "fall"),
		_kill(6.0, 6.0, "lava"), # 자기 자신이 killer 여도 자멸
		_kill(7.0, 1.0, "hp"),
	])
	expect(t.rows[1], {"kills": 3, "fall": 2, "crush": 1, "self": 0, "combo": 0, "counter": 0, "hits": 0}, "1번 킬·낙사·압사")
	expect(t.rows[7], {"kills": 1, "fall": 0, "crush": 0, "self": 0, "combo": 0, "counter": 0, "hits": 0}, "7번 체력 킬 (낙사·압사 아님)")
	expect(t.rows[4].self, 1, "4번 자멸")
	expect(t.rows[6], {"kills": 0, "fall": 0, "crush": 0, "self": 1, "combo": 0, "counter": 0, "hits": 0}, "6번 자멸 (킬 아님)")
	check(not t.rows.has(2) and not t.rows.has(3) and not t.rows.has(5), "죽기만 한 사람은 줄 없음: %s" % str(t.rows.keys()))
	check(t.first == 4 and t.first_self, "첫 탈락 4번·자멸: %s %s" % [str(t.first), str(t.first_self)])
	# 콤보는 가장 긴 것, 카운터·맞은 hit 는 횟수 (ok 거짓은 안 셈). 모르는 이벤트는 흘림
	var rev: int = t.rev
	_award_feed(t, [
		{"type": "combo", "by": 2.0, "target": 3.0, "n": 3.0, "finish": false}, {"type": "combo", "by": 2.0, "target": 3.0, "n": 6.0, "finish": true},
		{"type": "combo", "by": 2.0, "target": 5.0, "n": 2.0, "finish": false},
		{"type": "counter", "by": 2.0, "target": 3.0}, {"type": "counter", "by": 2.0, "target": 5.0},
		{"type": "hit", "by": 2.0, "target": 3.0, "ok": true}, {"type": "hit", "by": 2.0, "target": 3.0, "ok": false}, {"type": "hit", "by": 5.0, "target": 3.0, "ok": true},
	])
	expect([t.rows[2].combo, t.rows[2].counter, t.rows[3].hits], [6, 2, 2], "콤보 최대·카운터·맞은 hit")
	check(t.rev == rev + 7, "센 이벤트마다 rev (ok 거짓 hit 는 안 셈): %d → %d" % [rev, t.rev])
	t.feed({"type": "land", "by": 2.0})
	t.feed({"type": "kill", "killer": 1.0, "victim": null, "cause": "fall"})
	check(t.rev == rev + 7 and t.rows[1].kills == 3, "모르는 이벤트·victim 없는 kill 은 흘림")


func test_awards_pick_max3_priority() -> void:
	# 후보 5개 (해결사 1번 · 콤보 장인 2번 · 받아치기 3번 · 버티기 4번 · 샌드백 5번) → 우선순위 위 3줄만
	var t := Awards.Tally.new()
	_award_feed(t, [
		_kill(1.0, 6.0, "hp"), _kill(1.0, 7.0, "hp"),
		{"type": "combo", "by": 2.0, "target": 5.0, "n": 7.0, "finish": true},
		{"type": "counter", "by": 3.0, "target": 5.0}, {"type": "counter", "by": 3.0, "target": 5.0},
		{"type": "hit", "by": 2.0, "target": 5.0, "ok": true}, {"type": "hit", "by": 2.0, "target": 5.0, "ok": true}, {"type": "hit", "by": 3.0, "target": 5.0, "ok": true},
	])
	var st := _award_state([[5, 80, false], [4, 150, true], [3, 30, false], [2, 40, false], [1, 20, true], [6, 0, false], [7, 0, false]], 1.0)
	expect(Awards.pick(t, st), ["해결사 · P1 2킬", "콤보 장인 · P2 7연타", "받아치기 · P3 카운터 2번"], "위 3줄")
	check(Awards.MAX_LINES == 3 and Awards.ORDER.size() == 9 and Awards.ORDER.all(func(a): return Awards.TITLES.has(a) and Awards.STAT_TEXT.has(a)), "칭호 표")
	# 위 칭호가 빠지면 아래 것이 차례로 올라옴: 압사 장인 > 밀어내기 왕 > … > 버티기 > 샌드백 > 발이 미끄러짐
	var t2 := Awards.Tally.new()
	_award_feed(t2, [
		_kill(null, 7.0, "fall"), _kill(3.0, 6.0, "fall"), _kill(3.0, 5.0, "fall"), _kill(2.0, 1.0, "crush"),
		{"type": "hit", "by": 3.0, "target": 5.0, "ok": true},
	])
	var st2 := _award_state([[7, 10, false], [5, 80, false], [4, 150, true], [3, 30, true], [2, 0, true], [1, 20, false], [6, 0, false]], 4.0)
	expect(Awards.pick(t2, st2), ["해결사 · P3 2킬", "압사 장인 · P2 압사 1킬", "버티기 · P4 피해 150%"], "밀어내기 왕은 이미 해결사인 3번 → 건너뛰고 버티기")
	st2.players = st2.players.filter(func(p): return int(p.id) != 3 and int(p.id) != 2) # 나간 사람은 후보가 아님
	expect(Awards.pick(t2, st2), ["버티기 · P4 피해 150%", "샌드백 · P5 1대 맞음", "발이 미끄러짐 · P7 첫 탈락이 자멸"], "아래 3개")
	# 완벽한 승리: 승자가 피해 0 · 맞은 hit 0 (한 대라도 맞았거나 승자가 아니거나 마스터면 아님)
	var t3 := Awards.Tally.new()
	var st3 := _award_state([[1, 0, true], [2, 60, false]], 1.0)
	expect(Awards.pick(t3, st3), ["완벽한 승리 · P1 피해 0%"], "완벽한 승리")
	st3.players[0].master = true
	expect(Awards.pick(t3, st3), [], "마스터는 완벽한 승리 아님")
	st3.players[0].master = false
	expect(Awards.pick(t3, _award_state([[1, 0, true], [2, 0, true]])), [], "승자 없음 (무승부)")
	t3.feed({"type": "hit", "by": 2.0, "target": 1.0, "ok": true})
	expect(Awards.pick(t3, st3), ["샌드백 · P1 1대 맞음"], "맞은 승자는 완벽한 승리 아님")


func test_awards_tie_and_one_per_player() -> void:
	# 2번·1번이 2킬 동률 → st.players 순서가 앞인 2번이 해결사. 낙사 킬도 동률 → 2번은 이미 받았으니 1번이 밀어내기 왕
	var t := Awards.Tally.new()
	_award_feed(t, [_kill(1.0, 5.0, "fall"), _kill(1.0, 6.0, "fall"), _kill(2.0, 7.0, "fall"), _kill(2.0, 8.0, "fall")])
	var rows := [[2, 0, true], [1, 0, true], [5, 0, false], [6, 0, false], [7, 0, false], [8, 0, false]]
	expect(Awards.pick(t, _award_state(rows)), ["해결사 · P2 2킬", "밀어내기 왕 · P1 낙사 2킬"], "동률 → 앞 사람, 다음 칭호는 남은 동률자")
	rows = [[1, 0, true], [2, 0, true], [5, 0, false], [6, 0, false], [7, 0, false], [8, 0, false]]
	expect(Awards.pick(t, _award_state(rows)), ["해결사 · P1 2킬", "밀어내기 왕 · P2 낙사 2킬"], "순서를 바꾸면 반대로")
	# 혼자 다 한 사람 (3킬 전부 낙사 · 콤보 6 · 카운터 2) 은 한 줄만 — 나머지 칭호는 2등에게 안 넘어감
	var t2 := Awards.Tally.new()
	_award_feed(t2, [
		_kill(1.0, 5.0, "fall"), _kill(1.0, 6.0, "fall"), _kill(1.0, 7.0, "fall"), _kill(2.0, 8.0, "fall"), _kill(2.0, 1.0, "fall"),
		{"type": "combo", "by": 1.0, "target": 2.0, "n": 6.0, "finish": true}, {"type": "combo", "by": 2.0, "target": 1.0, "n": 5.0, "finish": true},
		{"type": "counter", "by": 1.0, "target": 2.0}, {"type": "counter", "by": 1.0, "target": 2.0},
	])
	var got := Awards.pick(t2, _award_state(rows))
	expect(got, ["해결사 · P1 3킬"], "한 사람 한 줄, 2등 (낙사 2킬·콤보 5) 은 '왕'·'장인' 아님")
	var names := {}
	for line in got:
		names[line.split(" · ")[1].split(" ")[0]] = true
	check(names.size() == got.size(), "같은 사람이 두 줄: %s" % str(got))


func test_awards_below_threshold_none() -> void:
	# 킬 1 · 콤보 2 뿐 (기준: 킬 2 · 콤보 5) → 0줄
	var t := Awards.Tally.new()
	_award_feed(t, [_kill(1.0, 2.0, "fall"), {"type": "combo", "by": 1.0, "target": 2.0, "n": 2.0, "finish": false}])
	var st := _award_state([[1, 40, true], [2, 90, false]], 1.0)
	expect(Awards.pick(t, st), [], "기준 미달")
	expect(Awards.pick(Awards.Tally.new(), _award_state([[1, 40, true], [2, 90, false]], 1.0)), [], "이벤트 없음")
	# 기준 바로 아래·딱 기준 (표 AWARD_MIN 값 그대로)
	expect(Awards.AWARD_MIN, {"kills": 2, "fall": 2, "crush": 1, "combo": 5, "counter": 2, "endure": 120, "sandbag": 1}, "기준 표")
	st.players[0].damage = 119.0
	t.feed({"type": "combo", "by": 1.0, "target": 2.0, "n": 4.0, "finish": false})
	t.feed({"type": "counter", "by": 1.0, "target": 2.0})
	expect(Awards.pick(t, st), [], "콤보 4 · 카운터 1 · 피해 119")
	st.players[0].damage = 120.0
	expect(Awards.pick(t, st), ["버티기 · P1 피해 120%"], "피해 120 = 기준")
	st.players[0].alive = false
	expect(Awards.pick(t, st), [], "죽은 사람은 버티기 아님")
	t.feed({"type": "combo", "by": 1.0, "target": 2.0, "n": 5.0, "finish": true})
	expect(Awards.pick(t, st), ["콤보 장인 · P1 5연타"], "콤보 5 = 기준")
	# 첫 탈락이 남에게 죽은 것이면 '발이 미끄러짐' 없음 (뒤 자멸은 상관없음)
	var t2 := Awards.Tally.new()
	_award_feed(t2, [_kill(1.0, 2.0, "hp"), _kill(null, 3.0, "fall")])
	expect(Awards.pick(t2, _award_state([[1, 0, false], [2, 0, false], [3, 0, false]])), [], "첫 탈락이 자멸 아님")


func test_awards_reset_on_new_round() -> void:
	var t := Awards.Tally.new()
	t.at_round("ABCD|1")
	_award_feed(t, [_kill(null, 3.0, "fall"), _kill(1.0, 2.0, "fall"), _kill(1.0, 4.0, "fall"), {"type": "hit", "by": 1.0, "target": 2.0, "ok": true}])
	var st := _award_state([[1, 0, true], [2, 0, false], [3, 0, false], [4, 0, false]])
	t.at_round("ABCD|1") # 같은 판이면 그대로
	check(t.rows[1].kills == 2 and t.first == 3, "같은 판은 안 비움")
	expect(Awards.pick(t, st).size(), 3, "1판 칭호")
	var rev: int = t.rev
	t.at_round("ABCD|2") # 새 판의 첫 이벤트 앞에서 비움
	check(t.rows.is_empty() and t.first == null and not t.first_self, "새 판이면 비움: %s" % str(t.rows))
	check(t.rev > rev, "비우면 rev 가 바뀜 (화면이 다시 그림)")
	expect(Awards.pick(t, st), [], "비운 뒤 칭호 없음")
	t.feed(_kill(4.0, 1.0, "crush"))
	check(t.rows.size() == 1 and t.rows[4].crush == 1 and t.first == 1 and not t.first_self, "새 판 집계는 처음부터")
	t.at_round("WXYZ|2") # 다른 방의 같은 판 번호도 새 판
	check(t.rows.is_empty(), "방이 바뀌어도 비움")
