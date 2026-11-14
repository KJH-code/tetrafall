# W51: 대기실 어두운 무대 소품을 시간 조각으로 끊어 짓기 (title_world.gd _cut) — 한 번에 지은 것과 같은 결과, 여러 조각, 중간에 치워도 안전
extends RefCounted

const C := preload("res://core/config.gd")
const WC := preload("res://world/world_config.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 한 무대의 모양 지문: 자식 수 · 난수 상태 · 먼지 상자 · 빛·갱신자 수 · 메시 정점·인스턴스 합
func _sig(st: Node) -> Dictionary:
	var verts := 0
	var inst := 0
	var nodes := 0
	var stack: Array = [st]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m: Mesh = (n as MeshInstance3D).mesh
			for si in m.get_surface_count():
				verts += m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX].size() if m is ArrayMesh else m.get_faces().size()
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			inst += mm.instance_count
			if mm.mesh != null:
				verts += mm.mesh.get_surface_count()
	return {"nodes": nodes, "rnd": st.rnd.s, "box": str(st.mote_box), "lights": st.lights.size(), "upd": st.updaters.size(), "verts": verts, "inst": inst}


func _opts(defer: bool) -> Dictionary:
	return {"low": true, "logoW": 0, "logoH": 0, "camDist": 30.0, "ring": true, "clear": 20.0, "floorZ": -4.0, "defer": defer}


func test_cut_build_equals_full_all_themes() -> void:
	var S = load("res://title/title_stage.gd")
	for id in C.TITLE_THEMES.keys():
		var full = S.new(id, _opts(false))
		var part = S.new(id, _opts(true))
		part.cut_override = 0.0 # 끊는 자리마다 끊음 (가장 잘게)
		var steps := 0
		while not part.setup_step() and steps < 400:
			steps += 1
		check(part.ready_built(), "%s 다 지음" % id)
		check(steps >= 3, "%s 소품이 여러 조각으로 끊김 (steps %d)" % [id, steps])
		var a := _sig(full)
		var b := _sig(part)
		check(a == b, "%s 끊어 지음 = 한 번에 지음 (%s vs %s)" % [id, str(a), str(b)])
		full.free()
		part.free()


# 끊지 않기 (cut_override < 0 = --no-dark-split) 면 예전처럼 소품 한 조각 + 빛 가루 한 조각
func test_no_split_is_two_pieces() -> void:
	var S = load("res://title/title_stage.gd")
	var part = S.new("castle", _opts(true))
	part.cut_override = -1.0
	var steps := 0
	while not part.setup_step() and steps < 5:
		steps += 1
	check(part.ready_built() and steps == 1, "끊지 않으면 두 조각 (steps %d)" % steps)
	part.free()


# 짓다가 (코루틴이 멈춰 있는 채) 무대를 치워도 오류 없이 (테스트 틀이 엔진 오류를 잡음)
func test_free_mid_build_is_safe() -> void:
	var S = load("res://title/title_stage.gd")
	for id in ["crystal", "castle"]:
		var part = S.new(id, _opts(true))
		part.cut_override = 0.0
		part.setup_step()
		part.setup_step()
		check(not part.ready_built(), "%s 짓는 중" % id)
		part.free()
	check(true, "치움")


func test_default_step_budget() -> void:
	check(WC.DARK_STEP_MS > 0.0 and WC.DARK_STEP_MS <= 8.0, "조각 시간 8ms 이하")
