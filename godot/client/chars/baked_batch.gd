# W7 미리 구운 몸 묶음: .glb 의 'batch' SkinnedMesh (툰 조각 전부 = 정점 색 메시 하나, 뼈 = 관절) 를 몸 노드에 잇기.
# G3 shaders/batch.gd 를 실행 중에 하던 일 (조각 정점을 다 돌며 SurfaceTool 로 합침, 탱크 약 13ms) 을 굽기 도구가 미리 함 → 여기는 뼈 ↔ 노드 짝만.
# 같은 이름·값 (pieces = 뼈마다 그 뼈를 움직이는 노드, skel, mi, root, HIDE_SCALE, rel_of·shown·sync·skinned_vertices) 이라 body.gd 의 뼈 맞추기 (_sync_bones) 가 그대로 씀.
# 다른 점: 피부 정점 색은 흰색 + 툰 skin_tint (a = 1, 몸 색) — 메시는 같은 캐릭터 몸끼리 같이 씀 (사람마다 색을 굽지 않음)
extends RefCounted

const G3 := preload("res://shaders/g3.gd")

const HIDE_SCALE := 1e-6 # 안 보이는 노드 뼈 크기 (G3 batch.gd 와 같음)

var pieces: Array[Node3D] = [] # 뼈 번호 → 노드
var skel: Skeleton3D
var mi: MeshInstance3D
var root: Node3D


# root = frame (뼈·정점 기준), nodes = body.gd 노드 표 (manifest 순서). 뼈 이름 'B_<노드 번호>' 로 짝을 찾음. 못 찾으면 false
func setup(root_: Node3D, skel_: Skeleton3D, nodes: Array, skin_color: Color) -> bool:
	root = root_
	skel = skel_
	for c in skel.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).skin != null:
			mi = c
	if mi == null:
		return false
	for b in skel.get_bone_count():
		var nm := skel.get_bone_name(b)
		var i := int(nm.substr(2)) if nm.begins_with("B_") else -1
		if i < 0 or i >= nodes.size():
			return false
		pieces.append(nodes[i])
	var m := G3.toon_material(Color.WHITE, {"vertex_color": true, "outline": true})
	m.set_shader_parameter("skin_tint", Color(skin_color.r, skin_color.g, skin_color.b, 1.0))
	mi.material_override = m
	sync()
	return true


# 뼈 자세 = 지금 노드 자리 (부모 뼈 노드 기준). 안 보이면 크기 거의 0 (G3 batch.gd sync 와 같은 셈)
func sync() -> void:
	for b in pieces.size():
		var p := pieces[b]
		var par := skel.get_bone_parent(b)
		var t := rel_of(p, pieces[par] if par >= 0 else root)
		skel.set_bone_pose_position(b, t.origin)
		skel.set_bone_pose_rotation(b, t.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(b, t.basis.get_scale() if p.visible else Vector3.ONE * HIDE_SCALE)


# upto 기준 노드 자리 (트리 밖에서도). 사이에 숨은 노드가 있으면 크기 HIDE_SCALE
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


func shown(n: Node3D) -> bool:
	while n != null and n != root:
		if not n.visible:
			return false
		n = n.get_parent() as Node3D
	return true


# 확인용 (테스트): 묶음 정점이 지금 자세에서 root 기준 어디에 있는지 (뼈 자세 × bind × 정점) + 그 정점의 뼈 번호
func skinned_vertices() -> PackedVector3Array:
	return skinned()[0]


func skinned() -> Array:
	var glob: Array[Transform3D] = []
	for b in pieces.size():
		var par := skel.get_bone_parent(b)
		glob.append((glob[par] if par >= 0 else Transform3D()) * skel.get_bone_pose(b))
	var bind_bone: Array[int] = [] # skin bind 번호 → 뼈 (이름으로 묶임)
	for k in mi.skin.get_bind_count():
		var bn := mi.skin.get_bind_name(k)
		bind_bone.append(skel.find_bone(bn) if bn != &"" else mi.skin.get_bind_bone(k))
	var out := PackedVector3Array()
	var which := PackedInt32Array()
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones = arr[Mesh.ARRAY_BONES]
	for i in vs.size():
		var k := int(bones[i * 4])
		var b := bind_bone[k]
		out.append(glob[b] * mi.skin.get_bind_pose(k) * vs[i])
		which.append(b)
	return [out, which]
