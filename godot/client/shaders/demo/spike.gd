# G3 첫 진입 멈춤 재기: '메뉴' (하늘·카메라만) 로 MENU_FRAMES 프레임 → g3_demo 장면을 숨긴 채 깔고 5 프레임 뒤 보이게 → 그 뒤 프레임 시간 (ms) = 처음 그리기 (셰이더 만들기) 만.
# --prewarm 이면 메뉴 동안 G3.prewarm. 인자는 g3_demo 와 같이 넘어감 (--theme · --terrain · --hazard · --pieces · --light · --body)
#   xvfb-run -a godot --path godot/client --rendering-driver opengl3 res://shaders/demo/spike.tscn -- --theme volcano --terrain --hazard 1.4 [--prewarm]
extends Node3D

const G3 := preload("res://shaders/g3.gd")
const MENU_FRAMES := 20
const MEASURE := 15

var frame := 0
var last := 0
var times: Array = []
var prewarm := false


func _ready() -> void:
	prewarm = OS.get_cmdline_user_args().has("--prewarm")
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	G3.apply_theme(self, "volcano")
	last = Time.get_ticks_usec()


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	frame += 1
	if frame == 3 and prewarm:
		G3.prewarm(self)
	if frame == MENU_FRAMES: # 판 장면을 숨긴 채 깖 (계산 시간은 재지 않음)
		get_node("G3Env").queue_free() # 판 장면이 제 하늘을 깖
		var d: Node3D = load("res://shaders/demo/g3_demo.tscn").instantiate()
		d.name = "Game"
		add_child(d)
		d.visible = false
	elif frame == MENU_FRAMES + 5: # 보이게 = 처음 그림 (셰이더 만들기) — 여기부터 잼
		get_node("Game").visible = true
	elif frame > MENU_FRAMES + 5:
		times.append((now - last) / 1000.0)
		if times.size() >= MEASURE:
			var worst := 0.0
			var sum := 0.0
			for t in times:
				worst = maxf(worst, t)
				sum += t
			print("SPIKE prewarm=%s 처음 %d프레임: 가장 긴 %.1fms · 합 %.1fms · 첫 셋 %s" % [prewarm, times.size(), worst, sum, str(times.slice(0, 3).map(func(x): return snappedf(x, 0.1)))])
			get_tree().quit()
	last = now
