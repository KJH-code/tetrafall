# W19 몸 비용 비교: 구운 몸 (assets/models/<id>.glb) vs 외부 모델 (Blender, assets/models/ext/<id>.glb) — 같은 캐릭터 판 몸 하나·1인칭 쌍둥이
# 실행 (레포 뿌리): <godot> --headless --path godot/client -s ../../tools/blender/cost.gd -- tank
# 숫자: 보이는 삼각형 · 그리기 (보이는 표면 × (1 + 외곽선 next_pass), 그림자 패스 뺌) · 뼈 · 몸 만들기 ms (처음 / 그 뒤 평균) · pose ms (자세 + 뼈 맞추기, 200 프레임 평균)
extends SceneTree

const Body := preload("res://chars/body.gd")
const Chars := preload("res://chars/chars.gd")
const External := preload("res://chars/external.gd")


var detail := false


func _draws(root: Node) -> Dictionary:
	var tris := 0
	var draws := 0
	var meshes := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		meshes += 1
		for s in m.mesh.get_surface_count():
			var mat: Material = m.material_override if m.material_override != null else m.get_active_material(s)
			var arr := m.mesh.surface_get_arrays(s)
			var n: int = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			tris += n / 3
			if detail:
				print("  ", m.name, " 표면 ", s, " 삼각형 ", n / 3, " 외곽선 ", mat != null and mat.next_pass != null)
			draws += 1
			if mat != null and mat.next_pass != null:
				draws += 1
	return {"tris": tris, "draws": draws, "meshes": meshes}


func _bones(root: Node) -> int:
	var n := 0
	for sk in root.find_children("*", "Skeleton3D", true, false):
		n += (sk as Skeleton3D).get_bone_count()
	return n


func _measure(cid: String, ext: bool) -> Dictionary:
	Body.use_ext = ext
	External._cache.clear()
	var t0 := Time.get_ticks_usec()
	var first = Chars.make_body(cid, Color(0.85, 0.22, 0.2))
	var first_ms := (Time.get_ticks_usec() - t0) / 1000.0
	root.add_child(first)
	var t1 := Time.get_ticks_usec()
	var more := []
	for i in 10:
		more.append(Chars.make_body(cid, Color(0.2, 0.5, 0.9)))
	var next_ms := (Time.get_ticks_usec() - t1) / 10000.0
	for b in more:
		b.free()
	var p := {"id": 1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}
	first.pose(p, 0.0)
	var t2 := Time.get_ticks_usec()
	for k in 200:
		p.x = k * 0.05
		first.pose(p, k * 16.0)
	var pose_ms := (Time.get_ticks_usec() - t2) / 200000.0
	var d := _draws(first)
	# 1인칭 쌍둥이 (viewmodel 이 만드는 몸, 팔만)
	var vm = load("res://chars/viewmodel.gd").new()
	root.add_child(vm)
	vm.update(first, true, 1.0 / 60.0)
	var v := _draws(vm)
	var out := {"tris": d.tris, "draws": d.draws, "meshes": d.meshes, "bones": _bones(first), "first_ms": first_ms, "next_ms": next_ms, "pose_ms": pose_ms,
		"vm_tris": v.tris, "vm_draws": v.draws, "ext": first.get("ext") != null}
	vm.free()
	first.free()
	return out


var frame := 0


func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	_run()
	return true


func _run() -> void:
	detail = OS.get_cmdline_user_args().has("--detail")
	var args := OS.get_cmdline_user_args()
	var cid: String = args[0] if args.size() > 0 else "tank"
	var a := _measure(cid, false)
	var b := _measure(cid, true)
	print("COST %s 구운 몸 %s" % [cid, JSON.stringify(a)])
	print("COST %s 외부 모델 %s" % [cid, JSON.stringify(b)])
	print("| | 구운 몸 | 외부 (Blender) |")
	print("| --- | --- | --- |")
	for k in ["tris", "draws", "meshes", "bones", "first_ms", "next_ms", "pose_ms", "vm_tris", "vm_draws"]:
		var fa = a[k]
		var fb = b[k]
		if fa is float:
			print("| %s | %.2f | %.2f |" % [k, fa, fb])
		else:
			print("| %s | %d | %d |" % [k, fa, fb])
