# W4 화면 노드를 실제로 만들어 값을 읽는 테스트: 점수 띠 다시 그리기 (JS scoreKey) · 화면별 핵심 크기·여백·글자 크기 (JS index.html 과 대조해 고친 값)
# 러너 (_initialize) 동안엔 root 가 트리 밖이라 _ready 가 안 불림 → 직접 부르고, 끝에 지움
extends RefCounted

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _make(path: String) -> Node:
	var n: Node = load(path).new()
	n._ready()
	return n


func _player(id: int, slot: int, wins: int) -> Dictionary:
	return {"id": id, "slot": slot, "name": "P%d" % (slot + 1), "nick": "", "wins": wins, "score": 0, "color": slot, "alive": true}


# hud.score_band: 같은 스냅샷이면 점수 띠 노드를 그대로 둠 (JS updateScore scoreKey), 승수가 바뀌면 다시 만듦 — 예전엔 스냅샷마다 (30Hz) 다 지우고 새로
func test_score_band_rebuilds_only_on_change() -> void:
	var keep := [Store.my_id, Store.room]
	Store.my_id = 1
	Store.room = {"code": "ABCD"}
	var hud = _make("res://ui/hud.gd")
	var st := {"phase": "lobby", "mode": "survival", "teamMode": false, "players": [_player(1, 0, 0), _player(2, 1, 0), _player(3, 2, 0)], "round": {"n": 0}}
	var vp := Vector2(1280, 720)
	hud.score_band(st, vp, true)
	var first: Array = hud.score_bar.get_children()
	check(first.size() > 0 and hud.score_panel.visible, "대기실 점수 띠가 보임 (%d칸)" % first.size())
	hud.score_band(st.duplicate(true), vp, true) # 다음 스냅샷 (내용 같음)
	var second: Array = hud.score_bar.get_children()
	check(second == first and first.all(func(c): return is_instance_valid(c)), "같은 스냅샷 두 번이면 노드 그대로")
	var st2: Dictionary = st.duplicate(true)
	st2.players[1].wins = 1
	hud.score_band(st2, vp, true)
	check(not first.any(func(c): return is_instance_valid(c)), "승수가 바뀌면 다시 만듦")
	var third: Array = hud.score_bar.get_children()
	hud.score_panel.visible = false # ui.gd 가 메뉴 화면에서 숨김 → 다시 대기실이면 내용이 같아도 보여야 함
	hud.score_band(st2, vp, true)
	check(hud.score_panel.visible and hud.score_bar.get_children() != third, "밖에서 숨겼으면 다시 그림")
	# 판 중 (킬 점수전): 남은 시간 글자가 바뀔 때만
	var k := {"phase": "playing", "mode": "kills", "teamMode": false, "players": [_player(1, 0, 0), _player(2, 1, 0)], "round": {"n": 1, "left": 60000.0, "killsTarget": 5}}
	hud.score_band(k, vp, false)
	var kc: Array = hud.score_bar.get_children()
	var k2: Dictionary = k.duplicate(true)
	k2.round.left = 60010.0 # 같은 '1:00'
	hud.score_band(k2, vp, false)
	check(hud.score_bar.get_children() == kc, "남은 시간 글자가 같으면 그대로")
	k2.round.left = 58000.0
	hud.score_band(k2, vp, false)
	check(hud.score_bar.get_children() != kc, "남은 시간 글자가 바뀌면 다시")
	hud.free()
	Store.my_id = keep[0]
	Store.room = keep[1]


func _sb(c: Control, st := "normal") -> StyleBoxFlat:
	return c.get_theme_stylebox(st) as StyleBoxFlat


func _fs(c: Control, nm := "font_size") -> int:
	return c.get_theme_font_size(nm)


# 안 여백 [왼, 위, 오른, 아래]
func _m(s: StyleBox) -> Array:
	return [int(s.content_margin_left), int(s.content_margin_top), int(s.content_margin_right), int(s.content_margin_bottom)]


