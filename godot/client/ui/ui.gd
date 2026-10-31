# G4 화면 뿌리 (CanvasLayer UI): 메뉴 · 대기실 판 · 방장 판 · (판 HUD·결과·설정 — 다음 단계) · 화면 전환 슬래시 · 접속 글·핑.
# 지금 화면 = ui_calc.screen_of (JS shared/wipe.js screenOf), 바뀌면 슬래시가 다 덮는 순간 뒤 화면을 바꿈 (JS updateScreen)
extends CanvasLayer

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const U := preload("res://ui/ui_calc.gd")

var menu: Control
var lobby: PanelContainer
var host_players: PanelContainer
var hud: Control
var results: PanelContainer
var settings: Control
var over_at := -1.0 # 판이 끝난 시각 (결과 연출 RESULTS_HERO_MS)
var wipe: Control
var status: Label
var ping: Label
var shown := "" # 지금 보이는 화면 (menu·lobby·game·results)
var target := "" # 바뀌려는 화면 (슬래시가 덮으면 shown 이 됨)


func _ready() -> void:
	layer = 10
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
	Store.state_changed.connect(_on_state)
	wipe.covered.connect(func(): _show(target))
	Net.status_changed.connect(func(t): status.text = t)
	_show(_screen_now())


func reduced() -> bool:
	return bool(View.settings.get("lowGfx", false)) or bool(View.settings.get("reducedMotion", false))


func _screen_now() -> String:
	var st := Store.state
	if not Store.in_room() or st.is_empty():
		return "menu"
	var hero: bool = st.phase == "over" and over_at >= 0.0 and Time.get_ticks_msec() - over_at < C.RESULTS_HERO_MS and not Store.room.get("practice", false)
	return U.screen_of(true, str(st.phase), hero, false) # 승자 클로즈업 (shared/victory.js) 은 G5 KO 연출과 같이


func _on_state(st: Dictionary, prev: Dictionary) -> void:
	if prev.get("phase") == "playing" and st.get("phase") == "over":
		over_at = Time.get_ticks_msec()
	elif st.get("phase") != "over":
		over_at = -1.0


func _show(screen: String) -> void:
	shown = screen
	target = screen
	menu.visible = screen == "menu"
	lobby.visible = screen == "lobby"
	host_players.visible = false
	hud.visible = screen == "game"
	results.visible = screen == "results"


func _process(_d: float) -> void:
	ping.text = Net.ping_text()
	# 메뉴·대기실·결과·설정이 떠 있거나 글자 칸에 커서가 있으면 게임 키·마우스 잡기를 막음 (판 중 HUD 는 안 막음)
	var focus := get_viewport().gui_get_focus_owner()
	PlayerInput.ui_blocking = settings.visible or shown in ["menu", "lobby", "results"] or focus is LineEdit
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
