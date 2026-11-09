# W7 구운 몸 (.glb, 레포 뿌리 tools/bake-bodies.mjs → assets/models/<캐릭터>.glb + .json, 불러오기 chars/baked.gd·baked_batch.gd):
# ① manifest·장면 이름이 맞음 ② 판 몸 (묶음)·1인칭 몸 (조각) 모두 예전 조립 (chars/data/bodies.bin = JS buildFigure) 과 보이는 정점 자리·색이 같음 (아무 자세에서도)
# ③ 노드·그리는 메시·뼈가 줄어듦 ④ 구운 몸이 없거나 이름이 안 맞으면 예전 조립 ⑤ 예전 조립 (use_glb 끔) 으로도 몸 테스트 (test_chars) 가 다 통과
extends RefCounted

const C := preload("res://core/config.gd")
const K := preload("res://chars/chars_config.gd")
const Chars := preload("res://chars/chars.gd")
const Body := preload("res://chars/body.gd")
const Baked := preload("res://chars/baked.gd")
const VM := preload("res://chars/viewmodel.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 구운 캐릭터 (지금 assets/models 에 있는 것)
static func baked_chars() -> Array:
	var out := []
	for ch in C.FIGURE_CHARS:
		if Baked.has_char(ch):
			out.append(ch)
	return out


func _body(ch: String, color: Color, merge: bool, glb: bool):
	var was: bool = Body.use_glb
	Body.use_glb = glb
	var b = Body.new()
	b.build(ch, color, merge)
	Body.use_glb = was
	return b


func test_baked_files() -> void:
	var list := baked_chars()
	check(list.has("tank"), "탱크 구운 몸 있음 (node tools/bake-bodies.mjs tank)")
	check(Baked.load_char("dummy") == null and Baked.load_char("없는캐릭터") == null, "없는 캐릭터는 null")
	for ch in list:
		var g: Dictionary = Baked.load_char(ch)
		var m: Dictionary = g.manifest
		var names := {}
		for e in m.nodes:
			names[e.name] = true
		check(names.size() == m.nodes.size(), "%s 노드 이름이 겹치지 않음" % ch)
		# 관절 이름 = body.gd 관절 (refs 키, [0] 오른쪽 · [1] 왼쪽)
		for nm in ["body", "rig", "hips", "waist", "neck", "torso", "shoulder_R", "shoulder_L", "elbow_R", "elbow_L", "hand_R", "hand_L", "thigh_R", "thigh_L", "knee_R", "knee_L", "foot_R", "foot_L"]:
			check(names.has(nm), "%s 관절 이름 %s" % [ch, nm])
		check(int(m.leafStart) <= int(m.batchStart) and int(m.batchStart) <= m.nodes.size(), "%s 잎·묶음 순서" % ch)
		for i in m.nodes.size():
			check(int(m.nodes[i].parent) < i, "%s 부모 번호 < 자식 번호 (%d)" % [ch, i])
			if i >= int(m.batchStart):
				check(m.nodes[i].get("batch", false) and i >= int(m.leafStart), "%s 맨 끝은 묶음 잎만 (%d)" % [ch, i])
		# 장면: frame 아래에서 manifest 순서대로 이름으로 다 찾음 + 뼈 'B_<노드 번호>' + 묶음 SkinnedMesh
		var root: Node3D = g.scene.instantiate()
		var frame := root.get_node_or_null("frame") as Node3D
		check(frame != null and frame.basis.is_equal_approx(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))), "%s frame 돌림 = 게임 → 고도" % ch)
		var found: Array = []
		for e in m.nodes:
			var par: Node = frame if int(e.parent) < 0 else found[int(e.parent)]
			var n: Node = par.get_node_or_null(NodePath(str(e.name))) if par != null else null
			check(n != null, "%s 노드 %s" % [ch, e.name])
			check(n == null or (n is MeshInstance3D) == e.has("mat"), "%s 메시 노드 %s" % [ch, e.name])
			found.append(n)
		var sk := frame.get_node_or_null("Skeleton3D") as Skeleton3D if frame != null else null
		check(sk != null and sk.get_bone_count() == m.bones.size(), "%s 뼈 %d" % [ch, sk.get_bone_count() if sk else -1])
		if sk != null:
			for b in sk.get_bone_count():
				check(sk.get_bone_name(b) == "B_%d" % int(m.bones[b].node), "%s 뼈 이름 %s" % [ch, sk.get_bone_name(b)])
		root.free()


