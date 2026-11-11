# W42 최적화 6차: 입장 쪼개기 문 (core/entry_gate.gd) · 어두운 무대 나눠 짓기 · 판 HUD 카드 미리 만들기 · 잔상 몸 풀 (chars/body.gd snapshot_fill, world/body_fx.gd)
# · GPU 첫 사용 커버리지 (world/warm_scan.gd 목록) · 유령 스킨 미리 켜기
extends RefCounted

const Gate := preload("res://core/entry_gate.gd")
const C := preload("res://core/config.gd")
const Body := preload("res://chars/body.gd")
const Chars := preload("res://chars/chars.gd")
const BodyFx := preload("res://world/body_fx.gd")
const Scenery := preload("res://world/scenery.gd")
const LobbyDark := preload("res://world/lobby_dark.gd")
const PS := preload("res://world/prewarm_sched.gd")

var errors: Array = []
var _fake_frame := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _frame() -> int:
	return _fake_frame


func _gate_reset() -> void:
	Gate.reset()
	Gate.enabled_override = true
	Gate._clock = Callable(self, "_frame")
	_fake_frame = 1


func _gate_end() -> void:
	Gate.reset()


# 순수 계산: 그 프레임에 큰 일이 없었으면 무조건 허용 (굶지 않음), 있었으면 합이 상한 이하일 때만
func test_gate_can() -> void:
	check(Gate.can(0.0, 99.0), "빈 프레임은 얼마나 큰 일이든 허용")
	check(Gate.can(14.0, 2.0) and not Gate.can(14.0, 25.0), "잔일 (예상 4ms 미만) 은 큰 일 뒤에도 허용 — 잔일이 큰 일을 굶기지 않음 / 큰 일 뒤 큰 일은 미룸")
	check(Gate.can(6.0, 10.0), "6 + 10 = 16 = 상한 → 허용")
	check(not Gate.can(6.0, 10.1), "6 + 10.1 > 상한 → 미룸")
	check(not Gate.can(14.0, 22.0), "큰 일 뒤에 큰 일은 미룸")
	check(Gate.CAP_MS <= 16.0, "상한은 평소 프레임 일 (~8ms) 을 더해도 25ms 안에 드는 값")


# 프레임 번호가 바뀌면 합이 0, 같은 프레임엔 쌓임. 못 한 일은 다음 프레임 첫 일로 돈다 (굶지 않음)
func test_gate_frames_and_starvation() -> void:
	_gate_reset()
	check(Gate.ok("world.dark.load"), "첫 일 허용")
	Gate.spent = 22.0 # 22ms 걸렸다고 침
	check(not Gate.ok("world.scenery"), "같은 프레임 두 번째 큰 일은 미룸")
	check(not Gate.ok("body"), "몸 만들기도 미룸")
	check(int(Gate.log["world.scenery"][1]) == 1 and int(Gate.log["body"][1]) == 1, "미룬 수를 셈")
	_fake_frame += 1
	check(Gate.ok("world.scenery"), "다음 프레임엔 첫 일이라 허용")
	var t0 := Gate.t() - 6000
	Gate.done("world.scenery", t0)
	check(Gate.spent >= 6.0 and Gate.frame_peak >= 6.0, "돌린 ms 가 이 프레임 합에 들어감 (%.1f)" % Gate.spent)
	check(Gate.est_of("world.scenery") >= 17.0, "큰 일의 예상은 기본값 밑으로 안 내려감 (%.1f)" % Gate.est_of("world.scenery"))
	Gate.est["ui.hud"] = 0.9
	check(is_equal_approx(Gate.est_of("ui.hud"), 0.9), "잔일은 잰 값 그대로")
	_gate_end()


# 꺼져 있으면 (--no-entry-split) 늘 허용 + 기록 안 함
func test_gate_off_always_ok() -> void:
	_gate_reset()
	Gate.enabled_override = false
	Gate.spent = 99.0
	check(Gate.ok("world.dark.load") and Gate.ok("body") and Gate.ok("ui.stage"), "끄면 늘 허용")
	Gate.done("body", Gate.t())
	check(Gate.log.is_empty(), "끄면 기록 안 함")
	_gate_end()


