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


# 방 옵션 꼬리 (손님 대기실 줄·공개 방 목록): 켠 것만, 순서 고정. 서버는 hpMode·roundEvents 를 켰을 때만 보냄 (없으면 끔)
func test_room_opts() -> void:
	check(U.room_opts({}) == "", "옵션 없음: '%s'" % U.room_opts({}))
	check(U.room_opts({"skyStairs": false, "hpMode": false}) == "", "전부 끔")
	check(U.room_opts({"skyStairs": true}) == " · 하늘 계단", "하늘 계단")
	check(U.room_opts({"skyStairs": false, "hpMode": true}) == " · 체력전", "체력전")
	check(U.room_opts({"roundEvents": true, "mode": "kills"}) == " · 돌발 이벤트", "돌발 이벤트")
	check(U.room_opts({"roundEvents": true, "hpMode": true, "skyStairs": true}) == " · 하늘 계단 · 체력전 · 돌발 이벤트", "전부: '%s'" % U.room_opts({"roundEvents": true, "hpMode": true, "skyStairs": true}))


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
