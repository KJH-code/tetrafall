# W43 모션 개선 3차 (Mixamo 없이): 방향 이동 (스트레이프·후진), 이동 기울임·방향 전환 (chars/ext_motion.gd 순수 계산 + external.gd 가산 층)
extends RefCounted

const Body := preload("res://chars/body.gd")
const Ext := preload("res://chars/external.gd")
const M := preload("res://chars/ext_motion.gd")
const Clips := preload("res://chars/ext_clips.gd")
const K := preload("res://chars/chars_config.gd")
const C := preload("res://core/config.gd")

var errors: Array = []
const CHARS := ["ninja", "tank", "hunter", "hook"]


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _body(ch: String):
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	return b


static func _st(over := {}) -> Dictionary:
	var st := {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "emote": -1, "victory": -1.0, "hit": null, "act": null,
		"tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "dizzy": 0.0, "whirl": -1.0, "glide": false,
		"accF": 0.0, "accS": 0.0, "mvF": 0.0, "mvS": 0.0, "vw": Vector2.ZERO}
	st.merge(over, true)
	return st


func _walk_st(f: float, s: float, ph := 1.0, run := false) -> Dictionary:
	var v: float = C.MOVE_SPEED * (1.0 if run else 0.6)
	return _st({"walking": true, "hs": v, "walk": ph, "mvF": v * f, "mvS": v * s, "vw": Vector2(v * f, v * s)})


func _step(X, st: Dictionary) -> void:
	var now := Time.get_ticks_msec() * 0.001
	X.cloth_t = now - 1.0 / 60.0
	X.extra_t = now - 1.0 / 60.0
	X.last_t = now - 1.0 / 60.0
	X.sync(st)


static func _gq(sk: Skeleton3D, nm: String) -> Quaternion:
	var b := sk.find_bone(nm)
	var t := Transform3D.IDENTITY
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t.basis.get_rotation_quaternion()


# ---------- 순수 계산 ----------

# 앞·옆·뒤 이동 방향을 접은 각과 뒤로 걸음 여부, 히스테리시스
func test_move_fold() -> void:
	var f := M.move_fold(4.0, 0.0, false)
	check(not f.rev and absf(f.psi) < 1e-5, "앞 = 뒤로 걸음 아님·psi 0")
	var b := M.move_fold(-4.0, 0.0, false)
	check(b.rev and absf(absf(b.psi)) < 1e-4, "뒤 = 뒤로 걸음·접은 각 0 (%f)" % b.psi)
	var l := M.move_fold(0.0, 4.0, false)
	check(not l.rev and absf(l.psi - PI / 2) < 1e-4, "왼쪽 옆 = 앞 모드 psi +90°")
	var r := M.move_fold(0.0, -4.0, false)
	check(not r.rev and absf(r.psi + PI / 2) < 1e-4, "오른쪽 옆 psi -90°")
	var bl := M.move_fold(-1.0, 1.0, false)
	check(bl.rev and absf(bl.psi + deg_to_rad(45.0)) < 1e-4, "뒤왼쪽 대각 = 거꾸로·접은 각 -45° (%f)" % rad_to_deg(bl.psi))
	var br := M.move_fold(-1.0, -1.0, false)
	check(br.rev and absf(br.psi - deg_to_rad(45.0)) < 1e-4, "뒤오른쪽 대각 = 거꾸로·접은 각 +45°")
	# 히스테리시스: 앞 모드에서 100° (문턱 105° 못 넘음) 는 그대로, 110° 는 거꾸로
	var a100 := M.move_fold(cos(deg_to_rad(100)), sin(deg_to_rad(100)), false)
	check(not a100.rev, "앞 모드 100° 는 안 바뀜")
	var a110 := M.move_fold(cos(deg_to_rad(110)), sin(deg_to_rad(110)), false)
	check(a110.rev, "앞 모드 110° 는 거꾸로")
	var c80 := M.move_fold(cos(deg_to_rad(80)), sin(deg_to_rad(80)), true)
	check(c80.rev, "거꾸로 모드 80° (문턱 75° 못 내려감) 는 그대로")
	var c70 := M.move_fold(cos(deg_to_rad(70)), sin(deg_to_rad(70)), true)
	check(not c70.rev, "거꾸로 모드 70° 는 앞으로")


