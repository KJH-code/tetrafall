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