# 입장 한 바퀴를 시뮬: 큰 일 6개 (표 예상값) 를 매 프레임 문에 물으면 한 프레임에 쓰는 합 (예상) 이 상한을 안 넘음
func test_gate_entry_sequence_never_over_cap() -> void:
	_gate_reset()
	var queue := ["world.theme", "world.dark.load", "world.dark", "world.dark.part", "world.dark.part", "world.scenery", "ui.stage", "body", "ui.portrait", "world.grid"]
	var frames := 0
	var worst := 0.0
	while not queue.is_empty() and frames < 40:
		frames += 1
		_fake_frame += 1
		var spent := 0.0
		var i := 0
		while i < queue.size():
			if Gate.ok(queue[i]):
				var e := Gate.est_of(queue[i])
				Gate.spent += e # 예상 = 실제라고 침
				spent += e
				queue.remove_at(i)
			else:
				break # 순서 지킴 (world 는 막히면 return)
		worst = maxf(worst, spent)
	check(queue.is_empty(), "다 돌아감 (굶지 않음)")
	# 한 일 하나 (스크립트 컴파일 22) 가 상한보다 커도 혼자면 허용 — 그 프레임은 그 일만
	check(worst <= maxf(Gate.CAP_MS, Gate.est_of("world.dark.load")) + 0.001, "한 프레임 합이 상한 (또는 홀로 도는 가장 큰 일) 이하 (%.1f)" % worst)
	check(frames >= 5 and frames <= 20, "프레임 수가 터무니없지 않음 (%d)" % frames)
	_gate_end()


# 게이트는 정적 상태에 Callable (람다) 을 남기지 않음 — 종료 때 정적 상태가 죽은 노드를 쥐는 abort 방지 (W41 병합 수정과 같은 규칙)
func test_gate_keeps_no_lambda_after_reset() -> void:
	_gate_reset()
	check(Gate._clock.is_valid(), "테스트 시계 있음")
	Gate.reset()
	check(not Gate._clock.is_valid() and Gate.log.is_empty() and Gate.est.is_empty(), "reset 이 시계·기록을 비움")
	var task_fn: Callable = LobbyDark.preload_stage
	check(task_fn.get_object() == null or not (task_fn.get_object() is Node), "스케줄러에 넣는 무대 스크립트 미리 읽기는 노드를 안 붙잡음")


# scenery.stale: 만들 일이 있나 (테마·판 크기·화질 바뀜) — 문이 먼저 묻는 용
func test_scenery_stale() -> void:
	var s := Scenery.new()
	s._ready()
	check(not s.stale(null, 12, 12, false), "테마 없음은 일 아님 (비우기만)")
	var id: String = C.WORLD_THEMES.keys()[0]
	check(s.stale(id, 12, 12, false), "처음엔 일")
	s.build(id, 12, 12, false)
	check(not s.stale(id, 12, 12, false), "만든 뒤엔 일 아님")
	check(s.stale(id, 13, 12, false) and s.stale(id, 12, 12, true), "판 크기·화질이 바뀌면 일")
	check(s.stale(C.WORLD_THEMES.keys()[1], 12, 12, false), "테마가 바뀌면 일")
	s.free()


# 어두운 무대 나눠 짓기: defer 로 지으면 앞부분만 하고, setup_step 두 번 (소품 · 빛 가루) 뒤 완성 = 한 번에 지은 것과 같은 자식 수
func test_stage_deferred_equals_full() -> void:
	var S = load("res://title/title_stage.gd")
	for id in ["crystal", "meadow"]:
		var opts := {"low": true, "logoW": 0, "logoH": 0, "camDist": 30.0, "ring": true, "clear": 20.0, "floorZ": -4.0}
		var full = S.new(id, opts)
		var od := opts.duplicate()
		od["defer"] = true
		var part = S.new(id, od)
		check(full.ready_built(), "%s 한 번에: 다 지음" % id)
		check(not part.ready_built(), "%s 나눔: 앞부분만" % id)
		check(part.get_child_count() < full.get_child_count(), "%s 나눔: 앞부분은 자식이 적음 (%d < %d)" % [id, part.get_child_count(), full.get_child_count()])
		var steps := 0
		while not part.setup_step() and steps < 5:
			steps += 1
		check(part.ready_built() and steps == 1, "%s 나눔: 두 조각이면 끝 (steps %d)" % [id, steps])
		check(part.get_child_count() == full.get_child_count(), "%s 나눔 = 한 번에 (자식 %d vs %d)" % [id, part.get_child_count(), full.get_child_count()])
		check(part.dust != null and full.dust != null, "%s 빛 가루 있음" % id)
		part.update(1.0, 1.0) # 다 지은 뒤엔 update 가 돔 (오류 없이)
		full.free()
		part.free()
	# 안 지은 채 update 해도 안전
	var early = S.new("crystal", {"low": true, "ring": true, "clear": 20.0, "floorZ": -4.0, "defer": true})
	early.update(1.0, 1.0)
	check(not early.ready_built(), "다 안 지은 무대는 update 가 건너뜀")
	early.free()


