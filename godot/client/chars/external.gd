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
const GhostDepth := preload("res://chars/ghost_depth.gd")
const ExtShadow := preload("res://chars/ext_shadow.gd")
const Clips := preload("res://chars/ext_clips.gd")
const Hitch := preload("res://core/hitch.gd")
const Motion_ := preload("res://chars/ext_motion.gd")

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
static var _scenes := {} # W41: 스레드 읽기가 끝난 장면을 미리 받아 둔 것 (경로 → PackedScene) — 받기 (메인 스레드 ~10ms) 와 정보 셈을 다른 프레임에
static var _warm_i := 0
static var _warm_wait := 0
static var _warm_body = null
static var lazy_tex: bool = not preload("res://core/opts.gd").args().has("--no-lazy-tex") # W39: 알베도 텍스처를 몸 만들 때만 읽음 — 안 쓰는 LOD·stage 알베도가 영상 메모리에 상주하지 않게 (끄기 --no-lazy-tex)
static var _tex_paths := {} # "장면 경로|메시 노드|표면" → 알베도 텍스처 경로 (장면에서 벗겨 낸 것)
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
		var s = _scenes.get(gp)
		if s == null:
			s = ResourceLoader.load_threaded_get(gp) if _req.has(gp) else load(gp)
		_scenes.erase(gp)
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
		if ResourceLoader.load_threaded_request(gp, "PackedScene", not lazy_tex) == OK:
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


# ---- W41 미리 읽기·데우기를 조각으로 (world/prewarm_sched.gd 가 프레임 예산 안에서 한 조각씩 부름) ----
const TexPre := preload("res://chars/tex_prefetch.gd")


# 이 캐릭터 .glb·클립 하나만 스레드로 요청 (request_all 은 8명 한꺼번에 — 읽기가 끝나는 순간 업로드가 한 프레임에 몰림). 요청했거나 이미 있으면 false
static func request_one(id: String) -> bool:
	var gp := glb_path(id)
	if _cache.has(id) or _req.has(gp) or not ResourceLoader.exists(gp):
		return false
	var ok := ResourceLoader.load_threaded_request(gp, "PackedScene", not lazy_tex) == OK
	if ok:
		_req[gp] = true
	var cc = read_cfg(id).get("clips", {})
	var cp: String = str((cc as Dictionary).get("file", "")) if cc is Dictionary else ""
	if cp != "" and ResourceLoader.exists(cp) and not Clips.requested.has(cp) and ResourceLoader.load_threaded_request(cp, "PackedScene", true) == OK:
		Clips.requested[cp] = true
	return ok


# 끝난 스레드 읽기 결과를 받아 둠 (load_char 가 쓸 것). 받았으면 true
static func take_scene(id: String) -> bool:
	var gp := glb_path(id)
	if _cache.has(id) or not _req.has(gp) or _scenes.has(gp):
		return false
	var s = ResourceLoader.load_threaded_get(gp)
	if s != null:
		_scenes[gp] = s
		_req.erase(gp)
		return true
	return false


# .glb 읽기가 끝났나 (요청 안 했거나 이미 정보가 있으면 참)
static func file_ready(id: String) -> bool:
	var gp := glb_path(id)
	if _cache.has(id) or not _req.has(gp):
		return true
	return ResourceLoader.load_threaded_get_status(gp) != ResourceLoader.THREAD_LOAD_IN_PROGRESS


# 그 캐릭터 몸이 쓸 알베도·마스크를 스레드로 요청: on_stage = 대기실 큰 캐릭터·초상 (최고 LOD), game = 판 몸 (화질 LOD). 정보 (load_char) 가 이미 있어야 함. 요청한 수
static func prefetch_tex(id: String, on_stage: bool, game: bool) -> int:
	if not lazy_tex or not _cache.has(id) or _cache[id] == null:
		return 0
	var info: Dictionary = _cache[id]
	var nodes := {}
	if on_stage:
		nodes[pick_lod(info.cfg, true, true)] = true
	if game:
		nodes[pick_lod(info.cfg, true, false)] = true
	var n := 0
	for sf in info.surfs:
		if nodes.has(str(sf.get("node", ""))) and TexPre.request(str(sf.get("tex_path", ""))):
			n += 1
	for node in nodes:
		var mp := str(info.cfg.get("skin_mask", {}).get(node, ""))
		if mp != "" and TexPre.request(mp):
			n += 1
	return n


