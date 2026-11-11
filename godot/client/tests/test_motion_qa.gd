# W44 모션 QA: 검출기 (core/motion_qa_math.gd) 를 합성 뼈 열로 시험 + 새 모델 4명 합성 시나리오 (서기·걷기·달리기·옆·뒤·공격·점프·착지·일어나기) 의 팝 수 상한 (회귀)
extends RefCounted

const M := preload("res://core/motion_qa_math.gd")
const Body := preload("res://chars/body.gd")
const Ext := preload("res://chars/external.gd")
const Motion_ := preload("res://chars/ext_motion.gd")
const C := preload("res://core/config.gd")

var errors: Array = []
const CHARS := ["ninja", "tank", "hunter", "hook"]
# 합성 시나리오의 팝 상한 (2026-11-11 W44 고친 뒤 값 + 여유). 모션 변경이 이걸 넘기면 새 튐이 생긴 것 — tools/motion_qa 로 어디인지 찾을 것
const POP_CAP_BODY := {"ninja": 36, "tank": 41, "hunter": 50, "hook": 44} # 몸통·팔다리·손발머리 (천 제외) 전체 (달리기 다리 포함)
const POP_CAP_CALM := {"ninja": 8, "tank": 16, "hunter": 13, "hook": 13} # 달리기 빼고 (서기·걷기·옆·뒤·공격·점프·착지·일어나기)
const POP_CAP_CLOTH := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


static func _rz(deg: float) -> Quaternion:
	return Quaternion(Vector3.BACK, deg_to_rad(deg))


# ---------- 순수 검출기 ----------

func test_rotation_math() -> void:
	check(absf(M.ang(Quaternion.IDENTITY, _rz(30.0)) - 30.0) < 1e-3, "각 30°")
	check(absf(M.ang(Quaternion.IDENTITY, Quaternion(0, 0, -1e-9, -1)) - 0.0) < 1e-3, "q 와 -q 는 같은 회전")
	check(absf(M.ang(_rz(10.0), _rz(-10.0)) - 20.0) < 1e-3, "부호 있는 두 각 사이")
	var v := M.rotvec(Quaternion.IDENTITY, _rz(40.0))
	check(absf(v.z - 40.0) < 1e-3 and absf(v.x) < 1e-3, "회전 벡터 = 축 × 각 (%s)" % str(v))
	check(absf(M.ang(_rz(0.0), _rz(0.01)) - 0.01) < 1e-4, "아주 작은 각도 정확 (%f)" % M.ang(_rz(0.0), _rz(0.01)))
	check(absf(M.twist_deg(Quaternion(Vector3.UP, deg_to_rad(50.0)), Vector3.UP) - 50.0) < 1e-4, "축 둘레 비틀림 50°")
	check(absf(M.twist_deg(Quaternion(Vector3.RIGHT, deg_to_rad(50.0)), Vector3.UP)) < 1e-4, "다른 축 회전은 비틀림 0")


func test_bone_classes() -> void:
	check(M.bone_class("mixamorig_Hips") == "torso" and M.bone_class("mixamorig_Spine2") == "torso", "몸통")
	check(M.bone_class("mixamorig_LeftArm") == "limb" and M.bone_class("mixamorig_RightUpLeg") == "limb" and M.bone_class("mixamorig_LeftShoulder") == "limb", "팔다리")
	check(M.bone_class("mixamorig_Head") == "end" and M.bone_class("mixamorig_LeftFoot") == "end" and M.bone_class("mixamorig_RightHand") == "end", "손·발·머리")
	check(M.bone_class("mixamorig_LeftHandIndex1") == "skip" and M.bone_class("mixamorig_HeadTop_End") == "skip", "손가락·끝 뼈는 안 봄")
	check(M.bone_class("mixamorig_Cape1_2") == "cloth" and M.bone_class("mixamorig_Scarf1") == "cloth" and M.bone_class("mixamorig_Tabard2_1") == "cloth" and M.bone_class("mixamorig_Skirt3_3") == "cloth", "천")
	check(M.pop_thr("end") > M.pop_thr("torso"), "손발 임계가 더 큼")


