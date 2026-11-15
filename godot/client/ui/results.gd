# 판 끝 결과 (JS #results updateResults): 판이 끝나고 RESULTS_HERO_MS 동안만, 오른쪽에 붙은 빛 판 — 승자 초상 (G2 전엔 색 상자) + 승리 글 + 결과 표
# (이름·캐릭터·승/킬·피해·결과). 승자가 먼저, 그다음 승/킬 순
# 고도 판 전용: 승리 글 아래 판 끝 칭호 최대 3줄 (awards_calc.gd — 판 동안 Store.game_event 를 세어 뽑음)
extends PanelContainer

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Portrait := preload("res://ui/portrait.gd")
const U := preload("res://ui/ui_calc.gd")
const Coords := preload("res://core/coords.gd")
const Awards := preload("res://ui/awards_calc.gd")
const R := preload("res://core/report.gd")

const CAUSE_KO := {"crush": "압사", "fall": "낙사", "lava": "용암", "hp": "체력"}
const TEAM_KO := {"red": "빨강", "blue": "파랑"}

var title: Label
var star: PanelContainer # 승자 초상 칸 (JS .star: rgba(0,0,0,.3) + 아래 6px 승자 색 + 사선 14px + 안쪽 1px gb)
var star_box: StyleBoxFlat
var pane_box: StyleBoxFlat
var win_rows: Array = [] # 표에서 승자 줄의 첫 칸 (줄 바탕 gb 를 그릴 자리)
var faces: Array = [] # [TextureRect, char, color] — 초상이 그려지면 넣음
var small_was = null
var star_img: TextureRect # 승자 초상 (192 얼굴)
var star_who = null # [char, color] — 그려지면 넣음
var head: Label
var table: GridContainer
var key := ""
# 판 끝 칭호: 판 동안 이벤트를 셈. 판 중에 들어온 (재접속) 사람은 그 전 이벤트가 없어 집계가 모자람 — KillTally 와 같은 한계
var tally := Awards.Tally.new()
var awards: Array = [] # 칭호 Label (Awards.MAX_LINES 개, 빈 줄은 숨김)
var awards_key := ""


func _ready() -> void:
	pane_box = S.pane() # JS #results padding 16 22 18 28
	pane_box.content_margin_top = 16
	pane_box.content_margin_right = 22
	pane_box.content_margin_bottom = 18
	pane_box.content_margin_left = 28
	add_theme_stylebox_override("panel", pane_box)
	visibility_changed.connect(func(): if visible and not S.reduced(): S.slide_in(self, 40.0)) # JS res-in .35s
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	title = S.glow_label("", 20, Color.WHITE, 4)
	title.add_theme_font_override("font", S.spaced(1)) # JS h4 letter-spacing 1px
	v.add_child(title)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 14)
	star = PanelContainer.new()
	star_box = StyleBoxFlat.new()
	star_box.bg_color = Color(0, 0, 0, 0.3)
	star_box.border_width_bottom = 6
	star_box.border_color = Color("888888")
	star_box.skew = Vector2(0.11, 0)
	star_box.anti_aliasing = true
	star.add_theme_stylebox_override("panel", star_box)
	star.custom_minimum_size = Vector2(128, 128)
	star_img = TextureRect.new()
	star_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	star.add_child(star_img)
	who.add_child(star)
	head = S.glow_label("", 34, Color.WHITE, 6)
	head.add_theme_font_override("font", S.spaced(-1)) # JS .head letter-spacing -1, max-width 260 에서 줄바꿈
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size.x = 120
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(head)
	v.add_child(who)
	for i in Awards.MAX_LINES:
		var a := S.label("", 16, S.ACCENT)
		a.visible = false
		awards.append(a)
		v.add_child(a)
	Store.game_event.connect(_on_event)
	Store.state_changed.connect(_on_state)
	table = GridContainer.new()
	table.columns = 5
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 6)
	# 승자 줄 바탕 (JS tr.win td { background: var(--gb) })
	table.draw.connect(func():
		for c in win_rows:
			if is_instance_valid(c):
				table.draw_rect(Rect2(0, (c as Control).position.y - 3, table.size.x, (c as Control).size.y + 6), S.alpha(S.g(), 0.22)))
	v.add_child(table)
	# W48: 한 판 성능·모션 보고서를 클립보드로 (F4 도 같음) — 느림·어색함을 채팅에 붙여 넣기만 하면 되게
	var rep := S.button("성능 보고 복사", func(): R.request_copy(), "ghost", 12)
	rep.size_flags_horizontal = Control.SIZE_SHRINK_END
	rep.tooltip_text = "이번 판의 FPS·끊김·모션 정보를 복사합니다 (F4)"
	v.add_child(rep)


