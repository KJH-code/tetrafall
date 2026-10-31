# 판 중 HUD (JS main.js drawHud · updatePlayers · updateScore · killFeed · updateKillsHud · updateSkills · updateCooldowns · updateSpectate):
# 밝은 예전 모양 (노랑·남색, ui_style hud_box). 아래 사람마다 초상 + 큰 % (+ 체력전 HP 막대), 위 시간·점수 띠 (킬 점수전은 목표까지 막대),
# 오른쪽 위 킬 피드, Tab(연습 창 키) 점수표, 부활 카운트다운, 스킬 F·R 칸, 조준점 둘레 대시·밀치기 쿨, 관전 안내, 카운트다운 큰 숫자
extends Control

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const U := preload("res://ui/ui_calc.gd")
const Coords := preload("res://core/coords.gd")

const CAUSE_KO := {"crush": "압사", "fall": "낙사", "lava": "용암", "hp": "체력"}
const TEAM_KO := {"red": "빨강", "blue": "파랑"}
const TEAM_COL := {"red": Color("ff5a4a"), "blue": Color("4aa8ff")}

var tally := U.KillTally.new()
var tally_round = null
var kill_events := false # 서버가 'kill' 을 보내면 피드·세기는 그것으로 (JS 와 같음)
var scores_held := false
var killed := {} # 나를 죽인 것 {by, byName, cause, weapon}

var timer_label: Label
var score_bar: HBoxContainer
var cards_row: HBoxContainer
var cards := {} # id → {panel, face, name, sub, pct, hp, bar}
var cards_key := ""
var feed: VBoxContainer
var board: PanelContainer
var board_text: RichTextLabel
var respawn: PanelContainer
var respawn_num: Label
var respawn_why: Label
var flash: ColorRect
var skills: HBoxContainer
var skill_f: Label
var skill_r: Label
var damage_label: Label
var spec_label: Label
var big: Label
var ring: Control
var dash_was := 0.0
var push_was := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label = _hud_label(26, true)
	timer_label.position = Vector2(14, 12)
	add_child(timer_label)
	score_bar = HBoxContainer.new()
	score_bar.add_theme_constant_override("separation", 6)
	var score_panel := PanelContainer.new()
	score_panel.add_theme_stylebox_override("panel", S.hud_box())
	score_panel.add_child(score_bar)
	score_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	score_panel.position.y = 12
	score_panel.name = "ScorePanel"
	add_child(score_panel)

	feed = VBoxContainer.new()
	feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed.position = Vector2(-12 - 420, 86)
	feed.size.x = 420
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	feed.add_theme_constant_override("separation", 5)
	add_child(feed)

	cards_row = HBoxContainer.new()
	cards_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(cards_row)

	skills = HBoxContainer.new()
	skills.add_theme_constant_override("separation", 8)
	skill_f = _slot()
	skill_r = _slot()
	skills.add_child(skill_f.get_parent())
	skills.add_child(skill_r.get_parent())
	add_child(skills)
	damage_label = _hud_label(54, false)
	add_child(damage_label)

	ring = Control.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.draw.connect(_draw_ring)
	add_child(ring)

	spec_label = _hud_label(15, false)
	spec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(spec_label)

	board = PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.06, 0.08, 0.16, 0.95)
	bs.border_width_left = 5
	bs.border_color = S.ACCENT
	bs.set_content_margin_all(14)
	board.add_theme_stylebox_override("panel", bs)
	board_text = RichTextLabel.new()
	board_text.bbcode_enabled = true
	board_text.fit_content = true
	board_text.custom_minimum_size.x = 520
	board_text.add_theme_font_size_override("normal_font_size", 15)
	board.add_child(board_text)
	board.visible = false
	add_child(board)

	respawn = PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.03, 0.05, 0.1, 0.84)
	rs.skew = Vector2(S.SKEW * 0.5, 0)
	rs.set_content_margin_all(12)
	respawn.add_theme_stylebox_override("panel", rs)
	var rv := VBoxContainer.new()
	rv.add_child(_center(_hud_label(18, false), "부활까지"))
	respawn_num = _center(_hud_label(96, false), "")
	respawn_num.add_theme_color_override("font_color", S.ACCENT)
	rv.add_child(respawn_num)
	respawn_why = _center(_hud_label(17, false), "")
	respawn_why.add_theme_color_override("font_color", Color("ffd6cc"))
	rv.add_child(respawn_why)
	respawn.add_child(rv)
	respawn.visible = false
	add_child(respawn)

	big = _center(_hud_label(118, false), "")
	big.visible = false
	add_child(big)

	flash = ColorRect.new()
	flash.color = Color(0.47, 0.9, 1.0, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

	Store.game_event.connect(_on_event)
	Store.state_changed.connect(_on_state)
	PlayerInput.ui_action.connect(_on_ui_action)


# 연습 창 키 (기본 Tab) 를 누르고 있는 동안 킬 점수전 점수표 (연습 방에선 G6 연습 창)
func _on_ui_action(id: String, pressed: bool) -> void:
	if id == "practice":
		scores_held = pressed


func _hud_label(size: int, accent: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", S.TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", int(max(2, size / 16)))
	if accent:
		l.add_theme_stylebox_override("normal", S.hud_box(true))
	return l


func _center(l: Label, text: String) -> Label:
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _slot() -> Label:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.05, 0.1, 0.78)
	s.border_color = Color("3c4a78")
	s.set_border_width_all(2)
	s.skew = Vector2(S.SKEW, 0)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size.x = 118
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return l


