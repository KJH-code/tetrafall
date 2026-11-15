# W46 모션 개선 4차: 걸음 (박자 배율·보폭 k 를 접지 발 미끄러짐 중앙값 비로 다시 고름, 옆걸음 골반 yaw) — core/gait_qa.gd 합성 이동으로 잼 (tools/gait_qa.gd 와 같은 측정)
extends RefCounted

const Body := preload("res://chars/body.gd")
const G := preload("res://core/gait_qa.gd")
const C := preload("res://core/config.gd")
const Motion_ := preload("res://chars/ext_motion.gd")
const MQ := preload("res://core/motion_qa_math.gd")
const K := preload("res://chars/chars_config.gd")

var errors: Array = []
const CHARS := ["ninja", "tank", "hunter", "hook"]
# 앞으로 걷기·달리기 접지 비 상한 (W46 값 0.09~0.21 (닌자 걷기 0.59) + 여유 — W45 이전 박자 ×1.6 보폭 ×1.4 는 1.4~2.6)
const FWD_MAX := {"ninja": {"walk": 0.75, "run": 0.30}, "tank": {"walk": 0.35, "run": 0.25}, "hunter": {"walk": 0.25, "run": 0.25}, "hook": {"walk": 0.25, "run": 0.20}}
const SIDE_RUN_MAX := 0.6 # 옆으로 달리기 (W46 전 0.73~0.8)


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _rig(ch: String, level := "") -> Array:
	var Gfx = load("res://world/gfx.gd")
	var was_plan = Gfx.plan
	if level != "":
		Gfx.plan = {"level": level}
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	Gfx.plan = was_plan
	return [b, G.rig(b, ch)]


func test_gait_slip_and_pops() -> void:
	for ch in CHARS:
		var pr := _rig(ch)
		var rg: Dictionary = pr[1]
		Motion_.clock = func(): return G.vt[0]
		var stand: Dictionary = G.measure(rg, 0.0, 0.0, 0.0)
		check(int(stand.n_st) == 0 and int(stand.still) == 0, "%s 서 있을 땐 접지 구간·끌림 0 (오탐 없음): %s" % [ch, stand])
		for nm in ["walk", "run"]:
			var spd: float = C.MOVE_SPEED * (0.45 if nm == "walk" else 1.0)
			var f: Dictionary = G.measure(rg, spd, spd, 0.0)
			var bk: Dictionary = G.measure(rg, spd, -spd, 0.0)
			check(int(f.n_st) >= 3, "%s %s 앞 접지 구간 %d >= 3" % [ch, nm, f.n_st])
			check(float(f.mean) <= float(FWD_MAX[ch][nm]), "%s %s 앞 발 미끄러짐 비 %.2f <= %.2f" % [ch, nm, f.mean, FWD_MAX[ch][nm]])
			check(float(bk.mean) <= float(FWD_MAX[ch][nm]), "%s %s 뒤 발 미끄러짐 비 %.2f <= %.2f" % [ch, nm, bk.mean, FWD_MAX[ch][nm]])
			if nm == "run":
				check(int(f.leg_pops) <= 2, "%s 달리기 다리 팝 %d <= 2 (W45 이전 20~60)" % [ch, f.leg_pops])
				check(float(f.worst) < 35.0, "%s 달리기 다리 최악 각속도 %.1f° < 35° (W45 이전 56~69)" % [ch, f.worst])
				var sd: Dictionary = G.measure(rg, spd, 0.0, spd)
				check(float(sd.mean) <= SIDE_RUN_MAX, "%s 옆 달리기 발 미끄러짐 비 %.2f <= %.2f" % [ch, sd.mean, SIDE_RUN_MAX])
		Motion_.clock = Callable()
		(pr[0] as Node).free()