func test_pop_detector() -> void:
	var d := M.PopDet.new(35.0, 0.5)
	var pops := 0
	for i in 60: # 매끈한 돌기 (프레임당 3°) — 팝 없음
		var r: Dictionary = d.feed(_rz(3.0 * i))
		pops += 1 if r.pop else 0
	check(pops == 0, "매끈한 회전은 팝 0 (%d)" % pops)
	var d2 := M.PopDet.new(35.0, 0.5)
	pops = 0
	var soft := 0
	var worst := 0.0
	for i in 40:
		var deg := 1.0 * i + (60.0 if i >= 20 else 0.0) # 20번째에 60° 순간이동
		var r: Dictionary = d2.feed(_rz(deg))
		pops += 1 if r.pop else 0
		soft += 1 if r.soft else 0
		worst = maxf(worst, float(r.w))
	check(pops == 1 and soft == 1, "60° 점프 하나 = 팝 정확히 1 (%d, 약한 %d)" % [pops, soft])
	check(absf(worst - 61.0) < 0.01, "최악 각속도 61° (%f)" % worst)
	var d3 := M.PopDet.new(35.0, 0.5) # 연속으로 임계 위 (빠른 휘두름) 는 한 번만 셈 — 위로 올라가는 모서리
	pops = 0
	for i in 10:
		pops += 1 if d3.feed(_rz(50.0 * i)).pop else 0
	check(pops == 1, "계속 빠른 회전은 처음 급가속 한 번만 (%d)" % pops)
	var d6 := M.PopDet.new(35.0, 0.5) # 매끈히 빨라지는 (달리기 다리) 40° 회전은 팝 아님
	pops = 0
	var fast := 0
	for i in 16:
		var r6: Dictionary = d6.feed(_rz(5.0 * i * (i + 1) / 2.0 * 0.5 + (0.0)))
		pops += 1 if r6.pop else 0
		fast += 1 if r6.fast else 0
	check(pops == 0 and fast >= 1, "매끈한 가속은 팝 아님·'빠름' 만 (%d, %d)" % [pops, fast])
	var d4 := M.PopDet.new(35.0, 0.5) # 간격 보정: 2배 간격 (30Hz) 에서 40° 는 표본당 20°
	d4.feed(_rz(0.0))
	check(not d4.feed(_rz(40.0), 0.5).pop, "간격 환산 (실제 간격이 2배면 각속도 절반)")
	var d5 := M.PopDet.new(35.0, 0.5)
	d5.feed(_rz(0.0))
	d5.reset()
	check(not d5.feed(_rz(170.0)).pop, "리셋 뒤 첫 표본은 팝 아님 (순간이동·부활)")


func test_jitter_detector() -> void:
	var j := M.JitDet.new()
	var bad := 0
	var wins := 0
	for i in 200: # ±0.6° 번갈아 (떨림)
		var w: Dictionary = j.feed(_rz(0.6 if i % 2 == 0 else -0.6))
		if not w.is_empty():
			wins += 1
			bad += 1 if M.jitter_bad(w) else 0
	check(wins >= 5 and bad == wins, "번갈아 떠는 뼈 = 떨림 창 전부 (%d/%d)" % [bad, wins])
	var j2 := M.JitDet.new()
	bad = 0
	wins = 0
	for i in 200: # 숨쉬기 같은 느린 사인 (2°)
		var w2: Dictionary = j2.feed(_rz(2.0 * sin(TAU * float(i) / 180.0)))
		if not w2.is_empty():
			wins += 1
			bad += 1 if M.jitter_bad(w2) else 0
	check(wins >= 5 and bad == 0, "느린 사인은 떨림 아님 (%d/%d)" % [bad, wins])
	var j3 := M.JitDet.new()
	var big := 0
	for i in 100: # 같은 방향으로 일정하게 돎 (가속 0) — 떨림 아님
		var w3: Dictionary = j3.feed(_rz(1.5 * i))
		if not w3.is_empty() and M.jitter_bad(w3):
			big += 1
	check(big == 0, "일정 속도 회전은 떨림 아님")


