# W14 외부 뼈대 모델 (chars/external.gd, 안내 chars/EXTERNAL.md):
# ① 뼈 이름 자동 매칭 (Mixamo·Quaternius/Rigify·언리얼·Biped·Meshy/Tripo 식) + 덮어쓰기 + 골반 고침 ② 시험 로봇 (assets/models/ext/robot_test.glb — W19 부터 탱크 자리에 끼워 봄) 정보
# ③ 판 몸: 외부 모델이 붙고 안쪽 몸은 안 그림, 키·발바닥, 관절을 돌리면 뼈 방향이 우리 팔다리 방향을 따라감 (스킨 메시 하나짜리 합성 모델로도)
# ④ 3단: 외부 → 구운 → 코드 조립 (외부를 끄거나 없는 캐릭터면 예전 그대로, 구운 몸을 꺼도 외부가 붙음)
# ⑤ 반투명·번쩍·한 겹 더 ⑥ 1인칭 팔 쌍둥이 (팔 메시만, 허리 아래에 붙음) ⑦ 래그돌이 켜지고 뼈가 래그돌 자세를 따라감 ⑧ 클립 재생
extends RefCounted

const C := preload("res://core/config.gd")
const K := preload("res://chars/chars_config.gd")
const Body := preload("res://chars/body.gd")
const Ext := preload("res://chars/external.gd")
const RagW := preload("res://chars/ragdoll.gd")
const VM_ := preload("res://chars/viewmodel.gd")
const Chars := preload("res://chars/chars.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 시험 로봇 (robot_test.glb) 을 탱크 자리에 끼워 몸을 만듦 (W19 부터 tank.glb = Blender 탱크)
func _robot_body(merge := true, ext := true, glb := true):
	var prev = Ext.load_char("tank")
	Ext._cache["tank"] = Ext.load_char("robot_test")
	var b = _body("tank", merge, ext, glb)
	Ext._cache["tank"] = prev
	return b


func _body(ch: String, merge := true, ext := true, glb := true):
	var was_e: bool = Body.use_ext
	var was_g: bool = Body.use_glb
	Body.use_ext = ext
	Body.use_glb = glb
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), merge)
	Body.use_ext = was_e
	Body.use_glb = was_g
	return b


# 이름 목록 → 매칭 결과를 이름으로
static func _names(list: Array, overrides := {}, parents := PackedInt32Array()) -> Dictionary:
	var names := PackedStringArray(list)
	var m := Ext.match_bones(names, overrides, parents)
	var out := {}
	for k in m:
		out[k] = names[m[k]]
	return out


func _expect(conv: String, got: Dictionary, want: Dictionary) -> void:
	for k in want:
		check(got.get(k) == want[k], "%s %s → %s (얻음 %s)" % [conv, k, want[k], got.get(k)])


func test_normalize() -> void:
	var cases := {"mixamorig_LeftForeArm": ["forearm", "L"], "mixamorig1:RightUpLeg": ["upleg", "R"], "upperarm_l": ["upperarm", "L"], "UpperArm.R": ["upperarm", "R"],
		"Bip01 L Thigh": ["thigh", "L"], "DEF-upper_arm.L": ["upperarm", "L"], "Head_2": ["head2", ""], "spine_01": ["spine01", ""], "L_Hand": ["hand", "L"],
		"hand.r": ["hand", "R"], "Armature|Hips": ["hips", ""], "leftarm": ["arm", "L"], "LeftHandThumb1": ["handthumb1", "L"], "Left_Foot": ["foot", "L"], "mixamorig_LeftArm": ["arm", "L"]}
	for n in cases:
		var r: Dictionary = Ext.normalize(n)
		check(r.core == cases[n][0] and r.side == cases[n][1], "정리 %s → %s %s (얻음 %s %s)" % [n, cases[n][0], cases[n][1], r.core, r.side])