func test_dir_counter_sums_to_one() -> void:
	var s := 0.0
	for e in K.EXT_DIR_COUNTER:
		s += float(e[1])
	check(absf(s - 1.0) < 1e-6, "골반 yaw 되돌림 몫 합 1 (%.3f)" % s)
	check(K.EXT_DIR_MAX_DEG >= 60.0 and K.EXT_DIR_GAIN >= 0.9, "옆걸음 골반 yaw 넉넉히")


# ---------- 천 사슬 끝 떨림 (W46: 박자 ×1.6·보폭 IK 가 사슬 앵커를 흔들던 것 — 곧게 달리기 표본간 각속도 변화 평균 °: 갈고리 3.48 → 0.64, 탱크 3.74 → 0.27, 사냥꾼 0.43 → 0.06) ----------

func test_cloth_tip_jitter_low() -> void:
	var cap := {"tank": 1.0, "hunter": 0.4, "hook": 1.2}
	for ch in cap:
		var pr := _rig(ch)
		Motion_.clock = func(): return G.vt[0]
		for zig in [false, true]:
			var cj: Dictionary = G.measure_cloth(pr[1], C.MOVE_SPEED, zig)
			check(int(cj.bones) >= 2, "%s 천 끝 뼈 %d >= 2" % [ch, cj.bones])
			check(float(cj.jerk) <= float(cap[ch]) * (1.5 if zig else 1.0), "%s 천 끝 떨림 %.2f° <= %.2f° (zig %s)" % [ch, cj.jerk, cap[ch], zig])
			check(float(cj.flip) <= 0.12, "%s 천 끝 방향 반전 %.0f%% <= 12%%" % [ch, float(cj.flip) * 100.0])
		Motion_.clock = Callable()
		(pr[0] as Node).free()


# ---------- 탱크 허리 장갑·벨트 삼각형 늘어남 (W46: 가중치 평활 — 모션 QA ×18.2 → ×3.5) ----------

