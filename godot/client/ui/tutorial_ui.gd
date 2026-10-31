# 튜토리얼 화면 (G6, client/tutorial-ui.js 자리): 처음 켜면 묻기 → 캐릭터 고르기 → 튜토리얼 방 (판 중 진행 띠) → 끝 (봇 3명과 한 판 / 메뉴로).
# 단계 판정·지형은 서버 (server/tutorial.js), 띠 문구는 tutorial_calc.gd 로 지금 키 설정 이름을 넣어 만듦. 다 했거나 건너뛰면 Prefs tutorial = done·skipped
# 여는 곳: 메뉴·설정의 '튜토리얼' (View.open_panel "tutorial"). main.gd 가 붙임
extends CanvasLayer

const C := preload("res://core/config.gd")
const Keys := preload("res://core/keys.gd")
const S := preload("res://ui/ui_style.gd")
const Prefs := preload("res://ui/ui_prefs.gd")
const TC := preload("res://ui/tutorial_calc.gd")
const Portrait := preload("res://ui/portrait.gd")
const Coords := preload("res://core/coords.gd")

var modal := PanelContainer.new()
var panes := {} # ask·pick·done -> VBoxContainer
var pane_name := ""
var chars_box := HBoxContainer.new()
var char_btns := {}
var intro: Label
var done_title: Label
var done_sum: Label
var band := HBoxContainer.new()
var prog: Label
var txt := HBoxContainer.new()
var ok_lab: Label
var chosen: String = C.CHAR_DEFAULT
var shown_key := ""
var done_shown := false
var ask_pending := false
var quick_pending := false # '봇 3명과 한 판': 새 방이 열리면 봇을 넣고 바로 시작


func _ready() -> void:
	layer = 20
	add_to_group("ui_blocker") # ui.gd 가 blocking() 을 봄
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	modal.add_theme_stylebox_override("panel", S.pane())
	modal.custom_minimum_size = Vector2(560, 0)
	center.add_child(modal)
	var stack := VBoxContainer.new()
	modal.add_child(stack)
	# 묻기
	var ask := _pane("ask", stack, "처음이에요?")
	ask.add_child(_text("혼자 섬에서 직접 해 보는 튜토리얼 (3~5분)", 16, S.TEXT))
	ask.add_child(_text("이동·점프·대시 → 밀어서 떨어뜨리기·치명타 → 스킬·필살기·아이템 → 블록 피하고 용암 위로", 13))
	ask.add_child(_btns([["건너뛰기", _skip_all, "ghost"], ["튜토리얼 하기", func(): show_pane("pick"), "go"]]))
	# 캐릭터 고르기
	var pick := _pane("pick", stack, "캐릭터 고르기")
	pick.add_child(_text("스킬 단계는 고른 캐릭터로 해 봄 (대기실에서 언제든 바꿈)", 13))
	chars_box.add_theme_constant_override("separation", 6)
	pick.add_child(chars_box)
	for ch in C.FIGURE_CHARS:
		var b := S.button(str(C.CHAR_NAMES[ch]), choose.bind(ch), "ghost", 14)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(62, 96)
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = true
		chars_box.add_child(b)
		char_btns[ch] = b
	intro = _text("", 14, S.TEXT)
	pick.add_child(intro)
	pick.add_child(_btns([["뒤로", func(): show_pane("ask"), "ghost"], ["시작", start, "go"]]))
	# 끝
	var done := _pane("done", stack, "튜토리얼 끝!")
	done_title = done.get_child(0)
	done_sum = _text("", 16, S.TEXT)
	done.add_child(done_sum)
	done.add_child(_text("이제 진짜 판: 블록이 떨어지고, 밀고, 살아남기", 13))
	done.add_child(_btns([["메뉴로", _to_menu, "ghost"], ["봇 3명과 한 판", _quick_match, "go"]]))
	modal.visible = false
	# 진행 띠 (위 가운데)
	var top := CenterContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.position.y = 58
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	band.add_theme_constant_override("separation", 0)
	top.add_child(band)
	prog = _chip("", Color("ffd23a"), Color("171b2c"))
	band.add_child(prog.get_parent())
	var tp := PanelContainer.new()
	tp.add_theme_stylebox_override("panel", _box(Color("1b2448")))
	tp.add_child(txt)
	band.add_child(tp)
	ok_lab = _chip("해냄!", Color("36d07a"), Color("062611"))
	band.add_child(ok_lab.get_parent())
	var skip := S.button("", func(): Store.send_room({"type": "tutorialSkip"}), "ghost", 13)
	skip.name = "SkipStep"
	band.add_child(skip)
	band.visible = false
	chosen = str(Prefs.get_value("char", C.CHAR_DEFAULT))
	if not C.FIGURE_CHARS.has(chosen):
		chosen = C.CHAR_DEFAULT
	View.open_panel.connect(func(n): if n == "tutorial": open_pick())
	PlayerInput.ui_action.connect(func(id, pressed): if id == "tutSkip" and pressed and band.visible: Store.send_room({"type": "tutorialSkip"}))
	Store.joined.connect(_on_joined)
	Store.state_changed.connect(func(st, _prev): update(st))
	Store.game_event.connect(_on_event)
	# 처음 켠 사람 (아직 안 물어봄): 메뉴에서 묻기. 자동 조종·방 주소로 들어오면 안 물음
	var args := OS.get_cmdline_user_args()
	if Prefs.get_value("tutorial") == null and not args.has("--auto") and not args.has("--room"):
		ask_pending = true # 타이틀이 끝나 메뉴가 보이면 (View.title_on 이 꺼지면) 물음 (JS startTitle onDone → tut.ask)


