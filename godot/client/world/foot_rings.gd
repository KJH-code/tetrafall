# 발밑 색 고리 (c7-u1): 판 중 살아 있는 사람마다 발 아래 바닥에 그 사람 색 (이름표와 같은 플레이어 색) 납작한 고리 — 난전에서 누가 어디 있는지.
# world/bodies.gd 의 자식 MultiMeshInstance3D 하나 (사람이 늘어도 그리기 한 번), bodies.update 끝에서 한 번 갱신. 누구를·어디에·얼마나는 world/foot_ring_math.gd (순수 계산), 수치 WC.FOOT_RING.
# 재질은 표준 재질 모양 (world/warm_scan.gd STD_KEYS 안 — 떨어지는 블록 그림자 칸과 같은 모양이라 셰이더를 새로 만들지 않음), 순서는 이름표 (WC.LABEL_PRIORITY) 아래
extends MultiMeshInstance3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const M := preload("res://world/foot_ring_math.gd")
const WS := preload("res://world/warm_scan.gd")
const BS := preload("res://shaders/block_style.gd")
const Cells := preload("res://world/cells.gd")


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


# c7-fix F3: 테마 지형 칸 (x, y, z) 의 윗면 높낮이 난수 −0.5~0.5 — 지형 셰이더가 받는 값 (block_style.gd cell_looks 의 custom.b → terrain.gdshader v_lift = b × tf_step) 과 같은 식.
# 둘이 어긋나지 않게 tests/test_world.gd test_c7_foot_ring_follows_top 이 cell_looks 값·셰이더 줄과 묶음
static func top_rand(x: int, y: int, z: int) -> float:
	return BS.cell_rand(x, y, z, 1) - 0.5


# 그 칸 윗면이 정수 높이에서 올라온 양 (칸): 칸마다 높낮이 (× 재질의 tf_step) + 잡음 밀림 (꼭짓점이 위로 가장 많이 밀릴 때 = 재질의 tf_disp × FOOT_RING.disp_k) 여유
static func top_bump(x: int, y: int, z: int, step: float, disp: float) -> float:
	return top_rand(x, y, z) * step + float(WC.FOOT_RING.disp_k) * disp


# 지금 판이 그리는 테마 지형 재질의 [tf_step, tf_disp] (grid_view.terrain_mmi — 그래픽 낮춤이면 둘 다 0, 테마 지형이 없으면 [0, 0])
static func terrain_steps(world) -> Array:
	var gv = world.get("grid_view") if world != null else null
	var tm = gv.get("terrain_mmi") if gv != null else null
	var mat := (tm as MultiMeshInstance3D).material_override as ShaderMaterial if tm is MultiMeshInstance3D and (tm as MultiMeshInstance3D).visible else null
	if mat == null:
		return [0.0, 0.0]
	var s = mat.get_shader_parameter("tf_step")
	var d = mat.get_shader_parameter("tf_disp")
	return [float(s) if s != null else 0.0, float(d) if d != null else 0.0]


# world = 판 (World: field·column_top·solid_at). 없으면 (테스트·도구가 Bodies 만 씀) 안 그림
func update(world, st: Dictionary, my_id, hide_me: bool, sky: bool, shown: Dictionary, colors: Dictionary) -> void:
	if world == null or not world.has_method("column_top") or not world.has_method("solid_at"):
		show_rings([])
		return
	var step := float(WC.FOOT_RING.step)
	var ground := func(cx: int, cy: int, feet_z: float) -> float:
		return float(M.ground_under(world.column_top(cx, cy), feet_z, func(z: int) -> bool: return world.solid_at(cx + 0.5, cy + 0.5, z), step))
	# 꼭대기 칸이 테마 지형 칸이면 그 칸 윗면의 실제 높낮이를 따라감 (F3). 쌓인 블록·건축가 블록 (skip)·바닥판은 평평 (0)
	var ts := terrain_steps(world)
	var bump := Callable()
	if float(ts[0]) != 0.0 or float(ts[1]) != 0.0:
		var g: PackedByteArray = world.grid()
		var f: Vector3i = world.field
		var skip: Dictionary = world.grid_view.skip
		bump = func(cx: int, cy: int, top: int) -> float:
			var i := ((top - 1) * f.y + cy) * f.x + cx
			if top <= 0 or i >= g.size() or g[i] != Cells.TERRAIN or skip.has(i):
				return 0.0
			return top_bump(cx, cy, top - 1, float(ts[0]), float(ts[1]))
	show_rings(M.rings(st, my_id, hide_me, sky, shown, colors, world.field, ground, WC.FOOT_RING, bump))
