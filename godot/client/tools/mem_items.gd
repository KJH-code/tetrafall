# 영상 메모리 항목별 값 (W45 항목 4): 빈 장면에서 하나씩 만들어 보며 RENDER_TEXTURE_MEM_USED (그림)·RENDER_BUFFER_MEM_USED (버퍼) 가 얼마나 느는지.
# 소프트웨어 렌더 (llvmpipe) 라도 메모리는 렌더러가 보고하는 값이라 믿을 만함 (압축 그림은 실제 GPU 와 같은 S3TC 크기).
# xvfb-run -a godot --path godot/client --rendering-driver opengl3 --resolution 1280x720 -s res://tools/mem_items.gd
extends SceneTree

var rows: Array = []
var steps: Array = []
var i := 0
var last := Vector2.ZERO
var wait := 0


func _mon() -> Vector2:
	return Vector2(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED), Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0


func _initialize() -> void:
	var ids := ["tank", "ninja", "hunter", "hook"]
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1, 5)
	root.add_child(cam)
	steps.append(["기준 (맨 장면, 창 %s)" % str(root.size), func(): pass])
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	root.add_child(sun)
	steps.append(["해 그림자 켬 (방향광 그림자 지도 기본 크기)", func(): pass])
	steps.append(["방향광 그림자 지도 1024 (게임 값)", func(): RenderingServer.directional_shadow_atlas_set_size(1024, true)])
	steps.append(["방향광 그림자 지도 4096 (고도 기본)", func(): RenderingServer.directional_shadow_atlas_set_size(4096, true)])
	steps.append(["방향광 그림자 지도 1024 원래 값", func(): RenderingServer.directional_shadow_atlas_set_size(1024, true)])
	for msaa in [1, 2, 3]:
		steps.append(["SubViewport 512x512 own_world MSAA %dx" % [[1, 2, 4][msaa - 1] if msaa < 3 else 4], func():
			var vp := SubViewport.new()
			vp.size = Vector2i(512, 512)
			vp.own_world_3d = true
			vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][msaa - 1]
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(vp)
			var c := Camera3D.new()
			vp.add_child(c)])
	for id in ids:
		for f in ["%s_%s_atlas.jpg" % [id, id], "%s_%s_atlas_lod1.jpg" % [id, id], "%s_mask_lod1.png" % id, "%s_mask.png" % id]:
			var path: String = "res://assets/models/ext/" + f
			if ResourceLoader.exists(path):
				steps.append(["그림 %s" % f, func(): _hold.append(load(path))])
	for id in ids:
		var gp := "res://assets/models/ext/%s.glb" % id
		steps.append(["몸 파일 %s.glb 불러와 장면에 넣음 (메시 전 LOD)" % id, func():
			var sc := (load(gp) as PackedScene).instantiate()
			_hold.append(sc)
			root.add_child(sc)])
	steps.append(["끝", func(): pass])


var _hold: Array = []


func _process(_d: float) -> bool:
	wait += 1
	if wait < 4:
		return false
	wait = 0
	var now := _mon()
	if i > 0:
		print("MEMI %-62s 그림 %+6.2f buf %+6.2f   (누계 그림 %.1f buf %.1f)" % [steps[i - 1][0], now.x - last.x, now.y - last.y, now.x, now.y])
	last = now
	if i >= steps.size():
		quit()
		return true
	(steps[i][1] as Callable).call()
	i += 1
	return false
