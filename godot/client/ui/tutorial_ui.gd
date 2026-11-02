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
var txt := RichTextLabel.new() # 단계 문구 (JS .txt: 19px, 키 글자 노랑, max-width 640 에서 줄바꿈 — 예전엔 글 조각을 한 줄로 이어 960 에서 화면 밖)
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
	done_sum = _text("", 16, S.TEXT, true)
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
	band.add_theme_constant_override("separation", -12) # JS .prog margin-right -12 · .ok margin-left -12 (사선끼리 겹침)
	top.add_child(band)
	prog = _chip("", Color("ffe98a").lerp(Color("ffc21e"), 0.5), Color("171b2c"), [16, 18]) # JS #ffe98a→#ffc21e, padding 9 18 9 16
	band.add_child(prog.get_parent())
	var tp := PanelContainer.new()
	var tb := _box(Color("1b2448"), [26, 26]) # JS .txt padding 9 26
	tp.add_theme_stylebox_override("panel", tb)
	txt.bbcode_enabled = true
	txt.fit_content = true
	txt.scroll_active = false
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.add_theme_font_size_override("normal_font_size", 19)
	txt.add_theme_color_override("default_color", S.TEXT)
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tp.add_child(txt)
	band.add_child(tp)
	ok_lab = _chip("해냄!", Color("5ef09a").lerp(Color("1fa85a"), 0.5), Color("062611"), [20, 20])
	band.add_child(ok_lab.get_parent())
	var gap := Control.new() # JS #tut-skip-step margin-left 8 (+ 겹침 12 되돌림)
	gap.custom_minimum_size.x = 20
	band.add_child(gap)
	var skip := S.button("", func(): Store.send_room({"type": "tutorialSkip"}), "ghost", 13)
	skip.name = "SkipStep"
	skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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


func _text(t: String, size := 14, color := S.DIM, disp := false) -> Label:
	var l := S.label(t, size, color) if disp else S.body_label(t, size, color) # JS #tutorial .box system-ui (#tut-sum 만 disp)
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


# 띠 칸: JS clip-path polygon(12px 0, 100% 0, calc(100% − 12px) 100%, 0 100%) = 다른 HUD 칸과 같은 '/' 사선 12px (높이 ~42 → 0.29) + 그림자 0 5px 0 (.45).
# 예전엔 -SKEW 라 튜토리얼 띠만 반대로 기울었음
func _box(c: Color, lr := [18, 18]) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.content_margin_left = lr[0]
	s.content_margin_right = lr[1]
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	s.skew = Vector2(0.29, 0)
	s.anti_aliasing = true
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 1
	s.shadow_offset = Vector2(0, 5)
	return s


func _chip(t: String, bg: Color, fg: Color, lr := [18, 18]) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(bg, lr))
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
	var bb := ""
	var plain := ""
	for part in TC.step_parts(str(step.text), ch, _key_name, func(ids): return Keys.group_label(PlayerInput.binds, ids)):
		var tx := str(part.text).replace("[", "[lb]")
		bb += ("[color=#%s] %s [/color]" % [S.ACCENT.to_html(false), tx]) if part.key else tx # JS .k: 노랑, padding 0 3px
		plain += (" %s " % part.text) if part.key else str(part.text)
	txt.text = bb
	# 폭: 글 한 줄 폭, 최대 640 (JS max-width) 이고 띠 전체가 화면 − 40 안 (JS #tut-band max-width calc(100vw − 40px))
	var vw: float = get_viewport().get_visible_rect().size.x if get_viewport() != null else 1280.0
	var one: float = txt.get_theme_font("normal_font").get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 4.0
	var others: float = prog.get_parent().get_combined_minimum_size().x + 300.0 # 진행 칸 + 해냄 + 넘기기 자리
	txt.custom_minimum_size.x = clampf(minf(one, 640.0 - 52.0), 120.0, maxf(120.0, vw - 40.0 - others))
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
