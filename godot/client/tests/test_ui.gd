# G4 화면 계산이 JS 와 같은 값인지 (tools/fixtures.mjs 가 뽑은 tests/fixtures/ui.json):
# 아래 판 배치·대기실 판 폭·이름표 · 킬 세기·위 띠·Tab 표·연속 킬·부활 초·HP · 화면 전환 · 큰 캐릭터·랜덤 뽑기 · 나가기
extends RefCounted

const U := preload("res://ui/ui_calc.gd")
const Awards := preload("res://ui/awards_calc.gd")
const Results := preload("res://ui/results.gd")
const Practice := preload("res://ui/practice.gd")
const TutorialUI := preload("res://ui/tutorial_ui.gd")

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


# 대기실 판 자리 (고도 판 전용, lobby.gd _place 가 쓰는 계산 — lobby_dock·lobby_scroll_h·lobby_y): 오른쪽에 붙고 세로 가운데 + LOBBY_DROP,
# 내용이 길면 판 높이를 화면 − LOBBY_VPAD 로 묶고 판 안에서 스크롤. 960×540·1280×720 에서 판이 화면 안이고 오른쪽 위 핑 칸 (ui.gd net_box) 과 안 겹침.
# (사이클 6 병합 리뷰 F4: 예전 '통째로 줄이기' 계산은 lobby.gd 가 안 부르는 죽은 코드라 그 테스트와 같이 지움)
func test_lobby_panel_fits() -> void:
	var m: float = U.C.HUD_CARD_MARGIN
	# [화면, 내용 높이 (스크롤 칸 안), 판 위아래 여백 합 (작은 창 6 + 6, 큰 창 10 + 10 — lobby.gd _small_sizes), 판 안에서 스크롤하는지]
	for row in [[Vector2(960, 540), 300.0, 12.0, false], [Vector2(960, 540), 436.0, 12.0, false], [Vector2(960, 540), 437.0, 12.0, true], [Vector2(960, 540), 660.0, 12.0, true],
			[Vector2(1280, 720), 300.0, 20.0, false], [Vector2(1280, 720), 600.0, 20.0, false], [Vector2(1280, 720), 660.0, 20.0, true], [Vector2(1280, 720), 2000.0, 20.0, true],
			[Vector2(1920, 1080), 660.0, 20.0, false]]:
		var view: Vector2 = row[0]
		var content_h: float = row[1]
		var pad: float = row[2]
		var dock := U.lobby_dock(view.x)
		var sh := U.lobby_scroll_h(view.y, content_h, pad)
		var h := sh + pad # 판 높이 = 스크롤 칸 + 여백
		var y := U.lobby_y(view.y, h)
		var rect := Rect2(dock.left, y, dock.w, h)
		var tag := "화면 %s 내용 %s → 판 %s" % [str(view), str(content_h), str(rect)]
		check((sh < content_h) == row[3], "스크롤 %s: %s" % [str(row[3]), tag])
		check(sh <= content_h and h <= view.y - U.LOBBY_VPAD + 1e-6, "판 높이는 화면 − LOBBY_VPAD 까지: " + tag)
		check(rect.position.x >= 0.0 and is_equal_approx(rect.end.x, view.x - m), "오른쪽 끝에 붙고 왼쪽도 화면 안: " + tag)
		check(rect.position.y >= U.LOBBY_TOP_MIN - 1e-6 and rect.end.y <= view.y - U.LOBBY_BOTTOM + 1e-6, "위·아래 화면 안: " + tag)
		for ping_w in [60.0, 84.0, 140.0]:
			check(not rect.intersects(U.net_ping_rect(view, ping_w)), "핑 칸 (폭 %d) 과 안 겹침: %s" % [int(ping_w), tag])
		if not row[3]: # 안 넘치면 세로 가운데 + LOBBY_DROP 그대로
			check(is_equal_approx(y, (view.y - h) / 2.0 + U.LOBBY_DROP), "가운데 + LOBBY_DROP: " + tag)
	# 실제 값: 960×540 에 긴 판 → 높이 540 − 92 = 448, 위 끝 (540 − 448) / 2 + 28 = 74, 아래 끝 522 (= 540 − 18)
	var sh540 := U.lobby_scroll_h(540.0, 660.0, 12.0)
	check(is_equal_approx(sh540, 436.0) and is_equal_approx(U.lobby_y(540.0, sh540 + 12.0), 74.0), "960×540 긴 판: 스크롤 칸 %s · 위 끝 %s" % [str(sh540), str(U.lobby_y(540.0, sh540 + 12.0))])
	check(is_equal_approx(U.lobby_y(720.0, 628.0), 74.0) and is_equal_approx(U.lobby_y(720.0, 400.0), 188.0), "1280×720 위 끝: %s · %s" % [str(U.lobby_y(720.0, 628.0)), str(U.lobby_y(720.0, 400.0))])
	# 화면보다 긴 판 (여백 계산이 틀려도) 은 위 끝 LOBBY_TOP_MIN 에서 멈춤 — 음수 자리로 안 올라감
	check(is_equal_approx(U.lobby_y(540.0, 600.0), U.LOBBY_TOP_MIN), "너무 긴 판은 위 끝에: %s" % str(U.lobby_y(540.0, 600.0)))


