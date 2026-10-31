# 플레이어 관리 (방장, 대기실 왼쪽 위 — JS #host-players updateHostPlayers): 팀전 켜기·팀 섞기, 사람마다 팀·관전/참가·내보내기
extends PanelContainer

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Coords := preload("res://core/coords.gd")

const TEAM_KO := {"red": "빨강", "blue": "파랑"}

var grid: GridContainer
var key := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", S.pane())
	position = Vector2(14, 96)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 5)
	add_child(grid)


func refresh(st: Dictionary) -> void:
	var ps: Array = st.players.duplicate()
	ps.sort_custom(func(a, b): return a.slot < b.slot)
	var k := JSON.stringify(ps.map(func(p): return [p.id, p.get("spectator"), p.get("nick"), p.get("team"), p.get("color"), p.get("away")])) + "|%s|%s" % [str(st.get("teamMode")), str(st.get("mode"))]
	if k == key:
		return
	key = k
	for c in grid.get_children():
		c.queue_free()
	var title := S.glow_label("플레이어 관리 (호스트)", 14, Color.WHITE, 3)
	grid.add_child(title)
	for i in 3:
		grid.add_child(Control.new())
	var team := CheckBox.new()
	team.text = "팀전 (빨강 vs 파랑)"
	S.style_check(team, 13)
	team.button_pressed = bool(st.get("teamMode", false))
	team.disabled = st.get("mode") == "master" # 블록 마스터는 1 대 다
	team.toggled.connect(func(on): Store.send_room({"type": "teamMode", "on": on}))
	grid.add_child(team)
	if st.get("teamMode", false):
		grid.add_child(S.button("팀 섞기", func(): Store.send_room({"type": "shuffleTeams"}), "ghost", 12))
	else:
		grid.add_child(Control.new())
	grid.add_child(Control.new())
	grid.add_child(Control.new())
	for p in ps:
		var nm := str(p.get("nick", "")) if str(p.get("nick", "")) != "" else str(p.name)
		var who := S.label("%s%s%s%s" % [nm, " (나)" if p.id == Store.my_id else "", " · 관전" if p.get("spectator", false) else "", " · 자리 비움" if p.get("away", false) else ""], 13, Coords.color(C.PLAYER_PALETTE[int(p.get("color", p.slot)) % C.PLAYER_PALETTE.size()]))
		if p.get("away", false):
			who.modulate.a = 0.6
		grid.add_child(who)
		var id = p.id
		if st.get("teamMode", false):
			var t := str(p.get("team", "red"))
			var tb := S.button(TEAM_KO.get(t, t), func(): Store.send_room({"type": "setTeam", "target": id, "team": "blue" if t == "red" else "red"}), "ghost", 12)
			grid.add_child(tb)
		else:
			grid.add_child(Control.new())
		var spec_on: bool = p.get("spectator", false)
		grid.add_child(S.button("참가로" if spec_on else "관전으로", func(): Store.send_room({"type": "spectate", "target": id, "on": not spec_on}), "ghost", 12))
		if p.id != Store.my_id:
			grid.add_child(S.button("내보내기", func(): Store.send_room({"type": "kick", "target": id}), "ghost", 12))
		else:
			grid.add_child(Control.new())