func _player_color(p: Dictionary) -> Color:
	var st := Store.state
	if st.get("teamMode", false) and TEAM_COL.has(str(p.get("team", ""))):
		return TEAM_COL[str(p.team)]
	return Coords.color(C.PLAYER_PALETTE[int(p.get("color", p.get("slot", 0))) % C.PLAYER_PALETTE.size()])


func _name(p: Dictionary) -> String:
	return str(p.get("nick", "")) if str(p.get("nick", "")) != "" else str(p.get("name", "?"))


func _kills_game(st: Dictionary) -> bool:
	return st.get("mode") == "kills" and str(st.get("phase")) in ["countdown", "playing", "over"]


# 목표 킬: 판 시작 때 서버가 인원·팀전·체력전으로 정해 스냅샷 round.killsTarget 에 (JS main.js killGoal). 없으면 0 (막대는 progress 가 1 로 나눔)
func _goal(st: Dictionary) -> int:
	var t = st.get("round", {}).get("killsTarget")
	return int(t) if t != null else 0


func _on_state(st: Dictionary, prev: Dictionary) -> void:
	if st.has("round") and st.round.n != tally_round:
		tally_round = st.round.n
		tally.reset()
	if not kill_events and st.get("events", []).any(func(e): return e.get("type") == "kill"):
		kill_events = true # 같은 묶음의 'death' 보다 먼저 알아야 두 줄이 안 뜸
	if prev.get("phase") == "countdown" and st.get("phase") == "playing":
		_big("시작!", Color("ffe14a"), 0.7)


func _on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"kill":
			if e.get("cause") == "disconnect":
				return
			var d := {"who": e.victim, "by": e.killer, "byName": e.get("killerName"), "cause": e.cause, "weapon": e.get("weapon")}
			_feed(d, tally.add({"who": e.victim, "by": e.killer, "streak": e.get("streak")}))
		"death":
			if e.who == Store.my_id:
				killed = {"by": e.get("by"), "byName": e.get("byName"), "cause": e.cause, "weapon": e.get("weapon")}
			if e.get("cause") != "disconnect" and not kill_events:
				_feed(e, tally.add(e))
		"respawn":
			if e.get("who") == Store.my_id and not Store.room.get("practice", false):
				var tw := create_tween()
				flash.color.a = 0.6
				tw.tween_property(flash, "color:a", 0.0, C.KILLS_RESPAWN_FLASH_MS / 1000.0)


