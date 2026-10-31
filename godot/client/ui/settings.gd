# 설정 창 (JS #settings): 마우스 감도·효과음·음악 (View.settings), 그래픽 낮춤·움직임 줄이기, 조작 키 (core/keys.gd — 칸을 누르고 키·마우스 버튼, Esc 취소,
# 겹치면 빨강), 키 기본값·기본값·닫기, 방 안이면 '방 나가기' (판 중이면 한 번 더 — ui_calc.leave_needs_confirm, LEAVE_CONFIRM_MS)
extends Control

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const U := preload("res://ui/ui_calc.gd")
const Keys := preload("res://core/keys.gd")

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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", S.pane())
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = 460
	box.add_child(v)
	var h := S.glow_label("설정", 30, Color.WHITE, 6)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	# 이름·범위·글은 JS index.html #settings · main.js fields/checks 그대로 (View.settings 이름 = JS 이름)
	_slider(v, "마우스 감도", "sens", 0.3, 3.0, 0.1, func(x): return "%.1f배" % x)
	_slider(v, "효과음", "sfx", 0.0, 1.0, 0.05, func(x): return "%d%%" % int(round(x * 100)))
	_slider(v, "음악", "music", 0.0, 1.0, 0.05, func(x): return "%d%%" % int(round(x * 100)) if x > 0 else "끔")
	_slider(v, "시야각", "fov", 60.0, 100.0, 1.0, func(x): return "%d°" % int(round(x)))
	_check(v, "그림자", "shadows", "켜기 (느리면 끄기)")
	_check(v, "외곽선", "outline", "켜기 (느리면 끄기)")
	_check(v, "그래픽 낮춤", "lowGfx", "켜기 (해상도·배경 장식 줄임)")
	_check(v, "시점", "third", "3인칭 (%s 로 바꿈)" % Keys.key_label(PlayerInput.binds.get("view", "KeyV")))
	_check(v, "움직임 줄이기", "reducedMotion", "켜기 (전환·반짝임 줄임)")
	var kh := HBoxContainer.new()
	kh.add_child(S.glow_label("조작 키", 16, Color.WHITE, 3))
	kh.add_child(S.button("키 기본값", _reset_keys, "ghost", 13))
	v.add_child(kh)
	v.add_child(S.label("칸을 누르고 바꿀 키나 마우스 버튼(옆 버튼도)을 누름 · Esc 취소", 13, Color("bbbbbb")))
	var scroll := ScrollContainer.new()
	keys_scroll = scroll
	keys_grid = GridContainer.new()
	keys_grid.columns = 2
	keys_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(keys_grid)
	v.add_child(scroll)
	var group := ""
	for a in Keys.ACTIONS:
		if a.group != group:
			group = a.group
			keys_grid.add_child(S.glow_label(group, 14, S.g().lerp(Color.WHITE, 0.5), 2))
			keys_grid.add_child(Control.new())
		var l := S.label(a.label, 13, S.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys_grid.add_child(l)
		var id: String = a.id
		var b := S.button("", func(): _listen(id), "ghost", 13)
		b.custom_minimum_size.x = 140
		key_btns[id] = b
		keys_grid.add_child(b)
	dup_label = S.label("", 13, Color("ff8a78"))
	v.add_child(dup_label)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	leave_btn = S.button("방 나가기", _leave, "ghost", 15)
	leave_btn.add_theme_color_override("font_color", Color("ffd6cc"))
	btns.add_child(leave_btn)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(gap)
	btns.add_child(S.button("튜토리얼", func(): open_tutorial.emit(), "ghost", 15))
	btns.add_child(S.button("기본값", _reset_settings, "ghost", 15))
	btns.add_child(S.button("닫기", func(): visible = false, "ghost", 15))
	v.add_child(btns)
	leave_note = S.label("판 중엔 나가면 이 판은 패배 — 한 번 더 누르면 나감", 13, Color("ff9a84"))
	leave_note.visible = false
	v.add_child(leave_note)
	visible = false
	visibility_changed.connect(_on_shown)


func _slider(parent: Node, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var row := HBoxContainer.new()
	var l := S.label(text, 15, S.TEXT)
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	row.add_child(sl)
	var val := S.label("", 14, S.TEXT)
	val.custom_minimum_size.x = 56
	row.add_child(val)
	sl.value_changed.connect(func(x):
		val.text = fmt.call(x)
		View.set_setting(key, x))
	sliders[key] = [sl, val, fmt]
	parent.add_child(row)


func _check(parent: Node, text: String, key: String, note: String) -> void:
	var row := HBoxContainer.new()
	var l := S.label(text, 15, S.TEXT)
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var c := CheckBox.new()
	c.text = note
	S.style_check(c, 14)
	c.toggled.connect(func(on): View.set_setting(key, on))
	row.add_child(c)
	checks[key] = c
	parent.add_child(row)


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
	# 키 목록은 남는 높이만큼 (960×540 에서도 창이 화면 안)
	keys_scroll.custom_minimum_size.y = clampf(get_viewport_rect().size.y - 480.0, 90.0, 260.0)
	leave_note.visible = false
	leave_armed_at = -100000.0
	_show_binds()


func _show_binds() -> void:
	var dup := Keys.conflicts(PlayerInput.binds)
	for id in key_btns:
		var b: Button = key_btns[id]
		b.text = "키를 누르세요…" if listening == id else Keys.key_label(PlayerInput.binds.get(id, ""))
		b.modulate = Color(1, 0.6, 0.55) if dup.has(PlayerInput.binds.get(id, "")) else Color.WHITE
	var lines := []
	for code in dup:
		lines.append("%s: %s" % [Keys.key_label(code), " · ".join(dup[code].map(func(i): return _label_of(i)))])
	dup_label.text = "\n".join(lines)


func _label_of(id: String) -> String:
	for a in Keys.ACTIONS:
		if a.id == id:
			return a.label
	return id


func _listen(id: String) -> void:
	listening = id
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
	for kv in [["sens", 1.0], ["sfx", 1.0], ["music", 1.0], ["fov", C.FOV_DEFAULT], ["shadows", true], ["outline", true], ["lowGfx", false], ["third", false], ["reducedMotion", false]]:
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
		return
	visible = false
	Store.leave()
