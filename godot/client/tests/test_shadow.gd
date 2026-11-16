# W32 해 그림자 비용 줄이기: 판 몸 그림자 전용 저폴리 (chars/ext_shadow.gd), 먼 몸·시야 밖 몸 그림자 끄기 (world/shadow_calc.gd · chars/body.gd set_shadow_off),
# 떨어지는·쌓인 블록 칸 그림자 상자 (world/pieces_view.gd · grid_view.gd), 그림자 거리 (shadow_calc.reach_next)
extends RefCounted

const WC := preload("res://world/world_config.gd")
const Gate := preload("res://core/entry_gate.gd")
const SC := preload("res://world/shadow_calc.gd")
const Body := preload("res://chars/body.gd")
const ExtShadow := preload("res://chars/ext_shadow.gd")
const PV := preload("res://world/pieces_view.gd")
const G3 := preload("res://shaders/g3.gd")
const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const LR := preload("res://world/landing_rim.gd")
const PT := preload("res://world/piece_tune.gd")
const MF := preload("res://core/mat_first.gd")
const WS := preload("res://world/warm_scan.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 몸이 던지는 그림자의 삼각형 수 (그림자를 던지는 MeshInstance3D 의 첫 표면 색인 / 3) + 던지는 메시 수
func _shadow_tris(b: Node) -> Array:
	var tris := 0
	var n := 0
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible or m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		n += 1
		for s in m.mesh.get_surface_count():
			var k: int = m.mesh.surface_get_array_index_len(s)
			tris += (k if k > 0 else m.mesh.surface_get_array_len(s)) / 3
	return [tris, n]


# 화면 (색) 패스에 그려지는 메시 수: 보이고 그림자 전용이 아닌 것
func _drawn(b: Node) -> int:
	var n := 0
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh != null and m.visible and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			n += 1
	return n


func _body(ch: String, third := true):
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), third)
	Body.use_ext = was
	return b


func test_far_off_hysteresis() -> void:
	var far: float = WC.SHADOW.far
	var h: float = WC.SHADOW.hyst
	check(not SC.far_off(8.0, 70.0, false) and not SC.far_off(far + h - 0.1, 70.0, false), "가까우면 그림자 켬")
	check(SC.far_off(far + h + 0.1, 70.0, false), "far + hyst 넘으면 끔")
	check(SC.far_off(far, 70.0, true) and not SC.far_off(far - h - 0.1, 70.0, true), "끈 몸은 far − hyst 안으로 와야 다시 켬")
	check(not SC.far_off(500.0, 70.0, true, true), "내 몸은 늘 켬")
	check(SC.far_off(far + h + 1.0, 70.0, false) and not SC.far_off(far + h + 1.0, 30.0, false), "시야각 반영 (좁게 보면 같은 거리가 가까움)")
	check(far > float(WC.OUTLINE_FAR.gone) and far > float(WC.POSE_LOD.far2), "그림자 끄는 거리는 외곽선 떼는 거리·몸 자세 둘째 단보다 멀다")
	var st := false
	var flips := 0
	for i in 200:
		var d: float = far + sin(i * 0.7) * 0.5
		var ns := SC.far_off(d, 70.0, st)
		if ns != st:
			flips += 1
		st = ns
	check(flips == 0, "경계 근처에서 켰다 껐다 안 함 (%d번)" % flips)


func test_visible_or_shadow() -> void:
	# 시야 = x ∈ [−10, 10], z ∈ [−10, 10] 상자 (면 법선이 바깥), 해는 +x 쪽으로 기운 곳 (그림자는 −x 로 눕는다)
	var planes := [Plane(Vector3(1, 0, 0), 10.0), Plane(Vector3(-1, 0, 0), 10.0), Plane(Vector3(0, 0, 1), 10.0), Plane(Vector3(0, 0, -1), 10.0)]
	var to_sun := Vector3(0.6, 0.8, 0.0).normalized()
	check(SC.visible_or_shadow(planes, Vector3(0, 1, 0), to_sun, 1.0), "시야 안 몸")
	check(not SC.visible_or_shadow(planes, Vector3(30, 1, 0), to_sun, 1.0), "몸도 그림자 자리도 시야 밖이면 끔")
	var s := SC.shadow_spot(Vector3(12, 4, 0), to_sun)
	check(s.x < 12.0 and absf(s.y) < 0.001, "그림자는 해 반대쪽 바닥에 눕는다 (%s)" % str(s))
	check(SC.visible_or_shadow(planes, Vector3(12.5, 4, 0), to_sun, 0.5) == (SC.shadow_spot(Vector3(12.5, 4, 0), to_sun).x < 10.5), "몸은 밖이어도 그림자가 시야 안으로 눕으면 켬")
	check(SC.visible_or_shadow(planes, Vector3(30, 20, 0), Vector3(0.9, 0.2, 0).normalized(), 1.0) == false, "해가 낮아도 그림자 길이를 묶어 판 밖으로 날지 않음")
	check(SC.visible_or_shadow([], Vector3(99, 0, 0), to_sun, 1.0), "시야 면이 없으면 (카메라 없음) 끄지 않음")


