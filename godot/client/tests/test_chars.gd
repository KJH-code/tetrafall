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


# 묶은 몸 뼈 묶음 (사이클 5 u3, body.gd bone_groups): 같은 부모 사슬 (조각 위 → 부모 조각 바로 아래) 끼리 묶어 사슬은 한 번만 곱함.
# 8명 모두 묶음 뼈를 합치면 묶은 뼈 전체 (빠짐·겹침 없음), 묶음 사슬 = 그 묶음 뼈마다의 부모 사슬 = 묶음 link 에서 bone_links 를 위로 따라간 길, 묶음 수 50 이하
func test_bodies_bone_groups() -> void:
	var seen := 0
	for ch in C.FIGURE_CHARS:
		var b = Chars.make_body(ch, Color(0.3, 0.7, 0.4))
		check(b.batch != null, "%s 묶은 몸" % ch)
		if b.batch == null:
			b.free()
			continue
		seen += 1
		var n: int = b.batch.pieces.size()
		var got := {}
		var dup := 0
		var bad_chain := 0
		for g in b.bone_groups:
			check(g.bones.size() > 0 and g.bones.size() == g.pieces.size(), "%s 묶음 뼈 %d · 조각 %d" % [ch, g.bones.size(), g.pieces.size()])
			for k in mini(g.bones.size(), g.pieces.size()):
				var bi: int = g.bones[k]
				if got.has(bi):
					dup += 1
				got[bi] = true
				check(g.pieces[k] == b.batch.pieces[bi], "%s 뼈 %d 조각이 묶음 조각과 다름" % [ch, bi])
				var want := _parent_chain(b, bi)
				var same: bool = want.size() == g.chain.size()
				for j in mini(want.size(), g.chain.size()):
					same = same and want[j] == g.chain[j]
				if not same:
					bad_chain += 1
			# 노드마다 한 번 곱하는 길 (bone_links): 묶음 link 에서 위로 따라가면 묶음 사슬 그대로
			var walk := []
			var li: int = g.link
			while li >= 0 and walk.size() <= g.chain.size():
				walk.append(b.bone_links[li])
				li = b.bone_link_up[li]
			var same_walk: bool = walk.size() == g.chain.size()
			for j in mini(walk.size(), g.chain.size()):
				same_walk = same_walk and walk[j] == g.chain[j]
			if not same_walk:
				bad_chain += 1
		check(dup == 0 and got.size() == n, "%s 묶음 뼈 %d (겹침 %d) / 묶은 뼈 %d" % [ch, got.size(), dup, n])
		check(bad_chain == 0, "%s 묶음 사슬이 뼈의 부모 사슬과 다름 %d" % [ch, bad_chain])
		check(b.bone_groups.size() <= 50 and b.bone_groups.size() < n, "%s 묶음 %d (뼈 %d)" % [ch, b.bone_groups.size(), n])
		b.free()
	check(seen == C.FIGURE_CHARS.size(), "묶은 몸 %d / %d" % [seen, C.FIGURE_CHARS.size()])


