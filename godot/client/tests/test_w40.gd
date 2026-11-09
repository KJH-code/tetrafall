# W40 모션 개선 2차 (Mixamo 없이): 천 뼈 (사냥꾼 망토·탱크 등 천·갈고리 코트 자락), 시선·머리 추적, 숨쉬기, 착지, 맞음 방향별 반응 (chars/ext_motion.gd·external.gd)
extends RefCounted

const Body := preload("res://chars/body.gd")
const Ext := preload("res://chars/external.gd")
const M := preload("res://chars/ext_motion.gd")
const K := preload("res://chars/chars_config.gd")
const C := preload("res://core/config.gd")
const RagW := preload("res://chars/ragdoll.gd")

var errors: Array = []

# 캐릭터 → [사슬 수, 뼈 이름 앞] (assets/models/ext/<id>.json cloth)
const CLOTH := {"hunter": [3, "Cape"], "tank": [2, "Tabard"], "hook": [3, "Skirt"]}


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
		"tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "dizzy": 0.0, "whirl": -1.0, "glide": false}
	st.merge(over, true)
	return st


# 한 걸음 (1/60 초) 으로 sync: 가산 층·천이 쓰는 실제 시계를 그만큼 전으로
func _step(X, st: Dictionary) -> void:
	var now := Time.get_ticks_msec() * 0.001
	X.cloth_t = now - 1.0 / 60.0
	X.extra_t = now - 1.0 / 60.0
	X.last_t = now - 1.0 / 60.0
	X.sync(st)


static func _gpos(sk: Skeleton3D, nm: String) -> Transform3D:
	var b := sk.find_bone(nm)
	var t := Transform3D.IDENTITY
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t


# ---------- 천 뼈 ----------

# 세 캐릭터: 뼈 수 (65 + 사슬 × 3), 사슬마다 뼈 3개, 판 LOD·stage 모두 새 뼈에 가중치가 있음, 같은 이름·같은 순서 (애니메이션 클립 뼈 번호 호환)
func test_cloth_bones_in_models() -> void:
	for ch in CLOTH:
		var info = Ext.load_char(ch)
		check(info != null, "%s 외부 모델" % ch)
		if info == null:
			continue
		var n: int = CLOTH[ch][0]
		var pre: String = CLOTH[ch][1]
		var model: Node = (info.scene as PackedScene).instantiate()
		var sk: Skeleton3D = model.get_node_or_null(info.sk_path) as Skeleton3D
		check(sk != null and sk.get_bone_count() == 65 + n * 3, "%s 뼈 %d 개 (65 + %d x 3)" % [ch, sk.get_bone_count() if sk else -1, n])
		for k in n:
			for i in 3:
				check(sk.find_bone("mixamorig_%s%d_%d" % [pre, k + 1, i + 1]) >= 0, "%s 천 뼈 %s%d_%d" % [ch, pre, k + 1, i + 1])
		# 기존 65 뼈 번호가 그대로 (새 뼈는 뒤에 붙음)
		check(sk.find_bone("mixamorig_Hips") == 0, "%s Hips 가 0번" % ch)
		# 모든 몸 메시 (stage + LOD) 가 새 뼈를 씀
		var lods := 0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (mi as MeshInstance3D).mesh
			if m == null or not String(mi.name).contains("_lod"):
				continue
			var used := false
			for si in m.get_surface_count():
				var arr: Array = m.surface_get_arrays(si)
				var bones = arr[Mesh.ARRAY_BONES]
				var wts = arr[Mesh.ARRAY_WEIGHTS]
				if bones is PackedInt32Array and wts is PackedFloat32Array:
					for q in bones.size():
						if bones[q] >= 65 and wts[q] > 0.01:
							used = true
							break
			lods += 1
			check(used, "%s %s 가 천 뼈 가중치를 가짐" % [ch, mi.name])
		check(lods >= 4, "%s stage + 판 LOD 3 = 메시 4개 이상 (%d)" % [ch, lods])
		model.free()


