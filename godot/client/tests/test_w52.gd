# W52 모션 개선 5차: 크로스페이드 호 이어 슬러프·이음 자세 차이에 맞춘 페이드 길이 (닌자 대시 팔 튐), 낙하 뒤 래그돌 모터 복귀 완화, 래그돌 쉬기 전 기다림·블렌드, snap 오르는 속도 제한, 플래그 pop_fix
extends RefCounted

const M := preload("res://chars/ext_motion.gd")
const K := preload("res://chars/chars_config.gd")
const C := preload("res://core/config.gd")
const RM := preload("res://chars/ragdoll_math.gd")
const RagW := preload("res://chars/ragdoll.gd")
const Chars := preload("res://chars/chars.gd")
const Clips := preload("res://chars/ext_clips.gd")
const Ext := preload("res://chars/external.gd")
const Opts := preload("res://core/opts.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _reset() -> void:
	Opts.override = null
	K.set_flags(null)
	K.refresh()


# ---------- 슬러프 ----------

# 목표가 180° 근처를 지나가는 합성 시험: Quaternion.slerp 는 a·b 부호가 바뀌는 프레임에 호를 뒤집어 한 프레임에 크게 튀고, slerp_cont 는 이어짐
func test_slerp_cont_no_flip() -> void:
	var a := Quaternion.IDENTITY
	var prev_old := Quaternion.IDENTITY
	var prev_new := Quaternion.IDENTITY
	var ref := Quaternion(0, 0, 0, 0)
	var worst_old := 0.0
	var worst_new := 0.0
	var n := 40
	for i in n + 1:
		var ang := deg_to_rad(160.0 + 40.0 * float(i) / n) # 목표 회전 160° → 200° (a·b 부호가 중간에 바뀜)
		var b := Quaternion(Vector3.UP, ang)
		var ef := 0.5 # 페이드 한가운데 고정 — 목표만 움직임
		var o: Quaternion = a.slerp(b, ef)
		var r: Array = M.slerp_cont(a, b, ef, ref)
		ref = r[1]
		if i > 0:
			worst_old = maxf(worst_old, rad_to_deg(prev_old.angle_to(o)))
			worst_new = maxf(worst_new, rad_to_deg(prev_new.angle_to(r[0])))
		prev_old = o
		prev_new = r[0]
	check(worst_old > 100.0, "옛 slerp 는 호가 뒤집혀 한 프레임에 크게 튐 (%.1f°)" % worst_old)
	check(worst_new < 6.0, "slerp_cont 는 이어짐 (%.1f°)" % worst_new)


func test_slerp_cont_ends() -> void:
	var a := Quaternion(Vector3(1, 2, 3).normalized(), 0.8)
	var b := Quaternion(Vector3(-2, 1, 0.5).normalized(), 2.1)
	var r0: Array = M.slerp_cont(a, b, 0.0, Quaternion(0, 0, 0, 0))
	var r1: Array = M.slerp_cont(a, b, 1.0, Quaternion(0, 0, 0, 0))
	check((r0[0] as Quaternion).angle_to(a) < 1e-4, "ef 0 = 시작")
	check((r1[0] as Quaternion).angle_to(b) < 1e-4, "ef 1 = 목표")
	var same: Array = M.slerp_cont(a, a, 0.5, Quaternion(0, 0, 0, 0))
	check((same[0] as Quaternion).angle_to(a) < 1e-4 and is_finite((same[0] as Quaternion).w), "같은 사원수 (0 나눗셈 없음)")
	var neg: Array = M.slerp_cont(a, -a, 0.5, Quaternion(0, 0, 0, 0))
	check((neg[0] as Quaternion).angle_to(a) < 1e-4, "부호만 반대인 같은 회전")


func test_fade_len() -> void:
	var base: float = K.EXT_CLIP_FADE_S
	check(is_equal_approx(M.fade_len_for(base, 0.0), base) and is_equal_approx(M.fade_len_for(base, 60.0), base), "차이가 작으면 기본 길이")
	check(is_equal_approx(M.fade_len_for(base, base * K.EXT_FADE_ADAPT_DPS), base), "경계에서 기본 길이")
	var l172: float = M.fade_len_for(base, 172.0)
	check(l172 > base and absf(l172 - 172.0 / K.EXT_FADE_ADAPT_DPS) < 1e-5, "172° 차이는 비율대로 늘어남 (%.3f)" % l172)
	check(is_equal_approx(M.fade_len_for(base, 5000.0), K.EXT_FADE_ADAPT_MAX_S), "상한")
	check(M.fade_len_for(0.3, 10.0) == 0.3, "기본이 상한보다 길면 그대로")


# 실제 닌자 클립: 표창 끝 자세 (t 0.3) → 대시 타격 (t 0.3~0.4 를 한 타격 동안) 크로스페이드를 60Hz 로 재현. 오른팔이 한 표본에 튀는 정도
func _dash_sweep(adaptive: bool, cont: bool) -> float:
	var info = Ext.load_char("ninja")
	var cc: Dictionary = info.cfg.get("clips", {})
	var lib := Clips.load_lib(str(cc.get("file", "")))
	if not lib.has("star") or not lib.has("dash"):
		return -1.0
	var bone := "mixamorig_RightArm"
	var star: Dictionary = lib["star"]
	var dash: Dictionary = lib["dash"]
	var from: Quaternion = (star.anim as Animation).rotation_track_interpolate(int(star.rot[bone]), 0.3)
	var q0: Quaternion = (dash.anim as Animation).rotation_track_interpolate(int(dash.rot[bone]), 0.3)
	var flen: float = K.EXT_CLIP_FADE_S
	if adaptive:
		var mx := 0.0
		for bn in dash.rot:
			if star.rot.has(bn):
				var fa: Quaternion = (star.anim as Animation).rotation_track_interpolate(int(star.rot[bn]), 0.3)
				var qa: Quaternion = (dash.anim as Animation).rotation_track_interpolate(int(dash.rot[bn]), 0.3)
				mx = maxf(mx, rad_to_deg(fa.angle_to(qa)))
		flen = M.fade_len_for(flen, mx)
	var dt := 1.0 / 60.0
	var t := 0.0
	var ref := Quaternion(0, 0, 0, 0)
	var prev := from
	var worst := 0.0
	var u_total := 5.0 * dt # 타격 길이 (서버 설계값, 약 0.08초)
	var first := true
	while t < 0.5:
		t += dt
		var u := clampf(t / u_total, 0.0, 1.0)
		var tt := 0.3 + u * 0.1 if t < u_total else 0.4 + (t - u_total) / 0.45 * 0.4 # 타격 0.3~0.4, 이어 회복 0.4~0.8
		var q: Quaternion = (dash.anim as Animation).rotation_track_interpolate(int(dash.rot[bone]), tt)
		var fi := minf(1.0, t / flen)
		var ef := fi * fi * (3.0 - 2.0 * fi)
		var out: Quaternion
		if fi < 1.0:
			if cont:
				var r: Array = M.slerp_cont(from, q, ef, ref)
				out = r[0]
				ref = r[1]
			else:
				out = from.slerp(q, ef)
		else:
			out = q
		if not first:
			worst = maxf(worst, rad_to_deg(prev.angle_to(out)))
		first = false
		prev = out
	var _unused := q0
	return worst


func test_ninja_dash_arm() -> void:
	var old := _dash_sweep(false, false)
	var fixed := _dash_sweep(true, true)
	if old < 0.0:
		check(false, "닌자 클립 (star·dash) 을 못 읽음")
		return
	check(old > 100.0, "옛 페이드는 대시 오른팔이 한 표본에 100° 넘게 튐 (%.1f°)" % old)
	check(fixed < 75.0, "새 페이드는 75° 안 (%.1f°)" % fixed)
	check(fixed < old * 0.6, "새 페이드는 옛 값의 6할 이하 (%.1f° / %.1f°)" % [fixed, old])


# ---------- 래그돌 모터 복귀 ----------

func test_motor_after_fall() -> void:
	_reset()
	var s0 := RM.motor({"falling": true, "act": null})
	check(s0.motor == C.RAGDOLL_FALL_MOTOR, "낙하 중에는 힘 빠짐")
	# 낙하가 끝난 직후부터 서서히: 한 프레임 (60Hz) 에 오르는 양이 작음 (예전: 0.002 → 1.6 한 프레임)
	var prev: float = s0.motor
	var worst := 0.0
	var t := 0.0
	while t < K.RAGDOLL_FALL_RECOVER_S - 0.001:
		var r := RM.motor({"falling": false, "sinceFall": t, "act": "wind"})
		worst = maxf(worst, float(r.motor) - prev)
		check(float(r.motor) >= prev - 1e-9, "모터는 오르기만 함 (%.2f초)" % t)
		prev = r.motor
		t += 1.0 / 60.0
	check(worst < 0.2, "한 프레임에 오르는 양이 작음 (%.3f)" % worst)
	check(prev > 0.9, "거의 다 돌아옴 (%.2f)" % prev)
	check(RM.motor({"falling": false, "sinceFall": K.RAGDOLL_FALL_RECOVER_S + 0.01, "act": "wind"}).motor == C.RAGDOLL_MOTOR_ATTACK, "끝나면 공격 모터")
	var early := RM.motor({"falling": false, "sinceFall": 0.0, "act": "wind"})
	check(early.motor < 0.05 and early.snap == 0.0, "낙하 끝난 직후 모터·snap 은 아직 힘 빠진 값 (%.3f)" % early.motor)
	# sinceFall 이 없으면 (예전 호출) 그대로
	var old := RM.motor({"falling": false, "act": "wind"})
	check(old.motor == C.RAGDOLL_MOTOR_ATTACK and old.snap == C.RAGDOLL_ATTACK_SNAP, "sinceFall 없으면 예전 그대로")
	# 끄면 예전
	K.set_flags({"pop_fix": false})
	var off := RM.motor({"falling": false, "sinceFall": 0.0, "act": "wind"})
	check(off.motor == C.RAGDOLL_MOTOR_ATTACK, "pop_fix 끄면 낙하 직후도 한 번에 (예전)")
	_reset()
	# 낙하가 길어도 INF·NaN 은 거부
	var bad := RM.motor({"falling": false, "sinceFall": INF, "act": null})
	check(bad.motor == 1.0, "sinceFall 무한대 = 평소")


# ---------- 래그돌 쉬기·snap ----------

func _rag_body(root: Window, w):
	var b = Chars.make_body("tank", Color(0.5, 0.5, 0.9))
	b.rag_test = true
	root.add_child(b)
	var p := {"id": -52, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.4}
	b.pose(p, 0.0)
	return [b, p]


func _free_rag_world(w, b, root: Window) -> void:
	root.remove_child(b)
	b.free()
	root.remove_child(w)
	w.free()
	RagW._inst = null


func test_ragdoll_sleep_gate_and_blend() -> void:
	_reset()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var w = RagW.new()
	w.name = "TfRagdollsW52"
	root.add_child(w)
	RagW._inst = w
	var bp = _rag_body(root, w)
	var b = bp[0]
	var p: Dictionary = bp[1]
	check(w.has(b), "래그돌 켬")
	var rag: Dictionary = w.rags.get(b, {})
	if rag.is_empty():
		_free_rag_world(w, b, root)
		return
	# 물리 몸 하나를 목표에서 멀리 (약 120° 비틂) 돌려 둠 — 관절 한계에 걸린 몸을 흉내
	var sg: Dictionary = rag.segs[3]
	var tq: Quaternion = sg.tq
	var twisted := Basis(tq * Quaternion(Vector3.RIGHT, deg_to_rad(120.0)))
	PhysicsServer3D.body_set_state(sg.body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(twisted, Vector3.ZERO))
	w.apply(b) # sg.wq 갱신
	check(w._pose_dev(rag) > 100.0, "물리 자세가 목표에서 멂 (%.1f°)" % w._pose_dev(rag))
	# 모터가 다 센 채 쉬기 시간이 지났어도 목표에서 멀면 아직 안 쉼
	rag.calm_at = Motion_now_ms() - (K.RAGDOLL_SLEEP_MS + 50.0)
	b.pose(p, 8.0)
	check(rag.awake, "목표에서 멀면 쉬지 않고 기다림")
	# 기다림 상한이 지나면 쉬되 블렌드 (물리 마지막 자세 → 목표)
	rag.calm_at = Motion_now_ms() - (K.RAGDOLL_SLEEP_MS + K.RAGDOLL_SLEEP_WAIT_MS + 50.0)
	PhysicsServer3D.body_set_state(sg.body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(twisted, Vector3.ZERO))
	w.apply(b)
	b.pose(p, 9.0)
	check(not rag.awake, "기다림 상한 뒤엔 쉼")
	check(float(rag.get("blend_len", 0.0)) > 0.04 and float(rag.blend_len) <= K.RAGDOLL_SLEEP_BLEND_MAX_S + 1e-6, "쉬면서 블렌드가 걸림 (%.3f초)" % float(rag.get("blend_len", 0.0)))
	check(float(rag.get("sleep_dev", 0.0)) > 100.0, "쉬는 순간 차이를 잼 (%.1f°)" % float(rag.get("sleep_dev", 0.0)))
	# 블렌드가 끝나면 꺼짐
	rag.blend_t0 = Motion_now_s() - 1.0
	w.apply(b)
	check(float(rag.blend_len) == 0.0, "블렌드가 끝나면 꺼짐")
	_free_rag_world(w, b, root)
	# 끄면 예전처럼 바로 쉼
	K.set_flags({"pop_fix": false})
	w = RagW.new()
	w.name = "TfRagdollsW52b"
	root.add_child(w)
	RagW._inst = w
	bp = _rag_body(root, w)
	b = bp[0]
	p = bp[1]
	rag = w.rags.get(b, {})
	if not rag.is_empty():
		sg = rag.segs[3]
		PhysicsServer3D.body_set_state(sg.body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(sg.tq * Quaternion(Vector3.RIGHT, deg_to_rad(120.0))), Vector3.ZERO))
		w.apply(b)
		rag.calm_at = Motion_now_ms() - (K.RAGDOLL_SLEEP_MS + 50.0)
		b.pose(p, 8.0)
		check(not rag.awake and float(rag.get("blend_len", 0.0)) == 0.0, "pop_fix 끄면 목표에서 멀어도 바로 쉼 (블렌드 없음)")
	_free_rag_world(w, b, root)
	_reset()