# 접속 상태 글 자리 (고도 판 전용, ui.gd status): 판 HUD 가 보이면 왼쪽, 판 시간 (hud.gd timer_label (14, 12) 글자 26 + 위아래 여백 3,
# 아래 끝 약 52) 아래 + 어두운 반투명 받침 (사이클 5 리뷰 F3: 예전 (16, 64) 은 튜토리얼 띠·블록 마스터 배너 (top_box y 62) 와 겹쳤음).
# 위 가운데 튜토리얼 진행 띠 (tutorial_ui.gd band_top y 58) 는 줄 수 따라 아래 끝이 달라져 (한 줄 약 97 · 두 줄 약 120 — 실제 글꼴로 잼) 고정 자리가 아니라
# 피할 칸으로 받음 (사이클 6 병합 리뷰 F1: 두 줄 띠가 (16, 108) 의 상태 글을 덮었음). 그 밖 (메뉴·대기실·결과) 은 예전 자리 그대로, 받침 투명
func test_status_pos() -> void:
	const TIMER_BOTTOM := 52.0
	const BAND_TOP := 58.0
	var game := U.status_pos(true)
	var other := U.status_pos(false)
	var box := U.status_box_pos(true)
	check(game == Vector2(16, 108), "판 중 자리: %s" % str(game))
	check(box == game - U.STATUS_PAD and box.y > TIMER_BOTTOM, "판 중 받침 위 끝이 판 시간 아래: %s" % str(box))
	# 튜토리얼 띠 (960 폭이면 x 약 45~915 — 화면 대부분): 한 줄이면 기본 자리 그대로, 두 줄·세 줄이면 띠 아래 끝 + 띄움으로 내려감
	var size := Vector2(300, 26) # '서버 응답 없음 — 다시 연결 중 (2/30)' 받침
	for bottom in [97.0, 120.0, 143.0]:
		var band := Rect2(45, BAND_TOP, 870, bottom - BAND_TOP)
		var at := U.status_box_pos(true, size, [band])
		check(not Rect2(at, size).intersects(band), "받침이 띠 (아래 끝 %d) 와 안 겹침: %s" % [int(bottom), str(at)])
		check(at.x == box.x and is_equal_approx(at.y, maxf(box.y, bottom + U.STATUS_GAP)), "띠 아래 끝 %d → 받침 위 끝 %s" % [int(bottom), str(at.y)])
	check(U.status_box_pos(true, size, [Rect2(45, BAND_TOP, 870, 97.0 - BAND_TOP)]) == box, "한 줄 띠는 기본 자리 그대로")
	check(box.x >= 0.0 and U.status_box_pos(false).x >= 0.0 and U.status_box_pos(false).y >= 0.0, "받침이 화면 안: %s / %s" % [str(box), str(U.status_box_pos(false))])
	check(other == Vector2(16, 12), "메뉴·대기실은 예전 자리: %s" % str(other))
	check(U.status_box_pos(false) == other - U.STATUS_PAD, "메뉴 받침도 글 자리에서 여백만큼 바깥 (글은 예전 자리)")
	check(game.x == other.x, "왼쪽 끝은 같음")
	check(U.status_back(true) == U.STATUS_BACK and U.STATUS_BACK.a >= 0.5 and U.STATUS_BACK.get_luminance() < 0.2, "판 중 받침은 어두운 반투명: %s" % str(U.STATUS_BACK))
	check(U.status_back(false).a == 0.0, "판 밖은 받침 없음")


# 판 중 받침이 가운데 위 알림 칸 (hud_extra top_box) 을 피함 (사이클 5 테스트 실패: 960 폭 블록 마스터 본인의 두 줄 배너 x 약 218~742,
# y 68~126 이 받침 (8~280, 104~130) 오른쪽 끝과 겹쳐 둘째 줄을 가림): 겹치면 그 칸 아래로 STATUS_GAP 띄워 내림, 안 겹치면 그대로
func test_status_avoids_top_box() -> void:
	var size := Vector2(272, 26)
	var base := U.status_box_pos(true)
	check(U.status_box_pos(true, size, []) == base, "알림 없으면 기본 자리: %s" % str(U.status_box_pos(true, size, [])))
	var banner := Rect2(218, 68, 524, 58) # 마스터 두 줄 배너 (960 폭)
	var p := U.status_box_pos(true, size, [banner])
	check(p.x == base.x and is_equal_approx(p.y, banner.end.y + U.STATUS_GAP), "두 줄 배너 아래로 띄움만큼: %s" % str(p))
	check(not Rect2(p, size).intersects(banner.grow(U.STATUS_GAP)), "내린 받침은 배너 (+띄움) 와 안 겹침")
	# 가운데 좁은 칸 (받침 오른쪽 끝 + 띄움보다 오른쪽) 은 가로로 안 겹쳐 그대로
	check(U.status_box_pos(true, size, [Rect2(base.x + size.x + U.STATUS_GAP + 1.0, 68, 360, 58)]) == base, "가로로 안 겹치면 그대로")
	# 평행사변형 기울기로 몇 px 삐져나오는 몫: 받침 오른쪽 끝 + 띄움 안이면 피함
	var edge := Rect2(base.x + size.x + U.STATUS_GAP - 1.0, 90, 300, 30)
	check(U.status_box_pos(true, size, [edge]).y > base.y, "띄움 안쪽으로 다가온 칸도 피함")
	# 여러 칸이 쌓임 (배너 + 경고 + 토스트): 내려간 뒤 또 겹치면 또 내림, 순서 상관없이 다 피함
	var danger := Rect2(150, 132, 660, 40)
	var toast := Rect2(200, 178, 560, 30)
	for avoid in [[banner, danger, toast], [toast, danger, banner]]:
		var q := U.status_box_pos(true, size, avoid)
		var clear := true
		for r in avoid:
			clear = clear and not Rect2(q, size).intersects((r as Rect2).grow(U.STATUS_GAP))
		check(clear and is_equal_approx(q.y, toast.end.y + U.STATUS_GAP), "쌓인 칸을 다 피함: %s" % str(q))
	# 판 밖 (메뉴·대기실·결과) 은 알림을 안 봄, 받침 크기 0 이면 안 내림
	check(U.status_box_pos(false, size, [Rect2(0, 0, 960, 540)]) == U.status_box_pos(false), "판 밖은 그대로")
	check(U.status_box_pos(true, Vector2.ZERO, [banner]) == base, "크기 0 이면 그대로")