# 달리면 사슬이 뒤로 날리고 길이는 그대로, 서면 쉬는 모양 쪽으로 돌아옴
func test_cloth_chains_run_and_settle() -> void:
	for ch in CLOTH:
		var b = _body(ch)
		if b.ext == null:
			b.free()
			continue
		var X = b.ext
		check(X.cloths.size() == CLOTH[ch][0], "%s 천 사슬 %d 개 (cfg.cloth)" % [ch, X.cloths.size()])
		var holder := Node3D.new()
		holder.add_child(b)
		for i in 100:
			holder.position.x = 6.0 * (i / 60.0)
			_step(X, _st())
		var W: Transform3D = RagW.glob(X.sk)
		var scl: float = W.basis.get_scale().x
		var worst := 0.0
		var lagged := 0
		for cl in X.cloths:
			check(cl.bones.size() == 3, "%s 사슬 뼈 3개" % ch)
			if cl.pts[0].x - cl.pts[cl.pts.size() - 1].x > 0.01:
				lagged += 1
			for i in range(1, cl.pts.size()):
				worst = maxf(worst, absf((cl.pts[i] - cl.pts[i - 1]).length() / (cl.rest_len[i - 1] * scl) - 1.0))
		check(lagged >= 1, "%s 달리면 천 끝이 뒤로 처짐 (%d 사슬)" % [ch, lagged])
		check(worst < 0.04, "%s 사슬 길이 유지 (%.1f%%)" % [ch, worst * 100.0])
		# 서서 1.5초: 끝 점이 쉬는 자리 (목표) 근처로
		for i in 90:
			_step(X, _st())
		var cl0 = X.cloths[0]
		var tipd: float = (cl0.pts[cl0.pts.size() - 1] - cl0.pts[0]).length()
		var rl := 0.0
		for l in cl0.rest_len:
			rl += l
		check(tipd > rl * scl * 0.7, "%s 서면 늘어짐 (끝까지 %.2f m)" % [ch, tipd])
		holder.free()


# 몸 앞쪽 한계: 쉬는 자리보다 앞으로 (fwd) 못 나옴 (등 뒤 천이 몸을 뚫고 오지 않음) — 급정지에서도
func test_cloth_forward_limit() -> void:
	var b = _body("tank")
	if b.ext == null:
		b.free()
		return
	var X = b.ext
	var holder := Node3D.new()
	holder.add_child(b)
	for i in 60:
		holder.position.x = 8.0 * (i / 60.0)
		_step(X, _st())
	for i in 20: # 급정지: 천은 관성으로 앞으로 쏠림
		_step(X, _st())
		var cl = X.cloths[0]
		var pf: Vector3 = (RagW.glob(X.sk).basis * Vector3.RIGHT).normalized()
		var tip: Vector3 = cl.pts[cl.pts.size() - 1]
		var tgt_ref: Vector3 = cl.pts[0]
		# 끝점이 앵커보다 몸 앞쪽으로 (쉬는 사슬이 약간 뒤로 기울어 있어 0.02 여유) 나오지 않음
		check((tip - tgt_ref).dot(pf) < 0.12, "탱크 급정지 %d: 천 끝이 몸 앞으로 안 나옴 (%.3f)" % [i, (tip - tgt_ref).dot(pf)])
	holder.free()


# ---------- 순수 계산 (ext_motion.gd) ----------

func test_gaze_math() -> void:
	check(absf(M.yaw_to(Vector3(1, 0, 0))) < 1e-6, "정면 = 0")
	check(M.yaw_to(Vector3(1, 0, -1)) > 0.7, "왼쪽 (-z) = + (고도 Y 회전)")
	check(M.yaw_to(Vector3(1, 0, 1)) < -0.7, "오른쪽 (+z) = −")
	var t: Dictionary = M.pick_target([Vector3(5, 0, 0), Vector3(2, 0, 1), Vector3(-1, 0, 0.2), Vector3(0.1, 0, 0)], 7.0, 1.9)
	check(not t.is_empty() and absf(float(t.dist) - sqrt(5.0)) < 1e-4, "가장 가까운 (앞쪽 시야, 너무 가까운 것 제외) 몸: %s" % [t])
	check(M.pick_target([Vector3(9, 0, 0)], 7.0, 1.9).is_empty(), "멀면 없음")
	check(M.pick_target([Vector3(-3, 0, 0)], 7.0, 1.9).is_empty(), "뒤에 있으면 안 돌아봄")
	check(absf(M.clamp_yaw(2.0, K.EXT_GAZE_MAX_DEG) - deg_to_rad(K.EXT_GAZE_MAX_DEG)) < 1e-6, "한계 ±%d 도" % int(K.EXT_GAZE_MAX_DEG))
	check(absf(M.clamp_yaw(-2.0, 35.0) + deg_to_rad(35.0)) < 1e-6, "음수 쪽도")
	var cur := 0.0
	for i in 30:
		cur = M.follow(cur, 0.5, 1.0 / 60.0, K.EXT_GAZE_RATE)
	check(cur > 0.2 and cur < 0.5, "부드럽게 따라감 (0.5 초 안에 목표의 일부)")
	var sum := 0.0
	for e in K.EXT_GAZE_BONES:
		sum += float(e[1])
	check(absf(sum - 1.0) < 1e-5, "시선 뼈 몫 합 = 1")


