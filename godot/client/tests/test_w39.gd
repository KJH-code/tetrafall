# W39 최적화 5차: 새 모델 알베도 텍스처 지연 로드 (항목 2) · (뒤 항목들은 아래에 이어 붙임)
extends RefCounted

const Ext := preload("res://chars/external.gd")
const Chars := preload("res://chars/chars.gd")
const Gfx := preload("res://world/gfx.gd")
const Body := preload("res://chars/body.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _atlas(id: String, suf := "") -> String:
	return "res://assets/models/ext/%s_%s_atlas%s.jpg" % [id, id, suf]


func _body(id: String, level := "high", stage := false) -> Node3D:
	var was: Dictionary = Gfx.plan
	var was_e: bool = Body.use_ext
	Gfx.plan = {"level": level}
	Body.use_ext = true
	Ext.stage = stage
	var b := Chars.make_body(id, Color(0.8, 0.3, 0.3))
	Ext.stage = false
	Body.use_ext = was_e
	Gfx.plan = was
	return b


func _tex_id(body: Node3D) -> int:
	for pt in body.ext.parts:
		if pt.tex != null:
			return (pt.tex as Object).get_instance_id()
	return 0


# 모델 정보만 읽었을 땐 알베도 텍스처가 하나도 안 올라와 있다 (장면이 붙잡지 않음), 표면에는 경로가 적혀 있음
func test_lazy_tex_info_holds_no_textures() -> void:
	var keep := Ext.lazy_tex
	Ext.lazy_tex = true
	for id in ["ninja", "tank", "hook"]:
		var info = Ext.load_char(id)
		check(info != null, "%s 읽음" % id)
		if info == null:
			continue
		for suf in ["", "_lod1", "_lod2", "_lod3"]:
			check(not ResourceLoader.has_cached(_atlas(id, suf)), "%s%s 알베도: 몸이 없으면 안 올라와 있음" % [id, suf])
		var n := 0
		for sf in info.surfs:
			if str(sf.tex_path) != "":
				n += 1
			check(sf.tex == null, "%s 표면의 텍스처 참조는 비어 있음" % id)
		check(n >= 4, "%s: 경로가 적힌 표면 %d" % [id, n])
	Ext.lazy_tex = keep


# 판 몸 = 고른 LOD 알베도만 올림 (보통이면 LOD2 만), 몸이 사라지면 같이 풀림, 같은 캐릭터 몸끼리는 한 텍스처를 나눠 씀
func test_lazy_tex_only_picked_lod_and_shared() -> void:
	var keep := Ext.lazy_tex
	Ext.lazy_tex = true
	var a := _body("ninja", "medium")
	check(a.ext != null, "닌자 붙음")
	check(ResourceLoader.has_cached(_atlas("ninja", "_lod2")), "보통: LOD2 알베도 올라옴")
	for suf in ["", "_lod1", "_lod3"]:
		check(not ResourceLoader.has_cached(_atlas("ninja", suf)), "보통: ninja%s 알베도는 안 올라옴" % suf)
	var b := _body("ninja", "medium")
	var ta := _tex_id(a)
	var tb := _tex_id(b)
	check(ta != 0 and ta == tb, "같은 캐릭터 두 몸이 알베도 텍스처 하나를 나눠 씀")
	a.free()
	check(ResourceLoader.has_cached(_atlas("ninja", "_lod2")), "한 몸이 남아 있으면 텍스처도 남음")
	b.free()
	check(not ResourceLoader.has_cached(_atlas("ninja", "_lod2")), "몸이 모두 사라지면 알베도도 풀림")
	Ext.lazy_tex = keep


# 대기실 큰 캐릭터 (stage) 는 stage 알베도만, 판 LOD 알베도는 안 올림
func test_lazy_tex_stage_body() -> void:
	var keep := Ext.lazy_tex
	Ext.lazy_tex = true
	var s := _body("tank", "high", true)
	check(ResourceLoader.has_cached(_atlas("tank")), "큰 캐릭터: stage 알베도 올라옴")
	for suf in ["_lod1", "_lod2", "_lod3"]:
		check(not ResourceLoader.has_cached(_atlas("tank", suf)), "큰 캐릭터: tank%s 안 올라옴" % suf)
	s.free()
	check(not ResourceLoader.has_cached(_atlas("tank")), "큰 캐릭터를 치우면 stage 알베도도 풀림")
	Ext.lazy_tex = keep


# 끄면 (--no-lazy-tex) 예전처럼 장면 정보가 텍스처를 쥐고 있음 — 몸 모습은 같은 텍스처
func test_lazy_tex_off_keeps_old_behavior() -> void:
	var keep := Ext.lazy_tex
	Ext.lazy_tex = false
	Ext._cache.erase("hook")
	var info = Ext.load_char("hook")
	var held := 0
	for sf in info.surfs:
		if sf.tex != null:
			held += 1
	check(held > 0 or Ext._tex_paths.size() > 0, "끄면 표면이 텍스처를 쥠 (또는 이미 벗겨진 장면: 경로로 읽음)")
	var t = null
	for sf in info.surfs:
		if str(sf.node) == str(info.cfg.lods.high):
			t = Ext.Ext.tex_of(sf)
	check(t != null, "끄고도 몸 텍스처가 나옴")
	Ext.lazy_tex = keep
	Ext._cache.erase("hook")


# ---------- 항목 3: 블록 칸 LOD (world/cell_lod.gd · pieces_view.gd · grid_view.gd) ----------

const C_ := preload("res://core/config.gd")
const CellLod := preload("res://world/cell_lod.gd")
const WC := preload("res://world/world_config.gd")
const G3 := preload("res://shaders/g3.gd")
const PV := preload("res://world/pieces_view.gd")
const GV := preload("res://world/grid_view.gd")
const Co := preload("res://core/coords.gd")


func _cam_at(pos: Vector3) -> void:
	CellLod.test_cam = {"pos": pos, "fov": 70.0}


func test_cell_lod_distance_and_hysteresis() -> void:
	var far: float = WC.cell_lod_far
	check(not CellLod.far_state(far - 0.5, 70.0, false) and not CellLod.far_state(far + 0.5, 70.0, false), "문턱 근처 (여유 안) 는 지금 상태 유지: 높은 모양 → 높은 모양")
	check(CellLod.far_state(far + 2.0, 70.0, false), "문턱 + 여유를 넘으면 낮은 모양")
	check(CellLod.far_state(far - 0.5, 70.0, true) and not CellLod.far_state(far - 2.0, 70.0, true), "낮은 모양에서 돌아오려면 문턱 - 여유 안으로")
	# 시야각을 넓히면 같은 거리가 작게 보임 → 더 일찍 낮춤
	check(CellLod.far_state(far * 0.8, 110.0, false) and not CellLod.far_state(far * 0.8, 70.0, false), "시야각 110° 는 70° 보다 가까운 거리에서 낮춤")


func test_cell_lod_worth() -> void:
	var keep: bool = WC.cell_lod
	WC.cell_lod = true
	var low: int = PV.mesh_tris(G3.piece_mesh("castle", true))
	check(CellLod.worth(PV.mesh_tris(G3.piece_mesh("castle", false)), low), "성 테마 칸 (432) 은 낮은 모양 (108) 이 이득")
	check(not CellLod.worth(PV.mesh_tris(G3.piece_mesh("crystal", false)), low), "수정 테마 칸 (56) 은 낮은 모양 (108) 이 오히려 큼 → 그대로")
	check(not CellLod.worth(low, low), "화질 낮음 (이미 낮은 모양) 은 그대로")
	WC.cell_lod = false
	check(not CellLod.worth(432, 108), "--no-cell-lod 면 안 함")
	WC.cell_lod = keep


# 떨어지는 칸: 가까운 조각은 칸 모양 MultiMesh, 먼 조각은 낮은 모양 (하늘 블록은 반투명 쪽), 그림자 상자는 모두, 합계 = 칸 수
func test_pieces_view_far_pieces_use_low_mesh() -> void:
	var keep: bool = WC.cell_lod
	WC.cell_lod = true
	_cam_at(Vector3.ZERO)
	var pv = PV.new()
	pv._ready()
	pv.set_look(G3.piece_mesh("castle", false), [StandardMaterial3D.new(), StandardMaterial3D.new()], C_.SHAPE_COLORS, G3.piece_mesh("castle", true))
	check(pv.low_mesh != null and pv.far_mmi.visible, "낮은 모양 준비됨")
	var near_p := Co.gxyz(2.5, 2.5, 2.5)
	_cam_at(near_p + Vector3(0, 3, 6)) # 칸에서 6.7m
	var st := {"pieces": [
		{"shape": "T", "cells": [[2, 2, 2], [3, 2, 2], [4, 2, 2]], "sky": false},
		{"shape": "I", "cells": [[40, 2, 2], [41, 2, 2]], "sky": false},
		{"shape": "O", "cells": [[2, 40, 2], [3, 40, 2]], "sky": true},
		{"shape": "L", "cells": [[2, 2, 6]], "sky": true}]}
	pv.update(st, 1, {}, 0.0)
	check(pv.cells_mmi.multimesh.visible_instance_count == 3, "가까운 칸 3 (얻음 %d)" % pv.cells_mmi.multimesh.visible_instance_count)
	check(pv.far_mmi.multimesh.visible_instance_count == 2, "먼 칸 2 (얻음 %d)" % pv.far_mmi.multimesh.visible_instance_count)
	check(pv.sky_mmi.multimesh.visible_instance_count == 1 and pv.sky_far_mmi.multimesh.visible_instance_count == 2, "하늘 블록: 가까움 1·멂 2 (얻음 %d·%d)" % [pv.sky_mmi.multimesh.visible_instance_count, pv.sky_far_mmi.multimesh.visible_instance_count])
	check(pv.far_mmi.multimesh.mesh == pv.low_mesh and pv.cells_mmi.multimesh.mesh != pv.low_mesh, "먼 칸은 낮은 모양, 가까운 칸은 칸 모양")
	# 그림자 상자 (보이는 칸 그림자는 상자가 대신): 일반 칸 3 + 2 = 5, 자리가 겹치지 않음
	var qm: MultiMesh = pv.caster_mmi.multimesh
	if pv.proxy_on:
		check(qm.visible_instance_count == 5, "그림자 상자 = 일반 칸 수 5 (얻음 %d)" % qm.visible_instance_count)
	# 내가 조종하는 조각은 늘 칸 모양
	var st2 := {"pieces": [{"shape": "T", "cells": [[40, 2, 2]], "sky": false, "phase": "control", "controller": 1}]}
	pv.update(st2, 1, {}, 0.0)
	check(pv.cells_mmi.multimesh.visible_instance_count == 1 and pv.far_mmi.multimesh.visible_instance_count == 0, "내가 조종하는 조각은 멀어도 칸 모양")
	# 끄면 모두 가까운 쪽
	WC.cell_lod = false
	pv.set_look(G3.piece_mesh("castle", false), [StandardMaterial3D.new(), StandardMaterial3D.new()], C_.SHAPE_COLORS, G3.piece_mesh("castle", true))
	check(pv.low_mesh == null and not pv.far_mmi.visible, "--no-cell-lod: 낮은 모양 안 씀")
	pv.update(st, 1, {}, 0.0)
	check(pv.far_mmi.multimesh.visible_instance_count == 0 and pv.cells_mmi.multimesh.visible_instance_count == 5, "--no-cell-lod: 전부 칸 모양")
	pv.free()
	CellLod.test_cam = null
	WC.cell_lod = keep


# 쌓인 칸: 가깝/멂으로 나눔, 카메라가 regroup_move 넘게 움직일 때만 다시 나눔, 합계는 늘 칸 수
func test_grid_view_regroup() -> void:
	var keep: bool = WC.cell_lod
	WC.cell_lod = true
	_cam_at(Co.gxyz(1.0, 1.0, 4.0))
	var gv = GV.new()
	gv._ready()
	gv.set_piece_look(G3.piece_mesh("castle", false), StandardMaterial3D.new(), C_.SHAPE_COLORS, G3.piece_mesh("castle", true))
	check(gv.low_mesh != null and gv.piece_far.visible, "낮은 모양 준비됨")
	var w := 40
	var d := 4
	var grid := PackedByteArray()
	grid.resize(w * d * 3)
	for x in [1, 2, 3, 30, 35, 38]: # 앞 셋은 카메라 가까이, 뒤 셋은 멀리
		grid[x + 1 * w] = 12
	gv.rebuild(grid, w, d, 3)
	var near_n: int = gv.piece_mmi.multimesh.instance_count
	var far_n: int = gv.piece_far.multimesh.instance_count
	check(near_n == 3 and far_n == 3 and gv.lod_far == 3, "가까움 3·멂 3 (얻음 %d·%d)" % [near_n, far_n])
	var rg: int = gv.regroups
	gv.regroup()
	check(gv.regroups == rg, "카메라가 안 움직이면 다시 안 나눔")
	_cam_at(CellLod.test_cam.pos + Vector3(0.3, 0, 0))
	gv.regroup()
	check(gv.regroups == rg, "regroup_move 안쪽 움직임은 다시 안 나눔")
	_cam_at(Co.gxyz(36.0, 1.0, 4.0)) # 반대쪽으로 크게
	gv.regroup()
	check(gv.regroups == rg + 1 and gv.piece_mmi.multimesh.instance_count == 3 and gv.piece_far.multimesh.instance_count == 3, "카메라가 반대쪽으로 가면 다시 나눔 (가까움 %d·멂 %d)" % [gv.piece_mmi.multimesh.instance_count, gv.piece_far.multimesh.instance_count])
	var near_x := 0
	for k in gv.near_idx:
		if gv._pxf[k].origin.x > 20.0:
			near_x += 1
	check(near_x == 3, "가까운 칸이 카메라 쪽 (x 30 이상) 으로 바뀜 (%d)" % near_x)
	WC.cell_lod = false
	gv.set_piece_look(G3.piece_mesh("castle", false), StandardMaterial3D.new(), C_.SHAPE_COLORS, G3.piece_mesh("castle", true))
	gv.rebuild(grid, w, d, 3)
	check(gv.piece_mmi.multimesh.instance_count == 6 and gv.piece_far.multimesh.instance_count == 0, "--no-cell-lod: 전부 칸 모양")
	gv.free()
	CellLod.test_cam = null
	WC.cell_lod = keep


# ---------- 항목 4: 지형·배경 (world/scenery.gd) ----------

const Scenery := preload("res://world/scenery.gd")


func _shadow_casters(sc: Node3D) -> int:
	var n := 0
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			n += 1
	return n


# 필드 아래 섬·섬 뿌리 바위·먼 떠 있는 섬은 해 그림자를 안 던짐 (--no-scenery-opt 면 예전처럼 둘이 던짐)
func test_scenery_shadow_off() -> void:
	var keep: bool = WC.scenery_opt
	for theme in ["castle", "mushroom"]:
		var sc := Scenery.new()
		WC.scenery_opt = true
		sc._ready()
		sc.build(theme, 14, 14, false)
		var on_n := _shadow_casters(sc)
		WC.scenery_opt = false
		sc.free()
		sc = Scenery.new()
		sc._ready()
		sc.build(theme, 14, 14, false)
		var off_n := _shadow_casters(sc)
		check(on_n == 0, "%s: 켬 — 그림자 던지는 배경 메시 0 (얻음 %d)" % [theme, on_n])
		check(off_n == 2, "%s: 끔 — 예전처럼 섬·바위 메시 둘이 던짐 (얻음 %d)" % [theme, off_n])
		sc.free()
	WC.scenery_opt = keep
