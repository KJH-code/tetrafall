# 판 중 HUD (JS main.js drawHud · updatePlayers · updateScore · killFeed · updateKillsHud · updateSkills · updateCooldowns · updateSpectate):
# 밝은 예전 모양 (노랑·남색, ui_style hud_box). 아래 사람마다 초상 + 큰 % (+ 체력전 HP 막대), 위 시간·점수 띠 (킬 점수전은 목표까지 막대),
# 오른쪽 위 킬 피드, Tab(연습 창 키) 점수표, 부활 카운트다운, 스킬 F·R 칸, 조준점 둘레 대시·밀치기 쿨, 관전 안내, 카운트다운 큰 숫자
extends Control

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Portrait := preload("res://ui/portrait.gd")
const U := preload("res://ui/ui_calc.gd")
const Coords := preload("res://core/coords.gd")
const Keys := preload("res://core/keys.gd")
const HM := preload("res://world/hunt_marks.gd") # 사냥꾼 표식 계산 (B4, shared/hunt-marks.js)

const CAUSE_KO := U.CAUSE_KO
const TEAM_KO := {"red": "빨강", "blue": "파랑"}
const TEAM_COL := {"red": Color("ff5a4a"), "blue": Color("4aa8ff")}

# 부활 빛: 화면 가장자리에서 안쪽으로 (CSS inset box-shadow 0 0 120px 40px ≈ 가장자리 거리 d 에서 .75·(1 - smoothstep(-80, 160, d))) + 안쪽 4px 흰 테 .8
const FLASH_SHADER := "shader_type canvas_item;\nuniform vec2 px = vec2(1280.0, 720.0);\nvoid fragment() {\n\tvec2 p = UV * px;\n\tfloat d = min(min(p.x, px.x - p.x), min(p.y, px.y - p.y));\n\tvec4 glow = vec4(0.47, 0.9, 1.0, 0.75 * (1.0 - smoothstep(-80.0, 160.0, d)));\n\tCOLOR = d < 4.0 ? mix(glow, vec4(1.0), 0.8) : glow;\n}\n"

var tally := U.KillTally.new()
var tally_round = null
var kill_events := false # 서버가 'kill' 을 보내면 피드·세기는 그것으로 (JS 와 같음)
var scores_held := false
var killed := {} # 나를 죽인 것 {by, byName, cause, weapon}

