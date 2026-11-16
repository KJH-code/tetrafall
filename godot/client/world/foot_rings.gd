# 발밑 색 고리 (c7-u1): 판 중 살아 있는 사람마다 발 아래 바닥에 그 사람 색 (이름표와 같은 플레이어 색) 납작한 고리 — 난전에서 누가 어디 있는지.
# world/bodies.gd 의 자식 MultiMeshInstance3D 하나 (사람이 늘어도 그리기 한 번), bodies.update 끝에서 한 번 갱신. 누구를·어디에·얼마나는 world/foot_ring_math.gd (순수 계산), 수치 WC.FOOT_RING.
# 재질은 표준 재질 모양 (world/warm_scan.gd STD_KEYS 안 — 떨어지는 블록 그림자 칸과 같은 모양이라 셰이더를 새로 만들지 않음), 순서는 이름표 (WC.LABEL_PRIORITY) 아래
extends MultiMeshInstance3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const M := preload("res://world/foot_ring_math.gd")
const WS := preload("res://world/warm_scan.gd")


func _init() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ring_mesh(float(WC.FOOT_RING.inner), int(WC.FOOT_RING.segs))
	mm.instance_count = int(C.ROOM_MAX) + 1 # 사람마다 하나 + 3인칭 내 안쪽 흰 테
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


# 빛 안 받는 반투명 정점 색 (인스턴스 색 = 플레이어 색 + 알파), 깊이 검사 켬 (블록 뒤 고리는 가려짐)
static func material() -> StandardMaterial3D:
	var m: StandardMaterial3D = WS.std_material(WC.FOOT_RING.key)
	m.render_priority = WC.FOOT_RING.order
	return m


# 바깥 반지름 1 인 납작한 고리 (안쪽 = inner), 위 (+Y) 를 봄. 크기는 인스턴스 배율로
static func ring_mesh(inner: float, segs: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in segs:
		var a := TAU * i / segs
		var d := Vector3(cos(a), 0, sin(a))
		verts.append(d)
		verts.append(d * inner)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		var o0 := i * 2
		var o1 := ((i + 1) % segs) * 2
		idx.append_array([o0, o1, o0 + 1, o1, o1 + 1, o0 + 1]) # 위에서 봐서 시계 방향 = 앞면
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# 한 줄 [x, y, z, 반지름, 색] 의 인스턴스 변환: 게임 좌표 자리, 반지름만큼 가로로 키움
static func xform(e: Array) -> Transform3D:
	var r := float(e[3])
	return Transform3D(Basis.from_scale(Vector3(r, 1, r)), Co.gxyz(e[0], e[1], e[2]))


# list = foot_ring_math.rings 의 줄 [x, y, z, 반지름, 색] 을 인스턴스로
func show_rings(list: Array) -> void:
	var mm := multimesh
	if list.size() > mm.instance_count:
		mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, xform(list[i]))
		mm.set_instance_color(i, list[i][4])
	mm.visible_instance_count = list.size()
	visible = not list.is_empty()


# world = 판 (World: field·column_top·solid_at). 없으면 (테스트·도구가 Bodies 만 씀) 안 그림
func update(world, st: Dictionary, my_id, hide_me: bool, sky: bool, shown: Dictionary, colors: Dictionary) -> void:
	if world == null or not world.has_method("column_top") or not world.has_method("solid_at"):
		show_rings([])
		return
	var step := float(WC.FOOT_RING.step)
	var ground := func(cx: int, cy: int, feet_z: float) -> float:
		return float(M.ground_under(world.column_top(cx, cy), feet_z, func(z: int) -> bool: return world.solid_at(cx + 0.5, cy + 0.5, z), step))
	show_rings(M.rings(st, my_id, hide_me, sky, shown, colors, world.field, ground, WC.FOOT_RING))
