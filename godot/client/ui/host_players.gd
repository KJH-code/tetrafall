# 플레이어 관리 (방장, 대기실 왼쪽 위 — JS #host-players updateHostPlayers): 팀전 켜기·팀 섞기, 사람마다 팀·관전/참가·내보내기
extends PanelContainer

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Coords := preload("res://core/coords.gd")

const TEAM_KO := {"red": "빨강", "blue": "파랑"}
const TEAM_MAIN := {"red": Color("ff5a4a"), "blue": Color("4aa8ff")}
const U := preload("res://ui/ui_calc.gd")

var grid: GridContainer
var box: VBoxContainer # 제목·팀전 줄 (JS .title grid-column 1 / -1 — 표 전체 폭) + 표
var head: VBoxContainer
var key := ""


var pane_box: StyleBoxFlat


func _ready() -> void:
	pane_box = S.pane() # JS #host-players padding 10 14 10 18 (작은 창 8 10)
	add_theme_stylebox_override("panel", pane_box)
	position = Vector2(14, 96)
	visibility_changed.connect(func(): if visible and not S.reduced(): S.slide_in(self, -30.0)) # JS slide-left .2s
	box = VBoxContainer.new()
	add_child(box)
	head = VBoxContainer.new()
	box.add_child(head)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)


func refresh(st: Dictionary) -> void:
	var ps: Array = st.players.duplicate()
	ps.sort_custom(func(a, b): return a.slot < b.slot)
	var small := U.small(get_viewport_rect().size)
	var k := JSON.stringify(ps.map(func(p): return [p.id, p.get("spectator"), p.get("nick"), p.get("team"), p.get("color"), p.get("away")])) + "|%s|%s|%s" % [str(st.get("teamMode")), str(st.get("mode")), small]
	if k == key:
		return
	key = k
	pane_box.content_margin_top = 8 if small else 10
	pane_box.content_margin_bottom = 8 if small else 10
	pane_box.content_margin_left = 10 if small else 18
	pane_box.content_margin_right = 10 if small else 14
	grid.add_theme_constant_override("h_separation", 5 if small else 7)
	grid.add_theme_constant_override("v_separation", 4 if small else 5)
	box.add_theme_constant_override("separation", 4 if small else 5) # JS grid gap 5 7 (작은 창 4 5) — 제목 줄도 표의 줄
	head.add_theme_constant_override("separation", 4 if small else 5)
	var fs := 12 if small else 13
	var bs := 11 if small else 12
	# 버튼 (JS #host-players button: 12px · padding 2 9, 작은 창 11px · 2 7)
	var btn := func(t: String, cb: Callable) -> Button:
		var b := S.button(t, cb, "ghost", bs)
		for stn in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(stn)
			sb.content_margin_left = 7 if small else 9
			sb.content_margin_right = 7 if small else 9
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
		return b
	for c in grid.get_children() + head.get_children():
		c.free() # 바로 지움 (queue_free 면 한 프레임 동안 옛 칸까지 재서 판이 넓어짐)
	# 제목·팀전 줄은 표 밖 (JS .title grid-column 1 / -1: 표 전체 폭) — 예전엔 표 첫 칸이라 이름 열이 제목 폭 (128) 으로 넓어져 판 265 (JS 177)
	var title := S.glow_label("플레이어 관리 (호스트)", 14, Color.WHITE, 3)
	head.add_child(title)
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8) # JS 팀 섞기 marginLeft 8
	head.add_child(team_row)
	var team := CheckBox.new()
	team.text = "팀전 (빨강 vs 파랑)"
	S.style_check(team, 14) # JS .title 14px 글꼴 disp
	team.button_pressed = bool(st.get("teamMode", false))
	team.disabled = st.get("mode") == "master" # 블록 마스터는 1 대 다
	team.toggled.connect(func(on): Store.send_room({"type": "teamMode", "on": on}))
	team_row.add_child(team)
	if st.get("teamMode", false):
		team_row.add_child(btn.call("팀 섞기", func(): Store.send_room({"type": "shuffleTeams"})))
	for p in ps:
		var nm := str(p.get("nick", "")) if str(p.get("nick", "")) != "" else str(p.name)
		var who := S.label("%s%s%s%s" % [nm, " (나)" if p.id == Store.my_id else "", " · 관전" if p.get("spectator", false) else "", " · 자리 비움" if p.get("away", false) else ""], fs, Coords.color(C.PLAYER_PALETTE[int(p.get("color", p.slot)) % C.PLAYER_PALETTE.size()]))
		if p.get("away", false):
			who.modulate.a = 0.6
		grid.add_child(who)
		var id = p.id
		if st.get("teamMode", false):
			var t := str(p.get("team", "red"))
			var tb: Button = btn.call(TEAM_KO.get(t, t), func(): Store.send_room({"type": "setTeam", "target": id, "team": "blue" if t == "red" else "red"}))
			tb.add_theme_color_override("font_color", TEAM_MAIN.get(t, Color.WHITE)) # JS: 팀 색 글자
			grid.add_child(tb)
		else:
			grid.add_child(Control.new())
		var spec_on: bool = p.get("spectator", false)
		grid.add_child(btn.call("참가로" if spec_on else "관전으로", func(): Store.send_room({"type": "spectate", "target": id, "on": not spec_on})))
		if p.id != Store.my_id:
			grid.add_child(btn.call("내보내기", func(): Store.send_room({"type": "kick", "target": id})))
		else:
			grid.add_child(Control.new())
	reset_size() # 판 폭 = 내용 (줄어들 때도)
