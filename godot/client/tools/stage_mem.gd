# 대기실 큰 캐릭터 렌더 대상 영상 메모리 (W45 항목 4): 보일 때 (칸 크기 × 화면 배율) 와 release 뒤 (2×2) 의 RENDER_TEXTURE_MEM_USED.
# xvfb-run -a godot --path godot/client --rendering-driver opengl3 --resolution 960x540 -s res://tools/stage_mem.gd -- [--no-stage-shrink]
extends SceneTree

var stage = null
var frames := 0
var m0 := 0.0
var m1 := 0.0


func _mem() -> float:
	return Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0


func _initialize() -> void:
	root.add_child(Camera3D.new())


func _process(_d: float) -> bool:
	frames += 1
	if frames == 5:
		m0 = _mem()
		stage = load("res://ui/char_stage.gd").new()
		stage.size = Vector2(360, 520)
		root.add_child(stage)
		stage.show_char("tank", Color(0.8, 0.2, 0.2))
	if frames == 40:
		m1 = _mem()
		print("STAGE_MEM 보임: %.2fMB → %.2fMB (+%.2f) 렌더 대상 %s" % [m0, m1, m1 - m0, str(stage.vp.size)])
		stage.release()
	if frames == 60:
		var m2 := _mem()
		print("STAGE_MEM release 뒤: %.2fMB (보일 때보다 %+.2f) 렌더 대상 %s" % [m2, m2 - m1, str(stage.vp.size)])
		quit()
	return false
