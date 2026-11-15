# G0 계산이 JS 화면과 같은 값인지 (tools/fixtures.mjs 가 뽑은 정답): 보간·핑 계산·키 설정
extends RefCounted

const C := preload("res://core/config.gd")
const Interp := preload("res://core/interp.gd")
const NetMeter := preload("res://core/net_meter.gd")
const NetScript := preload("res://core/net.gd")
const Keys := preload("res://core/keys.gd")
const StoreScript := preload("res://core/store.gd")
const Menu := preload("res://ui/menu.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func load_json(name: String):
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name))


func test_config_generated() -> void:
	check(C.TICK_RATE == 30.0 and typeof(C.TICK_RATE) == TYPE_FLOAT, "숫자는 float (1000 / C.TICK_RATE 가 정수 나눗셈 아님)")
	check(C.FIELD_SIZES["8"] == 19.0, "표도 그대로 (FIELD_SIZES)")
	check(C.MAPS.flat.name == "바람 들판", "맵 이름")
	check(C.CHARACTERS.size() == 8, "캐릭터 8명")
	check(C.BASIC_ATTACKS.ninja.chain.size() == 4, "중첩 표 (BASIC_ATTACKS)")


func test_interp_matches_js() -> void:
	var fx = load_json("interp.json")
	check(fx != null, "interp.json")
	var clock := Interp.SnapClock.new()
	var track := []
	var fi := 0
	var last_frame = null
	var bad := 0
	for e in fx.events:
		if e.type == "snap":
			clock.on_snapshot(e.server, e.at)
			Interp.push_track(track, e.server, e.x, e.y, e.z)
			continue
		var dt: float = 16.6 if last_frame == null else e.at - last_frame
		last_frame = e.at
		var t = clock.advance(e.at, dt)
		var want: Array = fx.frames[fi]
		fi += 1
		if (t == null) != (want[2] == null) or (t != null and absf(t - want[2]) > 1e-9):
			if bad < 2:
				errors.append("프레임 %d 시계 %s / JS %s" % [fi, str(t), str(want[2])])
			bad += 1
			continue
		check(track.size() == int(want[4]), "기록 수 %d / JS %d (프레임 %d)" % [track.size(), int(want[4]), fi])
		if t == null:
			continue
		var s = Interp.sample_track(track, t - C.INTERP_DELAY_MS, C.INTERP_EXTRAP_MS)
		var w: Array = want[3]
		if s == null or absf(s.x - w[0]) > 1e-5 or absf(s.y - w[1]) > 1e-5 or absf(s.z - w[2]) > 1e-5: # Vector3 는 32비트
			if bad < 2:
				errors.append("프레임 %d 위치 %s / JS %s" % [fi, str(s), str(w)])
			bad += 1
	check(fi == fx.frames.size(), "프레임 수 %d / %d" % [fi, fx.frames.size()])
	check(bad == 0, "보간이 JS 와 다른 프레임 %d개" % bad)


func test_net_meter_matches_js() -> void:
	var m := NetMeter.new()
	var bad := 0
	var n := 0
	for row in load_json("net.json"):
		match row[0]:
			"state":
				m.on_state(row[1])
			"pong":
				m.on_pong(row[2], row[1])
			"frame":
				m.on_frame(row[1])
				var v := m.view(row[1])
				var w: Dictionary = row[2]
				n += 1
				if v.ping != w.ping or v.server != int(w.server) or v.level != w.level or (v.warn if v.warn != null else "") != (w.warn if w.warn != null else ""):
					if bad < 3:
						errors.append("핑 표시 %s / JS %s" % [str(v), str(w)])
					bad += 1
	check(n > 300, "프레임 %d" % n)
	check(bad == 0, "핑 표시가 JS 와 다른 프레임 %d개" % bad)


# PC 판 스냅샷 묶음: 바이너리 패킷은 gzip 을 풀고, 글자 패킷 (JS 서버·작은 메시지) 은 그대로
func test_net_unpack() -> void:
	var text := "{\"type\":\"state\",\"name\":\"재혁\",\"grid\":\"%s\"}" % "0123456789".repeat(400)
	var raw := text.to_utf8_buffer()
	var gz := raw.compress(FileAccess.COMPRESSION_GZIP)
	check(gz.size() < raw.size(), "gzip %d / 원문 %d" % [gz.size(), raw.size()])
	check(NetScript.unpack(gz, false) == text, "gzip 바이너리를 풀면 원문")
	check(NetScript.unpack(raw, true) == text, "글자 패킷은 그대로")
	var m = JSON.parse_string(NetScript.unpack(gz, false))
	check(typeof(m) == TYPE_DICTIONARY and m.get("type") == "state" and m.get("name") == "재혁", "푼 글자가 JSON 으로 읽힘")
	check(NetScript.gzip_size(gz) == raw.size(), "gzip 꼬리의 푼 크기 %d / %d" % [NetScript.gzip_size(gz), raw.size()])


# 푼 크기 상한 (INBOUND_MAX_BYTES): 작은 패킷이 아주 크게 풀리는 것 (gzip 폭탄) 은 풀어 보지 않고 버림 — 엔진 오류 줄도 없음 (러너가 오류로 셈)
func test_net_unpack_limit() -> void:
	var lim: int = NetScript.INBOUND_MAX_BYTES
	check(lim == 1 << 22, "상한 %d" % lim)
	for row in [[lim, true], [lim + 1, false], [lim * 16, false]]:
		var raw := PackedByteArray()
		raw.resize(row[0])
		raw.fill(97)
		var gz := raw.compress(FileAccess.COMPRESSION_GZIP)
		check(gz.size() < lim / 16, "푼 크기 %d 가 %d 로 눌림" % [raw.size(), gz.size()])
		var got := NetScript.unpack(gz, false)
		check(got.length() == (raw.size() if row[1] else 0), "푼 크기 %d → 글자 %d (%s)" % [raw.size(), got.length(), "풀림" if row[1] else "버림"])
	# 꼬리가 없을 만큼 짧은 바이너리도 조용히 버림
	check(NetScript.unpack(PackedByteArray([31, 139]), false) == "", "2바이트 패킷")
	check(NetScript.unpack(PackedByteArray(), false) == "", "빈 패킷")


