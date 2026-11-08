# W14 외부 뼈대 모델 (.glb — Meshy·Tripo·Mixamo·Quaternius 류 사람형, T/A 포즈) 받아들이기 (안내서 chars/EXTERNAL.md)
# 방법 = 코드 구동 그대로: 몸 (body.gd) 은 예전처럼 관절 노드 (hips·waist·…·foot_L) 를 figure_motion·래그돌이 돌리고, 그 관절 노드는 안 그림.
# 여기서 매 프레임 관절의 '쉬는 자세 대비 회전 차이' 를 모델 뼈 (Skeleton3D) 에 옮김 → 스킨·뼈에 붙은 조각이 따라 움직임.
#   ① 뼈 이름 매칭: 우리 관절 → 모델 뼈 (대소문자·접두어 mixamorig:·Bip01·DEF-·좌우 표기 Left/L/.L/_l 무시, 별칭 표 ALIASES, 수동 덮어쓰기 <id>.json "bones")
#   ② 크기·자리: 모델 키 = C.PLAYER_HEIGHT × C.FIGURE_SCALE (예전 몸과 같은 키) × height, 발바닥을 바닥에, 앞 = 게임 +x (glTF 앞 +Z → yaw 90°)
#   ③ 뼈 맞추기: 뼈 전역 회전 = (관절 지금 회전 × 관절 처음 회전⁻¹) × 맞춤 회전 A × 뼈 쉬는 회전. A = 모델 뼈 방향 (뼈 → 자식 뼈) 을 우리 관절 방향으로 돌리는 최단 회전
#      (T 포즈 팔 → 우리 내린 팔). 자리: 골반은 관절 이동 × (모델 골반 높이 / 우리 골반 높이), 나머지는 '우리 부모 관절' 의 뼈에 쉬는 자세 상대 자리로 붙음 (IK 용으로 발 뼈가 뿌리 뼈 밑에 있어도 다리를 따라감)
#   ④ 재질: 원래 PBR 재질의 알베도 색·텍스처 그대로 G3 툰 (음영 단계 + 외곽선) 로 바꿈, 표면마다 MeshInstance3D 하나 (material_override — 반투명·한 겹 더·스텐실·위험 빛이 예전 몸과 같은 길)
#      몸 색: "keep" 텍스처 색 그대로 · "band" 그대로 + 허리에 플레이어 색 띠 · "tint" 플레이어 색을 곱함 (tint_k 만큼)
#   ⑤ 1인칭 팔 (viewmodel 쌍둥이, merge = false): 모델 장면을 허리 관절 아래에 붙이고 (viewmodel 이 허리를 카메라 앞으로 옮김) 팔 뼈 (vm_from 부터 아래) 에 붙은 삼각형만 남긴 메시
#   ⑥ 클립: 모델에 든 AnimationPlayer 동작 하나를 그대로 재생 (play_clip) — 그동안은 뼈 맞추기를 쉼
# 3단: 외부 모델 (assets/models/ext/<id>.glb, K.EXT 또는 실행 인자 --ext) → 구운 몸 (assets/models/<id>.glb) → 코드 조립 (bodies.bin)
extends RefCounted

const C := preload("res://core/config.gd")
const G3 := preload("res://shaders/g3.gd")
const K := preload("res://chars/chars_config.gd")
const ExtShadow := preload("res://chars/ext_shadow.gd")
const Clips := preload("res://chars/ext_clips.gd")
const Hitch := preload("res://core/hitch.gd")

const DIR := "res://assets/models/ext/"

# 우리 관절 이름 (BAKE.md·구운 몸 노드 이름과 같음) 순서 = 부모 먼저
const JOINTS := ["hips", "waist", "torso", "neck", "shoulder_R", "elbow_R", "hand_R", "shoulder_L", "elbow_L", "hand_L", "thigh_R", "knee_R", "foot_R", "thigh_L", "knee_L", "foot_L"]
# 우리 관절 나무의 부모 (자리 붙이기)
const PARENT := {"waist": "hips", "torso": "waist", "neck": "torso", "shoulder": "torso", "elbow": "shoulder", "hand": "elbow", "thigh": "hips", "knee": "thigh", "foot": "knee"}
# 방향 맞추기에 쓰는 자식 관절 (없으면 부모 관절의 맞춤을 그대로)
const CHILD := {"waist": "neck", "torso": "neck", "shoulder": "elbow", "elbow": "hand", "thigh": "knee", "knee": "foot"}
# 뼈 이름 별칭 (정리한 이름 = 소문자·구분자·좌우·접두어 뺌, 앞에 있을수록 먼저). Mixamo (Hips·Spine·Spine1·Spine2·Neck·Head·LeftShoulder=빗장·LeftArm·LeftForeArm·LeftHand·LeftUpLeg·LeftLeg·LeftFoot),
# Quaternius·블렌더 Rigify (Hips·Spine·Chest·UpperArm.L·LowerArm.L·Hand.L·UpperLeg.L·LowerLeg.L·Foot.L), 언리얼 (pelvis·spine_01~03·upperarm_l·lowerarm_l·thigh_l·calf_l),
# 3ds Max Biped (Bip01 L UpperArm·L Forearm·L Thigh·L Calf), Meshy·Tripo 자동 뼈 (Mixamo 식 이름이 많음 — 다르면 <id>.json "bones"),
# Tripo 자동 리깅 뼈 (BoneRoot·Hip·Pelvis·Waist·Spine01·Spine02·NeckTwist01·Head·L_Clavicle·L_Upperarm·L_Forearm·L_Hand·L_Thigh·L_Calf·L_Foot + 트위스트·ShareBone — 별칭으로 통함, 안 맞춘 뼈는 부모를 따라감)
const ALIASES := {
	"hips": ["hips", "pelvis", "hip", "cog"],
	"waist": ["spine", "abdomen", "spine01", "spine1", "lowerspine", "spinelower", "stomach"],
	"torso": ["chest", "upperchest", "spine2", "spine02", "spine03", "torso", "upperspine", "spineupper", "ribcage", "spine1", "spine01"],
	"neck": ["neck", "neck1", "neck01", "necktwist01", "necktwist", "head"],
	"shoulder": ["upperarm", "arm", "uparm", "humerus", "armupper"],
	"elbow": ["forearm", "lowerarm", "loarm", "elbow", "armlower"],
	"hand": ["hand", "wrist", "palm"],
	"thigh": ["upleg", "upperleg", "thigh", "legupper"],
	"knee": ["lowerleg", "calf", "shin", "leg", "knee", "loleg", "leglower"],
	"foot": ["foot", "ankle"],
}
# 꼭 있어야 하는 관절 (없으면 외부 모델 안 씀)
const REQUIRED := ["hips", "shoulder_R", "shoulder_L", "elbow_R", "elbow_L", "thigh_R", "thigh_L", "knee_R", "knee_L"]
const JUNK := ["mixamorig", "bip", "bip01", "bip001", "def", "org", "jnt", "joint", "bn", "armature", "skeleton", "sk", "rig", "character", "ctrl"]

static var _cache := {} # 캐릭터 → 모델 정보 (없으면 null)
static var _req := {} # W30: 스레드로 미리 요청한 파일 (경로 → true)
static var _warm_i := 0
static var _warm_wait := 0
static var _warm_body = null
static var stage := false # W19: 대기실 큰 캐릭터·초상 몸을 만드는 동안 참 (ui/portrait.gd still_body) → 최고 품질 LOD


# ---------- 파일 ----------

static func glb_path(char_id: String) -> String:
	return DIR + char_id + ".glb"


# 캐릭터의 외부 모델 정보 (없으면 null): {scene, cfg, ...} — 뼈 매칭·쉬는 자세·크기·표면 메시는 한 번만 셈 (몸끼리 같이 씀)
static func load_char(char_id: String):
	if _cache.has(char_id):
		return _cache[char_id]
	var out = null
	var gp := glb_path(char_id)
	var _ht := Hitch.t() # W30 히치 로거
	if ResourceLoader.exists(gp):
		var s = ResourceLoader.load_threaded_get(gp) if _req.has(gp) else load(gp)
		_req.erase(gp)
		Hitch.span("몸 불러오기", char_id + " 파일", _ht)
		if s is PackedScene:
			var _hm := Hitch.t()
			out = model_info(s, read_cfg(char_id))
			Hitch.span("몸 불러오기", char_id + " 정보", _hm)
	_cache[char_id] = out
	return out


static func has_char(char_id: String) -> bool:
	return load_char(char_id) != null


