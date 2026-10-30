# 서버 틱 시간 (고도 쪽): tools/js_tick_bench.mjs 와 같은 각본.
# 인원 N명 (기본 8, 닌자, 자동 블록 자리 고르기 CLEAR_BIAS) 이 각본대로 움직임: 가장 가까운 상대 쪽으로 걷고, 가까우면 6틱마다 평타,
# 90틱마다 F, 게이지 차면 R, 45틱마다 점프. 판이 끝나면 다시. 틱마다 game.tick + 스냅샷 JSON 만들기 시간을 잼.
# --bots 면 각본 대신 sim/bot.gd 봇 (봇 생각 시간 포함)
# 실행: godot --headless --path godot -s res://tests/bench.gd -- [틱 수] [인원] [--bots] [--no-chars]
extends SceneTree

const Game := preload("res://sim/game.gd")
const C := preload("res://sim/config.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var nums := []
	for a in args:
		if a.is_valid_int():
			nums.append(int(a))
	var n_ticks: int = nums[0] if nums.size() > 0 else 18000
	var n_players: int = nums[1] if nums.size() > 1 else 8
	var use_bots := args.has("--bots")
	var chars := not args.has("--no-chars")
	var g := Game.new(Callable(), chars)
	g.rng.seed = 12345
	g.profile = true
	for i in n_players:
		if use_bots:
			g.add_bot()
		else:
			g.add_player(i + 1)
	g.start_round()
	var times := PackedFloat64Array()
	var rounds := 0
	var deaths := {}
	for i in n_ticks:
		if g.phase == "over":
			rounds += 1
			for d in g.deaths:
				deaths[d.cause] = deaths.get(d.cause, 0) + 1
			g.start_round()
		var t0 := Time.get_ticks_usec()
		if not use_bots:
			script_inputs(g, i)
		g.tick(1000.0 / C.TICK_RATE)
		var snap := g.snapshot()
		snap["events"] = g.drain_events()
		JSON.stringify(snap)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	var budget := 1000.0 / C.TICK_RATE
	print("고도 %s GDScript, %d명%s%s: 틱 %d번, 판 %d번 — 평균 %.3fms (예산 %.1f%%), 중앙 %.3fms, 99%% %.3fms, 최대 %.2fms, 사망 %s" % [Engine.get_version_info().string, n_players, " 봇" if use_bots else " 각본", " 닌자" if chars else "", n_ticks, rounds, sum / n_ticks, sum / n_ticks / budget * 100.0, times[n_ticks / 2], times[int(n_ticks * 0.99)], times[n_ticks - 1], str(deaths)])
	var over := 0
	for t in times:
		if t > budget:
			over += 1
	var parts := []
	for k in ["bots", "pieces", "placement", "physics", "combat", "lava"]:
		parts.append("%s %.3f" % [k, g.prof.get(k, 0) / 1000.0 / n_ticks])
	print("  구간 평균 ms/틱: %s (자리 고르기 %d번, 한 번 평균 %.1fms), 예산(%.1fms) 넘은 틱 %d개" % [", ".join(parts), g.prof.get("placement_n", 0), g.prof.get("placement", 0) / 1000.0 / maxi(1, g.prof.get("placement_n", 0)), budget, over])
	quit(0)


# js_tick_bench.mjs script() 와 같은 각본
func script_inputs(g, i: int) -> void:
	for p in g.players.values():
		if not p.alive:
			continue
		var best = null
		var bd := INF
		for t in g.players.values():
			if t == p or not t.alive:
				continue
			var d := sqrt((t.x - p.x) * (t.x - p.x) + (t.y - p.y) * (t.y - p.y))
			if d < bd:
				bd = d
				best = t
		var yaw: float = atan2(best.y - p.y, best.x - p.x) if best else p.yaw
		g.handle_input(p.id, 1.0 if bd > 1.0 else 0.0, 0.0, (i + p.id * 7) % 45 == 0, yaw)
		if bd < 1.7 and (i + p.id) % 6 == 0:
			g.handle_action(p.id, "push")
		if (i + p.id * 11) % 90 == 0:
			g.handle_action(p.id, "skill")
		if p.ult >= C.ULT_MAX:
			g.handle_action(p.id, "ult")