func test_slide_detector() -> void:
	# 발 고정 (땅에 닿은 채 몸만 감) → 미끄러짐 0
	var s := M.SlideDet.new()
	var out := {}
	for i in 40:
		var r: Dictionary = s.feed(Vector2(1.0, 1.0), 0.0, Vector2(0.05 * i, 0.0))
		if not r.is_empty():
			out = r
	var fin: Dictionary = s.feed(Vector2(1.0, 1.0), 0.2, Vector2(2.0, 0.0)) # 발이 들림 → 디딤 끝
	if not fin.is_empty():
		out = fin
	check(not out.is_empty() and float(out.ratio) < 0.01 and float(out.body) > 1.5, "발 고정 = 비 0 (%s)" % str(out))
	# 발이 몸과 같이 감 (스케이팅) → 비 1
	var s2 := M.SlideDet.new()
	var out2 := {}
	for i in 40:
		var r2: Dictionary = s2.feed(Vector2(0.05 * i, 0.0), 0.0, Vector2(0.05 * i, 0.0))
		if not r2.is_empty():
			out2 = r2
	var f2: Dictionary = s2.feed(Vector2(2.0, 0.0), 0.2, Vector2(2.0, 0.0))
	if not f2.is_empty():
		out2 = f2
	check(not out2.is_empty() and absf(float(out2.ratio) - 1.0) < 0.05, "발이 몸과 같이 = 비 1 (%s)" % str(out2))
	# 발이 높이 들려 있으면 디딤 아님
	var s3 := M.SlideDet.new()
	var any := false
	for i in 40:
		if not s3.feed(Vector2(0.05 * i, 0.0), 0.1, Vector2(0.05 * i, 0.0)).is_empty():
			any = true
	check(not any and s3.flush().is_empty(), "들린 발은 디딤 아님")
	# 너무 짧은 닿음 (2표본) 은 안 셈
	var s4 := M.SlideDet.new()
	s4.feed(Vector2.ZERO, 0.0, Vector2.ZERO)
	s4.feed(Vector2.ZERO, 0.0, Vector2.ZERO)
	check(s4.feed(Vector2.ZERO, 0.2, Vector2.ZERO).is_empty(), "닿음 2표본은 디딤 아님")


func test_penetration_and_stretch() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(0, 1, 0)
	check(absf(M.capsule_depth(Vector3(0.05, 0.5, 0), a, b, 0.1) - 0.05) < 1e-6, "캡슐 안 깊이 0.05")
	check(M.capsule_depth(Vector3(0.2, 0.5, 0), a, b, 0.1) == 0.0, "밖은 0")
	check(absf(M.capsule_depth(Vector3(0, 1.05, 0), a, b, 0.1) - 0.05) < 1e-6, "끝 반구 안")
	check(M.capsule_depth(Vector3(0, 0.02, 0), a, a, 0.1) > 0.0, "길이 0 캡슐도 안 깨짐")
	check(absf(M.stretch_ratio(Vector3.ZERO, Vector3(0, 0, 3), 1.0) - 3.0) < 1e-9, "신축 비 3")
	check(M.stretch_ratio(Vector3.ZERO, Vector3.ZERO, 0.0) == 0.0, "쉬는 길이 0 안 터짐")


func test_limits() -> void:
	var ax := M.hinge_axis([Vector3(0, 0, 40), Vector3(0, 0, 80), Vector3(1, 0, 60)])
	check(ax.z > 0.99, "경첩 축 = 굽힘 방향 평균 (%s)" % str(ax))
	var f := M.hinge_flex(Vector3(0, 0, 90), ax)
	check(absf(float(f.flex) - 90.0) < 3.0 and float(f.off) < 3.0, "굽힘 90°·옆 꺾임 0")
	check(M.limit_flags(60.0, 0.0, 0.0).is_empty(), "정상 굽힘은 위반 아님")
	check(M.limit_flags(-40.0, 0.0, 0.0)[0].kind == "rev", "반대 굽힘")
	check(M.limit_flags(170.0, 0.0, 0.0)[0].kind == "over", "과굽힘")
	check(M.limit_flags(0.0, -80.0, 0.0)[0].kind == "neck", "목 비틂 (음수도)")
	check(M.limit_flags(0.0, 30.0, 0.0).is_empty(), "목 30° 는 정상")
	check(M.limit_flags(0.0, 0.0, 95.0)[0].kind == "spine", "척추 누적")


# ---------- 새 모델 합성 시나리오 (회귀) ----------

func _st(over := {}) -> Dictionary:
	var st := {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "emote": -1, "victory": -1.0, "hit": null, "act": null,
		"tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "dizzy": 0.0, "whirl": -1.0, "glide": false,
		"accF": 0.0, "accS": 0.0, "mvF": 0.0, "mvS": 0.0, "vw": Vector2.ZERO}
	st.merge(over, true)
	return st


