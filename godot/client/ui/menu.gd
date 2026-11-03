# 메뉴 (방 밖, JS #rooms .menu): 가운데 빛 로고 + 내 이름 + 큰 버튼 (방 만들기·코드로 들어가기·공개 방 / 연습·튜토리얼·설정).
# 큰 버튼을 누르면 바로 아래 세부가 펼쳐짐 (한 번에 하나, 다시 누르면 접힘 — JS openMenu). 3D 배경은 다음 단계 (지금은 뒤 장면 그대로)
extends Control

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Prefs := preload("res://ui/ui_prefs.gd")
const U := preload("res://ui/ui_calc.gd")
const Lobby := preload("res://ui/lobby.gd")
const Big := preload("res://ui/big_btn.gd")

signal open_settings
signal open_tutorial

var nick: LineEdit
var msg: Label
var count_label: Label
var room_name: LineEdit
var room_code: LineEdit
var list_box: VBoxContainer
var create_btn: Button
var bigs := {} # 이름 → Button
var panes := {} # 이름 → 펼친 세부 Control
var list_key := ""
var col: VBoxContainer
var logo: Label
var logo_glow: Array = [] # 로고 뒤 빛 겹 (CSS text-shadow 4·18·46·90px 흐림 흉내: 외곽선 굵기·진하기를 겹겹이)
var streak: TextureRect # 로고 가운데 빛 줄 (h2::after)
var sub: Label
var mrow: HBoxContainer
var mrow_btns: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 가장자리 어둡게 (JS #rooms radial-gradient(ellipse at 50% 42%, transparent 0 35%, rgba(0,0,0,.55) 100%)) — 예전엔 화면 전체 .35
	add_child(S.radial_shade(Vector2(0.5, 0.42), 0.35, Color(0, 0, 0, 0), Color(0, 0, 0, 0.55)))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	col = VBoxContainer.new()
	col.custom_minimum_size.x = 600
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var top_col := VBoxContainer.new() # 로고·부제·이름 (JS h2 → .sub margin 6 0 14 → .nick margin-bottom 12)
	top_col.add_theme_constant_override("separation", 0)
	col.add_child(top_col)

	# 로고는 판 폭(600)을 넘쳐도 판을 넓히지 않음 (JS h2 가 .menu 밖으로 넘침) — 컨테이너 아닌 Control 안에 가운데로
	var logo_box := Control.new()
	logo_box.custom_minimum_size.y = 120
	top_col.add_child(logo_box)
	# JS h2: 기울임 + skewX(-6deg) (글꼴 기울기 변환), 자간 .04em, 부드러운 빛 (흐림 대신 빛 겹), 가운데 빛 줄
	streak = S.streak()
	logo_box.add_child(streak)
	for gl in S.LOGO_GLOW:
		var l := Label.new()
		l.text = "TETRAFALL"
		l.add_theme_font_override("font", S.slanted(S.LOGO_SLANT))
		l.add_theme_font_size_override("font_size", 112)
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0))
		l.add_theme_constant_override("outline_size", int(gl[0]))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		S.glow_layer(l, gl[1], gl[2])
		logo_box.add_child(l)
		logo_glow.append(l)
	logo = Label.new()
	logo.text = "TETRAFALL"
	logo.add_theme_font_override("font", S.slanted(S.LOGO_SLANT))
	logo.add_theme_font_size_override("font_size", 112)
	logo.add_theme_color_override("font_color", Color.WHITE)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logo_box.add_child(logo)
	logo_box.resized.connect(_place_logo.bind(logo_box))
	sub = S.label("떨어지는 블록 위에서 밀어 떨어뜨리는 3D 대전", 15)
	sub.add_theme_font_override("font", S.spaced(3, true)) # JS .sub system-ui · letter-spacing 3px, 색 gl, 흐림 .85
	S.tint(sub)
	sub.modulate.a = 0.85
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_col.add_child(sub)

	var nick_row := HBoxContainer.new()
	nick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	nick_row.add_theme_constant_override("separation", 10) # JS .nick gap 10, 글자 gl 빛 없음
	nick_row.add_child(S.tint(S.label("내 이름", 18, Color.WHITE)))
	nick = S.line_edit("머리 위에 보임", 22, int(C.NAME_MAX_LEN))
	nick.custom_minimum_size.x = 198 # 9em
	nick.alignment = HORIZONTAL_ALIGNMENT_CENTER
	S.underline_edit(nick) # JS .nick input: 아래 2px 빛 줄만 + rgba(0,0,0,.35), padding 4 8
	nick.text = str(Prefs.get_value("name", ""))
	nick.text_changed.connect(func(t): Prefs.set_value("name", t.strip_edges()))
	nick_row.add_child(nick)
	top_col.add_child(nick_row)

	msg = S.body_label("", 15) # JS #rooms-msg system-ui
	S.tint(msg, Color("ffd0a0"), 0.65)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.visible = false # JS #rooms-msg:empty { display: none } — 빈 줄 자리를 차지하지 않게
	col.add_child(msg)

	# 방 만들기
	var create := VBoxContainer.new()
	var cline := HBoxContainer.new()
	room_name = S.line_edit("방 이름 (비우면 '내 이름의 방')", 20, int(C.ROOM_NAME_MAX_LEN))
	room_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_name.text_submitted.connect(func(_t): _create())
	cline.add_child(room_name)
	create_btn = S.button("만들기", _create, "go", 20)
	cline.add_child(create_btn)
	create.add_child(cline)
	create.add_child(_note("처음엔 비공개 — 코드·링크를 아는 사람만 (대기실에서 '공개로')"))
	_item(col, "create", "방 만들기", create)

	# 코드로 들어가기
	var code := VBoxContainer.new()
	var kline := HBoxContainer.new()
	kline.alignment = BoxContainer.ALIGNMENT_CENTER
	room_code = S.line_edit("ABCD", 26, int(C.ROOM_CODE_LEN))
	room_code.custom_minimum_size.x = 156 # 6em
	room_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_code.add_theme_font_override("font", S.spaced(8)) # JS #room-code letter-spacing 8px, text-transform uppercase
	room_code.text_changed.connect(func(t):
		var up: String = str(t).to_upper()
		if up != t:
			var at := room_code.caret_column
			room_code.text = up
			room_code.caret_column = at)
	room_code.text_submitted.connect(func(_t): _join(room_code.text))
	kline.add_child(room_code)
	kline.add_child(S.button("들어가기", func(): _join(room_code.text), "go", 20))
	code.add_child(kline)
	code.add_child(_note("친구에게 받은 방 코드"))
	_item(col, "code", "코드로 들어가기", code)

	# 공개 방
	scroll = ScrollContainer.new() # JS #room-list: 내용만큼, 최대 30vh
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)
	_item(col, "list", "공개 방", scroll)
	count_label = S.body_label("", 15, Color(1, 1, 1, 0.75)) # JS button.big small: 글 바로 뒤 margin-left 10 (자리는 _place_count)
	bigs.list.add_child(count_label)
	bigs.list.resized.connect(_place_count)

	# 연습·튜토리얼·설정
	mrow = HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	for it in [["연습", _practice], ["튜토리얼", func(): open_tutorial.emit()], ["설정", func(): open_settings.emit()]]:
		var b := S.button(it[0], it[1], "big", 24)
		b.custom_minimum_size.y = 50
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", S.spaced(3)) # JS .mrow button.big letter-spacing 3px
		Big.attach(b, 3, S.reduced()) # 반짝임 늦춤 .75초 (JS .mrow button.big::after)
		mrow.add_child(b)
		mrow_btns.append(b)
	mrow_btns[0].tooltip_text = "혼자, 허수아비 · 친구도 코드로 들어옴" # JS #practice-btn title
	col.add_child(mrow)

	resized.connect(_layout)
	_layout.call_deferred()
	Store.rooms_changed.connect(func(_l): _render_list())
	Store.join_error.connect(func(r): _msg(str(r)))
	Store.left_room.connect(func(r): _msg("" if str(r) == "" else str(r)))
	_render_list()