func test_match_conventions() -> void:
	# Mixamo (빗장 LeftShoulder 는 안 씀, 팔 = LeftArm)
	var mix := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head", "mixamorig_LeftShoulder", "mixamorig_LeftArm",
		"mixamorig_LeftForeArm", "mixamorig_LeftHand", "mixamorig_LeftHandThumb1", "mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
		"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase", "mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot"]
	_expect("Mixamo", _names(mix), {"hips": "mixamorig_Hips", "waist": "mixamorig_Spine", "torso": "mixamorig_Spine2", "neck": "mixamorig_Neck",
		"shoulder_L": "mixamorig_LeftArm", "elbow_L": "mixamorig_LeftForeArm", "hand_L": "mixamorig_LeftHand", "shoulder_R": "mixamorig_RightArm", "elbow_R": "mixamorig_RightForeArm",
		"hand_R": "mixamorig_RightHand", "thigh_L": "mixamorig_LeftUpLeg", "knee_L": "mixamorig_LeftLeg", "foot_L": "mixamorig_LeftFoot", "thigh_R": "mixamorig_RightUpLeg",
		"knee_R": "mixamorig_RightLeg", "foot_R": "mixamorig_RightFoot"})
	# Quaternius·블렌더 (.L/.R)
	var qua := ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L", "Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R",
		"UpperLeg.L", "LowerLeg.L", "Foot.L", "Toes.L", "UpperLeg.R", "LowerLeg.R", "Foot.R"]
	_expect("Quaternius", _names(qua), {"hips": "Hips", "waist": "Spine", "torso": "Chest", "neck": "Neck", "shoulder_L": "UpperArm.L", "elbow_L": "LowerArm.L", "hand_L": "Hand.L",
		"shoulder_R": "UpperArm.R", "elbow_R": "LowerArm.R", "hand_R": "Hand.R", "thigh_L": "UpperLeg.L", "knee_L": "LowerLeg.L", "foot_L": "Foot.L", "foot_R": "Foot.R"})
	# 언리얼 마네킹
	var ue := ["root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
		"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r"]
	_expect("언리얼", _names(ue), {"hips": "pelvis", "waist": "spine_01", "torso": "spine_02", "neck": "neck_01", "shoulder_L": "upperarm_l", "elbow_R": "lowerarm_r", "hand_L": "hand_l",
		"thigh_R": "thigh_r", "knee_L": "calf_l", "foot_R": "foot_r"})
	# 3ds Max Biped
	var bip := ["Bip01", "Bip01 Pelvis", "Bip01 Spine", "Bip01 Spine1", "Bip01 Neck", "Bip01 Head", "Bip01 L Clavicle", "Bip01 L UpperArm", "Bip01 L Forearm", "Bip01 L Hand",
		"Bip01 R Clavicle", "Bip01 R UpperArm", "Bip01 R Forearm", "Bip01 R Hand", "Bip01 L Thigh", "Bip01 L Calf", "Bip01 L Foot", "Bip01 R Thigh", "Bip01 R Calf", "Bip01 R Foot"]
	_expect("Biped", _names(bip), {"hips": "Bip01 Pelvis", "waist": "Bip01 Spine", "torso": "Bip01 Spine1", "neck": "Bip01 Neck", "shoulder_R": "Bip01 R UpperArm",
		"elbow_L": "Bip01 L Forearm", "hand_R": "Bip01 R Hand", "thigh_L": "Bip01 L Thigh", "knee_R": "Bip01 R Calf", "foot_L": "Bip01 L Foot"})
	# Meshy·Tripo 자동 뼈 식 (Mixamo 이름 + 접두어 없음·소문자 섞임, 숫자 붙은 척추)
	var meshy := ["Hips", "Spine", "Spine01", "Spine02", "neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
	_expect("Meshy", _names(meshy), {"hips": "Hips", "waist": "Spine", "torso": "Spine02", "neck": "neck", "shoulder_L": "LeftArm", "elbow_R": "RightForeArm", "knee_L": "LeftLeg"})
	var tripo := ["pelvis", "spine", "chest", "neck", "head", "L_Clavicle", "L_Upperarm", "L_Forearm", "L_Hand", "R_Clavicle", "R_Upperarm", "R_Forearm", "R_Hand",
		"L_Thigh", "L_Calf", "L_Foot", "R_Thigh", "R_Calf", "R_Foot"]
	_expect("Tripo", _names(tripo), {"hips": "pelvis", "waist": "spine", "torso": "chest", "shoulder_L": "L_Upperarm", "elbow_L": "L_Forearm", "hand_R": "R_Hand", "knee_R": "R_Calf"})


func test_match_override_and_pelvis() -> void:
	var qua := ["Hips", "Spine", "Chest", "Neck", "UpperArm.L", "LowerArm.L", "Hand.L", "UpperArm.R", "LowerArm.R", "Hand.R", "UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R", "Weapon"]
	var got := _names(qua, {"hand_R": "Weapon", "neck": ""})
	check(got.get("hand_R") == "Weapon" and not got.has("neck"), "덮어쓰기 (손 → Weapon, 목 안 씀): %s" % [got])
	check(got.get("hand_L") == "Hand.L", "덮어쓰지 않은 건 자동")
	# 로봇 모델 모양: 다리가 Hips 가 아니라 그 부모 Body 아래 → 골반 = 두 허벅지·허리의 공통 조상
	var names := ["Bone", "Body", "Hips", "Abdomen", "Torso", "UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R", "Foot.L", "Foot.R"]
	var parents := PackedInt32Array([-1, 0, 1, 2, 3, 1, 5, 1, 7, 0, 0])
	var r := _names(names, {}, parents)
	check(r.get("hips") == "Body" and r.get("waist") == "Abdomen", "골반 고침 Body (얻음 %s)" % [r])


func test_robot_info() -> void:
	var info = Ext.load_char("robot_test")
	check(info != null, "시험 로봇 robot_test.glb 읽음")
	if info == null:
		return
	for j in Ext.JOINTS:
		check(info.map.has(j), "로봇 관절 %s" % j)
	check(info.names[info.map.hips] == "Body" and info.names[info.map.hand_L] == "Palm2.L" and info.names[info.map.foot_R] == "Foot.R", "로봇 골반·손·발 뼈")
	check((info.box as AABB).size.y > 0.0 and info.surfs.size() >= 14, "상자·표면 %d" % info.surfs.size())
	check(info.anims.has("Wave") and info.anims.has("Dance"), "로봇 클립")
	check(Ext.load_char("dummy") == null and Ext.load_char("없는캐릭터") == null and not Ext.has_char("bard"), "없는 캐릭터는 null")
	check(info.cfg.get("keep") == ["shields"] and info.cfg.get("tint") == "band" and float(info.cfg.yaw) == 90.0, "robot_test.json 덮음 + 기본 값")


# 뼈 b 의 몸 (body) 기준 전역 자리
static func _bone_pos(b, bi: int) -> Vector3:
	var e = b.ext
	return e._body_rel(e.sk) * _global(e.sk, bi).origin


# 뼈 전역 자세를 지역 자세로 직접 곱함 (트리 밖 Skeleton3D 는 get_bone_global_pose 가 한 번 셈한 뒤 안 갱신됨 — 판에선 그리기 전에 갱신)
static func _global(sk: Skeleton3D, bi: int) -> Transform3D:
	var t := sk.get_bone_pose(bi)
	var p := sk.get_bone_parent(bi)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t


static func _jpos(b, n: Node3D) -> Vector3:
	return b.ext._body_rel(n).origin


# 뼈 a→c 방향과 우리 관절 ja→jc 방향 사이 각 (도)
static func _dir_err(b, ja: String, jc: String) -> float:
	var info: Dictionary = b.ext.info
	var db: Vector3 = _bone_pos(b, info.map[jc]) - _bone_pos(b, info.map[ja])
	var dj: Vector3 = _jpos(b, b.ext._joint(jc)) - _jpos(b, b.ext._joint(ja))
	return rad_to_deg(db.angle_to(dj))


func _check_follow(b, tag: String) -> void:
	# 쉬는 자세 (T 포즈 모델 → 우리 내린 팔): 팔·다리 뼈 방향 = 우리 관절 방향
	var worst := 0.0
	for pair in [["shoulder_L", "elbow_L"], ["elbow_L", "hand_L"], ["shoulder_R", "elbow_R"], ["thigh_R", "knee_R"], ["knee_L", "foot_L"]]:
		worst = maxf(worst, _dir_err(b, pair[0], pair[1]))
	check(worst < 2.0, "%s 쉬는 자세 뼈 방향 %.2f°" % [tag, worst])
	# 팔을 앞으로 들고 무릎을 굽힘 (figureAnim 이 하는 관절 회전) → 뼈가 따라감
	b.P.shFwd = [1.4, 0.3]
	b.P.elbow = [1.2, 0.2]
	b.P.thFwd = [0.9, 0.0]
	b.P.knee = [1.3, 0.0]
	b._apply(0.0)
	b.ext.sync()
	for pair in [["shoulder_R", "elbow_R"], ["elbow_R", "hand_R"], ["thigh_R", "knee_R"], ["knee_R", "foot_R"], ["shoulder_L", "elbow_L"]]:
		var er := _dir_err(b, pair[0], pair[1])
		check(er < 2.0, "%s 팔 들고 무릎 굽힘 뼈 방향 %s %.2f°" % [tag, pair, er])
	var hand_up: float = _bone_pos(b, b.ext.info.map.hand_R).y - _bone_pos(b, b.ext.info.map.elbow_R).y
	check(hand_up > -0.05, "%s 앞으로 든 손 (팔꿈치보다 아래로 안 처짐 %.3f)" % [tag, hand_up])


func test_body_ext() -> void:
	var b = _robot_body()
	check(b.ext != null and b.ext.get_parent() == b.frame, "외부 모델 붙음 (frame 아래)")
	if b.ext == null:
		b.free()
		return
	check(b.merged_count == 1 and b.batch == null, "판 몸: 안쪽은 조각 몸 (묶음 없음), 래그돌용 합친 수 1")
	var ext_n := 0
	var kept := 0
	for dr in b.drawn:
		if dr.get("ext", false):
			ext_n += 1
		else:
			kept += 1
	check(ext_n >= 15 and kept >= 1, "그리는 메시: 외부 %d (표면 + 띠) · 남긴 방패 %d" % [ext_n, kept])
	var shown := 0
	for n in b.nodes:
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			shown += 1
	check(shown == kept, "안쪽 몸은 남긴 소품만 메시 (%d)" % shown)
	check(b.ext.band != null and (b.ext.band.material_override as ShaderMaterial).get_shader_parameter("albedo").is_equal_approx(Color(0.2, 0.5, 1.0)), "팀 색 띠")
	var m: ShaderMaterial = b.ext.parts[0].mi.material_override
	check(m.next_pass != null and m.get_shader_parameter("toon_steps") != null, "툰 + 외곽선")
	# 키·발바닥: 모델 상자 (쉬는 자세) 의 몸 기준 높이
	var box: AABB = b.ext.info.box
	var lo := INF
	var hi := -INF
	for c in 8:
		var p: Vector3 = b.ext._body_rel(b.ext) * box.get_endpoint(c)
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	check(absf(lo) < 1e-3 and absf(hi - C.PLAYER_HEIGHT * C.FIGURE_SCALE) < 1e-3, "발바닥 0 · 키 %.3f (얻음 %.3f~%.3f)" % [C.PLAYER_HEIGHT * C.FIGURE_SCALE, lo, hi])
	_check_follow(b, "로봇")
	# 골반: 우리 골반을 내리면 (웅크림) 모델 골반도 키 비율만큼 내려감
	var h0: float = _bone_pos(b, b.ext.info.map.hips).y
	b.hips.position.z -= 0.2
	b.ext.sync()
	var h1: float = _bone_pos(b, b.ext.info.map.hips).y
	check(h1 < h0 - 0.05, "웅크리면 골반 내려감 %.3f → %.3f" % [h0, h1])
	# 발 뼈는 (로봇은 뿌리 뼈 아래 IK 용) 우리 무릎 뼈를 따라감: 무릎을 굽히면 발이 뒤로
	var f0: Vector3 = _bone_pos(b, b.ext.info.map.foot_R)
	b.P.knee = [1.5, 0.0]
	b._apply(0.0)
	b.ext.sync()
	check(_bone_pos(b, b.ext.info.map.foot_R).distance_to(f0) > 0.05, "무릎 굽히면 발 뼈도 움직임")
	b.free()


func test_three_tiers() -> void:
	var off = _body("tank", true, false)
	check(off.ext == null and off.baked and off.batch != null, "외부 끔 → 구운 몸 (예전 그대로)")
	off.free()
	var no = _body("bard", true, true)
	check(no.ext == null, "외부 모델 없는 캐릭터는 그대로")
	no.free()
	var pieces = _robot_body(true, true, false)
	check(pieces.ext != null and not pieces.baked, "구운 몸 끔 → 코드 조립 위에 외부")
	if pieces.ext != null:
		_check_follow(pieces, "조립 위 로봇")
	pieces.free()
	var d = _body("dummy", true, true)
	check(d.ext == null, "허수아비는 외부 없음")
	d.free()


# 메시 하나짜리 스킨 모델 (Meshy·Tripo 가 주는 모양): Mixamo 이름 T 포즈, 뼈마다 쉬는 회전이 제각각
static func _synthetic() -> PackedScene:
	var root := Node3D.new()
	root.name = "Synth"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	sk.owner = root
	# [이름, 부모, 전역 자리 (Y 위, 앞 +Z, 왼쪽 +X)]
	var defs := [["mixamorig_Hips", -1, Vector3(0, 1.0, 0)], ["mixamorig_Spine", 0, Vector3(0, 1.12, 0)], ["mixamorig_Spine2", 1, Vector3(0, 1.35, 0)],
		["mixamorig_Neck", 2, Vector3(0, 1.55, 0)], ["mixamorig_Head", 3, Vector3(0, 1.65, 0)],
		["mixamorig_LeftShoulder", 2, Vector3(0.06, 1.5, 0)], ["mixamorig_LeftArm", 5, Vector3(0.18, 1.5, 0)], ["mixamorig_LeftForeArm", 6, Vector3(0.45, 1.5, 0)], ["mixamorig_LeftHand", 7, Vector3(0.7, 1.5, 0)],
		["mixamorig_RightShoulder", 2, Vector3(-0.06, 1.5, 0)], ["mixamorig_RightArm", 9, Vector3(-0.18, 1.5, 0)], ["mixamorig_RightForeArm", 10, Vector3(-0.45, 1.5, 0)], ["mixamorig_RightHand", 11, Vector3(-0.7, 1.5, 0)],
		["mixamorig_LeftUpLeg", 0, Vector3(0.1, 0.95, 0)], ["mixamorig_LeftLeg", 13, Vector3(0.1, 0.5, 0)], ["mixamorig_LeftFoot", 14, Vector3(0.1, 0.08, 0)], ["mixamorig_LeftToe", 15, Vector3(0.1, 0.02, 0.15)],
		["mixamorig_RightUpLeg", 0, Vector3(-0.1, 0.95, 0)], ["mixamorig_RightLeg", 17, Vector3(-0.1, 0.5, 0)], ["mixamorig_RightFoot", 18, Vector3(-0.1, 0.08, 0)], ["mixamorig_RightToe", 19, Vector3(-0.1, 0.02, 0.15)]]
	var globals: Array[Transform3D] = []
	for i in defs.size():
		var rot := Basis(Vector3(sin(i * 1.3), cos(i * 0.7), 0.5).normalized(), 0.4 * i) # 제각각 쉬는 회전
		var g := Transform3D(rot, defs[i][2])
		globals.append(g)
		sk.add_bone(defs[i][0])
		if defs[i][1] >= 0:
			sk.set_bone_parent(i, defs[i][1])
		var par: Transform3D = globals[defs[i][1]] if defs[i][1] >= 0 else Transform3D.IDENTITY
		sk.set_bone_rest(i, par.affine_inverse() * g)
	sk.reset_bone_poses()
	# 메시: 뼈 → 자식 뼈 막대 (정점은 그 뼈에 무게 1)
	var vs := PackedVector3Array()
	var bones := PackedInt32Array()
	var ws := PackedFloat32Array()
	var skin := Skin.new()
	for i in defs.size():
		skin.add_bind(i, globals[i].affine_inverse())
	for i in defs.size():
		var par: int = defs[i][1]
		if par < 0:
			continue
		var a: Vector3 = defs[par][2]
		var c: Vector3 = defs[i][2]
		var side := (c - a).cross(Vector3(0.3, 0.2, 1.0)).normalized() * 0.04
		for t in [[a - side, a + side, c + side], [a - side, c + side, c - side]]:
			for v in t:
				vs.append(v)
				bones.append_array([par, 0, 0, 0])
				ws.append_array([1.0, 0.0, 0.0, 0.0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = ws
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.3, 0.2)
	am.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = am
	mi.skin = skin
	sk.add_child(mi)
	mi.owner = root
	mi.skeleton = NodePath("..")
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps


func test_synthetic_skinned() -> void:
	var cfg := Ext.read_cfg("없는캐릭터")
	cfg.tint = "keep"
	var info = Ext.model_info(_synthetic(), cfg)
	check(info != null, "합성 스킨 모델 정보")
	if info == null:
		return
	check(info.names[info.map.shoulder_L] == "mixamorig_LeftArm" and info.names[info.map.torso] == "mixamorig_Spine2", "합성 모델 매칭")
	check(info.surfs.size() == 1 and info.surfs[0].skinned, "스킨 메시 하나")
	var vm = info.surfs[0].vm_mesh
	var tri: int = (vm as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3 if vm != null else 0
	check(tri == 2 * 2, "1인칭 팔 메시 = 팔꿈치 아래 막대 (양쪽 아래팔→손 막대 1개씩 × 삼각형 2, 얻음 %d)" % tri)
	Ext._cache["ninja"] = info # 닌자 자리에 끼워 봄 (조립 길)
	var b = _body("ninja")
	check(b.ext != null and b.ext.band == null, "합성 모델 붙음 (keep: 띠 없음)")
	if b.ext != null:
		_check_follow(b, "합성")
		var m: ShaderMaterial = b.ext.parts[0].mi.material_override
		check(m.get_shader_parameter("albedo").is_equal_approx(Color(0.8, 0.3, 0.2)), "원래 알베도 색 그대로 (keep)")
	b.free()
	Ext._cache.erase("ninja")


func test_ext_fx() -> void:
	var b = _robot_body()
	if b.ext == null:
		check(false, "외부 모델 없음")
		b.free()
		return
	var mi: MeshInstance3D = b.ext.parts[0].mi
	var solid = mi.material_override
	b.ext.fx([b.skin_color, Color(0, 0, 0), Color(0, 0, 0)], 0.5)
	check(mi.material_override != solid and (mi.material_override as ShaderMaterial).get_shader_parameter("albedo").a == 0.5, "반투명 재질")
	b.ext.fx([b.skin_color, Color(0, 0, 0), Color(0, 0, 0)], 1.0)
	check(mi.material_override == solid, "반투명 끝")
	b.ext.fx([Color.WHITE, Color(0, 0, 0), Color(0, 0, 0)], 1.0)
	var e: Color = (mi.material_override as ShaderMaterial).get_shader_parameter("emissive")
	check(e.r >= K.EXT_FLASH - 1e-4, "경직 하얀 깜빡임 = 하얀 발광 %s" % e)
	b.ext.fx([b.skin_color, Color(0.4, 0.2, 0), Color(0, 0, 0)], 1.0)
	check((mi.material_override as ShaderMaterial).get_shader_parameter("emissive").is_equal_approx(Color(0.4, 0.2, 0)), "스킬 빛 발광")
	# 판 흐름 (pose): 유령화 반투명 → 외부 재질도
	for i in 3:
		b.pose({"id": 1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "ghostLeft": 500.0}, i * 16.0)
	check(b.opacity < 1.0 and mi.material_override != solid, "유령화면 외부 몸도 반투명")
	var ov := StandardMaterial3D.new()
	b.set_overlay(ov)
	check(mi.material_overlay == ov, "한 겹 더")
	b.free()


func test_ext_viewmodel_twin() -> void:
	var t = _robot_body(false)
	check(t.ext != null and t.ext.get_parent() == t.waist and not t.ext.third, "1인칭 쌍둥이: 허리 관절 아래")
	if t.ext == null:
		t.free()
		return
	var n := 0
	for dr in t.drawn:
		if dr.get("ext", false):
			n += 1
			check(dr.mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "1인칭 팔 그림자 없음")
	check(n >= 2 and n < t.ext.info.surfs.size(), "팔 메시만 %d (전체 표면 %d)" % [n, t.ext.info.surfs.size()])
	# viewmodel 처럼 허리를 떼어 다른 노드에 붙여도 팔꿈치 뼈 = 우리 팔꿈치 관절 자리 (vm_snap)
	var anchor := Node3D.new()
	t.waist.get_parent().remove_child(t.waist)
	anchor.add_child(t.waist)
	t.shoulders[0].rotation = Vector3(0.3, -1.0, 0)
	t.ext.sync()
	var eb: Vector3 = t.ext.W * _global(t.ext.sk, t.ext.info.map.elbow_R).origin
	var ej: Vector3 = t.ext._rel(t.elbows[0]).origin
	check(eb.distance_to(ej) < 1e-3, "1인칭 팔꿈치 뼈 = 우리 팔꿈치 %s / %s" % [eb, ej])
	anchor.free()
	t.free()


func test_ext_ragdoll() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var w = RagW.new()
	w.name = "TfRagdollsExtTest"
	root.add_child(w)
	RagW._inst = w
	var b = _robot_body()
	b.rag_test = true
	root.add_child(b)
	var p := {"id": -2, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}
	b.pose(p, 0.0)
	check(w.has(b), "외부 몸도 래그돌 켬 (%s)" % b.rag_why)
	# 래그돌이 관절을 쓰러뜨린 자세 → 뼈가 따라감 (관절에 바로 넣어 봄)
	b.thighs[0].rotation = Vector3(0.4, -1.2, 0.2)
	b.waist.rotation = Vector3(0.3, 0.8, 0.1)
	b.ext.sync()
	var worst := 0.0
	for pair in [["thigh_R", "knee_R"], ["shoulder_L", "elbow_L"], ["elbow_R", "hand_R"]]:
		worst = maxf(worst, _dir_err(b, pair[0], pair[1]))
	check(worst < 2.0, "래그돌 자세 뼈 방향 %.2f°" % worst)
	root.remove_child(b)
	b.free()
	check(w.rags.is_empty(), "몸을 지우면 래그돌 끔")
	RagW._inst = null
	w.free()


func test_ext_clip() -> void:
	var b = _robot_body()
	if b.ext == null:
		check(false, "외부 모델 없음")
		b.free()
		return
	var sk: Skeleton3D = b.ext.sk
	var bi: int = b.ext.info.map.shoulder_R
	var q0: Quaternion = sk.get_bone_pose_rotation(bi)
	check(not b.ext.play_clip("없는클립") and b.ext.clip == "", "없는 클립은 안 됨")
	check(b.ext.play_clip("Wave") and b.ext.clip == "Wave", "클립 재생")
	b.ext.anim.advance(0.6)
	var q1: Quaternion = sk.get_bone_pose_rotation(bi)
	b.ext.sync() # 클립 중엔 뼈 맞추기 쉼
	check(sk.get_bone_pose_rotation(bi).is_equal_approx(q1), "클립 중 뼈 맞추기 안 함")
	b.ext.stop_clip()
	check(b.ext.clip == "" and sk.get_bone_pose_rotation(bi).is_equal_approx(q0), "클립 끝 → 다시 관절 따라감")
	b.free()


# ---------- W19 Blender 탱크 (tools/blender/build_character.py tank → assets/models/ext/tank.glb·tank_shield.glb·tank.json) ----------

func test_matches_our_names() -> void:
	# 우리 관절 이름 그대로인 뼈대: 이름이 같은 뼈를 먼저 (별칭 표에 shoulder·waist 가 없어도)
	var ours := PackedStringArray(Ext.JOINTS)
	var got := _names(Array(ours))
	for j in Ext.JOINTS:
		check(got.get(j) == j, "우리 이름 그대로 %s (얻음 %s)" % [j, got.get(j)])
	# Rigify 처럼 'torso' 조종 뼈가 있어도 우리 이름 모델이 아니면 예전 별칭 순서 (chest 먼저)
	var rig := _names(["hips", "spine", "chest", "torso", "neck", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"])
	check(rig.get("torso") == "chest", "Rigify 식은 그대로 (torso → chest, 얻음 %s)" % rig.get("torso"))



# W19 고퀄 탱크 (tools/blender): 뼈 = 우리 관절 이름, LOD 4 (stage·high·medium·low 메시 노드), 몸 = 구운 알베도 텍스처 + 몸 색 칸 (UV2) 일부만, 얼굴 = 표정 텍스처
func _lod_surfs(info: Dictionary, node: String) -> Array:
	var out := []
	for sf in info.surfs:
		if str(sf.get("node", "")) == node:
			out.append(sf)
	return out


func _tris(m: Mesh) -> int:
	return (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


# W22 자동 리깅 탱크 (스킨 메시 하나 + Mixamo 식 뼈 65, tools/blender/tripo/rig_tank_auto.py): 방패 (왼팔)·해머 (오른손) 가 몸 메시에 붙어 있음 (원본은 좌우 반대라 뒤집음)
func test_blender_tank_info() -> void:
	var info = Ext.load_char("tank")
	check(info != null, "탱크 tank.glb 읽음")
	if info == null:
		return
	for j in Ext.JOINTS:
		check(info.map.has(j), "뼈 매칭 %s" % j)
	check(info.map.hips >= 0 and String(info.names[info.map.hips]).ends_with("Hips") and String(info.names[info.map.waist]).ends_with("Spine") and String(info.names[info.map.torso]).ends_with("Spine2"), "골반=Hips·허리=Spine·가슴=Spine2")
	check(String(info.names[info.map.shoulder_L]).ends_with("LeftArm") and String(info.names[info.map.elbow_R]).ends_with("RightForeArm") and String(info.names[info.map.foot_L]).ends_with("LeftFoot"), "위팔=Arm (빗장 아님)·아래팔=ForeArm·발=Foot")
	check(info.names.size() >= 60, "손가락까지 뼈 %d" % info.names.size())
	var lods: Dictionary = info.cfg.get("lods", {})
	check(lods.size() == 4 and str(lods.high) != str(lods.medium) and str(lods.medium) != str(lods.low) and str(lods.stage) != str(lods.high), "LOD: stage 하나 + 판 셋 (W31 새 UV 로 다시 구움, 메시 셋이 따로)")
	# 삼각형: 원본 1.94만 그대로 (대기실·초상·1인칭) + 판 high 5000 (W31 새 UV 로 다시 굽기 — 예전엔 UV 조각이 잘게 나뉘어 8900 밑으로 안 내려감)
	var want := {"stage": [15000, 20000], "high": [4400, 5000]}
	var stage_sf = null
	for k in want:
		var ss := _lod_surfs(info, str(lods.get(k, "")))
		var tri := 0
		var body_sf = null
		for sf in ss:
			tri += _tris(sf.mesh)
			body_sf = sf
		check(ss.size() == 1 and body_sf.skinned and body_sf.vcolor and body_sf.tex != null, "%s: 몸 표면 하나 = 스킨·꼭짓점 색 (몸 색 칸)·텍스처 (얼굴 재질 없음, 닫힌 투구)" % k)
		check(tri >= want[k][0] and tri <= want[k][1], "%s 삼각형 %d (%d~%d)" % [k, tri, want[k][0], want[k][1]])
		var st := _albedo_stats(body_sf.mesh, body_sf.tex)
		check(st[1] > 0.03 and st[1] < 0.35, "%s 몸 색 칸 넓이 %.0f%% (3~35%% — 붉은 목도리·허리 천)" % [k, st[1] * 100.0])
		if k == "stage":
			stage_sf = body_sf
	check((info.cfg.get("faces", {}) as Dictionary).is_empty(), "표정 텍스처 없음 (닫힌 투구)")
	check(info.cfg.tint == "mask" and (info.cfg.attach as Array).is_empty() and (info.cfg.keep as Array).is_empty() and str(info.cfg.get("vm_node", "")) == "tank_vm", "tank.json: mask·소품 없음 (방패·해머가 몸에 붙음), 1인칭은 닫힌 팔 tank_vm (W28, 방패·해머 포함)")
	# 방패는 캐릭터 왼쪽 (glTF -Z) 팔 뼈에, 해머는 오른쪽 (+Z) 팔 뼈에 매여 있어야 함 (게임 규칙: 방패 왼손 viewmodel, 해머 오른손 평타). 원본은 반대라 뒤집음
	if stage_sf != null:
		var arr: Array = stage_sf.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var side := {"left": 0, "right": 0}
		var wrong := 0
		for i in v.size():
			if absf(v[i].z) < 0.33 * float(info.box.size.y) / 0.98:
				continue
			var best := 0
			for k in 4:
				if bw[i * 4 + k] > bw[i * 4 + best]:
					best = k
			var bn: String = info.names[stage_sf.binds[bi[i * 4 + best]]]
			var left: bool = v[i].z < 0.0
			if bn.contains("Left") == left and (bn.contains("Left") or bn.contains("Right")):
				side["left" if left else "right"] += 1
			else:
				wrong += 1
		check(side.left > 800 and side.right > 800 and wrong < 100, "몸 바깥 (|z| > 0.33) 꼭짓점 뼈 좌우: 왼쪽 방패 %d·오른쪽 해머 %d 맞음, 어긋남 %d" % [side.left, side.right, wrong])


# 판 몸: 크기·발바닥, 뼈가 우리 관절 방향을 따라감 (팔 들기·무릎 굽힘), 몸 색 칸 = 플레이어 색, 소품 메시 없음 (방패·해머가 몸에 붙어 있음)
func test_blender_tank_body() -> void:
	var Gfx = load("res://world/gfx.gd")
	var was: Dictionary = Gfx.plan
	Gfx.plan = {} # 화질 모름 = high (앞 테스트가 바꿔 둔 값을 비움)
	var b = _body("tank")
	Gfx.plan = was
	check(b.ext != null, "탱크 붙음")
	if b.ext == null:
		b.free()
		return
	var sc: float = b.ext.transform.basis.get_scale().x
	var hh: float = (b.ext.info.box as AABB).size.y * sc
	var want_h: float = C.PLAYER_HEIGHT * C.FIGURE_SCALE * float(b.ext.info.cfg.height)
	check(absf(hh - want_h) < 0.01, "키 %.3f m = 예전 몸 키 %.3f m × height (원본 단위라 배율 %.3f)" % [hh, want_h, sc])
	for j in ["foot_R", "foot_L"]:
		var dz: float = _bone_pos(b, b.ext.info.map[j]).y - _jpos(b, b.ext._joint(j)).y
		check(absf(dz) < 0.1, "발 뼈 높이 = 우리 발 (차이 %.3f m)" % dz)
	_check_follow(b, "탱크")
	var ext_n := 0
	for dr in b.drawn:
		ext_n += 1 if dr.get("ext", false) else 0
	check(ext_n == 1 and b.drawn.size() == 1 and b.ext.band == null, "그리는 메시 1 (몸 하나 — 방패·해머 소품 없음, 코드 방패 안 남김, 얻음 %d/%d)" % [ext_n, b.drawn.size()])
	check(b.ext.find_children("*", "BoneAttachment3D", true, false).is_empty(), "손 뼈에 붙인 소품 없음")
	check(b.ext.lod == str(b.ext.info.cfg.lods.high), "판 몸 = high LOD (얻음 %s)" % b.ext.lod)
	var lods_seen := {}
	for mi in b.ext.find_children("*", "MeshInstance3D", true, false):
		lods_seen[String(mi.name).split("_s")[0]] = true
	check(not lods_seen.has(str(b.ext.info.cfg.lods.stage)), "stage LOD 메시는 없음 (%s)" % [lods_seen.keys()])
	var m: ShaderMaterial = b.ext.parts[0].mi.material_override
	check(m.get_shader_parameter("use_vertex_color") == true and m.get_shader_parameter("skin_multiply") == true and (m.get_shader_parameter("skin_tint") as Color).is_equal_approx(Color(0.2, 0.5, 1.0, 1.0)), "몸 색 칸 = 플레이어 색 곱하기")
	check(m.next_pass != null and float((m.next_pass as ShaderMaterial).get_shader_parameter("thickness")) < C.OUTLINE_THICKNESS, "외곽선 얇게 (외부 모델 outline 배율)")
	check(float(m.get_shader_parameter("rim_strength")) > 0.0, "림 빛")
	b.free()


# LOD 고르기: 1인칭 쌍둥이·대기실·초상 = stage, 판 몸 = 화질 (world/gfx.gd plan.level)
func test_blender_tank_lod() -> void:
	var Gfx = load("res://world/gfx.gd")
	var cfg := {"lods": {"stage": "a", "high": "b", "medium": "c", "low": "d"}}
	var was: Dictionary = Gfx.plan
	Gfx.plan = {}
	check(Ext.pick_lod(cfg, true, false) == "b", "화질 모름 = high")
	check(Ext.pick_lod(cfg, false, false) == "a" and Ext.pick_lod(cfg, true, true) == "a", "1인칭·대기실 = stage")
	for lv in ["high", "medium", "low"]:
		Gfx.plan = {"level": lv}
		check(Ext.pick_lod(cfg, true, false) == cfg.lods[lv], "화질 %s" % lv)
	Gfx.plan = {"level": "low"}
	var b = _body("tank")
	check(b.ext != null and b.ext.lod == str(b.ext.info.cfg.lods.low), "화질 낮음 판 몸 = low LOD")
	b.free()
	Gfx.plan = was
	Ext.stage = true
	var s = _body("tank")
	Ext.stage = false
	check(s.ext != null and s.ext.lod == str(s.ext.info.cfg.lods.stage), "대기실·초상 몸 = stage LOD")
	s.free()


# 표정: Tripo 기사는 닫힌 투구라 얼굴 재질·표정 텍스처가 없음 — 맞음·공격 상태에서도 오류 없이 idle 그대로
func test_blender_tank_face() -> void:
	var b = _body("tank")
	if b.ext == null:
		check(false, "외부 모델 없음")
		b.free()
		return
	check(b.ext.face_tex.is_empty() and b.ext.expression() == "idle", "표정 텍스처 없음 = idle 만")
	b.was_stunned = true
	b.ext.sync()
	b.was_stunned = false
	b.cur_act = {"move": "x"}
	b.ext.sync()
	b.cur_act = null
	check(b.ext.face_now == "idle" or b.ext.face_now == "", "경직·공격 중에도 오류 없음")
	b.free()


# 방패 동작: 3인칭은 몸 모델 방패가 왼팔을 따라감 (안쪽 코드 방패 노드는 비어 있음 = 겹쳐 그려지지 않음). 방패 올려치기 자세에서 방패 뼈 (왼손 끝) 가 오른쪽보다 위로 올라감
func test_blender_tank_shield() -> void:
	var b = _body("tank")
	if b.ext == null:
		check(false, "외부 모델 없음")
		b.free()
		return
	var back: Node3D = b._n(b.refs.shields.back)
	var front: Node3D = b._n(b.refs.shields.front)
	check(back.get_node_or_null("ext_shields_back") == null and front.get_node_or_null("ext_shields_front") == null, "코드 방패 노드에 소품 없음 (몸 모델 방패와 안 겹침)")
	var left: int = -1
	var right: int = -1
	for i in b.ext.info.names.size():
		var n: String = b.ext.info.names[i]
		if n.ends_with("LeftHandMiddle3"):
			left = i
		elif n.ends_with("RightHandMiddle3"):
			right = i
	check(left >= 0 and right >= 0, "손가락 뼈 둘 (방패·해머가 매인 뼈)")
	if left >= 0 and right >= 0:
		var y0: float = _bone_pos(b, left).y
		b.P.shFwd = [0.2, 2.5]
		b.P.elbow = [0.2, 0.5]
		b._apply(0.0)
		b.ext.sync()
		var y1: float = _bone_pos(b, left).y
		var yr: float = _bone_pos(b, right).y
		check(y1 > y0 + 0.2 and y1 > yr, "왼팔을 들면 방패 뼈가 따라 올라감 (%.2f → %.2f, 오른손 %.2f)" % [y0, y1, yr])
	b.free()


func test_blender_tank_fx_twin() -> void:
	var b = _body("tank")
	if b.ext == null:
		check(false, "외부 모델 없음")
		b.free()
		return
	var mi: MeshInstance3D = b.ext.parts[0].mi
	var solid = mi.material_override
	b.ext.fx([Color.WHITE, Color(0, 0, 0), Color(0, 0, 0)], 1.0)
	check((mi.material_override as ShaderMaterial).get_shader_parameter("skin_tint").is_equal_approx(Color.WHITE), "경직 하얀 깜빡임 = 몸 색 칸 하양 (구운 몸과 같은 길)")
	b.ext.fx([b.skin_color, Color(0.4, 0.2, 0), Color(0.1, 0.1, 0)], 1.0)
	var sm := mi.material_override as ShaderMaterial
	check(sm.get_shader_parameter("skin_emissive").is_equal_approx(Color(0.4, 0.2, 0)) and sm.get_shader_parameter("emissive").is_equal_approx(Color(0.1, 0.1, 0)), "피부 발광·나머지 발광 나눔")
	b.ext.fx([b.skin_color, Color(0, 0, 0), Color(0, 0, 0)], 0.5)
	var am := mi.material_override as ShaderMaterial
	check(am != solid and am.get_shader_parameter("albedo").a == 0.5 and am.get_shader_parameter("use_vertex_color") == true and am.get_shader_parameter("skin_multiply") == true, "반투명도 꼭짓점 색·곱하기")
	b.ext.fx([b.skin_color, Color(0, 0, 0), Color(0, 0, 0)], 1.0)
	check(mi.material_override == solid, "반투명 끝")
	b.free()
	# 1인칭 쌍둥이: stage LOD 의 팔꿈치 아래 삼각형만 (방패·해머 포함 — 손에 붙어 따라감), 소품·코드 방패 없음
	var t = _body("tank", false)
	check(t.ext != null and not t.ext.third and t.ext.lod == "tank_vm", "1인칭 쌍둥이 = 닫힌 팔 tank_vm (W28)")
	if t.ext != null:
		var arm_tri := 0
		for sf in _lod_surfs(t.ext.info, t.ext.lod):
			if sf.vm_mesh != null:
				arm_tri += _tris(sf.vm_mesh)
		check(arm_tri > 2000 and arm_tri < 9000, "1인칭 팔 삼각형 %d (아래팔·손·방패·해머만 남김)" % arm_tri)
		check(t.ext.find_children("*", "BoneAttachment3D", true, false).is_empty(), "1인칭에도 따로 붙인 소품 없음")
		check((t._n(t.refs.shields.front) as Node3D).get_node_or_null("ext_shields_front") == null, "1인칭 앞 방패 노드에 소품 없음 (몸 모델 방패가 왼팔을 따라감)")
	t.free()


# 몸 메시의 넓이 가중 평균 색 (꼭짓점 색 × 텍스처 (있으면, 삼각형 가운데 UV), 몸 색 칸 빼고) · 몸 색 칸 넓이 비율
func _albedo_stats(mesh: Mesh, tex = null) -> Array:
	var arr: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var uv = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var img: Image = null
	if tex is Texture2D:
		img = (tex as Texture2D).get_image()
		if img != null and img.is_compressed():
			img.decompress()
	var s := Vector3.ZERO
	var area_sum := 0.0
	var skin := 0.0
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		var area := (v[i1] - v[i0]).cross(v[i2] - v[i0]).length() * 0.5
		if u2[i0].x > 0.5:
			skin += area
			continue
		var col: Color = (c[i0] + c[i1] + c[i2]) / 3.0
		if img != null and uv != null:
			var u: Vector2 = ((uv[i0] + uv[i1] + uv[i2]) / 3.0)
			var px := Vector2i(clampi(int(fposmod(u.x, 1.0) * img.get_width()), 0, img.get_width() - 1), clampi(int(fposmod(u.y, 1.0) * img.get_height()), 0, img.get_height() - 1))
			col = col * img.get_pixelv(px)
		s += Vector3(col.r, col.g, col.b) * area
		area_sum += area
	return [s / maxf(1e-9, area_sum), skin / maxf(1e-9, skin + area_sum)]


# 밝기 (W19 재혁 '어둡고 탁함'): Blender 탱크 (high LOD, 몸 색 칸 뺀 갑옷·옷, 구운 그늘 포함) 의 넓이 평균 밝기가 구운 탱크의 0.92~1.35 배 (W20 Tripo 기사는 원본 칠한 색이라 0.65~1.35 로 넓힘, 눈으로 확인)
func test_blender_tank_brightness() -> void:
	var baked = _body("tank", true, false)
	var ext = _body("tank")
	var bm: Mesh = null
	for dr in baked.drawn:
		if (dr.mi as MeshInstance3D).mesh != null and (dr.mi as MeshInstance3D).mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR:
			bm = (dr.mi as MeshInstance3D).mesh
	var ep = null if ext.ext == null else ext.ext.parts[0]
	check(bm != null and ep != null, "구운 몸·Blender 몸 메시")
	if bm != null and ep != null:
		var a := _albedo_stats(bm)
		var b := _albedo_stats((ep.mi as MeshInstance3D).mesh, ep.tex)
		var la: float = (a[0] as Vector3).dot(Vector3(0.2126, 0.7152, 0.0722))
		var lb: float = (b[0] as Vector3).dot(Vector3(0.2126, 0.7152, 0.0722))
		check(lb / la > 0.65 and lb / la < 1.35, "몸 평균 밝기 구운 몸 대비 %.3f (구운 %.3f, Blender %.3f)" % [lb / la, la, lb])
	baked.free()
	ext.free()


# 무대 빛 (대기실 큰 캐릭터·초상, ui/portrait.gd stage_light): 구운 몸·Blender 몸 모두 툰 재질이 전역 (대기실 어두운 장면) 빛 대신 JS 무대 흰 빛
func test_stage_light() -> void:
	var P = load("res://ui/portrait.gd")
	for ext in [false, true]:
		var b = _body("tank", true, ext)
		P.stage_light(b)
		var n := 0
		var on := 0
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m = (mi as MeshInstance3D).material_override
			if (mi as MeshInstance3D).mesh != null and m is ShaderMaterial and P._has_local_light((m as ShaderMaterial).shader):
				n += 1
				if m.get_shader_parameter("local_light") == true and is_equal_approx(float(m.get_shader_parameter("local_hemi_energy")), 1.05):
					on += 1
		check(n > 0 and on == n, "%s 툰 재질 %d 개 모두 무대 빛 (%d)" % ["Blender" if ext else "구운", n, on])
		b.free()


# ---------- 닌자 (스킨 메시 하나 + Mixamo 식 뼈 65, tools/blender/tripo/rig_ninja.py) ----------

# 뼈 이름 자동 매칭 (손가락·빗장은 안 맞춤), LOD (stage = 원본 전체, 판 = 약 8500: 이음선 때문에 더 못 줄임), 몸 색 칸 = 목도리·허리띠 일부, ninja.json
func test_ninja_info() -> void:
	var info = Ext.load_char("ninja")
	check(info != null, "닌자 ninja.glb 읽음")
	if info == null:
		return
	for j in Ext.JOINTS:
		check(info.map.has(j), "뼈 매칭 %s" % j)
	check(info.map.hips >= 0 and String(info.names[info.map.hips]).ends_with("Hips") and String(info.names[info.map.waist]).ends_with("Spine") and String(info.names[info.map.torso]).ends_with("Spine2"), "골반=Hips·허리=Spine·가슴=Spine2")
	check(String(info.names[info.map.shoulder_L]).ends_with("LeftArm") and String(info.names[info.map.elbow_R]).ends_with("RightForeArm") and String(info.names[info.map.foot_L]).ends_with("LeftFoot"), "위팔=Arm (빗장 아님)·아래팔=ForeArm·발=Foot")
	check(info.names.size() >= 60, "손가락까지 뼈 %d" % info.names.size())
	var lods: Dictionary = info.cfg.get("lods", {})
	check(lods.size() == 4 and str(lods.high) != str(lods.medium) and str(lods.medium) != str(lods.low) and str(lods.stage) != str(lods.high), "LOD: stage 하나 + 판 셋 (W31 새 UV 로 다시 구움, 메시 셋이 따로)")
	var want := {"stage": [15000, 20000], "high": [4400, 5000]}
	for k in want:
		var ss := _lod_surfs(info, str(lods.get(k, "")))
		var tri := 0
		var body_sf = null
		for sf in ss:
			tri += _tris(sf.mesh)
			body_sf = sf
		check(ss.size() == 1 and body_sf.skinned and body_sf.vcolor and body_sf.tex != null, "%s: 몸 표면 하나 = 스킨·꼭짓점 색 (몸 색 칸)·텍스처" % k)
		check(tri >= want[k][0] and tri <= want[k][1], "%s 삼각형 %d (%d~%d)" % [k, tri, want[k][0], want[k][1]])
		var st := _albedo_stats(body_sf.mesh, body_sf.tex)
		check(st[1] > 0.05 and st[1] < 0.35, "%s 몸 색 칸 넓이 %.0f%% (5~35%% — 목도리·허리띠)" % [k, st[1] * 100.0])
	check(info.cfg.tint == "mask" and (info.cfg.attach as Array).size() == 2 and (info.cfg.keep as Array).is_empty() and str(info.cfg.get("vm_node", "")) == "ninja_vm", "ninja.json: mask·단검 2 (판 몸만)·1인칭은 닫힌 팔 노드 ninja_vm (W23)")


# 위치가 같은 꼭짓점을 한 점으로 보고 삼각형 한 개에만 쓰인 모서리 수 (0 = 닫힌 껍질)
static func _open_edges(mesh: ArrayMesh) -> int:
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var ks := PackedStringArray()
	for v in vs:
		ks.append("%d,%d,%d" % [roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5)])
	var ec := {}
	for i in range(0, idx.size(), 3):
		for k in 3:
			var a: String = ks[idx[i + k]]
			var b: String = ks[idx[i + (k + 1) % 3]]
			var e: String = (a + "|" + b) if a < b else (b + "|" + a)
			ec[e] = int(ec.get(e, 0)) + 1
	var n := 0
	for e in ec:
		if ec[e] == 1:
			n += 1
	return n


# 판 몸: 크기·발바닥, 뼈가 우리 관절 방향을 따라감 (팔 들기·무릎 굽힘), 단검 두 자루가 손에 붙음, 몸 색 칸 = 플레이어 색, 안쪽 몸 소품은 안 남김
func test_ninja_body() -> void:
	var Gfx = load("res://world/gfx.gd")
	var was: Dictionary = Gfx.plan
	Gfx.plan = {}
	var b = _body("ninja")
	Gfx.plan = was
	check(b.ext != null, "닌자 붙음")
	if b.ext == null:
		b.free()
		return
	var sc: float = b.ext.transform.basis.get_scale().x
	var hh: float = (b.ext.info.box as AABB).size.y * sc
	var want_h: float = C.PLAYER_HEIGHT * C.FIGURE_SCALE * float(b.ext.info.cfg.height)
	check(absf(hh - want_h) < 0.01, "키 %.3f m = 예전 몸 키 %.3f m × height (원본 단위라 배율 %.3f)" % [hh, want_h, sc])
	for j in ["foot_R", "foot_L"]:
		var dz: float = _bone_pos(b, b.ext.info.map[j]).y - _jpos(b, b.ext._joint(j)).y
		check(absf(dz) < 0.1, "발 뼈 높이 = 우리 발 (차이 %.3f m)" % dz)
	_check_follow(b, "닌자")
	var ext_n := 0
	for dr in b.drawn:
		ext_n += 1 if dr.get("ext", false) else 0
	check(ext_n == 3 and b.drawn.size() == 3 and b.ext.band == null, "그리는 메시 3 (몸 + 단검 2 — W32 에 단검 세 조각을 한 메시로 합침, 얻음 %d/%d)" % [ext_n, b.drawn.size()])
	var daggers := 0
	for ba in b.ext.find_children("*", "BoneAttachment3D", true, false):
		daggers += 1 if String((ba as BoneAttachment3D).bone_name).ends_with("Hand") else 0
	check(daggers == 2, "손 뼈에 단검 둘 (얻음 %d)" % daggers)
	var m: ShaderMaterial = b.ext.parts[0].mi.material_override
	check(m.get_shader_parameter("use_vertex_color") == true and m.get_shader_parameter("skin_multiply") == true and (m.get_shader_parameter("skin_tint") as Color).is_equal_approx(Color(0.2, 0.5, 1.0, 1.0)), "몸 색 칸 = 플레이어 색 곱하기")
	check(b.ext.lod == str(b.ext.info.cfg.lods.high), "판 몸 = high LOD (얻음 %s)" % b.ext.lod)
	b.free()


# 1인칭 쌍둥이: stage LOD 의 팔꿈치 아래 삼각형만 남김 (소매·장갑이 닫힌 팔이라 깨지지 않음), 단검은 안 붙임 (viewmodel 이 표창을 쥐여 줌)
func test_ninja_first_person() -> void:
	var t = _body("ninja", false)
	check(t.ext != null and not t.ext.third and t.ext.lod == "ninja_vm", "1인칭 쌍둥이 = 닫힌 팔 노드 ninja_vm (W23)")
	if t.ext != null:
		var arm_tri := 0
		for sf in _lod_surfs(t.ext.info, t.ext.lod):
			if sf.vm_mesh != null:
				arm_tri += _tris(sf.vm_mesh)
		check(arm_tri > 300 and arm_tri < 5000, "1인칭 팔 삼각형 %d (아래팔·손만)" % arm_tri)
		for sf in _lod_surfs(t.ext.info, t.ext.lod):
			if sf.vm_mesh != null:
				var op := _open_edges(sf.vm_mesh)
				check(op <= 20, "1인칭 팔 닫힘: 열린 가장자리 %d (예전 가르기는 팔꿈치 둘레가 수백 개 열림)" % op)
		var bas := 0
		for ba in t.ext.find_children("*", "BoneAttachment3D", true, false):
			bas += 1
		check(bas == 0, "1인칭에는 단검 안 붙음 (%d)" % bas)
	t.free()


# ---------- 사냥꾼 (스킨 메시 하나 + Mixamo 식 뼈 65, tools/blender/tripo/rig_hunter.py) ----------

# 뼈 매칭, LOD (stage = 원본 전체, 판 = 5000·4000·3000 — 닌자·탱크와 달리 이음선이 덜 잘려 셋 다 만듦), 몸 색 칸 = 모자 + 목수건, 소총이 오른팔 뼈에 매임
func test_hunter_info() -> void:
	var info = Ext.load_char("hunter")
	check(info != null, "사냥꾼 hunter.glb 읽음")
	if info == null:
		return
	for j in Ext.JOINTS:
		check(info.map.has(j), "뼈 매칭 %s" % j)
	check(String(info.names[info.map.hips]).ends_with("Hips") and String(info.names[info.map.shoulder_R]).ends_with("RightArm") and String(info.names[info.map.elbow_L]).ends_with("LeftForeArm"), "골반=Hips·위팔=Arm·아래팔=ForeArm")
	check(info.names.size() >= 60, "손가락까지 뼈 %d" % info.names.size())
	var lods: Dictionary = info.cfg.get("lods", {})
	var names := {}
	for k in lods:
		names[str(lods[k])] = true
	check(lods.size() == 4 and names.size() == 4, "LOD 4개 (stage·high·medium·low 모두 다른 메시)")
	var want := {"stage": [15000, 20000], "high": [4500, 5500], "medium": [3500, 4500], "low": [2500, 3500]}
	var stage_sf = null
	for k in want:
		var ss := _lod_surfs(info, str(lods.get(k, "")))
		var tri := 0
		var body_sf = null
		for sf in ss:
			tri += _tris(sf.mesh)
			body_sf = sf
		check(ss.size() == 1 and body_sf.skinned and body_sf.vcolor and body_sf.tex != null, "%s: 몸 표면 하나 = 스킨·꼭짓점 색 (몸 색 칸)·텍스처" % k)
		check(tri >= want[k][0] and tri <= want[k][1], "%s 삼각형 %d (%d~%d)" % [k, tri, want[k][0], want[k][1]])
		var st := _albedo_stats(body_sf.mesh, body_sf.tex)
		check(st[1] > 0.03 and st[1] < 0.35, "%s 몸 색 칸 넓이 %.0f%% (3~35%% — 모자·붉은 목수건)" % [k, st[1] * 100.0])
		if k == "stage":
			stage_sf = body_sf
	check(info.cfg.tint == "mask" and (info.cfg.attach as Array).is_empty() and (info.cfg.keep as Array).is_empty() and str(info.cfg.get("vm_node", "")) == "hunter_vm", "hunter.json: mask·소품 없음 (소총이 몸에 붙음, 코드 총은 안 남김)·1인칭 팔 = hunter_vm (소총 뺌)")
	# 소총은 몸 밖으로 크게 나온 쪽 아래팔 (게임 R 관절 = Mixamo Right*) 에 매임: 몸 바깥 (|z|) 꼭짓점의 아래팔 뼈 쪽 센 수
	if stage_sf != null:
		var arr: Array = stage_sf.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var cnt := {"R": 0, "L": 0}
		for i in v.size():
			if absf(v[i].z) < 0.2 * float(info.box.size.y):
				continue
			var best := 0
			for k in 4:
				if bw[i * 4 + k] > bw[i * 4 + best]:
					best = k
			var bn: String = info.names[stage_sf.binds[bi[i * 4 + best]]]
			if bn.contains("ForeArm"):
				cnt["R" if bn.contains("Right") else "L"] += 1
		check(cnt.R > 3 * cnt.L and cnt.R > 300, "소총·오른 아래팔 뼈 꼭짓점 오른 %d·왼 %d" % [cnt.R, cnt.L])


# 판 몸: 크기·발바닥, 뼈가 우리 관절을 따라감, 그리는 메시 하나, 몸 색 칸 = 플레이어 색, 화질별 LOD
func test_hunter_body() -> void:
	var Gfx = load("res://world/gfx.gd")
	var was: Dictionary = Gfx.plan
	for lv in ["high", "medium", "low"]:
		Gfx.plan = {"level": lv}
		var b = _body("hunter")
		check(b.ext != null and b.ext.lod == str(b.ext.info.cfg.lods[lv]), "화질 %s → LOD %s" % [lv, b.ext.lod if b.ext != null else "-"])
		b.free()
	Gfx.plan = {}
	var b = _body("hunter")
	Gfx.plan = was
	check(b.ext != null, "사냥꾼 붙음")
	if b.ext == null:
		b.free()
		return
	var sc: float = b.ext.transform.basis.get_scale().x
	var hh: float = (b.ext.info.box as AABB).size.y * sc
	var want_h: float = C.PLAYER_HEIGHT * C.FIGURE_SCALE * float(b.ext.info.cfg.height)
	check(absf(hh - want_h) < 0.01, "키 %.3f m = 예전 몸 키 %.3f m × height" % [hh, want_h])
	for j in ["foot_R", "foot_L"]:
		var dz: float = _bone_pos(b, b.ext.info.map[j]).y - _jpos(b, b.ext._joint(j)).y
		check(absf(dz) < 0.1, "발 뼈 높이 = 우리 발 (차이 %.3f m)" % dz)
	_check_follow(b, "사냥꾼")
	var ext_n := 0
	for dr in b.drawn:
		ext_n += 1 if dr.get("ext", false) else 0
	check(ext_n == 1 and b.drawn.size() == 1 and b.ext.band == null, "그리는 메시 1 (몸 하나, 얻음 %d/%d)" % [ext_n, b.drawn.size()])
	check(b.ext.find_children("*", "BoneAttachment3D", true, false).is_empty(), "손 뼈에 붙인 소품 없음")
	var m: ShaderMaterial = b.ext.parts[0].mi.material_override
	check(m.get_shader_parameter("use_vertex_color") == true and m.get_shader_parameter("skin_multiply") == true and (m.get_shader_parameter("skin_tint") as Color).is_equal_approx(Color(0.2, 0.5, 1.0, 1.0)), "몸 색 칸 = 플레이어 색 곱하기")
	b.free()


# 1인칭 쌍둥이: glb 안의 hunter_vm (stage 몸에서 아래팔·손만, 소총 꼭짓점은 뺌 — 안 빼면 소총이 화면 가운데를 가로지름). 판 몸에는 안 그려짐
func test_hunter_first_person() -> void:
	var t = _body("hunter", false)
	check(t.ext != null and not t.ext.third and t.ext.lod == "hunter_vm", "1인칭 쌍둥이 = hunter_vm (얻음 %s)" % (t.ext.lod if t.ext != null else "-"))
	if t.ext != null:
		var arm_tri := 0
		for sf in t.ext.info.surfs:
			if sf.vm_mesh != null:
				arm_tri += _tris(sf.vm_mesh)
		check(arm_tri > 500 and arm_tri < 3000, "1인칭 팔 삼각형 %d (아래팔·손, 소총 없음)" % arm_tri)
		var meshes := 0
		for mi in t.ext.find_children("*", "MeshInstance3D", true, false):
			meshes += 1 if (mi as MeshInstance3D).mesh != null and String(mi.name).begins_with("hunter_") else 0
		check(meshes == 1, "1인칭에 그리는 외부 메시 하나 (%d)" % meshes)
	t.free()
	var b = _body("hunter")
	var seen := {}
	for mi in b.ext.find_children("*", "MeshInstance3D", true, false):
		seen[String(mi.name).split("_s")[0]] = true
	check(not seen.has("hunter_vm") and not seen.has("hunter_lod0"), "판 몸에는 1인칭 팔·stage 메시 없음 (%s)" % [seen.keys()])
	b.free()


# ---------- 갈고리 (해적 선장, 스킨 메시 하나 + Mixamo 식 뼈 65, tools/blender/tripo/rig_hook.py) ----------

# 뼈 매칭, LOD (stage = 원본 전체, 판 = 하나 약 8400 을 high·medium·low 가 같이 씀 — UV 이음선 때문에 더 못 줄임), 몸 색 칸 = 삼각 모자, 갈고리 손이 게임 L 관절 (= Mixamo Left*)
func test_hook_info() -> void:
	var info = Ext.load_char("hook")
	check(info != null, "갈고리 hook.glb 읽음")
	if info == null:
		return
	for j in Ext.JOINTS:
		check(info.map.has(j), "뼈 매칭 %s" % j)
	check(String(info.names[info.map.hips]).ends_with("Hips") and String(info.names[info.map.hand_L]).ends_with("LeftHand") and String(info.names[info.map.elbow_L]).ends_with("LeftForeArm"), "골반=Hips·왼손=LeftHand·아래팔=ForeArm")
	check(info.names.size() >= 60, "손가락까지 뼈 %d" % info.names.size())
	var lods: Dictionary = info.cfg.get("lods", {})
	var names := {}
	for k in lods:
		names[str(lods[k])] = true
	check(lods.size() == 4 and names.size() == 4, "LOD: stage 하나 + 판 셋 (W31 새 UV 로 다시 구움, 메시 넷이 따로)")
	var want := {"stage": [17000, 20000], "high": [4400, 5000]}
	var stage_sf = null
	for k in want:
		var ss := _lod_surfs(info, str(lods.get(k, "")))
		var tri := 0
		var body_sf = null
		for sf in ss:
			tri += _tris(sf.mesh)
			body_sf = sf
		check(ss.size() == 1 and body_sf.skinned and body_sf.vcolor and body_sf.tex != null, "%s: 몸 표면 하나 = 스킨·꼭짓점 색 (몸 색 칸)·텍스처" % k)
		check(tri >= want[k][0] and tri <= want[k][1], "%s 삼각형 %d (%d~%d)" % [k, tri, want[k][0], want[k][1]])
		var st := _albedo_stats(body_sf.mesh, body_sf.tex)
		check(st[1] > 0.05 and st[1] < 0.35, "%s 몸 색 칸 넓이 %.0f%% (5~35%% — 삼각 모자)" % [k, st[1] * 100.0])
		if k == "stage":
			stage_sf = body_sf
	check(info.cfg.tint == "mask" and (info.cfg.attach as Array).is_empty() and (info.cfg.keep as Array).is_empty() and str(info.cfg.get("vm_node", "")) == "hook_vm" and str(info.cfg.get("rope_bone", "")) != "", "hook.json: mask·소품 없음 (갈고리가 몸에 붙음, 코드 갈고리는 안 남김)·1인칭 hook_vm·밧줄 뼈")
	# 갈고리는 게임 L 관절 팔 (갈고리 던지기·휘두르기·내려치기 모두 L): 몸 밖으로 크게 나온 꼭짓점 중 왼 아래팔·손 뼈 쪽이 오른쪽보다 많음 (원본은 갈고리 손이 Mixamo LeftHand)
	if stage_sf != null:
		var arr: Array = stage_sf.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var cnt := {"R": 0, "L": 0}
		for i in v.size():
			if absf(v[i].z) < 0.2 * float(info.box.size.y):
				continue
			var best := 0
			for k in 4:
				if bw[i * 4 + k] > bw[i * 4 + best]:
					best = k
			var bn: String = info.names[stage_sf.binds[bi[i * 4 + best]]]
			if bn.contains("Hand") or bn.contains("ForeArm"):
				cnt["R" if bn.contains("Right") else "L"] += 1
		check(cnt.L > cnt.R, "갈고리 손 = 왼 (L 관절) 팔 뼈 꼭짓점 왼 %d·오른 %d" % [cnt.L, cnt.R])


# 코트·치맛자락이 팔을 따라 올라오지 않게 (원본은 코트 판 3360 꼭짓점이 손 뼈에 매였음): 팔 뼈 (위팔·아래팔·손·손가락) 가중치는 그 쪽 팔 뼈가 가장 센 꼭짓점이거나 뼈 선분 3 cm 안에만
func test_hook_arm_weights() -> void:
	var info = Ext.load_char("hook")
	if info == null:
		check(false, "hook.glb 읽음")
		return
	var sf = _lod_surfs(info, str(info.cfg.lods.stage))[0]
	var arr: Array = sf.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var rest: Array = info.rest_global
	var segs := {}
	for i in info.names.size():
		var n: String = info.names[i]
		if not (n.contains("Arm") or n.contains("Hand")) or n.contains("Shoulder"):
			continue
		var kid := -1
		for j in info.names.size():
			if info.parents[j] == i:
				kid = j
				break
		var a: Vector3 = (rest[i] as Transform3D).origin
		var b: Vector3 = (rest[kid] as Transform3D).origin if kid >= 0 else a + Vector3(0, -0.03, 0)
		segs[i] = [a, b, n.contains("Left")]
	var bad := 0
	var arm_verts := 0
	for i in v.size():
		var best := 0
		for k in 4:
			if bw[i * 4 + k] > bw[i * 4 + best]:
				best = k
		var top: int = sf.binds[bi[i * 4 + best]]
		var top_arm: bool = segs.has(top)
		var top_left: bool = top_arm and bool(segs[top][2])
		arm_verts += 1 if top_arm else 0
		for k in 4:
			if bw[i * 4 + k] < 0.01:
				continue
			var bone: int = sf.binds[bi[i * 4 + k]]
			if not segs.has(bone):
				continue
			if top_arm and top_left == bool(segs[bone][2]):
				continue
			var a: Vector3 = segs[bone][0]
			var b: Vector3 = segs[bone][1]
			var t := clampf((v[i] - a).dot(b - a) / maxf(1e-9, (b - a).length_squared()), 0.0, 1.0)
			if (v[i] - (a + (b - a) * t)).length() > 0.035 * float(info.box.size.y):
				bad += 1
	check(arm_verts > 1000, "팔 뼈가 센 꼭짓점 %d" % arm_verts)
	check(bad == 0, "팔 뼈 가중치가 코트에 번진 꼭짓점 %d (0)" % bad)


# 판 몸: 크기·발바닥, 뼈가 우리 관절을 따라감, 그리는 메시 하나, 몸 색 칸 = 플레이어 색, 화질별 LOD, 밧줄이 모델 갈고리 쪽에서 나감
func test_hook_body() -> void:
	var Gfx = load("res://world/gfx.gd")
	var was: Dictionary = Gfx.plan
	for lv in ["high", "medium", "low"]:
		Gfx.plan = {"level": lv}
		var b = _body("hook")
		check(b.ext != null and b.ext.lod == str(b.ext.info.cfg.lods[lv]), "화질 %s → LOD %s" % [lv, b.ext.lod if b.ext != null else "-"])
		b.free()
	Gfx.plan = {}
	var b = _body("hook")
	Gfx.plan = was
	check(b.ext != null, "갈고리 붙음")
	if b.ext == null:
		b.free()
		return
	var sc: float = b.ext.transform.basis.get_scale().x
	var hh: float = (b.ext.info.box as AABB).size.y * sc
	var want_h: float = C.PLAYER_HEIGHT * C.FIGURE_SCALE * float(b.ext.info.cfg.height)
	check(absf(hh - want_h) < 0.01, "키 %.3f m = 예전 몸 키 %.3f m × height" % [hh, want_h])
	for j in ["foot_R", "foot_L"]:
		var dz: float = _bone_pos(b, b.ext.info.map[j]).y - _jpos(b, b.ext._joint(j)).y
		check(absf(dz) < 0.1, "발 뼈 높이 = 우리 발 (차이 %.3f m)" % dz)
	_check_follow(b, "갈고리")
	var ext_n := 0
	for dr in b.drawn:
		ext_n += 1 if dr.get("ext", false) else 0
	check(ext_n == 1 and b.drawn.size() == 1 and b.ext.band == null, "그리는 메시 1 (몸 하나, 얻음 %d/%d)" % [ext_n, b.drawn.size()])
	check(b.ext.find_children("*", "BoneAttachment3D", true, false).is_empty(), "손 뼈에 붙인 소품 없음 (코드 갈고리 안 남김)")
	var m: ShaderMaterial = b.ext.parts[0].mi.material_override
	check(m.get_shader_parameter("use_vertex_color") == true and m.get_shader_parameter("skin_multiply") == true and (m.get_shader_parameter("skin_tint") as Color).is_equal_approx(Color(0.2, 0.5, 1.0, 1.0)), "몸 색 칸 = 플레이어 색 곱하기")
	b.free()
	# 밧줄 시작점: 쉬는 자세에서 모델 왼손 (갈고리) 뼈 곁 (≤ 0.15 m) 이고, 코드 손 관절과는 다른 자리 (모델 팔 길이가 달라 어긋나던 것)
	var rb = _body("hook")
	rb.pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "emote": -1}, 0.0)
	var rp = rb.ext.rope_point()
	check(rp != null, "밧줄 뼈 위치 (rope_bone)")
	if rp != null:
		var hand_pos: Vector3 = _bone_pos(rb, rb.ext.info.map.hand_L)
		var hand_joint: Vector3 = _jpos(rb, rb.ext._joint("hand_L"))
		check((rp as Vector3).distance_to(hand_pos) < 0.15, "밧줄 시작점이 모델 왼손 곁 (%.3f m)" % (rp as Vector3).distance_to(hand_pos))
		check((rp as Vector3).distance_to(hand_joint) > 0.03, "코드 손 관절과 다른 자리 (모델 갈고리 쪽, %.3f m)" % (rp as Vector3).distance_to(hand_joint))
	rb.free()


# 1인칭 쌍둥이: glb 안의 hook_vm (닫힌 팔 — 왼쪽은 갈고리가 화면에 보임, 오른쪽은 주먹). 판 몸에는 안 그려짐
func test_hook_first_person() -> void:
	var t = _body("hook", false)
	check(t.ext != null and not t.ext.third and t.ext.lod == "hook_vm", "1인칭 쌍둥이 = hook_vm (얻음 %s)" % (t.ext.lod if t.ext != null else "-"))
	if t.ext != null:
		var arm_tri := 0
		for sf in t.ext.info.surfs:
			if sf.vm_mesh != null:
				arm_tri += _tris(sf.vm_mesh)
		check(arm_tri > 1000 and arm_tri < 3000, "1인칭 팔 삼각형 %d (아래팔·손·갈고리, 코트 안 번짐)" % arm_tri)
		var meshes := 0
		for mi in t.ext.find_children("*", "MeshInstance3D", true, false):
			meshes += 1 if (mi as MeshInstance3D).mesh != null and String(mi.name).begins_with("hook_") else 0
		check(meshes == 1, "1인칭에 그리는 외부 메시 하나 (%d)" % meshes)
	t.free()
	var b = _body("hook")
	var seen := {}
	for mi in b.ext.find_children("*", "MeshInstance3D", true, false):
		seen[String(mi.name).split("_s")[0]] = true
	check(not seen.has("hook_vm") and not seen.has("hook_lod0"), "판 몸에는 1인칭 팔·stage 메시 없음 (%s)" % [seen.keys()])
	b.free()


# ---------- 대포수 (스킨 메시 하나 + Tripo 자동 리깅 뼈 78 — 접두어 없는 L_/R_ 이름, tools/blender/tripo/rig_cannon.py) ----------

# 뼈 매칭 (ALIASES 만으로 — cannon.json 에 bones 덮어쓰기 없음), LOD, 몸 색 칸 = 빨간 두건·다이너마이트 띠, 손대포는 몸에서 떼어 오른손 소품으로
func test_cannon_info() -> void:
	if not Ext.has_char("cannon"): # W26 대포수 몸은 보관 중 (assets/models/ext_hold/) — ext/ 에 cannon.glb 가 없으면 건너뜀
		print("      (건너뜀: ext/cannon.glb 없음 — 보관 중)")
		return
	var info = Ext.load_char("cannon")
	check(info != null, "대포수 cannon.glb 읽음")
	if info == null:
		return
	for j in Ext.JOINTS:
		check(info.map.has(j), "뼈 매칭 %s" % j)
	var nm := func(j: String) -> String: return String(info.names[info.map[j]])
	check(nm.call("hips") == "Pelvis" and nm.call("waist") == "Spine01" and nm.call("torso") == "Spine02" and nm.call("neck") == "NeckTwist01", "골반=Pelvis·허리=Spine01·가슴=Spine02·목=NeckTwist01")
	check(nm.call("shoulder_R") == "R_Upperarm" and nm.call("elbow_L") == "L_Forearm" and nm.call("knee_R") == "R_Calf" and nm.call("foot_L") == "L_Foot", "위팔=Upperarm (빗장 안 씀)·아래팔=Forearm·정강이=Calf")
	check(not (info.cfg.get("bones", {}) as Dictionary).size() > 0, "cannon.json 에 bones 덮어쓰기 없음 (이름 매칭만)")
	check(info.names.size() >= 70, "손가락·트위스트까지 뼈 %d" % info.names.size())
	var lods: Dictionary = info.cfg.get("lods", {})
	check(lods.stage == "cannon_lod0" and lods.high == lods.medium and lods.medium == lods.low and lods.high != lods.stage, "LOD: stage 하나 + 판 하나 (UV 이음선 때문에 약 8000 아래로 안 내려감)")
	var want := {"stage": [16000, 19500], "high": [6500, 9000]}
	var stage_sf = null
	for k in want:
		var ss := _lod_surfs(info, str(lods.get(k, "")))
		var tri := 0
		var body_sf = null
		for sf in ss:
			tri += _tris(sf.mesh)
			body_sf = sf
		check(ss.size() == 1 and body_sf.skinned and body_sf.vcolor and body_sf.tex != null, "%s: 몸 표면 하나 = 스킨·꼭짓점 색 (몸 색 칸)·텍스처" % k)
		check(tri >= want[k][0] and tri <= want[k][1], "%s 삼각형 %d (%d~%d)" % [k, tri, want[k][0], want[k][1]])
		var st := _albedo_stats(body_sf.mesh, body_sf.tex)
		check(st[1] >= 0.05 and st[1] < 0.3, "%s 몸 색 칸 넓이 %.1f%% (5~30%% — 빨간 두건·다이너마이트 띠)" % [k, st[1] * 100.0])
		if k == "stage":
			stage_sf = body_sf
	check(info.cfg.tint == "mask" and str(info.cfg.get("vm_node", "")) == "cannon_vm" and (info.cfg.get("hold") is Dictionary), "cannon.json: mask·1인칭 닫힌 팔·두 손으로 든 자세 hold")
	var at: Array = info.cfg.get("attach", [])
	check(at.size() == 1 and at[0].joint == "hand_R" and at[0].get("vm", false) == true and ResourceLoader.exists(str(at[0].glb)), "손대포 소품 = 오른손 뼈 하나 (판 몸·1인칭 둘 다)")
	if stage_sf != null:
		# 손대포가 몸 메시에 안 남음: 두 손 사이 앞 (glTF 축: 앞 x 0.15~0.46, 높이 y 0.52~0.65, |z| < 0.05, 미터) 에 꼭짓점이 거의 없어야 함 (남으면 한 팔만 들 때 대포가 늘어나 가시)
		var v: PackedVector3Array = stage_sf.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var left := 0
		for p in v:
			if p.x > 0.15 and p.x < 0.46 and absf(p.z) < 0.05 and p.y > 0.52 and p.y < 0.65:
				left += 1
		check(left < 200, "몸 메시에 손대포 통이 거의 안 남음 (앞 가운데 %d 꼭짓점 — 주먹에 녹은 나무 그루터기 ~120 은 남음, 원본 대포는 수천)" % left)
	var gun = load(str(at[0].glb)).instantiate()
	var gtri := 0
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		gtri += _tris((mi as MeshInstance3D).mesh)
	check(gtri > 800 and gtri < 2500, "손대포 소품 삼각형 %d" % gtri)
	gun.free()


# 판 몸: 크기·발바닥, 뼈가 우리 관절을 따라감, 그리는 메시 = 몸 하나 + 손대포 하나, 손대포 = 오른손 뼈, 코드 대포 안 남김, 두 손으로 든 자세
func test_cannon_body() -> void:
	if not Ext.has_char("cannon"):
		return
	var Gfx = load("res://world/gfx.gd")
	var was: Dictionary = Gfx.plan
	Gfx.plan = {}
	var b = _body("cannon")
	Gfx.plan = was
	check(b.ext != null, "대포수 붙음")
	if b.ext == null:
		b.free()
		return
	var sc: float = b.ext.transform.basis.get_scale().x
	var hh: float = (b.ext.info.box as AABB).size.y * sc
	var want_h: float = C.PLAYER_HEIGHT * C.FIGURE_SCALE * float(b.ext.info.cfg.height)
	check(absf(hh - want_h) < 0.01, "키 %.3f m = 예전 몸 키 %.3f m × height" % [hh, want_h])
	for j in ["foot_R", "foot_L"]:
		var dz: float = _bone_pos(b, b.ext.info.map[j]).y - _jpos(b, b.ext._joint(j)).y
		check(absf(dz) < 0.1, "발 뼈 높이 = 우리 발 (차이 %.3f m)" % dz)
	_check_follow(b, "대포수")
	var bas: Array = b.ext.find_children("*", "BoneAttachment3D", true, false)
	check(bas.size() == 1 and String((bas[0] as BoneAttachment3D).bone_name) == "R_Hand", "손대포 = 오른손 뼈 소품 하나 (%d)" % bas.size())
	var ext_n := 0
	for dr in b.drawn:
		ext_n += 1 if dr.get("ext", false) else 0
	check(ext_n == 2 and b.drawn.size() == 2, "그리는 메시 2 (몸 + 손대포, 얻음 %d/%d)" % [ext_n, b.drawn.size()])
	# 두 손으로 든 자세 (hold): 코드 몸의 어깨에 멘 자세 (오른팔 옆 1.75) 대신 팔꿈치를 굽혀 앞으로
	var st := {"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "emote": -1}
	for i in 30:
		b.pose(st, i * 16.0)
	var el: float = -(b.elbows[0] as Node3D).rotation.y
	var sh: float = absf((b.shoulders[0] as Node3D).rotation.x) + absf((b.shoulders[0] as Node3D).rotation.z)
	check(absf(el - 1.4) < 0.2 and sh < 1.0, "쉬는 자세 = 두 손으로 앞에 듦 (오른 팔꿈치 %.2f, 어깨 %.2f)" % [el, sh])
	var m: ShaderMaterial = b.ext.parts[0].mi.material_override
	check(m.get_shader_parameter("use_vertex_color") == true and m.get_shader_parameter("skin_multiply") == true and (m.get_shader_parameter("skin_tint") as Color).is_equal_approx(Color(0.2, 0.5, 1.0, 1.0)), "몸 색 칸 = 플레이어 색 곱하기")
	b.free()


# 1인칭 쌍둥이: glb 안의 닫힌 팔 cannon_vm (원본 팔·손은 대포에 녹아 있어 못 씀) + 손대포 (vm: true). 판 몸에는 안 그려짐
func test_cannon_first_person() -> void:
	if not Ext.has_char("cannon"):
		return
	var t = _body("cannon", false)
	check(t.ext != null and not t.ext.third and t.ext.lod == "cannon_vm", "1인칭 쌍둥이 = cannon_vm (얻음 %s)" % (t.ext.lod if t.ext != null else "-"))
	if t.ext != null:
		var arm_tri := 0
		for sf in t.ext.info.surfs:
			if sf.vm_mesh != null:
				arm_tri += _tris(sf.vm_mesh)
		check(arm_tri > 100 and arm_tri < 400, "1인칭 팔 삼각형 %d (닫힌 소매·띠·주먹 두 팔)" % arm_tri)
		check(t.ext.find_children("*", "BoneAttachment3D", true, false).size() == 1, "1인칭에도 손대포 하나")
	t.free()
	var b = _body("cannon")
	var seen := {}
	for mi in b.ext.find_children("*", "MeshInstance3D", true, false):
		seen[String(mi.name).split("_s")[0]] = true
	check(not seen.has("cannon_vm") and not seen.has("cannon_lod0"), "판 몸에는 1인칭 팔·stage 메시 없음 (%s)" % [seen.keys()])
	b.free()


# ---------- W27 대기실 큰 캐릭터·초상 (ui/portrait.gd prime_idle·frame) ----------

# 위팔 → 아래팔 뼈가 아래쪽을 향하는 정도 (1 = 똑바로 아래, 0 = 옆으로 쭉 = T 포즈). 뼈 이름은 Mixamo 식 (새 외부 모델 넷 모두)
static func _arm_down(b) -> float:
	var worst := 1.0
	for side in ["Left", "Right"]:
		var a = b.ext.bone_point(side + "Arm")
		var f = b.ext.bone_point(side + "ForeArm")
		if a == null or f == null:
			return -2.0
		var d: Vector3 = ((f as Vector3) - (a as Vector3)).normalized()
		worst = minf(worst, -d.y)
	return worst


# 대기실 큰 캐릭터·초상이 만드는 몸 (ui/portrait.gd still_body — stage LOD 최고 품질)
func _still(ch: String, ext := true):
	var P = load("res://ui/portrait.gd")
	var was_e: bool = Body.use_ext
	Body.use_ext = ext
	var b = P.still_body(load("res://chars/chars.gd"), ch, Color(0.2, 0.5, 1.0))
	Body.use_ext = was_e
	return b


func _ext_ids() -> Array:
	var out := []
	for ch in ["tank", "ninja", "hunter", "hook"]:
		if Ext.has_char(ch):
			out.append(ch)
	return out


# 대기실 큰 캐릭터 (char_stage.gd) 는 만들자마자 첫 프레임을 그림 → prime_idle 을 거치면 팔이 쉬는 자세 (내린 팔, 옆으로 쭉 안 벌어짐 = T 포즈 아님).
# 처음 자세 (pose 를 한 번도 안 부른 몸) 와 달라야 priming 이 실제로 일을 한다는 뜻
func test_stage_not_t_pose() -> void:
	var P = load("res://ui/portrait.gd")
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	for ch in _ext_ids():
		var b = _still(ch)
		root.add_child(b)
		P.prime_idle(b)
		var down := _arm_down(b)
		check(down > 0.55, "%s 큰 캐릭터 쉬는 자세 팔이 내려옴 (아래 %.2f, 0 = T 포즈)" % [ch, down])
		check(b.posed, "%s prime_idle 이 pose 를 불렀음" % ch)
		root.remove_child(b)
		b.free()
	var cb = _still("bard", false)
	root.add_child(cb)
	P.prime_idle(cb) # 코드 몸도 그대로 됨
	check(cb.posed, "코드 몸도 prime_idle")
	root.remove_child(cb)
	cb.free()


# 초상 프레이밍 (얼굴): 가운데 = 머리 뼈 근처 (몸 뿌리가 아님 — 모델마다 머리 높이·앞뒤 자리가 다름), 세로 반은 몸 키에 비례, 머리 뼈가 칸 안.
# 온몸은 몸 상자 가운데에 몸 전체. 코드 몸 넷도 칸이 몸 키·머리에 맞음
func test_portrait_frame() -> void:
	var P = load("res://ui/portrait.gd")
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	for ch in _ext_ids() + ["bard", "berserker", "cannon", "builder"]:
		var ext: bool = Ext.has_char(ch) and ch in ["tank", "ninja", "hunter", "hook"]
		var b = _still(ch, ext)
		root.add_child(b)
		P.prime_idle(b)
		var f: Dictionary = P.frame(b, false)
		var g: Dictionary = P.frame(b, true)
		check(f.half > 0.15 and f.half < 0.5, "%s 얼굴 칸 세로 반 %.2f m (0.15~0.5)" % [ch, f.half])
		var top: float = C.PLAYER_HEIGHT * C.FIGURE_SCALE
		if ext:
			check(g.half > top * 0.5 and g.half < top * 0.7 and absf(g.at.y - top / 2.0) < top * 0.05, "%s 온몸 칸 세로 반 %.2f 가운데 %.2f (몸 키 %.2f)" % [ch, g.half, g.at.y, top])
			check(f.at.y > top * 0.6 and f.at.y < top, "%s 얼굴 칸 가운데 높이 %.2f (몸 위쪽, 키 %.2f)" % [ch, f.at.y, top])
			var hp: Vector3 = b.ext.bone_point("Head")
			check(absf(f.at.y - hp.y) < f.half * 0.3, "%s 얼굴 칸 가운데가 머리 뼈 근처 (칸 %.2f, 머리 뼈 %.2f)" % [ch, f.at.y, hp.y])
			check(absf(f.at.x - hp.x) < 0.1 and absf(f.at.z - hp.z) < 0.1, "%s 가로 자리도 머리 (칸 %s, 머리 %s)" % [ch, f.at, hp])
			check(f.half > top * 0.18 and f.half < top * 0.3, "%s 칸 크기가 몸 키에 비례 (%.2f / 키 %.2f)" % [ch, f.half, top])
		root.remove_child(b)
		b.free()
	# 몸 키가 다르면 칸도 따라감 (같은 모델을 키 배율 1.25 로 — 고정 m 값이면 안 따라감)
	if Ext.has_char("ninja"):
		var info = Ext.load_char("ninja")
		var prev: Dictionary = info.cfg
		var cfg2: Dictionary = prev.duplicate(true)
		cfg2["height"] = 1.25
		var key := "ninja"
		Ext._cache.erase(key)
		var saved = info
		Ext._cache[key] = Ext.model_info(info.scene, cfg2)
		var big = _still("ninja")
		root.add_child(big)
		P.prime_idle(big)
		var fb: Dictionary = P.frame(big, false)
		var small = _still("ninja")
		Ext._cache[key] = saved
		root.remove_child(big)
		big.free()
		small.free()
		check(fb.half > 0.22 * 1.84 * 1.25 * 0.8, "키 배율 1.25 면 얼굴 칸도 커짐 (%.2f)" % fb.half)


# 캐릭터 바꾸기 (char_stage.show_char) 직후: prime_idle → 도발 시작 (age 0) 첫 pose 때 팔은 아직 내려와 있음 (처음 관절 값·T 포즈 한 프레임 아님).
# 도발이 진행되면 일부 모델은 팔을 수평으로 듦 (사냥꾼 겨누기·갈고리 손짓 등 설계된 포즈 — 연속 캡처 tools/switch_shot.gd) → 여기선 안 막음
func test_switch_first_frame_arms_down() -> void:
	var P = load("res://ui/portrait.gd")
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	for ch in _ext_ids():
		var b = _still(ch)
		root.add_child(b)
		P.prime_idle(b)
		b.pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "emote": C.EMOTE_CHAR}, 5000.0)
		var down := _arm_down(b)
		check(down > 0.55, "%s 바꾼 직후 도발 첫 pose 에 팔이 내려옴 (%.2f)" % [ch, down])
		root.remove_child(b)
		b.free()


# W27 대기실 큰 캐릭터: 외부 몸은 도발 없이 (바꾼 뒤 3초 모든 프레임 팔 내림 > 0.55), 예전 코드 몸은 도발 유지
func test_stage_ext_no_taunt() -> void:
	var P = load("res://ui/portrait.gd")
	var CS = load("res://ui/char_stage.gd")
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	for ch in _ext_ids():
		var b = _still(ch)
		root.add_child(b)
		P.prime_idle(b)
		var worst := 9.0
		var emotes := 0
		for i in 180: # 3초, 60fps
			var age := i * 1000.0 / 60.0
			var em: float = CS.emote_for(b, age)
			if em >= 0.0:
				emotes += 1
			b.pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "emote": em, "noIdle": true}, 5000.0 + age)
			worst = minf(worst, _arm_down(b))
		check(emotes == 0 and worst > 0.55, "%s 바꾼 뒤 3초 도발 없음 (%d 프레임)·팔 내림 최저 %.2f" % [ch, emotes, worst])
		root.remove_child(b)
		b.free()
	var cb = _still("bard", false)
	check(CS.emote_for(cb, 100.0) == C.EMOTE_CHAR and CS.emote_for(cb, C.EMOTE_MS + 500.0) == -1.0, "예전 코드 몸은 도발 유지 (EMOTE_MS 뒤 끝)")
	cb.free()


