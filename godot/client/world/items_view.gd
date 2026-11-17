# 필드 아이템·넉백 투사체 (c10-u2): 종류마다 실루엣이 다른 코드 모델 (world/item_models.gd — 표 world/item_look.gd). 종류마다 MultiMesh 하나 (툰 + 공용 잉크 외곽선, 한 재질을 나눠 씀),
# 표에 없는 종류는 예전 노란 상자 (items). 해 그림자는 그림자 전용 상자 MultiMesh 하나 (casters), 칸 윗면에 아이템 빛 노랑 받침 고리 (rings — 발밑 고리와 같은 모양·재질 갈래).
# 투사체는 글러브 주먹 공 (projs), 세로축으로 돎. 개수 0 인 묶음은 숨김 (그리기 0). 묶기·자리·고리 줄은 world/item_view_math.gd (순수 계산)
# c10-fix F3 나옴·사라짐 신호: 스냅샷마다 아이템 열쇠 (종류·칸) 를 앞 스냅샷과 견줘, 새로 나온 칸에 짧은 빛 기둥 (pillars) + 퍼지는 고리, 없어진 칸에 터지는 겹 고리 + 짧은 빛 줄 (IL.SIGNAL).
# 고리는 받침 고리 묶음 (rings) 에 얹음 (그리기 수 그대로), 기둥·빛 줄만 묶음 하나 (신호가 도는 0.5초 동안만 보임). 첫 스냅샷·판 바뀜·재접속·연습·튜토리얼엔 안 냄 (M.signal_ok)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const IL := preload("res://world/item_look.gd")
const IM := preload("res://world/item_models.gd")
const M := preload("res://world/item_view_math.gd")
const FR := preload("res://world/foot_rings.gd")
const G3 := preload("res://shaders/g3.gd")
const CellLod := preload("res://world/cell_lod.gd")
const EventFx := preload("res://fx/event_fx.gd")
const EM := preload("res://fx/event_fx_math.gd")
const EK := preload("res://fx/event_fx_config.gd")

const GROW := 4 # 인스턴스 자리가 모자라면 이만큼 더 잡음

var items := MultiMeshInstance3D.new() # 표에 없는 종류 (예전 상자)
var projs := MultiMeshInstance3D.new()
var models := {} # 묶음 이름 → MultiMeshInstance3D (IL.KINDS 순서 + 상자 = items)
var casters := MultiMeshInstance3D.new() # 그림자 전용 상자
var rings := MultiMeshInstance3D.new() # 받침 고리
var mat: ShaderMaterial # 모델 재질 하나 (종류·투사체가 나눠 씀)
var spin := 0.0
var hold_spin = null # 확인용 (tools/item_sheet.gd): 숫자를 넣으면 도는 각도를 그 값으로 고정
var pillars := MultiMeshInstance3D.new() # c10-fix F3 나옴 빛 기둥 (카메라 쪽으로 선 세로 줄 — 이벤트 효과 보급 기둥과 같은 메시 갈래·같은 재질 모양)
var sigs: Array = [] # 지금 그리는 신호 [{kind: "born"|"gone", x, y, z, type, t0 (ms)}]
var hold_sig = null # 확인용 (tools/item_sheet.gd): 숫자를 넣으면 신호의 나이 (ms) 를 그 값으로 고정 (안 끝남)
var _seen = null # 앞 스냅샷의 아이템 (M.seen_of) — null 이면 아직 본 적 없음
var _seen_meta: Array = [] # 그 스냅샷의 M.meta_of
var _seen_st = null # 그 스냅샷 (같은 스냅샷이면 다시 안 견줌)


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
	var b: Dictionary = IL.SIGNAL.born
	var look := {"core": b.core, "color": int(C.GAME_LIGHT_ITEM), "core_color": 0xffffff}
	var pm: StandardMaterial3D = EventFx.material(int(IL.SIGNAL.order))
	_fill(pillars, EventFx.strip_mesh(EventFx.two_tier(look, float(b.alpha), float(b.core_alpha)), b.prof), pm, true)
	add_child(pillars)


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
	_track(st, list, now_ms)
	if list.is_empty() and pl.is_empty() and sigs.is_empty() and not (rings.visible or projs.visible or pillars.visible):
		return # 아이템·투사체·신호가 없고 이미 다 숨겼으면 할 일 없음 (대부분의 프레임)
	var turn := Basis(Vector3.UP, spin)
	for g in M.groups(list):
		var idx: Array = g[1]
		var mm := _count(models[g[0]], idx.size())
		for k in idx.size():
			var i: int = idx[k]
			mm.set_instance_transform(k, Transform3D(turn, Co.gpos(M.item_pos(list[i], i, now_ms))))
	var cm := _count(casters, list.size())
	var sig_rows := _signal_rows(now_ms)
	var rm := _count(rings, list.size() + sig_rows.size())
	for i in list.size():
		cm.set_instance_transform(i, Transform3D(turn, Co.gpos(M.item_pos(list[i], i, now_ms))))
		var row := M.ring_row(list[i])
		rm.set_instance_transform(i, FR.xform(row))
		rm.set_instance_color(i, row[4])
	for j in sig_rows.size(): # 신호 고리는 받침 고리 뒤에 (같은 묶음)
		rm.set_instance_transform(list.size() + j, FR.xform(sig_rows[j]))
		rm.set_instance_color(list.size() + j, sig_rows[j][4])
	var pm := _count(projs, pl.size())
	var pturn := Basis(Vector3.UP, spin * IL.PROJ_SPIN)
	for i in pl.size():
		pm.set_instance_transform(i, Transform3D(pturn, Co.gxyz(pl[i].x, pl[i].y, pl[i].z)))


