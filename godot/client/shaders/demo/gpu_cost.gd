# G3 재질별 그리기 비용: g3_demo 장면 (인자 그대로) 을 깔고, 셰이더 하나씩 숨겨 가며 viewport 그리기 시간 (CPU+GPU, ms) 평균을 잼.
#   xvfb-run -a godot --path godot/client --rendering-driver opengl3 --resolution 1280x720 res://shaders/demo/gpu_cost.tscn -- --theme desert --terrain --hazard 1.4
extends Node3D

const G3 := preload("res://shaders/g3.gd")

const N := 20
var game: Node3D
var cases: Array = [] # [이름, 숨길 셰이더 경로 목록]
var ci := -1
var frame := 0
var acc := [0.0, 0.0]
var hidden: Array = []


func _ready() -> void:
	game = load("res://shaders/demo/g3_demo.tscn").instantiate()
	add_child(game)
	if OS.get_cmdline_user_args().has("--cost-low"): # 그래픽 낮춤으로 재기
		G3.set_low(game, true)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	cases = [["전부", []], ["지형 빼고", ["terrain"]], ["위험 빼고", ["hazard"]], ["바닥 빼고", ["floor"]], ["툰 (조각) 빼고", ["toon"]], ["하늘 빼고", ["sky"]], ["외곽선 끔", ["@outline"]], ["그림자 끔", ["@shadow"]]]


func _shader_of(n: Node) -> String:
	var m = n.get("material_override")
	if not (m is ShaderMaterial and m.shader):
		return ""
	if "hazard.gdshaderinc" in m.shader.code:
		return "hazard" # 갈래 셰이더 (경로 없음)
	return m.shader.resource_path.get_file().get_basename()


func _apply(hide: Array) -> void:
	for n in hidden:
		n.visible = true
	hidden.clear()
	var sun: DirectionalLight3D = game.get_node("G3Env/Sun")
	sun.shadow_enabled = not hide.has("@shadow")
	for n in game.find_children("*", "GeometryInstance3D", true, false):
		var m = n.get("material_override")
		if m is ShaderMaterial:
			m.next_pass = null if hide.has("@outline") else m.get_meta("np", m.next_pass)
			if not m.has_meta("np"):
				m.set_meta("np", m.next_pass)
		if hide.has(_shader_of(n)) and n.visible:
			n.visible = false
			hidden.append(n)


func _process(_d: float) -> void:
	frame += 1
	if ci < 0:
		if frame >= 15:
			ci = 0
			frame = 0
			_apply(cases[0][1])
		return
	if frame > 5: # 바꾼 뒤 몇 프레임 버림
		var vr := get_viewport().get_viewport_rid()
		acc[0] += RenderingServer.viewport_get_measured_render_time_cpu(vr)
		acc[1] += RenderingServer.viewport_get_measured_render_time_gpu(vr)
	if frame >= 5 + N:
		print("COST %s: CPU %.1fms · GPU %.1fms" % [cases[ci][0], acc[0] / N, acc[1] / N])
		acc = [0.0, 0.0]
		ci += 1
		frame = 0
		if ci >= cases.size():
			get_tree().quit()
			return
		_apply(cases[ci][1])
