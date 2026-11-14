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


# 서버 침묵 감지 (net.gd silent): 마지막으로 받은 뒤 SILENCE_MS (6초) 넘게 조용하면 true. 프레임이 멈췄던 시간 (slack) 은 빼고, 받은 적 없으면 false
func test_net_silence_watchdog() -> void:
	var lim: float = NetScript.SILENCE_MS
	check(lim == 6000.0, "침묵 상한 %s" % lim)
	check(lim > C.NET_PING_MS * 3 and lim > C.ROOM_LIST_MS * 3, "핑·방 목록 간격 (1초) 의 몇 배")
	var t0 := 50000.0
	check(not NetScript.silent(t0 + 1000.0, t0, 0.0), "1초 전에 받음")
	check(not NetScript.silent(t0 + lim, t0, 0.0), "딱 6초는 아직")
	check(NetScript.silent(t0 + lim + 1.0, t0, 0.0), "6초 넘는 침묵")
	check(NetScript.silent(t0 + 12000.0, t0, 0.0), "12초 침묵")
	# 프레임이 12초 멈췄다 풀림: slack 이 침묵을 덮음
	check(not NetScript.silent(t0 + 12000.0, t0, 12000.0), "slack 12초가 12초 침묵을 덮음")
	check(not NetScript.silent(t0 + 12000.0, t0, 6000.0), "slack 6초 → 남은 6초는 아직")
	check(NetScript.silent(t0 + 12000.0, t0, 5000.0), "slack 5초 → 남은 7초는 침묵")
	check(not NetScript.silent(t0 + 99999.0, null, 0.0), "첫 패킷 전 (받은 적 없음)")
	# 실제 slack (net_meter): 프레임이 멈췄다 풀린 직후엔 멈춘 시간만큼, 고른 프레임이면 한 프레임
	var m := NetMeter.new()
	for i in 40:
		m.on_frame(t0 + i * 16.0)
	var last := t0 + 39 * 16.0
	check(NetScript.silent(last + 7000.0, last - 1.0, m.slack(last)), "고른 프레임 + 7초 침묵")
	m.on_frame(last + 12000.0) # 12초 멈췄다 풀린 프레임
	check(not NetScript.silent(last + 12000.0, last, m.slack(last + 12000.0)), "프레임이 12초 멈췄다 풀린 직후엔 안 끊음")


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


# 죽은 방 탈출 (store.gd): 방 안에서 joinError (다시 붙었는데 그 방이 없음) → 방을 비우고 left_room(이유) = 메뉴로. 방 밖 joinError 는 join_error 만
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
	check(left == ["방이 없어졌습니다 — ZZZZ: 그런 방이 없습니다"], "left_room 이유: %s" % str(left))
	check(errs.is_empty(), "방 안이면 join_error 는 안 냄: %s" % str(errs))
	# 방 밖 (메뉴에서 없는 코드): join_error 만
	s._on_message({"type": "joinError", "reason": "QQQQ: 그런 방이 없습니다"})
	check(errs == ["QQQQ: 그런 방이 없습니다"] and left.size() == 1, "방 밖 + joinError → join_error 만: %s / %s" % [str(errs), str(left)])
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
