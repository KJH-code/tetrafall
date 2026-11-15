# 서버 접속 (자동 로드 Net). client/main.js connect + client/net.js 재접속·핑 몫.
# 메시지는 JSON 글자 (JS·C# 서버 같은 프로토콜). 받은 메시지는 message 신호로 (Store 가 프로토콜을 처리), 보내기는 send(dict) 만.
# 끊기면 NET_RECONNECT_MS 마다 다시 붙어 보고 (NET_RECONNECT_TRIES 번), 붙으면 reconnected → Store 가 자리 토큰으로 rejoin
# 열려 있는데 SILENCE_MS 넘게 아무것도 안 오면 (멈춘 서버·죽은 길) 그 소켓을 버리고 같은 길로 다시 붙음. 붙어 보기가 CONNECT_MS 넘게 매달려도 버리고 다음 시도로.
# 다 써도 못 붙으면 gave_up (Store 가 방을 비우고 메뉴로), 그 뒤엔 retry() 로 다시
# PC 판은 주소에 ?pack=gzip 을 붙여 접속 → C# 서버가 큰 메시지 (스냅샷) 를 gzip 바이너리로 보냄 (고도 WebSocketPeer 는 permessage-deflate 를 못 씀:
# 8명 판 13.9KB × 30Hz 가 그대로 옴). 웹 판은 브라우저가 압축을 풀어 주니 그대로, JS 서버는 쿼리를 무시하고 글자로 보냄 — 글자 패킷은 예전처럼 읽음
extends Node

const Prof := preload("res://core/prof.gd")

const C := preload("res://core/config.gd")
const NetMeter := preload("res://core/net_meter.gd")

# 받는 패킷 크기 상한 (8명 스냅샷 + 격자): WebSocket 받는 버퍼 (누른 크기) 이자 gzip 을 푼 크기 상한 — 작은 패킷 하나가 수백 MB 로 풀리는 것 막기.
# config NET_MAX_PAYLOAD_BYTES (서버가 받는 메시지 상한 64KB) 와는 다른 값: 그걸 쓰면 큰 스냅샷이 잘림
const INBOUND_MAX_BYTES := 1 << 22
# 서버 침묵 상한: 서버는 내 핑마다 (NET_PING_MS = 1초) pong 을 보내므로 6초 침묵은 비정상 (서버가 멈췄거나 길이 죽음 — TCP 는 한참 뒤에야 끊긴 줄 앎).
# 메뉴·대기실·판 어디서든 이 pong 하나가 받침 — 방 목록은 바뀔 때만 와서 (C# Rooms.BroadcastList·JS rooms.js) 근거가 아님.
# NET_PING_MS 를 늘리거나 핑을 빼면 이 값도 같이 볼 것. 프레임이 멈췄던 시간 (meter.slack) 은 뺌
const SILENCE_MS := 6000
# 붙어 보기 상한: 한 번 붙어 보기 (TCP + 업그레이드 응답) 가 이보다 오래 CONNECTING 이면 그 소켓을 버리고 다음 시도로 (처음 접속도 같음).
# 멈춘 서버 (SIGSTOP·교착) 는 커널이 TCP 를 받아 줘도 업그레이드 응답이 안 와 CONNECTING 에 끝없이 머묾. 프레임이 멈췄던 시간 (meter.slack) 은 뺌.
# 시도마다 max(NET_RECONNECT_MS, CONNECT_MS) 라 다 막히면 포기 (gave_up) 까지 NET_RECONNECT_TRIES × 6초 = 약 3분 (거절되는 서버는 × 2초 = 1분)
const CONNECT_MS := 6000
const GZIP_ISIZE_BYTES := 4 # gzip 꼬리 ISIZE: 푼 크기 (리틀 엔디언 32비트, RFC 1952)
const LOST_CLOSED := "서버 연결 끊김" # 끊긴 까닭 글 (상태 글 앞머리)
const LOST_SILENT := "서버 응답 없음"