var timer_label: Label
var score_bar: HBoxContainer
var score_key := "" # 점수 띠 내용 열쇠 (JS scoreKey) — 같으면 다시 안 만듦 (예전엔 스냅샷마다 30Hz 로 노드를 다 지우고 새로 만듦)
var score_panel: PanelContainer # 위 점수 띠 (JS #score). ui.gd 가 화면 뿌리로 옮겨 대기실·결과에도 씀 (score_band)
var score_box_light: StyleBoxFlat
var score_box_dark: StyleBoxFlat
var cards_row: HBoxContainer
var cards := {} # id → {panel, face, name, sub, pct, hp, bar}
var cards_key := ""
var feed: VBoxContainer
var board: PanelContainer
var board_text: RichTextLabel
var respawn: PanelContainer
var respawn_num: Label
var respawn_why: Label
var flash: ColorRect # 부활 순간 가장자리 빛 (JS #respawn-flash: inset 0 0 120px 40px rgba(120,230,255,.75) + 안쪽 4px 흰 테)
var shown_pct := {} # id → 마지막 피해 % (오르면 % 흔들림 — JS shownPct·.hurt)
var spec_box: PanelContainer
var skills: HBoxContainer
var skill_f: Label
var skill_r: Label
var damage_label: Label
var spec_label: Label
var big: Label
var ring: Control
var ghost_ring: Control # 유령 투하 조준 원 (JS #ghost-cd): 쿨이면 회색이 시계 방향으로 차오름, 안 되는 걸 누르면 흔들림
var ghost_hint: Label # 처음 죽었을 때 한 번만 (JS #ghost-hint, GHOST_HINT_MS)
var ghost_hint_until := -1.0 # -1 = 아직 안 보여 줌
var ghost_fill := 1.0
var ghost_ready := true
var my_marks: Label # 맞은 사람 화면 위 칸 ◆◆◇ (JS #my-marks)
var mark_edge: TextureRect # 맞은 사람 화면 가장자리 빨강 (JS #mark-edge)
var mark_hit: Label # 사냥꾼 히트마커 '표식 +1 ◆◆◇' (JS #mark-hit)
var mark_hit_tw: Tween
var mark_edge_at := -1.0e9 # 내게 표식이 붙은 시각 ms (가장자리 한 번 더·칸 커졌다 줄기)
var rig = null # G1 카메라 (world/cam_rig.gd — 관전 전체 보기·하늘 시점·안 되는 투하 시각)
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
	score_panel = PanelContainer.new()
	score_box_light = S.hud_box() # JS #score: padding 4 20
	score_box_light.content_margin_left = 20
	score_box_light.content_margin_right = 20
	score_box_light.content_margin_top = 4
	score_box_light.content_margin_bottom = 4
	score_box_dark = score_box_light.duplicate() # body.ui-dark #score: rgba(10,6,22,.72) + 안쪽 1px ga + 바깥 빛 14px gc
	score_box_dark.bg_color = Color8(10, 6, 22, 184)
	score_box_dark.set_border_width_all(1)
	S.theme_border(score_box_dark, 0.55)
	score_box_dark.shadow_color = S.alpha(S.g(), 0.1)
	score_box_dark.shadow_size = 14
	score_panel.add_theme_stylebox_override("panel", score_box_light)
	score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	spec_box = PanelContainer.new() # JS #spec: rgba(8,12,26,.8) · padding 7 20 · 사선
	spec_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sps := StyleBoxFlat.new()
	sps.bg_color = Color8(8, 12, 26, 204)
	sps.skew = Vector2(S.SKEW * 0.5, 0)
	sps.content_margin_left = 20
	sps.content_margin_right = 20
	sps.content_margin_top = 7
	sps.content_margin_bottom = 7
	spec_box.add_theme_stylebox_override("panel", sps)
	spec_box.add_child(spec_label)
	spec_box.visible = false
	add_child(spec_box)
	ghost_ring = Control.new()
	ghost_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_ring.size = Vector2(30, 30)
	ghost_ring.draw.connect(_draw_ghost)
	add_child(ghost_ring)
	# 사냥꾼 표식 (2026-10-31 재혁 '표식 불명확'): 가장자리 빨강 (CSS radial-gradient 55% 투명 → 끝 빨강 .9) · 위 칸 · 히트마커
	mark_edge = TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 0.157, 0.118, 0.0))
	gr.set_color(1, Color(1, 0.157, 0.118, 0.9))
	gr.set_offset(0, 0.55)
	gt.gradient = gr
	mark_edge.texture = gt
	mark_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark_edge.stretch_mode = TextureRect.STRETCH_SCALE
	mark_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark_edge.modulate.a = 0.0
	add_child(mark_edge)
	move_child(mark_edge, 0)
	my_marks = _hud_label(26, false)
	my_marks.add_theme_constant_override("outline_size", 6)
	add_child(my_marks)
	mark_hit = _hud_label(20, false)
	mark_hit.modulate.a = 0.0
	add_child(mark_hit)
	ghost_hint = _hud_label(19, false)
	ghost_hint.text = "클릭: 블록 떨어뜨리기"
	ghost_hint.visible = false
	add_child(ghost_hint)

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
	board_text.custom_minimum_size.x = 420 # 열은 expand 비율로 이 폭을 채움 (넓히면 오른쪽이 빔)
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
	var ws := StyleBoxFlat.new() # JS .why: 빨강 칸 rgba(90,22,10,.85) · 사선 · 비면 숨김
	ws.bg_color = Color8(90, 22, 10, 217)
	ws.skew = Vector2(S.SKEW * 0.6, 0)
	ws.content_margin_left = 16
	ws.content_margin_right = 16
	ws.content_margin_top = 4
	ws.content_margin_bottom = 4
	respawn_why.add_theme_stylebox_override("normal", ws)
	respawn_why.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rv.add_child(respawn_why)
	respawn.add_child(rv)
	respawn.visible = false
	add_child(respawn)

	big = _center(_hud_label(118, false), "")
	big.visible = false
	add_child(big)

	flash = ColorRect.new()
	var fsh := Shader.new()
	fsh.code = FLASH_SHADER
	var fm := ShaderMaterial.new()
	fm.shader = fsh
	flash.material = fm
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	add_child(flash)
	flash.resized.connect(func(): fm.set_shader_parameter("px", flash.size))

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
	# 채움 막대 (JS #skills .fill: 노랑→주황 반투명, 폭 = F 쿨 진행 / R 게이지): 같은 기울기 상자를 폭만 줄여 판 위·글자 아래에 그림
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 0.7, 0.18, 0.38)
	fill.skew = s.skew
	p.set_meta("fill", 0.0)
	p.draw.connect(func():
		var f: float = p.get_meta("fill", 0.0)
		if f > 0.0:
			fill.draw(p.get_canvas_item(), Rect2(2, 2, (p.size.x - 4) * f, p.size.y - 4)))
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return l