# 가장 큰 스킨 조각의 변 (지배 뼈가 다른 변, 긴 변만) 중 합성 자세에서 늘어난 최대 배수
func _max_stretch(b, poses: Array) -> float:
	var X = b.ext
	var sk: Skeleton3D = X.sk
	var best: MeshInstance3D = null
	var bn := 0
	for pt in X.parts:
		var mi: MeshInstance3D = pt.mi
		if mi.skin == null or mi.mesh == null:
			continue
		var n := (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if n > bn:
			bn = n
			best = mi
	if best == null:
		return 0.0
	var arr := best.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := 8 if (best.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var skin: Skin = best.skin
	var bb := PackedInt32Array()
	var binds := []
	for i in skin.get_bind_count():
		var bi := skin.get_bind_bone(i)
		if bi < 0:
			bi = sk.find_bone(skin.get_bind_name(i))
		bb.append(bi)
		binds.append(skin.get_bind_pose(i))
	var dom := PackedInt32Array()
	dom.resize(vs.size())
	for v in vs.size():
		var bw := -1.0
		var bo := -1
		for j in per:
			if weights[v * per + j] > bw:
				bw = weights[v * per + j]
				bo = bones[v * per + j]
		dom[v] = bb[bo] if bo >= 0 and bo < bb.size() else -1
	var edges := []
	var seen := {}
	var i2 := 0
	while i2 + 2 < idx.size():
		for e in [[idx[i2], idx[i2 + 1]], [idx[i2 + 1], idx[i2 + 2]]]:
			var lo: int = mini(e[0], e[1])
			var hi: int = maxi(e[0], e[1])
			var key: int = lo * 100000 + hi
			if seen.has(key) or dom[lo] < 0 or dom[hi] < 0 or dom[lo] == dom[hi]:
				continue
			seen[key] = true
			var na := sk.get_bone_name(dom[lo])
			var nb := sk.get_bone_name(dom[hi])
			var rl := vs[lo].distance_to(vs[hi])
			if rl < 0.02 or (na.contains("LeftUpLeg") and nb.contains("RightUpLeg")) or (na.contains("RightUpLeg") and nb.contains("LeftUpLeg")):
				continue
			if MQ.bone_class(na) == "cloth" or MQ.bone_class(nb) == "cloth":
				continue
			edges.append([lo, hi, rl])
		i2 += 3
	var worst := 0.0
	var rl_q: Array = X.info.rest_local
	for pose in poses:
		sk.reset_bone_poses()
		for p in pose:
			var bi := sk.find_bone("mixamorig_" + str(p[0]))
			if bi < 0:
				continue
			if p[1] is Quaternion: # 절대 지역 회전 (모션 QA 가 잰 실제 자세)
				sk.set_bone_pose_rotation(bi, p[1])
				continue
			var rq: Quaternion = (rl_q[bi] as Transform3D).basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(bi, rq * Quaternion(p[1], deg_to_rad(float(p[2]))))
		var G_ := {}
		var sv := {}
		for e in edges:
			for v in [e[0], e[1]]:
				if sv.has(v):
					continue
				var pp := Vector3.ZERO
				for j in per:
					var w := weights[v * per + j]
					if w > 0.0:
						var bi: int = bb[bones[v * per + j]]
						if not G_.has(bi):
							G_[bi] = _gt(sk, bi)
						pp += w * ((G_[bi] as Transform3D) * (binds[bones[v * per + j]] as Transform3D) * vs[v])
				sv[v] = pp
		for e in edges:
			worst = maxf(worst, (sv[e[0]] as Vector3).distance_to(sv[e[1]]) / float(e[2]))
	sk.reset_bone_poses()
	return worst


static func _gt(sk: Skeleton3D, bi: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var b := bi
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t


func test_tank_waist_stretch() -> void:
	var poses := [
		[["LeftUpLeg", Vector3.RIGHT, 70.0]], [["LeftUpLeg", Vector3.RIGHT, -70.0]], [["RightUpLeg", Vector3.RIGHT, 70.0]],
		[["LeftUpLeg", Vector3.BACK, 45.0]], [["RightUpLeg", Vector3.BACK, -45.0]],
		[["LeftUpLeg", Vector3.RIGHT, 75.0], ["Spine", Vector3.RIGHT, 40.0], ["Hips", Vector3.UP, 20.0]],
		[["RightUpLeg", Vector3.RIGHT, 75.0], ["Spine", Vector3.RIGHT, -45.0], ["Hips", Vector3.UP, -25.0], ["Spine1", Vector3.BACK, 20.0]],
		[["LeftUpLeg", Vector3.RIGHT, 90.0], ["RightUpLeg", Vector3.RIGHT, 90.0], ["Spine", Vector3.RIGHT, 30.0]],
		# 모션 QA 가 늘어남 ×12.5 를 잰 실제 자세 (탱크 주먹, 25.9초): 지역 회전 그대로
		[["Hips", Quaternion(0.0, 0.125222, 0.0, 0.992129)], ["Spine", Quaternion(0.009623, 0.078627, -0.043205, 0.995921)], ["LeftUpLeg", Quaternion(0.855539, 0.516582, -0.033218, -0.009664)],
			["RightUpLeg", Quaternion(0.992213, -0.00264, 0.048651, 0.114626)], ["Tabard1_1", Quaternion(0.263292, -0.409572, -0.508278, 0.710339)],
			["Tabard1_2", Quaternion(0.021692, 0.058529, 0.147958, 0.987022)], ["Tabard1_3", Quaternion(-0.011241, -0.008969, 0.049492, 0.998671)]],
	]
	for level in ["stage", "high", "medium", "low"]:
		var pr := _rig("tank", level)
		var mx: float = _max_stretch(pr[0], poses)
		print("   [탱크 허리 늘어남] %s 합성 자세 9개 최대 ×%.2f" % [level, mx])
		check(mx <= 5.0, "탱크 %s 몸 삼각형 늘어남 ×%.2f <= ×5 (모션 QA 전 ×12~18)" % [level, mx])
		(pr[0] as Node).free()
