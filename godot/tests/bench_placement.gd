# 자동 블록 자리 고르기 한 번 시간 (판 크기별): 평지 / tests/js_placement.json 의 울퉁불퉁한 격자.
# 실행: godot --headless --path godot -s res://tests/bench_placement.gd   (JS 쪽: node godot/tools/js_placement_bench.mjs)
extends SceneTree

const Game := preload("res://sim/game.gd")


func _init() -> void:
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://tests/js_placement.json"))
	for size in [10, 14, 19]:
		print("%d×%d 평지: %s" % [size, size, timed(make(size, []))])
	for cs in cases:
		print("%d×%d 울퉁불퉁: %s" % [cs.size, cs.size, timed(make(int(cs.size), cs.tops))])
	quit(0)


func make(size: int, tops: Array) -> Game:
	var g := Game.new()
	g.set_field_size(size)
	for i in tops.size():
		for z in int(tops[i]):
			g.grid[g.idx(i % size, i / size, z)] = 1
	return g


func timed(g: Game) -> String:
	var n := 5
	var t0 := Time.get_ticks_usec()
	var cands := []
	for k in n:
		cands = g.auto_candidates("I")
	return "후보 %d개, 한 번 %.1fms" % [cands.size(), (Time.get_ticks_usec() - t0) / 1000.0 / n]
