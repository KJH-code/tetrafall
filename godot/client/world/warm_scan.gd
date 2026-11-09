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


# 카메라 앞에 재질들을 아주 작게 그리는 노드 (host 아래). 두 프레임 뒤 free() — 재질은 원래 주인이 쥐고 있어 셰이더가 남음
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
		var m: Material = e[0]
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = m
		mi.position = Vector3(i * 0.002, 0.004, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = box
		mm.instance_count = 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.position = Vector3(i * 0.002, 0.006, 0)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		i += 1
	return root