func test_reach_by_camera() -> void:
	var full: float = G3.shadow_full(19.0, 19.0)
	var mid: float = SC.reach(Vector3(9.5, 9.5, 5.0), 19.0, 19.0, full)
	var corner: float = SC.reach(Vector3(-4.0, -4.0, 8.0), 19.0, 19.0, full)
	check(mid <= full and corner <= full, "판 크기 값 (%.1f) 을 안 넘음: 가운데 %.1f · 구석 %.1f" % [full, mid, corner])
	check(mid < corner, "카메라가 가운데면 구석 모퉁이보다 짧다 (%.1f < %.1f)" % [mid, corner])
	check(mid >= minf(float(WC.SHADOW.reach_min), full), "reach_min 아래로는 안 줄임")
	check(fmod(mid, float(WC.SHADOW.reach_step)) < 0.001 or mid == full or mid == float(WC.SHADOW.reach_min), "step 단위")
	# 판 가장 먼 모퉁이는 늘 그림자 안에 듦
	var far_d: float = Vector2(9.5, 9.5).length()
	check(mid >= sqrt(far_d * far_d + 25.0), "가장 먼 모퉁이 (%.1f) 까지 덮음" % far_d)
	# 히스테리시스: 늘면 곧바로, 줄면 한 단계 반 넘게 여유일 때만
	var cur: float = corner
	var cam := Vector3(9.5, 9.5, 5.0)
	check(SC.reach_next(-1.0, cam, 19.0, 19.0, full) == mid, "처음엔 그대로 정함")
	check(SC.reach_next(mid, Vector3(-4.0, -4.0, 8.0), 19.0, 19.0, full) == corner, "늘려야 하면 곧바로")
	var step := float(WC.SHADOW.reach_step)
	check(SC.reach_next(mid + step, cam, 19.0, 19.0, full) == mid + step or mid + step > full, "한 단계 줄일 여유는 아직 안 줄임 (떨림 방지)")
	check(SC.reach_next(mid + step * 2.0, cam, 19.0, 19.0, full) == mid or mid + step * 2.0 > full, "두 단계 여유면 줄임")
	check(cur > 0.0, "")


