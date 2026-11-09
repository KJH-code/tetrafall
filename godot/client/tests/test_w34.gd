# W34 새 모델 다듬기: 몸 색 칸 마스크 텍스처 (skin_mask), (뒤 항목은 같은 파일에 계속 더함)
extends RefCounted

const Body := preload("res://chars/body.gd")
const Ext := preload("res://chars/external.gd")
const Pose := preload("res://chars/figure_pose.gd")
const C := preload("res://core/config.gd")
const Clips := preload("res://chars/ext_clips.gd")

var errors: Array = []

const IDS := ["ninja", "tank", "hook", "hunter"]
const MIN_COVER := {"ninja": 0.10, "tank": 0.05, "hook": 0.08, "hunter": 0.05} # 마스크 넓이 (텍셀 비율) — 칸 >= 5%
const EDGE_MAX := 0.25 # 가장자리 (0.05~0.95) 텍셀 ÷ 칸 텍셀 — 꼭짓점 판정의 경계 삼각형 32~55% 보다 한참 아래


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _body(ch: String, level: String):
	var Gfx = load("res://world/gfx.gd")
	var was_plan = Gfx.plan
	Gfx.plan = {"level": level}
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	Gfx.plan = was_plan
	return b


func test_skin_mask_files() -> void:
	for id in IDS:
		var txt := FileAccess.get_file_as_string("res://assets/models/ext/%s.json" % id)
		var d = JSON.parse_string(txt)
		check(d is Dictionary and d.has("skin_mask"), "%s.json 에 skin_mask" % id)
		if not (d is Dictionary and d.has("skin_mask")):
			continue
		var seen := {}
		for node in d.skin_mask:
			var p: String = d.skin_mask[node]
			check(ResourceLoader.exists(p), "%s 마스크 파일 %s" % [id, p])
			if seen.has(p):
				continue
			seen[p] = true
			var tex := load(p) as Texture2D
			if tex == null:
				check(false, "%s 못 읽음" % p)
				continue
			var im := tex.get_image()
			check(im.get_width() == 1024 and im.get_height() == 1024, "%s 1024² (%dx%d)" % [p, im.get_width(), im.get_height()])
			im.decompress() if im.is_compressed() else null
			var tot := 0.0
			var edge := 0.0
			var step := 4 # 4칸마다 (속도)
			var n := 0
			for y in range(0, im.get_height(), step):
				for x in range(0, im.get_width(), step):
					var v := im.get_pixel(x, y).r
					tot += v
					n += 1
					if v > 0.05 and v < 0.95:
						edge += 1.0
			var cover := tot / n
			check(cover >= MIN_COVER[id], "%s 칸 넓이 %.3f >= %.2f" % [p, cover, MIN_COVER[id]])
			var ratio := edge / maxf(tot, 1.0)
			check(ratio <= EDGE_MAX, "%s 경계 텍셀 비율 %.3f <= %.2f" % [p, ratio, EDGE_MAX])


# 판 몸 3단계 LOD 모두 몸 색 재질이 마스크 텍스처를 쓰고, 마스크 재질 수는 늘지 않음 (몸 하나당 표면 재질 = 이전과 같은 수)
func test_skin_mask_in_body_all_levels() -> void:
	for id in IDS:
		for lv in ["high", "medium", "low"]:
			var b = _body(id, lv)
			var used := 0
			var plain := 0
			for mi in b.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).material_override as ShaderMaterial
				if m == null or not m.get_shader_parameter("skin_multiply"):
					continue
				if m.get_shader_parameter("use_skin_mask") == true and m.get_shader_parameter("skin_mask_tex") != null:
					used += 1
				else:
					plain += 1
			check(used >= 1 and plain == 0, "%s %s: 마스크 텍스처 쓰는 몸 재질 %d, 꼭짓점 판정 %d" % [id, lv, used, plain])
			b.free()


# 마스크 없는 재질은 예전 그대로 (use_skin_mask 꺼짐)
func test_toon_for_without_mask_unchanged() -> void:
	var m: ShaderMaterial = Ext.Ext.toon_for(Color.WHITE, null, true, true, Color.RED)
	check(m.get_shader_parameter("use_skin_mask") != true, "마스크 안 주면 꼭짓점 판정")
	var t := load("res://assets/models/ext/ninja_mask_lod1.png") as Texture2D
	var m2: ShaderMaterial = Ext.Ext.toon_for(Color.WHITE, null, true, true, Color.RED, {"skin_mask": t})
	check(m2.get_shader_parameter("use_skin_mask") == true, "마스크를 주면 텍스처 판정")