# 메뉴 (JS #rooms): 로고 clamp(64, 9.2vw, 124) · 작은 창 clamp(48, 9vh, 80), 부제 15/13, 큰 버튼 30·62 / 24·46, 아래 줄 24·50 / 20·38, 간격 10/7
func test_menu_sizes() -> void:
	var m = _make("res://ui/menu.gd")
	m.set_anchors_preset(Control.PRESET_TOP_LEFT) # 화면 가득 앵커면 크기를 못 정함
	m.size = Vector2(960, 540)
	m._layout()
	check(_fs(m.logo) == 48, "960 로고 %d (JS clamp(48, 9vh=48.6, 80))" % _fs(m.logo))
	check(_fs(m.sub) == 13 and m.col.get_theme_constant("separation") == 7, "960 부제 13 · 간격 7")
	for id in m.bigs:
		check(_fs(m.bigs[id]) == 24 and m.bigs[id].custom_minimum_size.y == 46, "960 큰 버튼 %s 24px·46" % id)
	for b in m.mrow_btns:
		check(_fs(b) == 20 and b.custom_minimum_size.y == 38, "960 아래 줄 버튼 20px·38")
	m.size = Vector2(1280, 720)
	m._layout()
	check(_fs(m.logo) == 117, "1280 로고 %d (JS 9.2vw = 117.8)" % _fs(m.logo))
	check(_fs(m.sub) == 15 and m.col.get_theme_constant("separation") == 10, "1280 부제 15 · 간격 10")
	for id in m.bigs:
		check(_fs(m.bigs[id]) == 30 and m.bigs[id].custom_minimum_size.y == 62, "1280 큰 버튼 %s 30px·62" % id)
	for b in m.mrow_btns:
		check(_fs(b) == 24 and b.custom_minimum_size.y == 50, "1280 아래 줄 버튼 24px·50")
	check(is_equal_approx(_sb(m.bigs.values()[0]).skew.x, S.SKEW_BIG), "큰 버튼 사선 %s (JS 18px / 62)" % S.SKEW_BIG)
	m.free()


# 메뉴 큰 버튼 꾸밈 (W8, ui/big_btn.gd = JS #rooms button.big): 평행사변형이 칸 안 (clip-path 18px), 왼쪽 빛 띠는 왼쪽 아래 세모만,
# 반짝임 5.5초 중 70% 쉼 → -60% 에서 130% 로, 아래 줄 버튼 사이가 겹치지 않음 (StyleBoxFlat skew 넘침을 expand_margin 으로 되돌림)
func test_menu_big_button_look() -> void:
	var Big = load("res://ui/big_btn.gd")
	var p: PackedVector2Array = Big.shape(600, 62, 18)
	check(p[0] == Vector2(18, 0) and p[1] == Vector2(600, 0) and p[2] == Vector2(582, 62) and p[3] == Vector2(0, 62), "평행사변형 %s" % str(p))
	var t: PackedVector2Array = Big.strip(62, 18)
	check(t.size() == 3 and is_equal_approx(t[0].y, 62.0 * (1.0 - 4.0 / 18.0)) and t[1] == Vector2(4, 62) and t[2] == Vector2(0, 62), "빛 띠 세모 %s" % str(t))
	check(Big.sheen_x(0.0) == null and Big.sheen_x(5500.0 * 0.69) == null, "반짝임 앞 70% 는 쉼")
	check(is_equal_approx(Big.sheen_x(5500.0 * 0.7), -0.6) and is_equal_approx(Big.sheen_x(5500.0 * 0.85), 0.35), "반짝임 -60% → 130%")
	var m = _make("res://ui/menu.gd")
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.size = Vector2(1280, 720)
	m._layout()
	var b: Button = m.bigs.values()[0]
	var sb: StyleBoxFlat = b.get_theme_stylebox("normal")
	check(is_equal_approx(sb.expand_margin_left, -S.SKEW_BIG * 31.0) and is_equal_approx(sb.expand_margin_right, -S.SKEW_BIG * 31.0), "큰 버튼 사선 넘침 되돌림 %s" % sb.expand_margin_left)
	check(sb.bg_color.a == 0.0 and sb.border_width_left == 1, "큰 버튼 stylebox 는 1px 테두리만 (바탕은 big_btn)")
	check(b.get_node_or_null("BigBack") != null and b.get_node("BigBack").show_behind_parent, "큰 버튼 뒤 겹")
	var mb: Button = m.mrow_btns[0]
	check(is_equal_approx(mb.get_theme_stylebox("hover").expand_margin_left, -S.SKEW_BIG * 25.0), "아래 줄 버튼 사선 넘침 되돌림")
	check(b.get_theme_constant("shadow_outline_size") == int(S.BIG_TXT_GLOW[0]), "큰 버튼 글자 넓은 빛")
	m.free()


