# 설정 창 (JS #settings): 마우스 감도·효과음·음악 (View.settings), 화질 (W6: 자동·높음·보통·낮음 — 낮음 = JS 그래픽 낮춤)·움직임 줄이기, 조작 키 (core/keys.gd — 칸을 누르고 키·마우스 버튼, Esc 취소,
# 겹치면 빨강), 키 기본값·기본값·닫기, 방 안이면 '방 나가기' (판 중이면 한 번 더 — ui_calc.leave_needs_confirm, LEAVE_CONFIRM_MS)
# W49: 세 탭 [일반 | 모션 | 조작 키] — 한 줄을 더하면 960×540 에서 창이 넘쳐서 (실제 글꼴로는 예전부터 35px 넘침) 탭으로 나눠 한 번에 하나만 보임, 높이는 가장 큰 탭 하나.
# '모션' 탭: 프리셋 (새·옛·최소, chars_config.gd EXT_MOTION_PRESETS) + 개별 토글 10개 (EXT_MOTION_FLAGS) — View.settings.motionFlags, 판 중에도 다음 프레임부터 적용
extends Control

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const U := preload("res://ui/ui_calc.gd")
const Keys := preload("res://core/keys.gd")
const WC := preload("res://world/world_config.gd")
const Gfx := preload("res://world/gfx.gd")
const GC := preload("res://world/gfx_calc.gd")
const UiScale := preload("res://core/ui_scale.gd")

signal open_tutorial

