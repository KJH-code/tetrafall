# 받은 상태 (자동 로드 Store): 프로토콜 처리 (client/main.js ws.onmessage 몫) + 최신 스냅샷 + 화면 위치 보간.
# **읽기 전용 창구**: 다른 묶음(world·chars·ui …)은 Store.state·Store.me()·Store.view_pos() 를 읽고 신호를 받기만. 쓰기는 G0 (core/) 만
# 서버로 보내기는 Store 의 함수 (create_room·join·send_room 등) 또는 PlayerInput (조작). 프로토콜 글자는 JS 화면과 같음
extends Node

const Prof := preload("res://core/prof.gd")

const C := preload("res://core/config.gd")
const Interp := preload("res://core/interp.gd")
const Seat := preload("res://core/seat.gd")

signal rooms_changed(list: Dictionary) # 공개 방 목록 {rooms, count, max}
signal joined(room: Dictionary, rejoined: bool) # 방에 들어감 (welcome)
signal join_error(reason: String)
signal left_room(reason: String) # 방 밖으로 (left)
signal state_changed(state: Dictionary, prev: Dictionary) # 스냅샷마다 (grid 는 늘 채워 둠)
signal game_event(e: Dictionary) # 스냅샷에 실려 온 이벤트 하나씩 (state_changed 다음)
signal grid_changed(version: int) # 격자가 바뀜 (gridVersion)

var my_id = null # 내 플레이어 id (int) — 방 밖이면 null
var room := {} # {code, name, public, practice, tutorial?, link?}
var state := {} # 최신 스냅샷 (JSON 그대로, 숫자는 float)
var prev_state := {}
var rooms_list := {}
var grid := PackedByteArray() # 격자 칸 (z * d + y) * w + x
var grid_version := -1
var pending_code := "" # 들어가려는 방 (명령줄 --room, 재접속)
var clock := Interp.SnapClock.new()
var tracks := {} # 플레이어 id -> [[t, x, y, z], ...] (interp.gd)
var view_time = null # 화면 서버 시각 (보간 기준, ms)
var _players_by_id := {}


func _ready() -> void:
	Net.message.connect(_on_message)
	Net.opened.connect(_on_opened)


# ---------- 보내기 (방 밖·방 안 메시지, rooms.js 와 같은 모양) ----------
func create_room(name: String, nick: String) -> void:
	Net.send({"type": "create", "name": name, "nick": nick})


func join(code: String) -> void:
	pending_code = code.strip_edges().to_upper()
	var tok := Seat.token(pending_code)
	Net.send({"type": "rejoin", "code": pending_code, "token": tok} if tok != "" else {"type": "join", "code": pending_code})


func leave() -> void:
	if not room.is_empty():
		Seat.drop(str(room.code))
	Net.send({"type": "leave"})


# 방 안 메시지 (addBot·start·setChar·setName …: server/rooms.js roomMessage 의 type 그대로)
func send_room(msg: Dictionary) -> void:
	Net.send(msg)


# ---------- 읽기 ----------
func in_room() -> bool:
	return my_id != null


func me() -> Dictionary:
	return player(my_id) if my_id != null else {}


func player(id) -> Dictionary:
	return _players_by_id.get(int(id), {}) if id != null else {}


func phase() -> String:
	return str(state.get("phase", ""))


# 화면에 그릴 위치 (게임 좌표 x, y 바닥 · z 위): 서버 시각보다 조금 늦게 두 스냅샷 사이에서 (client/interp.js, render.js 와 같은 지연)
func view_pos(id) -> Vector3:
	var p := player(id)
	if p.is_empty():
		return Vector3.ZERO
	var tr: Array = tracks.get(int(id), [])
	if view_time == null or tr.is_empty():
		return Vector3(p.x, p.y, p.z)
	var delay: float = C.INTERP_DELAY_SELF_MS if int(id) == my_id else C.INTERP_DELAY_MS
	var v = Interp.sample_track(tr, view_time - delay, C.INTERP_EXTRAP_MS)
	return v if v != null else Vector3(p.x, p.y, p.z)


func _process(delta: float) -> void:
	var _pt := Prof.now() # 성능 구간 (--perf-log 만, core/prof.gd)
	_prof_process(delta)
	Prof.add("store 시계", _pt)


func _prof_process(delta: float) -> void:
	view_time = clock.advance(Net.now_ms(), delta * 1000.0)


# ---------- 받기 ----------
func _on_opened(reconnect: bool) -> void:
	# 링크·명령줄로 정한 방, 또는 끊기기 전 방 → 자리 토큰이 있으면 같은 자리로
	if reconnect and not room.is_empty():
		pending_code = str(room.code)
	if pending_code != "":
		join(pending_code)


func _on_message(m: Dictionary) -> void:
	match str(m.get("type", "")):
		"rooms":
			rooms_list = m
			rooms_changed.emit(m)
		"rejoinError":
			Seat.drop(str(m.code)) # 자리 유지 시간이 지났거나 방이 없어짐 → 보통 들어가기로
			Net.send({"type": "join", "code": m.code})
		"joinError":
			pending_code = ""
			join_error.emit(str(m.get("reason", "")))
		"welcome":
			my_id = int(m.id)
			room = m.room
			pending_code = ""
			Seat.save(str(room.code), str(m.get("token", "")))
			joined.emit(room, bool(m.get("rejoined", false)))
		"left":
			if not room.is_empty() and not m.get("replaced", false):
				Seat.drop(str(room.code))
			my_id = null
			room = {}
			state = {}
			prev_state = {}
			tracks.clear()
			_players_by_id.clear()
			clock.reset()
			left_room.emit(str(m.get("reason", "")))
		"state":
			if my_id == null:
				return # 방을 나간 직후 남은 스냅샷
			_on_state(m)


func _on_state(m: Dictionary) -> void:
	prev_state = state
	if m.has("grid"):
		var g: Array = m.grid
		grid = PackedByteArray(g)
		grid_version = int(m.get("gridVersion", 0))
		grid_changed.emit(grid_version)
	state = m
	if m.has("room"):
		room = m.room
	_players_by_id.clear()
	var t: float = m.time
	clock.on_snapshot(t, m.recvAt)
	var seen := {}
	for p in m.players:
		var id := int(p.id)
		_players_by_id[id] = p
		seen[id] = true
		if not tracks.has(id):
			tracks[id] = []
		Interp.push_track(tracks[id], t, p.x, p.y, p.z)
	for id in tracks.keys():
		if not seen.has(id):
			tracks.erase(id)
	state_changed.emit(state, prev_state)
	for e in m.get("events", []):
		game_event.emit(e)