# 로고 흐린 빛 (W8, ui/text_glow.gd = JS h2 text-shadow 18·46·90px): 흐림은 크기 그대로·멀리 번짐·넓을수록 더 멀리, 굽기는 트리 밖이면 안 함.
# 세기는 JS 스샷 (자수정 메뉴 로고 위 23px 픽셀 68,18,79) 에 맞춘 값
func test_logo_blur_glow() -> void:
	var TG = load("res://ui/text_glow.gd")
	check(TG.halvings(9.0) == 4 and TG.halvings(23.0) == 5 and TG.halvings(45.0) == 6, "반씩 줄이는 횟수 %d·%d·%d" % [TG.halvings(9.0), TG.halvings(23.0), TG.halvings(45.0)])
	var img := Image.create(128, 64, false, Image.FORMAT_RGB8)
	img.fill_rect(Rect2i(60, 28, 8, 8), Color.WHITE)
	var near: Image = TG.blur(img, 9.0)
	var far: Image = TG.blur(img, 45.0)
	check(near.get_size() == img.get_size() and far.get_size() == img.get_size(), "흐려도 크기 그대로")
	check(img.get_pixel(64, 12).r == 0.0 and near.get_pixel(64, 12).r > 0.0, "흐리면 글자 밖으로 번짐")
	check(far.get_pixel(20, 32).r > near.get_pixel(20, 32).r, "넓은 흐림이 더 멀리")
	check(S.LOGO_BLUR.size() == 3 and S.LOGO_BLUR[2][0] == 90 and S.LOGO_BLUR_LOW.size() == 1, "로고 빛 겹: 보통 18·46·90, 그래픽 낮춤 14 하나")
	check(S.LOGO_GLOW.size() == 2, "굵은 외곽선 빛 겹은 뺌 (9·4 만)")
	var gc: Color = S.gain(Color(1, 0.5, 0.2), 0.5)
	check(is_equal_approx(gc.r, 0.5) and is_equal_approx(gc.b, 0.1) and gc.a == 1.0, "더하기 빛 색 = rgb × 세기")
	var m = _make("res://ui/menu.gd")
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.size = Vector2(1280, 720)
	m._layout()
	check(m.blur_rects.is_empty(), "트리 밖이면 굽지 않음")
	m.free()