# 연습 방 왼쪽 위 힌트 '연습 창 Tab'·연습 창 (practice.gd — 병합 뒤 자리는 둘 다 (14, 70), 아래 숫자는 계산만 보는 예전 자리 (16, 110) 그대로. 위 층 CanvasLayer 15) 도 피함 (사이클 5 수정 리뷰 1:
# 끊긴 동안 상태 글 (16, 108) 이 힌트와 겹쳐 뭉개지고, 연습 창을 열면 통째로 가려졌음). 아래로 내리다 아래 HUD (F·R 칸) 에 닿으면 막은 칸 오른쪽 옆
func test_status_avoids_practice() -> void:
	var size := Vector2(272, 26)
	var gap := U.STATUS_GAP
	var base := U.status_box_pos(true)
	var room720 := U.status_room(Vector2(1280, 720), [Rect2(511, 676, 258, 28)]) # F·R 칸 (1인칭 연습 방)
	var hint := Rect2(16, 110, 92, 18)
	var p := U.status_box_pos(true, size, [hint], room720)
	check(p.x == base.x and is_equal_approx(p.y, hint.end.y + gap), "힌트 아래로: %s" % str(p))
	check(not Rect2(p, size).intersects(hint.grow(gap)), "힌트 (+띄움) 와 안 겹침")
	# 연습 창 (1280×720): 창 아래에 자리가 있으면 창 아래
	var win := Rect2(16, 110, 300, 400)
	var q := U.status_box_pos(true, size, [win], room720)
	check(q.x == base.x and is_equal_approx(q.y, win.end.y + gap) and room720.encloses(Rect2(q, size)), "1280×720 연습 창 아래: %s" % str(q))
	# 960×540: 창 아래로 내리면 아래 HUD 에 닿음 → 창 오른쪽 옆, 처음 높이
	var room540 := U.status_room(Vector2(960, 540), [Rect2(351, 496, 258, 28)])
	var s := U.status_box_pos(true, size, [win], room540)
	check(is_equal_approx(s.x, win.end.x + gap) and s.y == base.y, "960×540 연습 창 오른쪽 옆: %s" % str(s))
	check(room540.encloses(Rect2(s, size)) and not Rect2(s, size).intersects(win.grow(gap)), "옆 자리는 화면 안·창과 안 겹침: %s" % str(s))
	# 옆 자리에 가운데 위 알림 칸이 있으면 그 열에서 다시 내림
	var toast := Rect2(300, 100, 360, 30)
	for avoid in [[win, toast], [toast, win]]:
		var t := U.status_box_pos(true, size, avoid, room540)
		var clear := room540.encloses(Rect2(t, size))
		for r in avoid:
			clear = clear and not Rect2(t, size).intersects((r as Rect2).grow(gap))
		check(clear and is_equal_approx(t.x, win.end.x + gap) and is_equal_approx(t.y, toast.end.y + gap), "옆 열의 알림 아래: %s" % str(t))
	# 어디에도 안 들어가면 (아주 작은 화면) 예전처럼 내린 자리, room 없음 (넓이 0) 도 예전 그대로
	check(U.status_box_pos(true, size, [win], Rect2(0, 0, 320, 200)) == U.status_box_pos(true, size, [win]), "자리가 없으면 내린 자리")
	check(U.status_box_pos(true, size, [win], Rect2()) == q, "room 없으면 제한 없이 내림")
	check(U.status_box_pos(true, size, [], room540) == base, "피할 칸 없으면 기본 자리")
	# 받침 칸: 아래 HUD 칸 중 가장 높은 위 끝 - 띄움까지, 없으면 화면 전체
	check(U.status_room(Vector2(1280, 720)) == Rect2(0, 0, 1280, 720), "아래 HUD 없으면 화면 전체")
	check(U.status_room(Vector2(1280, 720), [Rect2(0, 650, 10, 10), Rect2(500, 600, 10, 10)]) == Rect2(0, 0, 1280, 600 - gap), "가장 높은 아래 칸 위까지")