# 골반 yaw 한계, 부호 (왼쪽 +), 접은 각 비례
func test_hip_yaw_limit() -> void:
	var lim := deg_to_rad(K.EXT_DIR_MAX_DEG)
	for d in [-180, -135, -90, -45, -10, 0, 10, 45, 90, 135, 180]:
		var y := M.hip_yaw(deg_to_rad(d))
		check(absf(y) <= lim + 1e-6, "골반 yaw 한계 안 (%d° → %f)" % [d, rad_to_deg(y)])
		check(y == 0.0 or signf(y) == signf(float(d)), "부호 (%d°)" % d)
	check(absf(M.hip_yaw(deg_to_rad(90)) - lim) < 1e-6, "옆걸음 90° 는 한계까지")
	check(M.hip_yaw(deg_to_rad(20)) < lim * 0.5, "작은 각은 한계의 절반 아래")


# 클립 고르기: 뒤로 걸음이면 같은 클립을 거꾸로 (t = 1 - t), 아니면 그대로, 걷지 않으면 rev 없음
func test_select_reverse() -> void:
	for ch in CHARS:
		var info = Ext.load_char(ch)
		var cc: Dictionary = info.cfg.get("clips", {})
		var base := _walk_st(1.0, 0.0, 1.1)
		var a := Clips.select(cc, base, 0.0)
		check(a.kind == "loco" and not bool(a.get("rev", false)), "%s 앞걸음은 정방향" % ch)
		var rv := _walk_st(-1.0, 0.0, 1.1)
		rv["rev"] = true
		var b := Clips.select(cc, rv, 0.0)
		check(b.clip == a.clip and bool(b.rev), "%s 뒤로 걸음: 같은 클립, rev" % ch)
		check(absf(fposmod(float(a.t) + float(b.t), 1.0)) < 1e-5 or absf(fposmod(float(a.t) + float(b.t), 1.0) - 1.0) < 1e-5, "%s 거꾸로 t = 1 - t (%f, %f)" % [ch, a.t, b.t])
		var idle := _st({"rev": true})
		check(not bool(Clips.select(cc, idle, 0.0).get("rev", false)), "%s 서 있으면 rev 없음" % ch)


func test_lean_pitch() -> void:
	var run: float = C.MOVE_SPEED
	var steady := M.lean_pitch(run, 0.0, false, true)
	check(steady > 0.0 and steady <= deg_to_rad(8.0), "달리면 앞으로 숙임 0~8° (%f)" % rad_to_deg(steady))
	check(M.lean_pitch(run * 0.5, 0.0, false, true) < steady, "느리면 덜 숙임")
	check(M.lean_pitch(0.0, 0.0, false, false) == 0.0, "서 있으면 0")
	var acc := M.lean_pitch(run, 30.0, false, true)
	check(acc > steady, "가속하면 더 앞으로")
	var brake := M.lean_pitch(run, -40.0, false, false)
	check(brake < 0.0, "급정지 = 뒤로 젖힘 (%f)" % brake)
	check(absf(brake) <= K.EXT_LEAN_ACC_MAX + 1e-6, "급정지 한계 (%f)" % brake)
	check(M.lean_pitch(run, 500.0, false, true) <= K.EXT_LEAN_SPEED_RAD + K.EXT_LEAN_ACC_MAX + 1e-6, "가속 한계")
	check(M.lean_pitch(run, 0.0, true, true) < 0.0, "뒤로 걸으면 뒤로 살짝")
	check(M.lean_pitch(run, NAN, false, true) == steady, "NaN 가속도는 무시")


func test_turn_twist_limit() -> void:
	check(absf(M.turn_twist(1000.0)) == K.EXT_TURN_MAX_RAD, "비틀림 한계")
	check(M.turn_twist(3.0) > 0.0 and M.turn_twist(-3.0) < 0.0, "부호")
	check(absf(M.wrap_pi(PI * 1.5) + PI * 0.5) < 1e-5, "각 접기")
	check(M.arm_swing_scale(0.1, true) >= K.EXT_ARM_SWING_RANGE.x and M.arm_swing_scale(99.0, true) <= K.EXT_ARM_SWING_RANGE.y, "팔 흔들림 배율 범위")