# 대기실 판 (JS #center): 작은 창·1280 줄 사이·카드·시작·방 설정·버튼 여백·고르기 칸 폭 — 960×540 에서 '링크 복사'·'방 나가기' 줄이 판 안에 들어오게 고친 값
func test_lobby_sizes() -> void:
	var l = _make("res://ui/lobby.gd")
	l._small_sizes(true)
	check(_m(l.pane_box) == [18, 6, 12, 6], "작은 창 판 여백 %s (JS 6 12 6 18)" % str(_m(l.pane_box)))
	check(_fs(l.status) == 15, "작은 창 상태 %d (JS 15px !important)" % _fs(l.status))
	check(l.card_btns.tank.custom_minimum_size == Vector2(62, 49), "작은 창 카드 %s (JS 62×49)" % str(l.card_btns.tank.custom_minimum_size))
	check(_fs(l.start_btn) == 22, "작은 창 시작 22px")
	check(_m(l.settings_wrap.get_theme_stylebox("panel")) == [10, 5, 10, 5], "작은 창 방 설정 판 padding 5 10")
	var small_gaps := {}
	for k in l.gaps:
		small_gaps[k] = int(l.gaps[k].custom_minimum_size.y)
	check(small_gaps.pick == 5 and small_gaps.name == 4 and small_gaps.swatches == 2 and small_gaps.start == 7 and small_gaps.settings == 8 and small_gaps.room == 6 and small_gaps.keys == 4, "작은 창 줄 사이 %s" % str(small_gaps))
	l._small_sizes(false)
	check(_m(l.pane_box) == [22, 10, 16, 10], "1280 판 여백 %s (JS 10 16 10 22)" % str(_m(l.pane_box)))
	check(_fs(l.status) == 18 and _fs(l.start_btn) == 30, "1280 상태 18 · 시작 30")
	check(l.card_btns.tank.custom_minimum_size == Vector2(72, 63), "1280 카드 %s (JS 72×63)" % str(l.card_btns.tank.custom_minimum_size))
	check(_m(l.settings_wrap.get_theme_stylebox("panel")) == [12, 7, 12, 7], "1280 방 설정 판 padding 7 12")
	check(int(l.gaps.pick.custom_minimum_size.y) == 7 and int(l.gaps.start.custom_minimum_size.y) == 12 and int(l.gaps.settings.custom_minimum_size.y) == 12, "1280 줄 사이")
	# 두 크기 같은 값: 방 설정·방 코드 줄 버튼 13px padding 3 11, 체크 15px (높이 21), 고르기 칸 폭 = JS select (모드 89 · 봇 63 · 맵 103), 이름 칸 높이 26
	for b in [l.add_bot, l.remove_bot, l.public_btn]:
		check(_fs(b) == 13 and _m(_sb(b)) == [11, 3, 11, 3], "버튼 %s 13px · padding 3 11 (%s)" % [b.text, str(_m(_sb(b)))])
	check([int(l.mode_sel.custom_minimum_size.x), int(l.level_sel.custom_minimum_size.x), int(l.map_sel.custom_minimum_size.x)] == [89, 63, 103], "고르기 칸 폭 %s (JS 89·63·103)" % str([l.mode_sel.custom_minimum_size.x, l.level_sel.custom_minimum_size.x, l.map_sel.custom_minimum_size.x]))
	check(not l.mode_sel.fit_to_longest_item, "고르기 칸 폭은 직접 (고도 기본은 글자 16 으로 재서 넓음)")
	# 높이는 글꼴 줄 높이 (17) + 여백 — 트리 밖에선 글꼴 줄 높이가 달라 여백으로 봄 (화면에선 체크 21 · 이름 칸 26, out-W4 덤프)
	check(_m(l.sky_box.get_theme_stylebox("normal")) == [4, 2, 0, 2] and l.sky_box.get_theme_icon("unchecked").get_size() == Vector2(15, 15), "체크 15px · margin 2 0 2 4 (높이 17 + 4 = JS 21)")
	check(_m(_sb(l.name_edit)) == [6, 5, 6, 4], "이름 칸 padding %s (17 + 9 = JS 26)" % str(_m(_sb(l.name_edit))))
	l.free()


