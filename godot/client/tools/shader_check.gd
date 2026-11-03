# 렌더러별 셰이더 확인 (W12 2026-11-03): 우리 .gdshader 전부를 그 렌더러로 실제로 그려 컴파일 오류를 찾음 (화면이 있어야 함 — xvfb).
#   xvfb-run -a <godot> --path godot/client --rendering-method forward_plus --rendering-driver vulkan -s tools/shader_check.gd
#   (mobile 도 같음, 기본 gl_compatibility 는 --rendering-driver opengl3). 오류는 고도가 'SHADER ERROR' 로 찍음 → 끝 줄 'shader check: …'
# 툰·블록 재질은 G3 가 만든 재질 (전역 값·next_pass 외곽선·투명 변형) 도 같이 그림. 코드 안 셰이더 (hud·ko) 는 판·재연을 그 렌더러로 돌려 확인
extends SceneTree

const SKIP := ["res://addons/", "res://.godot/"]


func _initialize() -> void:
	var files := []
	_scan("res://", files)
	files.sort()
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 3)
	root3.add_child(cam)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	root3.add_child(sun)
	var layer := CanvasLayer.new()
	get_root().add_child(layer)
	var n := 0
	var x := -2.0
	for f in files:
		var sh: Shader = load(f)
		if sh == null:
			printerr("shader load fail %s" % f)
			continue
		var m := ShaderMaterial.new()
		m.shader = sh
		if sh.get_mode() == Shader.MODE_CANVAS_ITEM:
			var r := ColorRect.new()
			r.size = Vector2(64, 64)
			r.material = m
			layer.add_child(r)
		elif sh.get_mode() == Shader.MODE_SPATIAL:
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			mi.material_override = m
			mi.position = Vector3(x, 0, 0)
			x += 0.3
			root3.add_child(mi)
		n += 1
	# G3 가 만드는 재질 (툰 불투명·투명·꼭짓점 색·외곽선 next_pass, 블록 칸)
	var g3_path := "res://shaders/g3.gd"
	var g3 = load(g3_path) if ResourceLoader.exists(g3_path) else null
	var made := 0
	if g3 != null:
		var mats := [g3.toon_material(Color.WHITE), g3.toon_material(Color.WHITE, {"opacity": 0.5}), g3.toon_material(Color.WHITE, {"vertex_color": true, "outline": false})]
		for m in mats:
			var mi := MeshInstance3D.new()
			mi.mesh = SphereMesh.new()
			mi.material_override = m
			mi.position = Vector3(x, 0.5, 0)
			x += 0.3
			root3.add_child(mi)
			made += 1
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	print("shader check: 렌더러 %s · 장치 %s · 파일 %d개 + G3 재질 %d개 그림" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), n, made])
	quit(0)


func _scan(dir: String, out: Array) -> void:
	for s in SKIP:
		if dir.begins_with(s):
			return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gdshader"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_scan(dir.path_join(sub), out)