# ---------- W28: 1인칭 팔이 이동·평타 때 공중에 떠 보이던 문제 (팔꿈치 쪽 끝이 화면 안에 올라와 몸에 안 이어짐) ----------

# 한쪽 팔 (L 이면 +y 쪽 / R 이면 반대) 의 쉬는 자세 팔꿈치 → 손목 축에 꼭짓점을 비춘 값: [뒤로 (어깨 쪽) 가장 먼 길이 / 팔 길이, 열린 가장자리 중 팔꿈치 평면 (0.5 팔 길이) 보다 어깨 쪽 개수, 열린 가장자리 수]
func _vm_reach(info: Dictionary, side: String, mesh: ArrayMesh) -> Array:
	var el: Vector3 = (info.rest_global[int(info.map["elbow_" + side])] as Transform3D).origin
	var ha: Vector3 = (info.rest_global[int(info.map["hand_" + side])] as Transform3D).origin
	var ln := el.distance_to(ha)
	var ax := (ha - el).normalized()
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	# 이 쪽 팔 꼭짓점: 축에서 팔 길이의 0.6 배 안 (두 팔은 몸 폭만큼 떨어져 있음)
	var mine := {}
	var back := 0.0
	for i in vs.size():
		var d := vs[i] - el
		var t := d.dot(ax)
		if (d - ax * t).length() < ln * 0.6:
			mine[i] = true
			back = maxf(back, -t)
	var ks := PackedStringArray()
	for v in vs:
		ks.append("%d,%d,%d" % [roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5)])
	var ec := {}
	var ends := {}
	for i in range(0, idx.size(), 3):
		for k in 3:
			var ia: int = idx[i + k]
			var ib: int = idx[i + (k + 1) % 3]
			var a: String = ks[ia]
			var b: String = ks[ib]
			var e: String = (a + "|" + b) if a < b else (b + "|" + a)
			ec[e] = int(ec.get(e, 0)) + 1
			ends[e] = [ia, ib]
	var open := 0
	var open_back := 0
	for e in ec:
		if ec[e] == 1:
			var pair: Array = ends[e]
			if mine.has(pair[0]) and mine.has(pair[1]):
				open += 1
				if (vs[pair[0]] - el).dot(ax) < 0.0 and (vs[pair[1]] - el).dot(ax) < 0.0:
					open_back += 1
	return [back / ln, open_back, open]