# 몸 데우기 한 캐릭터를 조각으로: 요청 → (읽기 끝날 때까지 기다림, 일 없음) → 정보 → 텍스처 요청 → 몸 만들기+작게 그리기 → 두 프레임 뒤 치움.
# step 이 true 를 돌려주면 끝. 조각마다 프레임 예산 스케줄러가 부름 (한 조각 = 메인 스레드 일 한 덩이)
class WarmJob:
	extends RefCounted
	var id := ""
	var stage := 0
	var body: Node3D = null
	var wait := 2
	var want_game := true # 판 몸 LOD 텍스처 미리 읽기
	var want_stage := false # 대기실 큰 캐릭터·초상 (최고 LOD) 텍스처 미리 읽기
	var cpu_done := false
	var make := true # 몸까지 만들어 작게 그려 봄 (아니면 미리 읽기만)

	func _init(id_: String, game_ := true, stage_ := false, make_ := true) -> void:
		id = id_
		want_game = game_
		want_stage = stage_
		make = make_

	# 읽기가 다 끝났나 (몸을 만들 때 텍스처를 기다리지 않을 만큼)
	func tex_ready() -> bool:
		var Ext_ = load("res://chars/external.gd")
		var info = Ext_._cache.get(id)
		if info == null:
			return true
		var T = preload("res://chars/tex_prefetch.gd")
		for sf in info.surfs:
			var tp := str(sf.get("tex_path", ""))
			if tp != "" and not T.ready(tp):
				return false
		return true

	# 돌려주는 값: true = 끝, false = 다음 프레임에 이어서, PSched.WAIT (-1) = 기다리는 중 (할 일 없음)
	func step(host: Node3D, make_body: Callable):
		var Ext_ = load("res://chars/external.gd")
		match stage:
			0:
				if not preload("res://chars/body.gd").use_ext or not ResourceLoader.exists(Ext_.glb_path(id)):
					return true
				Ext_.request_one(id)
				stage = 1
			1:
				if not Ext_.file_ready(id):
					return -1 # WAIT
				stage = 2
			2:
				var _t2 := Hitch.t()
				Ext_.take_scene(id) # 받기만 (장면 정보 셈은 다음 조각)
				Hitch.span("몸 불러오기", id + " 받기", _t2)
				stage = 3
			3:
				Ext_.load_char(id) # 정보 셈 (몸마다 같이 씀)
				Ext_.prefetch_tex(id, want_stage, want_game)
				stage = 4 if make or want_stage else 9
			4:
				if not tex_ready():
					return -1
				if not make:
					return true
				if host == null or not host.is_visible_in_tree():
					# 타이틀·메뉴 동안 world 는 숨겨져 (title.gd) 그려도 셰이더가 안 만들어짐 → 여기선 만들기 (CPU 첫 사용 값) 만 한 번 치르고 버림,
					# 그리기는 world 가 보이는 대기실에서 (두 번째 만들기는 싸다)
					if not cpu_done:
						cpu_done = true
						var b0: Node3D = make_body.call(id, Color(0.8, 0.3, 0.3))
						b0.free()
						return false
					return -1
				var _ht := Hitch.t()
				body = make_body.call(id, Color(0.8, 0.3, 0.3))
				var cam := host.get_viewport().get_camera_3d() if host.is_inside_tree() else null
				body.scale = Vector3.ONE * 0.001
				host.add_child(body)
				if cam:
					body.global_position = cam.global_position + (-cam.global_transform.basis.z) * 2.0
				Hitch.span("미리 그리기", "몸 " + id, _ht)
				stage = 5
			5:
				wait -= 1
				if wait <= 0:
					body.queue_free()
					body = null
					return true
			_:
				return true
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
	var mat_tex := {} # 재질 → 벗긴 알베도 경로 (이 장면 안)
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
			var tex_key := "%s|%s|%d" % [scene.resource_path, str(m.name), si]
			if mat is BaseMaterial3D:
				col = (mat as BaseMaterial3D).albedo_color
				tex = (mat as BaseMaterial3D).albedo_texture
				if lazy_tex:
					# W39: 장면 (PackedScene) 이 알베도 텍스처를 붙잡고 있지 않게 벗김 — 몸이 만들어질 때 그 LOD 것만 읽음. 재질을 여러 LOD 가 나눠 쓰면 (사냥꾼) 처음 본 경로를 같이 씀,
					# 이미 벗긴 장면을 다시 읽으면 (테스트) 처음에 적어 둔 경로
					var tp := str(tex.resource_path) if tex != null else str(mat_tex.get(mat.get_instance_id(), _tex_paths.get(tex_key, "")))
					if tp.begins_with("res://") and not tp.contains("::"):
						_tex_paths[tex_key] = tp
						mat_tex[mat.get_instance_id()] = tp
						(mat as BaseMaterial3D).albedo_texture = null
						tex = null
			var tex_path: String = str(_tex_paths.get(tex_key, "")) if lazy_tex else ""
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
			surfs.append({"path": root.get_path_to(m), "surf": si, "mesh": one, "color": col, "tex": tex, "tex_path": tex_path, "skinned": skinned, "bone": bone, "binds": binds,
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
	const Prof_ := preload("res://core/prof.gd")
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
		var mt = opts.get("skin_mask")
		opts.erase("skin_mask")
		var m := G3_.toon_material(col, opts)
		if vcolor and mask:
			m.set_shader_parameter("skin_tint", Color(skin.r, skin.g, skin.b, 1.0))
			if mt != null: # W34 몸 색 칸 마스크 텍스처 (꼭짓점 UV2 대신)
				m.set_shader_parameter("skin_mask_tex", mt)
				m.set_shader_parameter("use_skin_mask", true)
		return m

	# W39 몸 만들 때 읽는 알베도 텍스처: 경로가 있으면 그때 load (같은 캐릭터 몸끼리는 리소스 캐시가 같은 객체를 줘서 공유, 쓰는 몸이 없으면 풀려남), 없으면 장면에 붙어 있던 그대로
	static func tex_of(sf: Dictionary):
		var p: String = str(sf.get("tex_path", ""))
		if p != "":
			return preload("res://chars/tex_prefetch.gd").get_tex(p) # W41: 미리 요청한 게 있으면 그걸
		return sf.get("tex")

	# W34 cfg.skin_mask[메시 노드 이름] 의 마스크 텍스처 (없으면 null = 꼭짓점 판정)
	static func skin_mask_for(cfg: Dictionary, node: String):
		var p: String = str(cfg.get("skin_mask", {}).get(node, ""))
		return preload("res://chars/tex_prefetch.gd").get_tex(p) if p != "" and ResourceLoader.exists(p) else null

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
	var rel_par := PackedInt32Array() # W39: maps 번호 → 관절 노드의 부모가 되는 매핑 관절의 maps 번호 (없으면 -1)
	var rels: Array[Transform3D] = [] # W39: 이번 프레임 관절 → space 자세 (maps 번호별)
	var rel_ok := PackedByteArray()
	var need_order := PackedInt32Array() # W39: 뼈 쓰기가 도는 뼈 (매핑된 뼈 + 조상, 부모 먼저)
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
	var gaze_y := 0.0 # W40 시선 (몸 기준 yaw, 라디안, 부드럽게)
	var gaze_w := 0.0
	var breath_w := 0.0
	var extra_t := 0.0
	# W43 방향 이동·기울임·방향 전환
	var move_off := OS.get_cmdline_args().has("--no-w43") # 실행 인자 --no-w43 으로도 끔 (전후 비용 비교). 확인 도구: W43 이동 가산 (방향·기울임·전환) 끄기 — 전후 비교·비용 재기
	var dir_rev := false # 뒤로 걸음 (클립 거꾸로)
	var dir_y := 0.0 # 골반 yaw (몸 기준, 라디안, 부드럽게)
	var lean_p := 0.0
	var turn_tw := 0.0
	var turn_prev := 0.0
	var turn_have := false
	var fade_len := 0.1
	var cur_kind := ""
	var extra_off := false # 확인 도구 (tools/ext_cost.gd) 가 가산 층 비용을 떼어 잴 때
	var arm_ids := {}
	var arm_delta := {} # W40: 클립이 코드 자세에서 벗어난 팔 뼈 (뼈 번호 → Quaternion: base⁻¹ · 클립 결과), 공격·스킬 클립 중에만 — 1인칭 쌍둥이가 읽어 감
	var src_ext = null # W40 1인칭 쌍둥이만: 베끼는 3인칭 몸의 Ext
	var clip_arm_k := 0.0

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
			if not Motion_.bodies.has(body):
				Motion_.bodies.append(body) # W40 시선: 다른 몸 찾기 (정적 목록 — 나무 밖 테스트에서도 됨)
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

	# W33: 판 몸 (third) 은 body.pose 가 sync(st) 로 클립까지 맞춤 — 그 뒤 같은 프레임에 이 _process 가 st 없는 sync() 를 또 부르면
	# 코드 구동 (_code_sync) 이 클립이 맞춘 팔다리 뼈를 도로 덮어씀 (고도는 _ready 때 _process 를 다시 켜서 setup 의 set_process(false) 가 안 먹음)
	var st_frame := -1

	func _process(_d: float) -> void:
		if third and st_frame == Engine.get_process_frames():
			return
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
		# W39 자세 CPU: ① 관절 위 부모가 다른 매핑 관절이면 그 전역 자세를 이어 곱함 (뿌리까지 매번 거슬러 올라가지 않게) ② 뼈 쓰기는 매핑된 뼈와 그 조상만 (손가락 같은 끝 뼈는 쉬는 자세 그대로 부모를 따라감)
		rel_par.resize(maps.size())
		rel_par.fill(-1)
		for i in maps.size():
			var pn: Node = (maps[i].joint as Node).get_parent()
			for j in i:
				if maps[j].joint == pn:
					rel_par[i] = j
					break
		rels.resize(maps.size())
		rel_ok.resize(maps.size())
		var need := {}
		var parents_: PackedInt32Array = info.parents
		for bi2 in mapped:
			var b2: int = int(bi2)
			while b2 >= 0 and not need.has(b2):
				need[b2] = true
				b2 = parents_[b2]
		need_order = PackedInt32Array()
		for b3 in info.order:
			if need.has(int(b3)):
				need_order.append(int(b3))

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
		if st != null:
			st_frame = Engine.get_process_frames()
		var t0 := Prof_.now()
		_face_sync()
		if clip != "" or sk == null:
			return
		t0 = _lap("몸 외부 몸 ·표정", t0)
		_code_sync()
		t0 = _lap("몸 외부 몸 ·뼈 맞추기", t0)
		if not third:
			_vm_bone_scale()
			_vm_clip_arms()
		if st != null and float(st.get("airDash", 0.0)) > 0.0 and not bool(st.get("stunned", false)):
			_dash_wrist()
		if third and not clipset.is_empty() and (st != null or not forced.is_empty()):
			_clip_layer(st)
		t0 = _lap("몸 외부 몸 ·클립 층", t0)
		if third and st != null:
			_reset_extra()
			_hit_flinch(st)
			_extra_layer(st)
		if not cloths.is_empty():
			var now := Time.get_ticks_msec() * 0.001
			var cdt := clampf(now - cloth_t, 0.0, 0.1) if cloth_t > 0.0 else 0.0
			cloth_t = now
			for cl in cloths:
				cl.step(cdt)
		_lap("몸 외부 몸 ·움찔·천", t0)

	static func _lap(name: String, t0: int) -> int:
		if t0 == 0:
			return 0
		Prof_.add(name, t0)
		return Prof_.now()

	func _code_sync() -> void:
		_code_maps()
		_code_bones()

	# ① 관절 → 매핑된 뼈의 뼈대 공간 전역 자세 (glob)
	func _code_maps() -> void:
		for i in maps.size():
			var m: Dictionary = maps[i]
			var pi: int = rel_par[i]
			var jr = (rels[pi] * (m.joint as Node3D).transform) if pi >= 0 and rel_ok[pi] != 0 else _rel(m.joint)
			if jr == null:
				rel_ok[i] = 0
				continue
			rels[i] = jr
			rel_ok[i] = 1
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

	# ② 부모 먼저 순서로 뼈 지역 자세를 skeleton 에 씀 (안 맞춘 뼈는 쉬는 자세 그대로 부모를 따라감)
	func _code_bones() -> void:
		var parents: PackedInt32Array = info.parents
		var rl: Array = info.rest_local
		for b in need_order:
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
			_dir_update(st)
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
			arm_delta.clear()
			if clip_dirty:
				_clip_release()
			cw = 0.0
			clip_info = {"clip": "", "cw": 0.0}
			return
		var name := str(use.clip)
		var ckey := name + ("~r" if bool(use.get("rev", false)) else "") # W43 같은 클립 거꾸로 재생도 따로 크로스페이드
		if ckey != cur_clip:
			fade_from = last_layer.duplicate() if cw > 0.05 else {}
			fade_t = 0.0 if not fade_from.is_empty() else 1.0
			fade_len = K_.EXT_DIR_FADE_S if (cur_clip.trim_suffix("~r") == name) else Clips_.fade_s(cur_kind, str(use.get("kind", "")))
			cur_clip = ckey
			cur_kind = str(use.get("kind", ""))
		fade_t = minf(1.0, fade_t + dt / fade_len)
		var data: Dictionary = clipset[name]
		var an: Animation = data.anim
		var tt := float(use.get("t", 0.0))
		if use.get("norm", false):
			tt *= float(data.len)
		tt = fposmod(tt, float(data.len)) if use.get("loop", false) else clampf(tt, 0.0, float(data.len))
		var ef := fade_t * fade_t * (3.0 - 2.0 * fade_t)
		var rl: Array = info.rest_local
		var is_act: bool = str(use.get("kind", "")) == "act" and want > 0.0
		arm_delta.clear()
		if arm_ids.is_empty():
			for jn in K_.VM_CLIP_ARM_BONES:
				var ab: int = int(info.map.get(jn, -1))
				if ab >= 0:
					arm_ids[ab] = true
		# W43 달릴 때 팔 흔들림 폭: 걷기·달리기 클립의 위팔 회전을 한 바퀴 평균 둘레로 (속도 / 클립 속도) 배
		var swing_k := 1.0
		var swing_bones := {}
		if str(use.get("kind", "")) == "loco" and st != null and not move_off:
			swing_k = Motion_.arm_swing_scale(float(st.get("hs", 0.0)), name == str(cc.get("run", "")))
			for jn in ["shoulder_L", "shoulder_R"]:
				var sbi: int = int(info.map.get(jn, -1))
				if sbi >= 0:
					swing_bones[sbi] = true
		for bn in data.rot:
			var bi: int = int(cbones.get(bn, -1))
			if bi < 0:
				continue
			var q: Quaternion = an.rotation_track_interpolate(int(data.rot[bn]), tt)
			if swing_bones.has(bi) and absf(swing_k - 1.0) > 0.01:
				var mq := _swing_mean(name, bn, an, int(data.rot[bn]))
				var dq: Quaternion = (mq.inverse() * q).normalized()
				var ang := dq.get_angle()
				if ang > PI:
					ang -= TAU
				if absf(ang) > 1e-5:
					q = mq * Quaternion(dq.get_axis().normalized(), ang * swing_k)
			if fade_t < 1.0 and fade_from.has(bn):
				q = (fade_from[bn] as Quaternion).slerp(q, ef)
			last_layer[bn] = q
			var base: Quaternion = sk.get_bone_pose_rotation(bi) if mapped.has(bi) else (rl[bi] as Transform3D).basis.get_rotation_quaternion()
			var fin: Quaternion = base.slerp(q, cw)
			sk.set_bone_pose_rotation(bi, fin)
			if is_act and arm_ids.has(bi):
				arm_delta[bi] = base.inverse() * fin
		clip_dirty = true
		var hb: int = int(info.map.get("hips", -1))
		var dy := 0.0
		if hb >= 0:
			var hp: Vector3 = sk.get_bone_pose_position(hb)
			var key := sk.get_bone_name(hb)
			if data.pos.has(key):
				var cp: Vector3 = an.position_track_interpolate(int(data.pos[key]), tt)
				sk.set_bone_pose_position(hb, hp.lerp(cp, cw))
			# W34 보폭 늘리기 (발 미끄러짐): 걷기·달리기 클립의 발 앞뒤 움직임을 (골반 기준 한 바퀴 평균 자리 c 둘레로) k 배로 늘려 2본 IK 로 다리를 다시 폄 (cfg.clips.stride {클립: [k, c, 박자 배율]})
			var sd = (cc.get("stride", {}) as Dictionary).get(name)
			if sd is Array and float(sd[0]) > 1.0 and not bool(use.get("air", false)):
				_stride_ik(1.0 + (float(sd[0]) - 1.0) * cw, float(sd[1]))
			# 발 붙이기: 가장 낮은 발 뼈가 바닥 (쉬는 자세 높이) 에 닿게 골반을 올리거나 내림 (달리기는 통통 뜨는 걸 두려고 파묻힘만 막음)
			if not bool(use.get("air", false)):
				dy = _ground_dy(cc, str(use.get("kind", "")) == "loco")
				if absf(dy) > 1e-6:
					sk.set_bone_pose_position(hb, sk.get_bone_pose_position(hb) + Vector3(0, dy * cw, 0))
		clip_info = {"clip": name, "cw": cw, "dy": dy, "t": tt}

	# W43 일어나기: 경직이 풀려 땅에 닿아 웅크림 (st.recover) 이 시작되면, 또는 몸이 숨었다 다시 보이면 (부활·판 시작) 타이머를 돌려 손 짚고 일어나는 자세를 가산.
	# 래그돌이 깨어 있으면 모터가 돌아오는 만큼 (getup_motor_w) 섞음 — 아직 축 늘어졌으면 물리에 맡김.
	var getup_t := -1.0
	var getup_amp := 1.0
	var getup_peak := 0.0
	var getup_mark := 0.0 # 확인 도구: 0 이상이면 이 진행 비율 (u) 로 고정
	var getup_w_last := 0.0

	func _getup_layer(st, dt: float, rag_motor: float) -> void:
		if move_off:
			return
		var now := Time.get_ticks_msec() * 0.001
		if getup_t < 0.0 and extra_gap > K_.EXT_GETUP_SPAWN_GAP_S and not Motion_.getup_blocked(st):
			getup_t = 0.0 # 부활·판 시작: 숨었다 나타남
			getup_amp = K_.EXT_GETUP_SPAWN_AMP
			getup_peak = 0.0
		var rec := float(st.get("recover", 0.0))
		if getup_t < 0.0 and rec > 0.05 and not Motion_.getup_blocked(st):
			getup_t = 0.0
			getup_peak = rec
			getup_amp = clampf(rec, 0.5, 1.0) # 가볍게 맞고 선 것 (recover_pow 0.5) 은 약하게, 구르다 선 것 (1) 은 크게
		if getup_t >= 0.0 and Motion_.getup_blocked(st):
			getup_t = -1.0
		if getup_t >= 0.0:
			getup_t += dt
			if getup_t > K_.EXT_GETUP_S:
				getup_t = -1.0
		var u := getup_mark if getup_mark > 0.0 else (getup_t / K_.EXT_GETUP_S if getup_t >= 0.0 else -1.0)
		getup_w_last = 0.0
		if u < 0.0:
			return
		var cv: Dictionary = Motion_.getup_curves(u)
		var w: float = float(cv.env) * Motion_.getup_motor_w(rag_motor) * getup_amp
		getup_w_last = w
		if w < 0.005:
			return
		var al: float = K_.EXT_GETUP_LEG * w * float(cv.step)
		var fy0 := _feet_y()
		var legs := [["R", 1.0], ["L", -0.5]] # 오른발 앞, 왼발 뒤로 (무릎 꿇는 쪽)
		for lg in legs:
			var th_i: int = int(info.map.get("thigh_" + str(lg[0]), -1))
			var kn_i: int = int(info.map.get("knee_" + str(lg[0]), -1))
			if th_i < 0 or kn_i < 0:
				continue
			var f: float = float(lg[1])
			_add_rot(th_i, Quaternion(Vector3.BACK, al * f))
			_add_rot(kn_i, Quaternion(Vector3.BACK, -al * (0.9 if f > 0.0 else 1.4)))
		var aa: float = K_.EXT_GETUP_ARM * w * float(cv.arm)
		for jn in ["shoulder_R", "shoulder_L"]:
			var sbi: int = int(info.map.get(jn, -1))
			if sbi >= 0:
				_add_rot(sbi, Quaternion(Vector3.BACK, aa))
		var tp: float = K_.EXT_GETUP_TORSO * w * float(cv.torso)
		for e in [["mixamorig_Spine1", 0.5], ["mixamorig_Spine2", 0.5], ["mixamorig_Head", -0.5]]:
			var bi := sk.find_bone(str(e[0]))
			if bi >= 0:
				_add_rot(bi, Quaternion(Vector3.BACK, -tp * float(e[1])))
		# 다리를 접으면 발이 올라가니 올라간 만큼 엉덩이를 내려 발은 땅에 (착지와 같은 방법)
		var hb: int = int(info.map.get("hips", -1))
		if hb >= 0 and fy0 < 1e8:
			var dy := _feet_y() - fy0
			sk.set_bone_pose_position(hb, sk.get_bone_pose_position(hb) - Vector3(0, dy, 0))

	# W43 무기 무게·흔들림 (config EXT_WEAPON): 손뼈 월드 가속도 → 용수철. 상태 = 항목마다 {p (이전 위치 월드), v, th [pitch, roll], om [pitch, roll]}
	var weapon_st: Array = []
	var weapon_w := 0.0
	var weapon_pitch_last := 0.0 # 확인용: 첫 항목의 지금 pitch (라디안)

	func _weapon_layer(st, dt: float) -> void:
		if move_off:
			return
		var table: Array = K_.EXT_WEAPON.get(str(body.get("char_id")), [])
		if table.is_empty():
			return
		weapon_w = move_toward(weapon_w, 1.0 if Motion_.weapon_allowed(st) else 0.0, dt * K_.EXT_WEAPON_W_RATE)
		var W: Transform3D = Rag_.glob(sk)
		var sp := clampf(float(st.get("hs", 0.0)) / float(C_.MOVE_SPEED), 0.0, 1.2) if bool(st.get("walking", false)) else 0.0
		if weapon_st.size() != table.size():
			weapon_st.clear()
			for e in table:
				weapon_st.append({"p": Vector3.INF, "v": Vector3.ZERO, "th": [0.0, 0.0], "om": [0.0, 0.0]})
		for i in table.size():
			var e: Dictionary = table[i]
			var s: Dictionary = weapon_st[i]
			var jb: int = int(info.map.get(str(e.joint), -1))
			var sb: int = int(info.map.get(str(e.get("src", e.joint)), -1))
			if jb < 0 or sb < 0:
				continue
			var pw: Vector3 = W * _gt(sb).origin # 월드
			var acc_b := Vector3.ZERO
			if (s.p as Vector3) != Vector3.INF:
				var vn: Vector3 = (pw - (s.p as Vector3)) / dt
				var an: Vector3 = (vn - (s.v as Vector3)) / dt
				s.v = vn
				# 월드 가속도 → 뼈대 공간 (앞 +x, 위 +y, 오른쪽 +z)
				acc_b = W.basis.orthonormalized().inverse() * an
				acc_b /= maxf(0.01, W.basis.get_scale().x)
			s.p = pw
			var ax := Motion_.clamp_acc(acc_b.x)
			var ay := Motion_.clamp_acc(acc_b.y)
			var az := Motion_.clamp_acc(acc_b.z)
			var k: float = float(e.k)
			var c: float = float(e.c)
			var rp := Motion_.spring_step(float(s.th[0]), float(s.om[0]), float(e.gp) * k * ax + float(e.gy) * k * ay, dt, k, c)
			var rr := Motion_.spring_step(float(s.th[1]), float(s.om[1]), -float(e.gr) * k * az, dt, k, c)
			var lim: float = float(e.get("max", 0.3))
			s.th = [clampf(float(rp[0]), -lim, lim), clampf(float(rr[0]), -lim, lim)]
			s.om = [rp[1], rr[1]]
			if i == 0:
				weapon_pitch_last = float(s.th[0])
			var w := weapon_w
			if w < 0.01:
				continue
			var pitch: float = (float(s.th[0]) + float(e.get("droop", 0.0)) * sp) * w
			var roll: float = float(s.th[1]) * w
			if absf(pitch) > 0.001 or absf(roll) > 0.001:
				var q := Quaternion(Vector3.BACK, pitch) * Quaternion(Vector3.RIGHT, roll)
				_add_rot(jb, q)

	var extra_gap := 0.0 # 직전 가산 층 이후 지난 시간 (몸이 숨었다 나타났는지 알아냄)

	func _feet_y() -> float:
		var fy := 0.0
		var nf := 0
		for side in ["R", "L"]:
			var fi: int = int(info.map.get("foot_" + side, -1))
			if fi >= 0:
				fy += _gt(fi).origin.y
				nf += 1
		return fy / nf if nf > 0 else 1e9

	# 클립 한 바퀴의 평균 회전 (부호 맞춰 더해 정규화), 클립·뼈마다 한 번만
	var swing_means := {}

	func _swing_mean(clip_name: String, bn: String, an: Animation, track: int) -> Quaternion:
		var key := clip_name + "/" + bn
		if swing_means.has(key):
			return swing_means[key]
		var ref: Quaternion = an.rotation_track_interpolate(track, 0.0)
		var acc := Vector4.ZERO
		for i in 8:
			var q: Quaternion = an.rotation_track_interpolate(track, an.length * float(i) / 8.0)
			if q.dot(ref) < 0.0:
				q = -q
			acc += Vector4(q.x, q.y, q.z, q.w)
		var m := Quaternion(acc.x, acc.y, acc.z, acc.w).normalized()
		swing_means[key] = m
		return m

	# W43: 몸 기준 이동 방향으로 '뒤로 걸음' 여부 (히스테리시스) 를 정해 st.rev 에 적음 → ext_clips.select 가 클립을 거꾸로 틂. 걷는 중 (땅·공격 아님) 만.
	func _dir_update(st) -> void:
		if move_off:
			return
		var mv := Vector2(float(st.get("mvF", 0.0)), float(st.get("mvS", 0.0)))
		var ok: bool = bool(st.get("walking", false)) and not bool(st.get("air", false)) and st.get("act") == null and mv.length() > K_.EXT_DIR_MIN_SPEED
		if ok:
			var r: Dictionary = Motion_.move_fold(mv.x, mv.y, dir_rev)
			dir_rev = bool(r.rev)
			dir_psi = float(r.psi)
		else:
			dir_rev = false
			dir_psi = 0.0
		st["rev"] = dir_rev

	var dir_psi := 0.0

	# W43 이동 가산 층 (extra_layer 에서): ① 골반을 이동 방향으로 돌리고 척추로 되돌림 (옆걸음) ② 속도·가속도 기울임 ③ 방향 전환 비틀림·팔 반동. 클립·코드 위에 뼈 회전만 더함.
	func _move_layer(st, dt: float) -> void:
		if move_off:
			return
		var walking: bool = bool(st.get("walking", false)) and not bool(st.get("air", false)) and st.get("act") == null
		var mvv := Vector2(float(st.get("mvF", 0.0)), float(st.get("mvS", 0.0)))
		var speed := mvv.length()
		# ① 골반 yaw
		var target := Motion_.hip_yaw(dir_psi) if (walking and speed > K_.EXT_DIR_MIN_SPEED) else 0.0
		dir_y = Motion_.follow(dir_y, target, dt, K_.EXT_DIR_RATE)
		if absf(dir_y) > 0.002:
			var hb: int = int(info.map.get("hips", -1))
			var wb: int = int(info.map.get("waist", -1))
			if hb >= 0:
				_add_rot(hb, Quaternion(Vector3.UP, dir_y))
			if wb >= 0:
				_add_rot(wb, Quaternion(Vector3.UP, -dir_y)) # 윗몸은 앞 (조준 방향) 그대로
		# ② 기울임
		var lt := Motion_.lean_pitch(speed, float(st.get("accF", 0.0)), dir_rev, walking) if not bool(st.get("air", false)) else 0.0
		lean_p = Motion_.follow(lean_p, lt, dt, K_.EXT_LEAN_RATE)
		if absf(lean_p) > 0.002:
			for e in K_.EXT_LEAN_BONES:
				var bi := sk.find_bone(str(e[0]))
				if bi >= 0:
					_add_rot(bi, Quaternion(Vector3.BACK, -lean_p * float(e[1])))
		# ③ 방향 전환
		var vw: Vector2 = st.get("vw", Vector2.ZERO)
		var tt := 0.0
		if walking and vw.length() > K_.EXT_TURN_MIN_SPEED:
			var ang := atan2(vw.y, vw.x)
			if turn_have:
				tt = Motion_.turn_twist(Motion_.wrap_pi(ang - turn_prev) / maxf(dt, 1e-3))
			turn_prev = ang
			turn_have = true
		else:
			turn_have = false
		turn_tw = Motion_.follow(turn_tw, tt, dt, K_.EXT_TURN_RATE)
		if absf(turn_tw) > 0.002:
			for e in K_.EXT_TURN_BONES:
				var bi2 := sk.find_bone(str(e[0]))
				if bi2 >= 0:
					_add_rot(bi2, Quaternion(Vector3.UP, turn_tw * float(e[1])))
			var ar: float = turn_tw / K_.EXT_TURN_MAX_RAD * K_.EXT_TURN_ARM_RAD
			var sr: int = int(info.map.get("shoulder_R", -1))
			var sl: int = int(info.map.get("shoulder_L", -1))
			if sr >= 0:
				_add_rot(sr, Quaternion(Vector3.BACK, ar))
			if sl >= 0:
				_add_rot(sl, Quaternion(Vector3.BACK, -ar))

	# W38 맞음 움찔: 맞은 직후 (hit.age < K_.EXT_HIT_FLINCH_S) 척추·머리를 맞은 방향으로 짧게 젖힘 (가산, 세기 = hit.pow 단계 — 약 0.5 … 치명 2).
	# 코드 구동 (hit_pose·휘청) 위에 척추 둘·머리 뼈를 더 돌릴 뿐이라 클립 층과 안 부딪침. 래그돌이 깨어 있고 모터가 약하면 (쓰러지는 중) 안 함 — 물리가 맡음.
	# 몸 기준 뼈대 공간: 앞 = +x, 위 = +y. 젖힘 (뒤로) = z 축 +, 옆 기울기 = x 축.
	func _hit_flinch(st) -> void:
		var hit = st.get("hit")
		if not (hit is Dictionary):
			return
		var react: Dictionary = Motion_.hit_react(hit)
		var win: float = maxf(K_.EXT_HIT_FLINCH_S, K_.EXT_HIT_CRIT_S if react.crit else 0.0)
		if float(hit.get("age", 9.0)) >= win:
			_armor_recoil()
			return
		var rg = Rag_._inst
		if rg != null and is_instance_valid(rg) and rg.rags.has(body):
			var r: Dictionary = rg.rags[body]
			if r.awake and float(r.motor) < K_.EXT_CLIP_MOTOR_MIN:
				return
		var age: float = float(hit.age)
		var env: float = (1.0 - exp(-age / 0.015)) * exp(-age / K_.EXT_HIT_FLINCH_DECAY_S)
		var amp: float = clampf(float(hit.get("pow", 1.0)), 0.4, 2.0) * K_.EXT_HIT_FLINCH_RAD * env
		var back: float = float(react.back) # 뒤로 밀리면 (dx < 0) 윗몸이 뒤로 젖혀짐
		var side: float = float(react.side)
		var twist: float = float(react.twist) # W40: 옆에서 맞으면 몸통이 비틀림, 뒤에서 맞으면 앞으로 숙이며 어깨 움츠림 (back 부호가 이미 반대)
		for e in K_.EXT_HIT_FLINCH_BONES:
			var bi := sk.find_bone(str(e[0]))
			if bi < 0:
				continue
			var k: float = float(e[1])
			var d := Quaternion(Vector3.BACK, back * amp * k) * Quaternion(Vector3.RIGHT, side * amp * k * 0.6) * Quaternion(Vector3.UP, twist * amp * k)
			_add_rot(bi, d)
		if react.crit: # 치명·강타: 머리가 채찍처럼 튕기고 무기 쥔 손이 흔들림 (감쇠 진동)
			var ce: float = exp(-age / 0.14) * clampf(float(hit.get("pow", 1.0)) / 2.0, 0.5, 1.2)
			var hb := sk.find_bone("mixamorig_Head")
			if hb >= 0:
				_add_rot(hb, Quaternion(Vector3.BACK, back * sin(age * 34.0) * K_.EXT_HIT_WHIP_RAD * ce))
			for hj in ["hand_R", "hand_L"]:
				var bi2: int = int(info.map.get(hj, -1))
				if bi2 >= 0:
					_add_rot(bi2, Quaternion(Vector3.BACK, sin(age * 52.0 + (0.0 if hj == "hand_R" else 1.7)) * K_.EXT_HIT_HAND_RAD * ce))
		_armor_recoil()

	# W40: 코드 구동이 안 맞추는 (안 매칭된) 뼈에 가산 층이 매 프레임 더하면 쌓이므로, 클립이 그 프레임 안 맞춘 뼈는 쉬는 회전으로 되돌린 뒤 더함
	# (옛 W38 움찔의 머리 뼈도 같은 문제 — 움찔이 끝나도 머리가 남은 만큼 기울어 있던 것을 같이 고침)
	var extra_ids: Array = []

	func _reset_extra() -> void:
		if extra_ids.is_empty():
			for n in ["mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head"]:
				extra_ids.append(sk.find_bone(n))
		var rl: Array = info.rest_local
		for bi in extra_ids:
			if bi < 0 or mapped.has(bi):
				continue
			if cw > 0.0005 and cbones.has(sk.get_bone_name(bi)):
				continue # 클립이 이번 프레임에 이 뼈를 새로 맞춤
			sk.set_bone_pose_rotation(bi, (rl[bi] as Transform3D).basis.get_rotation_quaternion())

	# 몸 (skeleton 공간) 축 회전 d 를 뼈의 지금 자세에 더함 (부모 전역 회전으로 지역 좌표로 옮김)
	func _add_rot(bi: int, d: Quaternion) -> void:
		var pg := _gt(sk.get_bone_parent(bi))
		var pb := pg.basis.get_rotation_quaternion()
		var lq: Quaternion = sk.get_bone_pose_rotation(bi)
		sk.set_bone_pose_rotation(bi, pb.inverse() * d * pb * lq)

	# W40 탱크 방어구 깨짐: 방패 쥔 (왼) 팔이 뒤로 튕김 (body.armor_break_react_at, 몸에 값이 있는 캐릭터만)
	func _armor_recoil() -> void:
		var at = body.get("armor_break_react_at")
		if at == null:
			return
		var age: float = Time.get_ticks_msec() / 1000.0 - float(at)
		if age < 0.0 or age > K_.EXT_ARMOR_BREAK_S:
			return
		var env: float = (1.0 - exp(-age / 0.02)) * exp(-age / 0.12)
		for j in ["shoulder_L", "elbow_L"]:
			var bi: int = int(info.map.get(j, -1))
			if bi >= 0:
				_add_rot(bi, Quaternion(Vector3.BACK, -K_.EXT_ARMOR_BREAK_RAD * env * (1.0 if j == "shoulder_L" else 0.6)))

	# 노드의 월드 변환 (나무 밖에서도: 부모 변환을 직접 곱함, 크기는 orthonormalized 로 뺄 것)
	func _world_of(n: Node3D) -> Transform3D:
		var t := Transform3D.IDENTITY
		var c: Node = n
		while c != null:
			if c is Node3D:
				t = (c as Node3D).transform * t
			c = c.get_parent()
		return t

	# W40 가산 층: 시선·머리 추적 + 숨쉬기 + 착지 숙임. 클립·코드 위에 뼈 회전만 더함 (판정·moves·figure_motion 불변).
	func _extra_layer(st) -> void:
		if extra_off:
			return
		var now := Time.get_ticks_msec() * 0.001
		extra_gap = (now - extra_t) if extra_t > 0.0 else 0.0
		var dt := clampf(now - extra_t, 0.0, 0.1) if extra_t > 0.0 else 0.0
		extra_t = now
		if dt <= 0.0:
			return
		var rg = Rag_._inst
		var rag_motor := -1.0
		if rg != null and is_instance_valid(rg) and rg.rags.has(body):
			var r: Dictionary = rg.rags[body]
			if r.awake:
				rag_motor = float(r.motor)
		_getup_layer(st, dt, rag_motor) # W43: 모터가 돌아오는 동안 손 짚고 일어나기 (힘 빠진 몸 규칙보다 먼저)
		if rag_motor >= 0.0 and rag_motor < K_.EXT_CLIP_MOTOR_MIN:
			return # 힘 빠진 몸은 물리가 맡음
		# --- 시선 ---
		var allow := Motion_.gaze_allowed(st)
		gaze_w = move_toward(gaze_w, 1.0 if allow else 0.0, dt * K_.EXT_GAZE_W_RATE)
		var want := 0.0
		if allow:
			var inv := _world_of(body).orthonormalized().affine_inverse()
			var others := []
			var alive := []
			for o in Motion_.bodies:
				if not is_instance_valid(o):
					continue
				alive.append(o)
				if o != body and (o as Node3D).visible and (o as Node).get_parent() != null: # 나무에서 뺀 (풀에 쉬는) 몸은 부모가 없어 안 봄
					others.append(inv * (_world_of(o).origin + Vector3(0, 1.4, 0)))
			if alive.size() != Motion_.bodies.size():
				Motion_.bodies = alive
			var tg: Dictionary = Motion_.pick_target(others, K_.EXT_GAZE_DIST, K_.EXT_GAZE_FOV)
			if not tg.is_empty():
				want = Motion_.clamp_yaw(float(tg.yaw), K_.EXT_GAZE_MAX_DEG)
		gaze_y = Motion_.follow(gaze_y, want, dt, K_.EXT_GAZE_RATE)
		var th: float = gaze_y * gaze_w
		if absf(th) > 0.002:
			for e in K_.EXT_GAZE_BONES:
				var bi := sk.find_bone(str(e[0]))
				if bi >= 0:
					_add_rot(bi, Quaternion(Vector3.UP, th * float(e[1])))
		_move_layer(st, dt) # W43
		_weapon_layer(st, dt) # W43
		# --- 숨쉬기 (서 있고 아무것도 안 할 때, 캐릭터마다 박자·위상 다름) ---
		breath_w = move_toward(breath_w, 1.0 if Motion_.breath_allowed(st) else 0.0, dt * 2.0)
		if breath_w > 0.01:
			var bv: float = Motion_.breath(float(st.get("t", 0.0)), str(body.get("char_id"))) * breath_w * K_.EXT_BREATH_RAD
			for e in [["mixamorig_Spine1", 0.5], ["mixamorig_Spine2", 1.0], ["mixamorig_Head", -0.6]]:
				var bi3 := sk.find_bone(str(e[0]))
				if bi3 >= 0:
					_add_rot(bi3, Quaternion(Vector3.BACK, bv * float(e[1])))
		# --- 착지: 윗몸 숙임 + 무릎 굽힘 (엉덩이를 그만큼 내려 발이 땅에 그대로) ---
		var la := Motion_.land_amount(st)
		if la > 0.02 and not bool(st.get("air", false)):
			var al: float = K_.EXT_LAND_BEND_RAD * la
			var fy0 := 0.0
			var nf := 0
			for side in ["R", "L"]:
				var fi: int = int(info.map.get("foot_" + side, -1))
				if fi >= 0:
					fy0 += _gt(fi).origin.y
					nf += 1
			for side in ["R", "L"]:
				var th_i: int = int(info.map.get("thigh_" + side, -1))
				var kn_i: int = int(info.map.get("knee_" + side, -1))
				var ft_i: int = int(info.map.get("foot_" + side, -1))
				if th_i >= 0 and kn_i >= 0:
					_add_rot(th_i, Quaternion(Vector3.BACK, al))
					_add_rot(kn_i, Quaternion(Vector3.BACK, -2.0 * al))
					if ft_i >= 0:
						_add_rot(ft_i, Quaternion(Vector3.BACK, al))
			# 무릎을 접으면 발이 올라가니 올라간 만큼 엉덩이를 내려 발은 땅에 그대로 (모델 다리 길이·비율이 달라도 잰 값으로)
			var hb: int = int(info.map.get("hips", -1))
			if hb >= 0 and nf > 0:
				var fy1 := 0.0
				for side in ["R", "L"]:
					var fi2: int = int(info.map.get("foot_" + side, -1))
					if fi2 >= 0:
						fy1 += _gt(fi2).origin.y
				sk.set_bone_pose_position(hb, sk.get_bone_pose_position(hb) - Vector3(0, (fy1 - fy0) / nf, 0))
			for e in [["mixamorig_Spine1", 0.5], ["mixamorig_Spine2", 0.5], ["mixamorig_Head", -0.5]]:
				var bi4 := sk.find_bone(str(e[0]))
				if bi4 >= 0:
					_add_rot(bi4, Quaternion(Vector3.BACK, -K_.EXT_LAND_LEAN_RAD * la * float(e[1])))

	# W34 1인칭 쌍둥이만: cfg.vm_bone_scale {모델 뼈 이름: 배율} — 그 뼈 (와 아래 자식 전부) 를 줄임. 탱크는 왼 아래팔에 붙은 방패가 화면 왼쪽 아래를 너무 가려서
	# (방패 쥐기 IK 는 손 관절 자리를 그대로 따라가니 3/4 타 쥐기는 유지, 방패·주먹만 같이 작아짐)
	func _vm_bone_scale() -> void:
		var vs: Dictionary = info.cfg.get("vm_bone_scale", {})
		for bn in vs:
			var bi := sk.find_bone(str(bn))
			if bi >= 0:
				sk.set_bone_pose_scale(bi, sk.get_bone_pose_scale(bi) * float(vs[bn]))

	# W40 1인칭 팔: 3인칭 몸의 공격·스킬 클립이 코드 자세에서 벗어난 만큼 (팔 뼈 지역 회전 차이) 을 쌍둥이 팔에 더함.
	# W43 안전한 방식: 손 뼈 차이는 안 받고 어깨·팔꿈치만 캐릭터별 비율 (VM_CLIP_ARM_K) 로 섞은 뒤, 손의 전역 회전이 그대로이도록 손 지역 회전을 되돌림 → 쥔 소총·갈고리·방패 방향이 안 변함
	# (W40: 손까지 섞으면 소총·갈고리를 쥔 팔이 솟고 왼손이 세로로 섰음). 새 전역 = sh·qs · el·qe · hand′ = sh · el · hand  ⇒  hand′ = qe⁻¹ · el⁻¹ · qs⁻¹ · el · hand
	func _vm_clip_arms() -> void:
		if clip_arm_k <= 0.0 or src_ext == null or not is_instance_valid(src_ext):
			return
		var kk: Array = K_.VM_CLIP_ARM_K.get(str(body.get("char_id")), [0.0, 0.0])
		for side in ["R", "L"]:
			var sb: int = int(info.map.get("shoulder_" + side, -1))
			var eb: int = int(info.map.get("elbow_" + side, -1))
			var hb: int = int(info.map.get("hand_" + side, -1))
			if sb < 0 or eb < 0 or hb < 0:
				continue
			var ds: Quaternion = src_ext.arm_delta.get(sb, Quaternion.IDENTITY)
			var de: Quaternion = src_ext.arm_delta.get(eb, Quaternion.IDENTITY)
			var qs := Quaternion.IDENTITY.slerp(ds, clip_arm_k * float(kk[0]))
			var qe := Quaternion.IDENTITY.slerp(de, clip_arm_k * float(kk[1]))
			if qs == Quaternion.IDENTITY and qe == Quaternion.IDENTITY:
				continue
			var el: Quaternion = sk.get_bone_pose_rotation(eb)
			var hd: Quaternion = sk.get_bone_pose_rotation(hb)
			sk.set_bone_pose_rotation(sb, sk.get_bone_pose_rotation(sb) * qs)
			sk.set_bone_pose_rotation(eb, el * qe)
			sk.set_bone_pose_rotation(hb, (qe.inverse() * el.inverse() * qs.inverse() * el * hd).normalized())

	# W34 공중 대시 손목: 공용 슈퍼맨 자세 (figure_pose SUPERMAN) 는 팔을 쭉 뻗는 것만 정해서 손에 쥔 무기 (해머·소총) 가 모델 쥐는 각 그대로 팔과 직각으로 솟음 —
	# cfg.dash_wrist {관절 이름 (hand_R 등): [x, y, z 도]} 만큼 손뼈를 그 뼈의 지역 축으로 더 돌려 무기가 팔 쪽 (앞) 으로 눕게. 코드 몸은 그대로
	func _dash_wrist() -> void:
		var dw: Dictionary = info.cfg.get("dash_wrist", {})
		for jn in dw:
			var bi: int = int(info.map.get(jn, -1))
			if bi < 0:
				continue
			var a: Array = dw[jn]
			var q := Quaternion.from_euler(Vector3(deg_to_rad(float(a[0])), deg_to_rad(float(a[1])), deg_to_rad(float(a[2]))))
			sk.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi) * q)

	# 뼈 전역 자세 (뼈대 공간): 뼈 지역 자세를 부모로 곱함
	func _gt(bi: int) -> Transform3D:
		var t := Transform3D.IDENTITY
		var b := bi
		while b >= 0:
			t = sk.get_bone_pose(b) * t
			b = sk.get_bone_parent(b)
		return t

	# W34 보폭 늘리기: 두 다리 각각, 발이 골반 기준 앞뒤 (뼈대 공간 x) 로 쉬는 자리에서 벗어난 만큼을 k 배로 늘린 자리 → 2본 IK (허벅지·정강이 길이 그대로, 무릎은 앞쪽).
	# c = 한 바퀴 평균 발 자리 (골반 기준 x, 뼈대 공간). 발 방향 (전역) 은 클립 그대로. 닿을 수 없으면 (다리 길이 밖) 가장 먼 자리까지만
	func _stride_ik(k: float, center: float) -> void:
		var hb: int = int(info.map.get("hips", -1))
		if hb < 0:
			return
		var rg: Array = info.rest_global
		for side in ["Left", "Right"]:
			var ub := sk.find_bone("mixamorig_%sUpLeg" % side)
			var kb := sk.find_bone("mixamorig_%sLeg" % side)
			var fb := sk.find_bone("mixamorig_%sFoot" % side)
			if ub < 0 or kb < 0 or fb < 0:
				continue
			var gH := _gt(hb)
			var gU := _gt(ub)
			var gK := _gt(kb)
			var gF := _gt(fb)
			var dx: float = (gF.origin.x - gH.origin.x) - center
			var target := gF.origin + Vector3(dx * (k - 1.0), 0.0, 0.0)
			var r := leg_ik(gU.origin, gK.origin, gF.origin, target, Vector3(1, 0, 0))
			var old1 := (gK.origin - gU.origin).normalized()
			var q1 := Quaternion(old1, ((r.knee as Vector3) - gU.origin).normalized())
			var bU := Basis(q1) * gU.basis
			var old2: Vector3 = q1 * (gF.origin - gK.origin).normalized()
			var q2 := Quaternion(old2, ((r.foot as Vector3) - (r.knee as Vector3)).normalized())
			var bK := Basis(q2) * Basis(q1) * gK.basis
			var pU := sk.get_bone_parent(ub)
			var pb: Basis = _gt(pU).basis if pU >= 0 else Basis.IDENTITY
			sk.set_bone_pose_rotation(ub, (pb.inverse() * bU).orthonormalized().get_rotation_quaternion())
			sk.set_bone_pose_rotation(kb, (bU.inverse() * bK).orthonormalized().get_rotation_quaternion())
			sk.set_bone_pose_rotation(fb, (bK.inverse() * gF.basis).orthonormalized().get_rotation_quaternion())

	# 2본 IK (순수 계산): 엉덩이 P·무릎 K·발 F 의 길이 (l1 = P→K, l2 = K→F) 를 지키며 발을 T 로 — 닿을 수 없으면 가장 먼/가까운 곳까지 (방향은 P→T).
	# pole = 무릎이 향할 쪽 (P→T 와 수직인 몫만 씀). 돌려줌 {knee, foot}
	static func leg_ik(P: Vector3, K: Vector3, F: Vector3, T: Vector3, pole: Vector3) -> Dictionary:
		var l1 := P.distance_to(K)
		var l2 := K.distance_to(F)
		var v := T - P
		var dist := v.length()
		if dist < 1e-6 or l1 < 1e-6 or l2 < 1e-6:
			return {"knee": K, "foot": F}
		var dir := v / dist
		dist = clampf(dist, absf(l1 - l2) + 1e-4, (l1 + l2) * 0.999)
		var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
		var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
		var perp := pole - dir * pole.dot(dir)
		if perp.length() < 1e-4:
			perp = (K - P) - dir * (K - P).dot(dir)
		perp = perp.normalized()
		return {"knee": P + dir * a + perp * h, "foot": P + dir * dist}

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
		cur_kind = ""
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
				var ft = face_tex.get("idle", tex_of(sf))
				var fm := style(G3_.toon_material(col, {"map": ft, "outline": false, "color_glow": float(cfg.get("face_glow", 0.0))}), cfg, false)
				mi.material_override = fm
				face_now = "idle"
				parts.append({"mi": mi, "color": col, "tex": ft, "solid": fm, "face": true})
				body.drawn.append({"mi": mi, "m": {"kind": "toon"}, "merged": false, "ext": true})
				continue
			var vc: bool = sf.get("vcolor", false)
			var mask: bool = vc and mode == "mask"
			var mt = skin_mask_for(cfg, str(sf.get("node", ""))) if mask else null
			var stex = tex_of(sf)
			var m := style(toon_for(col, stex, vc, mask, body.skin_color, {"skin_mask": mt} if mt != null else {}), cfg)
			mi.material_override = m
			parts.append({"mi": mi, "color": col, "tex": stex, "solid": m, "vcolor": vc, "mask": mask, "mask_tex": mt})
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
					pt.mi.material_override = GhostDepth.wrap_in(pt) # W35 깊이 선 먼저
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
				mi.material_override = GhostDepth.wrap_in(pt) # W35 깊이 선 먼저
			var sm := (pt.alpha if op < 1.0 else mi.material_override) as ShaderMaterial # 반투명이면 깊이 선 재질 말고 안쪽 반투명 재질에
			if sm != null:
				sm.set_shader_parameter("emissive", Color(0, 0, 0) if pt.get("band", false) and e == f[1] and e == Color(0, 0, 0) else e)
		opacity = op

	func _fx_mask(pt: Dictionary, f: Array, op: float) -> void:
		var mi: MeshInstance3D = pt.mi
		var want: Material = pt.solid
		if op < 1.0:
			if not pt.has("alpha"):
				pt.alpha = style(toon_for(pt.color, pt.tex, true, true, body.skin_color, {"opacity": 0.5, "outline": false, "skin_mask": pt.get("mask_tex")}), info.cfg, false)
				G3_.toon_hazard_light(pt.alpha, body.hz_light)
			want = pt.alpha
		var shown: Material = GhostDepth.wrap_in(pt) if op < 1.0 else want # W35 반투명이면 깊이 선 먼저
		if mi.material_override != shown:
			mi.material_override = shown
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
