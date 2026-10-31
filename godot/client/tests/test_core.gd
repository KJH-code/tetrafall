# G0 계산이 JS 화면과 같은 값인지 (tools/fixtures.mjs 가 뽑은 정답): 보간·핑 계산·키 설정
extends RefCounted

const C := preload("res://core/config.gd")
const Interp := preload("res://core/interp.gd")
const NetMeter := preload("res://core/net_meter.gd")
const Keys := preload("res://core/keys.gd")

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
