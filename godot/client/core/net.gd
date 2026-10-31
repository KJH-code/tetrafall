# 서버 접속 (자동 로드 Net). client/main.js connect + client/net.js 재접속·핑 몫.
# 메시지는 JSON 글자 (JS·C# 서버 같은 프로토콜). 받은 메시지는 message 신호로 (Store 가 프로토콜을 처리), 보내기는 send(dict) 만.
# 끊기면 NET_RECONNECT_MS 마다 다시 붙어 보고 (NET_RECONNECT_TRIES 번), 붙으면 reconnected → Store 가 자리 토큰으로 rejoin
extends Node

const Prof := preload("res://core/prof.gd")

const C := preload("res://core/config.gd")
const NetMeter := preload("res://core/net_meter.gd")

signal opened(reconnect: bool) # 붙음 (reconnect: 끊겼다 다시 붙음)
signal closed # 끊김 (다시 붙어 보는 중이면 status 로)
signal message(msg: Dictionary) # 받은 메시지 하나 (msg.recvAt = 받은 로컬 시각 ms)
signal status_changed(text: String) # 접속 상태 글 (화면 아래 줄 등)

var url := ""
var ws := WebSocketPeer.new()
var meter := NetMeter.new()
var was_open := false
var ever_open := false
var reconnecting := false
var tries := 0
var retry_at := 0.0
var ping_at := 0.0
var status := ""


static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


# 서버 주소: 명령줄 --server ws://… > 웹이면 페이지 주소 (?server= 또는 같은 호스트) > ws://127.0.0.1:PORT
static func default_url(args: Dictionary) -> String:
	if args.has("server"):
		return str(args.server)
	if OS.has_feature("web"):
		var u = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host)", true)
		return str(u)
	return "ws://127.0.0.1:%d" % int(C.PORT)


func start(server_url: String) -> void:
	url = server_url
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 22 # 8명 스냅샷 + 격자
	var err := ws.connect_to_url(url)
	_set_status("연결 중… %s" % url if err == OK else "연결 실패 %s (%d)" % [url, err])


func is_open() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(obj: Dictionary) -> void:
	if is_open():
		ws.send_text(JSON.stringify(obj))


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)


func _process(_delta: float) -> void:
	var _pt := Prof.now() # 성능 구간 (--perf-log 만, core/prof.gd)
	_prof_process(_delta)
	Prof.add("net (스냅샷 받기·JSON·state 신호)", _pt)


func _prof_process(_delta: float) -> void:
	var now := now_ms()
	meter.on_frame(now)
	if url == "":
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not was_open:
			was_open = true
			var again := ever_open
			ever_open = true
			reconnecting = false
			tries = 0
			ping_at = now
			_set_status("연결됨")
			opened.emit(again)
		while ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if typeof(m) != TYPE_DICTIONARY:
				continue
			m["recvAt"] = now
			if m.get("type") == "pong":
				meter.on_pong(m, now)
			elif m.get("type") == "state":
				meter.on_state(now)
			message.emit(m)
		if now >= ping_at:
			send(meter.ping(now))
			ping_at = now + C.NET_PING_MS
	elif st == WebSocketPeer.STATE_CLOSED:
		if was_open or (not ever_open and tries == 0 and not reconnecting):
			was_open = false
			reconnecting = true
			retry_at = now + C.NET_RECONNECT_MS
			closed.emit()
			_set_status("서버 연결 끊김 — 다시 연결 중")
		if reconnecting and now >= retry_at:
			if tries >= C.NET_RECONNECT_TRIES:
				reconnecting = false
				_set_status("다시 연결 못 함. 호스트가 터널을 다시 켰으면 새 링크로 들어오세요")
				return
			tries += 1
			retry_at = now + C.NET_RECONNECT_MS
			_set_status("서버 연결 끊김 — 다시 연결 중 (%d/%d)" % [tries, int(C.NET_RECONNECT_TRIES)])
			ws = WebSocketPeer.new()
			ws.inbound_buffer_size = 1 << 22
			ws.connect_to_url(url)


# 접속 상태 표시 (client/net.js draw 글자 그대로): "핑 12ms" (+ 서버 느림), 알림 글
func ping_text() -> String:
	var v := meter.view(now_ms())
	return "핑 %s%s" % [v.ping, (" · 서버 %dms" % v.server) if v.server >= C.NET_SERVER_SLOW_MS else ""]


func warn_text() -> String:
	var v := meter.view(now_ms())
	return v.warn if v.warn != null else ""


# 시험용: 연결을 일부러 끊음 (재접속 확인)
func drop_for_test() -> void:
	ws.close()
