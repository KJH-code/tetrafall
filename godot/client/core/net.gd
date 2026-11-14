# 서버 접속 (자동 로드 Net). client/main.js connect + client/net.js 재접속·핑 몫.
# 메시지는 JSON 글자 (JS·C# 서버 같은 프로토콜). 받은 메시지는 message 신호로 (Store 가 프로토콜을 처리), 보내기는 send(dict) 만.
# 끊기면 NET_RECONNECT_MS 마다 다시 붙어 보고 (NET_RECONNECT_TRIES 번), 붙으면 reconnected → Store 가 자리 토큰으로 rejoin
# PC 판은 주소에 ?pack=gzip 을 붙여 접속 → C# 서버가 큰 메시지 (스냅샷) 를 gzip 바이너리로 보냄 (고도 WebSocketPeer 는 permessage-deflate 를 못 씀:
# 8명 판 13.9KB × 30Hz 가 그대로 옴). 웹 판은 브라우저가 압축을 풀어 주니 그대로, JS 서버는 쿼리를 무시하고 글자로 보냄 — 글자 패킷은 예전처럼 읽음
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
var recv_bytes := 0 # 받은 패킷 바이트 합 (누른 그대로 = 실제로 받은 양)
var recv_states := 0 # 받은 스냅샷 수
var recv_packed := 0 # 그중 gzip 바이너리로 온 패킷 수
var recv_from := -1.0 # 첫 패킷 받은 시각 ms
var recv_log := false # --auto (자동 확인) 일 때만 끝날 때 받은 양 한 줄


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


# PC 판 접속 주소: 쿼리 pack=gzip 을 붙임 (경로가 없으면 / 부터)
static func packed_url(u: String) -> String:
	if u.contains("?"):
		return u + "&pack=gzip"
	var host_at := u.find("://")
	var has_path := u.find("/", host_at + 3 if host_at >= 0 else 0) >= 0
	return u + ("?pack=gzip" if has_path else "/?pack=gzip")


# 받은 패킷 → JSON 글자: 글자 패킷은 그대로, 바이너리는 gzip 풀기 (못 풀면 빈 글자 → 그 패킷은 버려짐)
static func unpack(bytes: PackedByteArray, is_text: bool) -> String:
	if is_text:
		return bytes.get_string_from_utf8()
	return bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()


# 실제로 붙을 주소 (url·상태 글은 원래 주소 그대로): 웹은 브라우저가 permessage-deflate 를 해 주니 그대로
func _connect_url() -> String:
	return url if OS.has_feature("web") else packed_url(url)


func start(server_url: String) -> void:
	url = server_url
	recv_log = OS.get_cmdline_user_args().has("--auto")
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 22 # 8명 스냅샷 + 격자
	var err := ws.connect_to_url(_connect_url())
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
		# 프레임 사이 쌓인 스냅샷 (웹 프레임이 느리면 여럿): 앞의 것은 가볍게 (store 가 보간·격자·이벤트만), 무거운 처리·state 신호는 마지막 것 하나만.
		# 다른 메시지는 순서 그대로 — 그 앞에 쌓인 스냅샷은 먼저 내보냄
		var pending: Array = []
		while ws.get_available_packet_count() > 0:
			var _pj := Prof.now()
			var pkt := ws.get_packet()
			var is_text := ws.was_string_packet()
			if recv_from < 0.0:
				recv_from = now
			recv_bytes += pkt.size()
			if not is_text:
				recv_packed += 1
			var m = JSON.parse_string(unpack(pkt, is_text))
			Prof.add("net ·JSON 파싱", _pj)
			if typeof(m) != TYPE_DICTIONARY:
				continue
			m["recvAt"] = now
			if m.get("type") == "pong":
				meter.on_pong(m, now)
				_emit(m)
			elif m.get("type") == "state":
				meter.on_state(now)
				recv_states += 1
				pending.append(m)
			else:
				_flush(pending)
				pending = []
				_emit(m)
		_flush(pending)
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
			ws.connect_to_url(_connect_url())


# 자동 확인 (--auto) 이 끝날 때 받은 양 한 줄: 스냅샷 묶음이 실제로 줄였는지 헤드리스 로그로 봄
func recv_line() -> String:
	var secs := maxf((now_ms() - recv_from) / 1000.0, 0.001) if recv_from >= 0.0 else 0.0
	var rate := recv_bytes / 1024.0 / secs if secs > 0.0 else 0.0
	return "[net] 받은 %.0fKB/s (스냅샷 %d개, gzip %s)" % [rate, recv_states, "켬" if recv_packed > 0 else "끔"]


func _exit_tree() -> void:
	if recv_log:
		print(recv_line())


func _emit(m: Dictionary) -> void:
	var _pe := Prof.now()
	message.emit(m)
	Prof.add("net ·메시지 처리 (store·신호 받는 쪽 전부)", _pe)


# 쌓인 스냅샷: 마지막 것 말고는 light (store 가 state 신호 없이 보간 버퍼·격자·이벤트만)
func _flush(list: Array) -> void:
	for i in list.size():
		if i < list.size() - 1:
			list[i]["_light"] = true
		_emit(list[i])
	if Prof.on and not list.is_empty():
		Prof.add_us("net ·받은 스냅샷 수", 1000 * list.size()) # ms 자리에 '개' (1000µs = 1)


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
