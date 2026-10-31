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
var stage_3d: SubViewportContainer # 큰 3D 캐릭터 (char_stage.gd)
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
var code_label: Label
var room_text: Label
var public_btn: Button
var keys_text: Label
var picked_at := -100000.0 # 캐릭터 고른 시각 (ms) — 큰 캐릭터 도발·돎 (G2 몸이 오면)
var rolling := false
var colors_key := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", S.pane())
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	status = S.glow_label("", 18, Color.WHITE, 5)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(status)
	hint = S.label("처음이면  WASD 이동 · Space 점프 (공중에서 한 번 더) · Shift 대시 · 좌클릭 밀기 · F 스킬 · R 필살기 — 밀어서 떨어뜨리기", 11, S.TEXT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

	# 캐릭터 고르기: 왼쪽 큰 캐릭터 (누르면 스킬 카드), 오른쪽 3×3 카드 (8명 + 랜덤)
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 10)
	col.add_child(pick)
	stage = PanelContainer.new()
	stage.custom_minimum_size = Vector2(130, 200)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(1, 1, 1, 0.035)
	sbox.border_color = S.alpha(S.g(), 0.22)
	sbox.set_border_width_all(1)
	sbox.skew = Vector2(S.SKEW * 0.5, 0)
	stage.add_theme_stylebox_override("panel", sbox)
	var sv := VBoxContainer.new()
	stage.add_child(sv)
	var skill_btn := S.button("스킬 보기", func(): skill_card.visible = not skill_card.visible, "ghost", 12)
	skill_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sv.add_child(skill_btn)
	stage_box = ColorRect.new() # G2 몸 SubViewport 자리
	stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_box.custom_minimum_size = Vector2(60, 120)
	sv.add_child(stage_box)
	stage_img = _tex_rect()
	stage_box.add_child(stage_img)
	stage_3d = load("res://ui/char_stage.gd").new()
	stage_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_box.add_child(stage_3d)
	stage_who = S.glow_label("", 22, Color.WHITE, 5)
	stage_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(stage_who)
	stage.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			skill_card.visible = not skill_card.visible)
	pick.add_child(stage)
	cards = GridContainer.new()
	cards.columns = 3
	cards.add_theme_constant_override("h_separation", 5)
	cards.add_theme_constant_override("v_separation", 5)
	pick.add_child(cards)
	for c in C.CHARACTERS:
		var id := str(c)
		card_btns[id] = _card(C.CHAR_NAMES[id], func(): _choose(id))
	card_btns["random"] = _card("랜덤", _roll_random)

	skill_card = PanelContainer.new()
	skill_card.add_theme_stylebox_override("panel", S.pane(false))
	skill_text = RichTextLabel.new()
	skill_text.bbcode_enabled = true
	skill_text.fit_content = true
	skill_text.add_theme_font_size_override("normal_font_size", 13)
	skill_card.add_child(skill_text)
	skill_card.visible = false
	col.add_child(skill_card)

	# 이름 · 색
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_child(S.label("이름", 14, Color("b9b0d2")))
	name_edit = S.line_edit("머리 위에 보임", 14, int(C.NAME_MAX_LEN))
	name_edit.custom_minimum_size.x = 150
	name_edit.text_submitted.connect(func(_t): _submit_name())
	name_edit.focus_exited.connect(_submit_name)
	name_row.add_child(name_edit)
	col.add_child(name_row)
	swatches = HBoxContainer.new()
	swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	swatches.add_theme_constant_override("separation", 3)
	col.add_child(swatches)

	start_btn = S.button("시작 (Enter)", func(): Store.send_room({"type": "start"}), "go", 30)
	start_btn.custom_minimum_size.y = 56
	col.add_child(start_btn)

	# 방 설정 (호스트): 작은 글씨 한 묶음
	settings_box = HFlowContainer.new()
	settings_box.alignment = FlowContainer.ALIGNMENT_CENTER
	settings_box.add_theme_constant_override("h_separation", 8)
	settings_box.add_child(S.glow_label("방 설정", 13, S.g().lerp(Color.WHITE, 0.5), 2))
	add_bot = S.button("봇 추가", func(): Store.send_room({"type": "addBot"}), "ghost", 13)
	remove_bot = S.button("봇 빼기", func(): Store.send_room({"type": "removeBot"}), "ghost", 13)
	settings_box.add_child(add_bot)
	settings_box.add_child(remove_bot)
	mode_sel = _select("모드", ["survival", "master", "kills"], func(id): return C.MODE_NAMES[id], func(id): Store.send_room({"type": "setMode", "mode": id}))
	level_sel = _select("봇", ["easy", "normal", "hard"], func(id): return BOT_LEVEL_KO[id], func(id): Store.send_room({"type": "botLevel", "level": id}))
	map_sel = _select("맵", ["random"] + Array(C.MAP_IDS), func(id): return "무작위" if id == "random" else C.MAPS[id].name, func(id): Store.send_room({"type": "setMap", "map": id}))
	sky_box = _check("하늘 계단", func(on): Store.send_room({"type": "skyStairs", "on": on}))
	hp_box = _check("체력전", func(on): Store.send_room({"type": "hpMode", "on": on}))
	col.add_child(settings_box)
	mode_info = S.label("", 12, Color("a49cbc"))
	mode_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(mode_info)

	# 방 코드 줄
	var room_row := HFlowContainer.new()
	room_row.alignment = FlowContainer.ALIGNMENT_CENTER
	room_row.add_theme_constant_override("h_separation", 6)
	room_row.add_child(S.label("방", 13, Color("a49cbc")))
	code_label = S.glow_label("", 19, Color.WHITE, 4)
	room_row.add_child(code_label)
	room_text = S.label("", 13, Color("a49cbc"))
	room_row.add_child(room_text)
	public_btn = S.button("공개로", func(): Store.send_room({"type": "setPublic", "on": not Store.room.get("public", false)}), "ghost", 13)
	room_row.add_child(public_btn)
	room_row.add_child(S.button("링크 복사", _copy_link, "ghost", 13))
	room_row.add_child(S.button("방 나가기", func(): Store.leave(), "ghost", 13))
	col.add_child(room_row)

	var keys_row := HBoxContainer.new()
	keys_row.add_child(S.button("설정", func(): open_settings.emit(), "ghost", 13))
	var keys_btn := S.button("조작법", func(): keys_text.visible = not keys_text.visible, "ghost", 13)
	keys_row.add_child(keys_btn)
	col.add_child(keys_row)
	keys_text = S.label("WASD 이동 · Space 점프 (공중에서 한 번 더) · Shift 대시 · F 스킬 · R 필살기 · 좌클릭 평타 · 우클릭 아이템 · Q/E 방향 · G 이모트 · V 시점 · H 조작법", 12, Color("cdd5ee"))
	keys_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys_text.visible = false
	col.add_child(keys_text)

	Store.joined.connect(func(_r, _re): _on_joined())


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
	pair.add_child(S.label(label_text, 13, Color("b9b0d2")))
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 13)
	for i in ids.size():
		o.add_item(name_of.call(ids[i]), i)
		o.set_item_metadata(i, ids[i])
	o.item_selected.connect(func(i): on_pick.call(o.get_item_metadata(i)))
	pair.add_child(o)
	settings_box.add_child(pair)
	return o


