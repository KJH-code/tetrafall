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
	check(lods.size() == 4 and str(lods.high) == str(lods.medium) and str(lods.medium) == str(lods.low) and str(lods.stage) != str(lods.low), "LOD: stage 하나 + 판 셋이 같은 메시 하나")
	# 삼각형: 원본 1.94만 그대로 (대기실·초상·1인칭) + 판 약 8900 (UV 조각이 잘게 나뉘어 meshopt 가 이음선을 안 넘으면 이 밑으로 안 내려감)
	var want := {"stage": [15000, 20000], "high": [6000, 9500]}
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
	check(info.cfg.tint == "mask" and (info.cfg.attach as Array).is_empty() and (info.cfg.keep as Array).is_empty() and str(info.cfg.get("vm_node", "")) == "", "tank.json: mask·소품 없음 (방패·해머가 몸에 붙음, W20 소품·닫힌 팔 메시 뺌)")
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
	check(t.ext != null and not t.ext.third and t.ext.lod == str(t.ext.info.cfg.lods.stage), "1인칭 쌍둥이 = stage LOD")
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
	check(lods.size() == 4 and str(lods.high) == str(lods.medium) and str(lods.medium) == str(lods.low) and str(lods.stage) != str(lods.low), "LOD: stage 하나 + 판 셋이 같은 메시 하나")
	var want := {"stage": [15000, 20000], "high": [6000, 9500]}
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
	check(ext_n == 7 and b.drawn.size() == 7 and b.ext.band == null, "그리는 메시 7 (몸 + 단검 2 × 3 조각, 얻음 %d/%d)" % [ext_n, b.drawn.size()])
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
