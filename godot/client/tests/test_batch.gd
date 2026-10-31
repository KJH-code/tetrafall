# G3 몸 묶기 (batch.gd): ① 정점 자리 = 조각 그대로 (어떤 자세든) ② 정점 색 = 조각 sRGB 색 ③ 숨긴 조각은 크기 0 ④ 조각은 안 그림·묶을 수 없는 건 그대로
extends RefCounted

const G3 := preload("res://shaders/g3.gd")

var errors: Array = []



func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _body() -> Node3D:
	var body := Node3D.new()
	body.position = Vector3(3, 1, -2)
	body.rotation = Vector3(0.2, 0.7, 0)
	var torso := MeshInstance3D.new()
	torso.name = "torso"
	torso.mesh = BoxMesh.new()
	torso.material_override = G3.toon_material(0xe0533a)
	body.add_child(torso)
	var arm := MeshInstance3D.new()
	arm.name = "arm"
	var cm := CylinderMesh.new()
	cm.height = 0.8
	arm.mesh = cm
	arm.position = Vector3(0.7, 0.2, 0)
	arm.material_override = G3.toon_material(0x3a7be0)
	arm.set_meta("tf_skin", true)
	torso.add_child(arm)
	var hand := MeshInstance3D.new()
	hand.name = "hand"
	hand.mesh = SphereMesh.new()
	hand.position = Vector3(0, -0.5, 0.1)
	hand.material_override = G3.toon_material(0xf2c53d)
	arm.add_child(hand)
	var face := MeshInstance3D.new() # 그림 있는 조각: 안 묶음
	face.name = "face"
	face.mesh = QuadMesh.new()
	face.material_override = G3.toon_material(0xffffff, {"map": PlaceholderTexture2D.new()})
	torso.add_child(face)
	return body


func _expected(b) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in b.pieces:
		var rel: Transform3D = b.rel_of(p)
		for s in p.mesh.get_surface_count():
			var arr: Array = p.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			for i in (range(vs.size()) if idx == null or idx.size() == 0 else Array(idx)):
				out.append(rel * vs[i])
	return out


func _same(a: PackedVector3Array, e: PackedVector3Array, msg: String) -> void:
	check(a.size() == e.size(), "%s: 정점 수 %d / %d" % [msg, a.size(), e.size()])
	var worst := 0.0
	for i in mini(a.size(), e.size()):
		worst = maxf(worst, a[i].distance_to(e[i]))
	check(worst < 1e-4, "%s: 가장 먼 차 %f" % [msg, worst])


func test_batch_pose_color_hide() -> void:
	var body := _body()
	var b = G3.batch_mesh(body)
	check(b.pieces.size() == 3, "묶은 조각 3 (그림 조각 뺌) %d" % b.pieces.size())
	_same(b.skinned_vertices(), _expected(b), "처음 자세")
	# 아무 자세: 조각을 돌리고 옮기고 크기 바꿈 + 몸 전체도 움직임
	var arm: Node3D = body.get_node("torso/arm")
	arm.rotation = Vector3(1.1, -0.4, 0.8)
	arm.scale = Vector3(1, 1.3, 0.9)
	body.get_node("torso").position = Vector3(0, 0.3, 0.2)
	body.get_node("torso/arm/hand").rotation = Vector3(0, 2, 0)
	body.rotation = Vector3(-0.3, 2.1, 0.4)
	body.position = Vector3(-5, 2, 9)
	b.sync()
	_same(b.skinned_vertices(), _expected(b), "돌린 자세")
	# 숨김
	body.get_node("torso/arm").visible = false
	b.sync()
	
	var hv: PackedVector3Array = b.skinned_vertices()
	var arr: Array = b.mi.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var want := [Color.hex(0xe0533aff), Color.hex(0x3a7be0ff), Color.hex(0xf2c53dff)]
	var bad := 0
	var spread := 0.0
	var hand_origin: Vector3 = b.rel_of(body.get_node("torso/arm/hand")).origin
	for i in cols.size():
		if not cols[i].is_equal_approx(want[bones[i * 4]]):
			bad += 1
		if bones[i * 4] == 2:
			spread = maxf(spread, hv[i].distance_to(hand_origin))
	check(bad == 0, "정점 색이 조각 sRGB 색과 다름 %d개" % bad)
	check(spread < 1e-4, "숨긴 팔의 손도 한 점으로 %f" % spread)
	# 조각은 안 그림, 그림 조각은 그대로
	check(body.get_node("torso").layers == 0 and body.get_node("torso").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "조각 안 그림")
	check(body.get_node("torso/face").layers != 0, "그림 조각은 따로 그림")
	var mat: ShaderMaterial = b.mi.material_override
	check(mat.get_shader_parameter("use_vertex_color") == true and mat.next_pass != null, "정점 색 툰 + 외곽선 하나")
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var skin_bad := 0
	for i in uv2.size():
		if (uv2[i].x > 0.5) != (bones[i * 4] == 1):
			skin_bad += 1
	check(uv2.size() == cols.size() and skin_bad == 0, "피부 조각 (tf_skin) 정점만 UV2.x = 1 (%d 틀림)" % skin_bad)
	body.free()