func _check(text: String, on_toggle: Callable) -> CheckBox:
	var b := CheckBox.new()
	b.text = text
	S.style_check(b, 13)
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
	var code := str(Store.room.get("code", ""))
	var link := str(Store.room.get("link", "")) if Store.room.get("link") else "%s?room=%s" % [Net.url.replace("ws://", "http://").replace("wss://", "https://"), code]
	DisplayServer.clipboard_set(link)


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
		text = "라운드 %d 종료" % int(st.round.n)
	status.text = text
	hint.visible = str(Prefs.get_value("tutorial", "")) != "done"
	_key_texts(bool(st.get("itemsEnabled", C.ITEMS_ENABLED)))
	start_btn.visible = host and st.get("canStart", false)
	start_btn.text = "재시작 (Enter)" if st.phase == "over" else "시작 (Enter)"
	settings_box.visible = host
	add_bot.disabled = n >= min(C.MAX_PLAYERS, C.SPAWN_POINTS.size())
	remove_bot.disabled = not st.players.any(func(p): return p.get("isBot", false))
	_set_select(mode_sel, st.get("mode", "survival"))
	_set_select(level_sel, st.get("botLevel", "normal"))
	if st.has("map"):
		_set_select(map_sel, st.map.choice)
	sky_box.set_pressed_no_signal(bool(st.get("skyStairs", false)))
	hp_box.set_pressed_no_signal(bool(st.get("hpMode", false)))
	mode_info.text = _mode_desc(str(st.get("mode", "survival")))
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
	stage_box.color = Color(0, 0, 0, 0) if live or big != null else my_col
	for id in C.CHARACTERS:
		var b: Button = card_btns[str(id)]
		var t := Portrait.tex(str(id), my_col, 128, true)
		if b.icon != t:
			b.icon = t
	if ch != "":
		skill_text.text = "[font_size=20][b]%s[/b][/font_size]\n%s\n[b]F[/b] %s — %s\n[b]R[/b] %s — %s" % [C.CHAR_NAMES[ch], C.CHAR_INTRO.get(ch, ""), C.SKILL_NAMES[ch], C.SKILL_DESC.get(ch, ""), C.ULT_NAMES[ch], C.ULT_DESC.get(ch, "")]
	if not name_edit.has_focus():
		name_edit.text = str(me.get("nick", ""))
	_render_colors(st, me)
	# 방 코드
	code_label.text = str(Store.room.get("code", ""))
	room_text.text = "· %s · %s" % [str(Store.room.get("name", "")), "공개 (목록에 보임)" if Store.room.get("public", false) else "비공개"]
	public_btn.visible = host
	public_btn.text = "비공개로" if Store.room.get("public", false) else "공개로"
	# 폭: 오른쪽에 붙임
	var vw := get_viewport_rect().size
	var dock := U.lobby_dock(vw.x)
	custom_minimum_size.x = dock.w
	size.x = dock.w
	position.x = dock.left
	position.y = max(84.0, (vw.y - size.y) / 2.0 + 28.0)


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
	swatches.add_child(S.label("색", 13, Color("a49cbc")))
	for i in C.PLAYER_PALETTE.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(18, 18)
		b.focus_mode = Control.FOCUS_NONE
		var s := StyleBoxFlat.new()
		s.bg_color = Coords.color(C.PLAYER_PALETTE[i])
		s.skew = Vector2(S.SKEW, 0)
		var mine: bool = me.get("color") != null and int(me.color) == i
		s.border_color = S.g() if mine else Color(1, 1, 1, 0.22)
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
