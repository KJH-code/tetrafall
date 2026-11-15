# 잔상·낙사 잔상 비용 (W42 항목 3): 몸 복제 (body.snapshot) 와 풀 재사용 (body.snapshot_pool) 의 ms 를 렌더 없이 잼
# godot --headless --path godot/client -s res://tools/ghost_pool.gd -- [--n 200] [--chars ninja,tank,hunter,hook,bard,builder,cannon,berserker]
extends SceneTree

const Chars := preload("res://chars/chars.gd")
const Body := preload("res://chars/body.gd")


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var n := 200
	var i := a.find("--n")
	if i >= 0:
		n = int(a[i + 1])
	var ids: Array = ["ninja", "tank", "hunter", "hook", "bard", "builder", "cannon", "berserker"]
	i = a.find("--chars")
	if i >= 0:
		ids = str(a[i + 1]).split(",")
	Body.use_ext = true
	var host := Node3D.new()
	root.add_child(host)
	var mat := StandardMaterial3D.new()
	for id in ids:
		var b = Chars.make_body(id, Color(0.8, 0.3, 0.3))
		host.add_child(b)
		for f in 30:
			b.pose({"id": 1, "slot": 0, "char": id, "alive": true, "yaw": 0.3, "x": 5.0 + f * 0.1, "y": 5.0, "z": 0.0, "damage": 0}, 1000.0 + f * 16.7)
		var cnt := _count(b.frame)
		var t0 := Time.get_ticks_usec()
		for k in n:
			var g: Node3D = b.snapshot(mat)
			host.add_child(g)
			g.queue_free()
		var t_old := (Time.get_ticks_usec() - t0) / 1000.0 / n
		var t_pool := -1.0
		var h: Node3D = b.snapshot(mat)
		host.add_child(h)
		var t1 := Time.get_ticks_usec()
		var okc := 0
		for k in n:
			if b.snapshot_fill(h, mat):
				okc += 1
		t_pool = (Time.get_ticks_usec() - t1) / 1000.0 / n
		if okc != n:
			print("  !! 구조 안 맞음 %d/%d" % [okc, n])
		print("GHOST_POOL %s: 노드 %s · 복제 %.2fms · 풀 %s" % [id, str(cnt), t_old, ("%.2fms" % t_pool) if t_pool >= 0.0 else "-"])
	quit(0)


func _count(n: Node) -> Dictionary:
	var d := {"all": 0, "mesh": 0, "skel": 0, "bones": 0}
	var st := [n]
	while not st.is_empty():
		var x: Node = st.pop_back()
		d.all += 1
		if x is MeshInstance3D:
			d.mesh += 1
		if x is Skeleton3D:
			d.skel += 1
			d.bones += (x as Skeleton3D).get_bone_count()
		for c in x.get_children():
			st.append(c)
	return d