# 스킬 칸 채움·준비 빛 (JS .slot.ready: 노랑 테두리 + 0 0 14px 빛)
static func slot_state(l: Label, fill: float, ready: bool) -> void:
	var p := l.get_parent() as PanelContainer
	var f := clampf(fill, 0.0, 1.0)
	if absf(float(p.get_meta("fill", 0.0)) - f) > 0.001:
		p.set_meta("fill", f)
		p.queue_redraw()
	var s := p.get_theme_stylebox("panel") as StyleBoxFlat
	s.border_color = S.ACCENT if ready else Color("3c4a78")
	s.shadow_color = Color(1, 0.82, 0.23, 0.75) if ready else Color(0, 0, 0, 0)
	s.shadow_size = 14 if ready else 0


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
		"mark":
			# 사냥꾼: 조준점 옆 '표식 +1 ◆◆◇' (꽉 차면 금색 'R 준비'), 맞은 사람: 가장자리 빨강이 한 번 진해짐 (JS handleEvent mark)
			if e.get("by") == Store.my_id:
				_show_mark_hit(int(e.get("n", 1)))
			if e.get("target") == Store.my_id:
				mark_edge_at = float(Time.get_ticks_msec())
		"respawn":
			if e.get("who") == Store.my_id and not Store.room.get("practice", false):
				var tw := create_tween()
				flash.modulate.a = 0.95
				tw.tween_property(flash, "modulate:a", 0.0, C.KILLS_RESPAWN_FLASH_MS / 1000.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


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
	txt += "[color=#%s]%s[/color] [color=#9fabcd][font_size=13]%s[/font_size][/color]" % [_player_color(victim).to_html(false), _name(victim), U.cause_text(e.cause, e.get("weapon"))]
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
	return U.fmt_time(ms) # JS fmt: 초는 버림 (예전엔 올림이라 1초 많게)


# 매 프레임 (ui.gd 가 판 화면일 때 부름)
func refresh(st: Dictionary) -> void:
	var vp := get_viewport_rect().size
	var me := Store.me()
	# 위 왼쪽: 남은 시간 (블록 마스터·킬 점수전) 또는 판 시간
	var left = st.round.get("left")
	timer_label.text = " " + (_fmt(left) if left != null else _fmt(float(st.round.get("elapsed", 0)))) + " "
	timer_label.visible = st.phase == "playing" # JS #status: 판 중에만 (카운트다운·판 끝엔 숨김)
	var small := U.small(vp)
	big.add_theme_font_size_override("font_size", 88 if small else 118) # JS #bigmsg (작은 창 88)
	respawn_num.add_theme_font_size_override("font_size", 72 if small else 96)
	# 카운트다운 큰 숫자
	if st.phase == "countdown":
		big.text = str(maxi(1, int(ceil(float(st.round.countdownLeft) / 1000.0))))
		big.add_theme_color_override("font_color", Color.WHITE)
		big.visible = true
	big.position = Vector2((vp.x - big.size.x) / 2.0, vp.y * 0.3 - big.size.y / 2.0)
	_cards(st, vp)
	score_band(st, vp, false)
	_skills(me, vp)
	_kills_panels(st, me, vp)
	_spectate(st, me, vp)
	_my_marks(me, vp)
	ring.queue_redraw()


# 위 점수 띠 (JS updateScore): 대기실·결과 (between = body.ui-dark 빛 판) 엔 승수 'A 1 : 0 B' · 셋 이상 'A 1 · B 0 · C 0' · 팀전 '빨강 1 : 0 파랑',
# 판 중엔 아래 판과 겹치는 개인전 승수는 숨기고 팀전·킬 점수전만. 킬 점수전 (판 중·판 끝) 은 1~N위 + 나 + 목표까지 막대 + 남은 시간
func score_band(st: Dictionary, vp: Vector2, between: bool) -> void:
	var ps: Array = st.players.filter(func(p): return not p.get("spectator", false) and not p.get("dummy", false))
	ps.sort_custom(func(a, b): return a.slot < b.slot)
	var panel := score_panel
	var kills: bool = st.get("mode") == "kills" and st.get("phase") != "lobby"
	var team: bool = st.get("teamMode", false)
	var dup: bool = not between and cards_row.visible and not team and not kills
	var show: bool = ps.size() >= 2 and not dup and not bool(Store.room.get("practice", false))
	var small := U.small(vp)
	# JS updateScore scoreKey: 판 끝 남은 시간 (글자)·승수·점수·이름·팀·색·자리 비움·나·팀 합계 + 고도는 화면 크기·판 사이 (빛 판)·테마 빛 색·목표 킬도
	var tw0: Dictionary = st.get("teamWins", {"red": 0, "blue": 0})
	var ts0: Dictionary = st.get("teamScores", {"red": 0, "blue": 0})
	var left_txt := _fmt(float(st.round.left)) if kills and st.get("round", {}).get("left") != null else ""
	var key := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s:%s|%s:%s|%s|%s" % [show, kills, left_txt, dup, between, vp, S.theme_id(),
		",".join(ps.map(func(p): return "%s:%s:%s:%s:%s:%s:%s:%s:%s" % [p.id, p.get("wins"), p.get("score"), p.get("nick"), p.get("name"), p.get("team"), p.get("color"), p.slot, p.get("away", false)])),
		Store.my_id, tw0.get("red"), tw0.get("blue"), ts0.get("red"), ts0.get("blue"), team, _goal(st) if kills else 0]
	if key == score_key and panel.visible == show: # 밖 (ui.gd 메뉴 화면) 에서 숨겼으면 다시 그림
		return
	score_key = key
	for c in score_bar.get_children():
		c.free()
	panel.visible = show
	panel.add_theme_stylebox_override("panel", score_box_dark if between else score_box_light)
	panel.position.y = 12
	if not panel.visible:
		return
	if not kills:
		var f := 16 if small else 20 # JS #score 20px (작은 창 16)
		var sep := func(t: String) -> Label:
			var l := _chip(t, Color("67739a"), f)
			return l
		var me_team = Store.me().get("team")
		var name_chip := func(p: Dictionary) -> Control:
			var l := _chip(_name(p) + (" 자리 비움" if p.get("away", false) else ""), _player_color(p), f)
			if p.get("away", false):
				l.modulate.a = 0.6
			if p.id == Store.my_id:
				_underline(l, between)
			return l
		if team:
			var tw: Dictionary = st.get("teamWins", {"red": 0, "blue": 0})
			var r := _chip("빨강", TEAM_COL.red, f)
			var b := _chip("파랑", TEAM_COL.blue, f)
			if me_team == "red":
				_underline(r, between)
			elif me_team == "blue":
				_underline(b, between)
			for n in [r, _chip(" %d" % int(tw.get("red", 0)), Color.WHITE, f), sep.call(":"), _chip("%d " % int(tw.get("blue", 0)), Color.WHITE, f), b]:
				score_bar.add_child(n)
		elif ps.size() == 2:
			for n in [name_chip.call(ps[0]), _chip(" %d" % int(ps[0].get("wins", 0)), Color.WHITE, f), sep.call(":"), _chip("%d " % int(ps[1].get("wins", 0)), Color.WHITE, f), name_chip.call(ps[1])]:
				score_bar.add_child(n)
		else:
			for i in ps.size():
				if i > 0:
					score_bar.add_child(sep.call("·"))
				score_bar.add_child(name_chip.call(ps[i]))
				score_bar.add_child(_chip(" %d" % int(ps[i].get("wins", 0)), Color.WHITE, f))
		panel.reset_size()
		panel.position.x = (vp.x - panel.size.x) / 2.0
		return
	var big_f := 15 if small else 18 # JS #score.kills 18 (작은 창 15)
	var bar_w := 30.0 if small else 46.0
	if kills and not st.get("teamMode", false):
		for r in U.top_bar(ps, Store.my_id):
			var p := Store.player(r.id)
			# JS .kc: 내 칸은 노랑 바탕 .12 + 아래 2px 노랑, 4위 아래 '나' 칸은 왼쪽 2px 선
			var kc := PanelContainer.new()
			var ks := StyleBoxFlat.new()
			ks.bg_color = Color(1, 0.82, 0.23, 0.12) if r.get("me", false) else Color(0, 0, 0, 0)
			ks.border_width_bottom = 2 if r.get("me", false) else 0
			ks.border_width_left = 2 if r.get("extra", false) else 0
			ks.border_color = S.ACCENT if r.get("me", false) else Color("3c4a78")
			ks.content_margin_left = 5 if small else 8
			ks.content_margin_right = 5 if small else 8
			kc.add_theme_stylebox_override("panel", ks)
			var kb := HBoxContainer.new()
			kb.add_theme_constant_override("separation", 5)
			kb.add_child(_chip("%d" % int(r.rank), S.DIM, 13))
			kb.add_child(_chip(_name(p), _player_color(p), big_f))
			kb.add_child(_chip("%d" % int(r.score), Color.WHITE, big_f))
			kb.add_child(_bar(U.progress(r.score, _goal(st)), _player_color(p), bar_w))
			kc.add_child(kb)
			score_bar.add_child(kc)
	else:
		# JS: '빨강 3 : 1 파랑' (팀 이름만 팀 색), 킬 점수전은 '빨강 3 ▬ : ▬ 1 파랑'
		var ts: Dictionary = st.get("teamScores", {"red": 0, "blue": 0}) if kills else st.get("teamWins", {"red": 0, "blue": 0})
		score_bar.add_child(_chip("빨강", TEAM_COL.red, big_f))
		score_bar.add_child(_chip("%d" % int(ts.get("red", 0)), Color.WHITE, big_f))
		if kills:
			score_bar.add_child(_bar(U.progress(ts.get("red", 0), _goal(st)), TEAM_COL.red, bar_w))
		score_bar.add_child(_chip(":", Color("67739a"), big_f))
		if kills:
			score_bar.add_child(_bar(U.progress(ts.get("blue", 0), _goal(st)), TEAM_COL.blue, bar_w))
		score_bar.add_child(_chip("%d" % int(ts.get("blue", 0)), Color.WHITE, big_f))
		score_bar.add_child(_chip("파랑", TEAM_COL.blue, big_f))
	if kills:
		score_bar.add_child(_chip("· 목표 %d킬" % _goal(st), S.DIM, 13))
		if st.round.get("left") != null:
			score_bar.add_child(_chip("· %s" % _fmt(float(st.round.left)), Color.WHITE, big_f)) # JS: 남은 시간도 띠 끝에
	panel.reset_size()
	panel.position.x = (vp.x - panel.size.x) / 2.0


