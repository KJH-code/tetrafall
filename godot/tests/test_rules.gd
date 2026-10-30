# 규칙 단위 테스트 (test/game.test.js 의 시제품 범위 몇 개를 옮김)
extends "res://tests/base.gd"

const Pieces := preload("res://sim/pieces.gd")


func test_rotation_normalized() -> void:
	var c := Pieces.rotated_cells("I", 1)
	check(Pieces.footprint(c) == Vector2i(1, 4), "I 를 한 번 돌리면 1×4")
	for r in 4:
		for s in Pieces.SHAPE_NAMES:
			var mn := Vector2i(99, 99)
			for v in Pieces.rotated_cells(s, r):
				mn = Vector2i(mini(mn.x, v.x), mini(mn.y, v.y))
			check(mn == Vector2i.ZERO, "%s 회전 %d 정규화" % [s, r])
	check(Pieces.rotated_cells("T", 4) == Pieces.rotated_cells("T", 0), "네 번 돌리면 제자리")


func test_field_size_by_players() -> void:
	var g := Game.new()
	for i in 4:
		g.add_player(i + 1)
	g.start_round()
	check(g.W == 14 and g.D == 14, "4명이면 14×14 (FIELD_SIZES)")
	check(g.add_player(99) != null, "판 중 난입은 받되")
	check(not g.players[99].alive, "관전 (죽은 상태)")


func test_piece_lands_and_fills_grid() -> void:
	var g := setup()
	g.add_falling(g.make_piece("O", 0, 4, 4, 3), C.AUTO_FALL_STEP_MS)
	run(g, 3000)
	check(g.pieces.is_empty(), "착지하면 떨어지는 블록 목록에서 빠짐")
	check(g.grid_at(4, 4, 0) != 0 and g.grid_at(5, 5, 0) != 0, "격자에 남음")
	check(g.column_top(4, 4) == 1, "기둥 높이 1")


func test_crush_on_ground() -> void:
	var g := setup()
	var p1: Game.Player = g.players[1]
	g.add_falling(g.make_piece("O", 0, 2, 2, 4), C.AUTO_FALL_STEP_MS)
	run(g, 3000)
	check(not p1.alive and p1.death_cause == "crush", "땅에 선 채 깔리면 압사")
	check(g.phase == "over" and g.winner_id == 2, "남은 한 명 승")


func test_head_bonk_survives() -> void:
	var g := setup()
	var p1: Game.Player = g.players[1]
	# 공중(필드 밖 → 아래가 끝없이 빔) 에서 블록 아래를 지나가면 머리 박음
	p1.x = -0.2
	p1.y = 0.5
	p1.z = 2.0
	p1.vz = 0.0
	p1.grounded = false
	var pc := g.make_piece("I", 0, 0, 0, 4)
	g.add_falling(pc, C.AUTO_FALL_STEP_MS)
	pc.next_step_at = g.time
	g.tick(TICK)
	check(p1.alive, "빈 공간이 넉넉하면 안 깔림")
	check(p1.z <= 3.0 - C.PLAYER_HEIGHT + 1e-6, "블록 아래로 밀려 내려감")


func test_push_knockback_and_damage() -> void:
	var g := setup()
	var a: Game.Player = g.players[1]
	var b: Game.Player = g.players[2]
	a.x = 3.0; a.y = 5.0; a.yaw = 0.0
	b.x = 4.2; b.y = 5.0
	g.handle_action(1, "push")
	check(b.damage == C.PUSH_DAMAGE, "피해 % 쌓임")
	check(b.kbx > 0.0, "앞으로 밀림")
	g.handle_action(1, "push")
	check(b.damage == C.PUSH_DAMAGE, "쿨타임 중엔 안 나감")
	# 뒤에 있는 사람은 안 맞음
	var g2 := setup()
	var a2: Game.Player = g2.players[1]
	var b2: Game.Player = g2.players[2]
	a2.x = 5.0; a2.y = 5.0; a2.yaw = 0.0
	b2.x = 4.0; b2.y = 5.0
	g2.handle_action(1, "push")
	check(b2.damage == 0, "등 뒤는 안 맞음")


func test_more_damage_more_knockback() -> void:
	var dist := []
	for dmg in [0, 100]:
		var g := setup()
		var a: Game.Player = g.players[1]
		var b: Game.Player = g.players[2]
		a.x = 2.0; a.y = 5.0; a.yaw = 0.0
		b.x = 3.0; b.y = 5.0; b.damage = dmg
		g.handle_action(1, "push")
		run(g, 2000)
		dist.append(b.x - 3.0)
	check(dist[1] > dist[0] * 1.5, "피해 %% 가 높을수록 멀리 (%s)" % str(dist))


func test_fall_death_off_edge() -> void:
	var g := setup()
	var a: Game.Player = g.players[1]
	a.x = -1.0
	a.y = 5.0
	a.z = 0.0
	a.grounded = false
	run(g, 1500)
	check(not a.alive and a.death_cause == "fall", "필드 밖은 허공 → 낙사")


func test_double_jump_and_dash_limits() -> void:
	var g := setup()
	var a: Game.Player = g.players[1]
	a.x = 5.0; a.y = 5.0
	g.handle_action(1, "jump")
	g.tick(TICK)
	check(not a.grounded, "점프")
	g.tick(TICK)
	g.handle_action(1, "jump")
	g.tick(TICK)
	check(a.air_jumps == 0, "2단 점프 한 번 씀")
	g.handle_action(1, "dash")
	check(a.air_dashes == 0, "공중 대시 한 번")
	a.dash_ready_at = 0.0
	var kb := a.kbx
	g.handle_action(1, "dash")
	check(a.kbx == kb, "공중 대시는 착지 전 한 번만")


func test_layer_clear_drops_above() -> void:
	var g := setup()
	for x in g.W:
		for y in g.D:
			if not (y == 0 and x < 4):
				g.grid[g.idx(x, y, 0)] = 1
	g.grid[g.idx(5, 5, 1)] = 1 # 위층 한 칸
	var a: Game.Player = g.players[1]
	a.z = 1.0
	var pc := g.make_piece("I", 0, 0, 0, 2)
	g.add_falling(pc, C.AUTO_FALL_STEP_MS)
	run(g, 2000)
	check(g.grid_at(5, 5, 0) != 0 and g.grid_at(5, 5, 1) == 0, "꽉 찬 층이 지워지고 위가 내려옴")
	check(g.grid_at(0, 0, 0) == 0, "지운 층의 블록도 없음")
	check(absf(a.z - 0.0) < 1e-3, "서 있던 사람도 한 칸 내려옴 (%s)" % a.z)


func test_auto_spawn_concurrent() -> void:
	var g := setup()
	g.next_spawn_at = 0.0
	run(g, 5000)
	check(g.pieces.size() >= 1 and g.pieces.size() <= g.target_concurrent(), "자동 블록이 동시 개수만큼 (%d)" % g.pieces.size())


func test_lava_kills_below_surface() -> void:
	var g := setup()
	g.base_avg_height = -2.0 # 쌓인 것으로 침
	g.tick(TICK)
	check(g.lava.active, "평균 높이가 넘으면 용암 시작")
	run(g, C.LAVA_RISE_MS_PER_CELL * 1.2)
	check(not g.players[1].alive and g.players[1].death_cause == "lava", "바닥에 있으면 용암에 죽음")