func test_net_packed_url() -> void:
	for row in [
		["ws://127.0.0.1:3000", "ws://127.0.0.1:3000/?pack=gzip"],
		["wss://x.trycloudflare.com", "wss://x.trycloudflare.com/?pack=gzip"],
		["ws://h:1/a?b=1", "ws://h:1/a?b=1&pack=gzip"],
		["ws://h:1/", "ws://h:1/?pack=gzip"],
	]:
		check(NetScript.packed_url(row[0]) == row[1], "주소 %s → %s / %s" % [row[0], NetScript.packed_url(row[0]), row[1]])


# 서버 침묵 감지 (net.gd silent): 마지막으로 받은 뒤 SILENCE_MS (6초) 넘게 조용하면 true. 프레임이 멈췄던 시간 (slack) 은 뺌.
# 실제로는 열린 동안에만 부르고 붙는 순간 last_recv_at = 붙은 시각이라 null 이 없음 (null 은 순수 함수 경계값 — 붙은 순간부터 세는지는 test_net_silent_from_open)
func test_net_silence_watchdog() -> void:
	var lim: float = NetScript.SILENCE_MS
	check(lim == 6000.0, "침묵 상한 %s" % lim)
	# 침묵 감시를 받치는 것은 내 핑 (NET_PING_MS) 의 pong 하나 (방 목록은 바뀔 때만 옴): 핑 간격이 상한의 몇 배 안에 들어야 함
	check(lim >= C.NET_PING_MS * 5, "핑 간격 %s 의 5배 이상" % C.NET_PING_MS)
	var t0 := 50000.0
	check(not NetScript.silent(t0 + 1000.0, t0, 0.0), "1초 전에 받음")
	check(not NetScript.silent(t0 + lim, t0, 0.0), "딱 6초는 아직")
	check(NetScript.silent(t0 + lim + 1.0, t0, 0.0), "6초 넘는 침묵")
	check(NetScript.silent(t0 + 12000.0, t0, 0.0), "12초 침묵")
	# 프레임이 12초 멈췄다 풀림: slack 이 침묵을 덮음
	check(not NetScript.silent(t0 + 12000.0, t0, 12000.0), "slack 12초가 12초 침묵을 덮음")
	check(not NetScript.silent(t0 + 12000.0, t0, 6000.0), "slack 6초 → 남은 6초는 아직")
	check(NetScript.silent(t0 + 12000.0, t0, 5000.0), "slack 5초 → 남은 7초는 침묵")
	check(not NetScript.silent(t0 + 99999.0, null, 0.0), "시각 없음 (안 붙어 있음 — 순수 함수 경계값)")
	# 실제 slack (net_meter): 프레임이 멈췄다 풀린 직후엔 멈춘 시간만큼, 고른 프레임이면 한 프레임
	var m := NetMeter.new()
	for i in 40:
		m.on_frame(t0 + i * 16.0)
	var last := t0 + 39 * 16.0
	check(NetScript.silent(last + 7000.0, last - 1.0, m.slack(last)), "고른 프레임 + 7초 침묵")
	m.on_frame(last + 12000.0) # 12초 멈췄다 풀린 프레임
	check(not NetScript.silent(last + 12000.0, last, m.slack(last + 12000.0)), "프레임이 12초 멈췄다 풀린 직후엔 안 끊음")


# 붙어 보기 상한 (net.gd connect_stuck): 시작한 뒤 CONNECT_MS (6초) 넘게 CONNECTING 이면 true. 프레임이 멈췄던 시간 (slack) 은 빼고, 시작 시각이 없으면 false
func test_net_connect_timeout() -> void:
	var lim: float = NetScript.CONNECT_MS
	check(lim == 6000.0, "붙어 보기 상한 %s" % lim)
	check(lim >= C.NET_RECONNECT_MS, "다시 붙기 간격 %s 이상 (시도마다 max(간격, 상한))" % C.NET_RECONNECT_MS)
	# 다 막힌 서버면 포기까지 시도 수 × 6초 (README 침묵 감지 단락의 '약 3분')
	check(C.NET_RECONNECT_TRIES * maxf(C.NET_RECONNECT_MS, lim) == 180000.0, "포기까지 %s ms" % (C.NET_RECONNECT_TRIES * maxf(C.NET_RECONNECT_MS, lim)))
	var t0 := 40000.0
	check(not NetScript.connect_stuck(t0 + 1000.0, t0, 0.0), "1초째는 아직")
	check(not NetScript.connect_stuck(t0 + lim, t0, 0.0), "딱 6초는 아직")
	check(NetScript.connect_stuck(t0 + lim + 1.0, t0, 0.0), "6초 넘게 매달림")
	check(not NetScript.connect_stuck(t0 + 12000.0, t0, 12000.0), "프레임이 12초 멈췄다 풀린 직후엔 안 버림")
	check(NetScript.connect_stuck(t0 + 12000.0, t0, 5000.0), "slack 5초 → 남은 7초는 매달림")
	check(not NetScript.connect_stuck(t0 + 99999.0, null, 0.0), "시작 시각 없음")


