# 헤드리스 서버: WebSocket 으로 받고, 방마다 Game 하나를 30Hz 고정 틱으로 돌려 스냅샷을 보냄 (server/index.js·rooms.js 와 같은 철학).
# 메시지는 JSON 글자 (웹 클라·JS 도구도 붙기 쉽게):
#   클라 → 서버 {type:'hello', room, name} · {type:'input', fwd, strafe, jump, yaw} · {type:'action', name}
#   서버 → 클라 {type:'welcome', id, room} · {type:'grid', gv, W, D, H, data(base64)} · {type:'state', ...Game.snapshot(), events}
extends Node

const Game := preload("res://sim/game.gd")
const C := preload("res://sim/config.gd")

var args := {}
var tcp := TCPServer.new()
var conns: Array = [] # { ws, id, room }
var rooms := {} # 코드 -> { game, restart_at, last_gv }
var next_id := 1
var rounds_done := 0
var max_rounds := 0
var tick_us: Array = [] # 틱마다 (모든 방 tick + 스냅샷 보내기) 걸린 시간
var quit_at := -1.0


func _ready() -> void:
	var port := int(args.get("port", C.PORT))
	max_rounds = int(args.get("rounds", 0))
	Engine.physics_ticks_per_second = C.TICK_RATE
	Engine.max_physics_steps_per_frame = 4
	var err := tcp.listen(port)
	if err != OK:
		push_error("포트 %d 열기 실패 (%d)" % [port, err])
		get_tree().quit(1)
		return
	print("[서버] 고도 %s, ws://0.0.0.0:%d, %dHz" % [Engine.get_version_info().string, port, C.TICK_RATE])


func _physics_process(_delta: float) -> void:
	while tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.outbound_buffer_size = 1 << 20
		ws.accept_stream(tcp.take_connection())
		conns.append({"ws": ws, "id": -1, "room": ""})
	for c in conns.duplicate():
		var ws: WebSocketPeer = c.ws
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			drop(c)
			continue
		if st != WebSocketPeer.STATE_OPEN:
			continue
		while ws.get_available_packet_count() > 0:
			var msg = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if typeof(msg) == TYPE_DICTIONARY:
				on_message(c, msg)
	var t0 := Time.get_ticks_usec()
	for code in rooms:
		step_room(code, rooms[code])
	tick_us.append(Time.get_ticks_usec() - t0)
	if quit_at > 0.0 and Time.get_ticks_msec() >= quit_at:
		print_stats()
		get_tree().quit(0)


func on_message(c: Dictionary, m: Dictionary) -> void:
	match str(m.get("type", "")):
		"hello":
			if c.id >= 0:
				return
			var code := str(m.get("room", "A")).substr(0, 8)
			if not rooms.has(code):
				rooms[code] = {"game": Game.new(func(s): print("[%s] %s" % [code, s])), "restart_at": -1.0, "last_gv": -1}
				rooms[code].game.rng.randomize()
				print("[서버] 방 %s 만듦" % code)
			var g: Game = rooms[code].game
			var p = g.add_player(next_id, str(m.get("name", "")).substr(0, 16))
			if p == null:
				send(c.ws, {"type": "full"})
				return
			c.id = next_id
			c.room = code
			next_id += 1
			send(c.ws, {"type": "welcome", "id": c.id, "room": code})
			rooms[code].last_gv = -1 # 새로 온 사람에게도 격자 보내게
			print("[서버] %s 들어옴 (방 %s, %d명)" % [p.name, code, g.players.size()])
		"input":
			if c.id >= 0:
				rooms[c.room].game.handle_input(c.id, float(m.get("fwd", 0)), float(m.get("strafe", 0)), bool(m.get("jump", false)), float(m.get("yaw", 0)))
		"action":
			if c.id >= 0:
				rooms[c.room].game.handle_action(c.id, str(m.get("name", "")))


func drop(c: Dictionary) -> void:
	conns.erase(c)
	if c.id < 0 or not rooms.has(c.room):
		return
	var r: Dictionary = rooms[c.room]
	r.game.remove_player(c.id)
	print("[서버] %d 나감 (방 %s)" % [c.id, c.room])
	if r.game.players.is_empty():
		rooms.erase(c.room)


func step_room(code: String, r: Dictionary) -> void:
	var g: Game = r.game
	var was := g.phase
	g.tick(1000.0 / C.TICK_RATE)
	if was == "playing" and g.phase == "over":
		rounds_done += 1
		r.restart_at = g.time + C.ROUND_RESTART_MS
		if max_rounds > 0 and rounds_done >= max_rounds:
			quit_at = Time.get_ticks_msec() + 500.0 # 마지막 스냅샷이 나가게 조금 뒤
	# 2명 이상이면 판 시작, 판 끝나면 ROUND_RESTART_MS 뒤 다음 판
	if g.phase == "lobby" and g.can_start():
		g.start_round()
	elif g.phase == "over" and g.time >= r.restart_at and g.can_start() and quit_at < 0.0:
		g.start_round()
	var out := g.snapshot()
	out["events"] = g.drain_events()
	var text := JSON.stringify(out)
	var grid_text := ""
	if g.grid_version != r.last_gv:
		r.last_gv = g.grid_version
		grid_text = JSON.stringify({"type": "grid", "gv": g.grid_version, "W": g.W, "D": g.D, "H": g.H, "data": Marshalls.raw_to_base64(g.grid)})
	for c in conns:
		if c.room != code:
			continue
		if grid_text != "":
			c.ws.send_text(grid_text)
		c.ws.send_text(text)


func send(ws: WebSocketPeer, m: Dictionary) -> void:
	ws.send_text(JSON.stringify(m))


func print_stats() -> void:
	var s := tick_us.duplicate()
	s.sort()
	var sum := 0
	for v in s:
		sum += v
	if s.is_empty():
		return
	print("[서버] 틱 %d번: 평균 %.3fms, 중앙 %.3fms, 99%% %.3fms, 최대 %.3fms (방 tick + 스냅샷 보내기)" % [s.size(), sum / 1000.0 / s.size(), s[s.size() / 2] / 1000.0, s[int(s.size() * 0.99)] / 1000.0, s[-1] / 1000.0])
	print("[서버] 끝: 판 %d번" % rounds_done)