# practice.gd 연결: 'status_avoid' 무리 + avoid_rects() 가 보이는 힌트·연습 창 사각형 (ui.gd _avoid_rects 가 모음). 튜토리얼 방엔 힌트·창이 없어 빈 배열
func test_practice_avoid_rects() -> void:
	var keep_state = Store.state
	var keep_room = Store.room
	var keep_locked = PlayerInput.locked
	Store.state = {"phase": "playing", "practice": {"dummies": []}, "players": []}
	Store.room = {"code": "PRAC", "practice": true}
	var p = Practice.new()
	p._ready() # 테스트 러너 안에선 트리가 안 돌아 직접 (test_complete hud_extra 와 같음)
	check(p.is_in_group("status_avoid"), "status_avoid 무리")
	p._process(0.0)
	p.hint.reset_size()
	var size := Vector2(272, 26)
	var room := U.status_room(Vector2(1280, 720))
	var r: Array = p.avoid_rects()
	check(r.size() == 1 and (r[0] as Rect2).position == Vector2(14, 70) and (r[0] as Rect2).size.y > 0.0, "힌트만: %s" % str(r))
	if r.size() == 1:
		var at := U.status_box_pos(true, size, r, room)
		check(not Rect2(at, size).intersects(r[0]) and room.encloses(Rect2(at, size)), "받침이 힌트와 안 겹침: %s" % str(at))
	p.set_open(true)
	p._process(0.0)
	check(p.open and p.win.visible and not p.hint.visible, "창 열림 → 힌트 숨김")
	p.win.size = Vector2(300, 400) # 트리 밖이라 컨테이너가 크기를 못 잼 (러너가 트리 시작 전에 돎) — 실제 크기는 화면 사진으로
	r = p.avoid_rects()
	check(r.size() == 1 and r[0] == Rect2(14, 70, 300, 400), "연습 창만 (힌트 숨김): %s" % str(r))
	if r.size() == 1:
		var at := U.status_box_pos(true, size, r, room)
		check(not Rect2(at, size).intersects(r[0]) and room.encloses(Rect2(at, size)), "받침이 연습 창과 안 겹침: %s" % str(at))
	# 튜토리얼 방 (연습 방 위에서 돎): 연습 힌트·창이 안 뜸 → 피할 칸 없음 (튜토리얼 띠는 tutorial_ui.gd 가 따로 알림 — test_tutorial_avoid_rects)
	Store.state = {"phase": "playing", "practice": {"dummies": []}, "tutorial": {"step": 0}, "players": []}
	Store.room = {"code": "TUTO", "practice": true, "tutorial": true}
	p._process(0.0)
	check(p.avoid_rects().is_empty() and not p.open, "튜토리얼 방은 빈 배열: %s" % str(p.avoid_rects()))
	p.free()
	Store.state = keep_state
	Store.room = keep_room
	PlayerInput.locked = keep_locked


# tutorial_ui.gd 연결 (사이클 6 병합 리뷰 F1): 'status_avoid' 무리 + avoid_rects() 가 보이는 진행 띠 사각형 (ui.gd _avoid_rects 가 모음).
# 문구가 두 줄로 접힌 띠 (960×540 에서 아래 끝 약 120) 가 상태 글 자리 (16, 108) 까지 내려와도 받침이 그 아래 — 예전엔 띠 (층 20) 가 상태 글 (층 10) 을 덮었음
func test_tutorial_avoid_rects() -> void:
	var t = TutorialUI.new()
	t._ready() # 테스트 러너 안에선 트리가 안 돌아 직접
	check(t.is_in_group("status_avoid"), "status_avoid 무리")
	check(not t.band.visible and t.avoid_rects().is_empty(), "띠가 안 보이면 빈 배열: %s" % str(t.avoid_rects()))
	check(t.band.get_parent() == t.band_top and is_equal_approx(t.band_top.position.y, 58.0), "띠 자리 (위 58): %s" % str(t.band_top.position))
	t.band.visible = true
	var size := Vector2(300, 26)
	# [화면, 띠 (band_top 안 자리·크기 — 트리 밖이라 컨테이너가 못 재서 화면에서 잰 값을 넣음: 960 폭 두 줄 / 1280 폭 두 줄 / 1280 폭 한 줄), 받침이 내려가는지]
	for row in [[Vector2(960, 540), Rect2(45, 0, 870, 63), true], [Vector2(1280, 720), Rect2(170, 0, 940, 63), true], [Vector2(1280, 720), Rect2(260, 0, 760, 39), false]]:
		var view: Vector2 = row[0]
		t.band.position = (row[1] as Rect2).position
		t.band.size = (row[1] as Rect2).size
		var r: Array = t.avoid_rects()
		var want := Rect2((row[1] as Rect2).position + Vector2(0, 58), (row[1] as Rect2).size)
		check(r.size() == 1 and r[0] == want, "띠 사각형 = 화면 좌표 (자리 + 위 58): %s / %s" % [str(r), str(want)])
		if r.size() != 1:
			continue
		var room := U.status_room(view, [Rect2(view.x / 2.0 - 129.0, view.y - 44.0, 258, 28)]) # F·R 칸
		var at := U.status_box_pos(true, size, r, room)
		var tag := "%s 띠 %s → 받침 %s" % [str(view), str(r[0]), str(at)]
		check(not Rect2(at, size).intersects(r[0]) and room.encloses(Rect2(at, size)), "받침이 띠와 안 겹치고 화면 안: " + tag)
		check((at.y > U.status_box_pos(true).y) == row[2], "두 줄 띠만 받침을 내림: " + tag)
		if row[2]:
			check(is_equal_approx(at.y, (r[0] as Rect2).end.y + U.STATUS_GAP) and at.x == U.status_box_pos(true).x, "띠 아래 끝 + 띄움, 왼쪽 그대로: " + tag)
	t.band.visible = false
	check(t.avoid_rects().is_empty(), "띠를 숨기면 다시 빈 배열")
	t.free()


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
	expect(t.rows[1], {"kills": 3, "fall": 2, "crush": 1, "self": 0, "deaths": 1, "combo": 0, "counter": 0, "hits": 0}, "1번 킬·낙사·압사 (+ 7번에게 죽음)")
	expect(t.rows[7], {"kills": 1, "fall": 0, "crush": 0, "self": 0, "deaths": 0, "combo": 0, "counter": 0, "hits": 0}, "7번 체력 킬 (낙사·압사 아님)")
	expect([t.rows[4].self, t.rows[4].deaths], [1, 1], "4번 자멸 (죽은 횟수에도)")
	expect(t.rows[6], {"kills": 0, "fall": 0, "crush": 0, "self": 1, "deaths": 1, "combo": 0, "counter": 0, "hits": 0}, "6번 자멸 (킬 아님)")
	for id in [2, 3, 5]: # 남에게 죽기만 한 사람: 죽은 횟수만
		expect(t.rows[id], {"kills": 0, "fall": 0, "crush": 0, "self": 0, "deaths": 1, "combo": 0, "counter": 0, "hits": 0}, "%d번 죽기만 함" % id)
	expect(Awards.NONE.deaths, 0, "이벤트 없는 사람의 죽은 횟수")
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
	check(t.rows.size() == 2 and t.rows[4].crush == 1 and t.rows[1].deaths == 1 and t.first == 1 and not t.first_self, "새 판 집계는 처음부터: %s" % str(t.rows))
	t.at_round("WXYZ|2") # 다른 방의 같은 판 번호도 새 판
	check(t.rows.is_empty(), "방이 바뀌어도 비움")


