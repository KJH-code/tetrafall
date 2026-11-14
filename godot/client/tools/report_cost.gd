# W48 성능 보고서의 프레임당 비용 측정 (기본으로 켜 두는 것들이 0.05ms 아래인지): godot --headless --path godot/client -s tools/report_cost.gd
#   1) Report.tick (프레임 간격 기록 + 최악 갱신 + Performance 모니터 + 히치 판정 Log.push)   2) 팝 카운터 한 표본 (합성 뼈대 12개, 60Hz 간격이면 프레임당 이 한 번)
#   3) 판이 끝날 때 한 번 (collect + build + 파일)   4) 끈 보고서 _process
# 측정은 소프트웨어 CPU 에서 GDScript 로 — 재혁 PC 는 보통 더 빠르다. 값은 us/번 중앙값 (3번 돌림).
extends SceneTree

var R
var Hitch
var Pops


func _bench(name: String, n: int, fn: Callable) -> float:
	var runs := []
	for k in 3:
		var t0 := Time.get_ticks_usec()
		for i in n:
			fn.call(i)
		runs.append((Time.get_ticks_usec() - t0) / float(n))
	runs.sort()
	print("%-52s %8.2f us/번 (중앙값, %d번×3)" % [name, runs[1], n])
	return runs[1]


func _initialize() -> void:
	_run.call_deferred() # 자동 불러오기 (Store 등) 가 올라온 뒤에 스크립트를 읽음 (preload 하면 컴파일이 안 됨)


func _run() -> void:
	R = load("res://core/report.gd")
	Hitch = load("res://core/hitch.gd")
	Pops = load("res://core/pop_count.gd")
	R.file_path = "user://cost_report.txt"
	var rep: Node = R.new()
	Hitch.on = true
	rep.ctx = {"char": "ninja", "players": 8, "bots": 7, "map": "flat", "mode": "survival"}
	rep._start_round()
	var n := 20000
	var tick := _bench("1) Report.tick (프레임 기록·히치 판정)", n, func(i): rep.tick(rep.start_us + i * 16700, 16.7 + (i % 7) * 0.1, []))
	var sk := Skeleton3D.new()
	for b in Pops.BONES:
		sk.add_bone("mixamorig_" + b)
	var p = Pops.new()
	var pop := _bench("2) 팝 카운터 한 표본 (뼈 12개)", n, func(i):
		for b in sk.get_bone_count():
			sk.set_bone_pose_rotation(b, Quaternion(Vector3.UP, deg_to_rad(0.3 * (i % 100))))
		p.sample_skel(sk, 1.0 / 60.0, i / 60.0, "ninja"))
	var set_only := _bench("   (뼈 회전 넣기만, 위 2 에 든 부분)", n, func(i):
		for b in sk.get_bone_count():
			sk.set_bone_pose_rotation(b, Quaternion(Vector3.UP, deg_to_rad(0.3 * (i % 100)))))
	var t0 := Time.get_ticks_usec()
	rep._end_round()
	var end_us := Time.get_ticks_usec() - t0
	print("%-52s %8.0f us (판 끝날 때 한 번, 프레임 %d개)" % ["3) 판 끝 보고서 만들기 (collect + build + 파일)", end_us, rep.frames.size()])
	R.enabled = false
	var off := _bench("4) 끈 보고서 _process", n, func(_i): rep._process(0.016))
	R.enabled = true
	print("")
	print("프레임당 합계 (60Hz 표본 한 번 기준): 1) %.2f + 2) %.2f (회전 넣기 %.2f 는 몸이 이미 함) = %.2f us = %.3f ms" % [tick, pop - set_only, set_only, tick + pop - set_only, (tick + pop - set_only) / 1000.0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://cost_report.txt"))
	sk.free()
	rep.free()
	quit(0)
