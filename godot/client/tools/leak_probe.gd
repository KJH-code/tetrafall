# 몸 만들고 지우기를 되풀이해 객체·자원·노드·정적 메모리가 늘어나는지 (W37, 긴 판 누수 후보 좁히기).
# xvfb-run -a godot --path godot/client --rendering-driver opengl3 -s res://tools/leak_probe.gd -- [--n 12] [--chars ninja,tank,...] [--no-ext] [--pose 3]
extends SceneTree

const Chars := preload("res://chars/chars.gd")
const Body := preload("res://chars/body.gd")

var ids: Array = ["ninja", "tank", "hunter", "hook", "bard", "berserker", "builder", "cannon"]
var n := 12
var posec := 3
var ci := 0
var it := 0
var phase := 0
var cur: Node = null
var base := {}
var rows: Array = []
var host: Node3D


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--n")
	if i >= 0:
		n = int(a[i + 1])
	i = a.find("--pose")
	if i >= 0:
		posec = int(a[i + 1])
	i = a.find("--chars")
	if i >= 0:
		ids = str(a[i + 1]).split(",")
	Body.use_ext = not a.has("--no-ext")
	host = Node3D.new()
	root.add_child(host)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 6.0)
	root.add_child(cam)


func _mon() -> Dictionary:
	return {"obj": Performance.get_monitor(Performance.OBJECT_COUNT), "res": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "node": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "mem": Performance.get_monitor(Performance.MEMORY_STATIC)}


var frames_in := 0


func _process(_d: float) -> bool:
	if ci >= ids.size():
		print("LEAK_PROBE 끝")
		quit()
		return false
	var id: String = ids[ci]
	if phase == 0: # 만들기
		cur = Chars.make_body(id, Color(0.3, 0.6, 0.9))
		host.add_child(cur)
		phase = 1
		frames_in = 0
	elif phase == 1:
		var p := {"id": 1, "slot": 0, "char": id, "alive": true, "yaw": 0.0, "x": 5.0, "y": 5.0, "z": 0.0, "damage": 0}
		if cur.has_method("pose"):
			cur.pose(p, Time.get_ticks_msec())
		frames_in += 1
		if frames_in >= posec:
			phase = 2
	elif phase == 2: # 지우기
		host.remove_child(cur)
		cur.queue_free()
		cur = null
		phase = 3
	elif phase == 3: # 한 프레임 뒤 (queue_free 처리) 쟀
		it += 1
		if it == 2:
			base = _mon() # 두 번 해 본 뒤를 기준 (처음 읽기·캐시 제외)
		if it == n:
			var m := _mon()
			rows.append([id, int(m.obj - base.obj), int(m.res - base.res), int(m.node - base.node), (m.mem - base.mem) / 1024.0])
			print("LEAK_PROBE %-9s %d회: 물체 %+d · 자원 %+d · 노드 %+d · 정적 메모리 %+.0fKB (회당 물체 %+.1f)" % [id, n - 2, rows[-1][1], rows[-1][2], rows[-1][3], rows[-1][4], float(rows[-1][1]) / (n - 2)])
			ci += 1
			it = 0
		phase = 0
	return false
