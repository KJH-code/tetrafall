# W46 걸음 QA 의 측정 본체 (tools/gait_qa.gd 와 tests/test_w46.gd 가 같이 씀): 몸 동작 층 (Ext.sync) 에 일정 속도 합성 이동을 4초 먹여
# 접지 발 미끄러짐 (비 = 접지 동안 발 월드 속도 중앙값 ÷ 몸 속도) 과 다리 뼈 튐을 잼. 설명·사용법은 tools/gait_qa.gd 머리말
extends RefCounted

const C := preload("res://core/config.gd")
const M := preload("res://core/motion_qa_math.gd")
const Motion_ := preload("res://chars/ext_motion.gd")

const NEAR := 0.02 # 땅 근처 높이 (두 발 전체 최저 + m)
const MIN_RUN := 3 # 접지 최소 프레임
const SECS := 4.0
const BAD := 0.35 # 비가 이 값을 넘으면 미끄러짐

static var vt := [100.0]


static func st_base(over := {}) -> Dictionary:
	var st := {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "emote": -1, "victory": -1.0, "hit": null, "act": null,
		"tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "dizzy": 0.0, "whirl": -1.0, "glide": false,
		"accF": 0.0, "accS": 0.0, "mvF": 0.0, "mvS": 0.0, "vw": Vector2.ZERO}
	st.merge(over, true)
	return st


# 몸 하나에서 필요한 값: {X, sk, sc, freq, foots, toes, leg_ids, all_ids}
static func rig(b, ch: String) -> Dictionary:
	var X = b.ext
	var sk: Skeleton3D = X.sk
	var sc: float = 1.0
	var nd: Node = sk
	while nd != null and nd != b.get_parent():
		if nd is Node3D:
			sc *= (nd as Node3D).transform.basis.get_scale().x
		nd = nd.get_parent()
	var foots := []
	var toes := []
	for nm in ["LeftFoot", "RightFoot"]:
		foots.append(sk.find_bone("mixamorig_" + nm))
		toes.append(sk.find_bone("mixamorig_" + nm.replace("Foot", "ToeBase")))
	var leg_ids := []
	for side in ["Left", "Right"]:
		for lg in ["UpLeg", "Leg", "Foot"]:
			leg_ids.append(sk.find_bone("mixamorig_%s%s" % [side, lg]))
	var all_ids := []
	for bi in sk.get_bone_count():
		var cl := M.bone_class(sk.get_bone_name(bi))
		if cl != "skip" and cl != "cloth":
			all_ids.append(bi)
	var Pose = load("res://chars/figure_pose.gd")
	return {"X": X, "sk": sk, "sc": sc, "freq": float(Pose.gait_of(ch).freq), "foots": foots, "toes": toes, "leg_ids": leg_ids, "all_ids": all_ids}


# 한 몸·한 속도·한 방향 측정 (Motion_.clock = vt 로 꽂아 둔 상태에서 부를 것) → {n_st, bad, mean, max, still, leg_pops, body_pops, worst, worst_bone}
static func measure(rg: Dictionary, spd: float, mvF: float, mvS: float) -> Dictionary:
	var X = rg.X
	var sk: Skeleton3D = rg.sk
	var sc: float = rg.sc
	var freq: float = rg.freq
	var foots: Array = rg.foots
	var toes: Array = rg.toes
	var leg_ids: Array = rg.leg_ids
	var all_ids: Array = rg.all_ids
	X.last_layer.clear()
	var phase := 0.0
	var disp := Vector2.ZERO
	var dets := {}
	for bi in all_ids:
		dets[bi] = M.PopDet.new(M.pop_thr(M.bone_class(sk.get_bone_name(bi))), M.POP_SOFT_K)
	var pop_leg := 0
	var pop_body := 0
	var worst := 0.0
	var worst_bone := ""
	var tr := [[], []]
	var frames := int(SECS * 60.0)
	for f in frames:
		vt[0] += 1.0 / 60.0
		var st := st_base({"t": vt[0]})
		if spd > 0.01:
			phase += spd * C.ANIM_WALK_FREQ * freq / 60.0
			st = st_base({"t": vt[0], "walking": true, "hs": spd, "mvF": mvF, "mvS": mvS, "vw": Vector2(mvF, mvS), "walk": phase})
		disp += Vector2(mvF, -mvS) / 60.0 # 뼈대 공간: 앞 +x, 오른쪽 +z
		X.sync(st)
		if f >= 60:
			for k in 2:
				var p: Vector3 = _gt(sk, foots[k]).origin * sc
				var ty: float = _gt(sk, toes[k]).origin.y * sc if toes[k] >= 0 else p.y
				(tr[k] as Array).append([Vector2(p.x, p.z) + disp, minf(p.y, ty), disp])
		for bi in all_ids:
			var r: Dictionary = dets[bi].feed(sk.get_bone_pose_rotation(bi))
			if f < 62:
				dets[bi].reset()
				continue
			if float(r.w) > worst and leg_ids.has(bi):
				worst = float(r.w)
				worst_bone = sk.get_bone_name(bi).trim_prefix("mixamorig_")
			if r.pop:
				if leg_ids.has(bi):
					pop_leg += 1
				else:
					pop_body += 1
	if OS.get_environment("GQ_DUMP") != "":
		for s_i in range(1, (tr[0] as Array).size()):
			var o := "DUMP %d" % s_i
			for k in 2:
				o += " | h %.1f v %.2f x %.3f" % [float(tr[k][s_i][1]) * 100.0, ((tr[k][s_i][0] as Vector2) - (tr[k][s_i - 1][0] as Vector2)).length() * 60.0, (tr[k][s_i][0] as Vector2).x - (tr[k][s_i][2] as Vector2).x]
			print(o)
	# 접지 판정
	var n_st := 0
	var bad := 0
	var sum_r := 0.0
	var max_r := 0.0
	var still := 0
	var hmin := 1e9
	for k in 2:
		for s in tr[k]:
			hmin = minf(hmin, float(s[1]))
	var seg := []
	var seg_foot := -1
	var n: int = (tr[0] as Array).size()
	for s_i in range(n + 1):
		var foot := -1
		if s_i < n:
			var h0: float = float(tr[0][s_i][1])
			var h1: float = float(tr[1][s_i][1])
			if minf(h0, h1) - hmin < NEAR:
				foot = 0 if h0 <= h1 else 1
		if foot != seg_foot or foot < 0:
			if seg_foot >= 0 and seg.size() >= MIN_RUN:
				var sp_l := []
				for q in range(1, seg.size()):
					sp_l.append(((seg[q][0] as Vector2) - (seg[q - 1][0] as Vector2)).length() * 60.0)
				sp_l.sort()
				var med: float = float(sp_l[sp_l.size() / 2])
				if spd > 0.01:
					var ratio := med / spd
					n_st += 1
					sum_r += ratio
					max_r = maxf(max_r, ratio)
					if ratio > BAD:
						bad += 1
				elif med * float(seg.size()) / 60.0 > 0.04: # 서 있는데 접지 발이 끌림 (서 있을 땐 접지 구간을 세지 않음 — 오탐 확인용)
					still += 1
			seg = []
			seg_foot = foot
		if foot >= 0:
			seg.append(tr[foot][s_i])
	return {"n_st": n_st, "bad": bad, "mean": sum_r / maxf(1.0, float(n_st)), "max": max_r, "still": still, "leg_pops": pop_leg, "body_pops": pop_body, "worst": worst, "worst_bone": worst_bone}