func test_gaze_off_states() -> void:
	check(M.gaze_allowed(_st()), "서 있으면 켬")
	check(M.gaze_allowed(_st({"walking": true, "hs": 4.0})), "달리기도 켬")
	for ov in [{"stunned": true}, {"tumble": 0.5}, {"recover": 0.4}, {"flip": 0.3}, {"dizzy": 0.5}, {"emote": 2}, {"victory": 0.5}, {"act": {"phase": "wind"}}, {"airDash": 0.5},
			{"hit": {"age": 0.1, "dx": -1.0, "dy": 0.0, "pow": 1.0}}]:
		check(not M.gaze_allowed(_st(ov)), "끔: %s" % [ov])
	check(M.gaze_allowed(_st({"hit": {"age": 2.0, "dx": -1.0, "dy": 0.0, "pow": 1.0}})), "맞은 지 오래면 다시 켬")


func test_breath_math() -> void:
	var ids := ["ninja", "tank", "hunter", "hook"]
	var ph := {}
	var per := {}
	for id in ids:
		ph[M.breath_phase(id)] = true
		per[snappedf(M.breath_period(id), 0.001)] = true
		var p: float = M.breath_period(id)
		check(p >= K.EXT_BREATH_PERIOD.x - 1e-4 and p <= K.EXT_BREATH_PERIOD.y + 1e-4, "%s 주기 %.2f 초 (2~4초 범위)" % [id, p])
		check(absf(M.breath(0.5, id)) <= 1.0, "숨쉬기 -1..1")
	check(ph.size() >= 3, "캐릭터마다 위상이 다름 (%d 종)" % ph.size())
	check(per.size() >= 3, "캐릭터마다 주기가 다름")
	check(M.breath_allowed(_st()), "서 있을 때만 숨쉬기")
	check(not M.breath_allowed(_st({"walking": true})) and not M.breath_allowed(_st({"air": true})) and not M.breath_allowed(_st({"act": {"phase": "wind"}})), "걷기·공중·공격 중 끔")


func test_hit_react_math() -> void:
	var front: Dictionary = M.hit_react({"dx": -1.0, "dy": 0.0, "pow": 1.0})
	var behind: Dictionary = M.hit_react({"dx": 1.0, "dy": 0.0, "pow": 1.0})
	var left: Dictionary = M.hit_react({"dx": 0.0, "dy": 1.0, "pow": 1.0})
	var right: Dictionary = M.hit_react({"dx": 0.0, "dy": -1.0, "pow": 1.0})
	check(front.back > 0.5 and front.front_hit and not front.back_hit, "앞에서 맞음 = 뒤로 젖힘")
	check(behind.back < -0.5 and behind.back_hit, "뒤에서 맞음 = 앞으로 숙임")
	check(left.twist * right.twist < 0.0 and absf(left.twist) > 0.1, "옆에서 맞음: 좌우 비틂 반대")
	check(not front.crit and M.hit_react({"dx": -1.0, "dy": 0.0, "pow": K.EXT_HIT_CRIT_POW}).crit, "치명·강타 = pow >= EXT_HIT_CRIT_POW")


# ---------- 뼈에 얹기 ----------

func _tree_root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