# 킬 피드 한 줄: "A ▸ B 원인 (무기)" + 연속 킬. 내 킬 금빛·내 죽음 빨강
func _feed(e: Dictionary, streak: int) -> void:
	var victim := Store.player(e.who)
	var by = e.get("by")
	var row := PanelContainer.new()
	var s := StyleBoxFlat.new()
	var mine_kill: bool = by == Store.my_id and e.who != Store.my_id
	s.bg_color = Color("5a4506") if mine_kill else (Color("5a160a") if e.who == Store.my_id else Color(0.03, 0.05, 0.1, 0.8))
	s.border_width_bottom = 2 if (mine_kill or e.who == Store.my_id) else 0
	s.border_color = S.ACCENT if mine_kill else S.HOT
	s.skew = Vector2(S.SKEW, 0)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", s)
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.add_theme_font_size_override("normal_font_size", 15)
	var txt := ""
	if by != null and by != e.who:
		var killer := Store.player(by)
		var kn: String = _name(killer) if not killer.is_empty() else str(e.get("byName", "?"))
		var kc := _player_color(killer) if not killer.is_empty() else S.TEXT
		txt += "[color=#%s]%s[/color] [color=#9fabcd]▸[/color] " % [kc.to_html(false), kn]
	txt += "[color=#%s]%s[/color] [color=#9fabcd][font_size=13]%s[/font_size][/color]" % [_player_color(victim).to_html(false), _name(victim), CAUSE_KO.get(str(e.cause), str(e.cause))]
	var st_text := U.streak_text(streak)
	if st_text != "":
		txt += " [bgcolor=#ffd23a][color=#1a1300][font_size=12] %s [/font_size][/color][/bgcolor]" % st_text
	t.text = txt
	row.add_child(t)
	feed.add_child(row)
	while feed.get_child_count() > int(C.KILLFEED_MAX):
		feed.get_child(0).free()
	var tw := row.create_tween()
	tw.tween_interval(C.KILLFEED_MS / 1000.0)
	tw.tween_property(row, "modulate:a", 0.0, 0.5)
	tw.tween_callback(row.queue_free)


func _big(text: String, col: Color, secs: float) -> void:
	big.text = text
	big.add_theme_color_override("font_color", col)
	big.visible = true
	var tw := big.create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(func(): big.visible = false)


func _fmt(ms: float) -> String:
	var s := int(ceil(ms / 1000.0))
	return "%d:%02d" % [s / 60, s % 60]


# 매 프레임 (ui.gd 가 판 화면일 때 부름)
func refresh(st: Dictionary) -> void:
	var vp := get_viewport_rect().size
	var me := Store.me()
	# 위 왼쪽: 남은 시간 (블록 마스터·킬 점수전) 또는 판 시간
	var left = st.round.get("left")
	timer_label.text = " " + (_fmt(left) if left != null else _fmt(float(st.round.get("elapsed", 0)))) + " "
	# 카운트다운 큰 숫자
	if st.phase == "countdown":
		big.text = str(int(ceil(float(st.round.countdownLeft) / 1000.0)))
		big.add_theme_color_override("font_color", Color.WHITE)
		big.visible = true
	big.position = Vector2((vp.x - big.size.x) / 2.0, vp.y * 0.3 - big.size.y / 2.0)
	_score_bar(st, vp)
	_cards(st, vp)
	_skills(me, vp)
	_kills_panels(st, me, vp)
	_spectate(st, me, vp)
	ring.queue_redraw()


func _score_bar(st: Dictionary, vp: Vector2) -> void:
	for c in score_bar.get_children():
		c.free()
	var ps: Array = st.players.filter(func(p): return not p.get("spectator", false) and not p.get("dummy", false))
	var panel := get_node("ScorePanel") as PanelContainer
	var kills := _kills_game(st)
	panel.visible = ps.size() >= 2 and (kills or st.get("teamMode", false))
	if not panel.visible:
		return
	if kills and not st.get("teamMode", false):
		for r in U.top_bar(ps, Store.my_id):
			var p := Store.player(r.id)
			score_bar.add_child(_chip("%d" % int(r.rank), S.DIM, 13))
			score_bar.add_child(_chip(_name(p), _player_color(p), 18))
			score_bar.add_child(_chip("%d" % int(r.score), Color.WHITE, 18))
			score_bar.add_child(_bar(U.progress(r.score, _goal(st)), _player_color(p)))
	else:
		var ts: Dictionary = st.get("teamScores", {"red": 0, "blue": 0}) if kills else st.get("teamWins", {"red": 0, "blue": 0})
		score_bar.add_child(_chip("빨강 %d" % int(ts.get("red", 0)), TEAM_COL.red, 18))
		if kills:
			score_bar.add_child(_bar(U.progress(ts.get("red", 0), _goal(st)), TEAM_COL.red))
			score_bar.add_child(_chip(":", S.DIM, 18))
			score_bar.add_child(_bar(U.progress(ts.get("blue", 0), _goal(st)), TEAM_COL.blue))
		score_bar.add_child(_chip("%d 파랑" % int(ts.get("blue", 0)), TEAM_COL.blue, 18))
	if kills:
		score_bar.add_child(_chip("· 목표 %d킬" % _goal(st), S.DIM, 13))
	panel.position.x = (vp.x - panel.size.x) / 2.0