# retry() 가 붙어 보기를 버릴 때 (net.gd retry_drops): 시작한 뒤 NET_RECONNECT_MS (2초) 넘게 CONNECTING 일 때만. 그보다 젊으면 느린 핸드셰이크일 수 있어 그대로.
# 프레임이 멈췄던 시간 (slack) 은 빼고, 시작 시각이 없으면 false. 2초 ~ CONNECT_MS (6초) 사이는 버튼을 눌렀을 때만 버림 (그 뒤는 프레임이 버림)
func test_net_retry_drops() -> void:
	var lim: float = C.NET_RECONNECT_MS
	check(lim == 2000.0, "다시 붙기 간격 %s" % lim)
	check(lim < NetScript.CONNECT_MS, "붙어 보기 상한 %s 보다 짧음" % NetScript.CONNECT_MS)
	var t0 := 30000.0
	check(not NetScript.retry_drops(t0, t0, 0.0), "막 시작함")
	check(not NetScript.retry_drops(t0 + 800.0, t0, 0.0), "0.8초째 (느린 터널 핸드셰이크) 는 그대로")
	check(not NetScript.retry_drops(t0 + lim, t0, 0.0), "딱 2초는 아직")
	check(NetScript.retry_drops(t0 + lim + 1.0, t0, 0.0), "2초 넘게 매달림 → 버림")
	check(not NetScript.connect_stuck(t0 + lim + 1.0, t0, 0.0), "그때 프레임은 아직 안 버림 (버튼만)")
	check(not NetScript.retry_drops(t0 + 3000.0, t0, 1500.0), "slack 1.5초 → 남은 1.5초는 아직")
	check(NetScript.retry_drops(t0 + 3000.0, t0, 500.0), "slack 0.5초 → 남은 2.5초는 매달림")
	check(not NetScript.retry_drops(t0 + 99999.0, null, 0.0), "시작 시각 없음")


# 멈춘 서버 (TCP 는 받아 주지만 업그레이드 응답이 없음 — 안 읽는 TCPServer) 에 붙어 보기: 상한이 지나면 소켓을 버리고 다음 시도로,
# 다 쓰면 gave_up, retry() 는 NET_RECONNECT_MS 넘게 매달린 소켓만 버리고 처음부터 (젊은 붙어 보기는 그대로).
# 상한을 기다리지 않게 connect_at 을 과거로 돌려 프레임 (_prof_process) 을 직접 돌림
func test_net_connect_stuck_moves_on() -> void:
	var hole := TCPServer.new()
	check(hole.listen(0, "127.0.0.1") == OK, "안 읽는 TCP 리스너")
	var n = NetScript.new() # 트리에 안 넣음 (_process 없음 — 프레임은 아래에서 직접)
	var texts: Array = []
	var gave: Array = []
	n.status_changed.connect(func(t): texts.append(t))
	n.gave_up.connect(func(): gave.append(1))
	var frame := func(times: int) -> void:
		for i in times:
			n._prof_process(0.0)
			OS.delay_msec(5)
	var back := NetScript.CONNECT_MS + 1000.0 # 상한 + 프레임 여유
	n.start("ws://127.0.0.1:%d" % hole.get_local_port())
	frame.call(20)
	check(n.ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING and n.connect_at != null, "처음 접속이 매달림 (상태 %d)" % n.ws.get_ready_state())
	check(not n.reconnecting and n.tries == 0, "상한 전엔 그대로")
	# 처음 접속이 상한을 넘김 → 버리고 끊긴 것과 같은 길 ('서버 응답 없음')
	n.connect_at = NetScript.now_ms() - back
	frame.call(1)
	check(n.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and n.connect_at == null, "처음 접속 소켓을 버림")
	check(n.reconnecting and n.lost == NetScript.LOST_SILENT and texts.back() == "서버 응답 없음 — 다시 연결 중", "다시 붙기 시작: %s" % str(texts))
	n.retry_at = 0.0
	frame.call(3)
	check(n.tries == 1 and n.ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING, "다음 시도 (%d, 상태 %d)" % [n.tries, n.ws.get_ready_state()])
	# 다시 붙는 중 매달림 → 다음 프레임에 횟수를 올려 바로 다음 시도 (간격 retry_at 은 이미 지남)
	n.connect_at = NetScript.now_ms() - back
	n.retry_at = 0.0
	frame.call(3)
	check(n.tries == 2 and n.ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING, "매달린 시도 다음으로 (%d)" % n.tries)
	check(texts.back() == "서버 응답 없음 — 다시 연결 중 (2/%d)" % int(C.NET_RECONNECT_TRIES), "상태 글: %s" % texts.back())
	# 마지막 시도도 매달림 → gave_up
	n.tries = int(C.NET_RECONNECT_TRIES)
	n.connect_at = NetScript.now_ms() - back
	n.retry_at = 0.0
	frame.call(3)
	check(gave.size() == 1 and not n.reconnecting and n.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED, "다 쓰면 gave_up (%d, %s)" % [gave.size(), n.reconnecting])
	# retry(): 포기한 뒤 → 다시 시작
	n.retry()
	frame.call(3)
	check(n.tries == 1 and n.ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING, "retry → 다시 붙어 봄 (%d)" % n.tries)
	# 붙어 보기 직후 거듭 누름 (느린 핸드셰이크일 수 있음): 소켓·시작 시각 그대로, 횟수만 되돌림
	var young = n.ws
	var young_at = n.connect_at
	for i in 5:
		n.tries = 9
		n.retry()
		check(n.tries == 0, "누를 때마다 횟수 0 (%d)" % n.tries)
		frame.call(1)
	check(n.ws == young and n.connect_at == young_at and n.ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING, "젊은 붙어 보기는 안 버림")
	# 2초 넘게 매달린 뒤 (프레임은 CONNECT_MS 전이라 아직 안 버림) 누르면 버리고 처음부터
	n.connect_at = NetScript.now_ms() - (C.NET_RECONNECT_MS + 1000.0)
	frame.call(1)
	check(n.ws == young and n.ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING, "프레임은 CONNECT_MS 전엔 그대로")
	var hung = n.ws
	n.tries = 9
	n.retry()
	check(n.ws != hung or n.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED, "매달린 소켓을 버림")
	check(n.tries == 0 and n.reconnecting and n.retry_at <= NetScript.now_ms() and n.connect_at == null, "횟수 0, 바로 다시 (%d)" % n.tries)
	frame.call(3)
	check(n.tries == 1 and n.ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING, "새 시도 (%d)" % n.tries)
	check(gave.size() == 1, "gave_up 은 한 번만")
	n._discard()
	hole.stop()
	n.free()