# ---------- 사이클 2 리뷰 지적 (F1~F6) ----------

# 결과 스냅샷 한 사람 (서버 WritePlayer 에서 칭호·결과 판이 읽는 것): 판 끝엔 마스터도 master 가 false
static func _award_player(id: int, opts := {}) -> Dictionary:
	var p := {"id": float(id), "slot": float(id - 1), "color": float(id - 1), "name": "P%d" % id, "nick": "", "spectator": false, "dummy": false, "team": null,
		"damage": 0.0, "alive": true, "wins": 0.0, "cause": null, "master": false, "zombie": false, "char": "tank"}
	p.merge(opts, true)
	return p


# F1: 블록 마스터 판에서 마스터가 이겨도 '완벽한 승리' 아님. 판 끝 스냅샷은 마스터도 master:false (서버 EndRound) → 판 중 스냅샷에서 기억한 id 로 뺌
func test_awards_master_winner_not_perfect() -> void:
	var playing := {"phase": "playing", "mode": "master", "round": {"n": 1.0},
		"players": [_award_player(1, {"master": true}), _award_player(2), _award_player(3)]}
	# 실제 모양의 판 끝: 마스터 (1번) 가 이김 — master false · 피해 0 · alive true · winnerIds = [마스터]. 생존자 둘은 용암 (킬 없음)
	var over := {"phase": "over", "mode": "master", "round": {"n": 1.0, "winnerId": 1.0, "winnerTeam": null, "winnerIds": [1.0]},
		"players": [_award_player(1), _award_player(2, {"alive": false, "cause": "lava"}), _award_player(3, {"alive": false, "cause": "lava"})]}
	var deaths := [_kill(null, 2.0, "lava"), _kill(null, 3.0, "lava")]
	var t := Awards.Tally.new()
	t.at_round("ABCD|1")
	var rev: int = t.rev
	t.note_state(playing)
	check(t.masters.has(1) and t.masters.size() == 1 and t.rev == rev + 1, "판 중 마스터 기억: %s" % str(t.masters))
	t.note_state(playing)
	check(t.rev == rev + 1, "이미 아는 마스터는 rev 그대로")
	_award_feed(t, deaths)
	t.note_state(over) # 판 끝 스냅샷 (master false) 이 와도 기억은 그대로
	check(t.masters.has(1), "판 끝 스냅샷이 기억을 지우지 않음")
	expect(Awards.pick(t, over), [], "마스터 승리: 완벽한 승리 없음")
	# 대조: 판 중 스냅샷을 못 봤으면 (기억 없음) 예전처럼 붙음 — 위 결과가 기억 덕분임을 보임
	var t0 := Awards.Tally.new()
	_award_feed(t0, deaths)
	expect(Awards.pick(t0, over), ["완벽한 승리 · P1 피해 0%"], "기억이 없으면 붙음 (판 끝 뒤에 들어온 사람의 한계)")
	# 죽어서 마스터 편으로 넘어간 사람 (zombie) 도 master:true → 같이 담김 (승자가 아니라 상관없음). 생존자가 이기면 그 생존자는 완벽한 승리
	var t2 := Awards.Tally.new()
	t2.note_state(playing)
	t2.feed(_kill(null, 2.0, "lava"))
	t2.note_state({"phase": "playing", "mode": "master", "players": [_award_player(1, {"master": true}), _award_player(2, {"master": true, "zombie": true}), _award_player(3)]})
	check(t2.masters.has(1) and t2.masters.has(2) and not t2.masters.has(3), "마스터 편: %s" % str(t2.masters))
	var survived := {"round": {"n": 1.0, "winnerId": 3.0, "winnerIds": [3.0]}, "players": [_award_player(1), _award_player(2, {"alive": false}), _award_player(3)]}
	expect(Awards.pick(t2, survived), ["완벽한 승리 · P3 피해 0%"], "혼자 버틴 생존자")
	# 블록 마스터 판 중이 아니면 안 담음 (다른 모드·대기실·카운트다운·판 끝)
	var t3 := Awards.Tally.new()
	for st in [{"phase": "playing", "mode": "survival"}, {"phase": "lobby", "mode": "master"}, {"phase": "countdown", "mode": "master"}, {"phase": "over", "mode": "master"}]:
		st["players"] = [_award_player(1, {"master": true})]
		t3.note_state(st)
	check(t3.masters.is_empty(), "판 중 블록 마스터가 아니면 안 담음: %s" % str(t3.masters))
	# 새 판이면 비움
	t.at_round("ABCD|2")
	check(t.masters.is_empty(), "새 판이면 마스터 기억도 비움")