func _hud_player(id: int, slot: int) -> Dictionary:
	return {"id": id, "slot": slot, "name": "P%d" % (slot + 1), "nick": "", "wins": 0, "score": 0, "color": slot, "alive": true, "char": C.FIGURE_CHARS[slot % C.FIGURE_CHARS.size()], "damage": 0, "team": ""}


# 판 HUD 아래 카드: 대기실에서 한 장씩 미리 만들어 두면 판 시작 때 _cards 가 새로 안 만들고 그대로 씀. 사람 목록이 바뀌면 처음부터
func test_hud_prebuild_cards() -> void:
	var keep := [Store.my_id, Store.room]
	Store.my_id = 1
	Store.room = {"code": "ABCD"}
	var hud = load("res://ui/hud.gd").new()
	hud._ready()
	var players := []
	for i in 8:
		players.append(_hud_player(i + 1, i))
	var st := {"phase": "lobby", "mode": "survival", "teamMode": false, "players": players, "round": {"n": 0}}
	var vp := Vector2(1280, 720)
	var calls := 0
	while not hud.prebuild_cards(st, vp) and calls < 20:
		calls += 1
	check(calls == 7, "카드 8장 = 부름 8번 (7번 거짓 뒤 참) %d" % calls)
	check(hud.cards.size() == 8 and hud.cards_row.get_child_count() == 8, "카드 8장이 만들어져 있음")
	var ids := []
	for c in hud.cards.values():
		ids.append(c.panel.get_instance_id())
	check(hud.prebuild_cards(st, vp), "다 만든 뒤엔 바로 참")
	# 판 시작 (countdown): _cards 가 노드를 그대로 씀
	var st2: Dictionary = st.duplicate(true)
	st2.phase = "countdown"
	st2["round"] = {"n": 1, "countdownLeft": 3000.0}
	hud._cards(st2, vp)
	var same := true
	for c in hud.cards.values():
		if not ids.has(c.panel.get_instance_id()):
			same = false
	check(same and hud.cards_row.visible, "countdown 에서 미리 만든 카드를 그대로 보임")
	# 사람이 바뀌면 (봇 추가) 처음부터
	var st3: Dictionary = st.duplicate(true)
	st3.players.pop_back()
	var calls3 := 0
	while not hud.prebuild_cards(st3, vp) and calls3 < 20:
		calls3 += 1
	check(calls3 == 6 and hud.cards.size() == 7, "사람이 바뀌면 다시 7장 (부름 %d)" % calls3)
	# 중간에 판이 시작해도 (반만 만든 상태) _cards 가 새로 만들어 안전
	var st4: Dictionary = st.duplicate(true)
	hud.prebuild_cards(st4, vp)
	hud.prebuild_cards(st4, vp)
	st4.phase = "countdown"
	st4["round"] = {"n": 1, "countdownLeft": 3000.0}
	hud._cards(st4, vp)
	check(hud.cards.size() == 8 and hud.cards_row.get_child_count() == 8, "반만 미리 만든 채 시작해도 8장 (%d)" % hud.cards.size())
	hud.free()
	Store.my_id = keep[0]
	Store.room = keep[1]


