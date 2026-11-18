# 손 아이템 조준 미리보기 + 놓인 폭탄 범위 고리 그리기 (c11-u1). 서버가 이미 보내는 값만 그림:
#   · 내가 든 설치 블록 (스냅샷 players[].aim kind "brick"): 놓일 2칸에 흰 반투명 상자 + 노란 모서리 테. 못 놓는 자리 (ok = false) 면 전부 빨강
#   · 내가 든 폭탄 (kind "bomb"): 부서질 3×3 칸에 주황 납작 판 + 폭탄 자리 둘레에 사람이 맞는 범위 고리 (내 색 이어진 고리)
#   · 놓인 폭탄 (스냅샷 bombs[], 모든 시점): 맞는 범위에 끊긴 고리 (번개 예고와 같은 메시) + 안에서 차오르는 주황 원 — 다 차면 터짐
# world.gd 가 변수 선언에서 만들고 프레임마다 update 를 부름. 그리는 것은 트리에 들어갈 때 (_ready) 만듦 (world/bolt_fx.gd 와 같은 까닭).
# 그리기: 상자·판 = MultiMesh 하나 (인스턴스 색), 테 = MultiMesh 하나, 조준 고리 = 메시 하나, 놓인 폭탄 고리·원 = MultiMesh 하나. 평소엔 다 숨김 (그리기 0), 그래픽 낮춤에서도 켬.
# 재질은 ring_look.material (world/warm_scan.gd STD_KEYS 에 있는 모양 — 새 셰이더 없음). 순수 계산·수치는 world/hand_aim_math.gd
extends Node3D

const M := preload("res://world/hand_aim_math.gd")
const BM := preload("res://world/bolt_fx_math.gd")
const RL := preload("res://world/ring_look.gd")
const Co := preload("res://core/coords.gd")
const Bodies := preload("res://world/bodies.gd")

var box_mm: MultiMesh
var box_mmi: MultiMeshInstance3D
var edge_mm: MultiMesh
var edge_mmi: MultiMeshInstance3D
var ring: MeshInstance3D
var ring_color := -1 # 지금 고리 메시의 색 (바뀔 때만 메시를 다시 고름)
var bomb_mm: MultiMesh
var bomb_mmi: MultiMeshInstance3D
var hold_spin = null # 견본 도구 (tools/aim_sheet.gd) 가 놓인 폭탄 고리 각도를 고정 (rad). null = 판 시계로 돎
var _aim_key = null # 지금 그려 둔 조준 (바뀔 때만 인스턴스를 다시 씀). null = 안 그림


func _ready() -> void:
	var pr := int(M.HAND_AIM.priority)
	var cells := int(M.HAND_AIM.max_cells)
	box_mm = MultiMesh.new()
	box_mmi = MultiMeshInstance3D.new()
	edge_mm = MultiMesh.new()
	edge_mmi = MultiMeshInstance3D.new()
	bomb_mm = MultiMesh.new()
	bomb_mmi = MultiMeshInstance3D.new()
	var cube := cube_mesh()
	_pool(box_mmi, box_mm, cube, cells, RL.material(1.0, pr))
	_pool(edge_mmi, edge_mm, cube, cells * 12, RL.material(1.0, pr + 1))
	_pool(bomb_mmi, bomb_mm, BM.warn_mesh(), int(M.BOMB_RING.max) * 2, RL.material(1.0, int(M.BOMB_RING.priority)))
	ring = MeshInstance3D.new()
	ring.material_override = RL.material(float(M.HAND_AIM.ring_alpha), pr + 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)


func _pool(mmi: MultiMeshInstance3D, mm: MultiMesh, mesh: Mesh, n: int, mat: Material) -> void:
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0 # 필드 어디든 (인스턴스가 움직여도 잘리지 않게 — world/bolt_fx.gd 풀과 같음)
	mmi.visible = false
	add_child(mmi)