# 보이는 정점 (frame 기준 자리, sRGB 색) — 묶음 (예전·구운) + 따로 그리는 조각
func _points(b) -> Array:
	var out := []
	var bt = b.batch
	if bt != null:
		var arr: Array = bt.mi.mesh.surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		if b.baked:
			var sv: Array = bt.skinned()
			var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
			var shown := {}
			for i in (sv[0] as PackedVector3Array).size():
				var bi: int = sv[1][i]
				if not shown.has(bi):
					shown[bi] = bt.shown(bt.pieces[bi])
				if shown[bi]:
					out.append([sv[0][i], b.skin_color if uv2[i].x > 0.5 else cols[i]])
		else:
			var got: PackedVector3Array = bt.skinned_vertices()
			var k := 0
			for p in bt.pieces:
				var n: int = p.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
				if bt.shown(p):
					for j in n:
						out.append([got[k + j], cols[k + j]])
				k += n
	for mi in b.frame.find_children("*", "MeshInstance3D", true, false):
		if mi.layers == 0 or (bt != null and mi == bt.mi) or not _shown(mi, b.frame):
			continue
		var m = mi.material_override
		var col: Color = (m as StandardMaterial3D).albedo_color if m is StandardMaterial3D else Color((m as ShaderMaterial).get_shader_parameter("albedo"))
		var rel := _rel(mi, b.frame)
		for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			out.append([rel * v, col])
	return out


static func _shown(n: Node3D, upto: Node3D) -> bool:
	while n != null and n != upto:
		if not n.visible:
			return false
		n = n.get_parent() as Node3D
	return true


static func _rel(n: Node3D, upto: Node3D) -> Transform3D:
	var t := Transform3D()
	while n != null and n != upto:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


# a 의 점마다 b 에 (거리 tol 안, 색 차 0.02 안) 짝이 있는지 — 못 찾은 수
static func _misses(a: Array, b: Array, tol: float) -> int:
	var cell := 0.01
	var grid := {}
	for p in b:
		var key := Vector3i((p[0] / cell).floor())
		if not grid.has(key):
			grid[key] = []
		grid[key].append(p)
	var miss := 0
	for p in a:
		var c := Vector3i((p[0] / cell).floor())
		var ok := false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for q in grid.get(c + Vector3i(dx, dy, dz), []):
						var ca: Color = p[1]
						var cb: Color = q[1]
						if (q[0] as Vector3).distance_to(p[0]) < tol and absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) < 0.02:
							ok = true
							break
					if ok:
						break
				if ok:
					break
			if ok:
				break
		if not ok:
			miss += 1
	return miss


func _same(a, b, msg: String) -> void:
	var pa := _points(a)
	var pb := _points(b)
	# 건축가 안전모 테: 구운 몸은 JS 값 (FIGURE_HAT_TRIM·contrast, manifest mats shadeK·contrast), 예전 조립 (bodies.bin) 은 근육 홈 값 → 예전 색을 JS 값으로 바꿔 비교
	for m in a.cd.mats:
		if m.get("shade", false) and (m.has("shadeK") or m.has("contrast")):
			var plain: Dictionary = m.duplicate()
			plain.erase("shadeK")
			plain.erase("contrast")
			var was: Color = Body._mat_color(plain, b.skin_color)
			var now: Color = Body._mat_color(m, a.skin_color)
			for q in pb: # 예전 묶음은 정점 색 (8비트) 으로 넣어서 오차 안에서
				var c: Color = q[1]
				if absf(c.r - was.r) + absf(c.g - was.g) + absf(c.b - was.b) < 0.02:
					q[1] = now
	var m1 := _misses(pa, pb, 2e-3)
	var m2 := _misses(pb, pa, 2e-3)
	check(pa.size() > 1000 and pb.size() > 1000, "%s: 정점 %d / %d" % [msg, pa.size(), pb.size()])
	check(m1 == 0 and m2 == 0, "%s: 구운 몸에만 %d / 예전 몸에만 %d (정점 %d / %d)" % [msg, m1, m2, pa.size(), pb.size()])


