# G2 캐릭터 몸: 걸음걸이·공중·기울임·평소 버릇 목표 자세가 JS (client/figure-pose.js) 와 같은 값인지 (tools/fixtures.mjs 가 뽑은 figure_pose.json)
extends RefCounted

const C := preload("res://core/config.gd")
const Pose := preload("res://chars/figure_pose.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func same_pose(got: Dictionary, want: Dictionary, label: String) -> bool:
	for key in want:
		var w = want[key]
		var g = got.get(key)
		if w is Array:
			for i in w.size():
				if absf(float(g[i]) - float(w[i])) > 1e-9:
					errors.append("%s %s[%d] %f / JS %f" % [label, key, i, g[i], w[i]])
					return false
		elif absf(float(g) - float(w)) > 1e-9:
			errors.append("%s %s %f / JS %f" % [label, key, g, w])
			return false
	return true


func test_figure_pose_matches_js() -> void:
	var fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/figure_pose.json"))
	check(fx != null, "figure_pose.json")
	if fx == null:
		return
	var bad := 0
	for c in fx.cases:
		var T: Dictionary = fx.rest.duplicate(true)
		var label: String = c.fn
		match c.fn:
			"gait":
				label = "걸음 %s hs %s walk %s" % [c["char"], c.hs, c.walk]
				Pose.gait_pose(T, fx.D, c.hs, c.walk, Pose.gait_of(c["char"]))
			"air":
				label = "공중 vz %s t %s" % [c.vz, c.t]
				Pose.air_pose(T, fx.D, c.vz, c.t, c.attacking)
			"acc":
				label = "기울임 %s %s" % [c.accF, c.accS]
				Pose.acc_lean(T, c.accF, c.accS)
			"superman":
				label = "슈퍼맨 %s" % c.w
				Pose.overlay_t(T, Pose.SUPERMAN, c.w)
			"idle":
				label = "버릇 %s u %s" % [c.kind, c.u]
				Pose.idle_pose(T, c.kind, c.u, c.s, c.form)
		if not same_pose(T, c.T, label):
			bad += 1
			if bad > 3:
				return
	check(fx.cases.size() > 100, "경우 수")


func test_gait_table() -> void:
	for ch in C.FIGURE_CHARS:
		var g := Pose.gait_of(ch)
		for k in C.FIGURE_GAIT_DEFAULT:
			check(g.has(k), "%s 걸음 %s" % [ch, k])
	check(Pose.gait_of("tank").freq < 1.0, "탱크 느리게")


const Motion := preload("res://chars/figure_motion.gd")
const Moves := preload("res://chars/moves.gd")


func test_figure_motion_matches_js() -> void:
	var fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/figure_motion.json"))
	check(fx != null, "figure_motion.json")
	if fx == null:
		return
	var bad := 0
	for c in fx.cases:
		if bad > 3:
			return
		match c.fn:
			"rest":
				if not same_pose(Motion.rest_pose(c.d), c.P, "기본 자세"):
					bad += 1
			"spring":
				var P := Motion.rest_pose(c.d)
				var V := Motion.zero_pose(P)
				var k := 0
				for s in c.steps:
					Motion.spring_pose(P, V, s.T, s.dt, s.fast)
					k += 1
					if not same_pose(P, s.P, "스프링 %d 자세" % k) or not same_pose(V, s.V, "스프링 %d 속도" % k):
						bad += 1
						break
			"hit":
				var T := Motion.rest_pose(c.d)
				Motion.hit_pose(T, c.dx, c.dy, c["pow"])
				if not same_pose(T, c.T, "맞은 자세"):
					bad += 1
			"sway":
				var sw: Dictionary = c.start.duplicate()
				for s in c.seq:
					Motion.step_sway(sw, s.dt)
					if not same_pose(sw, s.sw, "휘청 dt %s" % s.dt):
						bad += 1
						break
			"overlay":
				var P := Motion.rest_pose(c.d)
				var V := Motion.zero_pose(P)
				for k in V:
					V[k] = [2.0, 2.0] if V[k] is Array else 2.0
				Motion.overlay(P, c.T, Moves.MOVES[c.move][c.part], c.w, V)
				if not same_pose(P, c.P, "덮기 %s %s %s" % [c.move, c.part, c.w]) or not same_pose(V, c.V, "덮기 속도 %s %s" % [c.move, c.part]):
					bad += 1
			"poseAt":
				var P := Motion.rest_pose(c.d)
				var T := Motion.rest_pose(c.d)
				var V := Motion.zero_pose(P)
				var end: float = INF if c.end == null else c.end
				Motion.pose_at(P, T, V, c.who, c.kind, c.t, end)
				if not same_pose(P, c.P, "포즈 %s %s t %s" % [c.who, c.kind, c.t]):
					bad += 1


func test_moves_table() -> void:
	check(Moves.MOVES.size() > 50, "MOVES %d" % Moves.MOVES.size())
	check(Moves.MOVES.has("punch") and Moves.MOVES["주먹"].has("W"), "punch·주먹")
	for who in ["tank", "ninja", "builder", "hook", "hunter", "cannon", "berserker", "bard", "metal"]:
		for kind in ["taunt", "victory"]:
			check(Moves.POSES[who][kind].has("S"), "%s %s" % [who, kind])
			if Moves.POSES[who][kind].loop:
				check(not Motion.pose_loop(who, kind, 0.4).is_empty(), "%s %s loop 옮김" % [who, kind])