# F1 화면 쪽 (results.gd): 스냅샷 신호를 받아 마스터를 기억하고, 판이 바뀌면 비움.
# 러너가 SceneTree._initialize 안에서 돌아 노드가 트리에 못 들어감 (뿌리가 아직 트리 밖) → _ready 를 직접 부르고,
# 화면 크기를 읽는 refresh (_place 의 get_viewport_rect) 는 못 부름 — 줄 고르기는 그 판의 tally 로 Awards.pick 을 직접
func test_results_remembers_master_from_snapshots() -> void:
	var keep_state = Store.state
	var keep_room = Store.room
	Store.room = {"code": "ABCD"}
	var r = Results.new()
	r._ready()
	check(Store.state_changed.is_connected(r._on_state) and Store.game_event.is_connected(r._on_event), "results 가 스냅샷·이벤트 신호를 받음")
	var playing := {"phase": "playing", "mode": "master", "round": {"n": 3.0},
		"players": [_award_player(1, {"master": true}), _award_player(2), _award_player(3)]}
	var over := {"phase": "over", "mode": "master", "round": {"n": 3.0, "winnerId": 1.0, "winnerTeam": null, "winnerIds": [1.0]},
		"players": [_award_player(1), _award_player(2, {"alive": false, "cause": "lava"}), _award_player(3, {"alive": false, "cause": "lava"})]}
	r._on_state(playing, {})
	check(r.tally.masters.has(1), "판 중 스냅샷 → 마스터 기억: %s" % str(r.tally.masters))
	Store.state = playing
	r._on_event(_kill(null, 2.0, "lava"))
	r._on_event(_kill(null, 3.0, "lava"))
	Store.state = over
	r._on_state(over, playing)
	check(r.tally.masters.has(1) and r.tally.rows.size() == 2, "같은 판의 이벤트·판 끝 스냅샷은 안 비움: %s %s" % [str(r.tally.masters), str(r.tally.rows)])
	expect(Awards.pick(r.tally, over), [], "마스터 승리 결과 판에 칭호 줄 없음")
	var next: Dictionary = playing.duplicate(true)
	next.round.n = 4.0
	next.phase = "countdown"
	r._on_state(next, over)
	check(r.tally.masters.is_empty() and r.tally.rows.is_empty(), "다음 판 스냅샷이 오면 비움")
	r.free()
	Store.state = keep_state
	Store.room = keep_room


# F2: 판 중에 죽었던 (부활하면 피해가 0 으로 돌아옴) 승자는 완벽한 승리 아님 — 죽은 횟수로 봄
func test_awards_perfect_needs_no_deaths() -> void:
	var st := _award_state([[1, 0, true], [2, 60, true]], 1.0)
	# 자멸 1번 (킬 점수전: 용암에 빠졌다 부활 — 피해 0·alive)
	var t := Awards.Tally.new()
	t.feed(_kill(null, 1.0, "lava"))
	expect([t.rows[1].self, t.rows[1].deaths, t.rows[1].hits], [1, 1, 0], "자멸: self·deaths")
	expect(Awards.pick(t, st), [], "자멸한 승자")
	# 조종 블록 압사 1번: killer 는 붙지만 hit 이벤트는 없음 (서버 Kill 은 death·kill 만) → hits 0·self 0 이어도 아님
	var t2 := Awards.Tally.new()
	t2.feed(_kill(2.0, 1.0, "crush"))
	expect([t2.rows[1].self, t2.rows[1].deaths, t2.rows[1].hits], [0, 1, 0], "압사당함: hits 0·self 0·deaths 1")
	expect(Awards.pick(t2, st), ["압사 장인 · P2 압사 1킬"], "조종 블록에 깔렸던 승자")
	# 깨끗한 승자 (남만 죽음)
	var t3 := Awards.Tally.new()
	t3.feed(_kill(null, 2.0, "lava"))
	expect(Awards.pick(t3, st), ["완벽한 승리 · P1 피해 0%"], "깨끗한 승자")


# F3: 팀전은 winnerIds 가 비고 winnerTeam 만 옴 → 그 팀 사람이 승자
func test_awards_perfect_team_win() -> void:
	var ps := [_award_player(3, {"team": "blue"}), _award_player(2, {"team": "red"}), _award_player(1, {"team": "red"}), _award_player(4, {"team": "blue", "alive": false})]
	var st := {"players": ps, "round": {"n": 1.0, "winnerId": null, "winnerTeam": "red", "winnerIds": []}}
	var t := Awards.Tally.new()
	_award_feed(t, [_kill(null, 2.0, "lava"), _kill(null, 4.0, "lava")]) # 빨강 2번은 판 중에 죽었음
	expect(Awards.pick(t, st), ["완벽한 승리 · P1 피해 0%"], "빨강 승리: 깨끗한 빨강 1번만 (죽었던 빨강 2번·깨끗한 파랑 3번은 아님)")
	st.round.winnerTeam = "blue"
	expect(Awards.pick(t, st), ["완벽한 승리 · P3 피해 0%"], "파랑 승리면 파랑 3번")
	st.round.winnerTeam = null
	expect(Awards.pick(t, st), [], "승리 팀 없음 (무승부)")
	# 개인전 (team null) 은 winnerTeam 이 없으니 예전 그대로
	for p in ps:
		p.team = null
	st.round.winnerIds = [3.0]
	expect(Awards.pick(t, st), ["완벽한 승리 · P3 피해 0%"], "개인전 대조군")