# 플레이어 관리 (JS #host-players): 제목·팀전 줄은 표 밖 (grid-column 1 / -1), 작은 창 글 12·버튼 11 padding 2 7·판 8 10·간격 4 5, 1280 13·12·2 9·10 14 10 18·5 7
func test_host_players_sizes() -> void:
	var keep = Store.my_id
	Store.my_id = 1
	var h = _make("res://ui/host_players.gd")
	var st := {"teamMode": false, "mode": "survival", "players": [_player(1, 0, 0), _player(2, 1, 0), _player(3, 2, 0), _player(4, 3, 0)]}
	h.build(st, true)
	check(_m(h.pane_box) == [10, 8, 10, 8], "작은 창 판 여백 %s (JS 8 10)" % str(_m(h.pane_box)))
	check(h.grid.get_theme_constant("h_separation") == 5 and h.grid.get_theme_constant("v_separation") == 4, "작은 창 간격 4 5")
	check(h.head.get_child(0) is Label and h.grid.get_child_count() == 16, "제목·팀전은 표 밖, 표 = 4명 × 4칸 (%d)" % h.grid.get_child_count())
	var b: Button = h.grid.get_child(2)
	check(_fs(b) == 11 and _m(_sb(b)) == [7, 2, 7, 2], "작은 창 버튼 11px · padding 2 7")
	check(_fs(h.grid.get_child(0)) == 12, "작은 창 이름 12px")
	var w: float = h.get_combined_minimum_size().x
	check(w <= 190.0, "작은 창 판 폭 %d (JS 177, 예전 265)" % w)
	h.build(st, false)
	check(_m(h.pane_box) == [18, 10, 14, 10], "1280 판 여백 %s (JS 10 14 10 18)" % str(_m(h.pane_box)))
	b = h.grid.get_child(2)
	check(_fs(b) == 12 and _m(_sb(b)) == [9, 2, 9, 2] and _fs(h.grid.get_child(0)) == 13, "1280 버튼 12px · padding 2 9 · 이름 13")
	check(h.get_combined_minimum_size().x <= 226.0, "1280 판 폭 %d (JS 213)" % h.get_combined_minimum_size().x)
	h.free()
	Store.my_id = keep


# 결과 판 (JS #results): padding 16 22 18 28 · 초상 128 · 승리 글 34, 작은 창 11 16 12 22 · 96 · 30
func test_results_sizes() -> void:
	var r = _make("res://ui/results.gd")
	r.apply_small(true)
	check(_m(r.pane_box) == [22, 11, 16, 12] and r.star.custom_minimum_size == Vector2(96, 96) and _fs(r.head) == 30, "작은 창 결과 %s" % str(_m(r.pane_box)))
	r.apply_small(false)
	check(_m(r.pane_box) == [28, 16, 22, 18] and r.star.custom_minimum_size == Vector2(128, 128) and _fs(r.head) == 34, "1280 결과 %s" % str(_m(r.pane_box)))
	check(_fs(r.title) == 20 and r.star_box.border_width_bottom == 6, "제목 20 · 초상 아래 6px 승자 색")
	r.free()


# 설정 창 (JS #settings .box padding 20 28 22 32, h3 30px, 키 칸 13px · padding 2 9 · 9.5em)
func test_settings_sizes() -> void:
	var s = _make("res://ui/settings.gd")
	check(_m(s.box.get_theme_stylebox("panel")) == [32, 20, 28, 22], "설정 판 여백 %s" % str(_m(s.box.get_theme_stylebox("panel"))))
	var kb: Button = s.key_btns.values()[0]
	check(_fs(kb) == 13 and _m(_sb(kb)) == [9, 2, 9, 2] and kb.custom_minimum_size.x == 124, "키 칸 13px · padding 2 9 · 폭 124")
	check(_fs(s.leave_btn) == 16, "아래 버튼 16px")
	s.free()