# ---- c10-fix F3 나옴·사라짐 신호 ----

# 스냅샷이 바뀔 때마다 아이템을 앞 스냅샷과 견줘 신호를 더함
func _track(st: Dictionary, list: Array, now_ms: float) -> void:
	if is_same(st, _seen_st):
		return
	_seen_st = st
	var meta := M.meta_of(st)
	var cur := M.seen_of(list)
	if _seen != null and M.signal_ok(_seen_meta, meta, float(IL.SIGNAL.gap_ms)):
		var d := M.item_diff(_seen, cur, int(IL.SIGNAL.born_max))
		for row in d.born:
			add_signal("born", row, now_ms)
		for row in d.gone:
			add_signal("gone", row, now_ms)
	elif _seen == null or not M.signal_ok(_seen_meta, meta, INF):
		sigs.clear() # 판이 바뀜·연습: 남은 신호도 지움 (시각만 뛴 것이면 그대로 둠)
	_seen = cur
	_seen_meta = meta


# 신호 하나 더함 (row = [칸 x, 칸 y, 높이 z, 종류]). 상한을 넘으면 가장 오래된 것을 버림
func add_signal(kind: String, row: Array, now_ms: float) -> void:
	sigs.append({"kind": kind, "x": int(row[0]), "y": int(row[1]), "z": float(row[2]), "type": str(row[3]), "t0": now_ms})
	while sigs.size() > int(IL.SIGNAL.max):
		sigs.pop_front()


# 끝난 신호를 지우고, 빛 기둥 묶음을 채우고, 신호 고리 줄 ([x, y, z, 반지름, 색] — 받침 고리 묶음에 얹을 것) 을 돌려줌
func _signal_rows(now_ms: float) -> Array:
	var rows := []
	if sigs.is_empty():
		if pillars.visible:
			_count(pillars, 0)
		return rows
	var S: Dictionary = IL.SIGNAL
	var yellow := Co.color(C.GAME_LIGHT_ITEM)
	var cam: Dictionary = CellLod.camera_of(self)
	var draw_pillar: bool = not G3.low and not cam.is_empty() # 그래픽 낮춤이면 고리만
	var posts := [] # [Transform3D, 인스턴스 색 (알파 포함)]
	for i in range(sigs.size() - 1, -1, -1):
		var g: Dictionary = sigs[i]
		var age: float = float(hold_sig) if hold_sig != null else now_ms - float(g.t0)
		if age >= float(S[g.kind].ms) or age < 0.0:
			sigs.remove_at(i)
			continue
		var h := float(S[g.kind].h)
		var beam := Color.WHITE # 빛 줄 인스턴스 색 (메시의 노랑·흰 심에 곱함)
		if g.kind == "born":
			var at: Array = M.born_at(age, S.born)
			rows.append(M.signal_ring_row(g, float(at[1]), Color(yellow, float(S.born.ring_alpha) * float(at[2])), float(S.lift)))
			beam.a = float(at[0])
		else:
			var at: Array = M.gone_at(age, S.gone)
			var gc := Color(M.gone_color(str(g.type), float(S.gone.mix)), float(S.gone.alpha) * float(at[1]))
			rows.append(M.signal_ring_row(g, float(at[0]), gc, float(S.lift)))
			rows.append(M.signal_ring_row(g, float(at[0]) * float(S.gone.ring2), gc, float(S.lift))) # 겹 물결
			beam = Color(M.gone_color(str(g.type), float(S.gone.mix)).lerp(Color.WHITE, 0.5), float(at[2]))
		if draw_pillar:
			var base := Co.gxyz(g.x + 0.5, g.y + 0.5, g.z)
			var c := base + Vector3.UP * (h * 0.5)
			var cp: Vector3 = cam.pos
			beam.a *= EM.near_k(EM.seg_dist(cp, base, base + Vector3.UP * h), EK.EVENT_FX.common) # 눈앞 빛 줄은 안 그림 (화면을 덮는 번쩍 금지)
			if beam.a > 0.0:
				posts.append([EM.streak_xform(c, Vector3.UP, h, EM.wide(float(S[g.kind].width), cp.distance_to(c), float(EK.EVENT_FX.common.thin)), cp), beam])
	var pm := _count(pillars, posts.size())
	for i in posts.size():
		pm.set_instance_transform(i, posts[i][0])
		pm.set_instance_color(i, posts[i][1])
	return rows