# F4: '발이 미끄러짐' 은 첫 탈락이 스스로 떨어진 것 (낙사 + 킬 없음) 일 때만 — 자동 블록 압사·용암 (killer null) 은 아님
func test_awards_slip_only_fall() -> void:
	var st := _award_state([[1, 30, true], [2, 30, false]])
	for cause in ["crush", "lava", "hp"]:
		var t := Awards.Tally.new()
		t.feed(_kill(null, 2.0, cause))
		check(t.first == 2 and not t.first_self, "첫 탈락 %s (킬 없음) 는 미끄러짐 아님" % cause)
		expect(t.rows[2].self, 1, "자멸 집계는 그대로 (%s)" % cause) # KillTally·서버 ScoreDeath 와 같은 정의
		expect(Awards.pick(t, st), [], "첫 탈락 %s·킬 없음 → 칭호 없음" % cause)
	var t2 := Awards.Tally.new()
	t2.feed(_kill(null, 2.0, "fall"))
	check(t2.first_self, "낙사 + 킬 없음 = 미끄러짐")
	expect(Awards.pick(t2, st), ["발이 미끄러짐 · P2 첫 탈락이 자멸"], "첫 탈락 낙사·킬 없음")
	# 첫 탈락이 압사 (킬 없음) 면 뒤의 자멸 낙사는 상관없음
	var t3 := Awards.Tally.new()
	_award_feed(t3, [_kill(null, 2.0, "crush"), _kill(null, 1.0, "fall")])
	expect(Awards.pick(t3, _award_state([[1, 30, false], [2, 30, false]])), [], "첫 탈락만 봄")


static func _combo(by: float, target: float, n: int) -> Dictionary:
	return {"type": "combo", "by": by, "target": target, "n": float(n), "finish": false}


# F5: 서버 combo 의 n 은 맞는 쪽이 이어 맞은 수 (누가 쳤든) — 여럿이 번갈아 친 사슬은 아무의 연타도 아님
func test_awards_combo_chain_single_hitter() -> void:
	var st := _award_state([[1, 0, true], [2, 0, true], [3, 0, true]])
	# 1번 4타·3번 3타를 2번에게 번갈아, 마지막은 3번 (첫 타는 이벤트 없음): n = 2(1번) 3(3번) 4(1번) 5(3번) 6(1번) 7(3번)
	var t := Awards.Tally.new()
	for i in 6:
		t.feed(_combo(1.0 if i % 2 == 0 else 3.0, 2.0, i + 2))
	expect(Awards.pick(t, st), [], "번갈아 친 7연타는 콤보 장인 없음")
	expect([t.rows[1].combo, t.rows.get(3, Awards.NONE).combo], [2, 0], "섞이기 전까지만 (1번 2), 3번은 0")
	# 한 사람이 7타
	var t2 := Awards.Tally.new()
	for n in range(2, 8):
		t2.feed(_combo(1.0, 2.0, n))
	expect(Awards.pick(t2, st), ["콤보 장인 · P1 7연타"], "혼자 7연타")
	# 섞인 사슬이 끝나고 새 사슬 (n 이 지난 n + 1 이 아님) 은 다시 셈
	for n in range(2, 6):
		t.feed(_combo(3.0, 2.0, n))
	expect(Awards.pick(t, st), ["콤보 장인 · P3 5연타"], "새 사슬은 3번 혼자 5연타")
	# 사슬은 맞는 사람마다 따로: 1번이 2번을, 3번이 4번을 동시에 쳐도 서로 안 섞임
	var t3 := Awards.Tally.new()
	for n in range(2, 7):
		t3.feed(_combo(1.0, 2.0, n))
		t3.feed(_combo(3.0, 4.0, n))
	expect([t3.rows[1].combo, t3.rows[3].combo], [6, 6], "맞는 사람이 다르면 따로")
	# 남이 끼어든 뒤로는 원래 치던 사람이 이어 쳐도 안 줌 (그 사슬 끝까지)
	var t4 := Awards.Tally.new()
	_award_feed(t4, [_combo(1.0, 2.0, 2), _combo(1.0, 2.0, 3), _combo(3.0, 2.0, 4), _combo(1.0, 2.0, 5), _combo(1.0, 2.0, 6)])
	expect([t4.rows[1].combo, t4.rows.get(3, Awards.NONE).combo], [3, 0], "끼어든 뒤는 안 셈")
	# target 없는 combo 는 흘림 (사슬을 알 수 없음)
	var rev: int = t4.rev
	t4.feed({"type": "combo", "by": 1.0, "n": 9.0})
	check(t4.rev == rev and t4.rows[1].combo == 3, "target 없는 combo 는 흘림")
	# 새 판이면 사슬도 비움
	t4.at_round("ABCD|9")
	check(t4.chains.is_empty(), "새 판이면 사슬 비움")