var box: PanelContainer
var keys_grid: GridContainer
var key_btns := {} # 행동 id → Button
var dup_label: Label
var leave_btn: Button
var leave_note: Label
var listening = null # 키를 기다리는 행동 id
var leave_armed_at := -100000.0
var sliders := {}
var checks := {}
var keys_scroll: ScrollContainer
var gfx_btns := {} # 화질 선택 (W6): "auto"·"high"·"medium"·"low" → Button
var gfx_help: Label # W32
var gfx_note: Label # 지금 실제 화질 (자동이면 무엇으로 정했는지)
const CHROME_PAD := 12.0 # 창 위아래 남길 여유 (UI 좌표)
const TAB_NAT := 300.0 # 탭 내용 높이 (UI 좌표)
const TAB_MIN := 140.0 # 탭 내용 최소 높이 (아주 짧은 창에선 이 밑으로 안 줄임 — 안은 스크롤)
const TABS := [["general", "일반"], ["motion", "모션"], ["keys", "조작 키"]]
const MOTION_ORDER := ["gait_new", "dir", "lean", "getup", "weapon", "cloth", "gaze", "land_breath", "hit_dir", "vm_arm", "pop_fix"]
const K := preload("res://chars/chars_config.gd")
var fit_h := -1.0 # 탭 높이를 맞춘 UI 좌표 높이 (UI 크기·창 크기가 바뀌면 다시)
var tab := "general"
var tab_btns := {} # 탭 id → Button
var tab_scrolls := {} # 탭 id → ScrollContainer (내용이 창보다 크면 스크롤)
var tab_boxes := {} # 탭 id → 내용 VBox
var mo_btns := {} # 모션 프리셋 id → Button
var mo_checks := {} # 모션 플래그 이름 → CheckBox
var mo_status: Label
var mo_args: Label
var stack: VBoxContainer
var scale_btns := {} # UI 크기 선택 (UiScale.label) → Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# JS #settings: radial-gradient(ellipse at 50% 45%, rgba(4,2,10,.35), rgba(0,0,0,.78)) — 예전엔 고른 .6
	var shade := S.radial_shade(Vector2(0.5, 0.45), 0.0, Color8(4, 2, 10, 89), Color(0, 0, 0, 0.78))
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = PanelContainer.new()
	var bb := S.pane() # JS #settings .box padding 20 28 22 32
	bb.content_margin_top = 20
	bb.content_margin_right = 28
	bb.content_margin_bottom = 22
	bb.content_margin_left = 32
	box.add_theme_stylebox_override("panel", bb)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = 460
	box.add_child(v)
	var h := S.glow_label("설정", 30, Color.WHITE, 6)
	h.add_theme_font_override("font", S.spaced(3)) # JS h3 letter-spacing 3px
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for t in TABS:
		var tid: String = t[0]
		var tb := S.button(str(t[1]), func(): _pick_tab(tid), "ghost", 15)
		tab_btns[tid] = tb
		tabs.add_child(tb)
	v.add_child(tabs)
	stack = VBoxContainer.new()
	v.add_child(stack)
	for t in TABS:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var tbx := VBoxContainer.new()
		tbx.add_theme_constant_override("separation", 6)
		tbx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(tbx)
		stack.add_child(sc)
		tab_scrolls[t[0]] = sc
		tab_boxes[t[0]] = tbx
	var gen: VBoxContainer = tab_boxes["general"]
	# 이름·범위·글은 JS index.html #settings · main.js fields/checks 그대로 (View.settings 이름 = JS 이름)
	_slider(gen, "마우스 감도", "sens", 0.3, 3.0, 0.1, func(x): return "%.1f배" % x)
	_slider(gen, "효과음", "sfx", 0.0, 1.0, 0.05, func(x): return "%d%%" % int(round(x * 100)))
	_slider(gen, "음악", "music", 0.0, 1.0, 0.05, func(x): return "%d%%" % int(round(x * 100)) if x > 0 else "끔")
	_slider(gen, "시야각", "fov", 60.0, 100.0, 1.0, func(x): return "%d°" % int(round(x)))
	_check(gen, "그림자", "shadows", "켜기 (느리면 끄기)")
	_check(gen, "외곽선", "outline", "켜기 (느리면 끄기)")
	_gfx_row(gen) # 예전 '그래픽 낮춤' 체크 자리: 화질 자동·높음·보통·낮음 (낮음 = 그래픽 낮춤)
	var vrow := _check(gen, "시점", "third", "3인칭 (%s 로 바꿈)" % Keys.key_label(PlayerInput.binds.get("view", "KeyV")))
	_check_in(vrow, "adaptRes", "3D 해상도 자동") # W31: 판 중 느리면 3D 해상도를 스스로 낮춤 (한 줄 더 안 늘리려고 시점 줄에)
	_check(gen, "움직임 줄이기", "reducedMotion", "켜기 (전환·반짝임 줄임)")
	_scale_row(gen)
	_motion_tab(tab_boxes["motion"])
	var kt: VBoxContainer = tab_boxes["keys"]
	var kh := HBoxContainer.new()
	var khint := S.body_label("칸을 누르고 바꿀 키나 마우스 버튼(옆 버튼도)을 누름 · Esc 취소", 13, Color("bbbbbb"))
	khint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kh.add_child(khint)
	kh.add_child(S.button("키 기본값", _reset_keys, "ghost", 13))
	kt.add_child(kh)
	var scroll := ScrollContainer.new()
	keys_scroll = scroll
	keys_grid = GridContainer.new()
	keys_grid.columns = 2
	keys_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(keys_grid)
	kt.add_child(scroll)
	var group := ""
	for a in Keys.ACTIONS:
		if a.group != group:
			group = a.group
			keys_grid.add_child(S.tint(S.glow_label(group, 14, Color.WHITE, 2)))
			keys_grid.add_child(Control.new())
		var l := S.body_label(a.label, 13, S.TEXT) # JS #keybinds 이름 system-ui (묶음 이름·키 칸은 disp)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys_grid.add_child(l)
		var id: String = a.id
		var b := S.button("", func(): _listen(id), "ghost", 13)
		b.custom_minimum_size.x = 124 # JS 9.5em, 13px · padding 2 9
		for stn in ["normal", "hover", "pressed", "focus"]:
			var kb: StyleBoxFlat = b.get_theme_stylebox(stn)
			kb.content_margin_left = 9
			kb.content_margin_right = 9
			kb.content_margin_top = 2
			kb.content_margin_bottom = 2
		key_btns[id] = b
		keys_grid.add_child(b)
	dup_label = S.body_label("", 13, Color("ff8a78"))
	kt.add_child(dup_label)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	leave_btn = S.button("방 나가기", _leave, "leave", 16) # JS button.leave: 빨강 빛 테두리 (판 중엔 한 번 더 — '정말 나가기')
	btns.add_child(leave_btn)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(gap)
	btns.add_child(S.button("튜토리얼", func(): open_tutorial.emit(), "ghost", 16)) # JS 16px
	btns.add_child(S.button("기본값", _reset_settings, "ghost", 16))
	btns.add_child(S.button("닫기", func(): visible = false, "ghost", 16))
	v.add_child(btns)
	leave_note = S.body_label("판 중엔 나가면 이 판은 패배 — 한 번 더 누르면 나감", 13, Color("ff9a84"))
	leave_note.visible = false
	v.add_child(leave_note)
	View.changed.connect(func(k): if k == "motionFlags" and is_inside_tree(): _show_motion())
	visible = false
	visibility_changed.connect(_on_shown)
	_pick_tab("general")


