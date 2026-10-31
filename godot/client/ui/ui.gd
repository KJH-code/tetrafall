# G4 화면 뿌리 (CanvasLayer UI): 메뉴 · 대기실 판 · 방장 판 · (판 HUD·결과·설정 — 다음 단계) · 화면 전환 슬래시 · 접속 글·핑.
# 지금 화면 = ui_calc.screen_of (JS shared/wipe.js screenOf), 바뀌면 슬래시가 다 덮는 순간 뒤 화면을 바꿈 (JS updateScreen)
extends CanvasLayer

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const U := preload("res://ui/ui_calc.gd")
const Portrait := preload("res://ui/portrait.gd")
const Coords := preload("res://core/coords.gd")
const Prefs := preload("res://ui/ui_prefs.gd")

var menu: Control
var lobby: PanelContainer
var host_players: PanelContainer
var hud: Control
var hud_extra: Control # 판 HUD 나머지 (배너·경고·알림·콤보·이모트 바퀴·도움말·버프·아이템 칸 …)
var results: PanelContainer
var settings: Control
var wipe: Control
var status: Label
var ping: Label
var shown := "" # 지금 보이는 화면 (menu·lobby·game·results)
var target := "" # 바뀌려는 화면 (슬래시가 덮으면 shown 이 됨)
var menu_since := -1.0 # 메뉴가 뜬 시각 (PORTRAIT_WARM_MS 뒤 카드 초상 미리 그리기)
var warmed := false
var covers_key := "" # View.covers 를 바뀔 때만 넣음


func _ready() -> void:
	layer = 10
	add_child(Portrait.new()) # 초상 그리기 (Portrait.inst)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	menu = load("res://ui/menu.gd").new()
	root.add_child(menu)
	lobby = load("res://ui/lobby.gd").new()
	root.add_child(lobby)
	host_players = load("res://ui/host_players.gd").new()
	root.add_child(host_players)
	hud = load("res://ui/hud.gd").new()
	root.add_child(hud)
	hud_extra = load("res://ui/hud_extra.gd").new()
	hud_extra.hud = hud
	root.add_child(hud_extra)
	results = load("res://ui/results.gd").new()
	root.add_child(results)
	status = S.label("연결 중...", 16, S.TEXT)
	status.position = Vector2(16, 12)
	root.add_child(status)
	ping = S.label("", 12, S.DIM)
	ping.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ping.position = Vector2(-120, 52)
	ping.size.x = 108
	ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ping)
	settings = load("res://ui/settings.gd").new()
	root.add_child(settings)
	menu.open_settings.connect(func(): settings.visible = true)
	lobby.open_settings.connect(func(): settings.visible = true)
	menu.open_tutorial.connect(func(): View.open_panel.emit("tutorial")) # G6 ui/tutorial_ui.gd
	settings.open_tutorial.connect(func():
		settings.visible = false
		View.open_panel.emit("tutorial"))
	wipe = load("res://ui/wipe.gd").new()
	root.add_child(wipe)
	wipe.covered.connect(func(): _show(target))
	Net.status_changed.connect(func(t): status.text = t)
	_show(_screen_now())


func reduced() -> bool:
	return bool(View.settings.get("lowGfx", false)) or bool(View.settings.get("reducedMotion", false))


func _screen_now() -> String:
	var st := Store.state
	if not Store.in_room() or st.is_empty():
		return "menu"
	# 판 끝 연출 단계 (shared/victory.js — G1 카메라가 View.victory_stage 에 넣음): slow·closeup 동안은 판 화면 그대로 (승자 클로즈업을 안 가림),
	# results 부터 결과 표, lobby 면 대기실 판 (JS overStage·resultsHeroNow·closeupNow)
	var stage := over_stage()
	return U.screen_of(true, str(st.phase), stage != "lobby", stage == "slow" or stage == "closeup")


static func over_stage() -> String:
	var st := Store.state
	if st.is_empty() or st.get("phase") != "over" or Store.room.get("practice", false):
		return "lobby"
	return str(View.victory_stage)


func _show(screen: String) -> void:
	if screen == "menu" and shown != "menu":
		menu_since = Time.get_ticks_msec()
	shown = screen
	target = screen
	menu.visible = screen == "menu"
	lobby.visible = screen == "lobby"
	host_players.visible = false
	hud.visible = screen == "game"
	hud_extra.visible = screen == "game"
	results.visible = screen == "results"


func _process(_d: float) -> void:
	ping.text = Net.ping_text()
	menu.visible = shown == "menu" and not View.title_on # 타이틀 동안은 메뉴 판 숨김 (title/title.gd)
	_put_covers()
	if not warmed and shown == "menu" and menu_since >= 0.0 and Time.get_ticks_msec() - menu_since >= C.PORTRAIT_WARM_MS and Portrait.inst != null:
		warmed = true
		Portrait.inst.warm(Coords.color(C.PLAYER_PALETTE[int(Prefs.get_value("color", 0)) % C.PLAYER_PALETTE.size()]))
	# 메뉴·대기실·결과·설정이 떠 있거나 글자 칸에 커서가 있으면 게임 키·마우스 잡기를 막음 (판 중 HUD 는 안 막음)
	var focus := get_viewport().gui_get_focus_owner()
	# 다른 화면 (연습 창·튜토리얼 창) 은 'ui_blocker' 무리 + blocking() — 여기서 한 번에 정해야 서로 덮어쓰지 않음
	var others := get_tree().get_nodes_in_group("ui_blocker").any(func(n): return bool(n.call("blocking")))
	PlayerInput.ui_blocking = settings.visible or shown in ["menu", "lobby", "results"] or focus is LineEdit or others
	status.visible = not Net.is_open() # 연결 중·끊김 글만 (판 시간은 HUD)
	var now := _screen_now()
	if now != target:
		var kind = U.wipe_kind(target, now)
		target = now
		if kind == null or not wipe.play(kind, reduced()):
			_show(now)
	var st := Store.state
	if shown == "game" and not st.is_empty():
		hud.refresh(st)
		hud_extra.refresh(st)
	if shown == "results" and not st.is_empty():
		results.refresh(st)
	if shown == "lobby" and not st.is_empty():
		lobby.refresh(st)
		var host: bool = st.get("hostId") == Store.my_id
		host_players.visible = host
		if host:
			host_players.refresh(st)


# Enter: 대기실·판 끝에 방장이면 시작 (판 중 Enter 는 블록 하드드롭이라 PlayerInput 이 가짐)
func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ENTER):
		return
	var st := Store.state
	if get_viewport().gui_get_focus_owner() is LineEdit or settings.visible or st.is_empty() or st.get("hostId") != Store.my_id or not st.get("canStart", false):
		return
	if st.phase == "lobby" or st.phase == "over":
		Store.send_room({"type": "start"})
		get_viewport().set_input_as_handled()


# 보이는 판의 화면 사각형 → View.covers (그 안의 3D 머리 위 이름표는 G1 이 숨김 — 대기실 이름표가 판과 겹치던 것).
# 대기실 판·플레이어 관리·결과 판·설정 창·Tab 점수표·부활 판. 바뀔 때만 넣음. View 에 covers 가 없는 판이면 set 이 그냥 무시
func _put_covers() -> void:
	var rects: Array = []
	var list: Array = [lobby, host_players, results, settings, hud.get("board"), hud.get("respawn")]
	for c in list:
		if c is Control and (c as Control).is_visible_in_tree():
			rects.append((c as Control).get_global_rect())
	var k := str(rects)
	if k == covers_key:
		return
	covers_key = k
	View.set("covers", rects)