func test_ragdoll_snap_rise_limited() -> void:
	_reset()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var w = RagW.new()
	w.name = "TfRagdollsW52c"
	root.add_child(w)
	RagW._inst = w
	var bp = _rag_body(root, w)
	var b = bp[0]
	var rag: Dictionary = w.rags.get(b, {})
	if rag.is_empty():
		_free_rag_world(w, b, root)
		return
	var dt := 1.0 / 60.0
	# 목표 가까이: 예전처럼 한 번에 공격 snap
	w.capture(b, {"act": "wind"}, null, dt)
	check(is_equal_approx(rag.snap, C.RAGDOLL_ATTACK_SNAP), "가까우면 snap 즉시 (%.2f)" % rag.snap)
	# 목표에서 멀 때: 0 에서 시작해 천천히
	rag.snap_eff = 0.0
	rag.snap = 0.0
	var sg: Dictionary = rag.segs[3]
	PhysicsServer3D.body_set_state(sg.body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(sg.tq * Quaternion(Vector3.RIGHT, deg_to_rad(120.0))), Vector3.ZERO))
	w.apply(b)
	w.restore(b)
	w.capture(b, {"act": "wind"}, null, dt)
	check(rag.snap <= K.RAGDOLL_SNAP_RISE_PER_S * dt + 1e-6 and rag.snap > 0.0, "멀면 snap 이 천천히 오름 (%.3f)" % rag.snap)
	w.capture(b, {"act": null}, null, dt)
	check(rag.snap == 0.0, "snap 내리는 건 바로")
	_free_rag_world(w, b, root)
	_reset()


# ---------- 플래그 ----------

func test_pop_fix_flag() -> void:
	_reset()
	check(K.EXT_MOTION_FLAGS.has("pop_fix") and K.EXT_MOTION_LABELS.has("pop_fix"), "pop_fix 플래그·글")
	check(K.flag("pop_fix"), "기본 켬")
	check(K.EXT_MOTION_PRESETS["new"].pop_fix and not K.EXT_MOTION_PRESETS["old"].pop_fix and not K.EXT_MOTION_PRESETS["min"].pop_fix, "프리셋: 새 켬, 옛·최소 끔")
	Opts.override = ["--no-pop-fix"]
	K.refresh()
	check(not K.flag("pop_fix"), "--no-pop-fix 로 끔")
	_reset()
	K.set_flags({"pop_fix": false})
	check(not K.flag("pop_fix"), "설정으로 끔")
	_reset()
	var src := FileAccess.get_file_as_string("res://ui/settings.gd")
	check(src.contains("\"pop_fix\"]"), "설정 창 모션 탭 표에 pop_fix")


func Motion_now_ms() -> float:
	return M.now_ms()


func Motion_now_s() -> float:
	return M.now_s()