func _chip(text: String, col: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _bar(frac: float, col: Color) -> Control:
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.12)
	back.custom_minimum_size = Vector2(46, 6)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.color = col
	fill.size = Vector2(46 * frac, 6)
	back.add_child(fill)
	return back


# 아래 사람마다 판: 초상 (G2 전엔 색 상자) · 이름 · 캐릭터·승/킬 · 큰 % · 체력전 HP 막대 · 색 띠. 판 크기는 card_layout
func _cards(st: Dictionary, vp: Vector2) -> void:
	var live: Array = st.players.filter(func(p): return not p.get("spectator", false) and not p.get("dummy", false))
	var on: bool = live.size() >= 2 and not Store.room.get("practice", false) and str(st.phase) in ["countdown", "playing"]
	cards_row.visible = on
	if not on:
		return
	var key := JSON.stringify(live.map(func(p): return [p.id, p.get("char"), p.get("color"), p.get("team"), _name(p)]))
	if key != cards_key:
		cards_key = key
		for c in cards_row.get_children():
			c.free()
		cards.clear()
		var L := U.card_layout(live.size(), vp.x)
		cards_row.add_theme_constant_override("separation", int(L.gap))
		for p in live:
			cards[p.id] = _make_card(p, L)
	cards_row.position = Vector2((vp.x - cards_row.size.x) / 2.0, vp.y - cards_row.size.y - 10)
	var kills: bool = st.get("mode") == "kills"
	for p in live:
		var c: Dictionary = cards.get(p.id, {})
		if c.is_empty():
			continue
		var dead: bool = not p.alive and not p.get("master", false)
		c.pct.text = "KO" if dead else "%d%%" % int(p.damage)
		c.pct.add_theme_color_override("font_color", S.HOT if dead else _damage_color(float(p.damage)))
		c.panel.modulate = Color(0.6, 0.6, 0.6) if dead else Color.WHITE
		c.sub.text = "%s%s %s" % ["%s팀 · " % TEAM_KO.get(str(p.get("team", "")), "") if st.get("teamMode", false) else "", C.CHAR_NAMES.get(str(p.get("char", "")), ""), ("킬 %d" % int(p.get("score", 0))) if kills else ("승 %d" % int(p.get("wins", 0)))]
		var hp = U.hp_frac(p, st.get("hpMax")) if st.get("hpMode", false) else null
		c.hp.visible = hp != null
		if hp != null:
			c.hp_fill.size.x = c.hp.size.x * hp
			c.hp_fill.color = Color("e0300c") if hp < C.HUD_HP_LOW else Color("2fbf5a")