# 시나리오: [상태 (딕셔너리), 프레임 수] 목록. 걷는 박자·시계는 호출 쪽이 흘림
func _scenario(ch: String, cc: Dictionary) -> Array:
	var run: float = C.MOVE_SPEED
	var seq := []
	seq.append([_st(), 60])
	seq.append([_st({"walking": true, "hs": run * 0.5, "mvF": run * 0.5, "vw": Vector2(run * 0.5, 0)}), 60])
	seq.append([_st({"walking": true, "hs": run, "mvF": run, "vw": Vector2(run, 0), "accF": 8.0}), 60])
	seq.append([_st({"walking": true, "hs": run, "mvS": run, "vw": Vector2(0, run)}), 40])
	seq.append([_st({"walking": true, "hs": run * 0.6, "mvF": -run * 0.6, "vw": Vector2(-run * 0.6, 0)}), 60])
	seq.append([_st({"walking": true, "hs": run * 0.6, "mvF": run * 0.4, "mvS": run * 0.4, "vw": Vector2(run * 0.4, run * 0.4)}), 40])
	seq.append([_st(), 40])
	seq.append([_st({"air": true, "vz": 6.0}), 12])
	seq.append([_st({"air": true, "vz": -4.0}), 20])
	seq.append([_st({"land": 0.8}), 14])
	seq.append([_st(), 30])
	for mv in (cc.get("moves", {}) as Dictionary):
		for ph in [["wind", 9], ["strike", 6], ["rec", 18]]:
			seq.append([_st({"act": {"move": mv, "phase": ph[0], "u": 0.5, "air": false}}), ph[1]])
		seq.append([_st(), 40])
	seq.append([_st({"recover": 0.8}), 8])
	seq.append([_st(), 60])
	return seq


# 한 캐릭터의 시나리오를 돌려 뼈 회전 팝 (표본 = 매 프레임 = 60Hz) 수: [몸, 천]
var verbose := OS.get_environment("TF_QA_VERBOSE") != ""


func _run_scenario(ch: String) -> Array:
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	var X = b.ext
	var sk: Skeleton3D = X.sk
	var cc: Dictionary = X.info.cfg.get("clips", {})
	var vt := [100.0]
	Motion_.clock = func(): return vt[0]
	var ids := []
	var dets := []
	var clothish := []
	for i in sk.get_bone_count():
		var c := M.bone_class(sk.get_bone_name(i))
		if c == "skip":
			continue
		ids.append(i)
		dets.append(M.PopDet.new(M.pop_thr(c), M.POP_SOFT_K))
		clothish.append(c == "cloth")
	var pops := [0, 0, 0]
	var phase := 0.0
	var frames := 0
	for step in _scenario(ch, cc):
		var st: Dictionary = step[0]
		for k in int(step[1]):
			vt[0] += 1.0 / 60.0
			if bool(st.walking):
				phase += float(st.hs) * C.ANIM_WALK_FREQ / 60.0
			st["walk"] = phase
			st["t"] = vt[0]
			if st.act != null:
				st.act["u"] = float(k) / maxf(1.0, float(step[1]) - 1.0)
			X.sync(st)
			frames += 1
			if frames <= 2:
				for d in dets:
					d.reset()
			for i in ids.size():
				var r: Dictionary = dets[i].feed(sk.get_bone_pose_rotation(ids[i]))
				if r.pop and frames > 2:
					pops[1 if clothish[i] else 0] += 1
					if not clothish[i] and not (bool(st.walking) and float(st.hs) >= C.MOVE_SPEED * 0.9):
						pops[2] += 1
					if verbose:
						print("      pop %s f%d %s %.1f° · %s %s" % [ch, frames, sk.get_bone_name(ids[i]), r.w, str(st.act.move if st.act != null else ("walk" if st.walking else "-")), str(X.cur_clip)])
	Motion_.clock = Callable()
	b.free()
	return pops


func test_scenario_pop_caps() -> void:
	for ch in CHARS:
		var p := _run_scenario(ch)
		check(int(p[0]) <= int(POP_CAP_BODY[ch]), "%s 합성 시나리오 몸 팝 %d > 상한 %d" % [ch, p[0], POP_CAP_BODY[ch]])
		check(int(p[2]) <= int(POP_CAP_CALM[ch]), "%s 합성 시나리오 (달리기 뺀) 몸 팝 %d > 상한 %d" % [ch, p[2], POP_CAP_CALM[ch]])
		check(int(p[1]) <= POP_CAP_CLOTH, "%s 합성 시나리오 천 팝 %d > 상한 %d" % [ch, p[1], POP_CAP_CLOTH])
		print("   [모션QA 합성] %s 팝: 몸 %d (달리기 뺀 %d) · 천 %d" % [ch, p[0], p[2], p[1]])