# 튜토리얼 띠 (JS #tut-band): 진행 칸 padding 9 18 9 16 · 문구 19px padding 9 26 · 해냄 9 20, 겹침 −12, 사선 12px
func test_tutorial_band_sizes() -> void:
	var t = _make("res://ui/tutorial_ui.gd")
	check(t.band.get_theme_constant("separation") == -12, "칸끼리 −12 겹침")
	var pb: StyleBoxFlat = t.prog.get_parent().get_theme_stylebox("panel")
	check(_m(pb) == [16, 9, 18, 9] and is_equal_approx(pb.skew.x, 0.29), "진행 칸 padding %s" % str(_m(pb)))
	check(_fs(t.txt, "normal_font_size") == 19 and _fs(t.prog) == 19, "문구·진행 19px")
	check(_m(t.ok_lab.get_parent().get_theme_stylebox("panel")) == [20, 9, 20, 9], "해냄 칸 padding 9 20")
	check(_m(t.txt.get_parent().get_theme_stylebox("panel")) == [26, 9, 26, 9], "문구 칸 padding 9 26")
	t.free()


# 연습 창 (JS #practice): left 14 top 70, 폭 252, padding 12 16, 잘린 모서리 16, 제목 18px, 안내 칸 12px padding 3 10
func test_practice_sizes() -> void:
	var p = _make("res://ui/practice.gd")
	var wb: StyleBoxFlat = p.win.get_theme_stylebox("panel")
	check(p.win.position == Vector2(14, 70) and p.win.custom_minimum_size.x == 252, "연습 창 자리·폭")
	check(_m(wb) == [16, 12, 16, 12] and wb.corner_radius_top_right == 16 and wb.corner_radius_bottom_left == 16, "연습 창 padding %s · 모서리 16" % str(_m(wb)))
	check(_fs(p.hint) == 12 and _m(_sb(p.hint)) == [10, 3, 10, 3] and p.hint.position == Vector2(14, 70), "Tab 안내 칸")
	p.free()


# 접속 표시 (JS #net: 세로 gap 4, #netPing 12px padding 2 12, #netWarn 15px padding 4 16)
func test_net_sizes() -> void:
	var u = load("res://ui/ui.gd").new()
	var nb: VBoxContainer = u.make_net()
	check(nb.get_theme_constant("separation") == 4, "핑·알림 사이 4")
	check(_fs(u.ping) == 12 and _m(_sb(u.ping)) == [12, 2, 12, 2], "핑 칸 12px · padding 2 12")
	check(_fs(u.net_warn) == 15 and _m(_sb(u.net_warn)) == [16, 4, 16, 4], "알림 칸 15px · padding 4 16")
	nb.free()
	u.free()


# 본문 글꼴 부분 집합 (tools/subset-body-font.mjs) 에 스크립트 글의 글자가 다 있음 — 게임 문구를 바꾸고 도구를 안 돌리면 여기서 걸림
# (Noto Sans KR 에 없는 기호는 대체 글꼴 Black Han Sans·DejaVu 로 — NOT_IN_NOTO)
const NOT_IN_NOTO := "▸↺↻" # Noto Sans KR 에 없음 → DejaVu 기호 조각 (ui_font 검사 test_core 가 있는지 봄)


func test_body_font_subset_has_script_chars() -> void:
	var noto: FontFile = load("res://assets/fonts/noto-sans-kr-body.woff2")
	var body: Font = S.BODY
	check(noto != null and body is FontVariation and (body as FontVariation).base_font == noto, "본문 글꼴 = Noto 부분 집합 + 대체")
	var re := RegEx.create_from_string("\"([^\"\\n]*)\"")
	var missing := {}
	var dirs := ["res://"]
	var n := 0
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(d):
			if not sub.begins_with(".") and not sub in ["tests", "build", "addons"]:
				dirs.append(d.path_join(sub))
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".gd"):
				continue
			n += 1
			for m in re.search_all(FileAccess.get_file_as_string(d.path_join(f))):
				for ch in m.get_string(1):
					var o := ch.unicode_at(0)
					if o > 32 and not noto.has_char(o) and not NOT_IN_NOTO.contains(ch):
						missing[ch] = d.path_join(f)
	check(n > 30, "스크립트 %d개" % n)
	check(missing.is_empty(), "본문 글꼴에 없는 글자 (node godot/client/tools/subset-body-font.mjs 다시): %s" % [missing])
	var bytes := FileAccess.get_file_as_bytes("res://assets/fonts/noto-sans-kr-body.woff2").size()
	check(bytes < 512 * 1024, "본문 글꼴 %dKB (목표 0.5MB 이하)" % (bytes / 1024))


