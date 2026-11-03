# 키보드·마우스 입력 (자동 로드 PlayerInput, client/input.js 그대로): 연속 입력은 INPUT_SEND_RATE 로, 단발 행동은 바로 서버에.
# 키 이름은 브라우저 e.code 글자 (keys.gd) → JS 판과 같은 키 설정. 판 중·살아 있을 때만 행동 (enabled, Store 스냅샷으로 정함)
# 화면 묶음이 쓰는 것: yaw·pitch (카메라), ui_action 신호 (도움말·시점·연습·성능·튜토리얼 넘기기·하늘 시점 돌리기), wheel_changed (이모트 바퀴)
extends Node

const Prof := preload("res://core/prof.gd")

const C := preload("res://core/config.gd")
const Keys := preload("res://core/keys.gd")

signal ui_action(id: String, pressed: bool)
signal wheel_changed(slot: int) # -2 = 닫힘, -1 = 열림·안 고름, 0~ = 고른 칸
signal action_sent(action: Dictionary) # 서버로 보낸 단발 행동 (내 평타 휘두름 소리·몸을 서버 응답 전에 바로 — JS onLocalAction)

var binds := {}
var by_code := {}
var keys := {} # 지금 눌린 코드
var yaw := 0.0
var pitch := 0.0
var locked := false # 마우스 잡힘 (브라우저 pointer lock 과 같음)
var enabled := false
var sky := false # 하늘 시점: 마우스 회전 무시
var sensitivity := 1.0
var wheel = null # 이모트 바퀴: 연 뒤 마우스 이동량 Vector2
var ui_blocking := false # 메뉴·글자 칸이 열려 있으면 화면 묶음이 true (게임 키 안 받음)
var typing := false # 글자 칸에 커서 (ui.gd 가 정함). 막혀 있어도 글자 칸이 아니면 성능 표시 키는 됨 (JS 는 글 칠 때만 키를 안 받음 — F3 은 메뉴·대기실에서도)
var override = null # 시험·자동 조종: 이 dict 를 input 대신 보냄 (client debug.inputOverride)
var _send_acc := 0.0


func _ready() -> void:
	set_binds(Keys.load_binds())
	Store.state_changed.connect(_on_state)
	Store.joined.connect(func(_room, rejoined): _on_joined(rejoined))
	Store.left_room.connect(_on_left_room)
	Net.message.connect(_on_message)
	Store.game_event.connect(_on_event)


func set_binds(b: Dictionary) -> void:
	binds = b.duplicate()
	by_code = {}
	for id in binds:
		var code: String = binds[id]
		if not by_code.has(code):
			by_code[code] = []
		by_code[code].append(id)


func held(id: String) -> bool:
	return keys.has(binds.get(id, ""))


func set_yaw_pitch(y: float, p: float) -> void:
	yaw = y
	pitch = p


func lock_mouse(on: bool) -> void:
	locked = on
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	if not on:
		release_all()


# 눌린 키 전부 놓음 + 누르고 있어야 열려 있는 것 (이모트 바퀴·도움말·킬 점수전 점수표) 닫기 (input.js releaseAll).
# 창이 포커스를 잃거나 마우스가 풀릴 때 — 예전엔 Esc 로 풀면 keys 만 비워 G 바퀴가 열린 채 남고, 다시 잡아도 바퀴가 마우스를 가로채 시점이 안 돎
func release_all() -> void:
	keys.clear()
	if wheel != null:
		wheel = null
		wheel_changed.emit(-2)
	ui_action.emit("help", false)
	ui_action.emit("practice", false)


# 판 크기별 시작 자리 (shared/config.js spawnPointsFor = spawnPoints(W, D, SPAWN_INSET)). 안쪽 거리는 기본 판 첫 자리 x 와 같음
static func spawn_points_for(w: float, d: float) -> Array:
	var inset: float = C.SPAWN_POINTS[0].x
	var out := []
	for xy in [[inset, inset], [w - inset, d - inset], [w - inset, inset], [inset, d - inset], [w / 2.0, inset], [w / 2.0, d - inset], [inset, d / 2.0], [w - inset, d / 2.0]]:
		out.append({"x": xy[0], "y": xy[1], "yaw": atan2(d / 2.0 - xy[1], w / 2.0 - xy[0])})
	return out