# W30 미리 읽기: 메뉴에서 쉴 때 모든 외부 모델 .glb (+ 클립 파일) 을 스레드로 요청 — 몸이 처음 나올 때 메인 스레드에서 읽느라 멈추지 않게.
# 파일 읽기·텍스처 올리기가 스레드에서 끝나 있어 load_char 는 장면 정보 셈 (수 ms) 만 함
static func request_all() -> int:
	var n := 0
	for id in C.FIGURE_CHARS:
		var gp := glb_path(id)
		if _cache.has(id) or _req.has(gp) or not ResourceLoader.exists(gp):
			continue
		if ResourceLoader.load_threaded_request(gp, "PackedScene", true) == OK:
			_req[gp] = true
			n += 1
		var cc = read_cfg(id).get("clips", {})
		var cp: String = str((cc as Dictionary).get("file", "")) if cc is Dictionary else ""
		if cp != "" and ResourceLoader.exists(cp) and not Clips.requested.has(cp) and ResourceLoader.load_threaded_request(cp, "PackedScene", true) == OK:
			Clips.requested[cp] = true
	return n


# W30 몸 미리 데우기: 메뉴·대기실 밖에서 쉴 때 한 번에 한 캐릭터씩 진짜 몸을 아주 작게 카메라 앞에 두 프레임 그려 셰이더·메시·텍스처를 올려 둠
# (첫 프레임이 새 캐릭터 몸을 처음 그리며 멈추지 않게). 반환: 다 끝났으면 true. host 는 카메라 앞에 둘 Node3D (world), 몸 만들기가 끝난 뒤에야 다음 캐릭터
static func warm_step(host: Node3D, make_body: Callable) -> bool:
	if _warm_body != null:
		_warm_wait -= 1
		if _warm_wait <= 0:
			_warm_body.queue_free()
			_warm_body = null
		return false
	if _warm_i >= C.FIGURE_CHARS.size():
		return true
	var id: String = C.FIGURE_CHARS[_warm_i]
	_warm_i += 1
	if not preload("res://chars/body.gd").use_ext or not ResourceLoader.exists(glb_path(id)):
		return false
	var _ht := Hitch.t()
	var b: Node3D = make_body.call(id, Color(0.8, 0.3, 0.3))
	var cam := host.get_viewport().get_camera_3d() if host.is_inside_tree() else null
	b.scale = Vector3.ONE * 0.001
	host.add_child(b)
	if cam:
		b.global_position = cam.global_position + (-cam.global_transform.basis.z) * 2.0
	_warm_body = b
	_warm_wait = 2
	Hitch.span("미리 그리기", "몸 " + id, _ht)
	return false


# 조정 값: chars_config.gd EXT_DEFAULTS 위에 assets/models/ext/<id>.json (있으면) 을 덮음
static func read_cfg(char_id: String) -> Dictionary:
	var cfg: Dictionary = K.EXT_DEFAULTS.duplicate(true)
	var jp := DIR + char_id + ".json"
	if FileAccess.file_exists(jp):
		var j = JSON.parse_string(FileAccess.get_file_as_string(jp))
		if j is Dictionary:
			for k in j:
				cfg[k] = j[k]
		else:
			push_warning("외부 .glb 조정 파일 %s: JSON 오류" % jp)
	return cfg


# ---------- ① 뼈 이름 ----------

# 뼈 이름 정리 → {core, side ("L"·"R"·"")}. 'mixamorig:LeftForeArm' → forearm L · 'upperarm_l' → upperarm L · 'Bip01 R Calf' → calf R · 'DEF-upper_arm.L' → upperarm L · 'Head_2' → head2
static func normalize(name: String) -> Dictionary:
	var s := name
	var cut: int = maxi(s.rfind(":"), s.rfind("|"))
	if cut >= 0:
		s = s.substr(cut + 1)
	var re := RegEx.create_from_string("([a-z0-9])([A-Z])")
	s = re.sub(s, "$1 $2", true)
	var toks := RegEx.create_from_string("[A-Za-z0-9]+").search_all(s)
	var side := ""
	var core := ""
	for m in toks:
		var t: String = m.get_string().to_lower()
		if t == "l" or t == "left":
			side = "L"
			continue
		if t == "r" or t == "right":
			side = "R"
			continue
		if t in JUNK:
			continue
		if core == "" and t.length() > 4 and t.begins_with("left"):
			side = "L"
			t = t.substr(4)
		elif core == "" and t.length() > 5 and t.begins_with("right"):
			side = "R"
			t = t.substr(5)
		core += t
	return {"core": core, "side": side}


# 끝 숫자 뺀 이름 ('head2' → 'head', 'spine01' → 'spine') — 정확히 맞는 뼈가 없을 때만
static func _strip_digits(core: String) -> String:
	var i := core.length()
	while i > 0 and core[i - 1] >= "0" and core[i - 1] <= "9":
		i -= 1
	return core.substr(0, i)


static func _joint_base(j: String) -> String:
	return j.split("_")[0]


static func _joint_side(j: String) -> String:
	return j.split("_")[1] if j.contains("_") else ""


