# 새 모델 몸 자세 CPU (W39 항목 5): 렌더 없이 몸 하나의 pose() 와 Ext.sync 안 구간을 반복해 ms 를 잼 (캐릭터별, 이동 자세·가만히).
# godot --headless --path godot/client -s res://tools/pose_cpu.gd -- [--n 2000] [--chars ninja,tank,hunter,hook]
extends SceneTree

const Chars := preload("res://chars/chars.gd")
const Body := preload("res://chars/body.gd")
const Prof := preload("res://core/prof.gd")


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var n := 2000
	var i := a.find("--n")
	if i >= 0:
		n = int(a[i + 1])
	var ids: Array = ["ninja", "tank", "hunter", "hook"]
	i = a.find("--chars")
	if i >= 0:
		ids = str(a[i + 1]).split(",")
	Body.use_ext = true
	var host := Node3D.new()
	root.add_child(host)
	for id in ids:
		var b = Chars.make_body(id, Color(0.8, 0.3, 0.3))
		host.add_child(b)
		var ext = b.ext
		if ext == null:
			print("POSE_CPU %s: 외부 몸 없음" % id)
			continue
		for walk in [false, true]:
			var t_pose := 0.0
			var t_sync := 0.0
			var t_maps := 0.0
			var t_bones := 0.0
			var t0 := 0
			var x := 5.0
			Prof.on = false
			for f in 60: # 데우기
				x += 0.1 if walk else 0.0
				b.pose({"id": 1, "slot": 0, "char": id, "alive": true, "yaw": 0.3, "x": x, "y": 5.0, "z": 0.0, "damage": 0}, 1000.0 + f * 16.7)
			t0 = Time.get_ticks_usec()
			for f in n:
				x += 0.1 if walk else 0.0
				b.pose({"id": 1, "slot": 0, "char": id, "alive": true, "yaw": 0.3, "x": x, "y": 5.0, "z": 0.0, "damage": 0}, 2000.0 + f * 16.7)
			t_pose = (Time.get_ticks_usec() - t0) / 1000.0 / n
			Prof.on = true # 구간별 (pose 안): 구간 재기 비용이 조금 섞임
			Prof.sums = {}
			for f in n:
				x += 0.1 if walk else 0.0
				b.pose({"id": 1, "slot": 0, "char": id, "alive": true, "yaw": 0.3, "x": x, "y": 5.0, "z": 0.0, "damage": 0}, 2000.0 + f * 16.7)
			var parts := []
			for k in Prof.sums:
				parts.append("%s %.3f" % [str(k).replace("몸 ", ""), float(Prof.sums[k][0]) / 1000.0 / n])
			print("POSE_CPU_구간 %s %s: %s" % [id, "이동" if walk else "정지", " · ".join(parts)])
			Prof.on = false
			t0 = Time.get_ticks_usec()
			for f in n:
				ext.sync()
			t_sync = (Time.get_ticks_usec() - t0) / 1000.0 / n
			t0 = Time.get_ticks_usec()
			for f in n:
				ext._code_maps()
			t_maps = (Time.get_ticks_usec() - t0) / 1000.0 / n
			t0 = Time.get_ticks_usec()
			for f in n:
				ext._code_bones()
			t_bones = (Time.get_ticks_usec() - t0) / 1000.0 / n
			print("POSE_CPU %-7s %-5s pose %.3fms · ext.sync %.3f (관절을 뼈로 %.3f + 뼈 쓰기 %.3f) · 뼈 %d (관절 %d, 쓰는 뼈 %d)" % [id, "이동" if walk else "정지", t_pose, t_sync, t_maps, t_bones, ext.info.order.size(), ext.maps.size(), ext.need_order.size()])
		b.free()
	quit()
