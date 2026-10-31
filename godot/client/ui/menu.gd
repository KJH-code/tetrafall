# 메뉴 (방 밖, JS #rooms .menu): 가운데 빛 로고 + 내 이름 + 큰 버튼 (방 만들기·코드로 들어가기·공개 방 / 연습·튜토리얼·설정).
# 큰 버튼을 누르면 바로 아래 세부가 펼쳐짐 (한 번에 하나, 다시 누르면 접힘 — JS openMenu). 3D 배경은 다음 단계 (지금은 뒤 장면 그대로)
extends Control

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Prefs := preload("res://ui/ui_prefs.gd")

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


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 가장자리 어둡게 (CSS radial-gradient)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 600
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var logo := S.glow_label("TETRAFALL", 112, Color.WHITE, 10)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(logo)
	var sub := S.label("떨어지는 블록 위에서 밀어 떨어뜨리는 3D 대전", 15, S.g().lerp(Color.WHITE, 0.5))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var nick_row := HBoxContainer.new()
	nick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	nick_row.add_child(S.glow_label("내 이름", 18, S.g().lerp(Color.WHITE, 0.5), 3))
	nick = S.line_edit("머리 위에 보임", 22, int(C.NAME_MAX_LEN))
	nick.custom_minimum_size.x = 200
	nick.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nick.text = str(Prefs.get_value("name", ""))
	nick.text_changed.connect(func(t): Prefs.set_value("name", t.strip_edges()))
	nick_row.add_child(nick)
	col.add_child(nick_row)

	msg = S.label("", 15, S.g().lerp(Color("ffd0a0"), 0.65))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	room_code.custom_minimum_size.x = 150
	room_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_code.text_submitted.connect(func(_t): _join(room_code.text))
	kline.add_child(room_code)
	kline.add_child(S.button("들어가기", func(): _join(room_code.text), "go", 20))
	code.add_child(kline)
	code.add_child(_note("친구에게 받은 방 코드"))
	_item(col, "code", "코드로 들어가기", code)

	# 공개 방
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 200
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)
	_item(col, "list", "공개 방", scroll)
	count_label = S.label("", 15, Color(1, 1, 1, 0.75))
	bigs.list.add_child(count_label)
	count_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	count_label.position.x -= 40

	# 연습·튜토리얼·설정
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for it in [["연습", _practice], ["튜토리얼", func(): open_tutorial.emit()], ["설정", func(): open_settings.emit()]]:
		var b := S.button(it[0], it[1], "big", 24)
		b.custom_minimum_size.y = 50
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	col.add_child(row)

	Store.rooms_changed.connect(func(_l): _render_list())
	Store.join_error.connect(func(r): msg.text = str(r))
	Store.left_room.connect(func(r): msg.text = "" if str(r) == "" else str(r))
	_render_list()


func _note(text: String) -> Label:
	var l := S.label(text, 13, Color("a49cbc"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# 큰 버튼 + 그 아래 접힌 세부 판
func _item(parent: Node, id: String, text: String, body: Control) -> void:
	var b := S.button(text, func(): open(id if bigs[id].button_pressed else null), "big", 30) # 토글 버튼: pressed 신호 때 이미 눌림 상태가 바뀌어 있음
	b.toggle_mode = true
	b.custom_minimum_size.y = 62
	parent.add_child(b)
	bigs[id] = b
	var pane := PanelContainer.new()
	pane.add_theme_stylebox_override("panel", S.pane(false))
	pane.add_child(body)
	pane.visible = false
	parent.add_child(pane)
	panes[id] = pane


# 한 번에 하나만 펼침 (null 이면 다 접음). 펼치면 그 안 글자 칸에 커서
func open(which) -> void:
	for id in bigs:
		bigs[id].set_pressed_no_signal(id == which)
		panes[id].visible = id == which
	if which == "create":
		room_name.grab_focus()
	elif which == "code":
		room_code.grab_focus()


func _nick() -> String:
	return nick.text.strip_edges()


func _create() -> void:
	msg.text = ""
	Store.create_room(room_name.text, _nick())


func _join(code: String) -> void:
	msg.text = ""
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
		c.queue_free()
	if rooms.is_empty():
		list_box.add_child(_note("공개된 방 없음. 친구에게 코드나 링크를 받거나 방을 만드세요"))
		return
	for r in rooms:
		var row := HBoxContainer.new()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(S.label(str(r.name), 18, Color.WHITE))
		var bots := " + 봇 %d" % int(r.bots) if float(r.get("bots", 0)) > 0 else ""
		var mode: String = C.MODE_NAMES.get(str(r.get("mode", "survival")), "생존")
		var map_name: String = C.MAPS[str(r.map)].name if C.MAPS.has(str(r.get("map", ""))) else ("무작위" if str(r.get("map", "")) == "random" else str(r.get("map", "")))
		info.add_child(S.label("사람 %d%s / %d명 · %s · 맵 %s%s · %s" % [int(r.humans), bots, int(r.max), mode, map_name, " · 하늘 계단" if r.get("skyStairs", false) else "", "팀전" if r.get("teamMode", false) else "개인전"], 12, Color("a49cbc")))
		row.add_child(info)
		var is_full: bool = float(r.humans) + float(r.get("bots", 0)) >= float(r.max)
		var code_s := str(r.code)
		var b := S.button("꽉 참" if is_full else "들어가기", func(): _join(code_s), "go", 16)
		b.disabled = is_full
		row.add_child(b)
		list_box.add_child(row)