# 가까운 몸 쪽으로 머리·윗몸이 돌아가되 한계 안, 멀면·끄는 상태면 안 돌아감 (같은 자세에서 목표 있을 때와 없을 때의 머리 방향 차이로 잼)
func test_gaze_turns_head_toward_nearest() -> void:
	for ch in ["ninja", "tank", "hunter", "hook"]:
		M.bodies.clear() # 다른 테스트가 남긴 몸이 목표가 되지 않게
		var a = _body(ch)
		if a.ext == null:
			a.free()
			continue
		a.ext.clipset = {} # 클립 섞임이 머리 각을 흔들지 않게
		var bb = _body(ch)
		var ha := Node3D.new()
		var hb := Node3D.new()
		ha.add_child(a)
		hb.add_child(bb)
		var X = a.ext
		var sk: Skeleton3D = X.sk
		hb.position = Vector3(40.0, 0.0, 0.0) # 멀리 = 시선 없음 (기준)
		for i in 150:
			_step(X, _st())
		var base: Quaternion = _gpos(sk, "mixamorig_Head").basis.get_rotation_quaternion()
		hb.position = Vector3(1.2, 0.0, 3.0) # 오른쪽 옆 (각도 약 68도 → 한계 35도로 잘림)
		for i in 150:
			_step(X, _st())
		var ang: float = base.angle_to(_gpos(sk, "mixamorig_Head").basis.get_rotation_quaternion())
		check(ang > deg_to_rad(28.0) and ang < deg_to_rad(K.EXT_GAZE_MAX_DEG + 3.0), "%s 가까운 몸 쪽으로 머리가 한계 안에서 돌아감 (%.1f 도, 한계 %d)" % [ch, rad_to_deg(ang), int(K.EXT_GAZE_MAX_DEG)])
		check(X.gaze_y < -0.5, "%s 오른쪽 목표 = 오른쪽으로 (yaw %.2f)" % [ch, X.gaze_y])
		# 앞쪽 가까운 몸 (정면 10도): 조금만
		hb.position = Vector3(3.0, 0.0, 0.5)
		for i in 150:
			_step(X, _st())
		var ang2: float = base.angle_to(_gpos(sk, "mixamorig_Head").basis.get_rotation_quaternion())
		check(ang2 < ang and ang2 > 0.05, "%s 정면에 가까울수록 덜 돌아감 (%.1f 도)" % [ch, rad_to_deg(ang2)])
		# 뒤에 있으면 안 돌아봄
		hb.position = Vector3(-3.0, 0.0, 0.5)
		for i in 150:
			_step(X, _st())
		check(base.angle_to(_gpos(sk, "mixamorig_Head").basis.get_rotation_quaternion()) < 0.05, "%s 뒤에 있는 몸은 안 돌아봄" % ch)
		# 맞아서 경직이면 끔: 목표가 있어도 가중치가 0 으로 (머리는 코드 자세)
		hb.position = Vector3(1.2, 0.0, 3.0)
		for i in 120:
			_step(X, _st())
		check(absf(X.gaze_y) > 0.4, "%s (다시 켜짐)" % ch)
		for i in 60:
			_step(X, _st({"stunned": true}))
		check(X.gaze_w < 0.05, "%s 경직 중에는 시선 가중치 0 (%.2f)" % [ch, X.gaze_w])
		for i in 60:
			_step(X, _st({"act": {"phase": "wind"}}))
		check(X.gaze_w < 0.05, "%s 공격 중에도 끔" % ch)
		# 맞음 움찔 뒤 머리 뼈가 쌓여 남지 않음 (옛 W38 문제: 안 매칭된 머리 뼈에 매 프레임 더해 졌음)
		hb.position = Vector3(40.0, 0.0, 0.0)
		for i in 150:
			_step(X, _st())
		var hq0: Quaternion = _gpos(sk, "mixamorig_Head").basis.get_rotation_quaternion()
		for i in 18:
			_step(X, _st({"hit": {"id": 1, "age": 0.01 + i / 60.0, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 2.0}}))
		for i in 30:
			_step(X, _st())
		check(hq0.angle_to(_gpos(sk, "mixamorig_Head").basis.get_rotation_quaternion()) < 0.03, "%s 맞음이 끝나면 머리가 원래대로 (쌓이지 않음, %.3f)" % [ch, hq0.angle_to(_gpos(sk, "mixamorig_Head").basis.get_rotation_quaternion())])
		ha.free()
		hb.free()


