# 서버 틱 시간 (고도 쪽): tools/js_tick_bench.mjs 와 같은 각본. 틱마다 game.tick + 스냅샷 JSON 만들기 시간을 잼
# 실행: godot --headless --path godot -s res://tests/bench.gd -- [틱 수]
extends SceneTree

const Game := preload("res://sim/game.gd")
const C := preload("res://sim/config.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 36000
	var g := Game.new()
	g.rng.seed = 12345
	g.add_player(1)
	g.add_player(2)
	g.start_round()
	var times := PackedFloat64Array()
	var rounds := 0
	for i in n:
		if g.phase == "over":
			rounds += 1
			g.start_round()
		for pair in [[1, 2], [2, 1]]:
			var a = g.players[pair[0]]
			var b = g.players[pair[1]]
			g.handle_input(pair[0], 1.0, 0.0, i % 45 == 0, atan2(b.y - a.y, b.x - a.x))
			if i % 20 == pair[0] * 5:
				g.handle_action(pair[0], "push")
		var t0 := Time.get_ticks_usec()
		g.tick(1000.0 / C.TICK_RATE)
		var snap := g.snapshot()
		snap["events"] = g.drain_events()
		JSON.stringify(snap)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	print("고도 %s (GDScript): 틱 %d번, 판 %d번 끝남 — 평균 %.4fms, 중앙 %.4fms, 99%% %.4fms, 최대 %.3fms" % [Engine.get_version_info().string, n, rounds, sum / n, times[n / 2], times[int(n * 0.99)], times[n - 1]])
	quit(0)