func _slider(parent: Node, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var row := HBoxContainer.new()
	var l := S.body_label(text, 15, S.TEXT) # JS #settings .box 15px system-ui
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	S.style_slider(sl) # JS input[type=range] accent-color: g (예전엔 기본 회색)
	row.add_child(sl)
	var val := S.body_label("", 14, S.TEXT)
	val.custom_minimum_size.x = 56
	row.add_child(val)
	sl.value_changed.connect(func(x):
		val.text = fmt.call(x)
		View.set_setting(key, x))
	sliders[key] = [sl, val, fmt]
	parent.add_child(row)


func _check(parent: Node, text: String, key: String, note: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := S.body_label(text, 15, S.TEXT)
	l.custom_minimum_size.x = 110
	row.add_child(l)
	_check_in(row, key, note)
	parent.add_child(row)
	return row


func _check_in(row: HBoxContainer, key: String, note: String) -> void:
	var c := CheckBox.new()
	c.text = note
	S.body(S.style_check(c, 14))
	c.toggled.connect(func(on): View.set_setting(key, on))
	row.add_child(c)
	checks[key] = c


# 화질 (W6): 자동·높음·보통·낮음 버튼 + 지금 실제 화질 (자동이면 내장 그래픽·창 크기로 정한 것). 고르면 View.settings.gfx → world/gfx.gd 가 적용
func _gfx_row(parent: Node) -> void:
	var row := HBoxContainer.new()
	var l := S.body_label("화질", 15, S.TEXT)
	l.custom_minimum_size.x = 110
	row.add_child(l)
	for c in WC.GFX_CHOICES:
		var id: String = c
		var b := S.button(WC.GFX_LABEL[c], func(): View.set_setting("gfx", id), "ghost", 13)
		gfx_btns[c] = b
		row.add_child(b)
	gfx_help = S.body_label("", 11, Color("bbbbbb")) # W32: 노트북 GPU 도움말 한 줄 (하이브리드를 알아내면 그 안내가 대신, 주황)
	gfx_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gfx_note = S.body_label("", 12, Color("bbbbbb"))
	gfx_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gfx_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(gfx_note)
	parent.add_child(row)
	parent.add_child(gfx_help)
	View.changed.connect(func(k): if k in ["gfx", "lowGfx"] and is_inside_tree(): _show_gfx.call_deferred())
	_show_gfx()


func _show_gfx() -> void:
	var pick := Gfx.choice if not Gfx.plan.is_empty() else GC.migrate(View.settings) # 적용 노드가 정한 선택 (확인용 --gfx 포함)
	for c in gfx_btns:
		var kind := "go" if c == pick else "ghost"
		if gfx_btns[c].get_meta("kind", "") != kind:
			gfx_btns[c].set_meta("kind", kind)
			S.style_button(gfx_btns[c], kind, 13)
	gfx_note.text = ("지금 " + GC.level_text(pick, Gfx.plan)) if not Gfx.plan.is_empty() else ""
	_show_gpu_help()


# W32: 하이브리드 노트북을 알아냈으면 그 안내 (주황), 아니면 늘 같은 도움말 한 줄. 안내는 레지스트리 조회가 끝난 뒤에 생기므로 창이 보일 때마다 다시
func _show_gpu_help() -> void:
	var warn: bool = Gfx.hint != ""
	gfx_help.text = Gfx.hint if warn else GC.GPU_HELP
	gfx_help.add_theme_color_override("font_color", Color("ffb050") if warn else Color("bbbbbb"))


# UI 크기 (W9, core/ui_scale.gd — JS 의 브라우저 확대 자리): 자동 (창 크기에 맞춤) · 80~200% 고정. 누르면 바로 바뀌고 저장
func _scale_row(parent: Node) -> void:
	var row := HBoxContainer.new()
	var l := S.body_label("UI 크기", 15, S.TEXT)
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 4)
	for c in UiScale.CHOICES:
		var choice = c
		var b := S.button(UiScale.label(c), func(): _pick_scale(choice), "ghost", 13)
		b.focus_mode = Control.FOCUS_NONE
		scale_btns[UiScale.label(c)] = b
		opts.add_child(b)
	row.add_child(opts)
	parent.add_child(row)


func _pick_scale(choice) -> void:
	View.set_setting("uiScale", choice)
	_show_scale() # (UI 좌표 높이가 바뀌면 키 목록은 _process 가 다시 맞춤)


# 고른 칸 = 주 버튼 채움 (키 칸 기다림과 같은 모양), 나머지 ghost. padding 2 8 (키 칸처럼 줄 높이를 늘리지 않게)
func _show_scale() -> void:
	var now := UiScale.label(View.settings.get("uiScale", "auto"))
	for k in scale_btns:
		var b: Button = scale_btns[k]
		var kind := "go" if k == now else "ghost"
		if b.get_meta("kind", "") == kind:
			continue
		b.set_meta("kind", kind)
		S.style_button(b, kind, 13)
		for stn in ["normal", "hover", "pressed", "focus"]:
			var kb: StyleBoxFlat = b.get_theme_stylebox(stn)
			kb.content_margin_left = 8
			kb.content_margin_right = 8
			kb.content_margin_top = 2
			kb.content_margin_bottom = 2


# W49 모션 탭: 프리셋 셋 (한 줄) + 지금 상태·도움말 + 개별 토글 10개 (2열). 고르면 바로 View.settings.motionFlags → 판 중에도 다음 프레임부터
func _motion_tab(parent: VBoxContainer) -> void:
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	for pn in ["new", "old", "min"]:
		var id: String = pn
		var b := S.button(str(K.EXT_MOTION_PRESET_NAMES[pn]), func(): View.set_setting("motionFlags", K.preset_flags(id)), "ghost", 13)
		mo_btns[pn] = b
		prow.add_child(b)
	parent.add_child(prow)
	mo_status = S.body_label("", 14, S.TEXT)
	mo_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(mo_status)
	parent.add_child(S.body_label("어색하면 '옛 모션' 으로 바꿔 비교해 보세요 (몸을 다시 만들지 않고 다음 프레임부터 바로 바뀜)", 13, Color("bbbbbb")))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in MOTION_ORDER:
		var name: String = n
		var c := CheckBox.new()
		c.text = str(K.EXT_MOTION_LABELS[name])
		S.body(S.style_check(c, 14))
		c.toggled.connect(func(on):
			var d: Dictionary = (View.settings.get("motionFlags", {}) as Dictionary).duplicate()
			d[name] = on
			View.set_setting("motionFlags", d))
		mo_checks[name] = c
		grid.add_child(c)
	parent.add_child(grid)
	mo_args = S.body_label("", 12, Color("ffb050"))
	mo_args.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(mo_args)


# 고른 프리셋 = 주 버튼 모양, 나머지 ghost (직접 고른 조합이면 아무것도 안 켜짐), 토글·상태 줄·실행 인자로 꺼진 것
func _show_motion() -> void:
	var fl = View.settings.get("motionFlags", {})
	var pn: String = K.preset_of(fl)
	for k in mo_btns:
		var kind := "go" if k == pn else "ghost"
		if mo_btns[k].get_meta("kind", "") != kind:
			mo_btns[k].set_meta("kind", kind)
			S.style_button(mo_btns[k], kind, 13)
	for n in mo_checks:
		mo_checks[n].set_pressed_no_signal(bool((fl as Dictionary).get(n, true)) if fl is Dictionary else true)
	mo_status.text = "지금: %s  ·  판 중 %s 키로 새 모션 ↔ 옛 모션 바로 전환" % [str(K.EXT_MOTION_PRESET_NAMES[pn]), Keys.key_label(PlayerInput.binds.get("motionToggle", "F6"))]
	var off: Array = K.arg_off_names()
	mo_args.text = ("실행 인자로 꺼짐 (설정보다 우선): " + " · ".join(off.map(func(n): return str(K.EXT_MOTION_LABELS[n])))) if not off.is_empty() else ""
	mo_args.visible = not off.is_empty()


func _pick_tab(id: String) -> void:
	tab = id
	for t in TABS:
		var tid: String = t[0]
		tab_scrolls[tid].visible = tid == id
		var kind := "go" if tid == id else "ghost"
		if tab_btns[tid].get_meta("kind", "") != kind:
			tab_btns[tid].set_meta("kind", kind)
			S.style_button(tab_btns[tid], kind, 15)
	if id == "motion":
		_show_motion()
	elif id == "keys":
		_show_binds()
	_fit_tabs()


# 캡처·테스트용: 탭 열기
func open_tab(id: String) -> void:
	_pick_tab(id)


func _on_shown() -> void:
	if not visible:
		listening = null
		return
	for key in sliders:
		sliders[key][0].set_value_no_signal(float(View.settings.get(key, 1.0)))
		sliders[key][1].text = sliders[key][2].call(float(View.settings.get(key, 1.0)))
	for key in checks:
		checks[key].set_pressed_no_signal(bool(View.settings.get(key, false)))
	leave_btn.visible = Store.in_room()
	_show_gfx()
	_show_scale()
	_show_motion()
	_disarm()
	_show_binds()
	_pick_tab(tab)


# 탭 높이 = TAB_NAT (일반·모션 탭이 들어가는 높이, 실제 글꼴로 잰 값 — 줄바꿈 글줄은 칸 크기가 정해지기 전엔 최소 높이를 못 믿어서 상수), 창이 짧으면 (창 − 탭 밖 틀) 만큼으로 줄임
# (넘치면 그 탭 안이 스크롤). 탭을 바꿔도 창이 안 들썩임. 키 목록은 키 탭 안에서 남는 높이를 다 씀 (안내·겹침 줄 빼고)
func _fit_tabs() -> void:
	fit_h = get_viewport_rect().size.y if is_inside_tree() else 540.0
	var chrome := box.get_combined_minimum_size().y - stack.get_combined_minimum_size().y
	var h := clampf(fit_h - CHROME_PAD - chrome, TAB_MIN, TAB_NAT)
	for t in TABS:
		(tab_scrolls[t[0]] as Control).custom_minimum_size.y = h
	var over := 66.0 # 키 탭 안 키 목록 밖 (안내 줄 31 + 겹침 줄 18 + 간격 12 + 여유)
	keys_scroll.custom_minimum_size.y = maxf(h - over, 40.0)


# '정말 나가기' 풀기 (JS disarmLeave: LEAVE_CONFIRM_MS 지나면·창을 다시 열면)
func _disarm() -> void:
	leave_note.visible = false
	leave_armed_at = -100000.0
	leave_btn.text = "방 나가기"
	S.style_button(leave_btn, "leave", 16)


func _process(_d: float) -> void:
	if visible and get_viewport_rect().size.y != fit_h:
		_fit_tabs()
	if leave_armed_at > 0.0 and Time.get_ticks_msec() - leave_armed_at > C.LEAVE_CONFIRM_MS:
		_disarm()
	# JS danger-blink .32s steps(2): 밝기 1.18 ↔ .9. 바뀔 때만 쓰고 다시 그림 알림 (W16: 구운 창은 투명도·밝기 바뀜을 draw 신호로만 앎)
	var lm := Color.WHITE
	if leave_armed_at > 0.0:
		lm = Color(1.18, 1.18, 1.18) if int(Time.get_ticks_msec() / 160) % 2 == 0 else Color(0.9, 0.9, 0.9)
	if leave_btn.modulate != lm:
		leave_btn.modulate = lm
		leave_btn.queue_redraw()


func _show_binds() -> void:
	var dup := Keys.conflicts(PlayerInput.binds)
	for id in key_btns:
		var b: Button = key_btns[id]
		b.text = "키를 누르세요 (Esc 취소)" if listening == id else Keys.key_label(PlayerInput.binds.get(id, "")) # JS showBinds
		# 기다리는 칸 = 주 버튼 채움 (JS .kb-btn.wait), 겹친 키 = 빨강 2px 테 + 글자 #ffb0a4 (.dup)
		var kind: String = "go" if listening == id else ("dup" if dup.has(PlayerInput.binds.get(id, "")) else "ghost")
		if b.get_meta("kind", "ghost") != kind: # 모양이 바뀔 때만 다시 칠함
			b.set_meta("kind", kind)
			S.style_button(b, kind, 13)
			for stn in ["normal", "hover", "pressed", "focus"]:
				var kb: StyleBoxFlat = b.get_theme_stylebox(stn)
				kb.content_margin_left = 9
				kb.content_margin_right = 9
				kb.content_margin_top = 2
				kb.content_margin_bottom = 2
	var lines := []
	for code in dup:
		lines.append("%s: %s" % [Keys.key_label(code), " · ".join(dup[code].map(func(i): return _label_of(i)))])
	dup_label.text = ("겹치는 키 (둘 다 실행됨) — %s" % " / ".join(lines)) if not lines.is_empty() else "" # JS #key-dup 한 줄
	dup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _label_of(id: String) -> String:
	for a in Keys.ACTIONS:
		if a.id == id:
			return a.label
	return id


func _listen(id: String) -> void:
	listening = null if listening == id else id # JS: 기다리는 칸을 다시 누르면 취소
	_show_binds()


# 키를 기다리는 동안은 게임보다 먼저 가로챔 (Esc = 취소)
func _input(e: InputEvent) -> void:
	if listening == null or not visible:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		get_viewport().set_input_as_handled()
		if e.physical_keycode == KEY_ESCAPE:
			listening = null
		else:
			_set_bind(listening, Keys.norm_code(Keys.event_code(e)))
		_show_binds()
	elif e is InputEventMouseButton and e.pressed:
		var code := Keys.event_code(e)
		if code != "":
			get_viewport().set_input_as_handled()
			_set_bind(listening, code)
			_show_binds()


func _set_bind(id: String, code: String) -> void:
	if code == "":
		return
	var b: Dictionary = PlayerInput.binds.duplicate()
	b[id] = code
	PlayerInput.set_binds(b)
	Keys.save_binds(b)
	listening = null


func _reset_keys() -> void:
	var b := Keys.default_binds()
	PlayerInput.set_binds(b)
	Keys.save_binds(b)
	_show_binds()


func _reset_settings() -> void:
	# JS SETTINGS_DEFAULT
	for kv in [["sens", 1.0], ["sfx", 1.0], ["music", 1.0], ["fov", C.FOV_DEFAULT], ["shadows", true], ["outline", true], ["gfx", "auto"], ["adaptRes", true], ["third", false], ["reducedMotion", false], ["uiScale", "auto"], ["motionFlags", K.preset_flags("new")]]:
		View.set_setting(kv[0], kv[1])
	_on_shown()


# 방 나가기: 판 중이면 한 번 더 (LEAVE_CONFIRM_MS 안에), 아니면 바로
func _leave() -> void:
	var me := Store.me()
	var need := U.leave_needs_confirm(Store.phase(), bool(Store.room.get("practice", false)), me.get("alive", true))
	var now := Time.get_ticks_msec()
	if need and now - leave_armed_at > C.LEAVE_CONFIRM_MS:
		leave_armed_at = now
		leave_note.visible = true
		leave_btn.text = "정말 나가기" # JS .leave.armed: 글 바뀜 + 빨강 채움 + 깜빡임
		S.style_button(leave_btn, "armed", 16)
		return
	_disarm()
	visible = false
	Store.leave()
