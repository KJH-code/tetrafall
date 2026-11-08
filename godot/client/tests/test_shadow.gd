# W32 해 그림자 비용 줄이기: 판 몸 그림자 전용 저폴리 (chars/ext_shadow.gd), 먼 몸·시야 밖 몸 그림자 끄기 (world/shadow_calc.gd · chars/body.gd set_shadow_off),
# 떨어지는·쌓인 블록 칸 그림자 상자 (world/pieces_view.gd · grid_view.gd), 그림자 거리 (shadow_calc.reach_next)
extends RefCounted

const WC := preload("res://world/world_config.gd")
const SC := preload("res://world/shadow_calc.gd")
const Body := preload("res://chars/body.gd")
const ExtShadow := preload("res://chars/ext_shadow.gd")
const PV := preload("res://world/pieces_view.gd")
const G3 := preload("res://shaders/g3.gd")

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
	var cap: int = WC.BODY_BUILDS_PER_FRAME
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