# JS 작은 창: padding 11 16 12 22, 초상 96, 승리 글 30, 표 13, 이름 15, 얼굴 26 (표 글자는 refresh 가 small_was 로)
func apply_small(small: bool) -> void:
	small_was = small
	pane_box.content_margin_top = 11 if small else 16
	pane_box.content_margin_right = 16 if small else 22
	pane_box.content_margin_bottom = 12 if small else 18
	pane_box.content_margin_left = 22 if small else 28
	star.custom_minimum_size = Vector2.ONE * (96 if small else 128)
	head.add_theme_font_size_override("font_size", 30 if small else 34)


# 세고 있는 판의 열쇠 (방 코드|판 번호): 이벤트·스냅샷이 같은 열쇠를 써야 판이 바뀔 때 한 번만 비워짐
func _round_key(st: Dictionary) -> String:
	var rnd = st.get("round")
	return "%s|%s" % [str(Store.room.get("code", "")), str(rnd.get("n")) if rnd is Dictionary else ""]


# 이벤트는 그 스냅샷의 state 다음에 옴 (store.gd) → Store.state.round.n 이 그 이벤트의 판. 판 (또는 방) 이 바뀌었으면 먼저 비움
func _on_event(e: Dictionary) -> void:
	tally.at_round(_round_key(Store.state))
	tally.feed(e)


# 스냅샷마다: 블록 마스터 판 중이면 마스터 편 id 를 기억 (판 끝 스냅샷엔 master 가 이미 false — awards_calc.gd note_state)
func _on_state(st: Dictionary, _prev: Dictionary) -> void:
	tally.at_round(_round_key(st))
	tally.note_state(st)


# 자리: 오른쪽에 붙이고 세로 가운데 조금 아래. 작은 창 (960×540 에 8명 + 칭호 3줄) 에서 판이 화면 밖으로 안 나가게
# 위·아래 여백 안으로 넣고, 그래도 넘치면 통째로 줄임 (계산은 ui_calc.gd results_place — tests/test_ui.gd 가 고정)
func _place() -> void:
	_place_in(get_viewport_rect().size)


# vp = 화면 크기 (테스트는 트리 밖이라 화면 크기를 못 읽어 직접 넣음)
func _place_in(vp: Vector2) -> void:
	var at := U.results_place(vp, size)
	scale = Vector2(at.scale, at.scale)
	position = Vector2(at.x, at.y)


# 칭호 줄 채우기. 마지막 킬 이벤트는 판 끝 스냅샷 뒤에 오므로 표 (key) 와 따로, 집계가 바뀌면 (tally.rev) 다시
func _fill_awards(st: Dictionary, k: String) -> void:
	var ak := "%s|%d" % [k, tally.rev]
	if ak == awards_key:
		return
	awards_key = ak
	var lines := Awards.pick(tally, st)
	for i in awards.size():
		var a: Label = awards[i]
		a.visible = i < lines.size()
		a.text = lines[i] if i < lines.size() else ""
	reset_size() # 줄이 줄면 판도 줄어듦 (컨테이너 밖 판은 저절로 안 줄어듦)
	_place()


func _color(p: Dictionary) -> Color:
	return Coords.color(C.PLAYER_PALETTE[int(p.get("color", p.get("slot", 0))) % C.PLAYER_PALETTE.size()])


func _name(p: Dictionary) -> String:
	return str(p.get("nick", "")) if str(p.get("nick", "")) != "" else str(p.get("name", "?"))


# W35: 승자 글 — 줄이 좁아도 '승 / 리' 로 끊기지 않게 승 리 사이에 WORD JOINER (안 보이는 글자)
static func win_text(who: String) -> String:
	return "%s 승\u2060리" % who