# 붙은 순간부터 침묵을 셈 (net.gd 붙은 갈래의 last_recv_at = now): 업그레이드까지 해 주고 아무 말도 안 하는 서버 (TCPServer + 서버 쪽 WebSocketPeer,
# pong 도 없음) 에 붙음. 받은 게 없어도 붙은 순간 last_recv_at 이 있어야 침묵 감시가 돎 (없으면 '받은 적 없음' 이라 영영 안 끊김).
# 6초를 기다리지 않게 last_recv_at 을 상한 너머 과거로 밀고 프레임 (_prof_process) 을 직접 돌림 → 버리고 같은 길로 다시 붙음
func test_net_silent_from_open() -> void:
	var tcp := TCPServer.new()
	check(tcp.listen(0, "127.0.0.1") == OK, "말 없는 WebSocket 리스너")
	var peers: Array = [] # 서버 쪽 소켓: 업그레이드 응답만 (poll), 아무것도 안 보냄
	var n = NetScript.new() # 트리에 안 넣음 (_process 없음 — 프레임은 아래에서 직접)
	var texts: Array = []
	var opens: Array = []
	var closes: Array = []
	n.status_changed.connect(func(t): texts.append(t))
	n.opened.connect(func(again): opens.append(again))
	n.closed.connect(func(): closes.append(1))
	var step := func() -> void:
		while tcp.is_connection_available():
			var p := WebSocketPeer.new()
			p.accept_stream(tcp.take_connection())
			peers.append(p)
		for p in peers:
			p.poll()
		n._prof_process(0.0)
		OS.delay_msec(5)
	var until_open := func() -> void:
		for i in 400: # 최대 약 2초
			step.call()
			if n.is_open():
				return
	var before := NetScript.now_ms()
	n.start("ws://127.0.0.1:%d" % tcp.get_local_port())
	until_open.call()
	check(n.is_open() and opens == [false], "붙음 (상태 %d, %s)" % [n.ws.get_ready_state(), str(opens)])
	check(n.recv_bytes == 0, "서버가 아무것도 안 보냄 (%d바이트)" % n.recv_bytes)
	check(n.last_recv_at != null and float(n.last_recv_at) >= before, "받은 게 없어도 붙은 순간부터 잼 (%s)" % str(n.last_recv_at))
	for i in 3:
		step.call()
	check(n.is_open() and closes.is_empty(), "상한 전엔 그대로")
	# 붙은 뒤 침묵이 상한을 넘음 → 그 소켓을 버리고 끊긴 것과 같은 길 ('서버 응답 없음')
	if n.last_recv_at != null:
		n.last_recv_at = float(n.last_recv_at) - (NetScript.SILENCE_MS + 1000.0)
	step.call()
	check(not n.is_open() and closes.size() == 1 and n.last_recv_at == null, "조용한 소켓을 버림 (상태 %d, 끊김 %d)" % [n.ws.get_ready_state(), closes.size()])
	check(n.reconnecting and n.lost == NetScript.LOST_SILENT and texts.back() == "서버 응답 없음 — 다시 연결 중", "다시 붙기 시작: %s" % str(texts))
	# 간격을 기다리지 않게 retry_at 을 당기면 같은 서버로 다시 붙고, 다시 붙은 순간부터 또 잼
	n.retry_at = 0.0
	before = NetScript.now_ms()
	until_open.call()
	check(n.is_open() and opens == [false, true] and n.tries == 0, "다시 붙음 (%s, %d)" % [str(opens), n.tries])
	check(n.last_recv_at != null and float(n.last_recv_at) >= before, "다시 붙은 순간부터 잼 (%s)" % str(n.last_recv_at))
	n._discard()
	for p in peers:
		p.close(-1)
	tcp.stop()
	n.free()


# 끊긴 까닭 글 (닫기 코드 + 까닭 글): 1001 + "server shutdown" (C# 서버를 끔 — WsSocket.Bye) 만 '서버가 꺼짐'. 다른 까닭의 1001 (프록시·터널의 Going Away),
# 보통 닫힘 1000·비정상 1006·코드 없음 -1 은 '서버 연결 끊김' (사이클 5 리뷰 F2 — 예전엔 코드만 봄)
func test_net_lost_reason() -> void:
	var why := NetScript.SHUTDOWN_CLOSE_REASON
	check(why == "server shutdown", "까닭 글: %s" % why)
	check(NetScript.is_shutdown(1001, why) and NetScript.lost_reason(1001, why) == NetScript.LOST_SHUTDOWN, "1001 + 끄기 → %s" % NetScript.lost_reason(1001, why))
	check(NetScript.LOST_SHUTDOWN == "서버가 꺼짐", "글: %s" % NetScript.LOST_SHUTDOWN)
	for r in ["", "going away", "Server Shutdown", "server shutdown "]:
		check(not NetScript.is_shutdown(1001, r) and NetScript.lost_reason(1001, r) == NetScript.LOST_CLOSED, "1001 + '%s' → %s" % [r, NetScript.lost_reason(1001, r)])
	for code in [1000, 1006, -1, 1011]:
		check(not NetScript.is_shutdown(code, why) and NetScript.lost_reason(code, why) == NetScript.LOST_CLOSED, "%d → %s" % [code, NetScript.lost_reason(code, why)])


# 클라 상수가 C# 서버 소스와 같은 글인지 (test_complete.gd 처럼 서버 소스를 읽음): 닫기 까닭 글 (WsSocket.cs CloseOutputAsync) · 끄기 left 이유 (Rooms.cs SHUTDOWN_REASON)
func test_shutdown_consts_match_server() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../server/src/Tetrafall.Server/")
	var ws := FileAccess.get_file_as_string(dir.path_join("WsSocket.cs"))
	var rooms := FileAccess.get_file_as_string(dir.path_join("Rooms.cs"))
	check(ws != "" and rooms != "", "서버 소스를 읽음 (%s)" % dir)
	check(ws.contains("CloseOutputAsync(WebSocketCloseStatus.EndpointUnavailable, \"%s\"" % NetScript.SHUTDOWN_CLOSE_REASON), "WsSocket.cs 닫기 까닭 글 = '%s'" % NetScript.SHUTDOWN_CLOSE_REASON)
	check(rooms.contains("public const string SHUTDOWN_REASON = \"%s\";" % StoreScript.LEFT_SHUTDOWN), "Rooms.cs SHUTDOWN_REASON = '%s'" % StoreScript.LEFT_SHUTDOWN)
	check(int(NetScript.CLOSE_GOING_AWAY) == 1001, "Going Away = EndpointUnavailable 1001")