# 뼈 이름 목록 → {우리 관절: 뼈 번호}. overrides = {"hand_L": "Palm2.L", "neck": ""} (빈 글자 = 안 씀). parents (있으면) 로 골반 고침:
# 고른 골반 뼈가 두 허벅지의 조상이 아니면 두 허벅지·허리 뼈의 가장 가까운 공통 조상 (로봇 모델: Hips 옆에 다리가 Body 아래)
static func match_bones(names: PackedStringArray, overrides: Dictionary = {}, parents: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	var norm: Array = []
	for n in names:
		norm.append(normalize(n))
	var used := {}
	var out := {}
	# W19: 꼭 있어야 하는 관절이 모두 우리 이름 그대로 (shoulder_R …, tools/blender) 인 모델이면 이름이 같은 뼈를 먼저 (Rigify 'torso' 같은 조종 뼈와 안 섞이게 그때만)
	var ours := true
	for j in REQUIRED:
		if names.find(j) < 0:
			ours = false
			break
	for j in JOINTS:
		if ours and not overrides.has(j) and names.find(j) >= 0 and not used.has(names.find(j)):
			out[j] = names.find(j)
			used[names.find(j)] = true
			continue
		if overrides.has(j):
			var want := str(overrides[j])
			var bi := names.find(want)
			if want != "" and bi < 0:
				push_warning("외부 .glb 뼈 덮어쓰기 %s → '%s' 가 없음" % [j, want])
			if bi >= 0:
				out[j] = bi
				used[bi] = true
			continue
		var base := _joint_base(j)
		var side := _joint_side(j)
		var found := -1
		for strip in [false, true]:
			for alias in ALIASES[base]:
				for bi in names.size():
					if used.has(bi) or norm[bi].side != side:
						continue
					var core: String = norm[bi].core
					if strip:
						core = _strip_digits(core)
					if core == alias:
						found = bi
						break
				if found >= 0:
					break
			if found >= 0:
				break
		if found >= 0:
			out[j] = found
			used[found] = true
	if parents.size() == names.size() and out.has("thigh_L") and out.has("thigh_R") and not overrides.has("hips"):
		var h: int = out.get("hips", -1)
		if h < 0 or not (_is_ancestor(parents, h, out.thigh_L) and _is_ancestor(parents, h, out.thigh_R)):
			var lca := _common(parents, out.thigh_L, out.thigh_R)
			if out.has("waist"):
				lca = _common(parents, lca, out.waist)
			if lca >= 0:
				if out.get("waist", -1) == lca:
					out.erase("waist")
				out.hips = lca
	return out


static func _is_ancestor(parents: PackedInt32Array, a: int, b: int) -> bool:
	var k := parents[b]
	while k >= 0:
		if k == a:
			return true
		k = parents[k]
	return false


static func _common(parents: PackedInt32Array, a: int, b: int) -> int:
	var up := {}
	var k := a
	while k >= 0:
		up[k] = true
		k = parents[k]
	k = b
	while k >= 0:
		if up.has(k):
			return k
		k = parents[k]
	return -1


# ---------- 모델 정보 (한 번) ----------

static func _skeleton(root: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for s in root.find_children("*", "Skeleton3D", true, false):
		if best == null or (s as Skeleton3D).get_bone_count() > best.get_bone_count():
			best = s
	return best


# n → 위로 stop 까지 transform 곱 (stop 은 빼고). 뼈에 붙은 조각 (BoneAttachment3D) 은 그 뼈의 쉬는 자리로
static func _rest_rel(n: Node, stop: Node, sk: Skeleton3D, sk_rel: Transform3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != stop:
		if n is BoneAttachment3D and sk != null and n.get_parent() == sk:
			var bi := sk.find_bone((n as BoneAttachment3D).bone_name)
			if bi >= 0:
				return sk_rel * sk.get_bone_global_rest(bi) * t
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# 장면 → 정보: 뼈 (이름·부모·쉬는 자세·부모 먼저 순서), 매칭, 키·발바닥, 표면 목록 (원래 MeshInstance3D 경로·표면 번호·색·텍스처·한 표면 메시), 1인칭 팔 메시
static func model_info(scene: PackedScene, cfg: Dictionary):
	var root := scene.instantiate()
	var sk := _skeleton(root)
	if sk == null or not (root is Node3D):
		push_warning("외부 .glb 에 Skeleton3D 가 없음")
		root.free()
		return null
	var nb := sk.get_bone_count()
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	for i in nb:
		names.append(sk.get_bone_name(i))
		parents.append(sk.get_bone_parent(i))
	var map := match_bones(names, cfg.get("bones", {}), parents)
	var missing := []
	for j in REQUIRED:
		if not map.has(j):
			missing.append(j)
	if not missing.is_empty():
		push_warning("외부 .glb 에 없는 뼈: %s (<id>.json 'bones' 로 덮어쓰기)" % [missing])
		root.free()
		return null
	var order: Array[int] = []
	var kids := {}
	for i in nb:
		kids[parents[i]] = kids.get(parents[i], []) + [i]
	var stack: Array = (kids.get(-1, []) as Array).duplicate()
	stack.reverse()
	while not stack.is_empty():
		var b: int = stack.pop_back()
		order.append(b)
		var ch: Array = (kids.get(b, []) as Array).duplicate()
		ch.reverse()
		stack.append_array(ch)
	var sk_rel := _rest_rel(sk, root, null, Transform3D.IDENTITY) # 뼈대 공간 → 모델 뿌리
	var rest_local: Array[Transform3D] = []
	var rest_global: Array[Transform3D] = []
	for i in nb:
		rest_local.append(sk.get_bone_rest(i))
		rest_global.append(sk.get_bone_global_rest(i))
	# 표면: 원래 메시마다·표면마다
	var surfs: Array = []
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := _rest_rel(m, root, sk, sk_rel)
		var skinned := m.skin != null
		if skinned:
			xf = _rest_rel(m, root, null, Transform3D.IDENTITY) # 스킨 메시는 정점이 쉬는 자세 그대로 (bind) — 메시 노드 자리
		var ab: AABB = xf * m.mesh.get_aabb()
		box = ab if first else box.merge(ab)
		first = false
		var bone := -1
		var pn := m.get_parent()
		while pn != null and pn != sk and pn != root:
			if pn is BoneAttachment3D:
				bone = sk.find_bone((pn as BoneAttachment3D).bone_name)
				break
			pn = pn.get_parent()
		for si in m.mesh.get_surface_count():
			var mat = m.get_surface_override_material(si)
			if mat == null:
				mat = m.mesh.surface_get_material(si)
			var col := Color.WHITE
			var tex = null
			if mat is BaseMaterial3D:
				col = (mat as BaseMaterial3D).albedo_color
				tex = (mat as BaseMaterial3D).albedo_texture
			var binds := PackedInt32Array() # 스킨 bind 번호 → 뼈 번호 (bind 가 이름으로만 이어진 것도)
			if skinned:
				for k in m.skin.get_bind_count():
					var bb: int = m.skin.get_bind_bone(k)
					binds.append(bb if bb >= 0 else sk.find_bone(m.skin.get_bind_name(k)))
			var one := _one_surface(m.mesh, si)
			# W19: 이름이 _unlit 로 끝나는 재질 (tools/blender — 눈 흰자) 은 빛 안 받는 색 (JS eyeWhiteMat), 외곽선 없음
			var unlit: bool = mat != null and str(mat.resource_name).ends_with("_unlit")
			# W19: 이름이 _face 로 끝나는 재질 = 얼굴 (표정 텍스처를 바꿔 끼움, 외곽선 없음), 메시 노드 이름 = LOD 이름 (cfg.lods)
			var face: bool = mat != null and str(mat.resource_name).ends_with("_face")
			surfs.append({"path": root.get_path_to(m), "surf": si, "mesh": one, "color": col, "tex": tex, "skinned": skinned, "bone": bone, "binds": binds,
				"vcolor": Ext.vertex_colored(one, 0, mat, str(cfg.get("tint", "band"))) and not unlit and not face, "unlit": unlit, "face": face, "node": str(m.name)})
	if first:
		push_warning("외부 .glb 에 메시가 없음")
		root.free()
		return null
	var info := {"scene": scene, "cfg": cfg, "names": names, "parents": parents, "map": map, "order": order, "rest_local": rest_local, "rest_global": rest_global,
		"sk_path": root.get_path_to(sk), "sk_rel": sk_rel, "box": box, "surfs": surfs, "anims": []}
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		info.anims = Array((ap as AnimationPlayer).get_animation_list())
		break
	info.vm_bones = _vm_bones(info)
	# W23 동작 클립 (cfg.clips.file = 뼈대·동작만 든 .glb, 안 쓰면 {}) — 몸끼리 같이 씀
	var cc = cfg.get("clips", {})
	info.clipset = Clips.load_lib(str((cc as Dictionary).get("file", ""))) if cc is Dictionary else {}
	var vm_node: String = str(cfg.get("vm_node", ""))
	for sf in surfs:
		# W20 vm_node: 1인칭 팔 = glb 안에 따로 만든 닫힌 팔 메시 (노드 이름) 통째로. 없으면 예전 (팔꿈치 아래 삼각형 가르기)
		if vm_node != "":
			sf.vm_mesh = sf.mesh if str(sf.node) == vm_node else null
		else:
			sf.vm_mesh = _arm_mesh(sf, info.vm_bones)
	root.free()
	return info


# 한 표면만 든 메시 (모프·LOD 는 버림)
static func _one_surface(mesh: Mesh, si: int) -> ArrayMesh:
	var am := ArrayMesh.new()
	var arr := mesh.surface_get_arrays(si)
	var flags := 0
	if mesh is ArrayMesh:
		flags = (mesh as ArrayMesh).surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	am.add_surface_from_arrays(mesh.surface_get_primitive_type(si) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return am


# 1인칭 팔에 남길 뼈: vm_from ("elbow" 또는 "shoulder") 관절 뼈와 그 아래 전부
static func _vm_bones(info: Dictionary) -> Dictionary:
	var out := {}
	var from: String = str(info.cfg.get("vm_from", "elbow"))
	for side in ["R", "L"]:
		var j: String = from + "_" + side
		if info.map.has(j):
			out[int(info.map[j])] = true
	var parents: PackedInt32Array = info.parents
	for b in info.order:
		if parents[b] >= 0 and out.has(parents[b]):
			out[b] = true
	return out


# 1인칭 팔 메시: 뼈에 붙은 조각은 그 뼈가 팔이면 통째로, 스킨 메시는 세 정점 모두 가장 센 뼈가 팔인 삼각형만 (없으면 null)
static func _arm_mesh(sf: Dictionary, arm: Dictionary):
	if not sf.skinned:
		return sf.mesh if arm.has(int(sf.bone)) else null
	var binds: PackedInt32Array = sf.binds
	var mesh: ArrayMesh = sf.mesh
	var arr := mesh.surface_get_arrays(0)
	var bones = arr[Mesh.ARRAY_BONES]
	var weights = arr[Mesh.ARRAY_WEIGHTS]
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if bones == null or weights == null or vs.is_empty():
		return null
	var per: int = 8 if (mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
	var keep := PackedByteArray()
	keep.resize(vs.size())
	for v in vs.size():
		var best := -1
		var bw := -1.0
		for k in per:
			if weights[v * per + k] > bw:
				bw = weights[v * per + k]
				best = int(bones[v * per + k])
		var sb: int = binds[best] if best >= 0 and best < binds.size() else -1
		keep[v] = 1 if arm.has(sb) else 0
	var idx = arr[Mesh.ARRAY_INDEX]
	var tri := PackedInt32Array()
	if idx == null or (idx as PackedInt32Array).is_empty():
		for i in range(0, vs.size() - 2, 3):
			if keep[i] and keep[i + 1] and keep[i + 2]:
				tri.append_array([i, i + 1, i + 2])
	else:
		var ia: PackedInt32Array = idx
		for i in range(0, ia.size() - 2, 3):
			if keep[ia[i]] and keep[ia[i + 1]] and keep[ia[i + 2]]:
				tri.append_array([ia[i], ia[i + 1], ia[i + 2]])
	if tri.is_empty():
		return null
	arr[Mesh.ARRAY_INDEX] = tri
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	return am


# ---------- 몸에 붙이기 ----------

# body.gd build 가 부름 (외부 모델이 있으면). 안쪽 몸은 조각 몸 (merge = false) 으로 만들어져 있음.
# third = 판·대기실·초상 몸 (body.build 의 merge), 아니면 1인칭 팔 쌍둥이. 돌려줌 = Ext (body.ext), 실패면 null (몸은 그대로 안쪽 몸)
static func attach(body: Node3D, third: bool):
	var info = load_char(body.char_id)
	if info == null:
		return null
	var e := Ext.new()
	e.lod = pick_lod(info.cfg, third, stage)
	e.shadow_lod = ExtShadow.caster_node(info.cfg, e.lod, third, stage)
	var _ht := Hitch.t()
	if not e.setup(body, info, third):
		e.free()
		return null
	Hitch.span("외부 몸 연결", body.char_id, _ht)
	return e


# W19 LOD: 1인칭 쌍둥이·대기실 큰 캐릭터·초상 = stage (한 명만 크게), 판 몸 = 화질 (world/gfx.gd plan.level — 없으면 high). cfg.lods 없으면 "" (모든 메시)
static func pick_lod(cfg: Dictionary, third: bool, on_stage: bool) -> String:
	var lods: Dictionary = cfg.get("lods", {})
	if lods.is_empty():
		return ""
	if not third and str(cfg.get("vm_node", "")) != "":
		return str(cfg.vm_node)
	if not third or on_stage:
		return str(lods.get("stage", lods.get("high", "")))
	var Gfx = load("res://world/gfx.gd") # preload 하면 -s 도구 (자동 로드 View 전) 에서 컴파일이 깨짐
	var plan: Dictionary = Gfx.plan
	var lv: String = str(plan.get("level", "high")) if not plan.is_empty() else "high"
	return str(lods.get(lv, lods.get("high", "")))


# 몸에 붙은 외부 모델 하나 (frame 또는 허리 관절 아래 Node3D)
class Ext extends Node3D:
	const G3_ := preload("res://shaders/g3.gd")
	const C_ := preload("res://core/config.gd")
	const K_ := preload("res://chars/chars_config.gd")
	# 소품 .glb (glTF Y 위·앞 +Z) → 게임 좌표 (앞 +x, 왼쪽 +y, 위 +z): attach "ref" 소품은 게임 좌표로 만든 것 (tools/blender — Blender (X, Y, Z) = (y, -x, z))
	const GLTF_TO_GAME_ := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
	const JOINTS_ := ["hips", "waist", "torso", "neck", "shoulder_R", "elbow_R", "hand_R", "shoulder_L", "elbow_L", "hand_L", "thigh_R", "knee_R", "foot_R", "thigh_L", "knee_L", "foot_L"]
	const PARENT_ := {"waist": "hips", "torso": "waist", "neck": "torso", "shoulder": "torso", "elbow": "shoulder", "hand": "elbow", "thigh": "hips", "knee": "thigh", "foot": "knee"}
	const CHILD_ := {"waist": "neck", "torso": "neck", "shoulder": "elbow", "elbow": "hand", "thigh": "knee", "knee": "foot"}

	# 꼭짓점 색을 쓸 표면: 정점 색이 있고 (tint "mask" 거나 원래 재질이 꼭짓점 색을 알베도로 씀)
	static func vertex_colored(mesh: Mesh, si: int, mat, tint: String) -> bool:
		if mesh == null or not (mesh is ArrayMesh) or ((mesh as ArrayMesh).surface_get_format(si) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			return false
		return tint == "mask" or (mat is BaseMaterial3D and (mat as BaseMaterial3D).vertex_color_use_as_albedo)


	# 툰 재질 (외부 모델·소품 표면): 꼭짓점 색이면 정점 색 × 알베도, tint "mask" 면 몸 색 칸 (UV2.x = 1, tools/blender) 을 플레이어 색으로 (skin_tint — 구운 몸과 같은 길)
	static func toon_for(col: Color, tex, vcolor: bool, mask: bool, skin: Color, extra := {}) -> ShaderMaterial:
		var opts := extra.duplicate()
		if tex != null:
			opts.map = tex
		if vcolor:
			opts.vertex_color = true
		var m := G3_.toon_material(col, opts)
		if vcolor and mask:
			m.set_shader_parameter("skin_tint", Color(skin.r, skin.g, skin.b, 1.0))
		return m

	# 빛 안 받는 색 (눈 흰자): 툰 재질의 알베도 검정 + 발광 = 색 → 하늘빛·해 음영 없이 그 색 (외곽선 없음, op < 1 이면 반투명)
	static func unlit_for(col: Color, op: float) -> ShaderMaterial:
		var opts := {"emissive": Color(col.r, col.g, col.b), "outline": false}
		if op < 1.0:
			opts.opacity = op
		return G3_.toon_material(Color(0, 0, 0), opts)

	# W19 재질 손질 (cfg): 몸 색 칸은 곱하기 (mask), 툰 단계·림 빛, 외곽선 굵기 (outline = false 면 외곽선 없앰)
	static func style(m: ShaderMaterial, cfg: Dictionary, outline := true) -> ShaderMaterial:
		if str(cfg.get("tint", "band")) == "mask":
			m.set_shader_parameter("skin_multiply", true)
		if cfg.has("toon_steps"):
			var ts: Array = cfg.toon_steps
			m.set_shader_parameter("toon_steps", Vector3(float(ts[0]), float(ts[1]), float(ts[2])))
		var rim: Array = cfg.get("rim", [0.0, 3.0])
		if float(rim[0]) > 0.0:
			m.set_shader_parameter("rim_strength", float(rim[0]))
			m.set_shader_parameter("rim_power", float(rim[1]))
		if not outline:
			m.next_pass = null
		elif m.next_pass != null and float(cfg.get("outline", 1.0)) != 1.0:
			m.next_pass = G3_.shared_outline(C_.OUTLINE_THICKNESS * float(cfg.outline))
		return m

	var body: Node3D
	var info: Dictionary
	var third := true
	var space: Node3D # 관절 자리를 재는 기준 노드 (판 몸 = frame, 1인칭 팔 = 허리 관절)
	var model: Node3D # .glb 장면 뿌리
	var sk: Skeleton3D
	var W := Transform3D.IDENTITY # 뼈대 공간 → space
	var Wi := Transform3D.IDENTITY
	var qw := Quaternion.IDENTITY
	var qwi := Quaternion.IDENTITY
	var maps: Array = [] # [{joint, bone, qref_inv, C (Basis, 뼈대 공간), anchor, off (Transform3D), root, jref, prest (space)}]
	var glob: Array[Transform3D] = [] # 뼈대 공간 전역 (매 프레임)
	var mapped := {} # 뼈 번호 → maps 번호
	var parts: Array = [] # [{mi, color, tex, solid, alpha}]
	var band: MeshInstance3D = null
	var anim: AnimationPlayer = null
	var clip := "" # 재생 중인 클립 (빈 글자 = 뼈 맞추기)
	var lod := "" # 그릴 메시 노드 이름 (pick_lod, 빈 글자 = 전부)
	var shadow_lod := "" # W32: 그림자만 던질 가장 낮은 LOD 노드 이름 (chars/ext_shadow.gd, 빈 글자 = 보이는 메시가 그림자도 던짐)
	var face_tex := {} # 표정 → Texture2D (cfg.faces)
	var face_now := ""
	var root_k := 1.0
	var opacity := 1.0
	# W23 동작 클립 층 (ext_clips.gd): 코드 구동 위에 뼈 회전을 클립 쪽으로 섞음 (cw = 섞는 정도)
	const Rag_ := preload("res://chars/ragdoll.gd")
	const Clips_ := preload("res://chars/ext_clips.gd")
	var clipset: Dictionary = {}
	var cbones := {} # 클립 뼈 이름 → 뼈 번호
	var cw := 0.0
	var air_t := 0.0
	var last_t := 0.0
	var cur_clip := ""
	var last_sel := {}
	var last_layer := {} # 뼈 이름 → Quaternion (지난 프레임 클립 층 결과, 클립이 바뀔 때 크로스페이드 시작점)
	var fade_from := {}
	var fade_t := 1.0
	var clip_dirty := false # 클립 층이 풀어 둔 뼈를 쉬는 자세로 되돌려야 함
	var forced := {} # 확인용 (tools/clip_shot.gd): {clip, t, air} 를 강제
	var clip_info := {} # 확인용: 마지막 프레임 {clip, cw, dy}
	const Cloth_ := preload("res://chars/ext_cloth.gd")
	var cloths: Array = [] # 천·끈 사슬 (cfg.cloth, ext_cloth.gd) — 판 몸만
	var cloth_t := 0.0

	func setup(b: Node3D, inf: Dictionary, third_: bool) -> bool:
		body = b
		info = inf
		third = third_
		name = "ext"
		space = b.frame if third else b.waist
		if space == null:
			return false
		model = (info.scene as PackedScene).instantiate() as Node3D
		sk = model.get_node_or_null(info.sk_path) as Skeleton3D
		if sk == null:
			model.free()
			return false
		add_child(model)
		space.add_child(self)
		_place()
		_bind()
		_surfaces()
		_hide_inner()
		if third:
			_band()
		_attach_props()
		anim = null
		for ap in model.find_children("*", "AnimationPlayer", true, false):
			anim = ap
			anim.active = false
			break
		if not third:
			process_priority = 100 # 1인칭 쌍둥이는 pose 가 안 불림 (viewmodel 이 관절만 베낌) → 그 뒤에 맞춤
			set_process(true)
		else:
			set_process(false)
		if third:
			for cdef in info.cfg.get("cloth", []):
				var cl = Cloth_.new()
				if cl.setup(sk, cdef.get("bones", []), info, cdef):
					cloths.append(cl)
		clipset = info.get("clipset", {})
		for cn in clipset:
			for bn in (clipset[cn].rot as Dictionary):
				if not cbones.has(bn):
					cbones[bn] = sk.find_bone(bn)
		sync()
		return true

	func _process(_d: float) -> void:
		sync()

	# 관절 n → space 기준 transform (못 닿으면 null)
	func _rel(n: Node) -> Variant:
		var t := Transform3D.IDENTITY
		while n != null and n != space:
			if not (n is Node3D):
				return null
			t = (n as Node3D).transform * t
			n = n.get_parent()
		return t if n == space else null

	# 밧줄·쇠사슬이 나가는 자리 (cfg rope_bone = 뼈 이름 끝, 예 "LeftHandMiddle4"): 모델 손 (갈고리) 뼈의 몸 (body) 기준 위치 — 호출 쪽이 body.global_transform 을 곱함.
	# 없으면 null (코드 손 관절을 씀 — 모델 팔 길이가 달라 20 cm 쯤 어긋남). 트리 밖에서도 됨 (뼈 지역 자세를 직접 곱함)
	func rope_point() -> Variant:
		return bone_point(str(info.cfg.get("rope_bone", "")))

	# 뼈 (이름이 name_end 로 끝남) 의 몸 (body) 기준 위치. 뼈 지역 자세를 직접 곱함 (트리 밖·그리기 전에도 맞음). 없으면 null.
	# 초상 (ui/portrait.gd) 이 머리 뼈로 얼굴 자리를 잡음
	func bone_point(name_end: String) -> Variant:
		if name_end == "" or sk == null:
			return null
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).ends_with(name_end):
				var t := sk.get_bone_pose(i)
				var p := sk.get_bone_parent(i)
				while p >= 0:
					t = sk.get_bone_pose(p) * t
					p = sk.get_bone_parent(p)
				return _body_rel(sk) * t.origin
		return null

	func _body_rel(n: Node) -> Transform3D:
		var t := Transform3D.IDENTITY
		while n != null and n != body:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		return t

	func _joint(j: String) -> Node3D:
		match j:
			"hips": return body.hips
			"waist": return body.waist
			"torso": return body.torso
			"neck": return body.neck
		var base: String = j.split("_")[0]
		var i := 0 if j.ends_with("_R") else 1
		match base:
			"shoulder": return body.shoulders[i]
			"elbow": return body.elbows[i]
			"hand": return body.hands[i]
			"thigh": return body.thighs[i]
			"knee": return body.knees[i]
			"foot": return body.feet[i]
		return null

	# 크기·방향·발바닥: 모델 뿌리 → 몸 (body) = yaw·크기·옮김, 그걸 space 기준으로
	func _place() -> void:
		var cfg: Dictionary = info.cfg
		var box: AABB = info.box
		var h := maxf(1e-6, box.size.y)
		var target: float = C_.PLAYER_HEIGHT * C_.FIGURE_SCALE * float(cfg.get("height", 1.0))
		var s := target / h
		var basis := Basis(Vector3.UP, deg_to_rad(float(cfg.get("yaw", 90.0)))).scaled(Vector3.ONE * s)
		var foot := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
		var off: Array = cfg.get("offset", [0, 0, 0])
		var tb := Transform3D(basis, -(basis * foot) + Vector3(float(off[0]), float(off[1]), float(off[2])))
		var sp := _body_rel(space)
		transform = sp.affine_inverse() * tb
		W = transform * (info.sk_rel as Transform3D)
		Wi = W.affine_inverse()
		qw = W.basis.get_rotation_quaternion()
		qwi = qw.inverse()

	# 쉬는 자세 맞춤: 관절마다 처음 회전·자리, 뼈 맞춤 회전 A (뼈 방향 → 관절 방향)
	func _bind() -> void:
		var rg: Array = info.rest_global
		var map: Dictionary = info.map
		glob.resize(rg.size())
		for i in rg.size():
			glob[i] = rg[i]
		sk.reset_bone_poses()
		var align := {} # 관절 → A (space 회전)
		var root_done := false
		for j in JOINTS_:
			if not map.has(j):
				continue
			var jn := _joint(j)
			var jr = _rel(jn) if jn != null else null
			if jr == null:
				continue
			var bi: int = map[j]
			var base: String = j.split("_")[0]
			var side: String = "_" + j.split("_")[1] if j.contains("_") else ""
			var bpos: Vector3 = (W * (rg[bi] as Transform3D)).origin
			var A := Quaternion.IDENTITY
			var cj = CHILD_.get(base)
			var pj = PARENT_.get(base)
			if cj != null and map.has(cj + (side if cj in ["elbow", "hand", "knee", "foot"] else "")):
				var cname: String = cj + (side if cj in ["elbow", "hand", "knee", "foot"] else "")
				var cn := _joint(cname)
				var cr = _rel(cn) if cn != null else null
				if cr != null:
					var dj: Vector3 = (cr as Transform3D).origin - (jr as Transform3D).origin
					var db: Vector3 = (W * (rg[int(map[cname])] as Transform3D)).origin - bpos
					if dj.length() > 1e-6 and db.length() > 1e-6:
						A = Quaternion(db.normalized(), dj.normalized())
			elif pj != null:
				var pname: String = pj + (side if pj in ["shoulder", "elbow", "thigh", "knee"] else "")
				A = align.get(pname, Quaternion.IDENTITY)
			if base in ["hips"]:
				A = Quaternion.IDENTITY
			align[j] = A
			var m := {"joint": jn, "bone": bi, "qref_inv": (jr as Transform3D).basis.get_rotation_quaternion().inverse(),
				"C": Basis(qwi * A * qw) * (rg[bi] as Transform3D).basis, "jref": (jr as Transform3D).origin, "prest": bpos, "root": false, "anchor": -1, "off": Transform3D.IDENTITY,
				"snap": not third and base in info.cfg.get("vm_snap", ["elbow"])}
			# 자리: 처음 닿는 관절 = 뿌리 (관절 이동을 키 비율로), 나머지는 우리 부모 관절의 뼈에 쉬는 자세 상대 자리로
			var anc := -1
			var pp = pj
			while pp != null and anc < 0:
				var pn2: String = pp + (side if pp in ["shoulder", "elbow", "thigh", "knee"] else "")
				if mapped.has(int(map.get(pn2, -1))):
					anc = int(map[pn2])
				pp = PARENT_.get(pp)
			if not root_done:
				m.root = true
				root_done = true
				var our_h: float = _body_rel(jn).origin.y
				var mod_h: float = (_body_rel(self) * (info.sk_rel as Transform3D) * (rg[bi] as Transform3D)).origin.y
				root_k = mod_h / our_h if absf(our_h) > 1e-4 else 1.0
			elif anc >= 0:
				m.anchor = anc
				m.off = (rg[anc] as Transform3D).affine_inverse() * (rg[bi] as Transform3D)
			mapped[bi] = maps.size()
			maps.append(m)

	# 표정 (cfg.faces): 경직·맞은 직후 = hit, 공격 동작 = attack, 나머지 idle
	func expression() -> String:
		if body.get("was_stunned") == true:
			return "hit"
		var h = body.get("hit")
		if h is Dictionary and Time.get_ticks_msec() / 1000.0 - float(h.get("t0", -99.0)) < K_.EXT_HIT_FACE_S:
			return "hit"
		if body.get("cur_act") != null:
			return "attack"
		return "idle"

	func _face_sync() -> void:
		if face_tex.is_empty():
			return
		var e := expression()
		if e == face_now or not face_tex.has(e):
			return
		face_now = e
		for pt in parts:
			if pt.get("face", false):
				pt.tex = face_tex[e]
				(pt.solid as ShaderMaterial).set_shader_parameter("albedo_tex", pt.tex)
				if pt.has("alpha"):
					(pt.alpha as ShaderMaterial).set_shader_parameter("albedo_tex", pt.tex)

	# 매 프레임: 관절 → 뼈 (st = body._anim_state — 있으면 동작 클립 층도, 판 몸만)
	func sync(st = null) -> void:
		_face_sync()
		if clip != "" or sk == null:
			return
		_code_sync()
		if third and not clipset.is_empty() and (st != null or not forced.is_empty()):
			_clip_layer(st)
		if not cloths.is_empty():
			var now := Time.get_ticks_msec() * 0.001
			var cdt := clampf(now - cloth_t, 0.0, 0.1) if cloth_t > 0.0 else 0.0
			cloth_t = now
			for cl in cloths:
				cl.step(cdt)

	func _code_sync() -> void:
		for m in maps:
			var jr = _rel(m.joint)
			if jr == null:
				continue
			var jt: Transform3D = jr
			var d: Quaternion = jt.basis.get_rotation_quaternion() * m.qref_inv
			var bas := Basis(qwi * d * qw) * (m.C as Basis)
			var pos: Vector3
			if m.snap: # 1인칭 팔: 팔꿈치 뼈를 우리 팔꿈치 관절 자리에 (viewmodel 이 맞춘 화면 구석 자리 — 모델 팔 길이·어깨 자리가 달라도)
				pos = Wi * jt.origin
			elif m.root:
				pos = Wi * ((m.prest as Vector3) + (jt.origin - (m.jref as Vector3)) * root_k)
			elif int(m.anchor) >= 0:
				pos = (glob[int(m.anchor)] * (m.off as Transform3D)).origin
			else:
				pos = Vector3.INF
			glob[int(m.bone)] = Transform3D(bas, pos)
		var parents: PackedInt32Array = info.parents
		var rl: Array = info.rest_local
		for b in info.order:
			var p := parents[b]
			if mapped.has(b):
				var g: Transform3D = glob[b]
				if g.origin == Vector3.INF: # 자리 기준이 없음 → 부모 아래 쉬는 자리
					g.origin = ((glob[p] if p >= 0 else Transform3D.IDENTITY) * (rl[b] as Transform3D)).origin
					glob[b] = g
				var loc: Transform3D = (glob[p].affine_inverse() * g) if p >= 0 else g
				sk.set_bone_pose_position(b, loc.origin)
				sk.set_bone_pose_rotation(b, loc.basis.get_rotation_quaternion())
				sk.set_bone_pose_scale(b, loc.basis.get_scale())
			else:
				glob[b] = (glob[p] * (rl[b] as Transform3D)) if p >= 0 else (rl[b] as Transform3D)

	# W23 동작 클립 층: 상태 → 클립·시각 (ext_clips.gd select) → 뼈 회전을 코드 구동 결과와 cw 만큼 섞음.
	# 힘 빠진 몸 (래그돌 깨어 있고 모터 약함) 은 코드 (물리) 쪽으로 빨리 돌아감 — 클립이 쓰러지는 몸을 붙잡지 않게.
	func _clip_layer(st) -> void:
		var cc: Dictionary = info.cfg.get("clips", {})
		var now := Time.get_ticks_msec() * 0.001
		var dt := clampf(now - last_t, 0.0, 0.1) if last_t > 0.0 else 0.0
		last_t = now
		var sel := {"clip": ""}
		if not forced.is_empty():
			sel = forced
		elif st != null:
			air_t = air_t + dt if bool(st.get("air", false)) else 0.0
			sel = Clips_.select(cc, st, air_t)
		var want := 1.0 if (str(sel.clip) != "" and clipset.has(str(sel.clip))) else 0.0
		if want > 0.0 and forced.is_empty():
			var rg = Rag_._inst
			if rg != null and is_instance_valid(rg) and rg.rags.has(body):
				var r: Dictionary = rg.rags[body]
				if r.awake and float(r.motor) < K_.EXT_CLIP_MOTOR_MIN:
					want = 0.0
		var rate: float = (K_.EXT_CLIP_IN if want > cw else K_.EXT_CLIP_OUT)
		cw = want if not forced.is_empty() else move_toward(cw, want, dt * rate)
		if want > 0.0:
			last_sel = sel
		var use: Dictionary = sel if want > 0.0 else last_sel
		if cw <= 0.0005 or str(use.get("clip", "")) == "" or not clipset.has(str(use.get("clip", ""))):
			if clip_dirty:
				_clip_release()
			cw = 0.0
			clip_info = {"clip": "", "cw": 0.0}
			return
		var name := str(use.clip)
		if name != cur_clip:
			fade_from = last_layer.duplicate() if cw > 0.05 else {}
			fade_t = 0.0 if not fade_from.is_empty() else 1.0
			cur_clip = name
		fade_t = minf(1.0, fade_t + dt / K_.EXT_CLIP_FADE_S)
		var data: Dictionary = clipset[name]
		var an: Animation = data.anim
		var tt := float(use.get("t", 0.0))
		if use.get("norm", false):
			tt *= float(data.len)
		tt = fposmod(tt, float(data.len)) if use.get("loop", false) else clampf(tt, 0.0, float(data.len))
		var ef := fade_t * fade_t * (3.0 - 2.0 * fade_t)
		var rl: Array = info.rest_local
		for bn in data.rot:
			var bi: int = int(cbones.get(bn, -1))
			if bi < 0:
				continue
			var q: Quaternion = an.rotation_track_interpolate(int(data.rot[bn]), tt)
			if fade_t < 1.0 and fade_from.has(bn):
				q = (fade_from[bn] as Quaternion).slerp(q, ef)
			last_layer[bn] = q
			var base: Quaternion = sk.get_bone_pose_rotation(bi) if mapped.has(bi) else (rl[bi] as Transform3D).basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(bi, base.slerp(q, cw))
		clip_dirty = true
		var hb: int = int(info.map.get("hips", -1))
		var dy := 0.0
		if hb >= 0:
			var hp: Vector3 = sk.get_bone_pose_position(hb)
			var key := sk.get_bone_name(hb)
			if data.pos.has(key):
				var cp: Vector3 = an.position_track_interpolate(int(data.pos[key]), tt)
				sk.set_bone_pose_position(hb, hp.lerp(cp, cw))
			# 발 붙이기: 가장 낮은 발 뼈가 바닥 (쉬는 자세 높이) 에 닿게 골반을 올리거나 내림 (달리기는 통통 뜨는 걸 두려고 파묻힘만 막음)
			if not bool(use.get("air", false)):
				dy = _ground_dy(cc, str(use.get("kind", "")) == "loco")
				if absf(dy) > 1e-6:
					sk.set_bone_pose_position(hb, sk.get_bone_pose_position(hb) + Vector3(0, dy * cw, 0))
		clip_info = {"clip": name, "cw": cw, "dy": dy, "t": tt}

	# 뼈 높이 (뼈대 공간): 뼈 지역 자세를 부모로 곱함 (get_bone_global_pose 는 트리 밖 뼈대에선 안 갱신됨 — 테스트·초상)
	func _bone_y(bi: int) -> float:
		var t := Transform3D.IDENTITY
		var b := bi
		while b >= 0:
			t = sk.get_bone_pose(b) * t
			b = sk.get_bone_parent(b)
		return t.origin.y

	func _ground_dy(cc: Dictionary, sink_only: bool) -> float:
		var names: Array = cc.get("ground", [])
		if names.is_empty():
			return 0.0
		var rest_min := 1e9
		var cur_min := 1e9
		for bn in names:
			var bi := sk.find_bone(str(bn))
			if bi < 0:
				continue
			rest_min = minf(rest_min, (info.rest_global[bi] as Transform3D).origin.y)
			cur_min = minf(cur_min, _bone_y(bi))
		if rest_min > 1e8:
			return 0.0
		var dy := rest_min - cur_min
		if sink_only and dy < 0.0:
			return 0.0
		return clampf(dy, -0.2, 0.2)

	# 클립이 끝나면 클립이 건드린 뼈 중 코드가 안 맞추는 뼈 (척추·빗장·머리·손가락) 를 쉬는 자세로
	func _clip_release() -> void:
		clip_dirty = false
		cur_clip = ""
		last_layer.clear()
		var rl: Array = info.rest_local
		for bn in cbones:
			var bi: int = int(cbones[bn])
			if bi >= 0 and not mapped.has(bi):
				sk.set_bone_pose_rotation(bi, (rl[bi] as Transform3D).basis.get_rotation_quaternion())

	# 확인용 (tools/clip_shot.gd): 클립 하나를 그 시각 (초) 에 통째로
	func preview_clip(nm: String, t: float, in_air := false) -> void:
		forced = {"clip": nm, "t": t, "air": in_air, "kind": "act"} if nm != "" else {}
		if nm == "":
			cw = 0.0
		sync()

	# ④ 표면마다 MeshInstance3D (원래 자리·스킨 그대로), 재질은 툰
	func _surfaces() -> void:
		var cfg: Dictionary = info.cfg
		var mode: String = str(cfg.get("tint", "band"))
		var tk: float = float(cfg.get("tint_k", 0.6))
		var olds := {}
		for mi0 in model.find_children("*", "MeshInstance3D", true, false): # 고른 LOD 밖 메시도 버림
			olds[mi0] = true
		for k in cfg.get("faces", {}):
			var fp: String = str(cfg.faces[k])
			if ResourceLoader.exists(fp):
				face_tex[k] = load(fp)
		for sf in info.surfs:
			if lod != "" and str(sf.get("node", "")) != lod:
				continue
			var orig := model.get_node_or_null(sf.path) as MeshInstance3D
			if orig == null:
				continue
			olds[orig] = true
			var mesh = sf.mesh if third else sf.vm_mesh
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "%s_s%d" % [orig.name, int(sf.surf)]
			mi.mesh = mesh
			mi.transform = orig.transform
			if sf.skinned:
				mi.skin = orig.skin
			if not third or shadow_lod != "": # 1인칭 쌍둥이는 그림자 없음 · W32 판 몸은 저폴리 그림자 전용 메시가 따로 던짐
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			orig.get_parent().add_child(mi)
			if sf.skinned:
				mi.skeleton = mi.get_path_to(sk)
			var col: Color = sf.color
			if mode == "tint":
				col = col * Color.WHITE.lerp(body.skin_color, tk)
			if sf.get("unlit", false):
				var um := unlit_for(sf.color, 1.0)
				mi.material_override = um
				parts.append({"mi": mi, "color": sf.color, "tex": null, "solid": um, "unlit": true})
				body.drawn.append({"mi": mi, "m": {"kind": "toon"}, "merged": false, "ext": true})
				continue
			if sf.get("face", false): # 얼굴: 표정 텍스처, 외곽선 없음
				var ft = face_tex.get("idle", sf.tex)
				var fm := style(G3_.toon_material(col, {"map": ft, "outline": false, "color_glow": float(cfg.get("face_glow", 0.0))}), cfg, false)
				mi.material_override = fm
				face_now = "idle"
				parts.append({"mi": mi, "color": col, "tex": ft, "solid": fm, "face": true})
				body.drawn.append({"mi": mi, "m": {"kind": "toon"}, "merged": false, "ext": true})
				continue
			var vc: bool = sf.get("vcolor", false)
			var mask: bool = vc and mode == "mask"
			var m := style(toon_for(col, sf.tex, vc, mask, body.skin_color), cfg)
			mi.material_override = m
			parts.append({"mi": mi, "color": col, "tex": sf.tex, "solid": m, "vcolor": vc, "mask": mask})
			body.drawn.append({"mi": mi, "m": {"kind": "toon"}, "merged": false, "ext": true})
		if shadow_lod != "":
			ExtShadow.add(model, sk, info.surfs, shadow_lod) # W32: 원래 메시 (olds) 를 지우기 전에 — 그 자리·스킨을 베낌
		for o in olds:
			(o as Node).get_parent().remove_child(o)
			(o as Node).free()

	# 안쪽 몸 (관절 노드 나무) 은 안 그림 — keep (refs 키 목록: 탱크 방패 "shields" 등) 아래 조각만 남김 (안쪽 관절을 따라감)
	func _hide_inner() -> void:
		var keep := {}
		for key in info.cfg.get("keep", []):
			var r = body.refs.get(key)
			var tmp := {}
			body._collect_nodes(r, tmp)
			for i in tmp:
				keep[int(i)] = true
		var nodes: Array = body.nodes
		var parents: Array = body.parents
		var kept := []
		for i in nodes.size():
			var n = nodes[i]
			if not (n is MeshInstance3D):
				continue
			var k: int = i
			var on := false
			while k >= 0:
				if keep.has(k):
					on = true
					break
				k = int(parents[k])
			if on:
				kept.append(n)
			else:
				(n as MeshInstance3D).mesh = null
		var dr := []
		for e in body.drawn:
			if e.get("ext", false) or kept.has(e.mi):
				dr.append(e)
		body.drawn = dr
		if third:
			body.merged_count = 1 # 래그돌은 판 몸 (합친 몸) 만 켬 — 외부 몸도 판 몸

	# 팀 색 띠: 허리 (torso 없으면 hips) 뼈에 납작한 고리
	func _band() -> void:
		var cfg: Dictionary = info.cfg
		if str(cfg.get("tint", "band")) != "band":
			return
		var bj: String = str(cfg.get("band_joint", "waist"))
		var bi: int = int(info.map.get(bj, info.map.get("hips", -1)))
		if bi < 0:
			return
		var ba := BoneAttachment3D.new()
		ba.bone_name = sk.get_bone_name(bi)
		sk.add_child(ba)
		var bm: Array = cfg.get("band", [0.17, 0.035, 0.0]) # 반지름·두께 (모델 키 비율)·뼈 따라 올림
		var h: float = (info.box as AABB).size.y / (info.sk_rel as Transform3D).basis.get_scale().x # 뼈대 공간 (모델 뿌리 아래 크기 배율을 뺌)
		var tm := TorusMesh.new()
		tm.inner_radius = float(bm[0]) * h
		tm.outer_radius = (float(bm[0]) + float(bm[1])) * h
		tm.rings = 24
		tm.ring_segments = 8
		band = MeshInstance3D.new()
		band.mesh = tm
		band.position = Vector3(0, float(bm[2]) * h, 0)
		var m := G3_.toon_material(body.skin_color)
		band.material_override = m
		ba.add_child(band)
		ba.transform = sk.get_bone_global_pose(bi)
		parts.append({"mi": band, "color": body.skin_color, "tex": null, "solid": m, "band": true})
		body.drawn.append({"mi": band, "m": {"kind": "toon"}, "merged": false, "ext": true})

	# 따로 받은 물건 (.glb) 을 뼈에 붙임: cfg.attach = [{glb, joint, pos [x,y,z] (모델 키 비율), rot [도], scale}] (판 몸만)
	# W19 "ref": 뼈 대신 안쪽 몸 소품 노드 (refs 경로, 예 "shields.back") 아래에 붙임 — 그 노드의 보이기·자리 (등 ↔ 앞 방패, 1인칭 viewmodel 쥐기) 를 그대로 따라감.
	#   소품 .glb 는 그 노드 좌표 (게임 축, 부모 크기 FIGURE_SCALE 전) 로 만든 것 → GLTF_TO_GAME, pos [m]·rot [도, 게임 축 XYZ]·scale 은 그 노드 기준. "third"/"vm" = 판 몸·1인칭 쌍둥이에 붙일지 (기본 둘 다)
	func _attach_props() -> void:
		for a in info.cfg.get("attach", []):
			if str(a.get("ref", "")) != "":
				_attach_ref(a)
				continue
			if not third and not bool(a.get("vm", false)): # 1인칭 쌍둥이에는 "vm": true 인 것만 (W20 해머)
				continue
			if third and not bool(a.get("third", true)): # "third": false = 판 몸에는 안 붙임 (1인칭만)
				continue
			var bi: int = int(info.map.get(str(a.get("joint", "hand_R")), -1))
			var gp: String = str(a.get("glb", ""))
			if bi < 0 or gp == "" or not ResourceLoader.exists(gp):
				push_warning("외부 .glb attach %s 안 됨" % [a])
				continue
			var ba := BoneAttachment3D.new()
			ba.bone_name = sk.get_bone_name(bi)
			sk.add_child(ba)
			var prop := (load(gp) as PackedScene).instantiate() as Node3D
			var h: float = (info.box as AABB).size.y / (info.sk_rel as Transform3D).basis.get_scale().x # 뼈대 공간 (모델 뿌리 아래 크기 배율을 뺌)
			var p: Array = a.get("pos", [0, 0, 0])
			var r: Array = a.get("rot", [0, 0, 0])
			prop.position = Vector3(float(p[0]), float(p[1]), float(p[2])) * h
			prop.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
			prop.scale = Vector3.ONE * float(a.get("scale", 1.0)) * h
			ba.add_child(prop)
			for mi in prop.find_children("*", "MeshInstance3D", true, false):
				var m := G3_.toon_material(Color.WHITE)
				var sm = (mi as MeshInstance3D).mesh.surface_get_material(0) if (mi as MeshInstance3D).mesh != null else null
				if sm is BaseMaterial3D:
					m = G3_.toon_material((sm as BaseMaterial3D).albedo_color, {"map": (sm as BaseMaterial3D).albedo_texture} if (sm as BaseMaterial3D).albedo_texture != null else {})
				(mi as MeshInstance3D).material_override = m
				if not third:
					(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parts.append({"mi": mi, "color": m.get_shader_parameter("albedo"), "tex": null, "solid": m})
				body.drawn.append({"mi": mi, "m": {"kind": "toon"}, "merged": false, "ext": true})

	func _attach_ref(a: Dictionary) -> void:
		if not bool(a.get("third" if third else "vm", true)):
			return
		var path: PackedStringArray = str(a.ref).split(".")
		var r = body.refs.get(path[0])
		for i in range(1, path.size()):
			r = r.get(path[i]) if r is Dictionary else null
		var host: Node3D = body._n(r) if r != null else null
		var gp: String = str(a.get("glb", ""))
		if host == null or gp == "" or not ResourceLoader.exists(gp):
			push_warning("외부 .glb attach %s 안 됨" % [a])
			return
		var prop := (load(gp) as PackedScene).instantiate() as Node3D
		var p: Array = a.get("pos", [0, 0, 0])
		var rr: Array = a.get("rot", [0, 0, 0])
		var rot := Basis.from_euler(Vector3(deg_to_rad(float(rr[0])), deg_to_rad(float(rr[1])), deg_to_rad(float(rr[2]))), EULER_ORDER_XYZ)
		prop.transform = Transform3D((rot * GLTF_TO_GAME_).scaled(Vector3.ONE * float(a.get("scale", 1.0))), Vector3(float(p[0]), float(p[1]), float(p[2])))
		prop.name = "ext_" + str(a.ref).replace(".", "_")
		host.add_child(prop)
		var mode: String = str(info.cfg.get("tint", "band"))
		for mi in prop.find_children("*", "MeshInstance3D", true, false):
			var me := (mi as MeshInstance3D).mesh
			if me == null:
				continue
			var sm = (mi as MeshInstance3D).get_surface_override_material(0)
			if sm == null:
				sm = me.surface_get_material(0)
			var col: Color = (sm as BaseMaterial3D).albedo_color if sm is BaseMaterial3D else Color.WHITE
			var tex = (sm as BaseMaterial3D).albedo_texture if sm is BaseMaterial3D else null
			var vc := vertex_colored(me, 0, sm, mode)
			var m := style(toon_for(col, tex, vc, vc and mode == "mask", body.skin_color), info.cfg)
			(mi as MeshInstance3D).material_override = m
			if not third:
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parts.append({"mi": mi, "color": col, "tex": tex, "solid": m, "vcolor": vc, "mask": vc and mode == "mask"})
			body.drawn.append({"mi": mi, "m": {"kind": "toon"}, "merged": false, "ext": true})

	# 몸 색 효과 (body.fx_colors: [피부 색, 피부 발광, 나머지 발광]) + 반투명 (body.opacity). 부위 구분이 없으니 피부 발광을 몸 전체에,
	# 경직 하얀 깜빡임 (피부 색이 하양) 은 하얀 발광으로
	# tint "mask" 표면은 구운 몸처럼 몸 색 칸만 피부 색·피부 발광 (skin_tint·skin_emissive), 나머지는 나머지 발광 — 하얀 깜빡임도 몸 색 칸이 하얘짐
	func fx(f: Array, op: float) -> void:
		var skin: Color = f[0]
		var e: Color = f[1]
		if skin == Color.WHITE and body.skin_color != Color.WHITE:
			e = Color(maxf(e.r, K_.EXT_FLASH), maxf(e.g, K_.EXT_FLASH), maxf(e.b, K_.EXT_FLASH))
		for pt in parts:
			if pt.get("mask", false):
				_fx_mask(pt, f, op)
				continue
			if pt.get("unlit", false): # 눈 흰자: 번쩍 없이 반투명만 (JS 눈도 그대로 하양)
				if op >= 1.0:
					if pt.mi.material_override != pt.solid:
						pt.mi.material_override = pt.solid
				else:
					if not pt.has("alpha"):
						pt.alpha = unlit_for(pt.color, 0.5)
					(pt.alpha as ShaderMaterial).set_shader_parameter("albedo", Color(0, 0, 0, op))
					pt.mi.material_override = pt.alpha
				continue
			var mi: MeshInstance3D = pt.mi
			if op >= 1.0:
				if mi.material_override != pt.solid:
					mi.material_override = pt.solid
			else:
				if not pt.has("alpha"):
					var opts := {"opacity": 0.5, "outline": false}
					if pt.tex != null:
						opts.map = pt.tex
					pt.alpha = style(G3_.toon_material(pt.color, opts), info.cfg, false)
					G3_.toon_hazard_light(pt.alpha, body.hz_light)
				var c: Color = pt.color
				(pt.alpha as ShaderMaterial).set_shader_parameter("albedo", Color(c.r, c.g, c.b, op))
				mi.material_override = pt.alpha
			var sm := mi.material_override as ShaderMaterial
			if sm != null:
				sm.set_shader_parameter("emissive", Color(0, 0, 0) if pt.get("band", false) and e == f[1] and e == Color(0, 0, 0) else e)
		opacity = op

	func _fx_mask(pt: Dictionary, f: Array, op: float) -> void:
		var mi: MeshInstance3D = pt.mi
		var want: Material = pt.solid
		if op < 1.0:
			if not pt.has("alpha"):
				pt.alpha = style(toon_for(pt.color, pt.tex, true, true, body.skin_color, {"opacity": 0.5, "outline": false}), info.cfg, false)
				G3_.toon_hazard_light(pt.alpha, body.hz_light)
			want = pt.alpha
		if mi.material_override != want:
			mi.material_override = want
		var key := [f, op]
		if pt.get("fx_m") == want and pt.get("fx_v") == key: # 같은 값이면 안 올림 (W15)
			return
		pt.fx_m = want
		pt.fx_v = key
		var sm := want as ShaderMaterial
		var skin: Color = f[0]
		sm.set_shader_parameter("skin_tint", Color(skin.r, skin.g, skin.b, 1.0))
		sm.set_shader_parameter("skin_emissive", f[1])
		sm.set_shader_parameter("emissive", f[2])
		if op < 1.0:
			var c: Color = pt.color
			sm.set_shader_parameter("albedo", Color(c.r, c.g, c.b, op))

	# ⑥ 모델에 든 클립 하나 재생 (이름 = AnimationPlayer 목록, 예: 로봇 "Wave"). 재생 동안 뼈 맞추기 쉼, stop_clip 으로 돌아옴
	func play_clip(nm: String) -> bool:
		if anim == null or not anim.has_animation(nm):
			return false
		clip = nm
		anim.active = true
		anim.play(nm)
		return true

	func stop_clip() -> void:
		if anim != null:
			anim.stop()
			anim.active = false
		clip = ""
		if sk != null:
			sk.reset_bone_poses()
		sync()