# 화면 크기 따라 (JS .menu 폭 min(600px, 100vw − 32px), 로고 clamp(64px, 9.2vw, 124px) · 작은 창 @media: 로고 clamp(48px, 9vh, 80px),
# 부제 13px margin 2 0 8, 이름 줄 아래 8, 버튼 사이 7, 큰 버튼 24px·padding 11 (46), 아래 줄 20px·padding 9 (38))
func _layout() -> void:
	var small := U.small(size)
	col.custom_minimum_size.x = minf(600.0, size.x - 32.0)
	var fs := clampf(size.y * 0.09, 48.0, 80.0) if small else clampf(size.x * 0.092, 64.0, 124.0)
	for l in [logo] + logo_glow:
		(l as Label).add_theme_font_size_override("font_size", int(fs))
	var logo_box := logo.get_parent() as Control
	logo_box.custom_minimum_size.y = fs * 0.95 + 6.0 # line-height .95 (+ 빛 여백)
	sub.add_theme_font_size_override("font_size", 13 if small else 15)
	col.add_theme_constant_override("separation", 7 if small else 10)
	var top_col := sub.get_parent() as VBoxContainer
	top_col.add_theme_constant_override("separation", 2 if small else 6)
	for id in bigs:
		bigs[id].add_theme_font_size_override("font_size", 24 if small else 30)
		bigs[id].custom_minimum_size.y = 46 if small else 62
		Big.fit(bigs[id], 46 if small else 62) # 사선을 칸 안으로 (JS clip-path)
	for b in mrow_btns:
		b.add_theme_font_size_override("font_size", 20 if small else 24)
		b.custom_minimum_size.y = 38 if small else 50
		Big.fit(b, 38 if small else 50)
	mrow.add_theme_constant_override("separation", 10)
	_place_logo(logo_box)
	_place_count()