signal opened(reconnect: bool) # 붙음 (reconnect: 끊겼다 다시 붙음)
signal closed # 끊김 (다시 붙어 보는 중이면 status 로)
signal message(msg: Dictionary) # 받은 메시지 하나 (msg.recvAt = 받은 로컬 시각 ms)
signal status_changed(text: String) # 접속 상태 글 (화면 아래 줄 등)
signal gave_up # 다시 붙기를 NET_RECONNECT_TRIES 번 다 씀 (Store: 방 안이면 방을 비우고 메뉴로). retry() 로 다시 시작

var url := ""
var ws := WebSocketPeer.new()
var meter := NetMeter.new()
var was_open := false
var ever_open := false
var reconnecting := false
var tries := 0
var retry_at := 0.0
var ping_at := 0.0
var last_recv_at = null # 이 연결에서 마지막으로 뭔가 받은 시각 ms (붙은 순간부터 잼, 안 붙어 있으면 null)
var connect_at = null # 지금 붙어 보기를 시작한 시각 ms (CONNECTING 동안만 뜻 있음, 붙거나 버리면 null)
var lost := LOST_CLOSED # 지금 다시 붙는 까닭 (상태 글)
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


# gzip 꼬리에 적힌 푼 크기 (꼬리가 없을 만큼 짧으면 -1)
static func gzip_size(bytes: PackedByteArray) -> int:
	return bytes.decode_u32(bytes.size() - GZIP_ISIZE_BYTES) if bytes.size() >= GZIP_ISIZE_BYTES else -1


