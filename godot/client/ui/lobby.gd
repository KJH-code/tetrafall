# 대기실 판 (JS #center, 판 사이): 오른쪽에 붙음 (폭 ui_calc.lobby_dock — 가운데 맵 미리보기 섬·사람이 보이게).
# 위에서부터 상태 한 줄 → 캐릭터 고르기 (큰 캐릭터 + 3×3 카드, '스킬 보기') → 이름·색 → 시작 → '방 설정' 묶음 → 방 코드 줄 → 설정·조작법.
# 큰 캐릭터·카드 초상은 G2 몸이 나오면 SubViewport (지금은 색 상자 + 이름). 방 메시지는 server/rooms.js 그대로 (Store.send_room)
extends PanelContainer

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Keys := preload("res://core/keys.gd")
const Portrait := preload("res://ui/portrait.gd")
const U := preload("res://ui/ui_calc.gd")
const Coords := preload("res://core/coords.gd")
const Prefs := preload("res://ui/ui_prefs.gd")

signal open_settings

const BOT_LEVEL_KO := {"easy": "쉬움", "normal": "보통", "hard": "어려움"}
const TEAM_KO := {"red": "빨강", "blue": "파랑"}

var status: Label
var hint: Label
var stage: PanelContainer
var stage_who: Label
var stage_box: ColorRect
var stage_img: TextureRect # 큰 캐릭터 초상 (256 온몸 — 그래픽 낮춤·헤드리스일 때)
var stage_3d: Control # 큰 3D 캐릭터 (char_stage.gd)
var cards: GridContainer
var card_btns := {} # char id → Button ('random' 은 랜덤 칸)
var skill_card: PanelContainer
var skill_text: RichTextLabel
var name_edit: LineEdit
var swatches: HBoxContainer
var start_btn: Button
var settings_box: HFlowContainer
var add_bot: Button
var remove_bot: Button
var mode_sel: OptionButton
var level_sel: OptionButton
var map_sel: OptionButton
var sky_box: CheckBox
var hp_box: CheckBox
var mode_info: Label
var map_info: Label # 방장 아닌 사람: 판 사이에 맵·모드 (JS #map-info)
var team_note: Label # 팀전이면 색 칸 대신 '팀전은 팀 색' (JS #color-team-note)
var code_label: Label
var room_text: Label
var public_btn: Button
var keys_text: Label
var scroll: ScrollContainer # JS #center max-height calc(100vh − 92px) · overflow-y auto
var col: VBoxContainer
var skill_btn: Button
var room_link: Label # JS #room-link (11px, 작은 창이면 숨김)
var settings_wrap: PanelContainer # '방 설정' 묶음 판 (JS #bot-btns: rgba(0,0,0,.28) + 안쪽 1px gc + 사선)
var pane_box: StyleBoxFlat
var small_was = null
var picked_at := -100000.0 # 캐릭터 고른 시각 (ms) — 큰 캐릭터 도발·돎 (G2 몸이 오면)
var rolling := false
var colors_key := ""
var gaps := {} # 줄 사이 틈 (JS margin — 줄마다 다름): 이름 → [틈 Control, 1280 px, 작은 창 px]

# 줄 사이 틈 [1280, 작은 창] — JS 대기실 요소 사각형 (Playwright getBoundingClientRect, 1280×720·960×540) 에서 잰 앞 줄 끝 → 다음 줄 위
const GAP := {"hint": [4, 4], "pick": [7, 5], "name": [9, 4], "swatches": [3, 2], "team_note": [3, 2], "start": [12, 7], "settings": [12, 8],
	"map_info": [5, 5], "mode_info": [5, 5], "room": [6, 6], "room_link": [0, 0], "keys": [6, 4], "keys_text": [4, 4]}
const CARD := [Vector2(72, 63), Vector2(62, 49)] # JS .cc 폭 72 (작은 창 62), 높이 = padding 3+4 + 얼굴 42 (30) + 이름 12×1.2 (11×1.1)
const ROW_BTN_PAD := [11, 3] # JS #bot-btns button · #room-row button: 13px, padding 3 11 (두 크기 같음)
const KEYS_BTN_PAD := [12, 3] # JS #center .keys > button: 13px, padding 3 12
const SET_PAD := [[12, 7], [10, 5]] # JS #bot-btns padding 7 12 (작은 창 5 10)
const SELECT_EXTRA := 30 # JS select 폭 = 가장 긴 글 + padding 4·4 + 테두리 1·1 + 화살표 칸 ~20 (모드 89 = 글 59 + 30)