func _make_card(p: Dictionary, L: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	var me: bool = p.id == Store.my_id
	s.bg_color = Color(0.19, 0.24, 0.43, 0.96) if me else Color(0.09, 0.12, 0.23, 0.93)
	s.border_width_top = 4 if me else 0
	s.border_color = S.ACCENT
	s.border_width_bottom = 5
	s.skew = Vector2(S.SKEW * 0.6, 0)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", s)
	panel.custom_minimum_size.x = L.w
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	var face := ColorRect.new() # 초상 자리 (G2 몸 SubViewport)
	face.color = _player_color(p)
	face.custom_minimum_size = Vector2(38, 38) * (0.85 if L.compact else 1.0)
	top.add_child(face)
	var names := VBoxContainer.new()
	var nm := _chip(_name(p), S.TEXT, 13 if not me else 14)
	names.add_child(nm)
	var sub := _chip("", S.DIM, 11)
	sub.visible = not L.compact
	names.add_child(sub)
	top.add_child(names)
	v.add_child(top)
	var pct := _chip("", S.TEXT, int((42 if me else 34) * L.scale))
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	pct.add_theme_constant_override("shadow_offset_y", 3)
	v.add_child(pct)
	var hp := ColorRect.new()
	hp.color = Color(1, 1, 1, 0.14)
	hp.custom_minimum_size.y = 6
	var hp_fill := ColorRect.new()
	hp_fill.size.y = 6
	hp.add_child(hp_fill)
	hp.visible = false
	v.add_child(hp)
	s.border_color = S.ACCENT if me else _player_color(p) # 아래 색 띠 = 그 사람 색 (위 띠는 내 판만)
	cards_row.add_child(panel)
	return {"panel": panel, "face": face, "sub": sub, "pct": pct, "hp": hp, "hp_fill": hp_fill}


# 피해 % 색 (JS damageColor): 흰 → 노랑 → 주황 → 빨강
func _damage_color(d: float) -> Color:
	if d < 40:
		return Color.WHITE.lerp(Color("ffe14a"), d / 40.0)
	if d < 90:
		return Color("ffe14a").lerp(Color("ff8a1f"), (d - 40) / 50.0)
	return Color("ff8a1f").lerp(Color("ff3020"), clampf((d - 90) / 60.0, 0, 1))


func _skills(me: Dictionary, vp: Vector2) -> void:
	var playing: bool = Store.phase() in ["countdown", "playing"] and not me.is_empty() and me.get("alive", false) and not me.get("master", false)
	skills.visible = playing and me.get("char") != null
	damage_label.visible = playing and not cards_row.visible
	var cards_h: float = cards_row.size.y + 18 if cards_row.visible else 16
	if skills.visible:
		var ch := str(me.char)
		var cd := float(me.get("skillCd", 0))
		skill_f.text = "F  %s %s" % [C.SKILL_NAMES[ch], "%.1fs" % (cd / 1000.0) if cd > 0 else ""]
		var ult_max := float(me.get("ultMax", C.ULT_MAX))
		var full := float(me.get("ult", 0)) >= ult_max
		skill_r.text = "R  %s %s" % [C.ULT_NAMES[ch], "준비!" if full else "%d%%" % int(floor(float(me.get("ult", 0)) / ult_max * 100))]
		skill_r.get_parent().modulate = Color(1.2, 1.1, 0.7) if full else Color.WHITE
		skills.position = Vector2((vp.x - skills.size.x) / 2.0, vp.y - cards_h - skills.size.y)
	if damage_label.visible:
		damage_label.text = "%d%%" % int(me.get("damage", 0))
		damage_label.add_theme_color_override("font_color", _damage_color(float(me.get("damage", 0))))
		damage_label.position = Vector2((vp.x - damage_label.size.x) / 2.0, vp.y - cards_h - skills.size.y - damage_label.size.y - 6)


# 조준점 + 둘레 쿨 (바깥 하늘색 = 대시, 안쪽 흰색 = 밀치기)
func _draw_ring() -> void:
	var me := Store.me()
	if me.is_empty() or not me.get("alive", false) or Store.phase() != "playing" or not PlayerInput.locked:
		return
	var c := ring.get_viewport_rect().size / 2.0
	ring.draw_arc(c, 6, 0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)
	var dash := float(me.get("dashCd", 0))
	var push := float(me.get("pushCd", 0))
	if dash > 0:
		ring.draw_arc(c, 27, -PI / 2, -PI / 2 + TAU * (1.0 - dash / C.DASH_COOLDOWN_MS), 48, Color("5ad0ff"), 4.0)
	if push > 0:
		ring.draw_arc(c, 21, -PI / 2, -PI / 2 + TAU * (1.0 - push / C.PUSH_COOLDOWN_MS), 48, Color(1, 1, 1, 0.85), 3.0)


func _kills_panels(st: Dictionary, me: Dictionary, vp: Vector2) -> void:
	# Tab 점수표
	var show_board: bool = scores_held and _kills_game(st) and not bool(Store.room.get("practice", false))
	board.visible = show_board
	if show_board:
		var team: bool = st.get("teamMode", false)
		var ts: Dictionary = st.get("teamScores", {"red": 0, "blue": 0})
		var head := "[color=#ffd23a][font_size=22]점수표[/font_size][/color]  [color=#9fabcd]%s목표 %d킬[/color]\n" % ["빨강 %d : %d 파랑 · " % [int(ts.red), int(ts.blue)] if team else "", _goal(st)]
		var rows := "[table=%d]" % (7 if team else 6)
		# 열 너비: 이름 칸 넓게, 숫자 칸 고르게 (expand 비율 + 좌우 여백) — JS #scoreboard 표
		rows += _cell("", 0) + (_cell("팀", 1) if team else "") + _cell("이름", 5) + _cell("킬", 1) + _cell("죽음", 1) + _cell("자멸", 1) + _cell("점수", 1)
		var i := 0
		for r in U.score_rows(st.players, tally, team):
			i += 1
			var p := Store.player(r.id)
			var nm := "[color=#%s]%s[/color]" % [_player_color(p).to_html(false), _name(p)]
			if r.id == Store.my_id:
				nm = "[bgcolor=#ffd23a33]%s[/bgcolor]" % nm
			rows += _cell(str(i), 0) + (_cell(str(TEAM_KO.get(str(r.team), "")), 1) if team else "") + _cell(nm, 5) + _cell(str(int(r.kills)), 1) + _cell(str(int(r.deaths)), 1) + _cell(str(int(r.self)), 1) + _cell("[color=#ffd23a]%d[/color]" % int(r.score), 1)
		board_text.text = head + rows + "[/table]"
		board.position = (vp - board.size) / 2.0 + Vector2(0, -vp.y * 0.04)
	# 부활 대기
	var waiting: bool = _kills_game(st) and st.phase == "playing" and not me.is_empty() and not me.get("alive", true) and me.get("respawnIn") != null
	respawn.visible = waiting
	if waiting:
		var by = killed.get("by")
		var who := ""
		if by != null and by != Store.my_id:
			var k := Store.player(by)
			who = "%s에게 · " % (_name(k) if not k.is_empty() else str(killed.get("byName", "?")))
		respawn_why.text = "%s%s%s" % [who, CAUSE_KO.get(str(me.get("cause", killed.get("cause", ""))), ""), " · 자멸 -1" if by == null or by == Store.my_id else ""]
		respawn_num.text = str(U.respawn_secs(me.respawnIn))
		respawn.position = Vector2((vp.x - respawn.size.x) / 2.0, vp.y * 0.22)


# 점수표 칸: expand 0 = 내용만큼 (순위), 나머지는 비율. 숫자 칸은 가운데
func _cell(text: String, expand: int) -> String:
	var body := text if expand >= 5 else "[center]%s[/center]" % text
	return "[cell expand=%d padding=10,2,10,2]%s[/cell]" % [max(expand, 1), body] if expand > 0 else "[cell padding=4,2,8,2]%s[/cell]" % text


func _spectate(st: Dictionary, me: Dictionary, vp: Vector2) -> void:
	var on: bool = not me.is_empty() and not me.get("alive", true) and st.phase == "playing"
	spec_label.visible = on
	if not on:
		return
	var head: String = "사망: %s" % CAUSE_KO.get(str(me.get("cause", "")), str(me.get("cause", "")))
	if me.get("spectator", false):
		head = "관전 중 (호스트가 관전으로 바꿈)"
	var t = View.spectate_target
	var target := Store.player(t) if t != null else {}
	spec_label.text = "%s\n%s · 마우스 돌리기 · 휠 거리 · 클릭/Space 다음 사람 · 우클릭 전체 보기" % [head, "%s 따라가는 중" % _name(target) if not target.is_empty() else "전체 보기"]
	var cards_h: float = cards_row.size.y + 22 if cards_row.visible else 18
	spec_label.position = Vector2((vp.x - spec_label.size.x) / 2.0, vp.y - cards_h - spec_label.size.y)