# 서버를 끔: 붙은 뒤 서버 쪽 소켓 (TCPServer + WebSocketPeer, test_net_silent_from_open 과 같은 모양) 이 left 를 보내고 틈 뒤 닫기 1001
# (C# WsSocket.Bye 의 NET_SHUTDOWN_CLOSE_GAP_MS — 한 poll 에 left 와 닫기를 같이 받으면 고도는 left 를 못 읽음)
# → left 는 message 로, 상태 글 '서버가 꺼짐 — 다시 연결 중', 핑 자리 글 '연결 끊김 · 다시 연결 중 N' (지난 핑 대신), 다시 붙기는 그대로 (같은 길)
func test_net_server_shutdown_close() -> void:
	var tcp := TCPServer.new()
	check(tcp.listen(0, "127.0.0.1") == OK, "WebSocket 리스너")
	var peers: Array = []
	var n = NetScript.new() # 트리에 안 넣음 (_process 없음 — 프레임은 아래에서 직접)
	var texts: Array = []
	var closes: Array = []
	var msgs: Array = []
	n.status_changed.connect(func(t): texts.append(t))
	n.closed.connect(func(): closes.append(1))
	n.message.connect(func(m): msgs.append(m))
	var step := func() -> void:
		while tcp.is_connection_available():
			var p := WebSocketPeer.new()
			p.accept_stream(tcp.take_connection())
			peers.append(p)
		for p in peers:
			p.poll()
		n._prof_process(0.0)
		OS.delay_msec(5)
	n.start("ws://127.0.0.1:%d" % tcp.get_local_port())
	for i in 400: # 최대 약 2초
		step.call()
		if n.is_open():
			break
	check(n.is_open() and peers.size() == 1, "붙음 (상태 %d, 서버 쪽 %d)" % [n.ws.get_ready_state(), peers.size()])
	check(n.ping_text().begins_with("핑 "), "붙어 있을 땐 핑 글: %s" % n.ping_text())
	for p in peers:
		p.send_text(JSON.stringify({"type": "left", "reason": "서버를 껐습니다"}))
	for i in 400:
		step.call()
		if msgs.any(func(m): return m.get("type") == "left"):
			break
	check(msgs.any(func(m): return m.get("type") == "left") and n.is_open(), "닫기 전에 left 를 읽음 (%s)" % str(msgs))
	for p in peers:
		p.close(1001, "server shutdown")
	for i in 400:
		step.call()
		if not closes.is_empty():
			break
	check(closes.size() == 1 and not n.is_open(), "끊김 (끊김 %d, 상태 %d)" % [closes.size(), n.ws.get_ready_state()])
	check(n.reconnecting and n.lost == NetScript.LOST_SHUTDOWN, "다시 붙기 시작, 까닭 %s" % n.lost)
	check(not texts.is_empty() and str(texts.back()).begins_with("서버가 꺼짐 — "), "상태 글: %s" % str(texts))
	check(n.ping_text().begins_with("연결 끊김"), "핑 자리 글: %s" % n.ping_text())
	check(n.ping_text() == "연결 끊김 · 다시 연결 중", "아직 다시 붙어 보기 전엔 숫자 없음 (상태 글과 같게, ' 0' 아님): %s" % n.ping_text())
	check(n.ping_value() == NetScript.PING_LOST, "성능 판 핑 값: %s" % n.ping_value())
	# 다시 붙어 보기 (서버가 다시 켜진 셈 — 같은 리스너): 시도 글도 같은 까닭, 횟수가 핑 자리에
	n.retry_at = 0.0
	step.call()
	check(n.tries == 1 and texts.back() == "서버가 꺼짐 — 다시 연결 중 (1/%d)" % int(C.NET_RECONNECT_TRIES), "시도 글: %s" % texts.back())
	check(n.ping_text() == "연결 끊김 · 다시 연결 중 1", "핑 자리 시도 횟수: %s" % n.ping_text())
	for i in 400:
		step.call()
		if n.is_open():
			break
	check(n.is_open() and not n.reconnecting and n.ping_text().begins_with("핑 "), "다시 붙으면 핑 글 (%s)" % n.ping_text())
	n._discard()
	for p in peers:
		p.close(-1)
	tcp.stop()
	n.free()


# 다시 붙기 처음부터 (net.gd retry): 포기한 뒤 (횟수 다 씀) 면 횟수를 되돌리고 바로 다시, 주소가 없으면 (접속 시작 전) 아무것도 안 함
func test_net_retry_restarts() -> void:
	var n = NetScript.new() # 트리에 안 넣음 (_process 없음 = 실제 접속 안 함)
	var texts: Array = []
	n.status_changed.connect(func(t): texts.append(t))
	n.tries = int(C.NET_RECONNECT_TRIES)
	n.retry()
	check(n.tries == int(C.NET_RECONNECT_TRIES) and not n.reconnecting and texts.is_empty(), "주소 없으면 그대로")
	n.url = "ws://127.0.0.1:1"
	n.retry()
	check(n.tries == 0 and n.reconnecting and n.retry_at <= NetScript.now_ms(), "포기한 뒤 → 횟수 0, 바로 다시 (%d, %s)" % [n.tries, n.reconnecting])
	check(texts == ["서버 연결 끊김 — 다시 연결 중"], "상태 글: %s" % str(texts))
	n.tries = 7 # 다시 붙는 중에 또 누름: 횟수만 되돌림
	n.retry()
	check(n.tries == 0 and n.reconnecting and texts.size() == 1, "붙는 중이면 횟수만: %s" % str(texts))
	n.free()


