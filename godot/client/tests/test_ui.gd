# G4 화면 계산이 JS 와 같은 값인지 (tools/fixtures.mjs 가 뽑은 tests/fixtures/ui.json):
# 아래 판 배치·대기실 판 폭·이름표 · 킬 세기·위 띠·Tab 표·연속 킬·부활 초·HP · 화면 전환 · 큰 캐릭터·랜덤 뽑기 · 나가기
extends RefCounted

const U := preload("res://ui/ui_calc.gd")

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