# JS 에서 system-ui 인 자리만 본문 글꼴 (설명·표 숫자·안내·체크 글·이름표), 제목·버튼·이름·방 코드는 그대로 Black Han Sans
func test_body_font_where_js_system_ui() -> void:
	var keep = Store.my_id
	Store.my_id = 1
	var l = _make("res://ui/lobby.gd")
	var bf := func(c: Control, nm := "font") -> bool: return c.get_theme_font(nm) == S.BODY
	check(bf.call(l.room_text) and bf.call(l.mode_info) and bf.call(l.keys_text) and bf.call(l.sky_box) and bf.call(l.hint), "대기실: 방 이름·모드 설명·조작법·체크 글·첫 안내 = 본문")
	check(not bf.call(l.code_label) and not bf.call(l.add_bot) and not bf.call(l.status) and not bf.call(l.stage_who), "대기실: 방 코드·버튼·상태·큰 캐릭터 이름 = 제목 글꼴")
	check(bf.call(l.skill_text, "normal_font"), "스킬 카드 설명 = 본문 (이름·키는 [font])")
	l.free()
	var h = _make("res://ui/host_players.gd")
	h.build({"teamMode": false, "mode": "survival", "players": [_player(1, 0, 0), _player(2, 1, 0)]}, false)
	check(bf.call(h.grid.get_child(0)) and not bf.call(h.head.get_child(0)), "플레이어 관리: 이름 = 본문, 제목 = 제목 글꼴")
	h.free()
	var s = _make("res://ui/settings.gd")
	check(bf.call(s.dup_label) and bf.call(s.checks.values()[0]) and not bf.call(s.key_btns.values()[0]), "설정: 안내·체크 = 본문, 키 칸 = 제목 글꼴")
	s.free()
	var p = _make("res://ui/practice.gd")
	check(bf.call(p.hint) and bf.call(p.checks.values()[0]), "연습: Tab 안내·체크 = 본문")
	p.free()
	Store.my_id = keep