# 시험용 Store (자동 로드와 따로 — 트리에 안 넣어 Net 신호를 안 받음): 방 안 상태로 채움
func _store_in_room():
	var s = StoreScript.new()
	s.my_id = 3
	s.room = {"code": "ZZZZ", "name": "시험"}
	s.state = {"phase": "lobby", "players": [{"id": 3}]}
	s.prev_state = {"phase": "lobby"}
	s.tracks = {3: [[0.0, 1.0, 1.0, 1.0]]}
	s._players_by_id = {3: {"id": 3}}
	return s


func _store_cleared(s) -> bool:
	return not s.in_room() and s.my_id == null and s.room.is_empty() and s.state.is_empty() and s.prev_state.is_empty() and s.tracks.is_empty() and s._players_by_id.is_empty()


# 죽은 방 탈출 (store.gd): 방 안에서 joinError (다시 붙었는데 그 방이 없음·꽉 참) → 방을 비우고 left_room(중립 앞머리 + 서버 이유) = 메뉴로. 방 밖 joinError 는 join_error 만
func test_store_dead_room_exit() -> void:
	check(StoreScript.join_error_action(true) == "left" and StoreScript.join_error_action(false) == "error", "joinError 처리 고르기")
	var s = _store_in_room()
	var left: Array = []
	var errs: Array = []
	s.left_room.connect(func(r): left.append(r))
	s.join_error.connect(func(r): errs.append(r))
	s.pending_code = "ZZZZ" # 다시 붙은 뒤 rejoin → rejoinError → join 을 보낸 상태
	s._on_message({"type": "joinError", "reason": "ZZZZ: 그런 방이 없습니다"})
	check(_store_cleared(s), "방 안 + joinError → 방 정리 (id %s, 방 %s)" % [str(s.my_id), str(s.room)])
	check(s.pending_code == "", "들어가려던 방도 지움")
	check(left == ["방으로 돌아가지 못했습니다 — ZZZZ: 그런 방이 없습니다"], "left_room 이유: %s" % str(left))
	check(errs.is_empty(), "방 안이면 join_error 는 안 냄: %s" % str(errs))
	# 방 밖 (메뉴에서 없는 코드): join_error 만
	s._on_message({"type": "joinError", "reason": "QQQQ: 그런 방이 없습니다"})
	check(errs == ["QQQQ: 그런 방이 없습니다"] and left.size() == 1, "방 밖 + joinError → join_error 만: %s / %s" % [str(errs), str(left)])
	s.free()
	# 자리 유지 (60초) 가 지난 뒤 다시 붙었는데 그 방이 꽉 참 (rejoinError → join → joinError): 앞머리가 '방이 없어졌습니다' 처럼 이유와 어긋나지 않음
	s = _store_in_room()
	left.clear()
	s.left_room.connect(func(r): left.append(r))
	s._on_message({"type": "joinError", "reason": "방이 꽉 찼습니다 (최대 8명)"})
	check(_store_cleared(s) and left == ["방으로 돌아가지 못했습니다 — 방이 꽉 찼습니다 (최대 8명)"], "꽉 찬 방 → 방 정리 + 이유: %s" % str(left))
	check(not str(left).contains("없어졌"), "꽉 찬 방에 '없어졌습니다' 를 붙이지 않음")
	# 서버의 left 는 예전 그대로 (같은 정리 함수): 이유 그대로, 방 정리
	s.free()
	s = _store_in_room()
	left.clear()
	s.left_room.connect(func(r): left.append(r))
	s._on_message({"type": "left", "reason": "방장이 내보냄"})
	check(_store_cleared(s) and left == ["방장이 내보냄"], "left → 방 정리 + 이유: %s" % str(left))
	s._on_message({"type": "state", "phase": "lobby", "players": [], "time": 1.0, "recvAt": 1.0})
	check(s.state.is_empty(), "방 밖에서 온 남은 스냅샷은 버림")
	s.free()


# 서버를 끈 닫기 → Store (사이클 5 리뷰 F2): 서버 쪽 소켓 (TCPServer + WebSocketPeer) 이 left·닫기를 보내고, 클라 (Net 시험용 + Store 시험용, 신호를 직접 이음) 를 돌림.
# send_left: 서버가 left 를 먼저 보냄, gap: left 와 닫기 사이에 클라가 poll 함 (서버 틈이 지켜진 경우) — false 면 둘 다 클라 버퍼에 쌓인 뒤 처음 poll.
# 반환 {left: left_room 이유들, read_left: Net 이 left 를 읽었나, in_room, lost, reconnecting}
func _shutdown_run(send_left: bool, gap: bool, reason: String) -> Dictionary:
	var tcp := TCPServer.new()
	check(tcp.listen(0, "127.0.0.1") == OK, "WebSocket 리스너")
	var peers: Array = []
	var n = NetScript.new() # 트리에 안 넣음 (_process 없음 — 프레임은 아래에서 직접)
	var s = _store_in_room() # 트리에 안 넣음 → 자동 로드 Net 대신 이 n 의 신호를 직접 이음
	var out := {"left": [], "read_left": false}
	s.left_room.connect(func(r): out.left.append(r))
	n.message.connect(func(m):
		if m.get("type") == "left":
			out.read_left = true
		s._on_message(m))
	n.server_shutdown.connect(s._on_server_shutdown)
	var serve := func() -> void:
		while tcp.is_connection_available():
			var p := WebSocketPeer.new()
			p.accept_stream(tcp.take_connection())
			peers.append(p)
		for p in peers:
			p.poll()
	n.start("ws://127.0.0.1:%d" % tcp.get_local_port())
	for i in 400: # 최대 약 2초
		serve.call()
		n._prof_process(0.0)
		OS.delay_msec(5)
		if n.is_open():
			break
	check(n.is_open() and peers.size() == 1, "붙음 (상태 %d)" % n.ws.get_ready_state())
	if send_left:
		for p in peers:
			p.send_text(JSON.stringify({"type": "left", "reason": StoreScript.LEFT_SHUTDOWN}))
		if gap:
			for i in 400:
				serve.call()
				n._prof_process(0.0)
				OS.delay_msec(5)
				if out.read_left:
					break
	for p in peers:
		p.close(1001, reason)
	for i in 10: # 서버 쪽만 돌려 left·닫기 프레임을 다 내보냄 (그동안 클라는 poll 안 함 — 창 끌기·로딩·백그라운드 탭)
		serve.call()
		OS.delay_msec(5)
	for i in 400:
		n._prof_process(0.0)
		if n.reconnecting:
			break
		serve.call()
		OS.delay_msec(5)
	out["in_room"] = s.in_room()
	out["cleared"] = _store_cleared(s)
	out["lost"] = n.lost
	out["reconnecting"] = n.reconnecting
	n._discard()
	for p in peers:
		p.close(-1)
	tcp.stop()
	n.free()
	s.free()
	return out