# 같은 자세를 둘 다에 (초상 길 → 도발 → 관절 비틀기 → 숨기기)
static func _drive(bs: Array) -> void:
	var p := {"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.3}
	for i in 30:
		for b in bs:
			b.pose(p, i * 16.0)
	p.emote = C.EMOTE_CHAR
	for i in 20:
		for b in bs:
			b.pose(p, 600.0 + i * 16.0)
	for b in bs:
		b.elbows[0].rotation = Vector3(0.4, -1.2, 0.3)
		b.neck.rotation.z = 0.8
		b.knees[1].rotation.y = 1.1
		b._sync_bones()


func test_baked_same_as_pieces() -> void:
	for ch in baked_chars():
		var col := Color(0.3, 0.7, 0.4)
		# 판·대기실·초상 몸 (묶음)
		var g = _body(ch, col, true, true)
		var o = _body(ch, col, true, false)
		check(g.baked and not o.baked and g.batch != null and o.batch != null, "%s 구운 몸 / 예전 몸" % ch)
		if not g.baked:
			g.free()
			o.free()
			continue
		_same(g, o, "%s 처음" % ch)
		_drive([g, o])
		_same(g, o, "%s 돌린 자세" % ch)
		# 숨긴 노드 (방패·망치 등) 가 묶음에서도 숨음
		var hid := 0
		for i in g.nodes.size():
			if not g.nodes[i].visible:
				hid += 1
		check(hid > 0, "%s 숨긴 노드 있음" % ch)
		g.rig.visible = false
		o.rig.visible = false
		g._sync_bones()
		o._sync_bones()
		check(_points(g).size() < 200, "%s rig 숨기면 묶음도 숨음 (%d)" % [ch, _points(g).size()])
		g.free()
		o.free()
		# 1인칭 팔 쪽 몸 (조각 그대로)
		g = _body(ch, col, false, true)
		o = _body(ch, col, false, false)
		check(g.baked and g.batch == null and g.frame.get_node_or_null("Skeleton3D") == null, "%s 조각 몸엔 묶음 없음" % ch)
		_drive([g, o])
		_same(g, o, "%s 조각 몸" % ch)
		g.free()
		o.free()


# 캐릭터별 부품 (manifest refs 로 이은 노드): 코드가 보이기·자세·재질을 바꾸는 부품을 다 켜도, 상태 (바드 메탈 폼·광전사 분노·포탄 수·갈고리 장전·어지러움) 를 바꿔도
# 판 몸 (묶음) 과 조각 몸 모두 예전 조립과 같은 정점·색. 매 프레임 뼈 맞추기 (_sync_bones) 만으로 묶음에 반영됨.
# 기준은 예전 '조각' 몸 (bodies.bin 노드 그대로): 예전 G3 묶음은 처음 숨긴 부품 (탱크 앞 방패·사냥꾼 손 활 등) 을 나중에 보이면 자리가 틀어짐 (G3 batch 의 기존 결함, 구운 몸엔 없음)
const STATES := [
	["bard", {"bard": {"form": "metal"}}],
	["bard", {"bard": {"form": "bard"}}],
	["berserker", {"damage": 999.0}],
	["cannon", {"cannon": {"ammo": 1}}],
	["cannon", {"cannon": {"ammo": 0}}],
	["hook", {"loaded": true}],
]


static func _show_parts(b) -> int:
	var dyn: Dictionary = b._dyn_nodes(b.cd)
	var n := 0
	for i in dyn:
		if not b.nodes[i].visible:
			b.nodes[i].visible = true
			n += 1
	b._sync_bones()
	return n


# 실제 시각 (Time.get_ticks_msec) 으로 움직이는 것 — 어지러움 별 돎·갈고리 장전 불꽃 깜빡임 — 은 두 몸을 다른 순간에 맞춰서 틀어질 수 있음 (컴퓨터가 바쁘면) → a 쪽 그대로 b 에
static func _same_clock(a, b) -> void:
	for i in mini(a.stars.size(), b.stars.size()):
		b.stars[i].transform = a.stars[i].transform
		b.stars[i].visible = a.stars[i].visible
	var ga = a.refs.get("gun")
	var gb = b.refs.get("gun")
	if ga is Dictionary and gb is Dictionary and ga.get("spark") != null and gb.get("spark") != null:
		var sb: Node3D = b._n(gb.spark)
		sb.visible = a._n(ga.spark).visible
	b._sync_bones()


func test_baked_special_parts() -> void:
	for ch in baked_chars():
		for merge in [true, false]:
			var g = _body(ch, Color(0.8, 0.5, 0.2), merge, true)
			var o = _body(ch, Color(0.8, 0.5, 0.2), false, false)
			var ng := _show_parts(g)
			var no := _show_parts(o)
			check(ng == no and ng > 0, "%s 숨긴 부품 수 %d / 예전 %d" % [ch, ng, no])
			_same(g, o, "%s 부품 다 보임 (%s)" % [ch, "판" if merge else "조각"])
			g.free()
			o.free()
		for s in STATES:
			if s[0] != ch:
				continue
			for merge in [true, false]:
				var g = _body(ch, Color(0.8, 0.5, 0.2), merge, true)
				var o = _body(ch, Color(0.8, 0.5, 0.2), false, false)
				var p: Dictionary = {"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.3}
				p.merge(s[1], true)
				for i in 12:
					for b in [g, o]:
						b.dizzy = C.BERSERK_DIZZY_S
						b.pose(p, i * 16.0)
				_same_clock(g, o)
				_same(g, o, "%s %s (%s)" % [ch, JSON.stringify(s[1]), "판" if merge else "조각"])
				g.free()
				o.free()


# 노드·그리는 메시·뼈가 예전 조립보다 적음, 묶음 메시는 몸끼리 같이 씀, 재질 (툰 피부색·외곽선)
func test_baked_lighter() -> void:
	for ch in baked_chars():
		var g = _body(ch, Color(0.9, 0.2, 0.2), true, true)
		var o = _body(ch, Color(0.9, 0.2, 0.2), true, false)
		var g2 = _body(ch, Color(0.1, 0.2, 0.9), true, true)
		var ng: int = g.find_children("*", "", true, false).size()
		var no: int = o.find_children("*", "", true, false).size()
		check(ng * 2 < no, "%s 노드 %d / 예전 %d" % [ch, ng, no])
		check(g.drawn.size() <= o.drawn.size(), "%s 그리는 메시 %d / 예전 %d" % [ch, g.drawn.size(), o.drawn.size()])
		check(g.batch.pieces.size() * 2 < o.batch.pieces.size(), "%s 뼈 %d / 예전 %d" % [ch, g.batch.pieces.size(), o.batch.pieces.size()])
		check(g.bone_dyn.size() <= g.batch.pieces.size(), "%s 매 프레임 뼈 %d" % [ch, g.bone_dyn.size()])
		check(g.batch.mi.mesh == g2.batch.mi.mesh, "%s 묶음 메시는 몸끼리 같이 씀" % ch)
		var m: ShaderMaterial = g.batch.mi.material_override
		check(m != g2.batch.mi.material_override and m.next_pass != null and m.get_shader_parameter("use_vertex_color"), "%s 몸마다 재질·외곽선" % ch)
		check(Color(m.get_shader_parameter("skin_tint")).is_equal_approx(Color(0.9, 0.2, 0.2, 1.0)), "%s 피부 = skin_tint" % ch)
		# 효과: 경직 하양 → skin_tint 하양, 끝나면 몸 색 (a 늘 1)
		g._fx_colors({"stunned": true})
		g._fx_colors({})
		check(Color(m.get_shader_parameter("skin_tint")).is_equal_approx(Color(0.9, 0.2, 0.2, 1.0)), "%s 효과 뒤 몸 색" % ch)
		# 반투명 (유령화): 투명 재질에도 피부색
		g.opacity = 0.5
		g._apply_opacity()
		var am: ShaderMaterial = preload("res://chars/ghost_depth.gd").inner(g.batch.mi.material_override)
		check(am != m and Color(am.get_shader_parameter("skin_tint")).a == 1.0, "%s 반투명 피부색" % ch)
		g.opacity = 1.0
		g._apply_opacity()
		check(g.batch.mi.material_override == m, "%s 반투명 끝" % ch)
		# 복제 (잔상): 묶음 메시가 같이 복제됨
		var snap: Node3D = g.snapshot(StandardMaterial3D.new())
		check(snap.find_children("*", "Skeleton3D", true, false).size() == 1, "%s 복제에 뼈" % ch)
		snap.free()
		for b in [g, o, g2]:
			b.free()


# 1인칭 팔: 구운 판 몸 (묶음) → 쌍둥이 (조각) — 베낄 노드는 판 몸 노드 표 안, 따라간 팔 자세·그리는 정점이 예전 조립 1인칭과 같음
func test_baked_viewmodel() -> void:
	for ch in baked_chars():
		var vms := []
		var bodies := []
		for glb in [true, false]:
			var was: bool = Body.use_glb
			Body.use_glb = glb
			var vm = VM.new()
			vm._ready()
			var b = Chars.make_body(ch, Color(0.9, 0.4, 0.2))
			vm._sync(b)
			Body.use_glb = was
			b.elbows[0].rotation = Vector3(0.3, -0.9, 0.2)
			b.shoulders[1].rotation = Vector3(-0.2, 0.7, 0.1)
			vm._follow(1.0 / 60.0)
			vms.append(vm)
			bodies.append(b)
		var vm = vms[0]
		var b = bodies[0]
		check(vm.twin.baked and vm.twin.batch == null and not vms[1].twin.baked, "%s 쌍둥이 = 구운 조각 몸" % ch)
		check(vm.pairs.size() > 5 and vm.pairs.all(func(i): return i < b.nodes.size()), "%s 베낄 노드 %d" % [ch, vm.pairs.size()])
		for k in 2:
			check(vm.twin.elbows[k].transform.is_equal_approx(vms[1].twin.elbows[k].transform) and vm.twin.shoulders[k].transform.is_equal_approx(vms[1].twin.shoulders[k].transform), "%s 팔 %d 자세 = 예전" % [ch, k])
		var pts := []
		for v in vms:
			var out := []
			for mi in v.anchor.find_children("*", "MeshInstance3D", true, false):
				if mi.layers == 0 or not _shown(mi, v.anchor):
					continue
				var m = mi.material_override
				var col: Color = (m as StandardMaterial3D).albedo_color if m is StandardMaterial3D else Color((m as ShaderMaterial).get_shader_parameter("albedo"))
				var rel := _rel(mi, v.anchor)
				for p in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					out.append([rel * p, col])
			pts.append(out)
		check(pts[0].size() > 100 and _misses(pts[0], pts[1], 2e-3) == 0 and _misses(pts[1], pts[0], 2e-3) == 0, "%s 1인칭 정점 %d / 예전 %d" % [ch, pts[0].size(), pts[1].size()])
		for k in 2:
			vms[k].twin.free()
			bodies[k].free()
			vms[k].free()


# 구운 몸이 없거나 (끔) manifest 이름이 장면과 안 맞으면 예전 조립
func test_baked_fallback() -> void:
	var o = _body("tank", Color.WHITE, true, false)
	check(not o.baked and o.batch != null and o.batch.get_script() != load("res://chars/baked_batch.gd"), "끄면 예전 조립")
	o.free()
	var g: Dictionary = Baked.load_char("tank")
	var bad: Dictionary = g.manifest.duplicate(true)
	bad.nodes[3].name = "없는노드"
	Baked._cache["tank"] = {"manifest": bad, "scene": g.scene}
	var b = Chars.make_body("tank", Color.WHITE)
	Baked._cache["tank"] = g
	check(not b.baked and b.hips != null and b.batch != null and b.nodes.size() == Body._data().chars.tank.nodes.size(), "이름이 안 맞으면 예전 조립")
	check(b.get_child_count() == 1, "예전 조립 frame 하나 (%d)" % b.get_child_count())
	b.free()


# 예전 조립 (구운 몸 끔) 으로 몸 테스트 (test_chars) 를 한 번 더
func test_chars_without_glb() -> void:
	var T = load("res://tests/test_chars.gd").new()
	var was: bool = Body.use_glb
	Body.use_glb = false
	for f in ["test_bodies_build_and_animate", "test_bodies_merged", "test_bodies_batch_pose", "test_body_fx_colors", "test_ragdoll_bodies", "test_viewmodel_follows"]:
		T.call(f)
	Body.use_glb = was
	for e in T.errors:
		errors.append("예전 조립: %s" % e)