# 숨쉬기: 서 있으면 척추가 아주 조금 오르내리고, 걸으면 안 함. 착지: 서 있다 land > 0 이면 무릎이 굽고 엉덩이가 내려감
func test_breath_and_land_on_bones() -> void:
	for ch in ["ninja", "tank", "hunter", "hook"]:
		var b = _body(ch)
		if b.ext == null:
			b.free()
			continue
		var X = b.ext
		X.clipset = {}
		var sk: Skeleton3D = X.sk
		var sp := sk.find_bone("mixamorig_Spine2")
		var lo := 9.0
		var hi := -9.0
		var q0: Quaternion = sk.get_bone_pose_rotation(sp)
		var maxd := 0.0
		for i in 240: # 4초
			_step(X, _st({"t": float(i) / 60.0}))
			maxd = maxf(maxd, q0.angle_to(sk.get_bone_pose_rotation(sp)))
		check(maxd > 0.003 and maxd < 0.12, "%s 숨쉬기 척추 움직임 %.4f rad (아주 작게)" % [ch, maxd])
		# 착지
		_step(X, _st())
		var hy0: float = sk.get_bone_pose_position(sk.find_bone("mixamorig_Hips")).y
		var kn0: Quaternion = sk.get_bone_pose_rotation(sk.find_bone("mixamorig_RightLeg"))
		_step(X, _st({"land": 0.9}))
		var hy1: float = sk.get_bone_pose_position(sk.find_bone("mixamorig_Hips")).y
		var kn1: Quaternion = sk.get_bone_pose_rotation(sk.find_bone("mixamorig_RightLeg"))
		check(hy1 < hy0 - 0.003, "%s 착지: 엉덩이가 내려감 (%.4f → %.4f)" % [ch, hy0, hy1])
		check(kn0.angle_to(kn1) > 0.15, "%s 착지: 무릎이 굽음 (%.2f rad)" % [ch, kn0.angle_to(kn1)])
		# 발은 땅에 그대로 (엉덩이 내림 + 굽힘이 맞물림): 발 높이 변화가 작음
		var f0: float = _gpos(sk, "mixamorig_RightFoot").origin.y
		_step(X, _st())
		var f_rest: float = _gpos(sk, "mixamorig_RightFoot").origin.y
		_step(X, _st({"land": 0.9}))
		var f1: float = _gpos(sk, "mixamorig_RightFoot").origin.y
		check(absf(f1 - f_rest) < 0.03, "%s 착지 굽힘에도 발 높이 거의 그대로 (%.3f)" % [ch, f1 - f_rest])
		b.free()


# 맞음: 앞/뒤/옆에 따라 움찔 방향이 다르고, 치명은 머리가 채찍처럼 오가며 손이 흔들림
func test_hit_direction_and_crit() -> void:
	for ch in ["tank", "hunter", "hook", "ninja"]:
		var b = _body(ch)
		if b.ext == null:
			b.free()
			continue
		var X = b.ext
		X.clipset = {}
		var sk: Skeleton3D = X.sk
		var s1 := sk.find_bone("mixamorig_Spine1")
		var hit := func(age: float, dx: float, dy: float, pw: float) -> Dictionary: return _st({"hit": {"id": 1, "age": age, "stop": 0.0, "dx": dx, "dy": dy, "pow": pw}})
		_step(X, _st())
		var head0 := _gpos(sk, "mixamorig_Head").origin
		_step(X, hit.call(0.04, -1.0, 0.0, 1.0))
		var h_front := _gpos(sk, "mixamorig_Head").origin - head0
		_step(X, hit.call(0.04, 1.0, 0.0, 1.0))
		var h_back := _gpos(sk, "mixamorig_Head").origin - head0
		check(h_front.x < -0.003 and h_back.x > 0.003, "%s 앞에서 맞으면 머리가 뒤로, 뒤에서 맞으면 앞으로 (%.3f / %.3f)" % [ch, h_front.x, h_back.x])
		_step(X, _st())
		var s_rest: Quaternion = sk.get_bone_pose_rotation(s1)
		_step(X, hit.call(0.04, 0.0, 1.0, 1.0))
		var t_l: Quaternion = sk.get_bone_pose_rotation(s1)
		_step(X, hit.call(0.04, 0.0, -1.0, 1.0))
		var t_r: Quaternion = sk.get_bone_pose_rotation(s1)
		check(t_l.angle_to(t_r) > 0.02, "%s 왼쪽·오른쪽에서 맞음 = 몸통이 다르게 비틀림 (%.3f)" % [ch, t_l.angle_to(t_r)])
		# 치명: 머리가 시간에 따라 부호를 바꾸며 진동 (채찍), 약한 타는 안 함
		var whip_min := 9.0
		var whip_max := -9.0
		for i in 14:
			_step(X, hit.call(0.02 + i * 0.012, -1.0, 0.0, 2.0))
			var z := _gpos(sk, "mixamorig_Head").origin.x
			whip_min = minf(whip_min, z)
			whip_max = maxf(whip_max, z)
		var weak_min := 9.0
		var weak_max := -9.0
		for i in 14:
			_step(X, hit.call(0.02 + i * 0.012, -1.0, 0.0, 1.0))
			var z2 := _gpos(sk, "mixamorig_Head").origin.x
			weak_min = minf(weak_min, z2)
			weak_max = maxf(weak_max, z2)
		check((whip_max - whip_min) > (weak_max - weak_min) * 1.2, "%s 치명은 약한 타보다 머리가 크게 흔들림 (%.3f vs %.3f)" % [ch, whip_max - whip_min, weak_max - weak_min])
		# 손 흔들림 (치명만)
		var hh := sk.find_bone("mixamorig_RightHand" if ch != "tank" else "mixamorig_RightHand")
		_step(X, _st())
		var hq: Quaternion = sk.get_bone_pose_rotation(hh)
		_step(X, hit.call(0.04, -1.0, 0.0, 1.0))
		var weak_h: float = hq.angle_to(sk.get_bone_pose_rotation(hh))
		_step(X, hit.call(0.04, -1.0, 0.0, 2.0))
		var crit_h: float = hq.angle_to(sk.get_bone_pose_rotation(hh))
		check(crit_h > weak_h + 0.03, "%s 치명은 쥔 손이 흔들림 (%.3f vs %.3f)" % [ch, crit_h, weak_h])
		b.free()