func test_store_server_shutdown_close() -> void:
	var why := NetScript.SHUTDOWN_CLOSE_REASON
	# left 와 닫기가 한 poll 에: 고도는 left 를 못 읽고 바로 CLOSED (읽혀도 같은 이유 한 번) → 방을 비우고 끄기 문구로 메뉴
	var r := _shutdown_run(true, false, why)
	check(r.cleared and r.left == [StoreScript.LEFT_SHUTDOWN], "한 poll 에 left + 1001 → 방 비움 + 끄기 문구 한 번: %s (left 읽음 %s)" % [str(r.left), r.read_left])
	check(r.reconnecting and r.lost == NetScript.LOST_SHUTDOWN, "다시 붙기는 그대로 (%s, %s)" % [r.reconnecting, r.lost])
	# left 없이 닫기만 (left 를 잃음): 닫기만으로 방을 비움 — 예전엔 다시 붙기를 다 쓸 때까지 (약 60초) 방에 갇혔음
	r = _shutdown_run(false, false, why)
	check(not r.read_left and r.cleared and r.left == [StoreScript.LEFT_SHUTDOWN], "닫기만 → 방 비움 + 끄기 문구: %s" % str(r.left))
	# 틈이 지켜져 left 를 먼저 읽음: left 로 방 밖 → 닫기는 아무 일 없음 (left_room 한 번)
	r = _shutdown_run(true, true, why)
	check(r.read_left and r.cleared and r.left == [StoreScript.LEFT_SHUTDOWN], "left 먼저 → left_room 한 번: %s" % str(r.left))
	# 같은 1001 이라도 까닭 글이 다르면 (프록시·터널의 Going Away): 방에 남고 다시 붙어 자리 토큰으로 돌아감 ('서버 연결 끊김')
	r = _shutdown_run(false, false, "going away")
	check(r.in_room and r.left.is_empty(), "다른 까닭의 1001 → 방에 남음: %s" % str(r.left))
	check(r.reconnecting and r.lost == NetScript.LOST_CLOSED, "다시 붙는 까닭 '서버 연결 끊김' (%s)" % r.lost)


# 다시 붙기를 포기하면 (Net.gave_up): 방 안이면 방을 비우고 지금 상태 글을 이유로 메뉴로, 방 밖이면 아무 일 없음
func test_store_gave_up_exit() -> void:
	var s = _store_in_room()
	var left: Array = []
	s.left_room.connect(func(r): left.append(r))
	var keep: String = Net.status
	Net.status = "다시 연결 못 함 (시험)"
	s._on_gave_up()
	check(_store_cleared(s) and left == ["다시 연결 못 함 (시험)"], "방 안 + 포기 → 방 정리 + 상태 글: %s" % str(left))
	s._on_gave_up()
	check(left.size() == 1, "방 밖이면 아무 일 없음")
	Net.status = keep
	s.free()


# 연결 없이 방 나가기 (store.gd leave): 서버의 left 가 올 수 없으니 그 자리에서 방 정리 + left_room("")
func test_store_leave_offline() -> void:
	check(not Net.is_open(), "시험 러너는 서버에 안 붙음")
	var s = _store_in_room()
	var left: Array = []
	s.left_room.connect(func(r): left.append(r))
	s.pending_code = "ZZZZ"
	s.leave()
	check(_store_cleared(s), "연결 없이 leave → 방 정리 (id %s, 방 %s)" % [str(s.my_id), str(s.room)])
	check(left == [""], "left_room 한 번, 이유 없음: %s" % str(left))
	check(s.pending_code == "", "다시 붙어도 그 방으로 안 돌아감")
	s.leave() # 방 밖에서 또 불러도 조용히
	check(left.size() == 1, "방 밖 leave 는 신호 없음")
	s.free()


# 메뉴 (ui/menu.gd): 연결 없이 방 만들기·들어가기·연습·튜토리얼을 누르면 글로 알리고 아무것도 안 함 — 만들기의 한 번짜리 welcome 연결도 안 남김
func test_menu_offline_press() -> void:
	check(not Net.is_open(), "시험 러너는 서버에 안 붙음")
	var menu = Menu.new()
	menu._ready()
	var mine := func() -> int:
		var n := 0
		for c in Store.joined.get_connections():
			if (c.callable as Callable).get_object() == menu:
				n += 1
		return n
	var tut: Array = []
	menu.open_tutorial.connect(func(): tut.append(1))
	var ran: Array = []
	for action in [menu._create, menu._practice, func(): menu._join("WXYZ"), func(): menu.open_tutorial.emit(), func(): ran.append(1)]:
		menu.msg.text = ""
		menu._online_do(action)
		check(menu.msg.text == Menu.OFFLINE_TEXT, "연결 없음 글: %s" % menu.msg.text)
	check(mine.call() == 0, "만들기의 한 번짜리 연결을 안 남김")
	check(tut.is_empty() and ran.is_empty(), "연결 없으면 아무것도 안 함")
	check(Store.pending_code == "", "들어가려는 방도 안 남김")
	# 붙어 있을 때 만들기를 눌렀다가 welcome 전에 끊긴 뒤 다시 누름: 남아 있던 연결을 걷음
	menu._create()
	check(mine.call() == 1, "만들기 → 연결 하나")
	menu._online_do(menu._create)
	check(mine.call() == 0, "연결 없이 다시 누르면 걷음")
	menu.free()


