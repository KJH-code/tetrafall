# 필드 아이템·넉백 투사체 (c10-u2): 종류마다 실루엣이 다른 코드 모델 (world/item_models.gd — 표 world/item_look.gd). 종류마다 MultiMesh 하나 (툰 + 공용 잉크 외곽선, 한 재질을 나눠 씀),
# 표에 없는 종류는 예전 노란 상자 (items). 해 그림자는 그림자 전용 상자 MultiMesh 하나 (casters), 칸 윗면에 아이템 빛 노랑 받침 고리 (rings — 발밑 고리와 같은 모양·재질 갈래).
# 투사체는 글러브 주먹 공 (projs), 세로축으로 돎. 개수 0 인 묶음은 숨김 (그리기 0). 묶기·자리·고리 줄은 world/item_view_math.gd (순수 계산)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const IL := preload("res://world/item_look.gd")
const IM := preload("res://world/item_models.gd")
const M := preload("res://world/item_view_math.gd")
const FR := preload("res://world/foot_rings.gd")

const GROW := 4 # 인스턴스 자리가 모자라면 이만큼 더 잡음

var items := MultiMeshInstance3D.new() # 표에 없는 종류 (예전 상자)
var projs := MultiMeshInstance3D.new()
var models := {} # 묶음 이름 → MultiMeshInstance3D (IL.KINDS 순서 + 상자 = items)
var casters := MultiMeshInstance3D.new() # 그림자 전용 상자
var rings := MultiMeshInstance3D.new() # 받침 고리
var mat: ShaderMaterial # 모델 재질 하나 (종류·투사체가 나눠 씀)
var spin := 0.0
var hold_spin = null # 확인용 (tools/item_sheet.gd): 숫자를 넣으면 도는 각도를 그 값으로 고정


func _init() -> void:
	mat = IM.material()
	for kind in IL.KINDS:
		var n := _mmi(IM.mesh(kind), mat)
		models[kind] = n
		add_child(n)
	_fill(items, IM.box_mesh(), IM.box_material())
	models[IL.BOX] = items
	add_child(items)
	_fill(projs, IM.proj_mesh(), mat)
	add_child(projs)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * IL.SHADOW_BOX
	_fill(casters, box, null)
	casters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(casters)
	_fill(rings, FR.ring_mesh(float(IL.RING.inner), int(IL.RING.segs)), FR.material(), true)
	add_child(rings)


static func _mmi(mesh: Mesh, m: Material) -> MultiMeshInstance3D:
	return _fill(MultiMeshInstance3D.new(), mesh, m)


# 빈 MultiMesh 를 달고 숨김 (개수 0 = 그리기 0), 그림자는 안 드리움 (casters 가 모아서)
static func _fill(n: MultiMeshInstance3D, mesh: Mesh, m: Material, colors := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.visible_instance_count = 0
	n.multimesh = mm
	n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.visible = false
	return n


# 인스턴스 n 개를 쓸 자리 (모자라면 늘림 — 늘리면 변환이 비므로 부른 쪽이 n 개를 다시 채움), 0 개면 숨김
static func _count(node: MultiMeshInstance3D, n: int) -> MultiMesh:
	var mm := node.multimesh
	if mm.instance_count < n:
		mm.instance_count = n + GROW
	mm.visible_instance_count = n
	node.visible = n > 0
	return mm


func update(st: Dictionary, dt: float, now_ms: float) -> void:
	spin += dt * WC.ITEM_BOB[3]
	if hold_spin != null:
		spin = float(hold_spin)
	var list: Array = st.get("items", [])
	var pl: Array = st.get("projectiles", [])
	if list.is_empty() and pl.is_empty() and not (rings.visible or projs.visible):
		return # 아이템·투사체가 없고 이미 다 숨겼으면 할 일 없음 (대부분의 프레임)
	var turn := Basis(Vector3.UP, spin)
	for g in M.groups(list):
		var idx: Array = g[1]
		var mm := _count(models[g[0]], idx.size())
		for k in idx.size():
			var i: int = idx[k]
			mm.set_instance_transform(k, Transform3D(turn, Co.gpos(M.item_pos(list[i], i, now_ms))))
	var cm := _count(casters, list.size())
	var rm := _count(rings, list.size())
	for i in list.size():
		cm.set_instance_transform(i, Transform3D(turn, Co.gpos(M.item_pos(list[i], i, now_ms))))
		var row := M.ring_row(list[i])
		rm.set_instance_transform(i, FR.xform(row))
		rm.set_instance_color(i, row[4])
	var pm := _count(projs, pl.size())
	var pturn := Basis(Vector3.UP, spin * IL.PROJ_SPIN)
	for i in pl.size():
		pm.set_instance_transform(i, Transform3D(pturn, Co.gxyz(pl[i].x, pl[i].y, pl[i].z)))