# 몸 상태에 몸 기준 이동 (앞·왼쪽) 이 들어감: yaw 90° (+y 를 봄) 에서 +x 로 가면 오른쪽 옆걸음
func test_anim_state_has_local_velocity() -> void:
	var b = _body("ninja")
	b.vxs = 2.0
	b.vys = 0.0
	var st: Dictionary = b._anim_state({"yaw": PI / 2}, 0.0)
	check(absf(float(st.mvF)) < 1e-4 and absf(float(st.mvS) + 2.0) < 1e-4, "yaw 90° 에서 +x 이동 = 오른쪽 (mvF %f mvS %f)" % [st.mvF, st.mvS])
	var st0: Dictionary = b._anim_state({"yaw": 0.0}, 0.0)
	check(absf(float(st0.mvF) - 2.0) < 1e-4 and absf(float(st0.mvS)) < 1e-4, "yaw 0 에서 +x 이동 = 앞")
	check(st0.vw == Vector2(2.0, 0.0), "월드 이동")
	b.free()


# ---------- 몸 (4명) ----------

# 옆걸음: 골반 yaw 가 들어가고 윗몸 (Spine2) 은 되돌려져 거의 그대로, 다리는 확 돌아감. 끄면 (move_off) 예전 그대로
func test_strafe_twists_hips_not_chest() -> void:
	for ch in CHARS:
		var b = _body(ch)
		var X = b.ext
		check(X != null, "%s 외부 몸" % ch)
		if X == null:
			b.free()
			continue
		var st_l := _walk_st(0.0, 1.0, 1.1)
		X.move_off = true
		for i in 8:
			_step(X, st_l)
		var off_chest := _gq(X.sk, "mixamorig_Spine2")
		var off_leg := _gq(X.sk, "mixamorig_LeftUpLeg")
		X.move_off = false
		X.dir_y = 0.0
		for i in 90:
			_step(X, st_l)
		var on_chest := _gq(X.sk, "mixamorig_Spine2")
		var on_leg := _gq(X.sk, "mixamorig_LeftUpLeg")
		check(absf(X.dir_y) > deg_to_rad(K.EXT_DIR_MAX_DEG) * 0.9, "%s 옆걸음 골반 yaw 가 한계 근처 (%f°)" % [ch, rad_to_deg(X.dir_y)])
		check(rad_to_deg(off_leg.angle_to(on_leg)) > 20.0, "%s 옆걸음에 다리가 돌아감 (%f°)" % [ch, rad_to_deg(off_leg.angle_to(on_leg))])
		check(rad_to_deg(off_chest.angle_to(on_chest)) < 14.0, "%s 옆걸음에도 윗몸은 앞 (%f°)" % [ch, rad_to_deg(off_chest.angle_to(on_chest))])
		b.free()


# 뒤로 걸음: 클립 거꾸로 + 상체 살짝 뒤로, 골반 yaw 는 0 근처. 서면 모두 풀림
func test_backward_reverses_and_releases() -> void:
	for ch in CHARS:
		var b = _body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		var st_b := _walk_st(-1.0, 0.0, 1.1)
		for i in 60:
			_step(X, st_b)
		check(X.dir_rev, "%s 뒤로 걸음 → 거꾸로" % ch)
		check(absf(X.dir_y) < 0.1, "%s 뒤로 가도 골반은 거의 그대로 (%f°)" % [ch, rad_to_deg(X.dir_y)])
		check(X.lean_p < 0.0, "%s 뒤로 걸을 때 윗몸 뒤로 (%f)" % [ch, X.lean_p])
		var idle := _st()
		for i in 90:
			_step(X, idle)
		check(not X.dir_rev and absf(X.dir_y) < 0.01 and absf(X.lean_p) < 0.01, "%s 서면 풀림" % ch)
		b.free()


# 달리면 윗몸이 앞으로 숙고, 서 있을 때와 윗몸 뼈 회전이 다름. 가속도 급정지 방향
func test_run_leans_forward() -> void:
	for ch in CHARS:
		var b = _body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		var run := _walk_st(1.0, 0.0, 1.1, true)
		for i in 60:
			_step(X, run)
		check(X.lean_p > 0.04 and X.lean_p <= deg_to_rad(8.0) + 1e-6, "%s 달리면 앞 숙임 0~8° (%f°)" % [ch, rad_to_deg(X.lean_p)])
		var brake := _walk_st(1.0, 0.0, 1.1, true)
		brake["accF"] = -30.0
		for i in 30:
			_step(X, brake)
		check(X.lean_p < 0.04, "%s 급정지엔 덜 숙임·뒤로 (%f°)" % [ch, rad_to_deg(X.lean_p)])
		b.free()