# ---- 2. 발 미끄러짐 (보폭 늘리기 IK + 박자 배율) ----
func test_leg_ik_pure() -> void:
	var P := Vector3(0, 0.45, 0)
	var K := Vector3(0.05, 0.25, 0)
	var F := Vector3(0, 0.02, 0)
	var l1 := P.distance_to(K)
	var l2 := K.distance_to(F)
	for tx in [-0.3, -0.1, 0.0, 0.2, 0.3, 0.9]: # 마지막은 닿을 수 없음 → 가장 먼 자리까지
		var T := Vector3(tx, 0.02, 0)
		var r := Ext.Ext.leg_ik(P, K, F, T, Vector3(1, 0, 0))
		check(absf(P.distance_to(r.knee) - l1) < 1e-4, "허벅지 길이 유지 (T.x %.1f)" % tx)
		check(absf((r.knee as Vector3).distance_to(r.foot) - l2) < 1e-4, "정강이 길이 유지 (T.x %.1f)" % tx)
		check((r.knee as Vector3).x >= minf(P.x, (r.foot as Vector3).x) - 1e-4, "무릎이 앞쪽 (T.x %.1f)" % tx)
		if P.distance_to(T) < (l1 + l2) * 0.999:
			check((r.foot as Vector3).distance_to(T) < 1e-3, "닿을 수 있으면 발이 목표에 (T.x %.1f)" % tx)
		else:
			check(P.distance_to(r.foot) <= (l1 + l2) * 0.9991, "못 닿으면 다리 길이까지만")


# 걷기·달리기 한 바퀴 동안 접지 발이 뒤로 가는 거리 ÷ (박자 배율을 반영한 코드 위상 한 바퀴 거리) — W33 측정 0.24~0.39 → 0.4 이상
func test_foot_slide_ratio() -> void:
	var old := {"ninja": 0.37, "tank": 0.28, "hunter": 0.39, "hook": 0.33} # W33 달리기
	for ch in IDS:
		var b = _body(ch, "high")
		var X = b.ext
		var sk: Skeleton3D = X.sk
		var sc := 1.0 # 뼈대 공간 → 몸 (m): 트리 밖이라 지역 크기를 몸까지 곱함
		var nd: Node = sk
		while nd != null and nd != b:
			if nd is Node3D:
				sc *= (nd as Node3D).transform.basis.get_scale().x
			nd = nd.get_parent()
		var need0: float = TAU / (C.ANIM_WALK_FREQ * float(Pose.gait_of(ch).freq))
		for nm in ["walk", "run"]:
			var sd = X.info.cfg.clips.stride.get(nm)
			check(sd is Array and sd.size() == 3 and float(sd[0]) > 1.0 and float(sd[2]) >= 1.0, "%s %s stride [k, c, 박자]" % [ch, nm])
			if not (sd is Array):
				continue
			var need: float = need0 / float(sd[2])
			var fR := sk.find_bone("mixamorig_RightFoot")
			var fL := sk.find_bone("mixamorig_LeftFoot")
			var travel := 0.0
			var prev := Vector3.ZERO
			var had := false
			var prev_st := -1
			var n := 60
			for i in n + 1:
				var t: float = float(X.clipset[nm].len) * float(i) / n
				X.preview_clip(nm, t)
				X.fade_t = 1.0
				X.preview_clip(nm, t)
				var pr: Vector3 = X._gt(fR).origin
				var pl: Vector3 = X._gt(fL).origin
				var stance: int = 0 if pr.y <= pl.y else 1
				var cur: Vector3 = pr if stance == 0 else pl
				if had and stance == prev_st:
					travel += -(cur.x - prev.x)
				prev = cur
				prev_st = stance
				had = true
			var ratio: float = travel * sc / need
			check(ratio >= 0.4, "%s %s 발 미끄러짐 비 %.2f >= 0.4 (W33 %s)" % [ch, nm, ratio, "달리기 %.2f" % old[ch]])
		b.free()