# 받은 패킷 → JSON 글자: 글자 패킷은 그대로, 바이너리는 gzip 풀기 (못 풀면 빈 글자 → 그 패킷은 버려짐).
# 푼 크기는 INBOUND_MAX_BYTES 까지: 꼬리에 적힌 크기가 상한을 넘으면 풀어 보지 않고 버리고 (엔진 오류 줄 없음),
# 풀 때도 적힌 크기까지만 푼다 — 꼬리가 거짓말이어도 (실제로는 더 큼) 고도가 거기서 멈추고 빈 배열을 돌려줌 (오류 한 줄)
static func unpack(bytes: PackedByteArray, is_text: bool) -> String:
	if is_text:
		return bytes.get_string_from_utf8()
	var n := gzip_size(bytes)
	if n <= 0 or n > INBOUND_MAX_BYTES:
		return ""
	return bytes.decompress_dynamic(n, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()


# 서버 침묵: 마지막으로 받은 뒤 SILENCE_MS 넘게 조용함 (slack = 프레임이 멈췄던 시간은 뺌 — 멈췄다 풀린 직후 잘못 끊지 않게). 받은 적 없으면 false
static func silent(now: float, last_recv_at, slack: float) -> bool:
	return last_recv_at != null and now - float(last_recv_at) - slack > SILENCE_MS


# 붙어 보기가 매달림: 시작한 뒤 CONNECT_MS 넘게 CONNECTING (slack = 프레임이 멈췄던 시간은 뺌 — 엔진이 poll 을 못 한 동안). 시작 시각이 없으면 false
static func connect_stuck(now: float, connect_at, slack: float) -> bool:
	return connect_at != null and now - float(connect_at) - slack > CONNECT_MS


# 실제로 붙을 주소 (url·상태 글은 원래 주소 그대로): 웹은 브라우저가 permessage-deflate 를 해 주니 그대로
func _connect_url() -> String:
	return url if OS.has_feature("web") else packed_url(url)


func start(server_url: String) -> void:
	url = server_url
	recv_log = OS.get_cmdline_user_args().has("--auto")
	var err := _dial(now_ms())
	_set_status("연결 중… %s" % url if err == OK else "연결 실패 %s (%d)" % [url, err])


# 새 소켓으로 붙어 보기 시작 (처음 접속·다시 붙기 같은 길): 시작 시각을 기억해 CONNECT_MS 를 잼
func _dial(now: float) -> Error:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = INBOUND_MAX_BYTES
	connect_at = now
	return ws.connect_to_url(_connect_url())


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
			connect_at = null
			ping_at = now
			last_recv_at = now # 붙은 순간부터 잼 (붙었는데 아무 말도 없는 서버도 잡음 — 첫 핑의 pong 이 바로 옴)
			_set_status("연결됨")
			opened.emit(again)
		# 프레임 사이 쌓인 스냅샷 (웹 프레임이 느리면 여럿): 앞의 것은 가볍게 (store 가 보간·격자·이벤트만), 무거운 처리·state 신호는 마지막 것 하나만.
		# 다른 메시지는 순서 그대로 — 그 앞에 쌓인 스냅샷은 먼저 내보냄
		var pending: Array = []
		while ws.get_available_packet_count() > 0:
			var _pj := Prof.now()
			var pkt := ws.get_packet()
			var is_text := ws.was_string_packet()
			last_recv_at = now
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
		# 쌓인 패킷을 다 읽은 뒤에 봄 (프레임이 멈췄다 풀리면 밀린 패킷이 먼저 읽혀 침묵이 아님)
		if silent(now, last_recv_at, meter.slack(now)):
			_drop_silent(now)
	elif st == WebSocketPeer.STATE_CONNECTING:
		if connect_stuck(now, connect_at, meter.slack(now)):
			_drop_stuck(now)
	elif st == WebSocketPeer.STATE_CLOSED:
		if was_open or (not ever_open and tries == 0 and not reconnecting):
			_lost(now, LOST_CLOSED)
		if reconnecting and now >= retry_at:
			if tries >= C.NET_RECONNECT_TRIES:
				reconnecting = false
				_set_status("다시 연결 못 함. 호스트가 터널을 다시 켰으면 새 링크로 들어오세요")
				gave_up.emit()
				return
			tries += 1
			retry_at = now + C.NET_RECONNECT_MS
			_set_status("%s — 다시 연결 중 (%d/%d)" % [lost, tries, int(C.NET_RECONNECT_TRIES)])
			_dial(now)


# 끊김 → 다시 붙기 시작 (why: 끊긴 까닭 글 LOST_*)
func _lost(now: float, why: String) -> void:
	was_open = false
	reconnecting = true
	retry_at = now + C.NET_RECONNECT_MS
	last_recv_at = null
	lost = why
	closed.emit()
	_set_status("%s — 다시 연결 중" % why)


# 지금 소켓을 인사 없이 바로 버림 (음수 코드 = 닫기 프레임 안 보냄 — 받을 서버가 멈춰 있음). 그래도 CLOSED 가 아니면 새 소켓으로 바꿈
func _discard() -> void:
	ws.close(-1)
	if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		ws = WebSocketPeer.new() # 새 소켓은 STATE_CLOSED → 다음 프레임부터 CLOSED 갈래
	connect_at = null


# 열려 있는데 조용한 소켓: 버리고 끊긴 것과 같은 길로 다시 붙음
func _drop_silent(now: float) -> void:
	_discard()
	_lost(now, LOST_SILENT)


# 붙어 보기가 CONNECT_MS 넘게 매달린 소켓: 버리고 다음 시도로. 다시 붙는 중이면 다음 프레임의 CLOSED 갈래가 횟수를 올려 다음 시도
# (다 쓰면 gave_up), 처음 접속이면 끊긴 것과 같은 길로 다시 붙기 시작. 상태 글은 '서버 응답 없음'
func _drop_stuck(now: float) -> void:
	_discard()
	if reconnecting:
		lost = LOST_SILENT
	else:
		_lost(now, LOST_SILENT)


# 다시 붙어 보기를 처음부터 (메뉴에서 눌렀는데 연결이 없을 때): 횟수를 되돌리고, 포기한 뒤거나 붙어 보기가 매달려 있으면
# (CONNECTING — 그 소켓은 버림) 바로 다시 시작
func retry() -> void:
	if url == "" or is_open():
		return
	tries = 0
	var hung := ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING
	if hung:
		_discard()
	if hung or (not reconnecting and ws.get_ready_state() == WebSocketPeer.STATE_CLOSED):
		reconnecting = true
		retry_at = now_ms()
		_set_status("%s — 다시 연결 중" % lost)


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