static func _gt(sk: Skeleton3D, bi: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var b := bi
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t


# 천 사슬 떨림 (W46): 몸이 일정 속도로 달리거나 (zig = 0.5초마다 좌우로 방향을 바꿈, 실제 판의 조작처럼) 하는 동안 천 뼈 (끝 마디 = 이름이 _3 으로 끝나는 뼈) 의 회전 각속도 ω (°/표본) 를 재
# → {jerk: 표본간 |Δω| 평균 (°), flip: ω 방향이 뒤집힌 비율, peak: 최대 ω, bones: 센 뼈 수}. 사슬 끝이 떠는 정도 (갈고리 치맛자락·사냥꾼 망토 가장자리)
static func measure_cloth(rg: Dictionary, spd: float, zig: bool) -> Dictionary:
	var X = rg.X
	var sk: Skeleton3D = rg.sk
	var ids := []
	for bi in sk.get_bone_count():
		var nm := sk.get_bone_name(bi)
		if M.bone_class(nm) == "cloth" and nm.ends_with("_3"):
			ids.append(bi)
	X.last_layer.clear()
	var phase := 0.0
	var prevq := {}
	var prevw := {}
	var sum_j := 0.0
	var n_j := 0
	var flips := 0
	var n_f := 0
	var peak := 0.0
	var frames := int(SECS * 60.0)
	for f in frames:
		vt[0] += 1.0 / 60.0
		var side := 0.0
		if zig:
			side = 1.0 if int(float(f) / 30.0) % 2 == 0 else -1.0
		var mvF := spd * (0.6 if zig else 1.0)
		var mvS := spd * 0.8 * side
		var hs := Vector2(mvF, mvS).length()
		phase += hs * C.ANIM_WALK_FREQ * rg.freq / 60.0
		var st := st_base({"t": vt[0], "walking": true, "hs": hs, "mvF": mvF, "mvS": mvS, "vw": Vector2(mvF, mvS), "walk": phase})
		X.sync(st)
		for bi in ids:
			var q: Quaternion = sk.get_bone_pose_rotation(bi)
			if prevq.has(bi) and f > 60:
				var rv: Vector3 = _rotvec(prevq[bi], q)
				var w := rv.length()
				peak = maxf(peak, w)
				if prevw.has(bi):
					var pw: Vector3 = prevw[bi]
					sum_j += (rv - pw).length()
					n_j += 1
					if rv.length() > 0.5 and pw.length() > 0.5:
						n_f += 1
						if rv.dot(pw) < 0.0:
							flips += 1
				prevw[bi] = rv
			prevq[bi] = q
	return {"jerk": sum_j / maxf(1.0, float(n_j)), "flip": float(flips) / maxf(1.0, float(n_f)), "peak": peak, "bones": ids.size()}


# 두 회전 사이 회전 벡터 (축 × 각, °)
static func _rotvec(a: Quaternion, b: Quaternion) -> Vector3:
	var d: Quaternion = (a.inverse() * b).normalized()
	if d.w < 0.0:
		d = Quaternion(-d.x, -d.y, -d.z, -d.w)
	var ang := 2.0 * acos(clampf(d.w, -1.0, 1.0))
	var sn := sqrt(maxf(1.0 - d.w * d.w, 0.0))
	if sn < 1e-6:
		return Vector3.ZERO
	return Vector3(d.x, d.y, d.z) / sn * rad_to_deg(ang)
