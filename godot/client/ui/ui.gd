# G4 화면 뿌리 (CanvasLayer UI): 메뉴 · 대기실 판 · 방장 판 · (판 HUD·결과·설정 — 다음 단계) · 화면 전환 슬래시 · 접속 글·핑.
# 지금 화면 = ui_calc.screen_of (JS shared/wipe.js screenOf), 바뀌면 슬래시가 다 덮는 순간 뒤 화면을 바꿈 (JS updateScreen)
extends CanvasLayer

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const U := preload("res://ui/ui_calc.gd")

var menu: Control
var lobby: PanelContainer
var host_players: PanelContainer
var wipe: Control
var status: Label
var ping: Label
var shown := "" # 지금 보이는 화면 (menu·lobby·game·results)
var target := "" # 바뀌려는 화면 (슬래시가 덮으면 shown 이 됨)


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	menu = load("res://ui/menu.gd").new()
	root.add_child(menu)
	lobby = load("res://ui/lobby.gd").new()
	root.add_child(lobby)
	host_players = load("res://ui/host_players.gd").new()
	root.add_child(host_players)
	status = S.label("연결 중...", 16, S.TEXT)
	status.position = Vector2(16, 12)
	root.add_child(status)
	ping = S.label("", 12, S.DIM)
	ping.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ping.position = Vector2(-120, 52)
	ping.size.x = 108
	ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ping)
	wipe = load("res://ui/wipe.gd").new()
	root.add_child(wipe)
	wipe.covered.connect(func(): _show(target))
	Net.status_changed.connect(func(t): status.text = t)
	_show(_screen_now())


func reduced() -> bool:
	return bool(View.settings.get("lowGraphics", false)) or bool(View.settings.get("reducedMotion", false))


func _screen_now() -> String:
	var st := Store.state
	if not Store.in_room() or st.is_empty():
		return "menu"
	return U.screen_of(true, str(st.phase), false, false) # 결과 연출(hero)·클로즈업은 결과 단계에서


func _show(screen: String) -> void:
	shown = screen
	target = screen
	menu.visible = screen == "menu"
	lobby.visible = screen == "lobby"
	host_players.visible = false
	status.visible = screen != "menu" and screen != "lobby"


func _process(_d: float) -> void:
	ping.text = Net.ping_text()
	var now := _screen_now()
	if now != target:
		var kind = U.wipe_kind(target, now)
		target = now
		if kind == null or not wipe.play(kind, reduced()):
			_show(now)
	var st := Store.state
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
	if PlayerInput.ui_blocking or st.is_empty() or st.get("hostId") != Store.my_id or not st.get("canStart", false):
		return
	if st.phase == "lobby" or st.phase == "over":
		Store.send_room({"type": "start"})
		get_viewport().set_input_as_handled()
