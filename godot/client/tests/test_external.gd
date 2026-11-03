# W14 외부 뼈대 모델 (chars/external.gd, 안내 chars/EXTERNAL.md):
# ① 뼈 이름 자동 매칭 (Mixamo·Quaternius/Rigify·언리얼·Biped·Meshy/Tripo 식) + 덮어쓰기 + 골반 고침 ② 시험 로봇 (assets/models/ext/tank.glb) 정보
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
	var info = Ext.load_char("tank")
	check(info != null, "시험 로봇 tank.glb 읽음")
	if info == null:
		return
	for j in Ext.JOINTS:
		check(info.map.has(j), "로봇 관절 %s" % j)
	check(info.names[info.map.hips] == "Body" and info.names[info.map.hand_L] == "Palm2.L" and info.names[info.map.foot_R] == "Foot.R", "로봇 골반·손·발 뼈")
	check((info.box as AABB).size.y > 0.0 and info.surfs.size() >= 14, "상자·표면 %d" % info.surfs.size())
	check(info.anims.has("Wave") and info.anims.has("Dance"), "로봇 클립")
	check(Ext.load_char("dummy") == null and Ext.load_char("없는캐릭터") == null and not Ext.has_char("ninja"), "없는 캐릭터는 null")
	check(info.cfg.get("keep") == ["shields"] and info.cfg.get("tint") == "band" and float(info.cfg.yaw) == 90.0, "tank.json 덮음 + 기본 값")


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
	var b = _body("tank")
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
	var no = _body("ninja", true, true)
	check(no.ext == null, "외부 모델 없는 캐릭터는 그대로")
	no.free()
	var pieces = _body("tank", true, true, false)
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
	var b = _body("tank")
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
	var t = _body("tank", false)
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
	var b = _body("tank")
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
	var b = _body("tank")
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