# 방향을 급히 꺾으면 윗몸이 새 방향으로 비틀리고 팔이 반동. 직진이면 없음
func test_direction_change_twist() -> void:
	var b = _body("hunter")
	var X = b.ext
	var run := _walk_st(1.0, 0.0, 1.1, true)
	for i in 30:
		_step(X, run)
	check(absf(X.turn_tw) < 0.01, "직진엔 비틀림 없음")
	var v := 4.5
	for i in 12:
		var a := float(i) * 0.12
		_step(X, _st({"walking": true, "hs": v, "walk": 1.1, "mvF": v, "vw": Vector2(cos(a), sin(a)) * v}))
	check(X.turn_tw > 0.03 and X.turn_tw <= K.EXT_TURN_MAX_RAD + 1e-6, "왼쪽으로 꺾으면 + 비틀림 (%f)" % X.turn_tw)
	b.free()


# 가산 층 끄기 (move_off) 면 코드·클립 결과와 같음 (서 있기에서는 켜도 같음)
func test_idle_unchanged_by_move_layer() -> void:
	var b = _body("tank")
	var X = b.ext
	var idle := _st()
	X.move_off = true
	for i in 10:
		_step(X, idle)
	var q0 := _gq(X.sk, "mixamorig_Spine2")
	var l0 := _gq(X.sk, "mixamorig_RightUpLeg")
	X.move_off = false
	for i in 10:
		_step(X, idle)
	check(rad_to_deg(q0.angle_to(_gq(X.sk, "mixamorig_Spine2"))) < 1.0, "서 있기 윗몸 같음")
	check(rad_to_deg(l0.angle_to(_gq(X.sk, "mixamorig_RightUpLeg"))) < 1.0, "서 있기 다리 같음")
	b.free()


# 팔 흔들림 폭: 같은 걸음 위상에서 클립 평균에서 벗어난 각이 빠르면 커지고 (최대 1.25 배), 느리면 작아짐 (최소 0.8 배)
func test_arm_swing_scales_with_speed() -> void:
	for ch in CHARS:
		var b = _body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		var ab: int = int(X.info.map.get("shoulder_R", -1))
		var dev := []
		for sp in [0.7, 1.0, 1.4]: # 달리기 클립 (속도 비 0.55 이상) 에서 속도만 바꿈
			var v: float = C.MOVE_SPEED * sp
			var st := _st({"walking": true, "hs": v, "walk": 0.3, "mvF": v, "vw": Vector2(v, 0.0)})
			for i in 30:
				_step(X, st)
			var cur: Quaternion = X.sk.get_bone_pose_rotation(ab)
			var key: String = ""
			for k in X.swing_means:
				if str(k).ends_with("RightArm"):
					key = str(k)
			dev.append(rad_to_deg(cur.angle_to(X.swing_means[key])) if key != "" else -1.0)
		check(dev[0] >= 0.0, "%s 평균 회전 캐시" % ch)
		check(dev[2] >= dev[1] - 0.01 or dev[1] <= 1.0, "%s 빠르면 팔 흔들림이 큼 (%s)" % [ch, dev])
		b.free()


# ---------- 일어나기 ----------

func test_getup_curves() -> void:
	var c0 := M.getup_curves(0.0)
	var c1 := M.getup_curves(1.0)
	check(c0.env == 0.0 and c1.env == 0.0, "일어나기 처음·끝은 가중치 0 (튐 없음)")
	var mx := 0.0
	var prev := 0.0
	for i in 101:
		var c := M.getup_curves(float(i) / 100.0)
		check(c.env >= 0.0 and c.env <= 1.0 and c.torso >= 0.0 and c.torso <= 1.0 and c.arm >= 0.0 and c.arm <= 1.0 and c.step >= 0.0 and c.step <= 1.0, "곡선 값 0~1 (u %d)" % i)
		mx = maxf(mx, c.env)
		if i > 0:
			check(absf(c.env - prev) < 0.12 and absf(c.arm) < 1.01, "곡선이 연속 (u %d)" % i)
		prev = c.env
	check(mx > 0.99, "가운데에서 최대 1")
	var a1 := M.getup_curves(0.3)
	var a2 := M.getup_curves(0.8)
	check(a1.arm > a2.arm, "손 짚고 (0.3) 밀어 놓음 (0.8) — 팔이 줄어듦")
	check(M.getup_curves(0.1).torso > M.getup_curves(0.7).torso, "윗몸이 일어나며 펴짐")