# 탱크 방어구 깨짐 → 방패 쥔 (왼) 팔 반동
func test_tank_armor_break_recoil() -> void:
	var b = _body("tank")
	if b.ext == null:
		b.free()
		return
	var X = b.ext
	X.clipset = {}
	var sk: Skeleton3D = X.sk
	var bi: int = int(X.info.map.get("shoulder_L", -1))
	check(bi >= 0, "왼 어깨 뼈 매칭")
	_step(X, _st({"hit": {"id": 1, "age": 5.0, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 1.0}}))
	var q0: Quaternion = sk.get_bone_pose_rotation(bi)
	b.armor_break_react_at = Time.get_ticks_msec() / 1000.0 - 0.03
	_step(X, _st({"hit": {"id": 1, "age": 5.0, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 1.0}}))
	var q1: Quaternion = sk.get_bone_pose_rotation(bi)
	check(q0.angle_to(q1) > 0.1, "방어구 깨짐: 방패 팔이 반동 (%.3f rad)" % q0.angle_to(q1))
	b.armor_break_react_at = -1e9
	_step(X, _st({"hit": {"id": 1, "age": 5.0, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 1.0}}))
	check(q0.angle_to(sk.get_bone_pose_rotation(bi)) < 1e-3, "시간이 지나면 반동 없음")
	b.free()


# W40 3: 1인칭 팔 = 3인칭 클립 곡선 (기본 끔 — K.VM_CLIP_ARM 0): 공격·스킬 클립 중에만 팔 뼈의 클립 차이를 기록, 다른 때는 비움
func test_vm_clip_arm_delta_recorded_only_in_act() -> void:
	check(K.VM_CLIP_ARM == 0.0, "1인칭 클립 팔은 기본 끔 (보류)")
	for ch in ["hunter", "hook", "tank"]:
		var b = _body(ch)
		if b.ext == null:
			b.free()
			continue
		var X = b.ext
		var move := "베기" if ch == "hunter" else ("갈고리 휘두르기" if ch == "hook" else "주먹")
		for i in 12:
			_step(X, _st({"act": {"id": 1, "move": move, "phase": "strike", "u": 0.5, "air": false}}))
		check(not X.arm_delta.is_empty(), "%s 공격 클립 중 팔 뼈 차이 기록 (%d 뼈)" % [ch, X.arm_delta.size()])
		var mx := 0.0
		for bi in X.arm_delta:
			mx = maxf(mx, Quaternion.IDENTITY.angle_to(X.arm_delta[bi]))
		check(mx > 0.05, "%s 클립이 코드 팔과 다름 (최대 %.2f rad)" % [ch, mx])
		for i in 40:
			_step(X, _st())
		check(X.arm_delta.is_empty(), "%s 공격이 끝나면 비움" % ch)
		b.free()