func test_vm_arm_reaches_shoulder() -> void:
	for ch in ["ninja", "tank", "hunter", "hook"]:
		var info = Ext.load_char(ch)
		check(info != null and str(info.cfg.get("vm_node", "")) == ch + "_vm", "%s: 1인칭 팔은 닫힌 전용 메시 %s_vm" % [ch, ch])
		if info == null:
			continue
		var m: ArrayMesh = null
		for sf in info.surfs:
			if sf.vm_mesh != null:
				m = sf.vm_mesh
		check(m != null, "%s: 1인칭 팔 메시가 있음" % ch)
		if m == null:
			continue
		for side in ["L", "R"]:
			var r := _vm_reach(info, side, m)
			check(r[0] >= 2.0, "%s %s: 1인칭 팔이 팔꿈치에서 어깨 쪽으로 팔 길이의 %.2f 배 뻗음 (2 배 이상 — 이동·평타 때 끝이 화면 밖 아래·카메라 뒤)" % [ch, side, r[0]])
			check(r[1] <= 8, "%s %s: 팔꿈치 뒤 (소매 통) 에 열린 가장자리 %d (닫힌 끝 — 예전엔 팔꿈치 둘레가 열려 단면이 보임)" % [ch, side, r[1]])


# 이동·점프·대시·평타 자세 (tools/move_shot.gd 와 같은 상태표): [이름, 공중, 걷는 속도 비율, 걸음 위상, vz, 공중 대시, 평타 단계, u]
const VM_POSES := [
	["idle", false, 0.0, 0.0, 0.0, 0.0, "", 0.0],
	["walk", false, 1.0, 1.57, 0.0, 0.0, "", 0.0],
	["walk2", false, 1.0, 4.71, 0.0, 0.0, "", 0.0],
	["jump", true, 1.0, 0.0, 7.0, 0.0, "", 0.0],
	["fall", true, 1.0, 0.0, -9.0, 0.0, "", 0.0],
	["dash", true, 1.0, 0.0, 0.0, 1.0, "", 0.0],
	["wind", false, 0.0, 0.0, 0.0, 0.0, "wind", 0.6],
	["strike", false, 0.0, 0.0, 0.0, 0.0, "strike", 0.6],
	["strike_walk", false, 1.0, 1.57, 0.0, 0.0, "strike", 0.6],
	["rec", false, 0.0, 0.0, 0.0, 0.0, "rec", 0.5],
]