func _place_logo(box: Control) -> void:
	# 글자 칸 높이는 글꼴 줄 높이 (~1.4em) 라 판 (line-height .95) 보다 큼 → 판 가운데에 맞춰 위아래로 넘치게 둠
	for l in [logo] + logo_glow:
		var lab := l as Label
		var m := lab.get_combined_minimum_size()
		lab.size = Vector2(maxf(m.x, box.size.x), m.y)
		lab.position = Vector2((box.size.x - lab.size.x) / 2.0, (box.size.y - m.y) / 2.0)
	# 빛 줄: 로고 글자 폭 + 양쪽 12%, 높이 54% 자리에 3px (JS h2::after left/right -12%, top 54%)
	var tw := logo.get_theme_font("font").get_string_size(logo.text, HORIZONTAL_ALIGNMENT_LEFT, -1, logo.get_theme_font_size("font_size")).x
	streak.size = Vector2(tw * 1.24, 3)
	streak.position = Vector2((box.size.x - streak.size.x) / 2.0, box.size.y * 0.54)


# '공개 방' 글 바로 뒤에 방 수 (JS <small> margin-left 10)
func _place_count() -> void:
	var b: Button = bigs.list
	var f := b.get_theme_font("font")
	var tw := f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
	count_label.reset_size()
	count_label.position = Vector2(b.size.x / 2.0 + tw / 2.0 + 10.0, (b.size.y - count_label.size.y) / 2.0 + 2.0)


func _note(text: String) -> Label:
	var l := S.body_label(text, 13, Color("a49cbc")) # JS .open .note system-ui
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# 큰 버튼 + 그 아래 접힌 세부 판
func _item(parent: Node, id: String, text: String, body: Control) -> void:
	var b := S.button(text, func(): open(id if bigs[id].button_pressed else null), "big", 30) # 토글 버튼: pressed 신호 때 이미 눌림 상태가 바뀌어 있음
	b.toggle_mode = true
	b.custom_minimum_size.y = 62
	b.add_theme_font_override("font", S.spaced(4)) # JS button.big letter-spacing 4px
	Big.attach(b, bigs.size(), S.reduced()) # 바탕·안쪽 빛·빛 세모·반짝임 (JS .mi:nth-child 마다 .25초 늦게)
	parent.add_child(b)
	bigs[id] = b
	var pane := PanelContainer.new()
	pane.add_theme_stylebox_override("panel", S.open_pane()) # JS .open: 거의 검정 + 안쪽 1px gb + 잘린 모서리, margin 6px 10px 0
	pane.add_child(body)
	pane.visible = false
	parent.add_child(pane)
	panes[id] = pane


