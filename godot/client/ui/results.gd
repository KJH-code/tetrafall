# 판 끝 결과 (JS #results updateResults): 판이 끝나고 RESULTS_HERO_MS 동안만, 오른쪽에 붙은 빛 판 — 승자 초상 (G2 전엔 색 상자) + 승리 글 + 결과 표
# (이름·캐릭터·승/킬·피해·결과). 승자가 먼저, 그다음 승/킬 순
extends PanelContainer

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Portrait := preload("res://ui/portrait.gd")
const U := preload("res://ui/ui_calc.gd")
const Coords := preload("res://core/coords.gd")

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


func _color(p: Dictionary) -> Color:
	return Coords.color(C.PLAYER_PALETTE[int(p.get("color", p.get("slot", 0))) % C.PLAYER_PALETTE.size()])


func _name(p: Dictionary) -> String:
	return str(p.get("nick", "")) if str(p.get("nick", "")) != "" else str(p.get("name", "?"))


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
	if small != small_was: # JS 작은 창: padding 11 16 12 22, 초상 96, 승리 글 30, 표 13, 이름 15, 얼굴 26
		small_was = small
		key = ""
		pane_box.content_margin_top = 11 if small else 16
		pane_box.content_margin_right = 16 if small else 22
		pane_box.content_margin_bottom = 12 if small else 18
		pane_box.content_margin_left = 22 if small else 28
		star.custom_minimum_size = Vector2.ONE * (96 if small else 128)
		head.add_theme_font_size_override("font_size", 30 if small else 34)
	reset_size()
	position = Vector2(vp.x - size.x - 12, (vp.y - size.y) / 2.0 + 22)
	if star_who != null and star_img.texture == null:
		star_img.texture = Portrait.tex(star_who[0], star_who[1], 192)
	for f in faces:
		if is_instance_valid(f[0]) and f[0].texture == null and f[1] != null:
			f[0].texture = Portrait.tex(f[1], f[2], 64)
	if k == key:
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
		head.text = "%s팀 승리" % TEAM_KO.get(str(wt), str(wt))
	elif winners.size() > 1:
		head.text = "공동 승리"
	elif top != null:
		head.text = "%s 승리" % _name(top)
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
	var cell := func(t: String, size: int, col: Color, left := false) -> Label:
		var l := S.label(t, size, col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT # JS td text-align right (이름만 왼쪽)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return l
	for h in ["이름", "캐릭터", "킬" if kills else "승", "남은 HP" if hp_on else "피해", "결과"]:
		table.add_child(cell.call(h, 12, Color("a49cbc"), h == "이름"))
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
		nm.add_child(cell.call(_name(p), 15 if small_was else 18, _color(p), true))
		table.add_child(nm)
		if winners.has(p.id):
			win_rows.append(nm)
		table.add_child(cell.call(C.CHAR_NAMES.get(str(p.get("char", "")), "—"), fs, row_col))
		table.add_child(cell.call("%d" % int(p.get("score", 0) if kills else p.get("wins", 0)), fs, row_col))
		var hv = U.hp_view(p, st) if hp_on else null
		table.add_child(cell.call(("%d" % (int(hv.hp) if p.alive else 0)) if hv != null else "%d%%" % int(p.damage), fs, row_col))
		table.add_child(cell.call("생존" if p.alive else CAUSE_KO.get(str(p.get("cause", "")), "탈락"), fs, row_col))
	table.queue_redraw()