# 모든 자세에서 두 팔의 소매 통 먼 끝 (팔꿈치에서 손목 반대로 팔 길이의 2.4 배) 이 1인칭 카메라 시야 밖 — 윗단면이 화면에 올라와 공중에 떠 보이지 않음
func test_vm_arm_tip_offscreen() -> void:
	var was: bool = Body.use_ext
	Body.use_ext = true
	for ch in ["ninja", "tank", "hunter", "hook"]:
		var vm = VM_.new()
		vm._ready() # 트리 밖 (test_viewmodel_follows 와 같은 방식) — 카메라 좌표는 부모 변환을 직접 곱해서 셈
		var b = Chars.make_body(ch, Color(0.9, 0.4, 0.2))
		vm._sync(b)
		if vm.twin == null or vm.twin.ext == null:
			check(false, "%s 1인칭 외부 팔 없음" % ch)
			vm.free()
			b.free()
			continue
		var sk: Skeleton3D = vm.twin.ext.sk
		var info: Dictionary = vm.twin.ext.info
		var worst := ""
		var t := 1.0
		for s in VM_POSES:
			t += 1.0 / 60.0
			var atk: Dictionary = C.BASIC_ATTACKS[ch].chain[0]
			var act = null
			if str(s[6]) != "":
				act = {"id": 1, "move": atk.name, "phase": s[6], "u": s[7], "air": false}
			var st := {"air": s[1], "walking": float(s[2]) > 0.0 and not s[1], "hs": float(s[2]) * C.MOVE_SPEED, "walk": s[3], "vz": s[4], "t": t, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0, "holding": false, "hit": null,
				"act": act, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false, "sniffAt": null, "idle": 0.0, "airDash": s[5], "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}
			b.hs = float(s[2]) * C.MOVE_SPEED
			b.walk = s[3]
			b.vz = s[4]
			b.t = t
			b._figure_anim(st, 1.0 / 60.0)
			b._apply(1.0 / 60.0)
			b.cur_act = act
			vm._follow(1.0 / 60.0)
			vm.twin.ext.sync()
			for side in ["L", "R"]:
				var eb: Vector3 = sk.get_bone_global_pose(int(info.map["elbow_" + side])).origin
				var hb: Vector3 = sk.get_bone_global_pose(int(info.map["hand_" + side])).origin
				var tip := _vm_cam_point(vm, sk, eb - (hb - eb) * 2.4)
				if _vm_in_view(vm.cam.fov, tip):
					worst += " %s/%s" % [s[0], side]
		check(worst == "", "%s: 이동·평타 자세에서 소매 통 먼 끝이 시야 안:%s" % [ch, worst])
		vm.twin.free()
		b.free()
		vm.free()
	Body.use_ext = was


# 스켈레톤 좌표의 점 → 1인칭 카메라 좌표 (부모 변환을 카메라까지 곱함)
func _vm_cam_point(vm, sk: Skeleton3D, p: Vector3) -> Vector3:
	var n: Node = sk
	var v := p
	while n != null and n != vm.cam:
		if n is Node3D:
			v = (n as Node3D).transform * v
		n = n.get_parent()
	return v


# 카메라 좌표의 점이 시야 (세로 fov, 가로세로 16:9, 가까운 면 0.01) 안인가
func _vm_in_view(fov_deg: float, v: Vector3) -> bool:
	if -v.z < 0.01:
		return false
	var hh := tan(deg_to_rad(fov_deg) * 0.5) * -v.z
	return absf(v.y) <= hh and absf(v.x) <= hh * 16.0 / 9.0


# W30 미리 읽기·미리 그리기: 스레드로 요청한 파일도 같은 정보가 나오고, 한 번 더 부르면 새로 요청 안 함, warm_step 은 캐릭터마다 몸 하나를 두 프레임 두었다 치우고 끝나면 true
func test_preload_and_warm() -> void:
	for id in ["tank", "ninja", "hunter", "hook"]:
		Ext._cache.erase(id)
	Ext._req.clear()
	var n: int = Ext.request_all()
	check(n >= 4, "외부 모델 4개 이상 요청: %d" % n)
	check(Ext.request_all() == 0, "두 번째는 새로 요청 안 함")
	var info = Ext.load_char("hunter") # 요청해 둔 스레드 결과를 받음
	check(info != null and not info.surfs.is_empty(), "스레드로 읽은 hunter 정보")
	check(not Ext._req.has(Ext.glb_path("hunter")), "받은 뒤 요청 표시 지움")
	var host := Node3D.new()
	var prev: bool = Body.use_ext
	Body.use_ext = true
	Ext._warm_i = 0
	Ext._warm_body = null
	var made: Array = []
	var mk := func(id, col):
		made.append(id)
		return Chars.make_body(id, col)
	var steps := 0
	while not Ext.warm_step(host, mk) and steps < 200:
		steps += 1
		var alive := host.get_children().filter(func(c): return not c.is_queued_for_deletion())
		check(alive.size() <= 1, "미리 그리는 몸은 한 번에 하나")
	check(steps < 200, "미리 그리기가 끝남")
	check(made.has("tank") and made.has("ninja") and made.has("hunter") and made.has("hook"), "외부 4명 다 만듦: %s" % [made])
	check(host.get_children().filter(func(c): return not c.is_queued_for_deletion()).is_empty(), "끝나면 몸을 치움")
	Body.use_ext = prev
	for c in host.get_children():
		c.free()
	host.free()


# W30: 외부 모델 아틀라스는 VRAM 압축 (무손실이면 읽을 때 2048² 를 풀어 100ms 넘게 멈추고 영상 메모리가 5배) — 가져오기 설정 + 프로젝트 설정이 지켜지는지
func test_atlas_vram_compressed() -> void:
	var ps := FileAccess.get_file_as_string("res://project.godot")
	check(ps.contains("textures/vram_compression/import_s3tc_bptc=true"), "project.godot 에 S3TC·BPTC 가져오기 켬")
	for id in ["tank", "ninja", "hunter", "hook"]:
		var p := "res://assets/models/ext/%s_%s_atlas.jpg.import" % [id, id]
		check(FileAccess.get_file_as_string(p).contains("compress/mode=2"), "%s 아틀라스 VRAM 압축" % id)
		var tex = load("res://assets/models/ext/%s_%s_atlas.jpg" % [id, id])
		check(tex != null and (tex as Texture2D).get_image().is_compressed(), "%s 아틀라스를 압축 상태로 읽음" % id)