# W35: 대기실 큰 캐릭터 칸이 클릭을 삼키지 않음 → 누르면 스킬 카드 열림, 카드를 누르거나 카드 밖을 누르면 닫힘
func test_lobby_stage_click_opens_skill_card() -> void:
	var l = _make("res://ui/lobby.gd")
	check(l.stage_box.mouse_filter == Control.MOUSE_FILTER_PASS, "큰 캐릭터 칸은 클릭을 위로 올림 (PASS)")
	var node: Node = l.stage_box
	while node != l.stage and node != null:
		check(node == l.stage_box or (node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_STOP), "stage 까지 길에 클릭을 삼키는 칸 없음 (%s)" % node.name)
		node = node.get_parent()
	for c in l.stage_box.get_children():
		if c != l.skill_btn and c != l.stage_3d: # stage_3d 는 _ready 에서 IGNORE (트리 밖이라 안 불림 — ui_check 가 실제로 확인)
			check((c as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "큰 캐릭터 칸 자식은 클릭 무시 (%s)" % c.name)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	l.stage.gui_input.emit(press)
	check(l.skill_card.visible and l.skill_btn.text == "스킬 닫기", "큰 캐릭터 클릭 → 스킬 카드 열림")
	l.skill_card.gui_input.emit(press)
	check(not l.skill_card.visible and l.skill_btn.text == "스킬 보기", "카드를 누르면 닫힘")
	l._toggle_card(true)
	l._toggle_card()
	check(not l.skill_card.visible, "토글 다시 → 닫힘")
	l.free()


# W35 결과 판 ↔ 메뉴 겹침 (재발 점검): 결과 → 방 나감 → 메뉴에서 결과·대기실·HUD 가 같이 보이면 안 됨. 슬래시가 덮는 순간에도 마지막 목표 화면만
func test_results_never_overlaps_menu() -> void:
	var keep := [Store.my_id, Store.room, Store.state, View.victory_stage]
	var ui = load("res://ui/ui.gd").new() # _ready (트리 밖이라 안 불림) 대신 판 노드를 직접 끼움 — 화면 고르기·보이기만 시험
	ui.menu = Control.new()
	ui.lobby = PanelContainer.new()
	ui.host_players = PanelContainer.new()
	ui.results = PanelContainer.new()
	ui.hud = _make("res://ui/hud.gd")
	ui.hud_extra = Control.new()
	ui.wipe = load("res://ui/wipe.gd").new()
	ui.wipe.covered.connect(func(): ui._show(ui.target))
	Store.my_id = 1
	Store.room = {"code": "ABCD"}
	Store.state = {"phase": "over", "mode": "survival", "players": [_player(1, 0, 1), _player(2, 1, 0)], "round": {"n": 1, "winnerId": 1}}
	View.victory_stage = "results"
	check(ui._screen_now() == "results", "판 끝 + 결과 단계 = 결과 화면")
	ui._show("results")
	check(ui.results.visible and not ui.menu.visible and not ui.lobby.visible and not ui.hud.visible, "결과 화면은 결과 판만")
	# 방을 나감 (Store 가 방을 비움) → 메뉴
	Store.my_id = null
	Store.room = {}
	Store.state = {}
	check(ui._screen_now() == "menu", "방 밖이면 메뉴")
	ui.target = "menu" # 슬래시가 도는 동안 목표가 바뀐 뒤 덮는 순간
	ui.wipe.covered.emit()
	check(ui.shown == "menu" and ui.menu.visible and not ui.results.visible and not ui.lobby.visible and not ui.hud.visible, "덮는 순간 메뉴만 (결과 판 안 남음)")
	# 연속 판: 결과 → 대기실 → 판 → 결과
	Store.my_id = 1
	Store.room = {"code": "ABCD"}
	for step in [["over", "results", "results"], ["lobby", "lobby", "lobby"], ["playing", "lobby", "game"], ["over", "results", "results"], ["over", "lobby", "lobby"]]:
		Store.state = {"phase": step[0], "mode": "survival", "players": [_player(1, 0, 0), _player(2, 1, 0)], "round": {"n": 2}}
		View.victory_stage = step[1]
		var want: String = step[2]
		check(ui._screen_now() == want, "%s·%s → %s (%s)" % [step[0], step[1], want, ui._screen_now()])
		ui._show(want)
		var vis := [ui.menu.visible, ui.lobby.visible, ui.results.visible, ui.hud.visible].filter(func(v): return v).size()
		check(vis == 1, "%s 화면은 판 하나만 보임 (%d)" % [want, vis])
	for n in [ui.menu, ui.lobby, ui.host_players, ui.results, ui.hud, ui.hud_extra, ui.wipe]:
		n.free()
	ui.free()
	Store.my_id = keep[0]
	Store.room = keep[1]
	Store.state = keep[2]
	View.victory_stage = keep[3]


# W35: 결과 판 승자 글 — 좁은 칸에서도 '승리' 가 두 줄로 쪼개지지 않게 (WORD JOINER), 보이는 글은 그대로
func test_results_head_keeps_word_together() -> void:
	const R := preload("res://ui/results.gd")
	var t: String = R.win_text("P4(봇)")
	check(t.contains("승\u2060리"), "승 리 사이 단어 이음표")
	check(t.replace("\u2060", "") == "P4(봇) 승리", "보이는 글은 'P4(봇) 승리' 그대로")
