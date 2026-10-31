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


const Chars := preload("res://chars/chars.gd")


# 8명 몸이 만들어지고, 여러 상태 (걷기·공중·경직·공격·포즈) 로 몸 자세를 돌려도 값이 깨지지 않음 (Store 없이 _figure_anim·_apply 를 바로)
func test_bodies_build_and_animate() -> void:
	for ch in C.FIGURE_CHARS:
		var b = Chars.make_body(ch, Color(0.8, 0.3, 0.2))
		var meshes := b.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 60, "%s 조각 %d (옷·무기 포함)" % [ch, meshes.size()])
		var states := [
			{"walking": true, "air": false, "hs": 4.5, "walk": 1.3},
			{"walking": false, "air": true, "vz": -4.0},
			{"walking": false, "air": false, "stunned": true, "tumble": 0.7},
			{"walking": false, "air": false, "idle": 3.5},
			{"walking": false, "air": false, "act": {"id": 1, "move": "punch", "phase": "strike", "u": 0.5, "air": false}},
			{"walking": false, "air": false, "victory": 1.2},
			{"walking": false, "air": false, "emote": int(C.EMOTE_CHAR), "emoteT": 0.6},
			{"walking": false, "air": false, "hit": {"id": 3, "age": 0.01, "stop": 0.1, "dx": -1.0, "dy": 0.3, "pow": 1.5}},
			{"walking": false, "air": false, "dizzy": 0.7, "punch": 0.6},
			{"walking": false, "air": true, "whirl": 0.4, "glide": true, "amp": true},
		]
		for s in states:
			var st := {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "hit": null, "act": null, "accF": 3.0, "accS": -2.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "form": "", "loaded": false, "ammo": 3.0, "dizzy": 0.0, "punch": 0.0, "whirl": -1.0, "glide": false, "amp": false}
			st.merge(s, true)
			for k in 10:
				b._figure_anim(st, 1.0 / 60.0)
				b._apply(1.0 / 60.0)
			check(b._pose_ok(), "%s 자세 깨짐 %s" % [ch, str(s.keys())])
			check(is_finite(b.hips.position.y) and is_finite(b.shoulders[0].rotation.y), "%s 관절 %s" % [ch, str(s.keys())])
		b.free()


# 합친 몸 (chars_config MERGE): 몸 하나 그리는 메시 수가 조각 수보다 훨씬 적음
func test_bodies_merged() -> void:
	for ch in C.FIGURE_CHARS:
		var b = Chars.make_body(ch, Color(0.2, 0.6, 0.9))
		var pieces: int = b.piece_mat.size()
		var drawn := 0
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			if mi.layers != 0:
				drawn += 1
		if b.merged_count > 0:
			check(drawn * 2 < pieces, "%s 그리는 메시 %d / 조각 %d" % [ch, drawn, pieces])
		if b.skel != null:
			# 늘 보이는 관절은 뼈 → 보이는 메시 (조상까지 보이는 것) 가 몸 하나에 몇 개뿐
			var shown := 0
			for mi in b.find_children("*", "MeshInstance3D", true, false):
				var n: Node = mi
				var vis: bool = mi.layers != 0
				while vis and n != null:
					vis = (n as Node3D).visible if n is Node3D else true
					n = n.get_parent()
				if vis:
					shown += 1
			check(shown <= 16, "%s 보이는 메시 %d (뼈 %d)" % [ch, shown, b.bone_nodes.size()])
			check(b.bone_nodes.has(b.elbows[0]) and b.bone_nodes.has(b.neck), "%s 팔꿈치·목은 뼈" % ch)
			# 뼈 자세 = 노드의 frame 기준 자리 (움직인 뒤에도)
			b.elbows[0].rotation.y = 0.7
			b._sync_bones()
			var bi: int = b.bone_nodes.find(b.elbows[0])
			var t := Transform3D.IDENTITY
			var nn: Node = b.elbows[0]
			while nn != b.frame:
				t = (nn as Node3D).transform * t
				nn = nn.get_parent()
			check(b.skel.get_bone_pose(bi).origin.distance_to(t.origin) < 1e-4 and b.skel.get_bone_pose(bi).basis.x.distance_to(t.basis.x) < 1e-4, "%s 뼈 자세" % ch)
		b.free()


const VM := preload("res://chars/viewmodel.gd")


# 1인칭 팔: 8명 내 몸을 베껴 팔꿈치 아래·무기만 그리고, 한 프레임 따라가도 깨지지 않음 (화면 없이 _sync·_follow 를 바로)
func test_viewmodel_follows() -> void:
	for ch in C.FIGURE_CHARS:
		var vm = VM.new()
		vm._ready()
		var b = Chars.make_body(ch, Color(0.9, 0.4, 0.2))
		vm._sync(b)
		check(vm.twin != null and vm.pairs.size() > 5, "%s 베낄 노드 %d" % [ch, vm.pairs.size()])
		var drawn := 0
		for mi in vm.anchor.find_children("*", "MeshInstance3D", true, false):
			if mi.layers != 0:
				drawn += 1
		check(drawn > 0, "%s 1인칭에 그리는 조각 %d" % [ch, drawn])
		vm._follow(1.0 / 60.0)
		check(is_finite(vm.anchor.position.x) and is_finite(vm.twin.shoulders[0].rotation.y), "%s 자리" % ch)
		vm.twin.free()
		b.free()
		vm.free()
