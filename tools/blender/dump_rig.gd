# W19 Blender 캐릭터 기준 뽑기: 지금 고도 몸 (구운 몸 = JS buildFigure 와 같은 모양) 의 쉬는 자세 관절 자리·회전, 관절별 조각 상자, 소품 (탱크 방패) 자리를
# tools/blender/ref/<캐릭터>_rig.json 으로. Blender 스크립트 (build_character.py) 가 이 자리에 뼈를 세우고 몸 크기를 맞춤.
# 실행 (레포 뿌리): <godot> --headless --path godot/client -s ../../tools/blender/dump_rig.gd -- tank [ninja …]
# 좌표 = 게임 좌표 (앞 +x, 왼쪽 +y, 위 +z, m, 발바닥 z = 0 — FIGURE_SCALE 들어간 실제 크기). Blender 로는 (X, Y, Z) = (y, -x, z) (앞 -Y, 왼쪽 +X)
extends SceneTree

const C := preload("res://core/config.gd")
const Body := preload("res://chars/body.gd")
const JOINTS := ["hips", "waist", "torso", "neck", "shoulder_R", "elbow_R", "hand_R", "shoulder_L", "elbow_L", "hand_L", "thigh_R", "knee_R", "foot_R", "thigh_L", "knee_L", "foot_L"]


func _rel(n: Node, stop: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != stop:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# 트리 밖이라 is_visible_in_tree 대신 조상 visible 을 직접 봄
func _shown(n: Node, stop: Node) -> bool:
	while n != null and n != stop:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 1e-5), snappedf(v.y, 1e-5), snappedf(v.z, 1e-5)]


func _q(b: Basis) -> Array:
	var q := b.orthonormalized().get_rotation_quaternion()
	return [snappedf(q.x, 1e-5), snappedf(q.y, 1e-5), snappedf(q.z, 1e-5), snappedf(q.w, 1e-5)]


func _box_json(ab: AABB) -> Dictionary:
	return {"min": _v(ab.position), "max": _v(ab.end)}


func _joint_node(b, j: String) -> Node3D:
	match j:
		"hips": return b.hips
		"waist": return b.waist
		"torso": return b.torso
		"neck": return b.neck
	var i := 0 if j.ends_with("_R") else 1
	match j.split("_")[0]:
		"shoulder": return b.shoulders[i]
		"elbow": return b.elbows[i]
		"hand": return b.hands[i]
		"thigh": return b.thighs[i]
		"knee": return b.knees[i]
		"foot": return b.feet[i]
	return null


func _dump(ch: String) -> Dictionary:
	Body.use_ext = false
	var b = Body.new()
	b.build(ch, Color(1, 1, 1), false) # 조각 몸 (관절 노드 + 조각 메시)
	var frame: Node3D = b.frame
	var joints := {}
	var jnodes := {}
	for j in JOINTS:
		var n := _joint_node(b, j)
		jnodes[n] = j
		var t := _rel(n, frame)
		joints[j] = {"pos": _v(t.origin), "rot": _q(t.basis)}
	# 조각 상자: 조각마다 가장 가까운 조상 관절 (torso 는 메시 노드라 waist 로 셈)
	var boxes := {}
	var all := AABB()
	var first := true
	for i in b.nodes.size():
		var n: Node3D = b.nodes[i]
		if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null or not _shown(n, frame):
			continue
		var owner := ""
		var k: Node = n
		while k != null and k != frame:
			if jnodes.has(k) and jnodes[k] != "torso":
				owner = jnodes[k]
				break
			k = k.get_parent()
		var ab: AABB = _rel(n, frame) * (n as MeshInstance3D).mesh.get_aabb()
		all = ab if first else all.merge(ab)
		first = false
		if owner == "":
			continue
		boxes[owner] = ab if not boxes.has(owner) else (boxes[owner] as AABB).merge(ab)
	var bj := {}
	for k in boxes:
		bj[k] = _box_json(boxes[k])
	# 소품: 탱크 방패 (앞·등) — 허리 관절 기준 자리·회전 + 방패 자리 기준 상자
	var props := {}
	if b.refs.get("shields") is Dictionary:
		for key in ["front", "back"]:
			var sn: Node3D = b._n(b.refs.shields[key])
			if sn == null:
				continue
			var lb := AABB()
			var f2 := true
			for mi in sn.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).mesh == null:
					continue
				var ab: AABB = _rel(mi, sn) * (mi as MeshInstance3D).mesh.get_aabb()
				lb = ab if f2 else lb.merge(ab)
				f2 = false
			if (sn is MeshInstance3D) and (sn as MeshInstance3D).mesh != null:
				var ab2: AABB = (sn as MeshInstance3D).mesh.get_aabb()
				lb = ab2 if f2 else lb.merge(ab2)
			var tw := _rel(sn, b.waist)
			props["shield_" + key] = {"parent": "waist", "pos": _v(tw.origin), "rot": _q(tw.basis), "scale": _v(_rel(sn, frame).basis.get_scale()), "box": _box_json(lb)}
	var pupils := []
	if b.refs.has("pupils"):
		for r in b.refs.pupils:
			var pn: Node3D = b._n(r)
			if pn != null:
				pupils.append(_v(_rel(pn, frame).origin))
	var out := {"char": ch, "player_height": C.PLAYER_HEIGHT, "figure_scale": C.FIGURE_SCALE, "body_kind": C.FIGURE_BODY.get(ch, "lean"),
		"dims": C.FIGURE_BODIES.get(C.FIGURE_BODY.get(ch, "lean")), "joints": joints, "boxes": bj, "box": _box_json(all), "props": props, "pupils": pupils}
	b.free()
	return out


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = PackedStringArray(["tank"])
	var dir := ProjectSettings.globalize_path("res://").path_join("../../tools/blender/ref").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	for ch in args:
		var o := _dump(ch)
		var p := dir.path_join(ch + "_rig.json")
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(JSON.stringify(o, "  ", false))
		f.close()
		print("뽑음 ", p)
	quit()
