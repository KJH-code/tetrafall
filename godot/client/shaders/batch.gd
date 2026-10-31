# 몸 조각 묶기 (JS client/batch.js): 조각 MeshInstance3D 여럿 → 정점 색 SkinnedMesh 하나 (뼈 = 조각) → 툰 1 + 외곽선 1 그리기.
# 조각은 그대로 남아 '뼈' (자세·숨김은 예전처럼 조각을 만지면 됨). 조각 자체는 안 그림 (layers 0·그림자 끔).
# 매 프레임 sync() (기본: _process, process_priority 큼 = 애니 뒤): 뼈 계층 = 조각 계층, 뼈 자세 = 부모 조각 기준 자리, 안 보이는 조각 (visible 거짓, 그 아래도) 은 뼈 크기 거의 0.
# 한 조각의 자기 transform 이 비뚤림 (shear) 을 가지면 안 됨 (뼈는 자리·돌림·크기만) — 부모 크기 × 자식 돌림은 괜찮음
# 묶는 조각: G3 툰 재질 (불투명, 그림 없음, 발광 없음) 만. 나머지 (그림·투명·발광·다른 셰이더) 는 그대로 따로 그림.
#   var b := G3.batch_mesh(body_root)   # body_root 아래 조각 다 모음 → body_root 에 "G3Batch" 자식으로 붙음
extends Node3D

const HIDE_SCALE := 1e-6 # 안 보이는 조각 뼈 크기 (0 이면 돌림을 못 뽑음)
const TOON := preload("res://shaders/toon.gdshader")

var pieces: Array[MeshInstance3D] = []
var skel: Skeleton3D
var mi: MeshInstance3D
var root: Node3D


static func _batchable(p: MeshInstance3D) -> bool:
	var m = p.material_override
	if m == null and p.mesh and p.mesh.get_surface_count() > 0:
		m = p.mesh.surface_get_material(0)
	if not (m is ShaderMaterial) or m.shader != TOON:
		return false
	if m.get_shader_parameter("use_tex") or m.get_shader_parameter("use_vertex_color"):
		return false
	var e = m.get_shader_parameter("emissive")
	return e == null or Color(e).is_equal_approx(Color.BLACK) or (e is Vector3 and e == Vector3.ZERO)


func build(body: Node3D, material: Material) -> void:
	root = body
	for n in body.find_children("*", "MeshInstance3D", true, false):
		if n is MeshInstance3D and n.mesh and _batchable(n):
			pieces.append(n)
	skel = Skeleton3D.new()
	skel.name = "Skel"
	add_child(skel)
	var skin := Skin.new()
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in pieces.size():
		var p := pieces[b]
		skel.add_bone("p%d" % b)
		var par := _parent_piece(p)
		if par >= 0:
			skel.set_bone_parent(b, par) # 뼈 계층 = 조각 계층 (부모 크기 × 자식 돌림의 비뚤림도 그대로 곱해짐)
		var rel := rel_of(p) # 조각 → root
		skin.add_bind(b, rel.affine_inverse())
		var m = p.material_override if p.material_override else p.mesh.surface_get_material(0)
		var col: Color = m.get_shader_parameter("albedo")
		for s in p.mesh.get_surface_count():
			var arr := p.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns = arr[Mesh.ARRAY_NORMAL]
			var idx = arr[Mesh.ARRAY_INDEX]
			var order: Array = range(vs.size()) if idx == null or idx.size() == 0 else Array(idx)
			for i in order:
				st.set_color(col) # sRGB 그대로 (툰이 COLOR 를 sRGB 로 보고 선형으로 바꿈)
				if ns != null and ns.size() > i:
					st.set_normal(rel.basis * ns[i])
				st.set_bones(PackedInt32Array([b, 0, 0, 0]))
				st.set_weights(PackedFloat32Array([1, 0, 0, 0]))
				st.add_vertex(rel * vs[i]) # root 기준 자리 (bind 때)
		p.layers = 0
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = st.commit()
	mi.skin = skin
	mi.material_override = material
	add_child(mi)
	mi.skeleton = mi.get_path_to(skel)
	process_priority = 1000
	sync()


# 뼈 자세 = 지금 조각 자리 (root 기준). 안 보이면 크기 0
func sync() -> void:
	for b in pieces.size():
		var p := pieces[b]
		var par := skel.get_bone_parent(b)
		var t := rel_of(p, pieces[par] if par >= 0 else root)
		skel.set_bone_pose_position(b, t.origin)
		skel.set_bone_pose_rotation(b, t.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(b, t.basis.get_scale() if p.visible else Vector3.ONE * HIDE_SCALE)


func _parent_piece(p: Node3D) -> int:
	var n := p.get_parent()
	while n != null and n != root:
		var i := pieces.find(n)
		if i >= 0:
			return i
		n = n.get_parent()
	return -1


# upto 기준 조각 자리 (부모를 따라 올라가며 곱함 — 장면 트리 밖에서도 됨). 사이에 묶이지 않은 노드가 숨으면 크기 HIDE_SCALE
func rel_of(n: Node3D, upto: Node3D = null) -> Transform3D:
	if upto == null:
		upto = root
	var t := Transform3D()
	var first := true
	while n != null and n != upto:
		if not first and not n.visible:
			t = Transform3D(Basis().scaled(Vector3.ONE * HIDE_SCALE), Vector3.ZERO) * t
		t = n.transform * t
		first = false
		n = n.get_parent() as Node3D
	return t


# root 까지 다 보이는지 (is_visible_in_tree 와 같지만 트리 밖에서도)
func shown(n: Node3D) -> bool:
	while n != null and n != root:
		if not n.visible:
			return false
		n = n.get_parent() as Node3D
	return true


func _process(_d: float) -> void:
	sync()


# 확인용 (테스트): 묶은 메시 정점이 지금 자세에서 root 기준 어디에 있는지 (뼈 자세 × bind × 정점)
func skinned_vertices() -> PackedVector3Array:
	var glob: Array[Transform3D] = [] # 뼈 전역 자세를 직접 곱함 (트리 밖이면 Skeleton3D 의 전역 캐시가 안 바뀜)
	for b in pieces.size():
		var par := skel.get_bone_parent(b)
		glob.append((glob[par] if par >= 0 else Transform3D()) * skel.get_bone_pose(b))
	var out := PackedVector3Array()
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	for i in vs.size():
		var b := bones[i * 4]
		out.append(glob[b] * mi.skin.get_bind_pose(b) * vs[i])
	return out