# 한 번에 하나만 펼침 (null 이면 다 접음). 펼치면 그 안 글자 칸에 커서
func open(which) -> void:
	for id in bigs:
		bigs[id].set_pressed_no_signal(id == which)
		panes[id].visible = id == which
		if id == which and not S.reduced():
			S.pop_down(panes[id]) # JS open-down .22s (위에서 6px, 흐림 → 보임)
	if which == "create":
		room_name.grab_focus()
	elif which == "code":
		room_code.grab_focus()


func _msg(t: String) -> void:
	msg.text = t
	msg.visible = t != ""


func _nick() -> String:
	return nick.text.strip_edges()


func _create() -> void:
	_msg("")
	Store.create_room(room_name.text, _nick())


func _join(code: String) -> void:
	_msg("")
	Store.join(code)


func _practice() -> void:
	Net.send({"type": "practice", "nick": _nick()})


# 공개 방 목록: 이름 + 정보 줄 + 들어가기 (꽉 차면 못 누름)
func _render_list() -> void:
	var L: Dictionary = Store.rooms_list
	if L.is_empty():
		return
	var rooms: Array = L.get("rooms", [])
	var full: bool = float(L.get("count", 0)) >= float(L.get("max", 1))
	create_btn.disabled = full
	count_label.text = "%d개%s" % [rooms.size(), " · 서버 방 가득 참" if full else ""]
	var key := JSON.stringify(rooms)
	if key == list_key:
		return
	list_key = key
	for c in list_box.get_children():
		c.free()
	if rooms.is_empty():
		var none := _note("공개된 방 없음. 친구에게 코드나 링크를 받거나 방을 만드세요")
		none.add_theme_font_size_override("font_size", 14) # JS #room-list .none: #8c84a4 14px
		none.add_theme_color_override("font_color", Color("8c84a4"))
		list_box.add_child(none)
		_fit_list()
		return
	for r in rooms:
		var row_box := PanelContainer.new() # JS .room: padding 8 12, rgba(255,255,255,.035) + 안쪽 1px gc, 사선
		row_box.add_theme_stylebox_override("panel", S.room_row())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row_box.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(S.label(str(r.name), 18, Color.WHITE))
		var bots := " + 봇 %d (%s)" % [int(r.bots), Lobby.BOT_LEVEL_KO.get(str(r.get("botLevel", "")), str(r.get("botLevel", "")))] if float(r.get("bots", 0)) > 0 else "" # JS: 봇 수 + 난이도
		var mode: String = C.MODE_NAMES.get(str(r.get("mode", "survival")), "생존")
		var map_name: String = C.MAPS[str(r.map)].name if C.MAPS.has(str(r.get("map", ""))) else ("무작위" if str(r.get("map", "")) == "random" else str(r.get("map", "")))
		info.add_child(S.body_label("사람 %d%s / %d명 · %s · 맵 %s%s · %s" % [int(r.humans), bots, int(r.max), mode, map_name, " · 하늘 계단" if r.get("skyStairs", false) else "", "팀전" if r.get("teamMode", false) else "개인전"], 12, Color("a49cbc")))
		row.add_child(info)
		var is_full: bool = float(r.humans) + float(r.get("bots", 0)) >= float(r.max)
		var code_s := str(r.code)
		var b := S.button("꽉 참" if is_full else "들어가기", func(): _join(code_s), "go", 16)
		b.disabled = is_full
		row.add_child(b)
		list_box.add_child(row_box)
	_fit_list()


# 목록 높이: 내용만큼, 최대 30vh (JS #room-list max-height: 30vh) — 예전엔 늘 200
var scroll: ScrollContainer
func _fit_list() -> void:
	scroll.custom_minimum_size.y = minf(size.y * 0.3, list_box.get_combined_minimum_size().y)