func refresh(st: Dictionary) -> void:
	var ps: Array = st.players.filter(func(p): return not p.get("spectator", false) and not p.get("dummy", false))
	var winners := {}
	var ids: Array = st.round.get("winnerIds", [])
	if ids.is_empty() and st.round.get("winnerId") != null:
		ids = [st.round.winnerId]
	for id in ids:
		winners[id] = true
	var kills: bool = st.get("mode") == "kills"
	var hp_on: bool = bool(st.get("hpMode", false)) # 체력전: '피해' 열 → '남은 HP'
	var k := "%s|%s|%s|%s" % [str(st.round.n), str(ids), JSON.stringify(ps.map(func(p): return [p.id, p.get("wins"), p.get("score"), p.damage, p.get("hp"), p.alive, p.get("cause")])), hp_on]
	var vp := get_viewport_rect().size
	visible = ps.size() >= 2 # JS livePlayers().length >= 2
	var small := U.small(vp)
	if small != small_was:
		key = ""
		apply_small(small)
	reset_size()
	_place_in(vp) # 자리·넘치면 줄이기 (칭호 줄이 붙어도 화면 안 — ui_calc results_place)
	if star_who != null and star_img.texture == null:
		star_img.texture = Portrait.tex(star_who[0], star_who[1], 192)
	for f in faces:
		if is_instance_valid(f[0]) and f[0].texture == null and f[1] != null:
			f[0].texture = Portrait.tex(f[1], f[2], 64)
	if k == key:
		_fill_awards(st, k)
		return
	key = k
	title.text = "라운드 %d 결과" % int(st.round.n)
	var top = null
	for p in ps:
		if winners.has(p.id):
			top = p
			break
	var wt = st.round.get("winnerTeam")
	if wt != null:
		head.text = "%s팀 승\u2060리" % TEAM_KO.get(str(wt), str(wt))
	elif winners.size() > 1:
		head.text = "공동 승\u2060리"
	elif top != null:
		head.text = win_text(_name(top))
	else:
		head.text = "무승부"
	head.add_theme_color_override("font_color", _color(top) if top != null else S.ACCENT)
	star.visible = top != null and top.get("char") != null # JS: 초상이 있을 때만
	star_img.texture = null
	star_who = null
	if top != null:
		star_box.border_color = _color(top)
		star_who = [top.get("char"), _color(top)]
	ps.sort_custom(func(a, b):
		var wa := 1 if winners.has(a.id) else 0
		var wb := 1 if winners.has(b.id) else 0
		if wa != wb:
			return wa > wb
		var sa := float(a.get("score", 0)) if kills else float(a.get("wins", 0))
		var sb := float(b.get("score", 0)) if kills else float(b.get("wins", 0))
		if sa != sb:
			return sa > sb
		return a.slot < b.slot)
	for c in table.get_children():
		c.free()
	win_rows = []
	faces = []
	var fs := 13 if small_was else 15
	var cell := func(t: String, size: int, col: Color, left := false, disp := false) -> Label:
		var l := S.label(t, size, col) if disp else S.body_label(t, size, col) # JS td system-ui (머리 줄 th·이름 td.n 은 disp)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT # JS td text-align right (이름만 왼쪽)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return l
	for h in ["이름", "캐릭터", "킬" if kills else "승", "남은 HP" if hp_on else "피해", "결과"]:
		table.add_child(cell.call(h, 12, Color("a49cbc"), h == "이름", true))
	for p in ps:
		var row_col := Color("e6e0f4") # JS #results 글자색 (승자 줄은 바탕 gb 로)
		# 이름 칸: 초상 32 (아래 2px 그 사람 색) + 이름 18 (JS td.n .face)
		var nm := HBoxContainer.new()
		nm.add_theme_constant_override("separation", 5)
		var face := PanelContainer.new()
		var fb := StyleBoxFlat.new()
		fb.bg_color = Color(0, 0, 0, 0.3)
		fb.border_width_bottom = 2
		fb.border_color = _color(p)
		fb.skew = Vector2(0.16, 0)
		face.add_theme_stylebox_override("panel", fb)
		face.custom_minimum_size = Vector2.ONE * (26 if small_was else 32)
		var fimg := TextureRect.new()
		fimg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fimg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face.add_child(fimg)
		faces.append([fimg, p.get("char"), _color(p)])
		nm.add_child(face)
		nm.add_child(cell.call(_name(p), 15 if small_was else 18, _color(p), true, true))
		table.add_child(nm)
		if winners.has(p.id):
			win_rows.append(nm)
		table.add_child(cell.call(C.CHAR_NAMES.get(str(p.get("char", "")), "—"), fs, row_col))
		table.add_child(cell.call("%d" % int(p.get("score", 0) if kills else p.get("wins", 0)), fs, row_col))
		var hv = U.hp_view(p, st) if hp_on else null
		table.add_child(cell.call(("%d" % (int(hv.hp) if p.alive else 0)) if hv != null else "%d%%" % int(p.damage), fs, row_col))
		table.add_child(cell.call("생존" if p.alive else CAUSE_KO.get(str(p.get("cause", "")), "탈락"), fs, row_col))
	table.queue_redraw()
	_fill_awards(st, k)