func _ready() -> void:
	visibility_changed.connect(func():
		if visible:
			_place()
			if not S.reduced():
				S.slide_in(self, 30.0)) # JS dock-in .22s (오른쪽 30px 에서)
	pane_box = S.pane()
	add_theme_stylebox_override("panel", pane_box)
	mouse_filter = Control.MOUSE_FILTER_STOP
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0) # 줄 사이는 _gap (JS 줄마다 margin 이 다름)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	status = S.glow_label("", 18, Color.WHITE, 5)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(status)
	hint = S.body_label("처음이면  WASD 이동 · Space 점프 (공중에서 한 번 더) · Shift 대시 · 좌클릭 밀기 · F 스킬 · R 필살기 — 밀어서 떨어뜨리기", 11, S.TEXT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hb := StyleBoxFlat.new() # JS #first-hint: rgba(0,0,0,.4) + 왼쪽 3px g + 사선, padding 4 14
	hb.bg_color = Color(0, 0, 0, 0.4)
	hb.border_width_left = 3
	S.theme_border(hb)
	hb.skew = Vector2(0.17, 0)
	hb.content_margin_left = 14
	hb.content_margin_right = 14
	hb.content_margin_top = 4
	hb.content_margin_bottom = 4
	hint.add_theme_stylebox_override("normal", hb)
	_add(hint, "hint")

	# 캐릭터 고르기: 왼쪽 큰 캐릭터 (누르면 스킬 카드), 오른쪽 3×3 카드 (8명 + 랜덤)
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 10)
	var pick_holder := MarginContainer.new() # 고르기 + 그 위를 덮는 스킬 카드 (JS #char-card position absolute inset 0)
	pick_holder.add_child(pick)
	_add(pick_holder, "pick")
	stage = PanelContainer.new()
	stage.custom_minimum_size = Vector2(130, 200)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(1, 1, 1, 0.035)
	S.theme_border(sbox, 0.22)
	sbox.set_border_width_all(1)
	sbox.skew = Vector2(0.045, 0) # JS --par 9px / 높이 200
	stage.add_theme_stylebox_override("panel", sbox)
	var sv := VBoxContainer.new()
	stage.add_child(sv)
	skill_btn = S.button("스킬 보기", func(): _toggle_card(), "ghost", 12) # JS #char-info-btn: 큰 캐릭터 왼쪽 위 6·6 에 겹침, padding 2 12
	for stn in ["normal", "hover", "pressed", "focus"]:
		var sb2: StyleBoxFlat = skill_btn.get_theme_stylebox(stn)
		sb2.content_margin_left = 12
		sb2.content_margin_right = 12
		sb2.content_margin_top = 2
		sb2.content_margin_bottom = 2
	stage_box = ColorRect.new() # G2 몸 SubViewport 자리
	stage_box.color = Color(0, 0, 0, 0) # 그리기 전엔 빈칸 (ColorRect 기본 흰색이 하얀 네모로 보이던 것)
	stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_box.custom_minimum_size = Vector2(60, 120)
	sv.add_child(stage_box)
	stage_box.add_child(S.radial_glow(Vector2(0.5, 0.88), 0.6, 0.42)) # JS #char-stage 아래 둥근 빛 (g 42% → 투명 60%)
	stage_img = _tex_rect()
	stage_box.add_child(stage_img)
	stage_3d = load("res://ui/char_stage.gd").new()
	stage_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_box.add_child(stage_3d)
	stage_who = S.glow_label("", 22, Color.WHITE, 5)
	stage_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(stage_who)
	stage_box.add_child(skill_btn)
	skill_btn.position = Vector2(6, 6)
	stage.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_toggle_card())
	pick.add_child(stage)
	cards = GridContainer.new()
	cards.columns = 3
	cards.add_theme_constant_override("h_separation", 5)
	cards.add_theme_constant_override("v_separation", 5)
	pick.add_child(cards)
	for c in C.CHARACTERS:
		var id := str(c)
		card_btns[id] = _card(C.CHAR_NAMES[id], func(): _choose(id))
	card_btns["random"] = _card("아무나", _roll_random) # JS .cc.random: 얼굴 자리 '랜덤' 17px 빛 글자 + 사선 줄무늬, 이름 '아무나'
	var rnd_face := S.glow_label("랜덤", 17, Color.WHITE, 3)
	rnd_face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rnd_face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rnd_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_btns.random.add_child(rnd_face)
	card_btns.random.text = "" # 버튼 글은 세로 가운데라 '아무나' 는 아래에 따로
	var rnd_nm := S.label("아무나", 12, Color("b9b0d2"))
	rnd_nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rnd_nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_btns.random.add_child(rnd_nm)
	rnd_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rnd_face.offset_top = 3
	rnd_face.offset_bottom = -20
	rnd_nm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	rnd_nm.offset_top = -20
	rnd_nm.offset_bottom = -2

	# 스킬 카드: 고르기 판 위를 덮음 (JS #char-card: 이름 22 · 소개 13 · [키 | 이름 / 설명] 표 · '닫기')
	skill_card = PanelContainer.new()
	var sc := S.pane(false)
	sc.bg_color = Color8(18, 11, 33, 250)
	sc.content_margin_left = 14
	sc.content_margin_right = 14
	sc.content_margin_top = 10
	sc.content_margin_bottom = 10
	skill_card.add_theme_stylebox_override("panel", sc)
	skill_text = RichTextLabel.new()
	skill_text.bbcode_enabled = true
	skill_text.fit_content = false
	skill_text.scroll_active = true
	skill_text.add_theme_font_size_override("normal_font_size", 13)
	S.body(skill_text) # JS #char-card .intro·.sk .d system-ui (이름·키·스킬 이름은 [font] 로 disp)
	skill_text.add_theme_font_size_override("bold_font_size", 13)
	skill_card.add_child(skill_text)
	var close := S.button("닫기", func(): _toggle_card(false), "ghost", 12)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.size_flags_vertical = Control.SIZE_SHRINK_END
	skill_card.add_child(close)
	skill_card.visible = false
	pick_holder.add_child(skill_card)

	# 이름 · 색
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_child(S.body_label("이름", 13, Color("a49cbc"))) # JS #color-row label system-ui
	name_edit = S.line_edit("머리 위에 보임", 14, int(C.NAME_MAX_LEN))
	name_edit.custom_minimum_size.x = 105 # JS #name-input 7.5em
	for stn in ["normal", "focus"]: # JS #name-input padding 3 6 + 테두리 2 → 높이 26
		var ne: StyleBoxFlat = name_edit.get_theme_stylebox(stn)
		ne.content_margin_top = 5
		ne.content_margin_bottom = 4
	name_edit.text_submitted.connect(func(_t): _submit_name())
	name_edit.focus_exited.connect(_submit_name)
	name_row.add_child(name_edit)
	_add(name_row, "name")
	swatches = HBoxContainer.new()
	swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	swatches.add_theme_constant_override("separation", 3)
	_add(swatches, "swatches")
	team_note = S.body_label("팀전은 팀 색", 12, Color("a49cbc"))
	team_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	team_note.visible = false
	_add(team_note, "team_note")

	start_btn = S.button("시작 (Enter)", func(): Store.send_room({"type": "start"}), "go", 30) # JS #start-btn: 30px · 자간 6 · padding 10 0 · 폭 92% · 사선 18px
	start_btn.custom_minimum_size.y = 56
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.add_theme_font_override("font", S.spaced(6))
	for stn in ["normal", "hover", "pressed", "focus", "disabled"]:
		(start_btn.get_theme_stylebox(stn) as StyleBoxFlat).skew = Vector2(0.32, 0)
	_add(start_btn, "start")

	# 방 설정 (호스트): 작은 글씨 한 묶음 (JS #bot-btns: 판 + '방 설정' gl 13px 자간 1)
	settings_wrap = PanelContainer.new()
	var swb := StyleBoxFlat.new()
	swb.bg_color = Color(0, 0, 0, 0.28)
	swb.set_border_width_all(1)
	S.theme_border(swb, 0.1)
	swb.skew = Vector2(0.09, 0)
	swb.content_margin_left = SET_PAD[0][0]
	swb.content_margin_right = SET_PAD[0][0]
	swb.content_margin_top = SET_PAD[0][1]
	swb.content_margin_bottom = SET_PAD[0][1]
	settings_wrap.add_theme_stylebox_override("panel", swb)
	settings_box = HFlowContainer.new()
	settings_box.alignment = FlowContainer.ALIGNMENT_CENTER
	settings_box.add_theme_constant_override("h_separation", 8)
	settings_box.add_theme_constant_override("v_separation", 5)
	settings_wrap.add_child(settings_box)
	var st_lab := S.label("방 설정", 13, Color.WHITE)
	st_lab.add_theme_font_override("font", S.spaced(1))
	settings_box.add_child(S.tint(st_lab))
	add_bot = S.pad(S.button("봇 추가", func(): Store.send_room({"type": "addBot"}), "ghost", 13), ROW_BTN_PAD[0], ROW_BTN_PAD[1])
	remove_bot = S.pad(S.button("봇 빼기", func(): Store.send_room({"type": "removeBot"}), "ghost", 13), ROW_BTN_PAD[0], ROW_BTN_PAD[1])
	settings_box.add_child(add_bot)
	settings_box.add_child(remove_bot)
	mode_sel = _select("모드", ["survival", "master", "kills"], func(id): return C.MODE_NAMES[id], func(id): Store.send_room({"type": "setMode", "mode": id}))
	level_sel = _select("봇", ["easy", "normal", "hard"], func(id): return BOT_LEVEL_KO[id], func(id): Store.send_room({"type": "botLevel", "level": id}))
	map_sel = _select("맵", ["random"] + Array(C.MAP_IDS), func(id): return "무작위" if id == "random" else C.MAPS[id].name, func(id): Store.send_room({"type": "setMap", "map": id}))
	sky_box = _check("하늘 계단", func(on): Store.send_room({"type": "skyStairs", "on": on}))
	hp_box = _check("체력전", func(on): Store.send_room({"type": "hpMode", "on": on}))
	_add(settings_wrap, "settings")
	map_info = S.body_label("", 13, Color("cdd5ee"))
	map_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_info.visible = false
	_add(map_info, "map_info")
	mode_info = S.body_label("", 12, Color("a49cbc"))
	mode_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add(mode_info, "mode_info")

	# 방 코드 줄
	var room_row := HFlowContainer.new()
	room_row.alignment = FlowContainer.ALIGNMENT_CENTER
	room_row.add_theme_constant_override("h_separation", 6)
	room_row.add_theme_constant_override("v_separation", 6) # JS #room-row gap 6 (줄 사이도)
	room_row.add_child(S.body_label("방", 13, Color("a49cbc"))) # JS #room-row system-ui (방 코드만 disp)
	code_label = S.glow_label("", 19, Color.WHITE, 4)
	code_label.add_theme_font_override("font", S.spaced(3)) # JS #room-row .code letter-spacing 3px
	room_row.add_child(code_label)
	room_text = S.body_label("", 13, Color("a49cbc"))
	room_row.add_child(room_text)
	public_btn = S.pad(S.button("공개로", func(): Store.send_room({"type": "setPublic", "on": not Store.room.get("public", false)}), "ghost", 13), ROW_BTN_PAD[0], ROW_BTN_PAD[1])
	room_row.add_child(public_btn)
	room_row.add_child(S.pad(S.button("링크 복사", _copy_link, "ghost", 13), ROW_BTN_PAD[0], ROW_BTN_PAD[1]))
	room_row.add_child(S.pad(S.button("방 나가기", func(): Store.leave(), "ghost", 13), ROW_BTN_PAD[0], ROW_BTN_PAD[1]))
	_add(room_row, "room")
	room_link = S.body_label("", 11, Color("7d7896"))
	room_link.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_link.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_add(room_link, "room_link")

	var keys_row := HBoxContainer.new()
	keys_row.add_theme_constant_override("separation", 10) # JS .keys 버튼 사이 (설정 586+46 → 조작법 642)
	keys_row.add_child(S.pad(S.button("설정", func(): open_settings.emit(), "ghost", 13), KEYS_BTN_PAD[0], KEYS_BTN_PAD[1]))
	var keys_btn := S.pad(S.button("조작법", func(): keys_text.visible = not keys_text.visible, "ghost", 13), KEYS_BTN_PAD[0], KEYS_BTN_PAD[1])
	keys_row.add_child(keys_btn)
	_add(keys_row, "keys")
	keys_text = S.body_label("WASD 이동 · Space 점프 (공중에서 한 번 더) · Shift 대시 · F 스킬 · R 필살기 · 좌클릭 평타 · 우클릭 아이템 · Q/E 방향 · G 이모트 · V 시점 · H 조작법", 12, Color("cdd5ee"))
	keys_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys_text.visible = false
	_add(keys_text, "keys_text")

	Store.joined.connect(func(_r, _re): _on_joined())


