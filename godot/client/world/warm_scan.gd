# 재질 미리 그리기 (W41): 이펙트·표식·투사체·갈고리·건축 블록·아이템 등 '처음 쓰일 때' 셰이더를 컴파일하던 재질을 메뉴에서 숨은 채로 한 번씩 그려 둠.
# 고도 Compatibility 는 재질 (BaseMaterial3D 도 기능 조합마다) 을 처음 그릴 때 GLSL 을 컴파일 — 비어 있는 MultiMesh 풀은 안 그려서 첫 폭발·첫 궁 순간에 컴파일 (GPU 드라이버 몫, CPU ms 로 못 잼).
# 방법: world 아래 모든 GeometryInstance3D 의 재질 (material_override·표면 재질·next_pass) 을 모아 (한 재질 한 번), 카메라 앞에 아주 작게 같은 재질의 상자 (보통·MultiMesh) 를 두 프레임 그림.
# 순수 수집 (collect) 과 그리기 (spawn) 를 나눠 테스트 (tests/test_w41.gd). 그리기는 world/prewarm_sched.gd 가 조각으로 부름.
extends RefCounted

const SKIP_SCRIPTS := ["body.gd", "external.gd", "ext_shadow.gd", "baked_batch.gd", "baked.gd", "bodies.gd", "ragdoll.gd", "viewmodel.gd"] # 몸·1인칭 팔은 W30 몸 데우기가 맡음


