# JS 판과 비교: tools/js_compare.mjs 가 뽑은 tests/js_expected.json 과 같은 장면을 돌려 숫자를 맞춤
# (JS 값을 다시 뽑으려면: node godot/tools/js_compare.mjs > godot/tests/js_expected.json)
extends "res://tests/base.gd"


func expected() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/js_expected.json"))


func test_push_distance_matches_js() -> void:
	var e := expected()
	for dmg in [0, 50]:
		var g := setup()
		var a: Game.Player = g.players[1]
		var b: Game.Player = g.players[2]
		a.x = 3.0; a.y = 5.0; a.yaw = 0.0
		b.x = 4.2; b.y = 5.0; b.yaw = PI; b.damage = dmg
		g.handle_action(1, "push")
		run(g, 2000)
		near(b.x - 4.2, e["push_dist_%d" % dmg], 0.005, "밀치기 거리 (피해 %d%%)" % dmg)
		check(b.damage == int(e["push_damage_after_%d" % dmg]), "피해 %")


func test_piece_fall_matches_js() -> void:
	var e := expected()
	for key in ["piece_land_ms", "crush_ms"]:
		var g := setup()
		var px := 4 if key == "piece_land_ms" else 2
		var pc := g.make_piece("O", 0, px, px, C.PIECE_SPAWN_Z)
		g.add_falling(pc, C.AUTO_FALL_STEP_MS)
		var t0 := g.time
		var at := -1.0
		for i in 2000:
			g.tick(TICK)
			var done: bool = (not g.pieces.has(pc)) if key == "piece_land_ms" else (not g.players[1].alive)
			if done:
				at = g.time - t0
				break
		near(at, e[key], 0.5, key)


func test_jump_matches_js() -> void:
	var e := expected()
	var g := setup()
	var a: Game.Player = g.players[1]
	a.x = 5.0; a.y = 5.0
	g.handle_input(1, 0, 0, true, 0)
	g.tick(TICK)
	g.handle_input(1, 0, 0, false, 0)
	var peak := 0.0
	var air := TICK
	for i in 200:
		g.tick(TICK)
		peak = maxf(peak, a.z)
		if a.grounded:
			break
		air += TICK
	near(peak, e.jump_peak, 0.002, "점프 최고 높이")
	near(air, e.jump_air_ms, 0.5, "점프 공중 시간")


func test_dash_walk_match_js() -> void:
	var e := expected()
	var g := setup()
	var a: Game.Player = g.players[1]
	a.x = 2.0; a.y = 5.0; a.yaw = 0.0
	g.handle_action(1, "dash")
	run(g, 2000)
	near(a.x - 2.0, e.dash_dist, 0.005, "대시 거리")
	var g2 := setup()
	var b: Game.Player = g2.players[1]
	b.x = 2.0; b.y = 5.0; b.yaw = 0.0
	g2.handle_input(1, 1, 0, false, 0)
	run(g2, 1000)
	near(b.x - 2.0, e.walk_1s, 0.005, "1초 걷기")


func test_fall_death_matches_js() -> void:
	var e := expected()
	var g := setup()
	var a: Game.Player = g.players[1]
	var b: Game.Player = g.players[2]
	a.x = 7.5; a.y = 5.0; a.yaw = 0.0
	b.x = 8.7; b.y = 5.0; b.damage = 150
	g.handle_action(1, "push")
	var t0 := g.time
	var dead := -1.0
	for i in 300:
		g.tick(TICK)
		if not b.alive:
			dead = g.time - t0
			break
	near(dead, e.fall_death_ms, 0.5, "밀려 낙사까지 시간")
	check(b.death_cause == e.fall_death_cause, "낙사 원인")
