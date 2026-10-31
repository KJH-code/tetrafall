# 키보드·마우스 입력 (자동 로드 PlayerInput, client/input.js 그대로): 연속 입력은 INPUT_SEND_RATE 로, 단발 행동은 바로 서버에.
# 키 이름은 브라우저 e.code 글자 (keys.gd) → JS 판과 같은 키 설정. 판 중·살아 있을 때만 행동 (enabled, Store 스냅샷으로 정함)
# 화면 묶음이 쓰는 것: yaw·pitch (카메라), ui_action 신호 (도움말·시점·연습·성능·튜토리얼 넘기기·하늘 시점 돌리기), wheel_changed (이모트 바퀴)
extends Node

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
var override = null # 시험·자동 조종: 이 dict 를 input 대신 보냄 (client debug.inputOverride)
var _send_acc := 0.0


func _ready() -> void:
	set_binds(Keys.load_binds())
	Store.state_changed.connect(_on_state)
	Store.joined.connect(func(_room, rejoined): _on_joined(rejoined))


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
		keys.clear()


# 들어오면 시작 자리 방향을 봄, 재접속이면 다음 스냅샷의 내 방향
var _aim_from_state := false


func _on_joined(rejoined: bool) -> void:
	_aim_from_state = rejoined
	if not rejoined:
		var p := Store.me()
		if not p.is_empty():
			set_yaw_pitch(p.yaw, 0)


func _on_state(st: Dictionary, _prev: Dictionary) -> void:
	var p := Store.me()
	if _aim_from_state and not p.is_empty():
		set_yaw_pitch(p.yaw, p.get("pitch", 0.0))
		_aim_from_state = false
	var ph := str(st.get("phase", ""))
	enabled = (ph == "playing" or ph == "countdown") and not p.is_empty() and p.alive


func _process(delta: float) -> void:
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
		return
	if e is InputEventMouseMotion:
		if wheel != null:
			wheel += e.relative
			wheel_changed.emit(wheel_pick())
			return
		if not locked or sky:
			return
		yaw -= e.relative.x * C.MOUSE_SENSITIVITY * sensitivity
		pitch -= e.relative.y * C.MOUSE_SENSITIVITY * sensitivity
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		keys.clear()
		if wheel != null:
			wheel = null
			wheel_changed.emit(-2)
		ui_action.emit("help", false)
		ui_action.emit("practice", false)


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