# 박자 배율: 같은 몸 속도 (코드 걸음 위상) 에서 클립이 배율만큼 더 돌고, 배율 1 이면 예전 그대로
func test_clip_rate_scales_phase() -> void:
	var st := {"air": false, "walking": true, "hs": 4.5, "walk": 1.0, "vz": 0.0, "t": 1.0, "stunned": false, "emote": -1, "victory": -1.0, "hit": null, "act": null,
		"tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "dizzy": 0.0, "whirl": -1.0, "glide": false}
	var cc := {"walk": "walk", "run": "run", "run_speed": 4.5, "run_from": 0.55}
	var a := Clips.select(cc, st, 0.0)
	cc["stride"] = {"run": [1.4, -0.1, 1.5]}
	var b := Clips.select(cc, st, 0.0)
	check(absf(float(a.t) - fposmod(1.0 / TAU, 1.0)) < 1e-5, "stride 없으면 위상 그대로")
	check(absf(float(b.t) - fposmod(1.5 / TAU, 1.0)) < 1e-5, "박자 1.5 배 (%.3f)" % float(b.t))


# ---- 3. 공중 대시 손목 (무기가 팔과 직각으로 솟던 것) ----
func test_dash_wrist() -> void:
	var st := {"air": true, "walking": false, "hs": 4.5, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "emote": -1, "victory": -1.0, "hit": null, "act": null,
		"tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "dizzy": 0.0, "whirl": -1.0, "glide": false}
	for ch in ["tank", "hunter", "ninja", "hook"]:
		var b = _body(ch, "high")
		var X = b.ext
		var dw: Dictionary = X.info.cfg.get("dash_wrist", {})
		check(dw.is_empty() == (ch in ["ninja", "hook"]), "%s dash_wrist 있음 여부 (무기가 쥔 해머·소총만)" % ch)
		var hb: int = int(X.info.map.get("hand_R", -1))
		X.sync(st)
		var q0: Quaternion = X.sk.get_bone_pose_rotation(hb)
		st.airDash = 1.0
		X.sync(st)
		var q1: Quaternion = X.sk.get_bone_pose_rotation(hb)
		st.airDash = 0.0
		var ang := rad_to_deg(q0.angle_to(q1))
		if dw.has("hand_R"):
			var a: Array = dw.hand_R
			var want := rad_to_deg(Quaternion.from_euler(Vector3(deg_to_rad(a[0]), deg_to_rad(a[1]), deg_to_rad(a[2]))).get_angle())
			X.info.cfg["dash_wrist"] = {} # 같은 대시 자세에서 손목 보정만 뺌 → 차이 = 설정한 각
			st.airDash = 1.0
			X.sync(st)
			var q2: Quaternion = X.sk.get_bone_pose_rotation(hb)
			st.airDash = 0.0
			X.info.cfg["dash_wrist"] = dw # 캐시된 설정을 되돌림
			var diff := rad_to_deg(q1.angle_to(q2))
			check(absf(diff - want) < 2.0, "%s 대시 손목 보정 %.1f도 (설정 %.1f)" % [ch, diff, want])
			check(ang > 20.0, "%s 대시에서 손뼈가 돌아감 (%.0f)" % [ch, ang])
		b.free()


# ---- 4. 사냥꾼 1인칭 소총 ----
func test_hunter_vm_rifle() -> void:
	var was: bool = Body.use_ext
	Body.use_ext = true
	var tw = Body.new()
	tw.build("hunter", Color(0.2, 0.5, 1.0), true) # 판 몸 (3인칭): 소총이 몸 메시에 있으니 따로 안 붙임
	var vm = Body.new()
	vm.build("hunter", Color(0.2, 0.5, 1.0), false) # 1인칭 쌍둥이
	Body.use_ext = was
	var n3 := 0
	for ba in tw.find_children("*", "BoneAttachment3D", true, false):
		n3 += ba.find_children("*", "MeshInstance3D", true, false).size()
	check(n3 == 0, "판 몸에는 소총 소품 없음 (몸에 있음) — %d" % n3)
	var rifles := []
	for ba in vm.find_children("*", "BoneAttachment3D", true, false):
		for mi in ba.find_children("*", "MeshInstance3D", true, false):
			rifles.append(mi)
	check(rifles.size() == 1, "1인칭 쌍둥이에 소총 하나 — %d" % rifles.size())
	if rifles.size() == 1:
		var m: Mesh = (rifles[0] as MeshInstance3D).mesh
		var tris: int = (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		check(tris >= 300 and tris <= 900, "소총 삼각형 300~900 (%d)" % tris)
		var bb: AABB = m.get_aabb()
		check(bb.size.length() > 0.25 and bb.size.length() < 0.7, "소총 길이 0.25~0.7 m (%.2f)" % bb.size.length())
		check(not (rifles[0] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "1인칭 소총은 그림자 없음")
	tw.free()
	vm.free()


# ---- 5. 탱크 1인칭 방패 크기 ----
func test_tank_vm_shield_scale() -> void:
	var was: bool = Body.use_ext
	Body.use_ext = true
	var vm = Body.new()
	vm.build("tank", Color(0.2, 0.5, 1.0), false)
	var tw = Body.new()
	tw.build("tank", Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	var bn := "mixamorig_LeftForeArm"
	var want: float = float((vm.ext.info.cfg.get("vm_bone_scale", {}) as Dictionary).get(bn, 1.0))
	check(want < 1.0 and want >= 0.45, "tank.json vm_bone_scale 왼 아래팔 0.45~1 (%.2f)" % want)
	vm.ext.sync()
	tw.ext.sync()
	var sv: float = vm.ext.sk.get_bone_pose_scale(vm.ext.sk.find_bone(bn)).x
	var st: float = tw.ext.sk.get_bone_pose_scale(tw.ext.sk.find_bone(bn)).x
	check(absf(sv / st - want) < 0.02, "1인칭 왼 아래팔이 판 몸의 %.2f 배 (%.3f / %.3f)" % [want, sv, st])
	vm.ext.sync() # 여러 번 불러도 누적해서 줄지 않음
	var sv2: float = vm.ext.sk.get_bone_pose_scale(vm.ext.sk.find_bone(bn)).x
	check(absf(sv2 - sv) < 1e-4, "배율이 누적되지 않음 (%.3f → %.3f)" % [sv, sv2])
	var hn := "mixamorig_RightForeArm" # 해머 쥔 오른팔은 그대로
	check(absf(vm.ext.sk.get_bone_pose_scale(vm.ext.sk.find_bone(hn)).x / tw.ext.sk.get_bone_pose_scale(tw.ext.sk.find_bone(hn)).x - 1.0) < 0.02, "오른팔 크기 그대로")
	vm.free()
	tw.free()