# 묶음으로 맞춘 뼈 자세 = 예전 식 (조각부터 부모 사슬을 하나씩 곱하고 자리·돌림·크기 셋으로 나눔) 과 1e-4 안 (돌림은 쿼터니언 내적 |q·q'| ≥ 1−1e-6).
# 8명마다 걷기 + 도발 (test_bodies_batch_pose 와 같은 길) / 팔꿈치·목 돌림 / 사슬 중간 노드 하나 + 다른 묶음 조각 하나 숨김
func test_bodies_bone_groups_same_pose() -> void:
	for ch in C.FIGURE_CHARS:
		var b = Chars.make_body(ch, Color(0.3, 0.7, 0.4))
		if b.batch == null:
			check(false, "%s 묶은 몸" % ch)
			b.free()
			continue
		var p := {"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}
		for i in 50:
			p.x = 0.05 * i # 걷기
			b.pose(p, i * 16.0)
		p.emote = C.EMOTE_CHAR
		for i in 30:
			b.pose(p, 800.0 + i * 16.0)
		b._sync_bones()
		_bones_same_old(b, "%s 걷기·도발" % ch)
		b.elbows[0].rotation = Vector3(0.4, -1.2, 0.3)
		b.neck.rotation.z = 0.8
		b._sync_bones()
		_bones_same_old(b, "%s 팔꿈치·목 돌림" % ch)
		# 가장 긴 사슬의 가운데 노드 숨김 + 그 노드 밑이 아닌 다른 묶음의 보이는 조각 하나 숨김
		var long_g = null
		for g in b.bone_groups:
			if long_g == null or g.chain.size() > long_g.chain.size():
				long_g = g
		check(long_g != null and long_g.chain.size() >= 2, "%s 긴 사슬" % ch)
		if long_g == null or long_g.chain.is_empty():
			b.free()
			continue
		var mid: Node3D = long_g.chain[floori(long_g.chain.size() / 2.0)]
		var hid_bone := -1
		for pass_ in 2: # 먼저 숨긴 노드 밑이 아닌 묶음에서, 없으면 아무 다른 묶음에서 (숨긴 조각 뼈 크기는 사슬과 상관없이 bone_hide)
			for g in b.bone_groups:
				if hid_bone >= 0:
					break
				if is_same(g, long_g) or (pass_ == 0 and g.chain.has(mid)):
					continue
				for k in g.pieces.size():
					if g.pieces[k].visible and b.batch.shown(g.pieces[k]):
						hid_bone = g.bones[k]
						g.pieces[k].visible = false
						break
		check(hid_bone >= 0, "%s 숨길 조각" % ch)
		mid.visible = false
		b._sync_bones()
		_bones_same_old(b, "%s 사슬 노드·조각 숨김" % ch)
		var sk: Skeleton3D = b.bone_skel
		# 숨김 길을 실제로 탔는지: 숨긴 조각 뼈 크기 = bone_hide, 숨긴 노드 밑 뼈는 크기가 거의 0
		if hid_bone >= 0:
			var hs: Vector3 = sk.get_bone_pose_scale(hid_bone) - Vector3.ONE * b.bone_hide
			check(maxf(absf(hs.x), maxf(absf(hs.y), absf(hs.z))) < b.bone_hide * 0.01, "%s 숨긴 조각 뼈 크기 %s" % [ch, sk.get_bone_pose_scale(hid_bone)])
		check(absf(sk.get_bone_pose_scale(long_g.bones[0]).x) < 1e-3, "%s 숨긴 노드 밑 뼈 크기 %s" % [ch, sk.get_bone_pose_scale(long_g.bones[0])])
		b.free()


# 뼈 bi 의 부모 사슬: 조각 바로 위부터 부모 조각 (없으면 묶음 root) 바로 아래까지 (곱하는 순서)
func _parent_chain(b, bi: int) -> Array:
	var par: int = b.bone_skel.get_bone_parent(bi)
	var stop: Node = b.batch.pieces[par] if par >= 0 else b.batch.root
	var out := []
	var n: Node = b.batch.pieces[bi].get_parent()
	while n != null and n != stop:
		out.append(n)
		n = n.get_parent()
	return out


# 모든 묶은 뼈의 자세가 예전 식 (사슬을 조각부터 하나씩 곱해 자리·돌림·크기) 과 같은지
func _bones_same_old(b, msg: String) -> void:
	var sk: Skeleton3D = b.bone_skel
	var hide: float = b.bone_hide
	var hb := Transform3D(Basis().scaled(Vector3.ONE * hide), Vector3.ZERO)
	var worst_p := 0.0
	var worst_s := 0.0
	var worst_q := 1.0
	for bi in b.batch.pieces.size():
		var piece: Node3D = b.batch.pieces[bi]
		var xf := piece.transform
		for n in _parent_chain(b, bi):
			if not (n as Node3D).visible:
				xf = hb * xf
			xf = (n as Node3D).transform * xf
		var want_s: Vector3 = xf.basis.get_scale() if piece.visible else Vector3.ONE * hide
		var dp: Vector3 = (sk.get_bone_pose_position(bi) - xf.origin).abs()
		var ds: Vector3 = (sk.get_bone_pose_scale(bi) - want_s).abs()
		worst_p = maxf(worst_p, maxf(dp.x, maxf(dp.y, dp.z)))
		worst_s = maxf(worst_s, maxf(ds.x, maxf(ds.y, ds.z)))
		worst_q = minf(worst_q, absf(sk.get_bone_pose_rotation(bi).dot(xf.basis.get_rotation_quaternion())))
	check(worst_p <= 1e-4 and worst_s <= 1e-4, "%s: 자리 차 %.7f · 크기 차 %.7f" % [msg, worst_p, worst_s])
	check(worst_q >= 1.0 - 1e-6, "%s: 돌림 |내적| %.9f" % [msg, worst_q])


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
		b.rag_test = true # 테스트 러너 (_initialize) 에선 root 에 넣어도 트리 안이 아님
		root.add_child(b)
		var p := {"id": -2, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.4}
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
		# KO 슬로모션: 시간 배율이 바뀌면 엔진 속도도 그 배율로 (힘은 ×배율² — 걸음에서)
		var rb: RID = rag.segs[1].body
		PhysicsServer3D.body_set_state(rb, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3(2, 0, 0))
		w.set_time_scale(0.25)
		var v: Vector3 = PhysicsServer3D.body_get_state(rb, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		check(absf(v.x - 0.5) < 1e-4 and w.ts == 0.25, "%s 슬로모션 속도 %s" % [ch, str(v)])
		w.set_time_scale(1.0)
		check(absf((PhysicsServer3D.body_get_state(rb, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3).x - 2.0) < 1e-4, "%s 슬로모션 끝 속도 되돌림" % ch)
		# 쉬기: 모터가 다 센 채로 RAGDOLL_SLEEP_MS 지나면 강체를 멈추고 figureAnim 자세 그대로, 경직이면 바로 깸
		rag.calm_at = -1e9
		b.pose(p, 8.0)
		check(not rag.awake, "%s 평소엔 쉼" % ch)
		p.stunned = true
		b.pose(p, 16.0)
		check(rag.motor == C.RAGDOLL_STUN_MOTOR, "%s 경직 힘 빠짐 %f" % [ch, rag.motor])
		check(rag.awake, "%s 경직이면 깸" % ch)
		b.visible = false # 1인칭 내 몸 (World 가 숨김)
		b.pose(p, 32.0)
		check(not w.has(b), "%s 숨기면 끔" % ch)
		b.visible = true
		b.pose(p, 48.0)
		check(w.has(b), "%s 다시 켬" % ch)
		root.remove_child(b)
		b.free()
		check(w.rags.is_empty(), "%s 몸을 지우면 끔" % ch)
	# 초상·큰 캐릭터 몸 (자기 SubViewport, rag_test 아님) 은 안 켬
	var pb = Chars.make_body("tank", Color.WHITE)
	var sv := SubViewport.new()
	sv.add_child(pb)
	pb.pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}, 0.0)
	check(not w.has(pb), "초상 몸은 래그돌 아님 (%s)" % pb.rag_why)
	sv.free()
	check(w.rags.is_empty(), "남은 래그돌 없음")
	RagW._inst = null
	w.free()


# 연습 방 허수아비 몸 (character.js buildDummy): 관절 없이 나무·자루·짚, 목 손수건 = 플레이어 색, 묶음 하나, 움직임은 기울기·구르기만, 이벤트는 무시
func test_dummy_body() -> void:
	var b = Chars.make_body("dummy", Color(0.9, 0.2, 0.2))
	check(b.dummy and b.hips == null and b.rig != null, "허수아비 몸")
	check(b.nodes.size() >= 30 and b.batch != null, "허수아비 조각 %d·묶음" % b.nodes.size())
	var p := {"id": -5, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "stunned": true}
	for i in 30:
		p.x = i * 0.2
		b.pose(p, i * 16.0)
	check(b.dummy_spin < -0.5, "경직 중 빨리 날아가면 구름 %f" % b.dummy_spin)
	p.stunned = false
	for i in 60:
		b.pose(p, 600.0 + i * 16.0)
	check(absf(fmod(b.dummy_spin, TAU)) < 0.05 or absf(absf(fmod(b.dummy_spin, TAU)) - TAU) < 0.05, "멈추면 섬 %f" % b.dummy_spin)
	# 표식 번쩍 (B4 가 glow_until·glow_color 를 켬) → 허수아비 묶음 재질도 발광
	b.glow_until = Time.get_ticks_msec() + 500.0
	b.glow_color = Color(1, 0, 0)
	b.pose(p, 2000.0)
	var bm: ShaderMaterial = b.batch.mi.material_override
	check(bm.get_shader_parameter("emissive") == Color(1, 0, 0), "허수아비 표식 번쩍")
	b.on_event({"type": "hit", "target": -5, "who": 1})
	b.on_event({"type": "attack", "who": -5})
	b.free()


# 몸 자세 전체 = JS figureAnim (fixtures/figure_anim.json): 8명 × 장면 (가만히·걷기·평타 1·2·3·스킬 동작·도발·승리·맞음·경직·공중), 3 프레임마다 관절 쿼터니언·엉덩이 높이.
# 장면마다 가장 큰 각 차이 (라디안) 를 메시지에 — 다른 곳 찾기 표
func test_figure_anim_matches_js() -> void:
	var fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/figure_anim.json"))
	check(fx != null, "figure_anim.json")
	if fx == null:
		return
	var dt: float = fx.dt
	var bad := []
	for c in fx.cases:
		var b = Chars.make_body(c.ch, Color.WHITE)
		var joints: Array = [b.hips, b.waist, b.neck, b.shoulders[0], b.shoulders[1], b.elbows[0], b.elbows[1], b.thighs[0], b.thighs[1], b.knees[0], b.knees[1]]
		var names := ["엉덩이", "허리", "목", "어깨R", "어깨L", "팔꿈치R", "팔꿈치L", "허벅지R", "허벅지L", "무릎R", "무릎L"]
		var worst := 0.0
		var where := ""
		var si := 0
		for k in c.frames.size():
			var st: Dictionary = fx.base.duplicate(true)
			st.merge(c.frames[k], true)
			st.t = 1.0 + (k + 1) * dt
			st.merge({"form": "", "loaded": false, "ammo": 3.0}, false)
			b._figure_anim(st, dt)
			b._apply(dt)
			if si < c.steps.size() and int(c.steps[si].k) == k:
				var sp: Dictionary = c.steps[si]
				si += 1
				for j in joints.size():
					var q: Quaternion = (joints[j] as Node3D).quaternion
					var e: Array = sp.q[j]
					var d := 2.0 * acos(clampf(absf(q.x * e[0] + q.y * e[1] + q.z * e[2] + q.w * e[3]), 0.0, 1.0))
					if d > worst:
						worst = d
						where = "%s 프레임 %d" % [names[j], k]
				var dz := absf(b.hips.position.z - float(sp.hz))
				if dz * 10.0 > worst:
					worst = dz * 10.0
					where = "엉덩이 높이 %.3f 프레임 %d" % [dz, k]
		if worst > 0.03:
			bad.append("%s %s %.3f (%s)" % [c.ch, c.name, worst, where])
		b.free()
	check(bad.is_empty(), "JS figureAnim 과 다른 장면 %d개: %s" % [bad.size(), "; ".join(bad)])


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