# 한 변 1 인 흰 상자 (가운데가 원점). 인스턴스 기저가 크기, 인스턴스 색이 칸 색
static func cube_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var vc := PackedColorArray()
	var nrm := PackedVector3Array()
	for axis in 3:
		for s in [-0.5, 0.5]:
			var o := Vector3.ZERO
			o[axis] = s
			var a := Vector3.ZERO
			a[(axis + 1) % 3] = 0.5
			var b := Vector3.ZERO
			b[(axis + 2) % 3] = 0.5
			v.append_array([o - a - b, o + a - b, o + a + b, o - a - b, o + a + b, o - a + b])
			for i in 6:
				vc.append(Color.WHITE)
				nrm.append(o * 2.0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = vc
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# 한 프레임: st = 스냅샷, me = 나 (없으면 {}), view_mode = View.mode, spectating = 관전 중인가, now = 판 시계 (ms)
func update(st: Dictionary, me: Dictionary, view_mode: String, spectating: bool, now: float) -> void:
	if box_mmi == null: # 트리 밖 (테스트)
		return
	var playing := BM.keep(str(st.get("phase", "")))
	# 조준: 스냅샷마다 같은 값이 오니 바뀔 때만 다시 씀 (든 채 가만히 있으면 그리기 명령 0)
	var key = null
	if M.aim_on(me, view_mode, spectating, playing):
		var color := Bodies.player_color(me, st)
		key = [me.aim.get("kind"), me.aim.get("ok"), me.aim.cells, color]
		if key != _aim_key:
			_aim(M.aim_rows(me, view_mode, spectating, color, playing))
	elif _aim_key != null:
		_aim([])
	_aim_key = key
	var bombs: Array = st.get("bombs", [])
	if not bombs.is_empty() or bomb_mmi.visible:
		_bombs(M.bomb_ring_rows(bombs, now, playing))


func _aim(rows: Array) -> void:
	var nb := 0
	var ne := 0
	var has_ring := false
	for r in rows:
		var kind := str(r.kind)
		var at := Co.gpos(r.at)
		var col := Co.color(r.color)
		if kind == "ring":
			has_ring = true
			if int(r.color) != ring_color:
				ring_color = int(r.color)
				ring.mesh = RL.mesh("windup", ring_color)
			ring.position = at
			ring.scale = Vector3(float(r.r), 1.0, float(r.r))
			continue
		var size: Vector3 = r.size
		var t := Transform3D(Basis.from_scale(Vector3(size.x, size.z, size.y)), at) # 게임 (x, y, z) 길이 → 고도 (x, z, y)
		if kind == "edge":
			if ne < edge_mm.instance_count:
				edge_mm.set_instance_transform(ne, t)
				edge_mm.set_instance_color(ne, Color(col.r, col.g, col.b, float(r.alpha)))
				ne += 1
		elif nb < box_mm.instance_count:
			box_mm.set_instance_transform(nb, t)
			box_mm.set_instance_color(nb, Color(col.r, col.g, col.b, M.face_alpha(float(r.alpha))))
			nb += 1
	box_mm.visible_instance_count = nb
	box_mmi.visible = nb > 0
	edge_mm.visible_instance_count = ne
	edge_mmi.visible = ne > 0
	ring.visible = has_ring


func _bombs(rows: Array) -> void:
	var n := 0
	var fc := Co.color(M.BOMB_RING.fill)
	for r in rows:
		if n + 2 > bomb_mm.instance_count:
			break
		var at := Co.gpos(r.at)
		# 원 먼저, 고리 나중 (인스턴스 차례 = 그리는 차례 — 번개 예고와 같음)
		bomb_mm.set_instance_transform(n, Transform3D(BM.fill_basis(float(r.fill_r)), at))
		bomb_mm.set_instance_color(n, Color(fc.r, fc.g, fc.b, float(M.BOMB_RING.fill_alpha)))
		bomb_mm.set_instance_transform(n + 1, Transform3D(BM.ring_basis(float(r.r), float(r.spin) if hold_spin == null else float(hold_spin)), at))
		bomb_mm.set_instance_color(n + 1, Color(1, 1, 1, float(M.BOMB_RING.ring_alpha)))
		n += 2
	bomb_mm.visible_instance_count = n
	bomb_mmi.visible = n > 0
