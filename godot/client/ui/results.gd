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
var star: ColorRect
var star_img: TextureRect # 승자 초상 (192 얼굴)
var star_who = null # [char, color] — 그려지면 넣음
var head: Label
var table: GridContainer
var key := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", S.pane())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	title = S.glow_label("", 20, Color.WHITE, 4)
	v.add_child(title)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 14)
	star = ColorRect.new() # 승자 초상 자리 (G2 몸 SubViewport)
	star.custom_minimum_size = Vector2(128, 128)
	star_img = TextureRect.new()
	star_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	star_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.add_child(star_img)
	who.add_child(star)
	head = S.glow_label("", 34, Color.WHITE, 6)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(head)
	v.add_child(who)
	table = GridContainer.new()
	table.columns = 5
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 4)
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
	position = Vector2(vp.x - size.x - 12, (vp.y - size.y) / 2.0 + 22)
	if star_who != null and star_img.texture == null:
		star_img.texture = Portrait.tex(star_who[0], star_who[1], 192)
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
	star.visible = top != null
	star_img.texture = null
	star_who = null
	if top != null:
		star.color = _color(top)
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
	for h in ["이름", "캐릭터", "킬" if kills else "승", "남은 HP" if hp_on else "피해", "결과"]:
		table.add_child(S.label(h, 12, Color("a49cbc")))
	for p in ps:
		var row_col := Color(1, 0.82, 0.23) if winners.has(p.id) else S.TEXT
		table.add_child(S.label(_name(p), 18, _color(p)))
		table.add_child(S.label(C.CHAR_NAMES.get(str(p.get("char", "")), "—"), 15, row_col))
		table.add_child(S.label("%d" % int(p.get("score", 0) if kills else p.get("wins", 0)), 15, row_col))
		var hv = U.hp_view(p, st) if hp_on else null
		table.add_child(S.label(("%d" % (int(hv.hp) if p.alive else 0)) if hv != null else "%d%%" % int(p.damage), 15, row_col))
		table.add_child(S.label("생존" if p.alive else CAUSE_KO.get(str(p.get("cause", "")), "탈락"), 15, row_col))