func test_getup_motor_weight_and_block() -> void:
	check(M.getup_motor_w(0.0) == 0.0 and M.getup_motor_w(0.05) == 0.0, "축 늘어진 몸엔 안 섞음")
	check(M.getup_motor_w(1.0) == 1.0 and M.getup_motor_w(0.5) >= 0.99, "돌아온 몸엔 전부")
	check(M.getup_motor_w(-1.0) == 1.0, "래그돌 없으면 1")
	var mid := M.getup_motor_w(0.3)
	check(mid > 0.0 and mid < 1.0, "모터가 돌아오는 도중엔 부분 (%f)" % mid)
	check(M.getup_motor_w(0.4) > M.getup_motor_w(0.2), "모터가 세질수록 섞임이 늚")
	check(not M.getup_blocked(_st()), "서 있으면 막히지 않음")
	check(M.getup_blocked(_st({"stunned": true})) and M.getup_blocked(_st({"act": {"move": "x"}})) and M.getup_blocked(_st({"air": true})), "경직·공격·공중이면 막힘")


# 경직이 풀려 웅크림 (recover) 이 시작되면 일어나기 타이머가 돌고, 끝나면 풀림. 다시 맞으면 끊김
func test_getup_starts_on_recover_and_ends() -> void:
	for ch in CHARS:
		var b = _body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		for i in 5:
			_step(X, _st())
		check(X.getup_t < 0.0, "%s 평소엔 일어나기 아님" % ch)
		_step(X, _st({"recover": 1.0}))
		check(X.getup_t >= 0.0 and X.getup_amp > 0.99, "%s 웅크림 시작 → 일어나기 시작 (amp %f)" % [ch, X.getup_amp])
		var any_w := 0.0
		for i in 30:
			_step(X, _st({"recover": maxf(0.0, 1.0 - i / 27.0)}))
			any_w = maxf(any_w, X.getup_w_last)
		check(any_w > 0.5, "%s 가중치가 올라감 (%f)" % [ch, any_w])
		for i in 60:
			_step(X, _st())
		check(X.getup_t < 0.0, "%s 0.7 초 뒤 끝" % ch)
		# 다시 경직이면 끊김
		_step(X, _st({"recover": 1.0}))
		check(X.getup_t >= 0.0, "%s 두 번째 시작" % ch)
		_step(X, _st({"stunned": true}))
		check(X.getup_t < 0.0, "%s 경직으로 끊김" % ch)
		# 가볍게 맞고 선 것 (recover 0.5) 은 약하게
		for i in 5:
			_step(X, _st())
		_step(X, _st({"recover": 0.5}))
		check(X.getup_amp < 0.9, "%s 가벼운 경직은 약하게 (%f)" % [ch, X.getup_amp])
		b.free()


# 일어나며 다리를 접어도 발은 땅에 그대로 (엉덩이 보정)
func test_getup_keeps_feet_on_ground() -> void:
	var b = _body("hook")
	var X = b.ext
	for i in 5:
		_step(X, _st())
	var rest := (X._feet_y() as float)
	X.getup_mark = 0.45
	for i in 4:
		_step(X, _st({"recover": 1.0}))
	check(X.getup_w_last > 0.9, "일어나기 켜짐 (%f)" % X.getup_w_last)
	check(absf(X._feet_y() - rest) < 0.04, "발 높이가 그대로 (%f → %f)" % [rest, X._feet_y()])
	X.getup_mark = 0.0
	b.free()


# 몸이 숨었다 (0.5초 이상 갱신 없음) 다시 보이면 (부활·판 시작) 낮은 세기로 일어나기
func test_getup_on_respawn() -> void:
	var b = _body("tank")
	var X = b.ext
	for i in 5:
		_step(X, _st())
	X.extra_t = Time.get_ticks_msec() * 0.001 - 2.0 # 2초 숨어 있었음
	X.sync(_st())
	check(X.getup_t >= 0.0 and X.getup_amp == K.EXT_GETUP_SPAWN_AMP, "숨었다 나타나면 일어나기 (amp %f)" % X.getup_amp)
	b.free()


# ---------- 무기 무게·흔들림 ----------