func _pane(name: String, parent: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(S.glow_label(title, 30, Color.WHITE, 5))
	parent.add_child(v)
	panes[name] = v
	return v


func _text(t: String, size := 14, color := S.DIM) -> Label:
	var l := S.label(t, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520
	return l


func _btns(list: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_theme_constant_override("separation", 10)
	for it in list:
		h.add_child(S.button(it[0], it[1], it[2], 16))
	return h


func _box(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.skew = Vector2(-S.SKEW, 0)
	return s


func _chip(t: String, bg: Color, fg: Color) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(bg))
	var l := S.label(t, 19, fg)
	p.add_child(l)
	return l


func show_pane(name: String) -> void:
	pane_name = name
	modal.visible = true
	for k in panes:
		panes[k].visible = k == name
	if name == "pick":
		choose(chosen)
		_faces()
	PlayerInput.lock_mouse(false)


func close() -> void:
	modal.visible = false
	pane_name = ""


func blocking() -> bool:
	return modal.visible


# 메뉴·설정 '튜토리얼': 방 안이면 나와서 바로 캐릭터 고르기
func open_pick() -> void:
	if Store.in_room():
		Store.leave()
	show_pane("pick")


# 캐릭터 카드 초상 (JS portrait 120 온몸, 내 색). 다 그려지기 전이면 다음 프레임에 다시
func _faces() -> void:
	var col := Coords.color(C.PLAYER_PALETTE[int(Prefs.get_value("color", 0)) % C.PLAYER_PALETTE.size()])
	var missing := false
	for ch in char_btns:
		var t := Portrait.tex(ch, col, 120, true)
		char_btns[ch].icon = t
		missing = missing or t == null
	if missing and modal.visible and pane_name == "pick":
		get_tree().create_timer(0.3).timeout.connect(_faces)


func choose(ch: String) -> void:
	chosen = ch if C.FIGURE_CHARS.has(ch) else C.CHAR_DEFAULT
	for k in char_btns:
		char_btns[k].button_pressed = k == chosen
	intro.text = "%s — %s" % [C.CHAR_NAMES[chosen], C.CHAR_INTRO.get(chosen, "")]


func _skip_all() -> void:
	if Prefs.get_value("tutorial") != "done":
		Prefs.set_value("tutorial", "skipped")
	close()


func start() -> void:
	Prefs.set_value("tutorial", "done")
	Prefs.set_value("char", chosen) # 대기실 고른 캐릭터로도 남음
	close()
	done_shown = false
	shown_key = ""
	Net.send({"type": "tutorial", "nick": str(Prefs.get_value("name", "")), "char": chosen})


func _to_menu() -> void:
	close()
	Store.leave()


func _quick_match() -> void:
	close()
	quick_pending = true
	Store.leave()
	Store.create_room("", str(Prefs.get_value("name", "")))


func _on_joined(_room, rejoined: bool) -> void:
	if quick_pending and not rejoined and not Store.room.get("practice", false):
		quick_pending = false
		for i in int(C.TUTORIAL_BOTS):
			Store.send_room({"type": "addBot"})
		Store.send_room({"type": "start"})
	if pane_name == "ask":
		close() # 묻는 동안 방에 들어감 (링크·재접속)


func _key_name(id: String) -> String:
	return Keys.key_label(str(PlayerInput.binds.get(id, "")))


# 스냅샷마다: 튜토리얼 방이면 띠 (단계·진행·해냄), 끝이면 끝 화면
func update(st: Dictionary) -> void:
	var t = st.get("tutorial")
	if not (t is Dictionary):
		band.visible = false
		return
	if t.get("done", false):
		band.visible = false
		if not done_shown:
			done_shown = true
			var msg := TC.done_message(t.get("results"))
			done_title.text = msg.title
			done_sum.text = msg.text
			done_sum.add_theme_color_override("font_color", S.GOOD if msg.kind == "all" else S.TEXT)
			show_pane("done")
		return
	band.visible = true
	ok_lab.get_parent().visible = bool(t.get("ok", false))
	txt.modulate = Color(0.75, 0.75, 0.75) if t.get("ok", false) else Color.WHITE
	var step := TC.step_of(t.get("id"))
	var me := Store.me()
	var ch := str(me.get("char", chosen)) if not me.is_empty() else chosen
	var key := "%s|%s|%s|%s" % [t.get("i"), t.get("id"), ch, JSON.stringify(PlayerInput.binds)]
	if key == shown_key or step.is_empty():
		return
	shown_key = key
	prog.text = TC.progress_label(int(t.get("i", 0)), int(t.get("n", C.TUTORIAL_STEPS.size())))
	for c in txt.get_children():
		c.queue_free()
	for part in TC.step_parts(str(step.text), ch, _key_name, func(ids): return Keys.group_label(PlayerInput.binds, ids)):
		var l := S.label(part.text, 19, S.ACCENT if part.key else S.TEXT)
		txt.add_child(l)
	(band.get_node("SkipStep") as Button).text = "이 단계 넘기기 (%s)" % _key_name("tutSkip")


func _on_event(e: Dictionary) -> void:
	var mine: bool = e.get("who") != null and Store.my_id != null and int(e.who) == Store.my_id
	if not mine:
		return
	if e.get("type") == "tutorialOk":
		View.sound_cue.emit("ui", {"key": "clear"})
	elif e.get("type") == "tutorialDone":
		View.sound_cue.emit("ui", {"key": "win"})


func _process(_dt: float) -> void:
	if ask_pending and not View.title_on:
		ask_pending = false
		if not Store.in_room():
			show_pane("ask")
