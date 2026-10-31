# 연습 방 화면 (G6, main.js updatePractice·setPracticeOpen 자리): 연습 키 (기본 Tab) 로 왼쪽 작은 창 — 토글 (F 쿨 없음·R 가득·블록 없음·안 죽음)·내 피해·캐릭터·맵·허수아비 (추가·피해 %·삭제)·연습 나가기.
# 오른쪽엔 허수아비 콤보 기록 (진행 중 노랑, 끝나면 흰 글씨로 잠깐). 튜토리얼 방엔 없음. 창이 열리면 마우스가 풀림. main.gd 가 붙임
extends CanvasLayer

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Keys := preload("res://core/keys.gd")
const Prefs := preload("res://ui/ui_prefs.gd")

const TOGGLES := [["noCooldown", "F 쿨 없음"], ["fullUlt", "R 항상 가득"], ["noBlocks", "블록·용암 없음"], ["noDeath", "안 죽음"]]

var win := PanelContainer.new()
var checks := {}
var my_dmg := SpinBox.new()
var char_sel := OptionButton.new()
var map_sel := OptionButton.new()
var add_btn: Button
var close_btn: Button
var dummies_box := VBoxContainer.new()
var dummy_key := ""
var hint: Label
var combo := VBoxContainer.new()
var open := false
var done := {} # 허수아비 id -> 끝난 콤보 {hits, damage, dist, height, until}
var syncing := false


func _ready() -> void:
	layer = 15
	win.add_theme_stylebox_override("panel", S.pane())
	win.position = Vector2(16, 110)
	win.custom_minimum_size = Vector2(300, 0)
	add_child(win)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	win.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(S.glow_label("연습", 22, Color.WHITE, 4))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(S.button("연습 나가기", func():
		set_open(false)
		Store.leave(), "ghost", 12))
	close_btn = S.button("닫기", func(): set_open(false), "ghost", 12)
	head.add_child(close_btn)
	v.add_child(head)
	for t in TOGGLES:
		var c := S.style_check(CheckBox.new(), 14)
		c.text = t[1]
		c.toggled.connect(func(on): if not syncing: Store.send_room({"type": "practiceSet", "key": t[0], "value": on}))
		checks[t[0]] = c
		v.add_child(c)
	my_dmg.max_value = C.PRACTICE_DAMAGE_MAX
	my_dmg.step = 10
	my_dmg.suffix = "%"
	my_dmg.value_changed.connect(func(x): if not syncing: Store.send_room({"type": "practiceSet", "key": "myDamage", "value": roundi(x)}))
	v.add_child(_row("내 피해", my_dmg))
	for c in C.CHARACTERS:
		char_sel.add_item(str(C.CHAR_NAMES[c]))
		char_sel.set_item_metadata(char_sel.item_count - 1, c)
	char_sel.item_selected.connect(func(i):
		var ch: String = char_sel.get_item_metadata(i)
		Prefs.set_value("char", ch)
		Store.send_room({"type": "setChar", "char": ch}))
	v.add_child(_row("캐릭터", char_sel))
	for id in ["random"] + Array(C.MAP_IDS):
		map_sel.add_item("무작위" if id == "random" else str(C.MAPS[id].name))
		map_sel.set_item_metadata(map_sel.item_count - 1, id)
	map_sel.item_selected.connect(func(i): Store.send_room({"type": "setMap", "map": map_sel.get_item_metadata(i)}))
	v.add_child(_row("맵", map_sel))
	add_btn = S.button("추가", func(): Store.send_room({"type": "dummyAdd"}), "ghost", 13)
	v.add_child(_row("허수아비", add_btn))
	v.add_child(dummies_box)
	win.visible = false
	hint = S.label("", 13, S.TEXT)
	hint.position = Vector2(16, 110)
	add_child(hint)
	combo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	combo.position = Vector2(-300, -40)
	combo.custom_minimum_size.x = 284
	combo.alignment = BoxContainer.ALIGNMENT_END
	add_child(combo)
	PlayerInput.ui_action.connect(func(id, pressed): if id == "practice" and pressed: set_open(not open))
	Store.game_event.connect(func(e):
		if e.get("type") == "dummyCombo" and e.get("done", false):
			var d: Dictionary = e.duplicate()
			d.until = Time.get_ticks_msec() + C.PRACTICE_COMBO_SHOW_MS
			done[int(e.id)] = d)


