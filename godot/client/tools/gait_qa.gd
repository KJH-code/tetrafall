# W46 걸음 QA (렌더·서버 없이 결정적): 4명 × 방향 (앞·뒤·좌·우·대각) × 속도 (걷기·달리기) 로 일정 속도 합성 이동을 몸 동작 층 (Ext.sync) 에 먹이고
#  ① 발 미끄러짐 — 발 월드 위치 (몸 이동 더함) 에서 '땅 근처 (그 발의 최저 높이 + 2.5cm 안) + 수평 속도가 낮은 구간' 을 디딤으로 잡아, 디딤 동안 발이 월드에서 움직인 거리 ÷ 몸이 간 거리 (0 = 딱 붙음, 1 = 몸 따라 스케이트)
#  ② 다리 팝 — 허벅지·무릎·발 뼈 회전 각속도 (60Hz 표본당 °) 의 최악값과 임계 (35°/60°) 넘은 수 (모션 QA 와 같은 검출기)
# 서 있을 때 (속도 0) 는 디딤 판정이 0 이 되는지 (오탐 0) 도 확인. 같은 일을 재연 (motion_qa) 으로 하면 디딤이 캐릭터마다 1~8개뿐이라 신뢰할 수 없었음 (W44).
# godot --headless --path godot/client -s res://tools/gait_qa.gd -- [캐릭터 ,로 이음 기본 ninja,tank,hunter,hook] [--csv 파일] [--no-stride] (W34 보폭 IK 끄기) [--rate 배율 고정]
extends SceneTree

const C := preload("res://core/config.gd")
const M := preload("res://core/motion_qa_math.gd")
const Pose := preload("res://chars/figure_pose.gd")
const Motion_ := preload("res://chars/ext_motion.gd")

const NEAR := 0.035 # 땅 근처 높이 (그 발의 이 구간 최저 + m)
const MIN_RUN := 3 # 디딤 최소 프레임
const SECS := 4.0
const DIRS := {"앞": [1.0, 0.0], "뒤": [-1.0, 0.0], "왼": [0.0, 1.0], "오른": [0.0, -1.0], "앞왼 대각": [0.7071, 0.7071], "뒤오른 대각": [-0.7071, -0.7071]} # [앞, 왼쪽] (mvF·mvS 와 같은 뜻)
const SPEEDS := {"걷기": 0.45, "달리기": 1.0}


func _initialize() -> void:
	_run.call_deferred()