func test_keys_match_js() -> void:
	var fx = load_json("keys.json")
	for row in fx.labels:
		check(Keys.key_label(row[0]) == row[1], "키 글자 %s → %s / JS %s" % [row[0], Keys.key_label(row[0]), row[1]])
	for row in fx.wheel:
		var got := Keys.wheel_slot(Vector2(row[0], row[1]), C.EMOTE_NAMES.size(), C.EMOTE_PICK_PX)
		check(got == int(row[2]), "바퀴 (%s, %s) → %d / JS %d" % [row[0], row[1], got, int(row[2])])
	var binds := Keys.default_binds()
	check(binds == fx.defaults, "기본 키가 JS 와 같음")
	for g in fx.groups:
		check(Keys.group_label(binds, g[0]) == g[1], "묶음 글자 %s / JS %s" % [Keys.group_label(binds, g[0]), g[1]])
	var clash := binds.duplicate()
	clash.skill = "KeyR"
	check(Keys.conflicts(clash) == fx.conflicts, "겹치는 키 %s / JS %s" % [str(Keys.conflicts(clash)), str(fx.conflicts)])


func test_event_codes() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_W
	check(Keys.event_code(k) == "KeyW", "W → KeyW")
	k.physical_keycode = KEY_SHIFT
	check(Keys.event_code(k) == "ShiftLeft", "Shift → ShiftLeft")
	k.physical_keycode = KEY_F3
	check(Keys.event_code(k) == "F3", "F3")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	check(Keys.event_code(mb) == "Mouse2", "우클릭 → Mouse2 (브라우저 번호)")
	for a in Keys.ACTIONS:
		var c: String = a.def
		check(c.begins_with("Mouse") or c.begins_with("Key") or c in Keys.NAMED or c.begins_with("F"), "기본 키 %s 를 고도에서 만들 수 있음" % c)


# 좌표: 게임 ↔ 고도 왕복, 고도 카메라가 게임 yaw 쪽을 보면 yaw_of 가 그 yaw (소리 좌우가 화면과 맞게)
func test_coords_roundtrip_and_yaw() -> void:
	const Co := preload("res://core/coords.gd")
	var v := Vector3(3.5, -2.25, 1.5)
	check(Co.game(Co.gpos(v)).is_equal_approx(v), "game(gpos(v)) = v")
	for yaw in [0.0, 0.7, 2.0, -1.2, 3.0]:
		var n := Node3D.new()
		n.look_at_from_position(Vector3.ZERO, Co.dir(yaw), Vector3.UP)
		check(absf(wrapf(Co.yaw_of(n) - yaw, -PI, PI)) < 1e-4, "yaw_of(카메라가 dir(%s) 를 봄) = %s" % [yaw, Co.yaw_of(n)])
		var body := Node3D.new()
		body.rotation.y = Co.rot_y(yaw)
		check((body.basis * Vector3.RIGHT).is_equal_approx(Co.dir(yaw)), "rot_y: +x 를 보던 몸이 dir(yaw) 를 봄 (yaw %s)" % yaw)
		n.free()
		body.free()


# 좌표 거울 고침 (x, z, -y) 과 입력이 맞는지: 마우스를 오른쪽으로 (yaw 줄어듦) = 카메라 오른쪽으로 돎, 오른쪽 이동 (strafe) = 화면 오른쪽
func test_input_yaw_matches_camera() -> void:
	const Co := preload("res://core/coords.gd")
	for yaw in [0.0, 0.9, 2.5, -2.0]:
		var cam := Node3D.new()
		cam.look_at_from_position(Vector3.ZERO, Co.dir(yaw), Vector3.UP)
		var right := cam.transform.basis.x # 카메라 화면 오른쪽
		# 서버 moveDir: strafe +1 = 게임 (sin yaw, -cos yaw)
		var strafe := Co.gpos(Vector3(sin(yaw), -cos(yaw), 0))
		check(strafe.is_equal_approx(right), "strafe 오른쪽 = 카메라 오른쪽 (yaw %s): %s / %s" % [yaw, strafe, right])
		# 마우스 오른쪽 → yaw -= dx·감도 → 보는 쪽이 카메라 오른쪽으로 감
		var turned := Co.dir(yaw - 0.1)
		check(turned.dot(right) > 0, "마우스 오른쪽이면 오른쪽으로 돎 (yaw %s)" % yaw)
		cam.free()


# 화면 글에 쓰는 글자가 다 프로젝트 글꼴에 있음 (웹엔 시스템 글꼴 대체가 없어 빠진 글자는 빈 칸 — 2026-10-31 웹 관전 안내의 '·').
# 스크립트 (tests 빼고) 의 "…" 글 안 글자를 모아 ui_font (Black Han Sans 한글·라틴 + DejaVu 기호 조각) 에 있는지 봄
func test_ui_font_has_all_chars() -> void:
	var font: Font = load("res://assets/fonts/ui_font.tres")
	var re := RegEx.create_from_string("\"([^\"\\n]*)\"")
	var missing := {}
	var files := []
	var dirs := ["res://"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(d):
			if not sub.begins_with(".") and sub != "tests" and sub != "build":
				dirs.append(d.path_join(sub))
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				files.append(d.path_join(f))
	for path in files:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			for ch in m.get_string(1):
				var o := ch.unicode_at(0)
				if o > 32 and not missing.has(ch) and not font.has_char(o):
					missing[ch] = path
	check(files.size() > 30, "스크립트 %d개" % files.size())
	check(missing.is_empty(), "글꼴에 없는 글자: %s" % [missing])