func test_weapon_table_and_spring_math() -> void:
	for ch in CHARS:
		check(K.EXT_WEAPON.has(ch) and not (K.EXT_WEAPON[ch] as Array).is_empty(), "%s 무기 흔들림 표" % ch)
		for e in K.EXT_WEAPON[ch]:
			check(e.has("joint") and float(e.k) > 0.0 and float(e.c) > 0.0 and float(e.max) > 0.0 and float(e.max) <= 0.4, "%s 표 값 (한계 0.4 이하)" % ch)
			check(float(e.c) / (2.0 * sqrt(float(e.k))) > 0.3 and float(e.c) / (2.0 * sqrt(float(e.k))) < 1.5, "%s 감쇠비가 적당 (진동하다 가라앉음)" % ch)
	# 용수철: 입력이 없으면 0 으로 가라앉고, 일정 입력이면 input/k 에 수렴
	var th := 0.4
	var om := 0.0
	for i in 240:
		var r := M.spring_step(th, om, 0.0, 1.0 / 60.0, 90.0, 9.0)
		th = r[0]
		om = r[1]
	check(absf(th) < 0.01, "용수철이 가라앉음 (%f)" % th)
	th = 0.0
	om = 0.0
	for i in 400:
		var r2 := M.spring_step(th, om, 90.0 * 0.2, 1.0 / 60.0, 90.0, 9.0)
		th = r2[0]
		om = r2[1]
	check(absf(th - 0.2) < 0.01, "일정 입력은 input/k 에 수렴 (%f)" % th)
	check(M.clamp_acc(1e6) == K.EXT_WEAPON_ACC_MAX and M.clamp_acc(NAN) == 0.0, "가속도 자르기")
	check(M.weapon_allowed(_st({"walking": true})) and not M.weapon_allowed(_st({"act": {"move": "x"}})) and not M.weapon_allowed(_st({"stunned": true})), "무기 흔들림 허용 상태")


# 몸을 앞뒤로 흔들면 (가속도) 무기 쥔 손뼈가 늦게 따라 흔들리고 (한계 안), 멈추면 가라앉음. 공격 중엔 꺼짐
func test_weapon_sways_with_motion_and_settles() -> void:
	for ch in CHARS:
		var b = _body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		var mx := 0.0
		var x := 0.0
		for i in 120:
			x = sin(float(i) / 60.0 * TAU * 1.5) * 0.15 # 1.5 Hz 앞뒤 (가속도 ≈ 13 m/s²)
			b.position = Vector3(x, 0, 0)
			_step(X, _st({"walking": true, "hs": 3.0, "walk": float(i) * 0.1, "mvF": 3.0, "vw": Vector2(3.0, 0.0)}))
			mx = maxf(mx, absf(X.weapon_pitch_last))
		var lim: float = float((K.EXT_WEAPON[ch] as Array)[0].max)
		check(mx > 0.02, "%s 흔들리면 무기가 늦게 처짐 (%f)" % [ch, mx])
		check(mx <= lim + 1e-5, "%s 한계 안 (%f ≤ %f)" % [ch, mx, lim])
		for i in 120:
			_step(X, _st())
		check(absf(X.weapon_pitch_last) < 0.01, "%s 멈추면 가라앉음 (%f)" % [ch, X.weapon_pitch_last])
		# 공격 중: 가중치 0 으로
		for i in 40:
			x = sin(float(i) / 60.0 * TAU * 1.5) * 0.15
			b.position = Vector3(x, 0, 0)
			_step(X, _st({"act": {"move": "x", "phase": "strike", "u": 0.5}}))
		check(X.weapon_w < 0.05, "%s 공격 중엔 꺼짐 (%f)" % [ch, X.weapon_w])
		b.free()


# 걷기 처짐 (droop): 탱크 해머는 달릴 때 앞으로 숙임 (손뼈 회전이 서 있을 때와 다름), 끄면 같음
func test_weapon_droop_changes_hand_pose() -> void:
	var b = _body("tank")
	var X = b.ext
	var hand := "mixamorig_RightHand"
	X.move_off = true
	for i in 20:
		_step(X, _st({"walking": true, "hs": C.MOVE_SPEED, "walk": 1.0, "mvF": C.MOVE_SPEED, "vw": Vector2(C.MOVE_SPEED, 0.0)}))
	var q_off := _gq(X.sk, hand)
	X.move_off = false
	for i in 60:
		_step(X, _st({"walking": true, "hs": C.MOVE_SPEED, "walk": 1.0, "mvF": C.MOVE_SPEED, "vw": Vector2(C.MOVE_SPEED, 0.0)}))
	var q_on := _gq(X.sk, hand)
	check(rad_to_deg(q_off.angle_to(q_on)) > 3.0, "달릴 때 해머 든 손이 처짐 (%f°)" % rad_to_deg(q_off.angle_to(q_on)))
	b.free()