func _st(over := {}) -> Dictionary:
	var st := {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "emote": -1, "victory": -1.0, "hit": null, "act": null,
		"tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "dizzy": 0.0, "whirl": -1.0, "glide": false,
		"accF": 0.0, "accS": 0.0, "mvF": 0.0, "mvS": 0.0, "vw": Vector2.ZERO}
	st.merge(over, true)
	return st


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var chars: PackedStringArray = ["ninja", "tank", "hunter", "hook"]
	var csv_path := ""
	var i := 0
	while i < a.size():
		if a[i] == "--csv" and i + 1 < a.size():
			csv_path = a[i + 1]
			i += 1
		elif not a[i].begins_with("--"):
			chars = a[i].split(",")
		i += 1
	var Body = load("res://chars/body.gd")
	Body.use_ext = true
	var vp := SubViewport.new()
	root.add_child(vp)
	var csv := ["char,dir,speed,stances,bad,mean_ratio,max_ratio,still_stances,knee_pops,body_pops,worst_deg,worst_bone"]
	for ch in chars:
		var b = Body.new()
		b.build(ch, Color(0.2, 0.5, 1.0), true)
		vp.add_child(b)
		await process_frame
		var X = b.ext
		var sk: Skeleton3D = X.sk
		var sc: float = (sk.global_transform.basis.get_scale() * X.get_parent().global_transform.basis.get_scale()).x
		var freq: float = float(Pose.gait_of(ch).freq)
		print("TGQINFO %s sc %.3f hip->foot(rest) %.3f m" % [ch, sc, (_gt(sk, sk.find_bone("mixamorig_LeftUpLeg")).origin - _gt(sk, sk.find_bone("mixamorig_LeftFoot")).origin).length() * sc])
		var vt := [100.0]
		Motion_.clock = func(): return vt[0]
		var foots := []
		var toes := []
		for nm in ["LeftFoot", "RightFoot"]:
			foots.append(sk.find_bone("mixamorig_" + nm))
			toes.append(sk.find_bone("mixamorig_" + nm.replace("Foot", "ToeBase")))
		var legs := ["UpLeg", "Leg", "Foot"]
		var leg_ids := []
		for side in ["Left", "Right"]:
			for lg in legs:
				leg_ids.append(sk.find_bone("mixamorig_%s%s" % [side, lg]))
		var all_ids := []
		for bi in sk.get_bone_count():
			var cl := M.bone_class(sk.get_bone_name(bi))
			if cl != "skip" and cl != "cloth":
				all_ids.append(bi)
		for sp in ["서기"] + SPEEDS.keys():
			for dn in DIRS.keys():
				if sp == "서기" and dn != "앞":
					continue
				var spd: float = 0.0 if sp == "서기" else C.MOVE_SPEED * float(SPEEDS[sp])
				var d: Array = DIRS[dn]
				var mvF: float = float(d[0]) * spd
				var mvS: float = float(d[1]) * spd
				# 새 몸 상태 (이전 방향 잔상 없이)
				X.last_layer.clear()
				var phase := 0.0
				var disp := Vector2.ZERO
				var pops_det := {}
				for bi in all_ids:
					pops_det[bi] = M.PopDet.new(M.pop_thr(M.bone_class(sk.get_bone_name(bi))), M.POP_SOFT_K)
				var pop_leg := 0
				var pop_body := 0
				var worst := 0.0
				var worst_bone := ""
				# 발 하나씩 디딤 추적
				var tr := [[], []] # [발] → 표본 목록 [월드 xz, 높이, 몸 변위]
				var frames := int(SECS * 60.0)
				for f in frames:
					vt[0] += 1.0 / 60.0
					var st := _st({"t": vt[0]})
					if spd > 0.01:
						phase += spd * C.ANIM_WALK_FREQ * freq / 60.0
						st = _st({"t": vt[0], "walking": true, "hs": spd, "mvF": mvF, "mvS": mvS, "vw": Vector2(mvF, mvS), "walk": phase})
					disp += Vector2(mvF, -mvS) / 60.0 # 뼈대 공간: 앞 +x, 오른쪽 +z
					X.sync(st)
					if f >= 60:
						for k in 2:
							var p: Vector3 = _gt(sk, foots[k]).origin * sc
							var ty: float = _gt(sk, toes[k]).origin.y * sc if toes[k] >= 0 else p.y
							(tr[k] as Array).append([Vector2(p.x, p.z) + disp, minf(p.y, ty), disp]) # 높이 = 발목·발가락 중 낮은 쪽
					for bi in all_ids:
						var r: Dictionary = pops_det[bi].feed(sk.get_bone_pose_rotation(bi))
						if f < 62:
							pops_det[bi].reset()
							continue
						if float(r.w) > worst and leg_ids.has(bi):
							worst = float(r.w)
							worst_bone = sk.get_bone_name(bi).trim_prefix("mixamorig_")
						if r.pop:
							if leg_ids.has(bi):
								pop_leg += 1
							else:
								pop_body += 1
				if OS.get_environment("GQ_DUMP") == ch + "/" + sp + "/" + dn:
					for s_i in range(1, (tr[0] as Array).size()):
						var o := "DUMP %d" % s_i
						for k in 2:
							o += " | h %.1f v %.2f x %.3f" % [float(tr[k][s_i][1]) * 100.0, ((tr[k][s_i][0] as Vector2) - (tr[k][s_i - 1][0] as Vector2)).length() * 60.0, (tr[k][s_i][0] as Vector2).x - (tr[k][s_i][2] as Vector2).x]
						print(o)
				# 디딤 판정: 두 발 중 낮은 쪽이 (두 발 전체 최저 높이 + NEAR) 안이면 그 발이 지지 발. 같은 발이 MIN_RUN 프레임 넘게 이어지면 한 디딤
				# (디딤 중 발 월드 변위 ÷ 몸 변위 = 비. 속도 조건은 안 둠 — 옆·뒤 이동에서 발이 정말 미끄러지는 걸 놓치지 않게)
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
				for s_i in range((tr[0] as Array).size() + 1):
					var foot := -1
					if s_i < (tr[0] as Array).size():
						var h0: float = float(tr[0][s_i][1])
						var h1: float = float(tr[1][s_i][1])
						var lowk := 0 if h0 <= h1 else 1
						if minf(h0, h1) - hmin < NEAR:
							foot = lowk
					if foot != seg_foot or foot < 0:
						if seg_foot >= 0 and seg.size() >= MIN_RUN:
							# 비 = 디딤 동안 발 월드 속도의 중앙값 ÷ 몸 속도 (중앙값이라 디딤 앞뒤 가장자리에 스치는 프레임에 안 흔들림). 0 = 딱 붙음, 1 = 몸 따라 스케이트
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
								if ratio > 0.35:
									bad += 1
							else:
								n_st += 1
								if med * float(seg.size()) / 60.0 > 0.04:
									still += 1
						seg = []
						seg_foot = foot
					if foot >= 0:
						seg.append(tr[foot][s_i])
				var mean_r := sum_r / maxf(1.0, float(n_st))
				print("TGQ %s %s %s: 디딤 %d (나쁜 %d, 비 평균 %.2f 최대 %.2f, 정지 끌림 %d) · 다리 팝 %d 몸 팝 %d · 다리 최악 %.1f° (%s)" % [ch, sp, dn if sp != "서기" else "-", n_st, bad, mean_r, max_r, still, pop_leg, pop_body, worst, worst_bone])
				csv.append("%s,%s,%s,%d,%d,%.3f,%.3f,%d,%d,%d,%.1f,%s" % [ch, dn, sp, n_st, bad, mean_r, max_r, still, pop_leg, pop_body, worst, worst_bone])
		Motion_.clock = Callable()
		b.queue_free()
	if csv_path != "":
		var fh := FileAccess.open(csv_path, FileAccess.WRITE)
		fh.store_string("\n".join(csv) + "\n")
	quit()


static func _gt(sk: Skeleton3D, bi: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var b := bi
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t