# 들어오면 시작 자리 방향을 봄 (welcome.slot, main.js), 재접속이면 다음 스냅샷의 내 방향
var _aim_from_state := false


func _on_joined(rejoined: bool) -> void:
	_aim_from_state = rejoined


# 방을 나가면 마우스 풀기 (main.js leftRoom 의 exitPointerLock) — 안 풀면 메뉴에서 커서가 안 보임
func _on_left_room(_reason: String) -> void:
	lock_mouse(false)


func _on_message(m: Dictionary) -> void:
	if str(m.get("type", "")) == "welcome" and not m.get("rejoined", false) and m.get("slot") != null:
		var sp: Dictionary = C.SPAWN_POINTS[int(m.slot) % C.SPAWN_POINTS.size()]
		set_yaw_pitch(sp.yaw, 0)


func _on_state(st: Dictionary, prev: Dictionary) -> void:
	var p := Store.me()
	if _aim_from_state and not p.is_empty():
		set_yaw_pitch(p.yaw, p.get("pitch", 0.0))
		_aim_from_state = false
	var ph := str(st.get("phase", ""))
	enabled = (ph == "playing" or ph == "countdown") and not p.is_empty() and p.alive
	# 판 사이 (결과·대기실) 에는 마우스를 풀어 커서가 보이게: 잡은 채로 대기실에 오면 버튼을 누를 수 없고 커서도 안 보임. 다시 잡는 건 '화면 클릭' (연습 방은 판이 안 끝남)
	if locked and not Store.room.get("practice", false) and (ph == "over" or ph == "lobby" or ph == ""):
		lock_mouse(false)
	# 판이 새로 시작되면 시점을 스폰 방향으로 (main.js onState) — 예전엔 판이 바뀌어도 전 판 끝에 보던 쪽 그대로
	if not p.is_empty() and not prev.is_empty() and _round_n(prev) != _round_n(st):
		var f: Dictionary = st.get("field", {})
		var pts: Array = spawn_points_for(float(f.w), float(f.d)) if f.has("w") else C.SPAWN_POINTS
		set_yaw_pitch(pts[int(p.slot) % pts.size()].yaw, 0)


static func _round_n(st: Dictionary):
	var rd = st.get("round")
	return rd.get("n") if rd is Dictionary else null


# 튜토리얼 단계 처음: 그 자리에서 볼 쪽으로 (main.js handleEvent tutorialStep)
func _on_event(e: Dictionary) -> void:
	if str(e.get("type", "")) == "tutorialStep" and Store.my_id != null and e.get("who") != null and int(e.who) == Store.my_id and e.has("yaw"):
		set_yaw_pitch(float(e.yaw), 0)


func _process(delta: float) -> void:
	var _pt := Prof.now() # 성능 구간 (--perf-log 만, core/prof.gd)
	_prof_process(delta)
	Prof.add("입력", _pt)


func _prof_process(delta: float) -> void:
	var ph := Store.phase()
	if ph != "playing" and ph != "countdown":
		_send_acc = 0.0
		return
	_send_acc += delta
	var step := 1.0 / C.INPUT_SEND_RATE
	if _send_acc >= step:
		_send_acc = fmod(_send_acc, step)
		Net.send(override if override != null else sample())


func _input(e: InputEvent) -> void:
	if ui_blocking:
		_input_blocked(e)
		return
	if e is InputEventMouseMotion:
		# screen_relative = 창 픽셀 (relative 는 UI 배율 (core/ui_scale.gd) 로 나눈 UI 좌표라 창 크기마다 감도가 바뀜, W9)
		if wheel != null:
			wheel += e.screen_relative
			wheel_changed.emit(wheel_pick())
			return
		if not locked or sky:
			return
		yaw -= e.screen_relative.x * C.MOUSE_SENSITIVITY * sensitivity
		pitch -= e.screen_relative.y * C.MOUSE_SENSITIVITY * sensitivity
		var lim := PI / 2 - 0.05
		pitch = clampf(pitch, -lim, lim)
		return
	if e is InputEventMouseButton:
		if e.pressed and not locked and e.button_index == MOUSE_BUTTON_LEFT and Store.in_room():
			lock_mouse(true) # 잠기기 전 클릭은 화면 클릭 (잠그기)
			return
		var code := Keys.event_code(e)
		if code == "":
			return
		if e.pressed:
			if locked:
				down(code)
		else:
			up(code)
		return
	if e is InputEventKey and not e.echo:
		if e.pressed and e.physical_keycode == KEY_ESCAPE and locked:
			lock_mouse(false) # 브라우저 Esc 처럼 마우스 풀기
			return
		var code := Keys.norm_code(Keys.event_code(e))
		if code == "":
			return
		if e.pressed:
			if down(code):
				get_viewport().set_input_as_handled()
		else:
			up(code)