# 잔상 풀: snapshot 복제본에 지금 자세만 베끼면 새로 복제한 것과 같은 자세. 구조가 안 맞으면 false
func test_snapshot_fill_matches_fresh() -> void:
	var was := Body.use_ext
	var mat := StandardMaterial3D.new()
	var host := Node3D.new()
	for spec in [["ninja", true], ["tank", true], ["bard", false], ["builder", false]]:
		Body.use_ext = spec[1]
		var b = Chars.make_body(spec[0], Color(0.8, 0.3, 0.3))
		host.add_child(b)
		for f in 20:
			b.pose({"id": 1, "slot": 0, "char": spec[0], "alive": true, "yaw": 0.3, "x": 5.0 + f * 0.1, "y": 5.0, "z": 0.0, "damage": 0}, 1000.0 + f * 16.7)
		var h: Node3D = b.snapshot(mat)
		host.add_child(h)
		for f in 25: # 자세가 달라지게
			b.pose({"id": 1, "slot": 0, "char": spec[0], "alive": true, "yaw": 1.1, "x": 9.0 + f * 0.2, "y": 6.0, "z": 0.5, "damage": 40}, 3000.0 + f * 16.7)
		var m2 := StandardMaterial3D.new()
		check(b.snapshot_fill(h, m2), "%s snapshot_fill 성공" % spec[0])
		var fresh: Node3D = b.snapshot(mat)
		host.add_child(fresh)
		var worst := 0.0
		var worst_name := ""
		var pairs := 0
		var skel_bad := 0
		var stack := [[fresh.get_child(0), h.get_child(0)]]
		while not stack.is_empty():
			var pr: Array = stack.pop_back()
			var a: Node = pr[0]
			var d: Node = pr[1]
			if a is Node3D and d is Node3D and not (a is BoneAttachment3D): # (뼈에 붙은 노드는 뼈 갱신 때 따라옴 — 복제본은 아직 안 갱신)
				pairs += 1
				var ta: Transform3D = (a as Node3D).transform
				var td: Transform3D = (d as Node3D).transform
				var dv: float = (ta.origin - td.origin).length() + absf(ta.basis.x.x - td.basis.x.x) + absf(ta.basis.y.y - td.basis.y.y) + absf(ta.basis.z.z - td.basis.z.z) + absf(ta.basis.x.y - td.basis.x.y) + absf(ta.basis.y.z - td.basis.y.z) + absf(ta.basis.z.x - td.basis.z.x)
				if dv > worst:
					worst = dv
					worst_name = "%s/%s" % [a.get_parent().name if a.get_parent() != null else "", a.name]
				if a is Skeleton3D:
					for i in (a as Skeleton3D).get_bone_count():
						if not (a as Skeleton3D).get_bone_pose(i).is_equal_approx((d as Skeleton3D).get_bone_pose(i)):
							skel_bad += 1
			for c in a.get_children(true):
				var cd: Node = d.get_node_or_null(NodePath(str(c.name).replace("@", "_")))
				if cd != null:
					stack.append([c, cd])
		check(pairs > 10 and worst < 1e-4 and skel_bad == 0, "%s 풀로 채운 자세 = 새로 복제한 자세 (노드 %d, 최대 차 %.6f %s, 뼈 다름 %d)" % [spec[0], pairs, worst, worst_name, skel_bad])
		var tinted: Array = h.get_meta("tinted")
		check(not tinted.is_empty() and tinted.all(func(g): return (g as MeshInstance3D).material_override == m2), "%s 재질만 갈아 끼움" % spec[0])
		# 구조가 안 맞는 holder (자식을 하나 지움) 는 거절
		var broken: Node3D = b.snapshot(mat)
		var skel: Node = broken.find_children("*", "MeshInstance3D", true, false)[0]
		skel.get_parent().remove_child(skel)
		skel.free()
		check(not b.snapshot_fill(broken, mat), "%s 구조가 안 맞으면 false" % spec[0])
		broken.free()
		fresh.free()
		h.free()
		b.free()
	Body.use_ext = was
	host.free()


# body_fx 풀: 끝난 잔상을 숨겨 두고 같은 종류 몸이면 다시 씀, 상한 넘으면 버림, --no-ghost-pool 이면 풀 안 씀
func test_body_fx_ghost_pool_reuse() -> void:
	var was := Body.use_ext
	Body.use_ext = false
	var fx = BodyFx.new()
	var host := Node3D.new()
	var b = Chars.make_body("builder", Color(0.3, 0.8, 0.3))
	host.add_child(b)
	var mat := StandardMaterial3D.new()
	var g1: Node3D = fx._snap(b, mat)
	check(fx.snap_stats == [0, 1] and g1.get_parent() == fx, "처음엔 새 복제 (풀 비어 있음)")
	fx._snap_release(g1)
	check(not g1.visible and (fx._snap_pool.values()[0] as Array).size() == 1, "끝난 잔상은 숨겨 풀에")
	var g2: Node3D = fx._snap(b, mat)
	check(g2 == g1 and g2.visible and fx.snap_stats == [1, 1], "같은 종류 몸이 다시 씀 (복제 안 함)")
	# 상한
	var many := []
	for i in BodyFx.SNAP_POOL_MAX + 3:
		many.append(fx._snap(b, mat))
	for g in many:
		fx._snap_release(g)
	var kept: int = (fx._snap_pool.values()[0] as Array).size()
	check(kept == BodyFx.SNAP_POOL_MAX, "풀은 상한 (%d) 까지만 (%d)" % [BodyFx.SNAP_POOL_MAX, kept])
	fx._snap_release(g2)
	# 몸 종류가 다르면 다른 풀
	var b2 = Chars.make_body("bard", Color(0.3, 0.3, 0.8))
	host.add_child(b2)
	var before: int = fx.snap_stats[1]
	var gb: Node3D = fx._snap(b2, mat)
	check(fx.snap_stats[1] == before + 1 and gb.get_meta("snap_key") != g1.get_meta("snap_key"), "몸 종류마다 풀이 따로")
	fx.free()
	host.free()
	Body.use_ext = was