# F6: 결과 판 자리 (results.gd _place): 오른쪽에 붙고, 작은 창에서 위·아래 여백 안으로 — 넘치면 통째로 줄임
func test_results_place() -> void:
	var m: float = U.C.HUD_CARD_MARGIN
	# [화면, 판 크기, 배율 1 인지]
	for row in [[Vector2(960, 540), Vector2(430, 504), false], [Vector2(960, 540), Vector2(430, 440), true], [Vector2(960, 540), Vector2(430, 480), false], [Vector2(1280, 720), Vector2(430, 504), true],
			[Vector2(1920, 1080), Vector2(430, 504), true], [Vector2(960, 540), Vector2(430, 700), false], [Vector2(400, 300), Vector2(430, 200), false]]:
		var view: Vector2 = row[0]
		var content: Vector2 = row[1]
		var at := U.results_place(view, content)
		var tag := "results_place(%s, %s) = %s" % [str(view), str(content), str(at)]
		check((at.scale == 1.0) == row[2], "배율 1 %s: %s" % [str(row[2]), tag])
		check(is_equal_approx(at.x + content.x * at.scale, view.x - m), "오른쪽 끝에 붙음 (줄인 폭으로): " + tag)
		check(at.x >= m - 1e-6, "왼쪽도 화면 안: " + tag)
		check(at.y >= U.RESULTS_TOP - 1e-6 and at.y + content.y * at.scale <= view.y - m + 1e-6, "위·아래 화면 안: " + tag)
	# 넉넉한 화면: 예전 자리 그대로 (세로 가운데 + RESULTS_DROP)
	var big := U.results_place(Vector2(1280, 720), Vector2(430, 504))
	check(is_equal_approx(big.y, (720.0 - 504.0) / 2.0 + U.RESULTS_DROP) and is_equal_approx(big.x, 1280.0 - m - 430.0), "1280×720: %s" % str(big))
	# 960×540 에 504 짜리 (8명 + 칭호 3줄): 자리 540 - 74 - 12 = 454 → 454/504 배, 위 끝 (핑 칸 아래) 에 붙음
	var small := U.results_place(Vector2(960, 540), Vector2(430, 504))
	check(is_equal_approx(U.RESULTS_TOP, 74.0), "결과 판 위 끝 = 핑 칸 아래 끝 (52 + 19) + 띄움 3 = 대기실 판의 가장 높은 위 끝: %s" % str(U.RESULTS_TOP))
	check(is_equal_approx(small.scale, 454.0 / 504.0) and is_equal_approx(small.y, U.RESULTS_TOP), "960×540: %s" % str(small))
	# 사이클 6 병합 리뷰 F3: 칭호 3줄로 길어진 8명 판이 오른쪽 위 핑 칸 (ui.gd net_box — 오른쪽 12 · 위 52, 높이 19) 과 안 겹침.
	# 예전 위 끝 40 은 960×540 에서 판이 y 41 까지 올라와 핑 칸이 판 오른쪽 위 모서리 안에 들어갔음. 긴 판·큰 화면에서도 같음
	check(U.RESULTS_TOP >= U.NET_TOP + U.NET_PING_H, "위 끝이 핑 칸 아래 끝보다 아래: %s" % str(U.RESULTS_TOP))
	check(is_equal_approx(U.RESULTS_TOP, U.lobby_y(540.0, 540.0 - U.LOBBY_VPAD)), "대기실 판의 가장 높은 위 끝과 같은 규칙: %s / %s" % [str(U.RESULTS_TOP), str(U.lobby_y(540.0, 540.0 - U.LOBBY_VPAD))])
	for view in [Vector2(960, 540), Vector2(1280, 720), Vector2(1920, 1080)]:
		for content in [Vector2(430, 504), Vector2(430, 560), Vector2(470, 640), Vector2(470, 900)]:
			var at := U.results_place(view, content)
			var panel := Rect2(at.x, at.y, content.x * at.scale, content.y * at.scale)
			for ping_w in [60.0, 84.0, 140.0]: # '핑 54ms' · '핑 671ms' · '핑 끊김' 보다 넓은 폭까지
				var ping := U.net_ping_rect(view, ping_w)
				check(not panel.intersects(ping) and panel.position.y - ping.end.y >= U.NET_GAP - 1e-6, "결과 판 %s 이 핑 칸 %s 과 안 겹침 (화면 %s)" % [str(panel), str(ping), str(view)])
			check(panel.end.y <= view.y - m + 1e-6 and panel.position.x >= m - 1e-6, "그래도 화면 안: %s (화면 %s)" % [str(panel), str(view)])
	# 접속 표시 자리 (ui.gd _net_draw): 오른쪽 끝에서 NET_RIGHT, 위 NET_TOP — 핑 칸 사각형과 같은 기준
	check(U.net_pos(Vector2(960, 540), 84.0) == Vector2(960.0 - 12.0 - 84.0, 52.0) and U.net_ping_rect(Vector2(960, 540), 84.0) == Rect2(864, 52, 84, 19), "접속 표시 자리: %s" % str(U.net_pos(Vector2(960, 540), 84.0)))
	# 줄이지 않아도 되지만 가운데 + DROP 이면 위 끝 (핑 칸 아래) 보다 올라가는 높이: 위 끝에 붙이고 아래는 여백 안
	var mid := U.results_place(Vector2(960, 540), Vector2(430, 450))
	check(mid.scale == 1.0 and is_equal_approx(mid.y, U.RESULTS_TOP) and mid.y + 450.0 <= 540.0 - m, "위 끝에 붙임: %s" % str(mid))
	check(U.results_place(Vector2(960, 540), Vector2(430, 0)).scale == 1.0, "높이 0 (크기를 아직 모름)")
	# 판 노드가 그 계산대로 놓임 (results.gd _place_in): 960×540 에선 줄어 네 테두리가 화면 안, 1280×720 에선 배율 1
	var r = Results.new()
	r._ready()
	r.size = Vector2(430, 504)
	check(is_equal_approx(r.size.y, 504.0), "판 크기를 넣음: %s" % str(r.size))
	for view in [Vector2(960, 540), Vector2(1280, 720)]:
		r._place_in(view)
		var end: Vector2 = r.position + r.size * r.scale
		var tag := "%s: 자리 %s 크기 %s 배율 %s" % [str(view), str(r.position), str(r.size), str(r.scale)]
		check(r.position.x >= 0.0 and r.position.y >= U.RESULTS_TOP - 1e-3 and end.y <= view.y - m + 1e-3 and is_equal_approx(end.x, view.x - m), "네 테두리가 화면 안: " + tag)
		check(is_equal_approx(r.scale.x, r.scale.y) and (r.scale.x < 1.0) == (view.y < 600.0), "작은 화면만 줄임: " + tag)
	r.free()
	# 실제 판 (8명 + 칭호 3줄) 이 960×540·1280×720 화면 안에 드는지는 노드가 트리에 있어야 재므로 (get_viewport_rect — 이 러너에선 못 함)
	# 자동 조종 스크린샷으로 봄: --resolution 960x540 … --shot-at results --shot-after 6 (ui/README.md)