func test_ext_shadow_caster_lod() -> void:
	var was: bool = WC.shadow_opt
	var Gfx = load("res://world/gfx.gd") # 판 몸 LOD 는 화질 (Gfx.plan.level) 을 따름 — 앞선 테스트가 정한 값에 흔들리지 않게 높음으로
	var plan_was: Dictionary = Gfx.plan
	Gfx.plan = {"level": "high"}
	for ch in ["ninja", "tank", "hook"]:
		WC.shadow_opt = false
		var b0 = _body(ch)
		var base: Array = _shadow_tris(b0)
		b0.free()
		WC.shadow_opt = true
		var b = _body(ch)
		var now: Array = _shadow_tris(b)
		var only := 0
		var vis_cast := 0
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				only += 1
				check(m.material_override == null and m.skin != null and not m.skeleton.is_empty(), "%s: 그림자 전용 메시는 재질 없이 스킨 몸에 붙음" % ch)
			elif m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and m.skin != null:
				vis_cast += 1
		check(only >= 1, "%s: 그림자 전용 메시 있음 (%d)" % [ch, only])
		check(vis_cast == 0, "%s: 보이는 스킨 메시는 그림자 끔 (%d)" % [ch, vis_cast])
		check(int(now[0]) < int(base[0]), "%s: 그림자 삼각형 줄음 %d → %d" % [ch, base[0], now[0]])
		check(int(now[0]) <= 3200 + 1500, "%s: 가장 낮은 LOD (3천) + 소품 정도 (%d)" % [ch, now[0]])
		b.free()
	# 화질 낮음이면 보이는 LOD 가 이미 가장 낮아 저폴리 그림자 메시를 따로 안 둠
	Gfx.plan = {"level": "low"}
	var bl = _body("ninja")
	var low_only := 0
	for mi in bl.find_children("*", "MeshInstance3D", true, false):
		low_only += 1 if (mi as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY else 0
	check(low_only == 0, "낮음: 그림자 전용 메시 없음 (%d)" % low_only)
	bl.free()
	Gfx.plan = plan_was
	WC.shadow_opt = was


func test_ext_shadow_caster_rules() -> void:
	var cfg := {"lods": {"stage": "x_lod0", "high": "x_lod1", "medium": "x_lod2", "low": "x_lod3"}}
	check(ExtShadow.caster_node(cfg, "x_lod1", true, false) == "x_lod3", "높음: 가장 낮은 LOD 가 그림자")
	check(ExtShadow.caster_node(cfg, "x_lod2", true, false) == "x_lod3", "보통도")
	check(ExtShadow.caster_node(cfg, "x_lod3", true, false) == "", "이미 가장 낮으면 안 함")
	check(ExtShadow.caster_node(cfg, "x_lod1", false, false) == "", "1인칭 쌍둥이는 그림자 없음")
	check(ExtShadow.caster_node(cfg, "x_lod0", true, true) == "", "대기실 큰 캐릭터·초상은 그대로")
	check(ExtShadow.caster_node({}, "", true, false) == "" and ExtShadow.caster_node({"lods": {}}, "", true, false) == "", "LOD 없는 모델은 그대로")
	var was: bool = WC.shadow_opt
	WC.shadow_opt = false
	check(ExtShadow.caster_node(cfg, "x_lod1", true, false) == "", "--no-shadow-opt 면 안 함")
	WC.shadow_opt = was


func test_body_shadow_off_restores() -> void:
	for ch in ["ninja", "bard"]:
		var b = _body(ch) if ch == "ninja" else Body.new()
		if ch != "ninja":
			b.build(ch, Color(0.2, 0.5, 1.0), true)
		var base: Array = _shadow_tris(b)
		check(int(base[1]) > 0, "%s: 그림자 던지는 메시 있음" % ch)
		var drawn0 := _drawn(b)
		b.set_shadow_off(true)
		check(_drawn(b) == drawn0, "%s: 그림자를 꺼도 화면에 그려지는 메시 수 그대로 (%d → %d) — 그림자 전용 메시가 화면에 나오면 안 됨" % [ch, drawn0, _drawn(b)])
		var off: Array = _shadow_tris(b)
		check(int(off[1]) == 0 and b.shadow_off(), "%s: 끄면 아무것도 안 던짐 (%s)" % [ch, str(off)])
		b.set_shadow_off(true)
		b.set_shadow_off(false)
		var on: Array = _shadow_tris(b)
		check(on == base and not b.shadow_off(), "%s: 켜면 원래 그대로 (그림자 전용 메시도 전용 그대로) %s vs %s" % [ch, str(on), str(base)])
		b.free()


func test_piece_cells_shadow_proxy() -> void:
	var was: bool = WC.shadow_opt
	WC.shadow_opt = true
	var box := BoxMesh.new()
	check(not PV.proxy_wanted(box), "상자 칸 (12 삼각형) 은 그대로 던짐")
	var mesh: Mesh = G3.piece_mesh("meadow", false)
	check(PV.mesh_tris(mesh) >= 100 and PV.proxy_wanted(mesh), "테마 칸 (%d 삼각형) 은 상자로 대신" % PV.mesh_tris(mesh))
	var pv = PV.new()
	pv._ready()
	pv.set_look(mesh, [StandardMaterial3D.new(), StandardMaterial3D.new()], {})
	check(pv.proxy_on and pv.cells_mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "보이는 칸은 그림자 끔")
	check(pv.caster_mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "상자는 그림자만")
	var st := {"pieces": [{"shape": "T", "cells": [[1, 1, 5], [2, 1, 5], [3, 1, 5]], "sky": false}]}
	pv.update(st, 1, {}, 0.0)
	var cm: MultiMesh = pv.caster_mmi.multimesh
	check(cm.visible_instance_count == 3 and pv.cells_mmi.multimesh.visible_instance_count == 3, "칸 3개 = 상자 3개")
	for i in 3:
		check(cm.get_instance_transform(i).origin.is_equal_approx(pv.cells_mmi.multimesh.get_instance_transform(i).origin), "상자 자리 = 보이는 칸 자리 (%d)" % i)
	pv.set_look(box, [StandardMaterial3D.new(), StandardMaterial3D.new()], {})
	check(not pv.proxy_on and pv.cells_mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and cm.visible_instance_count == 0, "상자 칸이면 보이는 칸이 그림자 (상자는 쉼)")
	WC.shadow_opt = false
	pv.set_look(mesh, [StandardMaterial3D.new(), StandardMaterial3D.new()], {})
	check(not pv.proxy_on, "--no-shadow-opt 면 예전 그대로")
	pv.free()
	WC.shadow_opt = was


func test_grid_cells_shadow_proxy() -> void:
	var was: bool = WC.shadow_opt
	WC.shadow_opt = true
	var GV = load("res://world/grid_view.gd")
	var gv = GV.new()
	gv._ready()
	var mesh: Mesh = G3.piece_mesh("castle", false)
	gv.set_piece_look(mesh, StandardMaterial3D.new(), {})
	check(gv.proxy_on and gv.piece_mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "쌓인 모양 칸: 보이는 칸 그림자 끔")
	var w := 4
	var grid := PackedByteArray()
	grid.resize(w * w * 3)
	grid[0] = 5
	grid[5] = 5
	grid[20] = 6
	gv.rebuild(grid, w, w, 3)
	check(gv.piece_caster.multimesh.instance_count == gv.piece_mmi.multimesh.instance_count and gv.piece_mmi.multimesh.instance_count == 3, "모양 칸 3개 = 상자 3개 (%d)" % gv.piece_caster.multimesh.instance_count)
	for k in 3:
		check(gv.piece_caster.multimesh.get_instance_transform(k).origin.is_equal_approx(gv.piece_mmi.multimesh.get_instance_transform(k).origin), "상자 자리 = 칸 자리 (%d)" % k)
	gv.set_piece_look(BoxMesh.new(), StandardMaterial3D.new(), {})
	check(not gv.proxy_on and gv.piece_mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "상자 칸이면 그대로")
	gv.free()
	WC.shadow_opt = was


# 몸 만들기 분산: 한 프레임에 WC.BODY_BUILDS_PER_FRAME 개까지 (내 몸은 따로 바로), 나머지는 다음 프레임에 — 방 입장·봇 8명이 한 프레임에 몰리지 않게
func test_body_builds_spread_over_frames() -> void:
	var Bodies = load("res://world/bodies.gd")
	var bd = Bodies.new()
	bd._ready()
	bd.chars_script = null # 상자 몸 (만들기 비용 상관없이 몇 개 만들었나만)
	var cap: int = WC.BODY_BUILDS_PER_FRAME_SPLIT if Gate.on() and not Gate.no_split("body") else WC.BODY_BUILDS_PER_FRAME # W45: 붙이기를 나눈 때는 한 프레임 새 몸 하나
	var ps := []
	for i in 8:
		ps.append({"id": i + 1, "char": "tank", "alive": true, "yaw": 0.0, "x": float(i), "y": 0.0, "z": 0.0, "slot": i, "color": i})
	var st := {"players": ps, "teamMode": false}
	bd.update(st, 5, false, false, 0.0) # 내 id 5
	check(bd.nodes.size() == cap + 1 and bd.nodes.has(5), "첫 프레임: 내 몸 + %d 개 (얻음 %d)" % [cap, bd.nodes.size()])
	check(bd.shown.size() == 8, "만들지 못한 몸도 자리는 알려 줌 (카메라·하늘 도우미) — %d" % bd.shown.size())
	var frames := 1
	var last: int = bd.nodes.size()
	while bd.nodes.size() < 8 and frames < 10:
		bd.update(st, 5, false, false, frames * 16.0)
		frames += 1
		check(bd.nodes.size() - last <= cap, "프레임마다 최대 %d 개씩 (%d → %d)" % [cap, last, bd.nodes.size()])
		last = bd.nodes.size()
	check(bd.nodes.size() == 8 and frames <= 1 + int(ceil((7 - cap) / float(cap))), "8명이 %d 프레임 안에 다 나옴 (%d)" % [1 + int(ceil((7 - cap) / float(cap))), frames])
	# 이미 있는 몸은 안 건드림: 다음 프레임에 새로 안 만듦
	var ids: Array = bd.nodes.keys()
	var roots := []
	for id in ids:
		roots.append(bd.nodes[id].root)
	bd.update(st, 5, false, false, 999.0)
	var same := true
	for i in ids.size():
		same = same and bd.nodes[ids[i]].root == roots[i]
	check(same, "다 나온 뒤엔 그대로")
	# 캐릭터가 바뀌면 (몸 새로) 그것도 프레임당 상한 안
	var st2 := st.duplicate(true)
	for p in st2.players:
		p["char"] = "ninja"
	bd.update(st2, 5, false, false, 1000.0)
	var rebuilt := 0
	for id in ids:
		rebuilt += 1 if bd.nodes[id].char == "ninja" else 0
	check(rebuilt <= cap + 1, "캐릭터 일괄 변경도 한 프레임에 최대 %d + 내 몸 (얻음 %d)" % [cap, rebuilt])
	for i in 6:
		bd.update(st2, 5, false, false, 1010.0 + i)
	var all_new := true
	for id in ids:
		all_new = all_new and bd.nodes[id].char == "ninja"
	check(all_new, "몇 프레임 뒤엔 다 바뀜")
	bd.free()


# ---- C7 (겉모습 2 — 바닥 읽힘): 블록 면 색 (world/piece_tune.gd) · 착지 예고 테 (world/landing_rim.gd)

# 조각 바깥 윤곽만: 이웃 칸이 없는 변만 고름 (칸 사이 안쪽 선 없음)
func test_c7_outer_edges() -> void:
	var shapes := {
		"I": [[[0, 0], [1, 0], [2, 0], [3, 0]], 10],
		"O": [[[0, 0], [1, 0], [0, 1], [1, 1]], 8],
		"T": [[[0, 0], [1, 0], [2, 0], [1, 1]], 10],
		"S": [[[1, 0], [2, 0], [0, 1], [1, 1]], 10],
		"한 칸": [[[4, 7]], 4],
	}
	for k in shapes:
		var cells: Array = shapes[k][0]
		var e: Array = LR.outer_edges(cells)
		check(e.size() == shapes[k][1], "%s 바깥 변 %d (얻음 %d)" % [k, shapes[k][1], e.size()])
		var have := {}
		for c in cells:
			have[Vector2i(c[0], c[1])] = true
		for x in e:
			var d: Array = LR.DIRS[x[2]]
			check(have.has(Vector2i(x[0], x[1])) and not have.has(Vector2i(x[0] + d[0], x[1] + d[1])), "%s 변 %s 은 조각 칸의 바깥쪽" % [k, str(x)])
	check(LR.outer_edges([[2.0, 3.0, 9.0], [2.0, 3.0, 10.0]]).size() == 4, "같은 x·y 로 겹친 칸은 한 칸 (스냅샷 값은 실수)")
	# 띠 조각: 변마다 폭 w × 길이 1, 안으로 꺾이는 모서리 (T 2곳·S 2곳·I·O 0곳) 는 w × w 로 메움 — 모두 제 조각 칸 안
	var w: float = LR.RIM.w
	for k in ["I", "O", "T", "S"]:
		var cells: Array = shapes[k][0]
		var st: Array = LR.strips(cells)
		var corners := 0
		for s in st:
			corners += 1 if is_equal_approx(s[2], w) and is_equal_approx(s[3], w) else 0
			check((is_equal_approx(s[2], w) or is_equal_approx(s[2], 1.0)) and (is_equal_approx(s[3], w) or is_equal_approx(s[3], 1.0)), "%s 띠 크기 %s" % [k, str(s)])
			var inside := false
			for c in cells:
				inside = inside or (s[0] - s[2] / 2.0 >= c[0] - 1e-6 and s[0] + s[2] / 2.0 <= c[0] + 1 + 1e-6 and s[1] - s[3] / 2.0 >= c[1] - 1e-6 and s[1] + s[3] / 2.0 <= c[1] + 1 + 1e-6)
			check(inside, "%s 띠 %s 는 조각 칸 안쪽" % [k, str(s)])
		check(st.size() == shapes[k][1] + corners and corners == {"I": 0, "O": 0, "T": 2, "S": 2}[k], "%s 띠 %d = 변 %d + 모서리 %d" % [k, st.size(), shapes[k][1], corners])
	var xf: Transform3D = LR.strip_xf([1.5, 2.0 + w / 2.0, 1.0, w], 3.0)
	check(xf.origin.is_equal_approx(Co.gxyz(1.5, 2.0 + w / 2.0, 3.0 + WC.SHADOW_LIFT + LR.RIM.lift)) and xf.basis.get_scale().is_equal_approx(Vector3(1.0, 1.0, w)), "띠 자리: 그림자 칸보다 조금 위, 납작하게")


# 판에서: 그림자 칸 옆 띠 MultiMesh 하나 — show_shadow 와 같은 조건, 재질은 미리 그리기 표 안. (헤드리스 렌더 서버는 인스턴스 값을 안 돌려줌 → 색·자리는 LR.items 로, 판에선 띠 수로 확인)
func test_c7_rim_in_pieces_view() -> void:
	var pv = PV.new()
	pv._ready()
	check(WS.STD_KEYS.map(func(k): return MF.mat_key(WS.std_material(k))).has(MF.mat_key(pv.rim_mmi.material_override)), "테 재질 모양이 표준 표 안 (판 중 컴파일 없음): " + MF.mat_key(pv.rim_mmi.material_override))
	check(MF.mat_key(pv.rim_mmi.material_override) == MF.mat_key(pv.shadow_mmi.material_override), "그림자와 같은 재질 모양")
	check(pv.rim_mmi.material_override.render_priority > pv.shadow_mmi.material_override.render_priority, "채움 위에 그림")
	check(pv.rim_mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and pv.rim_mmi.multimesh.mesh == pv.shadow_mmi.multimesh.mesh, "같은 1×1 판, 그림자 안 던짐")
	var t_shadow := [[1, 1], [2, 1], [3, 1], [2, 2]]
	var st := {"pieces": [
		{"shape": "T", "cells": [[1, 1, 5], [2, 1, 5], [3, 1, 5], [2, 2, 5]], "shadow": t_shadow, "landZ": 0.0, "shadowVisible": true, "eta": 500.0, "sky": false},
		{"shape": "O", "cells": [[6, 6, 9], [7, 6, 9]], "shadow": [[6, 6], [7, 6]], "landZ": 1.0, "shadowVisible": false, "eta": 9000.0, "sky": false},
	]}
	pv.set_floor_luma(0.26)
	pv.update(st, 1, {}, 0.0)
	var rm: MultiMesh = pv.rim_mmi.multimesh
	var want: int = LR.strips(t_shadow).size()
	check(pv.shadow_mmi.multimesh.visible_instance_count == 4 and rm.visible_instance_count == want and want == 12, "보이는 그림자만 테 (칸 4 → 띠 %d, 얻음 %d)" % [want, rm.visible_instance_count])
	check(rm.instance_count >= want and pv.rim_danger == 0, "띠 자리 넉넉 (%d), 위험 띠 없음" % rm.instance_count)
	var w0: int = pv.writes
	pv.update(st, 1, {}, 0.0)
	check(pv.writes == w0, "같은 스냅샷이면 다시 안 씀")
	pv.set_floor_luma(0.9)
	pv.update(st, 1, {}, 0.0)
	check(pv.writes == w0 + 1 and rm.visible_instance_count == want, "바닥 밝기가 바뀌면 (테마 바뀜) 테 색을 다시 씀")
	# 내 조종 블록: 서버가 안 보인다고 한 그림자여도 그림 (채움과 같은 조건)
	var mine := {"pieces": [{"shape": "O", "cells": [[6, 6, 9]], "shadow": [[6, 6]], "landZ": 1.0, "shadowVisible": false, "phase": "control", "controller": 1, "fits": false, "sky": false}]}
	pv.update(mine, 1, {}, 0.0)
	check(rm.visible_instance_count == 4 and pv.shadow_mmi.multimesh.visible_instance_count == 1, "내 블록 한 칸 → 띠 4")
	pv.update(mine.duplicate(true), 2, {}, 0.0)
	check(rm.visible_instance_count == 0 and pv.shadow_mmi.multimesh.visible_instance_count == 0, "남이 조종하는 안 보이는 그림자는 테도 없음")
	# 내 머리 위 위험 칸: T 가운데 칸 (2,1) 위에 서 있음 → 그 칸의 띠 (아래 변 1 + 꺾인 모서리 2) 만 위험 색
	pv.update(st.duplicate(true), 1, {"alive": true, "danger": 1, "x": 2.5, "y": 1.5}, 0.0)
	check(rm.visible_instance_count == want and pv.rim_danger == 3, "내 머리 위 칸의 띠만 위험 색 (%d / %d)" % [pv.rim_danger, rm.visible_instance_count])
	pv.update({"pieces": []}, 1, {}, 0.0)
	check(rm.visible_instance_count == 0, "그림자가 없으면 테도 없음")
	pv.free()
	# 띠 값 (자리·색): 보통은 바닥 밝기로 크림/잉크, 위험 칸의 띠만 위험 색
	for luma in [0.26, 0.9]:
		var it: Array = LR.items(t_shadow, 2.0, "normal", {Vector2i(2, 1): true}, luma)
		var red := 0
		for x in it:
			var c: Color = x[1]
			var at: Vector3 = (x[0] as Transform3D).origin
			check(is_equal_approx(at.y, 2.0 + WC.SHADOW_LIFT + LR.RIM.lift), "테 높이 = 착지 높이 + 그림자 띄움 + 조금")
			var hot: bool = at.x > 2.0 and at.x < 3.0 and -at.z > 1.0 and -at.z < 2.0
			check(c.is_equal_approx(LR.rim_color("danger" if hot else "normal", luma)), "띠 색 (바닥 밝기 %.2f, 위험 칸 %s)" % [luma, hot])
			red += 1 if hot else 0
		check(it.size() == 12 and red == 3, "띠 12 가운데 위험 3 (%d·%d)" % [it.size(), red])
	check(LR.items([[6, 6]], 1.0, "fit", {}, 0.9)[0][1].is_equal_approx(LR.rim_color("fit", 0.9)) and LR.items([[6, 6]], 1.0, "nofit", {}, 0.3)[0][1].is_equal_approx(LR.rim_color("nofit", 0.3)), "내 블록 테 색")


func _face_mid(style: String) -> float:
	var img: Image = (load("res://assets/pieces/%s.png" % style) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var n := 0
	for y in range(h / 4, h * 3 / 4): # 면 가운데 절반
		for x in range(w / 4, w * 3 / 4):
			sum += img.get_pixel(x, y).srgb_to_linear().get_luminance()
			n += 1
	return sum / n


# 면의 주색이 조각 색: 면 그림 가운데 밝기 (선형) 에 faceLift 를 먹인 값이 0.30 이상 — 어두운 그림 (화산 흑요석) 만 올림
func test_c7_face_luma_floor() -> void:
	for id in C.WORLD_THEMES:
		var m := _face_mid(str(G3.piece_spec(id).style))
		var lift: float = PT.face_lift(id)
		check(PT.lifted(m, lift) >= 0.30, "%s 면 가운데 밝기 %.3f (그림 %.3f, faceLift %.2f) ≥ 0.30" % [id, PT.lifted(m, lift), m, lift])
		check(lift == 0.0 or id == "volcano", "%s: 화산 말고는 faceLift 0 (%.2f)" % [id, lift])
	check(_face_mid("obsidian") < 0.30 and PT.face_lift("volcano") >= 0.25 and PT.face_lift("volcano") <= 0.4, "화산은 그림이 어두워 올림 (0.25~0.4)")
	check(is_equal_approx(PT.lifted(0.2, 0.0), 0.2) and is_equal_approx(PT.lifted(0.2, 1.0), 1.0), "lifted = mix(m, 1, lift)")


func _luma(v) -> float:
	return Co.color(v).get_luminance()


# 테가 어느 바닥에서든 읽힘: 7 테마 모두 보통 테 색과 바닥 두 색 (floor.a·b) 의 sRGB 밝기 차 ≥ 0.25
func test_c7_rim_contrast() -> void:
	check(C.WORLD_THEMES.size() == 7, "테마 7개")
	for id in C.WORLD_THEMES:
		var t: Dictionary = C.WORLD_THEMES[id]
		var luma: float = LR.floor_luma(t)
		check(is_equal_approx(luma, (_luma(t.floor.a) + _luma(t.floor.b)) / 2.0), "%s 바닥 밝기 = floor.a·b 평균" % id)
		var rim: Color = LR.rim_color("normal", luma)
		for k in ["a", "b"]:
			check(absf(rim.get_luminance() - _luma(t.floor[k])) >= 0.25, "%s 보통 테 %.2f vs 바닥 %s %.2f" % [id, rim.get_luminance(), k, _luma(t.floor[k])])
		var dark: bool = id in ["volcano", "crystal", "mushroom"]
		check((luma < LR.RIM.luma_split) == dark and rim.is_equal_approx(Color(Co.color(LR.RIM.cream if dark else LR.RIM.ink), LR.RIM.alpha)), "%s: %s 바닥 → %s 테" % [id, "어두운" if dark else "밝은", "크림" if dark else "잉크"])
	check(LR.floor_luma({}) == _luma(C.TERRAIN_COLOR), "바닥 정의 없으면 기본 지형 색")


func _hue_gap(a: Color, b: Color) -> float:
	var d := absf(a.h - b.h) * 360.0
	return minf(d, 360.0 - d)


# 테를 둘러도 종류가 구분됨: 보통·내 것 (놓을 수 있음·없음)·위험 색이 서로 다르고, 보통과 위험은 색상 20° 이상 또는 밝기 0.25 이상 차이
func test_c7_rim_keeps_kind() -> void:
	for id in C.WORLD_THEMES:
		var luma: float = LR.floor_luma(C.WORLD_THEMES[id])
		var cols := {}
		for k in LR.KINDS:
			cols[k] = LR.rim_color(k, luma)
			check(is_equal_approx(cols[k].a, LR.RIM.alpha), "%s %s 알파" % [id, k])
		for i in LR.KINDS.size():
			for j in range(i + 1, LR.KINDS.size()):
				check(not cols[LR.KINDS[i]].is_equal_approx(cols[LR.KINDS[j]]), "%s: %s·%s 테 색이 다름" % [id, LR.KINDS[i], LR.KINDS[j]])
		var n: Color = cols.normal
		var d: Color = cols.danger
		check(_hue_gap(n, d) >= 20.0 or absf(n.get_luminance() - d.get_luminance()) >= 0.25, "%s 보통 vs 위험: 색상 %.0f° · 밝기 %.2f" % [id, _hue_gap(n, d), absf(n.get_luminance() - d.get_luminance())])
		check(_hue_gap(n, cols.nofit) >= 20.0 or absf(n.get_luminance() - cols.nofit.get_luminance()) >= 0.25, "%s 보통 vs 못 놓음" % id)
	# 내 것·위험은 그림자 채움과 같은 색에서 나옴: 밝은 바닥은 그대로, 어두운 바닥은 흰 쪽으로
	check(LR.rim_color("fit", 0.9).is_equal_approx(Color(Co.color(WC.PREVIEW_COLOR[0]), LR.RIM.alpha)) and LR.rim_color("danger", 0.9).is_equal_approx(Color(Co.color(WC.DANGER_SHADOW[0]), LR.RIM.alpha)), "밝은 바닥: 제 색 그대로")
	check(LR.rim_color("nofit", 0.2).is_equal_approx(Color(Co.color(WC.PREVIEW_COLOR[1]).lerp(Color.WHITE, LR.RIM.whiten), LR.RIM.alpha)), "어두운 바닥: 흰 쪽으로")


# 덧값 표는 faceLift·accentTint 뿐이고 uniform 으로만 들어감 — C.WORLD_THEMES (JS 정답) 는 그대로
func test_c7_piece_tune_keys() -> void:
	var before := var_to_str(C.WORLD_THEMES)
	for id in PT.PIECE_TUNE:
		check(C.WORLD_THEMES.has(id), "표의 테마 id %s" % id)
		for k in PT.PIECE_TUNE[id]:
			check(PT.KEYS.has(k), "%s: 표 키 %s 는 faceLift·accentTint 뿐" % [id, k])
	check(PT.KEYS == ["faceLift", "accentTint"], "키 둘")
	for low in [false, true]: # 낮춤 갈래도 같은 값 (G3.set_low 가 안 건드림)
		var vm: ShaderMaterial = G3.piece_material("volcano", low)
		check(is_equal_approx(vm.get_shader_parameter("face_lift"), PT.PIECE_TUNE.volcano.faceLift) and vm.get_shader_parameter("accent_tint") == Vector2.ZERO, "화산 칸 face_lift = 표 값 (낮춤 %s)" % low)
		var mm: ShaderMaterial = G3.piece_material("meadow", low)
		check(mm.get_shader_parameter("face_lift") == 0.0 and mm.get_shader_parameter("accent_tint") == Vector2.ZERO, "초원 칸은 0 (예전 그대로)")
		var jm: ShaderMaterial = G3.piece_material("mushroom", low, {"transparent": true})
		check(jm.get_shader_parameter("accent_tint").is_equal_approx(Vector2(0.0, 0.35)) and jm.get_shader_parameter("face_lift") == 0.0, "버섯 칸: 받침만 조각 색 쪽으로 (흰 점 0)")
	check(G3.piece_material(null).get_shader_parameter("face_lift") == 0.0, "테마 없는 장난감 블록도 0")
	var src := FileAccess.get_file_as_string("res://shaders/piece_common.gdshaderinc")
	check(src.contains("uniform float face_lift = 0.0;") and src.contains("uniform vec2 accent_tint = vec2(0.0);"), "셰이더 기본값 0")
	check(src.contains("smoothstep(0.6, 0.95, tex.r)"), "금 (crack) 은 그림 그대로 봄")
	check(var_to_str(C.WORLD_THEMES) == before and not C.WORLD_THEMES.volcano.piece.has("faceLift"), "C.WORLD_THEMES 그대로")