# ---- 항목 4·5: GPU 첫 사용 (셰이더 컴파일) 커버리지 ----
const WS := preload("res://world/warm_scan.gd")
const MF := preload("res://core/mat_first.gd")

# --mat-first 로 8명 판 (캐릭터마다 한 판, 소프트웨어 렌더) 을 돌려 '판에서 처음 그려진' 표준 재질 모양을 모은 것 (render_priority 뺀 열쇠). 이 모양은 미리 그리기 표 (STD_KEYS) 에 있어야 함 — 없으면 이벤트 때 컴파일
const OBSERVED_STD := [
	"B:sh0,tr1,bl0,cu2,dt0,bb0,vc0,tx0,em0,fog1,dd0", "B:sh0,tr1,bl0,cu0,dt0,bb0,vc1,tx0,em0,fog0,dd0", "B:sh0,tr1,bl0,cu2,dt0,bb0,vc1,tx0,em0,fog0,dd2",
	"B:sh0,tr1,bl1,cu2,dt0,bb0,vc0,tx1,em0,fog1,dd0", "B:sh0,tr0,bl0,cu2,dt0,bb0,vc0,tx0,em0,fog0,dd0", "B:sh0,tr1,bl0,cu2,dt0,bb0,vc0,tx0,em0,fog0,dd0",
	"B:sh0,tr1,bl1,cu2,dt0,bb0,vc0,tx0,em0,fog1,dd0", "B:sh0,tr1,bl1,cu2,dt0,bb0,vc0,tx0,em0,fog0,dd2", "B:sh0,tr0,bl0,cu2,dt0,bb0,vc0,tx0,em0,fog1,dd0",
	"B:sh0,tr1,bl0,cu0,dt0,bb0,vc1,tx0,em0,fog1,dd0", "B:sh0,tr1,bl1,cu0,dt0,bb1,vc0,tx1,em0,fog1,dd0", "B:sh0,tr1,bl0,cu2,dt1,bb0,vc0,tx0,em0,fog0,dd0",
	"B:sh0,tr1,bl0,cu2,dt1,bb0,vc0,tx0,em0,fog1,dd0",
]


func test_std_keys_cover_observed_events() -> void:
	var have := []
	for k in WS.STD_KEYS:
		have.append(MF.mat_key(WS.std_material(k)))
	for o in OBSERVED_STD:
		check(have.has(o), "판에서 처음 그려지는 재질 모양이 미리 그리기 표에 없음: " + o)
	check(have.size() == WS.STD_KEYS.size() and have.size() >= OBSERVED_STD.size(), "표의 모양이 겹치지 않음 (%d)" % have.size())
	for k in WS.SKIN_KEYS:
		check(WS.STD_KEYS.has(k), "스킨에 입히는 모양은 표준 표 안")


func test_std_entries_have_sprite_and_clear() -> void:
	var e: Array = WS.std_entries()
	check(e.size() == WS.STD_KEYS.size() + 1 and e.back()[0] is String, "표준 재질 + Sprite3D 한 칸")
	var host := Node3D.new()
	var root: Node3D = WS.spawn(host, [e.back()], null)
	var sprites := root.find_children("*", "Sprite3D", true, false)
	check(sprites.size() == 2, "Sprite3D 두 갈래 (%d)" % sprites.size())
	check(MF.keys_of(sprites[0]) == ["sprite3d"], "mat_first 가 Sprite3D 로 셈")
	WS.clear_static()
	check(WS._std.is_empty() and WS._px == null, "clear_static 이 정적 재질을 비움 (종료 때 쥐고 있지 않음)")
	host.free()