# root 아래 보이는 대상 재질 목록 (중복 없이, 이미 한 것 (done: id → true) 제외). 한 항목 = [재질, MultiMesh 로도 그릴지]
static func collect(root: Node, done: Dictionary) -> Array:
	var out := []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is GeometryInstance3D) or _skip(n):
			continue
		var gi := n as GeometryInstance3D
		var multi := gi is MultiMeshInstance3D
		var mats := []
		if gi.material_override != null:
			mats.append(gi.material_override)
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			var mesh := (gi as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var m = (gi as MeshInstance3D).get_surface_override_material(si)
				if m == null:
					m = mesh.surface_get_material(si)
				if m != null:
					mats.append(m)
		elif multi and (gi as MultiMeshInstance3D).multimesh != null and (gi as MultiMeshInstance3D).multimesh.mesh != null:
			var mesh2 := (gi as MultiMeshInstance3D).multimesh.mesh
			for si in mesh2.get_surface_count():
				var m2 = mesh2.surface_get_material(si)
				if m2 != null:
					mats.append(m2)
		for m in mats:
			var id: int = m.get_instance_id()
			if done.has(id):
				continue
			done[id] = true
			out.append([m, multi])
	return out


static func _skip(n: Node) -> bool:
	var a: Node = n
	while a != null and a.get_script() == null:
		a = a.get_parent()
	return a != null and (a.get_script() as Script).resource_path.get_file() in SKIP_SCRIPTS


# W42 항목 4 (--mat-first 로 8명 판을 돌려 '판에서 처음 그려진 재질 모양' 을 모은 것): 이벤트 때 코드가 새로 만드는 BaseMaterial3D 모양들 — 이전 미리 그리기는 트리에 있는 재질만 덮어
# 반짝·고리·표창·경고 칸·그림자 칸 같은 이벤트 재질은 처음 쓰일 때 컴파일됐음. 한 줄 = [shading, transparency, blend, cull, no_depth, billboard, vertex_color, texture, emission, disable_fog, depth_draw]
# (core/mat_first.gd mat_key 와 같은 순서·값. render_priority 는 셰이더 모양에 안 들어가 뺌). 테스트가 만든 재질의 열쇠가 이 줄과 같은지 확인
const STD_KEYS := [
	[0, 1, 0, 2, 0, 0, 0, 0, 0, 1, 0], [0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0], [0, 1, 0, 2, 0, 0, 1, 0, 0, 0, 2], [0, 1, 1, 2, 0, 0, 0, 1, 0, 1, 0],
	[0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0], [0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0], [0, 1, 1, 2, 0, 0, 0, 0, 0, 1, 0], [0, 1, 1, 2, 0, 0, 0, 0, 0, 0, 2],
	[0, 0, 0, 2, 0, 0, 0, 0, 0, 1, 0], [0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0], [0, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0], [0, 1, 0, 2, 1, 0, 0, 0, 0, 0, 0],
	[0, 1, 0, 2, 1, 0, 0, 0, 0, 1, 0],
]
# 스킨 몸에 입히는 표준 반투명 모양 (잔상·낙사 잔상·표식 번쩍: STD_KEYS 중 스킨 메시에도 쓰이는 것)
const SKIN_KEYS := [[0, 1, 0, 2, 0, 0, 0, 0, 0, 1, 0], [0, 1, 1, 2, 0, 0, 0, 0, 0, 1, 0]]
static var _px: ImageTexture = null


static func std_material(k: Array) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = k[0]
	m.transparency = k[1]
	m.blend_mode = k[2]
	m.cull_mode = k[3]
	m.no_depth_test = k[4] == 1
	m.billboard_mode = k[5]
	m.vertex_color_use_as_albedo = k[6] == 1
	if k[7] == 1:
		if _px == null:
			var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
			_px = ImageTexture.create_from_image(img)
		m.albedo_texture = _px
	m.emission_enabled = k[8] == 1
	m.disable_fog = k[9] == 1
	m.depth_draw_mode = k[10]
	return m


# 이 표의 재질들 (한 번만 만들어 기억 — 같은 모양은 컴파일도 한 번). 항목 = [재질, MultiMesh 로도]
static var _std: Array = []


static func std_entries() -> Array:
	if _std.is_empty():
		for k in STD_KEYS:
			_std.append([std_material(k), true])
		_std.append(["sprite", false]) # 빌보드 그림 (머리 위 음표·표식 칸·HP 막대) — Sprite3D 가 스스로 만드는 재질 갈래
	return _std.duplicate()


static func clear_static() -> void: # 종료 때 정적 상태를 비움 (재질 리소스를 쥔 채 엔진이 내려가지 않게)
	_std = []
	_px = null


# 카메라 앞에 재질들을 아주 작게 그리는 노드 (host 아래). 두 프레임 뒤 free() — 재질은 원래 주인이 쥐고 있어 셰이더가 남음.
# 한 재질을 그리는 모양: 메시 · MultiMesh (색+custom) · (W42) MultiMesh 색만 · custom 만 · 평범 — 고도는 그리는 노드 종류마다 셰이더 갈래를 따로 컴파일할 수 있어 판이 실제로 쓰는 조합 전부
static func spawn(host: Node3D, mats: Array, cam: Camera3D) -> Node3D:
	var root := Node3D.new()
	root.name = "WarmScan"
	host.add_child(root)
	if cam != null and cam.is_inside_tree():
		root.global_transform = cam.global_transform.translated_local(Vector3(0, 0, -2.0))
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.001
	var i := 0
	for e in mats:
		if e[0] is String: # "sprite": 판이 쓰는 Sprite3D 두 갈래 (음표·표식 칸 = 양면·깊이 검사, HP 막대 = 깊이 검사 끔)
			for nd in [false, true]:
				var sp := Sprite3D.new()
				sp.texture = std_material([0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0]).albedo_texture
				sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				sp.fixed_size = true
				sp.shaded = false
				sp.double_sided = not nd
				sp.no_depth_test = nd
				sp.pixel_size = 0.0001
				sp.position = Vector3(i * 0.002, 0.01 + (0.002 if nd else 0.0), 0)
				root.add_child(sp)
			i += 1
			continue
		var m: Material = e[0]
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = m
		mi.position = Vector3(i * 0.002, 0.004, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var f := 0
		for flags in MULTI_FLAGS:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = flags[0]
			mm.use_custom_data = flags[1]
			mm.mesh = box
			mm.instance_count = 1
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = m
			mmi.position = Vector3(i * 0.002, 0.006 + f * 0.002, 0)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
			f += 1
		i += 1
	return root


const MULTI_FLAGS := [[true, true], [true, false], [false, true], [false, false]] # [색, custom]