# 줄 하나 더함 + 그 위 틈 (JS margin-top). 줄이 숨으면 틈도 숨음
func _add(c: Control, gap_key: String) -> void:
	var sp := Control.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.custom_minimum_size.y = GAP[gap_key][0]
	col.add_child(sp)
	col.add_child(c)
	gaps[gap_key] = sp
	sp.visible = c.visible
	c.visibility_changed.connect(func(): sp.visible = c.visible)


func _toggle_card(on = null) -> void:
	var show: bool = (not skill_card.visible) if on == null else bool(on)
	skill_card.visible = show
	skill_btn.text = "스킬 닫기" if show else "스킬 보기" # JS toggleCharCard
	if show and not S.reduced():
		S.slide_in(skill_card, -30.0)


func _link() -> String:
	var code := str(Store.room.get("code", ""))
	return str(Store.room.get("link", "")) if Store.room.get("link") else "%s?room=%s" % [Net.url.replace("ws://", "http://").replace("wss://", "https://").trim_suffix("/") + "/", code]


func _tex_rect() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _card(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.text = text
	b.custom_minimum_size = Vector2(72, 66)
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	S.style_button(b, "ghost", 12)
	b.pressed.connect(cb)
	cards.add_child(b)
	return b


func _select(label_text: String, ids: Array, name_of: Callable, on_pick: Callable) -> OptionButton:
	# 이름표와 고르기를 한 묶음으로 (줄이 넘어가도 둘이 떨어지지 않게)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 3)
	pair.add_child(S.body_label(label_text, 13, Color("b9b0d2"))) # JS #bot-btns label system-ui
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 13)
	# JS select: 13px, padding 2 4, 바탕 rgba(0,0,0,.45) + 1px gb — 기본 테마 (넓은 여백·회색) 대신
	for stn in ["normal", "hover", "pressed", "focus", "disabled"]:
		var ob := StyleBoxFlat.new()
		ob.bg_color = Color(0, 0, 0, 0.45) if stn != "hover" else Color(0.08, 0.05, 0.14, 0.7)
		ob.set_border_width_all(1)
		S.theme_border(ob, 0.22 if stn != "hover" else 0.55)
		ob.content_margin_left = 4
		ob.content_margin_right = 4
		ob.content_margin_top = 2
		ob.content_margin_bottom = 2
		o.add_theme_stylebox_override(stn, ob)
	o.add_theme_constant_override("arrow_margin", 3)
	o.add_theme_constant_override("h_separation", 2)
	o.fit_to_longest_item = false # 고도는 가장 긴 글을 기본 글자 크기 (16) 로 재서 넓음 → 직접 (JS select 폭)
	var longest := 0.0
	for i in ids.size():
		o.add_item(name_of.call(ids[i]), i)
		o.set_item_metadata(i, ids[i])
		longest = maxf(longest, S.FONT.get_string_size(str(name_of.call(ids[i])), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	o.custom_minimum_size.x = ceilf(longest) + SELECT_EXTRA
	o.item_selected.connect(func(i): on_pick.call(o.get_item_metadata(i)))
	pair.add_child(o)
	settings_box.add_child(pair)
	return o


func _check(text: String, on_toggle: Callable) -> CheckBox:
	var b := CheckBox.new()
	b.text = text
	S.body(S.style_check(b, 13))
	b.toggled.connect(on_toggle)
	settings_box.add_child(b)
	return b


# 들어오면: 기억한 이름·색·캐릭터를 서버에 (JS main.js welcome)
func _on_joined() -> void:
	var nm := str(Prefs.get_value("name", ""))
	if nm != "":
		Store.send_room({"type": "setName", "name": nm})
	var col = Prefs.get_value("color")
	if col != null:
		Store.send_room({"type": "setColor", "color": int(col)})
	var ch = Prefs.get_value("char")
	if ch != null and C.CHARACTERS.has(ch):
		Store.send_room({"type": "setChar", "char": ch})


func _submit_name() -> void:
	var t := name_edit.text.strip_edges()
	Prefs.set_value("name", t)
	if t != str(Store.me().get("nick", "")):
		Store.send_room({"type": "setName", "name": t})


func _choose(c: String) -> void:
	if rolling:
		return
	Prefs.set_value("char", c)
	picked_at = Time.get_ticks_msec()
	Store.send_room({"type": "setChar", "char": c})


# '랜덤': 불이 카드 사이를 돌다 멈춤 (ui_calc.random_reel — JS rollRandom)
func _roll_random() -> void:
	if rolling:
		return
	var reel := U.random_reel(Array(C.CHARACTERS), Store.me().get("char"), func(): return randf())
	rolling = true
	for st in reel.steps:
		get_tree().create_timer(st.at / 1000.0).timeout.connect(func(): _light(st.char))
	get_tree().create_timer(C.CHAR_RANDOM_MS / 1000.0 + 0.05).timeout.connect(func():
		rolling = false
		_choose(reel.pick))


func _light(c: String) -> void:
	for id in card_btns:
		card_btns[id].set_pressed_no_signal(id == c)


func _copy_link() -> void:
	DisplayServer.clipboard_set(_link())


# 매 프레임 (ui.gd 가 부름): 스냅샷을 보고 판 내용 맞춤
func refresh(st: Dictionary) -> void:
	var me := Store.me()
	var host: bool = st.get("hostId") == Store.my_id
	var n: int = st.players.size()
	var max_p: int = int(C.MAX_PLAYERS)
	var text := ""
	if st.phase == "lobby":
		if not st.get("canStart", false):
			text = "플레이어 대기 중 (%d명, 최소 %d명)%s" % [n, int(C.MIN_PLAYERS), " · 혼자면 '봇 추가'" if host else ""]
		elif host:
			text = "%d명 접속 (최대 %d명) · 더 기다리거나 시작" % [n, max_p]
		else:
			text = "%d명 접속. 호스트가 시작하길 기다리는 중" % n
	else:
		var wt = st.round.get("winnerTeam")
		var names := []
		for wid in st.round.get("winnerIds", []):
			var wp := Store.player(wid)
			if not wp.is_empty():
				names.append(str(wp.get("nick", "")) if str(wp.get("nick", "")) != "" else str(wp.get("name", "?")))
		text = "라운드 %d 종료\n승자: %s" % [int(st.round.n), ("%s팀" % TEAM_KO.get(str(wt), "")) if wt != null and str(wt) != "" else (", ".join(names) if not names.is_empty() else "무승부")] # JS: 승자 줄
	status.text = text
	var small := U.small(get_viewport_rect().size)
	hint.visible = st.phase == "lobby" and str(Prefs.get_value("tutorial", "")) != "done" and not small # JS: 대기실에서만, 작은 창이면 숨김
	if small != small_was:
		small_was = small
		_small_sizes(small)
	_key_texts(bool(st.get("itemsEnabled", C.ITEMS_ENABLED)))
	start_btn.visible = host and st.get("canStart", false)
	start_btn.text = "재시작 (Enter)" if st.phase == "over" else "시작 (Enter)"
	settings_wrap.visible = host
	var mp = st.get("map")
	map_info.visible = mp is Dictionary and not host
	if mp is Dictionary:
		var ch := str(mp.get("choice", "random"))
		map_info.text = "맵: %s · 모드: %s%s" % ["무작위" if ch == "random" or not C.MAPS.has(ch) else str(C.MAPS[ch].name), str(C.MODE_NAMES.get(str(st.get("mode", "")), st.get("mode", ""))), " · 하늘 계단" if st.get("skyStairs", false) else ""]
	team_note.visible = bool(st.get("teamMode", false))
	add_bot.disabled = n >= min(C.MAX_PLAYERS, C.SPAWN_POINTS.size())
	remove_bot.disabled = not st.players.any(func(p): return p.get("isBot", false))
	_set_select(mode_sel, st.get("mode", "survival"))
	_set_select(level_sel, st.get("botLevel", "normal"))
	if st.has("map"):
		_set_select(map_sel, st.map.choice)
	sky_box.set_pressed_no_signal(bool(st.get("skyStairs", false)))
	hp_box.set_pressed_no_signal(bool(st.get("hpMode", false)))
	mode_info.text = _mode_desc(str(st.get("mode", "survival")))
	mode_info.visible = not small # JS 작은 창: 모드 설명은 고르는 칸으로
	room_link.text = _link()
	room_link.visible = not small
	# 캐릭터
	var ch := str(me.get("char", ""))
	if not rolling:
		_light(ch)
	stage_who.text = C.CHAR_NAMES.get(ch, "")
	var my_col := Coords.color(C.PLAYER_PALETTE[int(me.get("color", me.get("slot", 0))) % C.PLAYER_PALETTE.size()])
	# 초상 (Portrait — 다 그려지기 전·헤드리스면 null → 색 상자 그대로). 카드 = 내 색 128 온몸, 큰 캐릭터 = 256 온몸
	# 큰 캐릭터: 도는 3D (그래픽 낮춤이면 정지 초상 — JS 와 같게)
	var low := bool(View.settings.get("lowGfx", false))
	stage_3d.visible = not low
	if not low:
		stage_3d.call("show_char", ch, my_col)
	var live: bool = not low and stage_3d.call("active")
	var big: Texture2D = Portrait.tex(ch, my_col, 256, true) if not live else null
	stage_img.texture = big
	stage_img.visible = not live
	stage_box.color = Color(0, 0, 0, 0) # 3D·초상 그리기 전엔 빈칸 (색 상자 안 씀)
	for id in C.CHARACTERS:
		var b: Button = card_btns[str(id)]
		var t := Portrait.tex(str(id), my_col, 128, true)
		if b.icon != t:
			b.icon = t
	if ch != "":
		# JS fillCharCard: 이름 22 (작은 창 18) · 소개 13 #ddd8ee · 표 [키 (gl) | 이름 / 설명 #c4bdd8], 키는 설정 따라
		var gl := S.g().lerp(Color.WHITE, 0.5).to_html(false)
		var nm_fs := 18 if small else 22
		var fs := 12 if small else 13
		var row := func(k: String, nm: String, d: String) -> String:
			return "[cell padding=0,1,10,1][font=%s][color=#%s]%s[/color][/font][/cell][cell][font=%s][color=#f4f6ff]%s[/color][/font]\n[color=#c4bdd8]%s[/color][/cell]" % [S.FONT_PATH, gl, k, S.FONT_PATH, nm, d]
		skill_text.text = "[font=%s][font_size=%d]%s[/font_size][/font]\n[font_size=%d][color=#ddd8ee]%s[/color][/font_size]\n[font_size=%d][table=2]%s%s[/table][/font_size]" % [S.FONT_PATH, nm_fs, C.CHAR_NAMES[ch], fs, C.CHAR_INTRO.get(ch, ""), fs,
			row.call(Keys.key_label(str(PlayerInput.binds.get("skill", "KeyF"))), C.SKILL_NAMES[ch], C.SKILL_DESC.get(ch, "")),
			row.call(Keys.key_label(str(PlayerInput.binds.get("ult", "KeyR"))), C.ULT_NAMES[ch], C.ULT_DESC.get(ch, ""))]
	if not name_edit.has_focus() and name_edit.text != str(me.get("nick", "")): # 같은 글을 다시 넣어도 LineEdit 는 다시 그림 (W16)
		name_edit.text = str(me.get("nick", ""))
	_render_colors(st, me)
	# 방 코드
	code_label.text = str(Store.room.get("code", ""))
	room_text.text = "· %s · %s" % [str(Store.room.get("name", "")), "공개 (목록에 보임)" if Store.room.get("public", false) else "비공개"]
	public_btn.visible = host
	public_btn.text = "비공개로" if Store.room.get("public", false) else "공개로"
	_place()


# 폭: 오른쪽에 붙임 (lobby_dock). 보이는 첫 프레임부터 (스냅샷이 오기 전에도) — 첫 1~2초 왼쪽에 좁게 붙던 것
func _place() -> void:
	var vw := get_viewport_rect().size
	var dock := U.lobby_dock(vw.x)
	custom_minimum_size.x = dock.w
	size.x = dock.w
	position.x = dock.left
	# JS #center: 가운데 + 28px, 최대 높이 100vh − 92px (넘치면 판 안에서 스크롤) — 예전엔 높이 제한이 없어 960×540 에서 아래로 넘침
	var pad: float = pane_box.content_margin_top + pane_box.content_margin_bottom
	scroll.custom_minimum_size.y = minf(col.get_combined_minimum_size().y, vw.y - 92.0 - pad)
	reset_size()
	size.x = dock.w
	position.y = (vw.y - size.y) / 2.0 + 28.0
	position.y = clampf(position.y, 46.0, maxf(46.0, vw.y - size.y - 18.0))
	start_btn.custom_minimum_size.x = (dock.w - pane_box.content_margin_left - pane_box.content_margin_right) * 0.92 # JS width 92%


# 작은 창 (JS @media): 판 여백 6 12 6 18, 상태 16, 큰 캐릭터 최소 120·이름 16, 카드 62 (얼굴 30·이름 11·간격 4), 시작 22px·padding 6
func _small_sizes(small: bool) -> void:
	pane_box.content_margin_top = 6 if small else 10
	pane_box.content_margin_bottom = 6 if small else 10
	pane_box.content_margin_left = 18 if small else 22
	pane_box.content_margin_right = 12 if small else 16
	stage.custom_minimum_size = Vector2(120 if small else 130, 120 if small else 200)
	stage_box.custom_minimum_size.y = 90 if small else 120
	stage_who.add_theme_font_size_override("font_size", 16 if small else 22)
	cards.add_theme_constant_override("h_separation", 4 if small else 5)
	cards.add_theme_constant_override("v_separation", 4 if small else 5)
	for id in card_btns:
		card_btns[id].custom_minimum_size = CARD[1] if small else CARD[0]
		card_btns[id].add_theme_font_size_override("font_size", 11 if small else 12)
	start_btn.add_theme_font_size_override("font_size", 22 if small else 30)
	start_btn.custom_minimum_size.y = 36 if small else 56
	status.add_theme_font_size_override("font_size", 15 if small else 18) # JS #center-text 15px !important (작은 창)
	var sp: Array = SET_PAD[1] if small else SET_PAD[0]
	var swb: StyleBoxFlat = settings_wrap.get_theme_stylebox("panel")
	swb.content_margin_left = sp[0]
	swb.content_margin_right = sp[0]
	swb.content_margin_top = sp[1]
	swb.content_margin_bottom = sp[1]
	for k in gaps:
		gaps[k].custom_minimum_size.y = GAP[k][1] if small else GAP[k][0]


func _process(_d: float) -> void:
	if visible:
		_place()


func _set_select(o: OptionButton, id) -> void:
	for i in o.item_count:
		if o.get_item_metadata(i) == id and o.selected != i:
			o.select(i)


func _mode_desc(mode: String) -> String:
	match mode:
		"master":
			return "블록 마스터: 한 명이 하늘에서 블록만 떨어뜨리고, 나머지는 %d초 버티기 (각자 도생, 죽으면 마스터 편, 마스터는 판마다 돌아감)" % int(C.MASTER_TIME_MS / 1000)
		"kills":
			return "킬 점수전: 죽어도 %d초 뒤 부활. 킬 +1 · 자멸 -1, %d분 또는 목표 킬 (인원따라)" % [int(C.KILLS_RESPAWN_MS / 1000), int(C.KILLS_TIME_MS / 60000)]
	return "생존: 마지막까지 살아남은 사람이 승"


# 색 칸: 팔레트, 남이 쓰는 색은 흐리게·못 누름, 내 색은 빛 테두리 (팀전은 팀 색이라 숨김)
func _render_colors(st: Dictionary, me: Dictionary) -> void:
	var used := {}
	for p in st.players:
		if p.get("id") != Store.my_id and p.get("color") != null:
			used[int(p.color)] = true
	var key := "%s|%s|%s" % [str(used.keys()), str(me.get("color")), str(st.get("teamMode", false))]
	if key == colors_key:
		return
	colors_key = key
	for c in swatches.get_children():
		c.queue_free()
	swatches.visible = not st.get("teamMode", false)
	swatches.add_child(S.body_label("색", 13, Color("a49cbc")))
	for i in C.PLAYER_PALETTE.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(18, 18)
		b.focus_mode = Control.FOCUS_NONE
		var s := StyleBoxFlat.new()
		s.bg_color = Coords.color(C.PLAYER_PALETTE[i])
		s.skew = Vector2(S.SKEW, 0)
		var mine: bool = me.get("color") != null and int(me.color) == i
		if mine:
			S.theme_border(s)
		else:
			s.border_color = Color(1, 1, 1, 0.22)
		s.set_border_width_all(2)
		for stn in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(stn, s)
		b.disabled = used.has(i)
		b.modulate.a = 0.28 if used.has(i) else 1.0
		var idx := i
		b.pressed.connect(func():
			Prefs.set_value("color", idx)
			Store.send_room({"type": "setColor", "color": idx}))
		swatches.add_child(b)


# 대기실 '처음이면' 한 줄·'조작법' 글: 지금 키 설정 이름으로 (JS data-key / data-keys, refreshKeyLabels)
func _key_texts(items: bool) -> void:
	var b: Dictionary = PlayerInput.binds
	var k := func(id): return Keys.key_label(str(b.get(id, "")))
	var move := Keys.group_label(b, ["fwd", "left", "back", "right"])
	hint.text = "처음이면  %s 이동 · %s 점프 (공중에서 한 번 더) · %s 대시 · %s 밀기 · %s 스킬 · %s 필살기 — 밀어서 떨어뜨리기" % [move, k.call("jump"), k.call("dash"), k.call("attack"), k.call("skill"), k.call("ult")]
	var t := "%s 이동 · %s 점프 (공중에서 한 번 더) · %s 대시 · %s 캐릭터 스킬 · %s 필살기 (때리거나 맞으면 게이지가 참)\n%s 평타 (가까운 상대를 바라보는 쪽으로 밀어냄)\n" % [move, k.call("jump"), k.call("dash"), k.call("skill"), k.call("ult"), k.call("attack")]
	if items:
		t += "%s 든 아이템 쓰기 — 아이템은 하나만 들 수 있음 (들고 있으면 다른 걸 못 주움)\n  투사체(빨간 공) · 설치 블록(노란 상자, 조준한 곳에 1×2 를 떨어뜨림, %s 방향) · 폭탄(검은 공, 블록을 부숨)\n" % [k.call("item"), Keys.group_label(b, ["rotL", "rotR"])]
	t += "맞을수록 머리 위 피해 % 가 쌓이고 더 멀리 날아감 (대난투식)\n"
	if items:
		t += "먹자마자 효과: 초록 = 점프력 상승 · 흰 고리 = 유령화 (블록 통과, 안 깔림) · 노랑 번개 = 이속 증가\n"
	t += "블록 마스터의 마스터: %s 이동 · %s 회전 · %s 낙하\n" % [Keys.group_label(b, ["pieceUp", "pieceDown", "pieceLeft", "pieceRight"]), Keys.group_label(b, ["rotL", "rotR"]), k.call("drop")]
	t += "공중에서 떨어지면서 위에서 공중 평타를 맞히면 치명타 (피해 ×%s, 더 멀리)\n" % (str(int(C.CRIT_DAMAGE_MULT)) if float(C.CRIT_DAMAGE_MULT) == floorf(C.CRIT_DAMAGE_MULT) else str(C.CRIT_DAMAGE_MULT))
	t += "상대를 블록에 깔리게(압사) 하거나 밖으로 떨어뜨리면(낙사) 승리. 블록이 쌓이면 용암이 올라온다 — 위로!\n"
	t += "판 중에는 %s 를 누르고 있으면 조작법이 보임 · %s 1인칭 ↔ 3인칭 · 키는 설정에서 바꿈" % [k.call("help"), k.call("view")]
	keys_text.text = t
