# JS 판과 비교: tools/js_compare.mjs 가 뽑은 tests/js_expected.json 과 같은 장면을 돌려 숫자를 맞춤
# (JS 값을 다시 뽑으려면: node godot/prototype/tools/js_compare.mjs > godot/prototype/tests/js_expected.json)
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


func test_ninja_combo_matches_js() -> void:
	var e := expected()
	var g := setup_ninja()
	var a: Game.Player = g.players[1]
	var b: Game.Player = g.players[2]
	check(a.chr == "ninja", "캐릭터 켜면 닌자")
	a.x = 3.0; a.y = 5.0; a.yaw = 0.0
	b.x = 4.0; b.y = 5.0; b.yaw = PI
	var peak := 0.0
	for i in 90:
		if i < 45 and i % 3 == 0:
			g.handle_action(1, "push")
		g.tick(TICK)
		peak = maxf(peak, b.z)
	check(b.damage == int(e.ninja_combo_damage), "연타 피해 %d, 기대 %d" % [b.damage, int(e.ninja_combo_damage)])
	near(b.x - 4.0, e.ninja_combo_bx, 0.005, "연타 밀린 거리")
	near(peak, e.ninja_combo_bpeak, 0.005, "연타 띄운 높이")
	near(a.x - 3.0, e.ninja_combo_ax, 0.005, "때린 쪽 앞으로 나간 거리")
	near(a.ult, e.ninja_combo_ult, 0.01, "필살기 게이지")


func test_ninja_blink_matches_js() -> void:
	var e := expected()
	var g := setup_ninja()
	var a: Game.Player = g.players[1]
	var b: Game.Player = g.players[2]
	a.x = 2.0; a.y = 5.0; a.yaw = 0.0
	b.x = 4.0; b.y = 5.0
	g.handle_action(1, "skill")
	run(g, 1000)
	near(a.x, e.ninja_blink_ax, 0.005, "순간 베기 뒤 위치")
	check(b.damage == int(e.ninja_blink_bdamage), "베기 피해")
	near(b.x, e.ninja_blink_bx, 0.005, "베인 쪽 위치")


func test_ninja_star_and_wallkick_match_js() -> void:
	var e := expected()
	var g := setup_ninja()
	var a: Game.Player = g.players[1]
	var b: Game.Player = g.players[2]
	a.x = 2.0; a.y = 5.0; a.yaw = 0.0; a.ult = 100.0
	b.x = 4.5; b.y = 5.0
	g.handle_action(1, "ult")
	g.tick(TICK)
	g.handle_action(1, "push")
	run(g, 1000)
	check(b.damage == int(e.ninja_star_bdamage), "표창 2연발 피해 %d" % b.damage)
	near(b.x - 4.5, e.ninja_star_bx, 0.005, "표창 밀린 거리")
	var g2 := setup_ninja()
	var a2: Game.Player = g2.players[1]
	for y in g2.D:
		for z in 2:
			g2.grid[g2.idx(5, y, z)] = 1
	a2.x = 3.5; a2.y = 5.5; a2.yaw = 0.0
	g2.handle_action(1, "skill")
	var peak := 0.0
	for i in 60:
		g2.tick(TICK)
		peak = maxf(peak, a2.z)
	near(a2.x, e.ninja_wallkick_ax, 0.005, "벽 앞에서 멈춤")
	near(peak, e.ninja_wallkick_peak, 0.005, "벽 차기 높이")


# 같은 격자 → 모든 후보 점수가 JS placementScorer 와 같고, 같은 무작위 값이면 같은 자리
func test_placement_scores_match_js() -> void:
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://tests/js_placement.json"))
	check(cases is Array and cases.size() == 8, "js_placement.json 격자 8개")
	if not cases is Array:
		return
	for cs in cases:
		var g := Game.new()
		g.set_field_size(int(cs.size))
		for i in cs.tops.size():
			var x: int = i % int(cs.size)
			var y: int = i / int(cs.size)
			for z in int(cs.tops[i]):
				g.grid[g.idx(x, y, z)] = 1
		var cands := g.auto_candidates("I")
		check(cands.size() == cs.scores.size(), "%d×%d 후보 수 %d, JS %d" % [cs.size, cs.size, cands.size(), cs.scores.size()])
		var bad := 0
		for i in mini(cands.size(), cs.scores.size()):
			if cands[i][4] != int(cs.scores[i]):
				bad += 1
		check(bad == 0, "%d×%d 점수 다른 후보 %d개" % [cs.size, cs.size, bad])
		for pk in cs.picks:
			var got: Array = g.pick_candidate(cands, pk[0])
			check(got[0] == pk[1] and got[1] == int(pk[2]) and got[2] == int(pk[3]) and got[3] == int(pk[4]), "%d×%d u=%s 고른 자리 %s, JS %s" % [cs.size, cs.size, pk[0], str(got.slice(0, 4)), str(pk.slice(1))])
