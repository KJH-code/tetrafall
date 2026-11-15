# W32 닌자 단검 합치기 (tools/blender/tripo/rig_ninja.py --dagger): 조각 셋이 한 메시 · 한 재질 (팔레트 그림) 이라 손마다 그리기 1 (+ 외곽선)
extends RefCounted

const Body := preload("res://chars/body.gd")
const PV := preload("res://world/pieces_view.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _body(ch: String, third := true):
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), third)
	Body.use_ext = was
	return b


# 닌자 단검: 조각 셋 (칼날·손잡이·날밑) 이 한 메시 · 한 재질 (팔레트 그림) 로 합쳐져 손마다 그리기 1 (+ 외곽선) — 몸 그리기 14 → 6
func test_ninja_dagger_merged() -> void:
	var b = _body("ninja")
	var props := []
	for ba in b.find_children("*", "BoneAttachment3D", true, false):
		for mi in ba.find_children("*", "MeshInstance3D", true, false):
			props.append(mi)
	check(props.size() == 2, "단검 메시 둘 (손마다 하나) — 얻음 %d" % props.size())
	var pal := [Color(0.898, 0.918, 0.945), Color(0.486, 0.380, 0.314), Color(0.627, 0.635, 0.667)] # 칼날·손잡이·날밑 (예전 조각 재질 색)
	for mi in props:
		var m := (mi as MeshInstance3D).mesh
		check(m.get_surface_count() == 1, "단검 한 표면 (%d)" % m.get_surface_count())
		check(PV.mesh_tris(m) == 46, "단검 삼각형 46 (칼날 6 + 손잡이 28 + 날밑 12, 예전 세 조각 합) — %d" % PV.mesh_tris(m))
		var mat = m.surface_get_material(0)
		check(mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null, "팔레트 그림 재질")
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
			var im: Image = (mat as BaseMaterial3D).albedo_texture.get_image()
			check(im.get_width() == 12 and im.get_height() == 1, "팔레트 12×1")
			for i in 3:
				var c := im.get_pixel(i * 4 + 2, 0)
				check(absf(c.r - pal[i].r) < 0.01 and absf(c.g - pal[i].g) < 0.01 and absf(c.b - pal[i].b) < 0.01, "팔레트 %d 칸 색 (%s)" % [i, str(c)])
		# 꼭짓점 UV 가 한 칸 가운데 (4 칸 폭 안쪽) 에만 있어 가장자리 섞임 없음
		var uv: PackedVector2Array = m.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var bad := 0
		for u in uv:
			var cell := u.x * 12.0
			if absf(cell - (floorf(cell / 4.0) * 4.0 + 2.0)) > 0.01:
				bad += 1
		check(uv.size() > 0 and bad == 0, "UV 는 칸 가운데 (벗어난 꼭짓점 %d)" % bad)
	# 몸 그리기 수 (보이는 MeshInstance3D): 단검 합친 뒤 몸 + 단검 둘 = 그림 3 표면 (예전 몸 + 단검 6 = 7)
	var surfaces := 0
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh != null and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and m.visible:
			surfaces += m.mesh.get_surface_count()
	check(surfaces <= 6, "닌자 몸 그림 표면 수 (몸 + 단검 둘 + 띠 등) %d" % surfaces)
	b.free()
