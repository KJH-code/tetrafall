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

const CAUSE_KO := {"crush": "압사", "fall": "낙사", "lava": "용암", "hp": "체력"}
const TEAM_KO := {"red": "빨강", "blue": "파랑"}

var title: Label
var star: ColorRect
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
	table.add_theme_constant_override("v_separation", 4)
	v.add_child(table)


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
	_place()
	if star_who != null and star_img.texture == null:
		star_img.texture = Portrait.tex(star_who[0], star_who[1], 192)
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
	_fill_awards(st, k)