# 창·글자 칸이 떠 있을 때: 뗌은 그대로 받음 (JS keyup·mouseup 은 글 칠 때도 받음 — 누른 채 창이 열리면 키가 눌린 채로 남아 계속 걷던 것),
# 글자 칸이 아니면 성능 표시 키도 (JS F3 은 메뉴·대기실에서도 됨)
func _input_blocked(e: InputEvent) -> void:
	if e is InputEventMouseButton and not e.pressed:
		up(Keys.event_code(e))
	elif e is InputEventKey and not e.echo:
		var code := Keys.norm_code(Keys.event_code(e))
		if not e.pressed:
			up(code)
		elif not typing and "perf" in by_code.get(code, []):
			ui_action.emit("perf", true)
			if get_viewport() != null:
				get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()


# 코드를 누름 → 묶인 행동들 실행. 행동이 하나라도 있으면 true
func down(code: String) -> bool:
	if keys.has(code):
		return true
	keys[code] = true
	if not by_code.has(code):
		return false
	for id in by_code[code]:
		press(id)
	return true


func up(code: String) -> void:
	if not keys.erase(code):
		return
	for id in by_code.get(code, []):
		if id == "emote" and wheel != null:
			var n := wheel_pick()
			wheel = null
			wheel_changed.emit(-2)
			if n >= 0:
				Net.send({"type": "action", "name": "emote", "n": n})
		if id in ["help", "view", "practice"]:
			ui_action.emit(id, false)


func _act(a: Dictionary) -> void:
	a["type"] = "action"
	Net.send(a)
	action_sent.emit(a)


func press(id: String) -> void:
	if id in ["help", "view", "practice", "perf", "tutSkip"]:
		ui_action.emit(id, true)
		return
	if id == "viewL" or id == "viewR":
		if sky:
			ui_action.emit(id, true)
		return
	if id == "emote":
		if locked and wheel == null:
			wheel = Vector2.ZERO
			wheel_changed.emit(-1)
		return
	if not enabled:
		return
	match id:
		"jump":
			if locked:
				_act({"name": "jump"})
		"dash":
			_act({"name": "dash"})
		"attack":
			if locked:
				_act({"name": "push"})
		"item":
			if locked:
				_act({"name": "fire"})
		"skill":
			_act({"name": "skill"})
		"ult":
			_act({"name": "ult"})
		"rotL":
			_act({"name": "rotate", "dir": -1})
		"rotR":
			_act({"name": "rotate", "dir": 1})
		"drop":
			_act({"name": "drop"})
		"pieceUp":
			piece_move(0, 1)
		"pieceDown":
			piece_move(0, -1)
		"pieceLeft":
			piece_move(-1, 0)
		"pieceRight":
			piece_move(1, 0)


func wheel_pick() -> int:
	return Keys.wheel_slot(wheel, C.EMOTE_NAMES.size(), C.EMOTE_PICK_PX)


# 방향키 (블록 조종): 화면 기준 (sx 오른쪽, sy 위) → 격자 방향 (보던 방향 기준)
func piece_move(sx: int, sy: int) -> void:
	var c := cos(yaw)
	var s := sin(yaw)
	_act({"name": "pieceMove", "dx": roundi(sx * s + sy * c), "dy": roundi(-sx * c + sy * s)})


# 서버에 보낼 연속 입력
func sample() -> Dictionary:
	var fwd := (1 if held("fwd") else 0) - (1 if held("back") else 0)
	var strafe := (1 if held("right") else 0) - (1 if held("left") else 0)
	return {"type": "input", "fwd": fwd if locked else 0, "strafe": strafe if locked else 0, "jump": locked and held("jump"), "yaw": yaw, "pitch": pitch}