func _row(label: String, c: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := S.label(label, 14, S.TEXT)
	l.custom_minimum_size.x = 80
	h.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	return h


# 연습 방 판 중 (튜토리얼 방 빼고)
func playing() -> bool:
	var st := Store.state
	return bool(Store.room.get("practice", false) or st.get("practice") != null) and st.get("tutorial") == null and str(st.get("phase", "")) in ["playing", "countdown"]


func set_open(on: bool) -> void:
	open = on and playing()
	win.visible = open
	PlayerInput.ui_blocking = open
	if open:
		PlayerInput.lock_mouse(false) # 마우스로 고르게 (닫고 화면을 누르면 다시 조작)


static func _name_of(p: Dictionary) -> String:
	var n := str(p.get("nick", ""))
	return n if n != "" else str(p.get("name", "허수아비"))


func _process(_dt: float) -> void:
	var on := playing()
	if on and not open and OS.get_cmdline_user_args().has("--practice-open") and not has_meta("auto_opened"): # 확인용
		set_meta("auto_opened", true)
		set_open(true)
	if not on and open:
		set_open(false)
	hint.visible = on and not open
	hint.text = "연습 창 %s" % Keys.key_label(str(PlayerInput.binds.get("practice", "Tab")))
	if not on:
		for c in combo.get_children():
			c.queue_free()
		return
	var st := Store.state
	var pr: Dictionary = st.get("practice", {}) if st.get("practice") is Dictionary else {}
	var dummies: Array = pr.get("dummies", [])
	var me := Store.me()
	if open:
		syncing = true
		for k in checks:
			checks[k].button_pressed = bool(pr.get(k, false))
		if not my_dmg.get_line_edit().has_focus():
			my_dmg.value = roundi(float(me.get("damage", 0)))
		_select(char_sel, me.get("char"))
		_select(map_sel, st.get("map", {}).get("choice") if st.get("map") is Dictionary else null)
		syncing = false
		add_btn.disabled = dummies.size() >= C.PRACTICE_DUMMY_MAX
		close_btn.text = "닫기 (%s)" % Keys.key_label(str(PlayerInput.binds.get("practice", "Tab")))
		_dummy_rows(dummies)
	# 콤보 기록
	var now := Time.get_ticks_msec()
	var lines := []
	for d in dummies:
		var c = d.get("combo")
		var tag := ("%s · " % _name_of(Store.player(d.id))) if dummies.size() > 1 else ""
		var dn = done.get(int(d.id))
		if c is Dictionary and c.get("active", false) and int(c.get("hits", 0)) > 0:
			lines.append([tag + _combo_text(c), S.ACCENT, 1.0])
		elif dn != null and now < dn.until:
			lines.append([tag + _combo_text(dn), S.TEXT, minf(1.0, (dn.until - now) / 400.0)])
	while combo.get_child_count() > lines.size():
		var x := combo.get_child(combo.get_child_count() - 1)
		combo.remove_child(x)
		x.queue_free()
	while combo.get_child_count() < lines.size():
		var l := S.label("", 18, S.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		combo.add_child(l)
	for i in lines.size():
		var l: Label = combo.get_child(i)
		l.text = lines[i][0]
		l.add_theme_color_override("font_color", lines[i][1])
		l.modulate.a = lines[i][2]


static func _combo_text(x: Dictionary) -> String:
	var h := float(x.get("height", 0))
	return "%d타 %d%% · %.1f칸%s" % [int(x.get("hits", 0)), roundi(float(x.get("damage", 0))), float(x.get("dist", 0)), (" · 높이 %.1f" % h) if h >= C.PRACTICE_SHOW_HEIGHT else ""]


func _select(o: OptionButton, id) -> void:
	if id == null or o.has_focus():
		return
	for i in o.item_count:
		if o.get_item_metadata(i) == id and o.selected != i:
			o.select(i)


# 허수아비 줄: 이름 · 피해 % · 삭제 (허수아비가 바뀔 때만 다시 만듦)
func _dummy_rows(dummies: Array) -> void:
	var key := ",".join(dummies.map(func(d): return str(d.id)))
	if key != dummy_key:
		dummy_key = key
		for c in dummies_box.get_children():
			c.queue_free()
		for d in dummies:
			var row := HBoxContainer.new()
			row.set_meta("id", int(d.id))
			var n := S.label(_name_of(Store.player(d.id)), 13, S.TEXT)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(n)
			var pct := SpinBox.new()
			pct.max_value = C.PRACTICE_DAMAGE_MAX
			pct.step = 10
			pct.suffix = "%"
			pct.value_changed.connect(func(x): if not syncing: Store.send_room({"type": "dummySet", "id": d.id, "damage": roundi(x)}))
			row.add_child(pct)
			row.add_child(S.button("삭제", func(): Store.send_room({"type": "dummyRemove", "id": d.id}), "ghost", 12))
			dummies_box.add_child(row)
	syncing = true
	for row in dummies_box.get_children():
		if row.is_queued_for_deletion():
			continue
		var pct: SpinBox = row.get_child(1)
		for d in dummies:
			if int(d.id) == int(row.get_meta("id")) and not pct.get_line_edit().has_focus():
				var p := Store.player(d.id)
				pct.value = roundi(float(d.get("damageSet", p.get("damage", 0)) if d.get("damageSet") != null else p.get("damage", 0)))
	syncing = false
