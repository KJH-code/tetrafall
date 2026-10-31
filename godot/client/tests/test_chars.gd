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
		if b.batch != null:
			# 툰 조각은 몸 한 메시 → 보이는 메시 (조상까지 보이는 것) 가 몸 하나에 몇 개뿐 (묶음 + 눈·체크 무늬·투명)
			var shown := 0
			for mi in b.find_children("*", "MeshInstance3D", true, false):
				var n: Node = mi
				var vis: bool = mi.layers != 0
				while vis and n != null:
					vis = (n as Node3D).visible if n is Node3D else true
					n = n.get_parent()
				if vis:
					shown += 1
			check(shown <= 16, "%s 보이는 메시 %d (묶은 조각 %d)" % [ch, shown, b.batch.pieces.size()])
		b.free()


# 묶은 몸 (K.SKIN): 대기실·초상 몸과 같은 길 (make_body → pose 여러 번, 장면 트리 밖) 뒤 아무 자세에서도 정점 자리 = 조각 그대로 (보이는 조각)
func test_bodies_batch_pose() -> void:
	for ch in C.FIGURE_CHARS:
		var b = Chars.make_body(ch, Color(0.3, 0.7, 0.4))
		if b.batch == null:
			b.free()
			continue
		var p := {"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}
		for i in 50:
			b.pose(p, i * 16.0) # 초상 (ui/portrait.gd) 과 같이
		_batch_same(b, "%s 초상 길" % ch)
		p.emote = C.EMOTE_CHAR # 대기실 큰 캐릭터 (char_stage) 의 도발
		for i in 30:
			b.pose(p, 800.0 + i * 16.0)
		b.elbows[0].rotation = Vector3(0.4, -1.2, 0.3)
		b.neck.rotation.z = 0.8
		b._sync_bones()
		_batch_same(b, "%s 돌린 자세" % ch)
		# 바드: 폼을 바꿔도 몸통은 묶음 밖 (재질이 바뀌는 조각)
		if ch == "bard":
			check(not b.batch.pieces.has(b.torso), "바드 몸통은 따로")
		b.free()


func _batch_same(b, msg: String) -> void:
	var got: PackedVector3Array = b.batch.skinned_vertices()
	var worst := 0.0
	var k := 0
	var n := 0
	for p in b.batch.pieces:
		var rel: Transform3D = b.batch.rel_of(p)
		var vs: PackedVector3Array = p.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var on: bool = b.batch.shown(p)
		for v in vs:
			if on and k < got.size():
				worst = maxf(worst, got[k].distance_to(rel * v))
				n += 1
			k += 1
	check(k == got.size() and n > 100, "%s: 정점 수 %d / %d (본 것 %d)" % [msg, got.size(), k, n])
	check(worst < 1e-3, "%s: 가장 먼 차 %f" % [msg, worst])


const VM := preload("res://chars/viewmodel.gd")


# 1인칭 팔: 8명 내 몸을 베껴 팔꿈치 아래·무기만 그리고, 한 프레임 따라가도 깨지지 않음 (화면 없이 _sync·_follow 를 바로)
# 몸 색 효과 (render.js bodyMat·mats 색): 피부만 (경직·조종권·점프·강화) / 몸 전체 (스킬 빛·F 준비·탱크 아머) + 묶음 재질에 들어감, 몸 복제
func test_body_fx_colors() -> void:
	var b = Chars.make_body("tank", Color(0.2, 0.4, 0.9))
	b.pid = 5
	var now := 100000.0
	var f: Array = b.fx_colors({"stunned": false}, now)
	check(f[0] == b.skin_color and f[1] == Color(0, 0, 0) and f[2] == Color(0, 0, 0), "평소 %s" % str(f))
	f = b.fx_colors({"stunned": true}, 70.0 * 10)
	check(f[0] == Color.WHITE and f[1].is_equal_approx(b._hex(0x664400)), "경직 하얗게 + 발광 %s" % str(f))
	f = b.fx_colors({"hasControl": true}, now)
	check(f[1].is_equal_approx(b._hex(0x005566)) and f[2] == Color(0, 0, 0), "조종권 = 피부만")
	f = b.fx_colors({"jumpLeft": 2.0}, now)
	check(f[1].is_equal_approx(b._hex(0x1a5a1a)), "점프 강화 초록")
	b.on_event({"type": "ult", "who": 5})
	f = b.fx_colors({}, Time.get_ticks_msec() * 1.0)
	check(f[2].is_equal_approx(b._hex(C.ULT_AURA_COLOR)) and f[1] == f[2], "필살기 빛 = 몸 전체")
	b.glow_until = -1e9
	b.on_event({"type": "charge", "who": 5})
	b.on_event({"type": "armor", "who": 5})
	f = b.fx_colors({}, Time.get_ticks_msec() * 1.0)
	check(f[2] == Color.WHITE, "아머 버틴 순간 하양")
	b.on_event({"type": "slam", "who": 5})
	b.on_event({"type": "skillWindup", "who": 5, "ms": 150})
	f = b.fx_colors({}, Time.get_ticks_msec() * 1.0)
	check(f[2].r > 0.5 and f[2].r == f[2].b, "F 준비 하얗게 %s" % str(f[2]))
	b.on_event({"type": "ult", "who": 6}) # 남의 이벤트는 안 받음
	b.windup_until = -1e9
	b._fx_colors({"hasControl": true})
	if b.batch != null:
		var bm: ShaderMaterial = b.batch.mi.material_override
		check(bm.get_shader_parameter("skin_emissive").is_equal_approx(b._hex(0x005566)) and bm.get_shader_parameter("emissive") == Color(0, 0, 0), "묶음 재질: 피부 발광만")
	# 복제: 굳은 복사본 (보이는 메시는 다 준 재질) · 한 겹 더
	var mat := StandardMaterial3D.new()
	var snap: Node3D = b.snapshot(mat)
	var n := 0
	for mi in snap.find_children("*", "MeshInstance3D", true, false):
		if mi.layers != 0:
			check(mi.material_override == mat, "복사본 재질")
			n += 1
	check(n > 0, "복사본 메시 %d" % n)
	b.set_overlay(mat)
	check(b.drawn.all(func(dr): return dr.mi.material_overlay == mat), "한 겹 더")
	b.set_overlay(null)
	snap.free()
	b.free()


const RM := preload("res://chars/ragdoll_math.gd")


static func _v(o) -> Vector3:
	return Vector3(o.x, o.y, o.z)


static func _q(o) -> Quaternion:
	return Quaternion(o.x, o.y, o.z, o.w)


static func _near(a: Vector3, b: Vector3) -> bool:
	return (a - b).length() <= 1e-3 * maxf(1.0, b.length())


# 래그돌 순수 계산 = JS client/ragdoll-math.js (모터 세기·쿼터니언 차이·관절 모터·골반·팔다리 끌어당김)
func test_ragdoll_math_matches_js() -> void:
	var fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ragdoll_math.json"))
	check(fx != null, "ragdoll_math.json")
	if fx == null:
		return
	var bad := 0
	for c in fx.motors:
		var st: Dictionary = c[0].duplicate()
		if st.sinceStun == null:
			st.sinceStun = INF
		var m := RM.motor(st)
		if absf(m.motor - c[1].motor) > 1e-6 or absf(m.snap - c[1].snap) > 1e-6:
			bad += 1
			check(false, "모터 %s → %s / JS %s" % [str(c[0]), str(m), str(c[1])])
	for c in fx.diffs:
		if not _near(RM.quat_diff_vec(_q(c[0]), _q(c[1])), _v(c[2])):
			bad += 1
			check(false, "쿼터니언 차이 %s" % str(c))
	for c in fx.pds:
		var a := RM.pd_angular(_q(c[0]), _q(c[1]), _v(c[2]), _v(c[3]), c[4])
		if not _near(a, _v(c[5])):
			bad += 1
			check(false, "관절 모터 %s / JS %s" % [str(a), str(c[5])])
	for c in fx.roots:
		var r := RM.root_pull(_v(c[0]), _v(c[1]), _v(c[2]), _v(c[3]), c[4])
		if r.snap != c[5].snap or (not r.snap and not _near(r.a, _v(c[5]))):
			bad += 1
			check(false, "골반 %s / JS %s" % [str(r), str(c[5])])
	for c in fx.limbs:
		var l := RM.limb_pull(_v(c[0]), _v(c[1]), _v(c[2]), _v(c[3]), c[4])
		if not _near(l, _v(c[5])):
			bad += 1
			check(false, "팔다리 %s / JS %s" % [str(l), str(c[5])])
	check(bad == 0 and fx.motors.size() == 60 and fx.roots.size() == 60, "래그돌 계산 %d 틀림" % bad)


const RagW := preload("res://chars/ragdoll.gd")


# 래그돌 (chars/ragdoll.gd): 판의 사람 몸만 켬 (초상·숨긴 몸은 끔), 조각 11·관절 10, 처음엔 목표 자세 그대로 (관절 회전 = figureAnim),
# 맞음·경직이면 힘이 빠짐, 끄면 물리에서 빠짐. 물리 걸음은 고도 틱이라 여기선 안 돎 (자세 계산·연결만)
func test_ragdoll_bodies() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var w = RagW.new()
	w.name = "TfRagdollsTest"
	root.add_child(w)
	RagW._inst = w
	for ch in C.RAGDOLL_CHARS:
		var b = Chars.make_body(ch, Color(0.5, 0.5, 0.9))
		root.add_child(b)
		var p := {"id": 3, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.4}
		b.pose(p, 0.0)
		check(w.has(b), "%s 래그돌 켬 (%s, 만든 수 %d)" % [ch, b.rag_why, w.made])
		var rag: Dictionary = w.rags.get(b, {})
		check(rag.get("segs", []).size() == 11 and rag.get("joints", []).size() == 10, "%s 조각 11·관절 10" % ch)
		if rag.is_empty():
			root.remove_child(b)
			b.free()
			continue
		# 처음 (fresh): 물리 자세 = 목표 → 관절 회전이 figureAnim 그대로
		var want := []
		for sg in rag.segs:
			want.append(RagW._joint_q(sg.joint))
		w.apply(b)
		var worst := 0.0
		for i in rag.segs.size():
			worst = maxf(worst, RM.quat_diff_vec(RagW._joint_q(rag.segs[i].joint), want[i]).length())
		check(worst < 1e-3, "%s 처음 자세 그대로 %f" % [ch, worst])
		check(rag.motor == 1.0, "%s 평소 모터 1" % ch)
		p.stunned = true
		b.pose(p, 16.0)
		check(rag.motor == C.RAGDOLL_STUN_MOTOR, "%s 경직 힘 빠짐 %f" % [ch, rag.motor])
		b.visible = false # 1인칭 내 몸 (World 가 숨김)
		b.pose(p, 32.0)
		check(not w.has(b), "%s 숨기면 끔" % ch)
		b.visible = true
		b.pose(p, 48.0)
		check(w.has(b), "%s 다시 켬" % ch)
		root.remove_child(b)
		check(not w.has(b), "%s 트리에서 빠지면 끔" % ch)
		b.free()
	# 초상·큰 캐릭터 몸 (id -1) 은 안 켬
	var pb = Chars.make_body("tank", Color.WHITE)
	root.add_child(pb)
	pb.pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}, 0.0)
	check(not w.has(pb), "초상 몸은 래그돌 아님")
	pb.free()
	check(w.rags.is_empty(), "남은 래그돌 없음")
	RagW._inst = null
	w.free()


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
		# 캐릭터별 1인칭 소품: 닌자 표창 3개 (단검은 숨김) · 대포수 포탄 · 광전사 아래팔 핏줄
		check((vm.star != null) == (ch == "ninja"), "%s 표창" % ch)
		if ch == "ninja":
			check(vm.star.get_child_count() == 3 and (vm.star.get_child(0) as MeshInstance3D).mesh.get_faces().size() == 8 * 4 * 3, "닌자 표창 3개·모양")
			b.star_at = Time.get_ticks_msec()
			vm._follow(1.0 / 60.0)
			check(not vm.star.visible, "닌자 던진 직후 빈손")
		check((vm.pips.size() > 0) == (ch == "cannon"), "%s 포탄 %d" % [ch, vm.pips.size()])
		check((vm.veins.size() == 2) == (ch == "berserker"), "%s 핏줄 %d" % [ch, vm.veins.size()])
		if ch == "cannon":
			b.cannon_kick_at = Time.get_ticks_msec()
			var sw: Array = vm._cannon_hold(null, vm.twin._n(vm.twin.refs.cannon))
			check(sw[1] > 0.1 and sw[2] > 0.9, "대포 반동 %s" % str(sw))
		vm.twin.free()
		b.free()
		vm.free()