# 내 이름·내 팀 밑줄 (JS #score .me border-bottom 3px — 판 중 노랑, 대기실·결과 테마 빛)
func _underline(l: Label, dark: bool) -> void:
	var u := StyleBoxFlat.new()
	u.bg_color = Color(0, 0, 0, 0)
	u.border_width_bottom = 3
	u.border_color = S.g() if dark else S.ACCENT
	l.add_theme_stylebox_override("normal", u)


func _chip(text: String, col: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _bar(frac: float, col: Color, w := 46.0) -> Control:
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.12)
	back.custom_minimum_size = Vector2(w, 6)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.color = col
	fill.size = Vector2(w * frac, 6)
	back.add_child(fill)
	return back


# 아래 사람마다 판: 초상 (G2 전엔 색 상자) · 이름 · 캐릭터·승/킬 · 큰 % · 체력전 HP 막대 · 색 띠. 판 크기는 card_layout
func _cards(st: Dictionary, vp: Vector2) -> void:
	var live: Array = st.players.filter(func(p): return not p.get("spectator", false) and not p.get("dummy", false))
	# 판 중 + 판 끝 마지막 킬 슬로모션까지 (승자 클로즈업·결과 표 동안은 숨김 — JS cardsOn)
	var slow: bool = str(st.phase) == "over" and str(View.victory_stage) == "slow"
	var on: bool = live.size() >= 2 and not Store.room.get("practice", false) and (str(st.phase) in ["countdown", "playing"] or slow)
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
		if c.face_img.texture == null:
			var ft := Portrait.tex(p.get("char"), c.col, 96)
			if ft != null:
				c.face_img.texture = ft
				c.face.color = Color(0, 0, 0, 0.35) # JS .face 바탕 rgba(0,0,0,.35) (초상 전엔 그 사람 색 상자)
		# 맞으면 % 가 흔들림 (JS .hurt .pct: shake .3s)
		var was = shown_pct.get(p.id)
		if was != null and float(p.damage) > float(was) and p.alive:
			_hurt(c.pct_row)
		shown_pct[p.id] = float(p.damage)
		# 체력전: 큰 % 자리에 남은 HP (글자색도 HP 비율), 그 아래 막대. 끄면 예전 % (JS updatePlayers)
		var hv = U.hp_view(p, st)
		c.pct.text = "KO" if dead else ("%d" % int(hv.hp) if hv != null else "%d" % int(p.damage))
		c.unit.visible = not dead and hv == null # JS <u>%</u> 20px
		c.pct.add_theme_font_size_override("font_size", 27 if dead else int(c.pct_size)) # JS .pct i (KO) 27px
		c.pct.add_theme_color_override("font_color", S.HOT if dead else (U.hp_color(hv.frac) if hv != null else U.damage_color(float(p.damage))))
		c.unit.add_theme_color_override("font_color", U.damage_color(float(p.damage)))
		# 죽음 회색 (JS grayscale .8 brightness .66 — 고도는 밝기만), 자리 비움 .62 + 태그, 관전 중 보는 사람 ▶ + 노랑 테
		var away: bool = bool(p.get("away", false))
		c.panel.modulate = Color(0.6, 0.6, 0.6) if dead else Color.WHITE
		c.panel.modulate.a = 0.62 if away else 1.0
		c.away.visible = away
		var r = _rig()
		var watch: bool = r != null and r.spectating() and not bool(r.spec.get("overview", false)) and View.spectate_target != null and int(View.spectate_target) == int(p.id)
		if watch != c.panel.get_meta("watch", false):
			c.panel.set_meta("watch", watch)
			c.panel.queue_redraw()
		c.watch.visible = watch
		if watch:
			c.watch.global_position = c.panel.global_position + Vector2((c.panel.size.x - c.watch.size.x) / 2.0, -15.0 - c.watch.size.y / 2.0)
		var mkd = HM.pick_mark(p.get("marks"), Store.my_id) if not dead else null
		var mk_text := ""
		if mkd != null and float(mkd.n) > 0 and not HM.mark_blink(float(mkd.get("left", 1e9)), float(Time.get_ticks_msec())):
			mk_text = HM.pip_text(mkd.n)
		c.mk.text = mk_text
		c.mk.add_theme_color_override("font_color", Color("ffd23a") if mkd != null and float(mkd.n) >= C.HUNTER_MARK_MAX else Color("ff3a2a"))
		c.mk.add_theme_color_override("font_outline_color", Color.WHITE if mkd != null and mkd.mine else Color.BLACK)
		c.sub.text = "%s%s %s" % ["%s팀 · " % TEAM_KO.get(str(p.get("team", "")), "") if st.get("teamMode", false) else "", C.CHAR_NAMES.get(str(p.get("char", "")), ""), ("킬 %d" % int(p.get("score", 0))) if kills else ("승 %d" % int(p.get("wins", 0)))]
		c.hp.visible = hv != null and not dead # KO 면 막대 없이 KO 만
		if hv != null:
			c.hp_fill.size.x = c.hp.size.x * float(hv.frac)
			c.hp_fill.color = Color("e0300c") if hv.low else Color("2fbf5a")


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
	top.add_theme_constant_override("separation", 4 if L.compact else 5)
	var face := ColorRect.new() # 초상 자리 (G2 몸 SubViewport)
	face.color = _player_color(p)
	var fs: float = 30.0 * float(L.scale) + 2.0 if L.compact else 38.0 # JS .face 38, 작은 판 30×배율+2
	face.custom_minimum_size = Vector2(fs, fs)
	var face_img := TextureRect.new()
	face_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.add_child(face_img)
	top.add_child(face)
	var names := VBoxContainer.new()
	var nm := _chip(_name(p), S.TEXT, 12 if L.compact else (14 if me else 13))
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # JS .nm 넘치면 말줄임 (긴 이름이 판을 넓히지 않게)
	names.add_child(nm)
	var sub := _chip("", S.DIM, 11)
	sub.visible = not L.compact
	names.add_child(sub)
	top.add_child(names)
	v.add_child(top)
	var pct_size := int((42 if me else 34) * L.scale)
	var pct := _chip("", S.TEXT, pct_size)
	pct.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	pct.add_theme_constant_override("shadow_offset_y", 3)
	var unit := _chip("%", S.TEXT, 20) # JS .pct u: % 는 20px 고정
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	unit.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	unit.add_theme_constant_override("shadow_offset_y", 2)
	var pct_row := HBoxContainer.new()
	pct_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pct_row.add_theme_constant_override("separation", 0)
	pct_row.add_child(pct)
	pct_row.add_child(unit)
	v.add_child(pct_row)
	var hp := ColorRect.new()
	hp.color = Color(1, 1, 1, 0.14)
	hp.custom_minimum_size.y = 6
	var hp_fill := ColorRect.new()
	hp_fill.size.y = 6
	hp.add_child(hp_fill)
	hp.visible = false
	v.add_child(hp)
	s.border_color = _player_color(p) # 아래 색 띠 = 그 사람 색 (내 판도 — 위 노랑 띠는 아래 덧그림)
	s.border_width_top = 0
	# 위 노랑 띠 (내 판) · 관전 중 보는 사람 노랑 테 (JS .pc.me border-top 4px · .pc.watch outline 2px): 같은 기울기 상자를 판 위에 덧그림
	var over_top := StyleBoxFlat.new()
	over_top.draw_center = false
	over_top.skew = s.skew
	over_top.border_width_top = 4
	over_top.border_color = S.ACCENT
	var over_watch := StyleBoxFlat.new()
	over_watch.draw_center = false
	over_watch.skew = s.skew
	over_watch.set_border_width_all(2)
	over_watch.border_color = S.ACCENT
	panel.draw.connect(func():
		if me:
			over_top.draw(panel.get_canvas_item(), Rect2(Vector2.ZERO, panel.size))
		if panel.get_meta("watch", false):
			over_watch.draw(panel.get_canvas_item(), Rect2(Vector2.ZERO, panel.size)))
	if me:
		s.content_margin_top = 6 # JS .pc.me padding-top 2 + 띠 4
	cards_row.add_child(panel)
	# 자리 비움 태그 (JS .away-tag: 왼쪽 위 10px 노랑 칸) · 관전 ▶ (판 위 가운데)
	var away := _chip("자리 비움", Color("1a1300"), 10)
	var aws := StyleBoxFlat.new()
	aws.bg_color = S.ACCENT
	aws.skew = Vector2(S.SKEW, 0)
	aws.content_margin_left = 8
	aws.content_margin_right = 8
	away.add_theme_stylebox_override("normal", aws)
	away.position = Vector2(-2, -4)
	away.z_index = 1
	away.visible = false
	face.add_child(away)
	var watch := _chip("▶", S.ACCENT, 12)
	watch.rotation = PI / 2.0
	watch.pivot_offset = Vector2(6, 8)
	watch.visible = false
	face.add_child(watch)
	# 표식 칸 (B4 JS: 위 줄 오른쪽 끝, 이름과 같은 높이 — 큰 % 와 안 섞이게): 빨강, 내가 붙인 것이면 흰 테, 꽉 차면 금색
	var mk := Label.new()
	mk.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.add_theme_font_size_override("font_size", 11)
	mk.add_theme_constant_override("outline_size", 4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(mk)
	return {"panel": panel, "face": face, "face_img": face_img, "col": _player_color(p), "sub": sub, "pct": pct, "pct_size": pct_size, "unit": unit, "pct_row": pct_row, "away": away, "watch": watch, "hp": hp, "hp_fill": hp_fill, "mk": mk}


# % 흔들림 (JS @keyframes shake .3s: 10%·90% -2px, 30%·70% +3px, 50% -4px). 줄은 VBox 안이라 x 0 이 제자리
func _hurt(row: Control) -> void:
	var tw := row.create_tween()
	for k in [[-2.0, 0.03], [3.0, 0.06], [-4.0, 0.06], [3.0, 0.06], [-2.0, 0.06], [0.0, 0.03]]:
		tw.tween_property(row, "position:x", k[0], k[1])


# 피해 % 색: JS damageColor 그대로 (0% 흰 → 50% 노랑 → 100% 빨강 rgb(255,40,0)) — 예전엔 40·90·150% 마디의 다른 곡선이라 100% 가 주황
func _damage_color(d: float) -> Color:
	return U.damage_color(d)


func _skills(me: Dictionary, vp: Vector2) -> void:
	var playing: bool = Store.phase() in ["countdown", "playing"] and not me.is_empty() and me.get("alive", false) and not me.get("master", false)
	skills.visible = playing and me.get("char") != null
	damage_label.visible = playing and not cards_row.visible
	# 자리는 hud_extra._bottom 이 아래 묶음 (버프 → 내 % → F·R → 아이템, JS #bottom) 으로 한 번에 놓음
	if skills.visible:
		var ch := str(me.char)
		var cd := float(me.get("skillCd", 0))
		var kf := Keys.key_label(str(PlayerInput.binds.get("skill", "KeyF"))) # JS data-key: 지금 키 설정 글자
		var kr := Keys.key_label(str(PlayerInput.binds.get("ult", "KeyR")))
		skill_f.text = "%s  %s %s" % [kf, C.SKILL_NAMES[ch], "%.1fs" % (cd / 1000.0) if cd > 0 else ""]
		var cd_total := float(C.SKILL_CD_MS.get(ch, 1.0))
		slot_state(skill_f, 1.0 - cd / cd_total if cd > 0 else 1.0, cd <= 0)
		var ult_max := float(me.get("ultMax", C.ULT_MAX))
		var full := float(me.get("ult", 0)) >= ult_max
		skill_r.text = "%s  %s %s" % [kr, C.ULT_NAMES[ch], "준비!" if full else "%d%%" % int(floor(float(me.get("ult", 0)) / ult_max * 100))]
		slot_state(skill_r, float(me.get("ult", 0)) / ult_max, full and not (typeof(me.get("ultTarget")) == TYPE_BOOL and not bool(me.ultTarget)))
	if damage_label.visible:
		var hv = U.hp_view(me, Store.state) # 체력전이면 % 대신 남은 HP
		damage_label.text = ("HP %d" % int(hv.hp)) if hv != null else "%d%%" % int(me.get("damage", 0))
		damage_label.add_theme_color_override("font_color", U.hp_color(hv.frac) if hv != null else _damage_color(float(me.get("damage", 0))))
		# 3인칭이면 왼쪽 아래 구석 (JS #damage.corner — 가운데면 내 발에 겹침), 1인칭이면 F·R 위 가운데
		var third := str(View.mode) == "third" # G1 카메라가 정한 지금 시점
		var small := U.small(vp)
		damage_label.add_theme_font_size_override("font_size", (36 if small else 44) if third else (42 if small else 54))
		if third:
			damage_label.position = Vector2(22, vp.y - damage_label.size.y - 18)


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
		var wk := U.weapon_ko(killed.get("weapon"))
		respawn_why.text = "%s%s%s%s" % [who, CAUSE_KO.get(str(me.get("cause", killed.get("cause", ""))), ""), " (%s)" % wk if wk != "" else "", " · 자멸 -1" if by == null or by == Store.my_id else ""]
		respawn_why.visible = respawn_why.text != ""
		var n := str(U.respawn_secs(me.respawnIn))
		if respawn_num.text != n: # 숫자가 바뀔 때마다 톡 (JS num-tick .3s 1.3 → 1)
			respawn_num.text = n
			respawn_num.pivot_offset = respawn_num.size / 2.0
			respawn_num.scale = Vector2(1.3, 1.3)
			respawn_num.create_tween().tween_property(respawn_num, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		respawn.position = Vector2((vp.x - respawn.size.x) / 2.0, vp.y * 0.22)


# 점수표 칸: expand 0 = 내용만큼 (순위), 나머지는 비율. 숫자 칸은 가운데
func _cell(text: String, expand: int) -> String:
	var body := text if expand >= 5 else "[center]%s[/center]" % text
	return "[cell expand=%d padding=10,2,10,2]%s[/cell]" % [max(expand, 1), body] if expand > 0 else "[cell padding=4,2,8,2]%s[/cell]" % text


func _rig():
	if rig == null or not is_instance_valid(rig):
		var w := get_tree().root.find_child("World", true, false)
		rig = w.get("rig") if w != null else null
	return rig


func _spectate(st: Dictionary, me: Dictionary, vp: Vector2) -> void:
	var on: bool = not me.is_empty() and not me.get("alive", true) and st.phase == "playing"
	spec_box.visible = on
	var r = _rig()
	# 유령 투하 되는 판 (스냅샷 ghostCd: 없음·null = 못 함, 0 = 됨, ms = 쿨)
	var ghost_on: bool = on and me.get("ghostCd") != null
	var aim_on: bool = ghost_on and (r == null or float(r.get("sky_blend")) == 0.0)
	ghost_ring.visible = aim_on
	if not aim_on:
		ghost_hint.visible = false
	else:
		var cd := float(me.ghostCd)
		ghost_ready = cd == 0.0
		ghost_fill = 1.0 if ghost_ready else 1.0 - minf(1.0, cd / C.GHOST_DROP_CD_MS)
		var at: Vector2 = vp / 2.0 if PlayerInput.locked else get_viewport().get_mouse_position()
		var now := float(Time.get_ticks_msec())
		var refuse: float = float(r.get("ghost_refuse_at")) if r != null else -1e9
		var shake := sin(now / 20.0) * 4.0 if now - refuse < 250.0 else 0.0
		ghost_ring.position = at - ghost_ring.size / 2.0 + Vector2(shake, 0)
		ghost_ring.queue_redraw()
		if ghost_hint_until < 0.0:
			ghost_hint_until = now + C.GHOST_HINT_MS
		ghost_hint.visible = now < ghost_hint_until
		ghost_hint.position = Vector2((vp.x - ghost_hint.size.x) / 2.0, vp.y * 0.38)
	if not on:
		return
	# JS updateSpectate 문구: 사망 원인 — 킬러의 무기, 다음 판부터 참가, 부활까지 N초 (킬 점수전은 가운데 큰 숫자), 판이 없으면 살아 있는 사람
	var head: String = "사망: %s" % CAUSE_KO.get(str(me.get("cause", "")), str(me.get("cause", "")))
	if killed.get("by") != null:
		var kp := Store.player(killed.by)
		head += " — %s의 %s" % [_name(kp) if not kp.is_empty() else str(killed.get("byName", "?")), U.weapon_ko(killed.get("weapon"))]
	if me.get("spectator", false):
		head = "관전 중 (호스트가 관전으로 바꿈)"
	elif me.get("cause") == null or str(me.get("cause", "")) == "":
		head = "이번 판은 관전 (다음 판부터 참가)"
	if me.get("respawnIn") != null and st.get("mode") != "kills":
		head += " · 부활까지 %d초" % int(ceil(float(me.respawnIn) / 1000.0))
	var t = View.spectate_target
	var target := Store.player(t) if t != null else {}
	var overview: bool = r != null and bool(r.spec.get("overview", false))
	var jump := Keys.key_label(str(PlayerInput.binds.get("jump", "Space")))
	var next := ("%s 다음 사람 · 클릭 블록 떨어뜨리기" % jump) if ghost_on else ("클릭/%s 다음 사람" % jump) # JS 문구
	var alive_txt := ""
	if not cards_row.visible: # 살아 있는 사람·피해 % 는 아래 판이 보여 줌 → 판이 없을 때만 글로
		var names := []
		for x in (r.alive_others() if r != null else []):
			names.append("%s%s %d%%" % ["▶ " if not overview and t != null and int(x.id) == int(t) else "", _name(x), int(x.get("damage", 0))])
		alive_txt = "   ".join(names)
	spec_label.text = "%s\n%s · 마우스 돌리기 · 휠 거리 · %s · 우클릭 %s%s" % [head, "%s 따라가는 중" % _name(target) if not target.is_empty() and not overview else "전체 보기", next, "따라가기" if overview else "전체 보기", "\n살아 있음: %s" % alive_txt if alive_txt != "" else ""]
	var cards_h: float = cards_row.size.y + 22 if cards_row.visible else 18
	spec_box.reset_size()
	spec_box.position = Vector2((vp.x - spec_box.size.x) / 2.0, vp.y - cards_h - spec_box.size.y)


# 조준 원: 흰 테두리 + 가운데 점, 쿨이면 회색 테두리 + 회색이 시계 방향으로 차오름 (JS #ghost-cd conic-gradient)
func _draw_ghost() -> void:
	var c := ghost_ring.size / 2.0
	if ghost_ready:
		ghost_ring.draw_circle(c, 14.0, Color(1, 1, 1, 0.12))
	else:
		ghost_ring.draw_circle(c, 14.0, Color(0, 0, 0, 0.25))
		var pts := PackedVector2Array([c])
		for i in 33:
			var a := -PI / 2.0 + TAU * ghost_fill * float(i) / 32.0
			pts.append(c + Vector2(cos(a), sin(a)) * 14.0)
		if ghost_fill > 0.0:
			ghost_ring.draw_colored_polygon(pts, Color(0.78, 0.78, 0.78, 0.55))
	ghost_ring.draw_arc(c, 14.0, 0.0, TAU, 40, Color(1, 1, 1, 0.85) if ghost_ready else Color(0.63, 0.63, 0.63, 0.8), 2.0)
	ghost_ring.draw_circle(c, 2.0, Color.WHITE)


# 맞은 사람: 화면 위 칸 (빈 칸까지, 꽉 차면 금색, 붙은 순간 커졌다 줄기) + 가장자리 빨강 (개수만큼·붙은 순간 한 번 더) — JS updateMyMarks
func _my_marks(me: Dictionary, vp: Vector2) -> void:
	var m = null
	if not me.is_empty() and me.get("alive", false):
		for x in me.get("marks", []):
			if m == null or float(x.n) > float(m.n):
				m = x
	var now := float(Time.get_ticks_msec())
	var blink: bool = m != null and HM.mark_blink(float(m.get("left", 1e9)), now)
	my_marks.text = HM.pip_text(m.n) if m != null and not blink else ""
	var full: bool = m != null and float(m.n) >= C.HUNTER_MARK_MAX
	my_marks.add_theme_color_override("font_color", Coords.color(C.HUNT_MARK_UI.full if full else C.HUNT_MARK_UI.on))
	var k := HM.pop_scale(now - mark_edge_at)
	my_marks.pivot_offset = my_marks.size / 2.0
	my_marks.scale = Vector2(k, k)
	my_marks.position = Vector2((vp.x - my_marks.size.x) / 2.0, vp.y * 0.13)
	mark_edge.modulate.a = HM.edge_level(float(m.n), C.HUNTER_MARK_MAX, now - mark_edge_at, blink) if m != null else 0.0


# 사냥꾼 히트마커: 조준점 오른쪽 아래 '표식 +1 ◆◆◇' (꽉 차면 금색 ' R 준비'), 커졌다 줄며 위로 사라짐 (HUNT_MARK_UI.hitMs)
func _show_mark_hit(n: int) -> void:
	var full := n >= int(C.HUNTER_MARK_MAX)
	mark_hit.text = "표식 +1 %s%s" % [HM.pip_text(n), " R 준비" if full else ""]
	mark_hit.add_theme_color_override("font_color", Coords.color(C.HUNT_MARK_UI.full if full else C.HUNT_MARK_UI.on))
	var vp := get_viewport_rect().size
	var at := vp / 2.0 + Vector2(22, 22)
	if mark_hit_tw != null:
		mark_hit_tw.kill()
	mark_hit.position = at
	mark_hit.modulate.a = 1.0
	mark_hit.scale = Vector2(1.35, 1.35)
	var ms: float = C.HUNT_MARK_UI.hitMs / 1000.0
	mark_hit_tw = create_tween()
	mark_hit_tw.tween_property(mark_hit, "scale", Vector2.ONE, ms * 0.25)
	mark_hit_tw.parallel().tween_property(mark_hit, "position", at + Vector2(0, -4), ms * 0.25)
	mark_hit_tw.tween_property(mark_hit, "position", at + Vector2(0, -14), ms * 0.75)
	mark_hit_tw.parallel().tween_property(mark_hit, "modulate:a", 0.0, ms * 0.75)


# 대기실에서 아래 판 초상 (96 얼굴) 을 미리 그려 둠 — 판 시작 직후 8명 판에서 P4~ 가 한참 색 네모이던 것 (JS warmPortraits 같은 자리)
func warm_faces(st: Dictionary) -> void:
	for p in st.get("players", []):
		if p.get("spectator", false) or p.get("dummy", false) or p.get("char") == null:
			continue
		Portrait.tex(p.get("char"), _player_color(p), 96)
