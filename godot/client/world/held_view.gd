# 든 아이템 (c11-u2): 손 아이템 (폭탄·넉백 글러브·설치 블록) 을 든 사람의 오른 어깨 옆에 그 종류 모델을 작게 띄움 — 누가 무엇을 들었는지 몸 옆 실루엣으로.
# world/bodies.gd 의 자식 (발밑 고리 world/foot_rings.gd 와 같은 길 — 몸 뼈에 안 붙임), bodies.update 끝에서 한 번 갱신. 종류마다 MultiMesh 하나 (바닥 아이템 모델 world/item_models.gd·툰 재질 하나를 나눠 씀),
# 아무도 안 들면 숨김 (그리기 0), 그림자·받침 고리 없음. 판 중 (발밑 고리와 같은 단계) 에만 · 관전에서 시선을 막아 옅어진 몸의 것은 안 그림 (c11-fix F3·F7). 누구를·어디에·얼마나는 world/held_math.gd (순수 계산), 수치 world/item_look.gd HELD
extends Node3D

const C := preload("res://core/config.gd")
const IL := preload("res://world/item_look.gd")
const IM := preload("res://world/item_models.gd")
const M := preload("res://world/held_math.gd")

var models := {} # 종류 → MultiMeshInstance3D (IL.HELD.kinds 순서)
var mat: ShaderMaterial # 모델 재질 하나 (세 종류가 나눠 씀)
var hold_spin = null # 확인용 (tools/item_sheet.gd): 숫자를 넣으면 도는 각도를 그 값으로 고정


func _init() -> void:
	mat = IM.material()
	for kind in IL.HELD.kinds:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = IM.mesh(kind)
		mm.instance_count = int(C.ROOM_MAX) # 사람마다 하나까지
		mm.visible_instance_count = 0
		var n := MultiMeshInstance3D.new()
		n.name = "Held_%s" % kind
		n.multimesh = mm
		n.material_override = mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.visible = false
		models[kind] = n
		add_child(n)


# rows = held_math.rows 의 줄 [종류, 자리] 을 종류별 인스턴스로 (0개인 종류는 숨김)
func show_rows(rows: Array, angle: float) -> void:
	var used := {}
	for row in rows:
		var kind := str(row[0])
		var mm: MultiMesh = (models[kind] as MultiMeshInstance3D).multimesh
		var k := int(used.get(kind, 0))
		if k >= mm.instance_count:
			continue # 방 최대 인원보다 많이는 안 옴
		mm.set_instance_transform(k, M.xform(row, angle))
		used[kind] = k + 1
	for kind in models:
		var n: MultiMeshInstance3D = models[kind]
		var cnt := int(used.get(kind, 0))
		if n.visible or cnt > 0:
			n.multimesh.visible_instance_count = cnt
			n.visible = cnt > 0


# players = 스냅샷 players · shown = Bodies.shown (id → 화면 위치) · hide_me = 1인칭이라 내 몸을 숨김 · phase = 판 단계 (판 중에만 그림) · thin = 관전에서 옅어진 몸 (그 사람 것은 안 그림)
func update(players: Array, my_id, hide_me: bool, shown: Dictionary, now_ms: float, phase: String, thin: Dictionary = {}) -> void:
	show_rows(M.rows(players, my_id, hide_me, shown, phase, thin), float(hold_spin) if hold_spin != null else M.spin_at(now_ms))