# 한 재질을 메시 · MultiMesh 네 갈래 (색+custom / 색 / custom / 없음) 로 그림 — 판이 실제로 쓰는 노드 종류 조합
func test_spawn_draws_all_node_kinds() -> void:
	var host := Node3D.new()
	var m := WS.std_material(WS.STD_KEYS[0])
	var root: Node3D = WS.spawn(host, [[m, true]], null)
	var kinds := {}
	for n in root.get_children():
		for k in MF.keys_of(n):
			kinds[str(k).split("|")[0]] = true
	for want in ["mesh", "multi+col+cd", "multi+col", "multi+cd", "multi"]:
		check(kinds.has(want), "미리 그리기가 노드 종류를 그림: " + want)
	host.free()


func test_mat_first_key_chain_and_kinds() -> void:
	var a := WS.std_material(WS.STD_KEYS[0])
	var b := WS.std_material(WS.STD_KEYS[1])
	a.next_pass = b
	check(MF.mat_key(a).contains(">B:"), "next_pass 줄 이어 적음")
	a.render_priority = 9
	check(not MF.mat_key(a).contains("rp"), "render_priority 는 셰이더 모양이 아니라 열쇠에 안 넣음")
	var sh := ShaderMaterial.new()
	sh.shader = load("res://shaders/toon.gdshader")
	check(MF.mat_key(sh) == "S:toon.gdshader", "셰이더 재질은 파일 이름")
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = sh
	check(MF.keys_of(mi) == ["mesh|S:toon.gdshader"], "메시 노드 열쇠")
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mmi.multimesh.use_colors = true
	mmi.multimesh.mesh = BoxMesh.new()
	mmi.multimesh.instance_count = 1
	mmi.material_override = sh
	check(MF.keys_of(mmi) == ["multi+col|S:toon.gdshader"], "MultiMesh 열쇠 (색)")
	mmi.multimesh.instance_count = 0
	check(MF.keys_of(mmi).is_empty(), "비어 있는 MultiMesh 는 안 그려져 안 셈")
	mi.free()
	mmi.free()


# 항목 5: 스킨 몸 유령 갈래 — 대기실 몸 종류마다 스킨 메시에 유령 재질·표준 반투명을 입혀 숨은 채 그림. 스킨 메시 열쇠가 'skin|...' 로 잡히는지 + 작업이 줄에 달리는지
func test_skin_warm_wiring_and_key() -> void:
	var was := Body.use_ext
	Body.use_ext = true
	var b = Chars.make_body("ninja", Color(0.8, 0.3, 0.3))
	var host := Node3D.new()
	host.add_child(b)
	var g: Node3D = b.snapshot(WS.std_material(WS.SKIN_KEYS[0]))
	host.add_child(g)
	var skin_keys := []
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		for k in MF.keys_of(mi):
			if str(k).begins_with("skin|"):
				skin_keys.append(k)
	check(not skin_keys.is_empty() and skin_keys.all(func(k): return str(k).begins_with("skin|B:")), "스킨 메시에 표준 반투명이 입혀짐 (%d)" % skin_keys.size())
	check(BodyFx.skin_key(b) == "ninja|x", "스킨 갈래 열쇠 = 몸 종류 (%s)" % BodyFx.skin_key(b))
	var src := FileAccess.get_file_as_string("res://world/world.gd")
	check(src.contains('"warm.skin"') and src.contains("_warm_skin_step") and src.contains("--no-skin-warm"), "world.gd 가 warm.skin 작업을 줄에 넣음 (--no-skin-warm 으로 끔)")
	host.free()
	Body.use_ext = was


# 잔상 복제본은 원본에 없는 (떼어 둔 LOD) 메시를 안 달고 있음 — 겹쳐 그리던 것 (삼각형 4만+) 과 풀 메모리 +19MB 를 없앰
func test_snapshot_has_only_source_meshes() -> void:
	var was := Body.use_ext
	Body.use_ext = true
	var b = Chars.make_body("ninja", Color(0.8, 0.3, 0.3))
	var host := Node3D.new()
	host.add_child(b)
	var count := func(n: Node) -> int:
		var k := 0
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).layers != 0:
				k += 1
		return k
	var g: Node3D = b.snapshot(StandardMaterial3D.new())
	host.add_child(g)
	check(count.call(g) == count.call(b.frame), "복제본 메시 수 = 원본 (%d vs %d)" % [count.call(g), count.call(b.frame)])
	var fresh_extra: int = Body.prune_extras(b.frame, g.get_child(0))
	check(fresh_extra == 0, "이미 정리됨 (더 지울 것 없음)")
	check(b.snapshot_fill(g, StandardMaterial3D.new()), "정리한 복제본도 풀로 채워짐")
	host.free()
	Body.use_ext = was
