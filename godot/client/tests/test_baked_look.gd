# c6-u1 구운 몸 화풍 맞추기 (chars/baked_look.gd, 표 baked_look_config.gd, 설명 chars/BAKE.md '화풍 맞추기'):
# 살은 살색·플레이어 색은 옷 칸만 (묶음 메시 사본의 정점 색·UV2.x), 작은 눈, 외부 모델과 같은 툰 단·림·얇은 외곽선. 끄면 (Body.use_look) 예전 그대로.
# 러너는 use_look 을 끈 채로 돌림 (예전 구운 몸 테스트가 그대로 보게) — 여기 테스트는 스스로 켜고 끝에 되돌림
extends RefCounted

const C := preload("res://core/config.gd")
const WC := preload("res://world/world_config.gd")
const G3 := preload("res://shaders/g3.gd")
const GK := preload("res://shaders/g3_config.gd")
const Body := preload("res://chars/body.gd")
const Baked := preload("res://chars/baked.gd")
const Look := preload("res://chars/baked_look.gd")
const LK := preload("res://chars/baked_look_config.gd")
const GhostDepth := preload("res://chars/ghost_depth.gd")

const RED := Color(0.9, 0.2, 0.2)
const PIECE_POS_EPS := 1e-4 # 조각 사본 정점 자리 허용 오차 (칸) — 압축 메시를 다시 담는 양자화 (실측 최대 7e-6)
const BLUE := Color(0.1, 0.2, 0.9)

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 판 몸 (묶음) 하나 — look 켬/끔. 외부 모델은 러너가 꺼 둠 (여기서도 끔)
func _body(ch: String, color: Color, look: bool):
	var was_l: bool = Body.use_look
	var was_e: bool = Body.use_ext
	Body.use_look = look
	Body.use_ext = false
	var b = Body.new()
	b.build(ch, color, true)
	Body.use_look = was_l
	Body.use_ext = was_e
	return b


func _geo(b) -> Dictionary:
	return Look.geometry(b.batch.mi.mesh, b.batch.mi.skin, b.batch.skel, b.cd)


static func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# 삼각형 변마다 |사본 변 − k × 원본 변| 의 가장 큰 값 (모양 그대로 k 배면 0)
static func _edge_ratio_off(vo: PackedVector3Array, vb: PackedVector3Array, idx: PackedInt32Array, k: float) -> float:
	var worst := 0.0
	for t in idx.size() / 3:
		for j in 3:
			var a := idx[t * 3 + j]
			var b := idx[t * 3 + (j + 1) % 3]
			worst = maxf(worst, absf(vb[a].distance_to(vb[b]) - k * vo[a].distance_to(vo[b])))
	return worst


# 삼각형으로 이어진 덩어리마다 상자 [작은 모서리, 큰 모서리] (테스트 제 셈 — 구현의 eye_sides 를 안 씀)
static func _eye_boxes(vs: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var label := PackedInt32Array()
	label.resize(vs.size())
	for v in vs.size():
		label[v] = v
	var changed := true
	while changed: # 삼각형 안 세 정점의 가장 작은 번호로 번지게 (수렴할 때까지)
		changed = false
		for t in idx.size() / 3:
			var m := mini(label[idx[t * 3]], mini(label[idx[t * 3 + 1]], label[idx[t * 3 + 2]]))
			for j in 3:
				if label[idx[t * 3 + j]] != m:
					label[idx[t * 3 + j]] = m
					changed = true
	var box := {}
	for v in vs.size():
		if not box.has(label[v]):
			box[label[v]] = [vs[v], vs[v]]
		else:
			box[label[v]][0] = (box[label[v]][0] as Vector3).min(vs[v])
			box[label[v]][1] = (box[label[v]][1] as Vector3).max(vs[v])
	return box.values()


# 표: 구운 8명 전부, 값 범위, 뼈·재질 이름이 manifest 에 있음, 선·단 값 = 외부 모델 json
func test_look_table_all_baked() -> void:
	check(C.FIGURE_CHARS.size() == 8, "캐릭터 8명")
	for ch in C.FIGURE_CHARS:
		check(Baked.has_char(ch) and Look.has_char(ch), "%s 구운 몸·표 있음" % ch)
	check(not Look.has_char("dummy"), "허수아비는 표에 없음")
	for ch in LK.LOOK:
		var lk: Dictionary = LK.LOOK[ch]
		var g = Baked.load_char(ch)
		if g == null:
			check(false, "%s 구운 몸 없음" % ch)
			continue
		var cd: Dictionary = g.manifest
		var bones := {} # 묶음 뼈 이름
		for bn in cd.bones:
			bones[str(cd.nodes[int(bn.node)].name)] = true
		check(int(lk.flesh) > 0 and int(lk.flesh) <= 0xffffff, "%s 살색 값" % ch)
		check(float(lk.eye_scale) > 0.3 and float(lk.eye_scale) <= 1.0, "%s 눈 배율 %s" % [ch, lk.eye_scale])
		var roles: Dictionary = lk.get("roles", {})
		for bone in roles:
			check(bone == "*" or bones.has(bone), "%s roles 뼈 %s 가 묶음에 있음" % [ch, bone])
			check(roles[bone] in ["flesh", "player", "keep"], "%s roles %s 값" % [ch, bone])
		for key in ["split", "wide"]:
			var tb: Dictionary = lk.get(key, {})
			for bone in tb:
				var r: Array = tb[bone]
				check(bones.has(bone) and r.size() == 3 and r[1] in ["flesh", "player", "keep"] and r[2] in ["flesh", "player", "keep"] and r[1] != r[2], "%s %s %s" % [ch, key, bone])
				check(key == "split" or not lk.get("split", {}).has(bone), "%s %s 뼈는 split·wide 하나만" % [ch, bone])
		for key in ["promote", "bare"]:
			for e in lk.get(key, []):
				var m: Dictionary = cd.mats[int(e[1])] if int(e[1]) < cd.mats.size() else {}
				check(bones.has(str(e[0])) and m.get("kind") == "toon" and not m.get("skin", false) and not m.get("shade", false), "%s %s %s" % [ch, key, e])
	# 외부 모델 json 과 같은 선·단
	var ep := "res://assets/models/ext/tank.json"
	if FileAccess.file_exists(ep):
		var ej: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ep))
		var ts: Array = ej.toon_steps
		check(Vector3(ts[0], ts[1], ts[2]).is_equal_approx(LK.TOON_STEPS), "툰 단 = 외부 모델")
		check(is_equal_approx(float(ej.rim[0]), float(LK.RIM[0])) and is_equal_approx(float(ej.rim[1]), float(LK.RIM[1])), "림 = 외부 모델")
		check(is_equal_approx(float(ej.rim_tint[0]), float(LK.RIM_TINT[0])) and is_equal_approx(float(ej.rim_tint[1]), float(LK.RIM_TINT[1])), "림 틴트 = 외부 모델 (c7-u1)")
		check(is_equal_approx(float(ej.outline), LK.OUTLINE), "외곽선 배율 = 외부 모델")
	check(LK.TOON_STEPS == Vector3(0.7, 0.86, 1.0) and LK.RIM == [0.22, 4.0] and LK.OUTLINE == 0.45, "선·단 값 (c7-u1: 림 지수 3 → 4)")


# 몸마다 플레이어 칸 넓이 10~40% (처음 보이는 묶음 삼각형 기준), 얼굴·손은 살색
func test_look_player_area() -> void:
	for ch in LK.LOOK:
		var b = _body(ch, RED, true)
		var g := _geo(b)
		var a := Look.area(g, g.u2, Look.shown_names(b.cd))
		var f: float = a[0] / a[1]
		check(f >= LK.PLAYER_AREA[0] and f <= LK.PLAYER_AREA[1], "%s 플레이어 칸 %.1f%% (10~40%%)" % [ch, f * 100.0])
		# 얼굴 (목 뼈에서 가장 아래부터 시작하는 피부 조각 = 머리) 과 손은 살색 정점
		var flesh := Look.rgb8(Look.hex(int(LK.LOOK[ch].flesh)))
		var seen := {}
		for v in g.vs.size():
			if Look.rgb8(g.cs[v]) == flesh and g.u2[v].x < 0.5:
				seen[g.names[g.bone[v]]] = true
		check(seen.has("neck"), "%s 얼굴 살색" % ch)
		check(seen.has("hand_R") or seen.has("hand_L"), "%s 손 살색" % ch)
		# 손 뼈에서 가장 큰 공 (피부 손을 덮는 장갑 공이 있으면 그 공 = 보이는 주먹) 이 플레이어 색이 아님 — 대포수는 그 공이 살색 (bare)
		for hand in ["hand_R", "hand_L"]:
			var flags := PackedByteArray()
			flags.resize(g.vs.size())
			var any := false
			for v in g.vs.size():
				if g.names[g.bone[v]] == hand:
					flags[v] = 1 if g.u2[v].x > 0.5 else (2 if Look.rgb8(g.cs[v]) == flesh else 3)
					any = true
			if not any:
				continue # 갈고리 왼손은 갈고리
			var ps := Look.pieces(g, flags)
			var big := -1
			var big_w := 0.0
			for r in ps.box:
				var bx: Array = ps.box[r]
				var w: float = minf(bx[1].x - bx[0].x, minf(bx[1].y - bx[0].y, bx[1].z - bx[0].z))
				if w > big_w:
					big_w = w
					big = r
			check(big >= 0 and flags[big] != 1, "%s %s 보이는 주먹이 플레이어 색이 아님" % [ch, hand])
			if ch == "cannon":
				check(flags[big] == 2, "대포수 %s 주먹 (장갑 공) 살색" % hand)
		b.free()


# 살색이 플레이어 색·팀 색 어느 것과도 헷갈리지 않음 (RGB 거리)
func test_look_flesh_far_from_palette() -> void:
	var cols := []
	for v in C.PLAYER_PALETTE:
		cols.append(Look.hex(int(v)))
	for team in WC.TEAM_COLORS:
		for v in WC.TEAM_COLORS[team]:
			cols.append(Look.hex(int(v)))
	check(cols.size() == 14 + 8, "플레이어 14색 + 팀 8색 (%d)" % cols.size())
	for ch in LK.LOOK:
		var f := Look.hex(int(LK.LOOK[ch].flesh))
		for c in cols:
			check(_dist(f, c) >= LK.FLESH_MIN_DIST, "%s 살색 #%s ↔ #%s 거리 %.3f" % [ch, f.to_html(false), c.to_html(false), _dist(f, c)])


# 사본은 원본과 같은 모양: 정점 수·자리·법선·뼈·가중치·삼각형·형식이 같고, 바뀐 건 피부 정점과 promote 정점의 색·UV2.x 뿐
func test_look_same_shape() -> void:
	for ch in LK.LOOK:
		var b = _body(ch, RED, true)
		var o = _body(ch, RED, false)
		var mb: ArrayMesh = b.batch.mi.mesh
		var mo: ArrayMesh = o.batch.mi.mesh
		check(mb != mo and b.batch.mi.skin == o.batch.mi.skin, "%s 사본 메시·같은 스킨" % ch)
		check(mb.get_surface_count() == 1 and mb.surface_get_format(0) == mo.surface_get_format(0), "%s 표면 하나·같은 형식" % ch)
		check(mb.get_aabb().is_equal_approx(mo.get_aabb()), "%s 같은 상자" % ch)
		var ab: Array = mb.surface_get_arrays(0)
		var ao: Array = mo.surface_get_arrays(0)
		for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX, Mesh.ARRAY_TEX_UV]:
			check(ab[k] == ao[k], "%s 배열 %d 같음" % [ch, k])
		var nb: PackedVector3Array = ab[Mesh.ARRAY_NORMAL]
		var no: PackedVector3Array = ao[Mesh.ARRAY_NORMAL]
		var worst := 0.0
		for v in mini(nb.size(), no.size()):
			worst = maxf(worst, (nb[v] - no[v]).length())
		check(nb.size() == no.size() and worst < 1e-3, "%s 법선 같음 (%.5f)" % [ch, worst])
		var cb: PackedColorArray = ab[Mesh.ARRAY_COLOR]
		var co: PackedColorArray = ao[Mesh.ARRAY_COLOR]
		var ub: PackedVector2Array = ab[Mesh.ARRAY_TEX_UV2]
		var uo: PackedVector2Array = ao[Mesh.ARRAY_TEX_UV2]
		var flesh := Look.rgb8(Look.hex(int(LK.LOOK[ch].flesh)))
		var bad := 0
		var n_flesh := 0
		var n_promote := 0
		var n_bare := 0
		var bare_cols := {} # bare 로 살색이 될 수 있는 원래 색 (그 재질 색)
		var bare_bones := {}
		for e in LK.LOOK[ch].get("bare", []):
			bare_cols[int(b.cd.mats[int(e[1])].color)] = true
			bare_bones[str(e[0])] = true
		var gb := _geo(b)
		for v in co.size():
			var same: bool = Look.rgb8(cb[v]) == Look.rgb8(co[v]) and ub[v].is_equal_approx(uo[v])
			if same:
				continue
			if uo[v].x > 0.5: # 피부 정점 → 살색 (UV2.x 0)
				n_flesh += 1
				if Look.rgb8(cb[v]) != flesh or ub[v].x > 0.5:
					bad += 1
			elif ub[v].x > 0.5: # promote → 흰색 + UV2.x 1
				n_promote += 1
				if Look.rgb8(cb[v]) != 0xffffff:
					bad += 1
			else: # bare → 살색, UV2.x 는 0 그대로 — 표에 적은 뼈·재질 색 정점만
				n_bare += 1
				if Look.rgb8(cb[v]) != flesh or not bare_cols.has(Look.rgb8(co[v])) or not bare_bones.has(gb.names[gb.bone[v]]):
					bad += 1
		check(bad == 0 and n_flesh > 0, "%s 바뀐 정점은 살색·플레이어 칸뿐 (어긋남 %d, 살 %d, 올림 %d, 맨살 %d)" % [ch, bad, n_flesh, n_promote, n_bare])
		check((n_promote > 0) == LK.LOOK[ch].has("promote"), "%s promote 정점 %d" % [ch, n_promote])
		check((n_bare > 0) == LK.LOOK[ch].has("bare"), "%s bare 정점 %d" % [ch, n_bare])
		# 묶음 정점이 지금 자세에서 같은 자리 (뼈 맞추기 그대로)
		var sb: PackedVector3Array = b.batch.skinned_vertices()
		var so: PackedVector3Array = o.batch.skinned_vertices()
		var far := 0.0
		for v in mini(sb.size(), so.size()):
			far = maxf(far, (sb[v] - so[v]).length())
		# 눈썹 (광전사) 만 눈 쪽으로 옮겨 줄임 — 나머지는 그대로
		check(sb.size() == so.size() and far < (0.1 if ch == "berserker" else 1e-5), "%s 자세 정점 (%.5f)" % [ch, far])
		b.free()
		o.free()


# 끄면 예전 구운 몸 그대로: 원본 메시 (.glb 것)·예전 툰 단·굵은 외곽선·눈 크기
func test_look_off_is_old() -> void:
	for ch in LK.LOOK:
		var o = _body(ch, RED, false)
		var src: Node3D = Baked.load_char(ch).scene.instantiate()
		var src_mesh: Mesh = null
		for c in src.get_node("frame/Skeleton3D").get_children():
			if c is MeshInstance3D:
				src_mesh = c.mesh
		check(o.batch.mi.mesh == src_mesh and not o.batch.look, "%s 끄면 .glb 메시 그대로" % ch)
		var m: ShaderMaterial = o.batch.mi.material_override
		check(Vector3(m.get_shader_parameter("toon_steps")).is_equal_approx(GK.TOON_STEPS), "%s 끄면 예전 툰 단" % ch)
		check(m.get_shader_parameter("rim_strength") == null or float(m.get_shader_parameter("rim_strength")) == 0.0, "%s 끄면 림 없음" % ch)
		check(not G3.outline_on or m.next_pass == G3.shared_outline(C.OUTLINE_THICKNESS), "%s 끄면 예전 외곽선" % ch)
		var en := Look.eye_nodes(o.cd)
		check(en.white.size() > 0 and en.pupil.size() > 0, "%s 눈 노드 찾음" % ch)
		for i in en.white + en.pupil:
			var mi := o.nodes[i] as MeshInstance3D
			var sn := src.find_child(str(o.cd.nodes[i].name), true, false) as MeshInstance3D
			check(mi != null and sn != null and mi.mesh == sn.mesh and mi.scale.is_equal_approx(sn.scale), "%s 끄면 눈 %s 그대로" % [ch, o.cd.nodes[i].name])
		# 켰다 꺼도 (캐시가 있어도) 끈 몸은 원본
		var b = _body(ch, RED, true)
		var o2 = _body(ch, RED, false)
		check(b.batch.look and b.batch.mi.mesh != src_mesh and o2.batch.mi.mesh == src_mesh, "%s 켠 뒤에도 끈 몸은 원본" % ch)
		for x in [o, b, o2]:
			x.free()
		src.free()
	# 조각 몸 (1인칭 팔 쌍둥이) 은 묶음이 없음 — 화풍은 조각 사본으로 (test_look_pieces_first_person). 허수아비는 look 과 상관없음
	var was: bool = Body.use_look
	Body.use_look = true
	var p = Body.new()
	p.build("tank", RED, false)
	check(p.batch == null and p.baked, "조각 몸은 묶음 없음")
	p.free()
	var d = Body.new()
	d.build("dummy", RED, true)
	check(d.batch == null or d.batch.get("look") != true, "허수아비는 look 없음")
	d.free()
	Body.use_look = was


# 조각 몸 (1인칭 팔 쌍둥이 — merge 끔) 하나. 외부 모델은 ext 로
func _pieces(ch: String, color: Color, look: bool, ext := false):
	var was_l: bool = Body.use_look
	var was_e: bool = Body.use_ext
	Body.use_look = look
	Body.use_ext = ext
	var b = Body.new()
	b.build(ch, color, false)
	Body.use_look = was_l
	Body.use_ext = was_e
	return b


# 정점 하나의 칸: "P" 플레이어 색 (UV2.x 1 → skin_tint) · 아니면 정점 색 (살색·옷 색) 16진
static func _cell(c: Color, u2x: float) -> String:
	return "P" if u2x > 0.5 else "%06x" % Look.rgb8(c)


# c6 리뷰 F2: 1인칭 팔 (조각 몸) 도 화풍 맞추기 — 예전엔 묶음 몸만 바꿔서 내 팔·주먹만 플레이어 색으로 남았음 (같은 화면의 초상·3인칭 몸은 살색).
# 조각 몸의 칸 (뼈마다 플레이어 색·살색·옷 색 정점 수) 이 묶음 사본과 똑같고, 손 조각은 살색 정점 + 정점 색 툰 재질 (skin_tint = 플레이어 색), 끄면 (--no-look) 예전 그대로
func test_look_pieces_first_person() -> void:
	for ch in LK.LOOK:
		var flesh: int = int(LK.LOOK[ch].flesh)
		var p = _pieces(ch, RED, true)
		var o = _pieces(ch, RED, false)
		var b = _body(ch, RED, true)
		var cd: Dictionary = p.cd
		check(p.baked and p.batch == null and p.look_mat != null and o.look_mat == null, "%s 조각 몸: 화풍 재질 (켬 %s · 끔 %s)" % [ch, p.look_mat, o.look_mat])
		if p.look_mat == null:
			for x in [p, o, b]:
				x.free()
			continue
		# 묶음 사본의 칸: 뼈 이름 | 칸 → 정점 수
		var g := _geo(b)
		var want := {}
		for v in g.vs.size():
			var k: String = "%s|%s" % [g.names[g.bone[v]], _cell(g.cs[v], g.u2[v].x)]
			want[k] = int(want.get(k, 0)) + 1
		# 조각 몸의 칸: 사본 조각은 정점 색·UV2, 그대로인 조각은 재질 (피부 재질 = 플레이어 색, 아니면 재질 색)
		var got := {}
		var copies := 0
		var bad_shape := 0
		var bad_mat := 0
		var kept_bad := 0
		for i in cd.nodes.size():
			var bone := Look.piece_bone(cd, i)
			if bone == "":
				continue
			var mi := p.nodes[i] as MeshInstance3D
			var om := o.nodes[i] as MeshInstance3D
			var arr: Array = mi.mesh.surface_get_arrays(0)
			var n: int = arr[Mesh.ARRAY_VERTEX].size()
			var md: Dictionary = cd.mats[int(cd.nodes[i].mat)]
			if mi.mesh != om.mesh:
				copies += 1
				var oa: Array = om.mesh.surface_get_arrays(0)
				var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
				var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
				if cs.size() != n or u2.size() != n or oa[Mesh.ARRAY_VERTEX].size() != n or arr[Mesh.ARRAY_INDEX] != oa[Mesh.ARRAY_INDEX] or oa[Mesh.ARRAY_COLOR] != null:
					bad_shape += 1
					continue
				for v in n: # 조각 메시는 자리를 16비트로 눌러 담음 (ARRAY_FLAG_COMPRESS_ATTRIBUTES) — 다시 담으며 7e-6 쯤 달라짐
					if (arr[Mesh.ARRAY_VERTEX][v] as Vector3).distance_to(oa[Mesh.ARRAY_VERTEX][v]) > PIECE_POS_EPS:
						bad_shape += 1
						break
				if mi.material_override != p.look_mat:
					bad_mat += 1
				for v in n:
					var k: String = "%s|%s" % [bone, _cell(cs[v], u2[v].x)]
					got[k] = int(got.get(k, 0)) + 1
			else:
				if mi.material_override != p.mats[int(cd.nodes[i].mat)]:
					kept_bad += 1
				var k: String = "%s|%s" % [bone, "P" if md.get("skin", false) else "%06x" % int(md.color)]
				got[k] = int(got.get(k, 0)) + n
		check(copies > 0 and bad_shape == 0, "%s 조각 사본 %d개: 정점·삼각형은 원본 그대로, 정점 색·UV2 만 더함 (어긋남 %d)" % [ch, copies, bad_shape])
		check(bad_mat == 0 and kept_bad == 0, "%s 사본 조각은 화풍 재질, 나머지 조각은 원래 재질 (어긋남 %d·%d)" % [ch, bad_mat, kept_bad])
		check(got == want, "%s 조각 몸의 칸이 묶음 사본과 같음 (다른 칸 %s)" % [ch, str(_diff(got, want)).substr(0, 300)])
		# 화풍 재질: 묶음 재질과 같은 꼴 (정점 색 툰 + skin_tint = 플레이어 색) + 같은 툰 단·림·얇은 외곽선
		var lm: ShaderMaterial = p.look_mat
		check(lm.get_shader_parameter("use_vertex_color") == true and Color(lm.get_shader_parameter("skin_tint")).is_equal_approx(Color(RED.r, RED.g, RED.b, 1.0)), "%s 화풍 재질: 정점 색 + 플레이어 색 칠" % ch)
		check(Vector3(lm.get_shader_parameter("toon_steps")).is_equal_approx(LK.TOON_STEPS) and is_equal_approx(float(lm.get_shader_parameter("rim_strength")), float(LK.RIM[0])), "%s 화풍 재질 툰 단·림" % ch)
		check(not G3.outline_on or lm.next_pass == Look.outline_for(ch), "%s 화풍 재질 얇은 외곽선 (c7-u1: 양면 천 몸은 깊이로 민 얇은 것)" % ch)
		# 손 (1인칭에서 보이는 것): 피부 손 조각이 있으면 플레이어 색 정점이 없고 살색 정점이 있음. 끈 몸은 플레이어 색 재질 그대로
		for hand in ["hand_R", "hand_L"]:
			var hi := -1
			for i in cd.nodes.size():
				if str(cd.nodes[i].name) == hand + "__m0" and cd.mats[int(cd.nodes[i].mat)].get("skin", false):
					hi = i
			if hi < 0:
				continue # 갈고리 왼손은 갈고리
			var hm := p.nodes[hi] as MeshInstance3D
			var ha: Array = hm.mesh.surface_get_arrays(0)
			var hc = ha[Mesh.ARRAY_COLOR]
			var hu = ha[Mesh.ARRAY_TEX_UV2]
			var fl := 0
			var pl := 0
			if hc != null and hu != null:
				for v in hc.size():
					if hu[v].x > 0.5:
						pl += 1
					elif Look.rgb8(hc[v]) == flesh:
						fl += 1
			check(hm.material_override == lm and fl > 0 and pl == 0, "%s %s 1인칭 손 조각: 살색 정점 %d · 플레이어 색 정점 %d" % [ch, hand, fl, pl])
			var om := o.nodes[hi] as MeshInstance3D
			var omat := om.material_override as ShaderMaterial
			check(om.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == null and omat != null and Color(omat.get_shader_parameter("albedo")).is_equal_approx(RED), "%s %s 끄면 예전 그대로 (플레이어 색 재질)" % [ch, hand])
		# 끈 몸: 조각 메시가 .glb 그대로, 툰 단도 예전 값
		var src: Node3D = Baked.load_char(ch).scene.instantiate()
		var same := 0
		var total := 0
		for i in cd.nodes.size():
			if Look.piece_bone(cd, i) == "":
				continue
			total += 1
			var sn := src.find_child(str(cd.nodes[i].name), true, false) as MeshInstance3D
			if sn != null and (o.nodes[i] as MeshInstance3D).mesh == sn.mesh:
				same += 1
		check(total > 0 and same == total, "%s 끄면 조각 메시가 .glb 그대로 (%d/%d)" % [ch, same, total])
		src.free()
		# 사본은 같은 캐릭터 조각 몸끼리 같이 씀, 재질은 몸마다
		var p2 = _pieces(ch, BLUE, true)
		var shared := true
		for i in cd.nodes.size():
			if (p.nodes[i] is MeshInstance3D) and (p.nodes[i] as MeshInstance3D).mesh != (p2.nodes[i] as MeshInstance3D).mesh:
				shared = false
		check(shared and p2.look_mat != lm and Color(p2.look_mat.get_shader_parameter("skin_tint")).is_equal_approx(Color(BLUE.r, BLUE.g, BLUE.b, 1.0)), "%s 조각 사본은 같이 쓰고 재질은 몸마다" % ch)
		# 효과·반투명: 묶음 재질처럼 skin_tint (플레이어 칸만) — 끝나면 몸 색·원래 재질
		p._fx_colors({"stunned": true})
		check(Color(lm.get_shader_parameter("skin_tint")).a == 1.0 and Color(lm.get_shader_parameter("albedo")).is_equal_approx(Color.WHITE), "%s 효과 중에도 재질 색은 흰색 (살색 정점을 플레이어 색으로 덮지 않음)" % ch)
		p._fx_colors({})
		check(Color(lm.get_shader_parameter("skin_tint")).is_equal_approx(Color(RED.r, RED.g, RED.b, 1.0)), "%s 효과 뒤 플레이어 색" % ch)
		var lp: MeshInstance3D = null
		for dr in p.drawn:
			if dr.get("look", false):
				lp = dr.mi
				break
		p.opacity = 0.5
		p._apply_opacity()
		var am := GhostDepth.inner(lp.material_override) as ShaderMaterial
		check(am != null and am != lm and am.get_shader_parameter("use_vertex_color") == true and Color(am.get_shader_parameter("skin_tint")).a == 1.0 and Color(am.get_shader_parameter("albedo")).r == 1.0, "%s 반투명 조각도 정점 색 + 플레이어 색 칠" % ch)
		p.opacity = 1.0
		p._apply_opacity()
		check(lp.material_override == lm, "%s 반투명 끝" % ch)
		for x in [p, o, b, p2]:
			x.free()
	# 외부 모델 안쪽 몸 (안 그리는 조각 몸) 은 안 건드림
	var e = _pieces("tank", RED, true, true)
	if e.ext != null:
		check(e.look_mat == null, "외부 모델 안쪽 조각 몸은 화풍 사본 없음")
	e.free()


static func _diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		if a[k] != b.get(k):
			out[k] = [a[k], b.get(k)]
	for k in b:
		if not a.has(k):
			out[k] = [null, b[k]]
	return out


# 눈: 흰자가 배율만큼 줄고 (가운데 그대로) 머리 폭의 1/3 이하, 눈동자·어지러움 궤도가 흰자 안, 광전사 눈썹이 눈 쪽으로 같은 배율
func test_look_eye_scale() -> void:
	for ch in LK.LOOK:
		var k := float(LK.LOOK[ch].eye_scale)
		var b = _body(ch, RED, true)
		var o = _body(ch, RED, false)
		# 머리 폭 = 목 뼈의 피부 조각 중 맨 아래에서 시작하는 것 (머리 공) 의 좌우 폭 — 원본 메시에서
		var g := _geo(o)
		var flags := PackedByteArray()
		flags.resize(g.vs.size())
		for v in g.vs.size():
			flags[v] = 1 if g.u2[v].x > 0.5 and g.names[g.bone[v]] == "neck" else 0
		var ps := Look.pieces(g, flags)
		var head_w := 0.0
		var low := 1e9
		for r in ps.box:
			var bx: Array = ps.box[r]
			if bx[0].z < low - 1e-4:
				low = bx[0].z
				head_w = bx[1].y - bx[0].y
		check(head_w > 0.1 and head_w < 0.3, "%s 머리 폭 %.3f" % [ch, head_w])
		var en := Look.eye_nodes(b.cd)
		var leaf := int(b.cd.leafStart)
		for i in en.white:
			var wb := b.nodes[i] as MeshInstance3D
			var wo := o.nodes[i] as MeshInstance3D
			var dia := 0.0
			if int(i) >= leaf: # 합친 눈 메시: 눈 (삼각형으로 이어진 덩어리) 마다 가운데 그대로·크기 k 배
				var ab: Array = wb.mesh.surface_get_arrays(0)
				var vb: PackedVector3Array = ab[Mesh.ARRAY_VERTEX]
				var vo: PackedVector3Array = wo.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var wi: PackedInt32Array = ab[Mesh.ARRAY_INDEX]
				check(wb.mesh != wo.mesh and vb.size() == vo.size(), "%s 흰자 사본" % ch)
				# 모양 그대로 줄었는지: 삼각형 변마다 길이가 k 배 (눈을 가르는 방법과 상관없는 확인 — 한 눈의 정점이 다른 눈 가운데로 줄면 변이 늘어남)
				check(_edge_ratio_off(vo, vb, wi, k) < 1e-5, "%s 흰자 변 길이 k 배 (어긋남 %.5f)" % [ch, _edge_ratio_off(vo, vb, wi, k)])
				var eb := _eye_boxes(vb, wi)
				var eo := _eye_boxes(vo, wi)
				check(eb.size() == eo.size() and eb.size() >= 1 and eb.size() <= 2, "%s 눈 덩어리 %d" % [ch, eb.size()])
				for e in mini(eb.size(), eo.size()):
					var cb: Vector3 = (eb[e][0] + eb[e][1]) * 0.5
					var co: Vector3 = (eo[e][0] + eo[e][1]) * 0.5
					var sb: Vector3 = eb[e][1] - eb[e][0]
					var so: Vector3 = eo[e][1] - eo[e][0]
					check(cb.distance_to(co) < 1e-5, "%s 흰자 %d 가운데 그대로" % [ch, e])
					check(sb.is_equal_approx(so * k), "%s 흰자 %d 상자 k 배 %s / %s" % [ch, e, sb, so])
					dia = maxf(dia, maxf(sb.x, maxf(sb.y, sb.z)))
				if eb.size() == 2: # 두 눈이 서로 안 닿음 (원본은 가운데서 겹침)
					var lo: Array = eb[0] if eb[0][0].y < eb[1][0].y else eb[1]
					var hi: Array = eb[1] if eb[0][0].y < eb[1][0].y else eb[0]
					check(lo[1].y < hi[0].y, "%s 두 흰자가 떨어져 있음 (%.4f < %.4f)" % [ch, lo[1].y, hi[0].y])
				# 눈동자 (같은 부모의 합친 눈동자 메시): 모양 그대로 k 배, 가운데가 가장 가까운 흰자의 반지름 안
				for j in en.pupil:
					if int(b.cd.nodes[j].parent) != int(b.cd.nodes[i].parent) or int(j) < leaf:
						continue
					var pa: Array = (b.nodes[j] as MeshInstance3D).mesh.surface_get_arrays(0)
					var pv: PackedVector3Array = pa[Mesh.ARRAY_VERTEX]
					var pov: PackedVector3Array = (o.nodes[j] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
					check((b.nodes[j] as MeshInstance3D).mesh != (o.nodes[j] as MeshInstance3D).mesh, "%s 눈동자 사본" % ch)
					check(_edge_ratio_off(pov, pv, pa[Mesh.ARRAY_INDEX], k) < 1e-5, "%s 눈동자 변 길이 k 배" % ch)
					var pbx := _eye_boxes(pv, pa[Mesh.ARRAY_INDEX])
					check(pbx.size() == eb.size(), "%s 눈동자 수 = 흰자 수" % ch)
					for pe in pbx:
						var pc: Vector3 = (pe[0] + pe[1]) * 0.5
						var near := 1e9
						var rad := 0.0
						for we in eb:
							var wc: Vector3 = (we[0] + we[1]) * 0.5
							if pc.distance_to(wc) < near:
								near = pc.distance_to(wc)
								rad = (we[1].y - we[0].y) * 0.5
						check(near <= rad + 1e-5, "%s 눈동자가 흰자 안 (%.4f / %.4f)" % [ch, near, rad])
			else: # 눈마다 노드 (광전사): 노드 크기 k 배, 자리 그대로
				check(wb.mesh == wo.mesh and wb.scale.is_equal_approx(wo.scale * k) and wb.position.is_equal_approx(wo.position), "%s 흰자 노드 배율" % ch)
				dia = C.FIGURE_EYE * 2.0 * k
			check(dia > 0.0 and dia <= head_w * LK.EYE_HEAD_MAX + 1e-4, "%s 흰자 지름 %.4f ≤ 머리 폭 %.4f 의 1/3" % [ch, dia, head_w])
		# 어지러움 궤도 (body._face): 눈동자 가운데가 늘 흰자 반지름 안
		var pupils = b.refs.get("pupils")
		if pupils is Array:
			for step in 24:
				b._face({"dizzy": 1.0}, step * 0.037)
				for pr in pupils:
					var pn: Node3D = b._n(pr)
					var wn := pn.get_parent() as Node3D
					var off: Vector3 = wn.transform * pn.position - wn.position # 목 관절 기준, 흰자 가운데에서
					check(off.length() <= C.FIGURE_EYE * k + 1e-5, "%s 어지러움 눈동자가 흰자 안 (%.4f / %.4f)" % [ch, off.length(), C.FIGURE_EYE * k])
		var rage = b.refs.get("rage")
		if rage is Dictionary:
			for br in rage.get("brows", []):
				var nb: Node3D = b._n(br.mesh)
				var no: Node3D = o._n(br.mesh)
				var near := Vector3.ZERO
				var best := 1e9
				for i in en.white:
					var wp: Vector3 = (o.nodes[i] as Node3D).position
					if wp.distance_to(no.position) < best:
						best = wp.distance_to(no.position)
						near = wp
				check(nb.scale.is_equal_approx(no.scale * k) and (nb.position - near).is_equal_approx((no.position - near) * k), "%s 눈썹이 눈 쪽으로 같은 배율" % ch)
				b.rage_k = 1.0
				b._face({"dizzy": 0.0}, 0.3)
				check(nb.scale.is_equal_approx(no.scale * k), "%s 분노 뒤에도 눈썹 배율" % ch)
		b.free()
		o.free()


# 같은 캐릭터 몸 둘이 사본 메시 하나를 같이 씀 (정적 캐시), 재질은 몸마다
func test_look_cache_shared() -> void:
	for ch in LK.LOOK:
		var a = _body(ch, RED, true)
		var b = _body(ch, BLUE, true)
		check(a.batch.look and b.batch.look and a.batch.mi.mesh == b.batch.mi.mesh, "%s 사본 메시는 몸끼리 같이 씀" % ch)
		var en := Look.eye_nodes(a.cd)
		for i in en.white + en.pupil:
			check((a.nodes[i] as MeshInstance3D).mesh == (b.nodes[i] as MeshInstance3D).mesh, "%s 눈 메시도 같이 씀" % ch)
		var ma: ShaderMaterial = a.batch.mi.material_override
		var mb: ShaderMaterial = b.batch.mi.material_override
		check(ma != mb and Color(ma.get_shader_parameter("skin_tint")).is_equal_approx(Color(RED.r, RED.g, RED.b, 1.0)) and Color(mb.get_shader_parameter("skin_tint")).is_equal_approx(Color(BLUE.r, BLUE.g, BLUE.b, 1.0)), "%s 재질은 몸마다 (플레이어 색)" % ch)
		# 효과: 경직 하얀 깜빡임·발광은 skin_tint·skin_emissive (플레이어 칸만), 끝나면 몸 색
		a._fx_colors({"stunned": true})
		check(Color(ma.get_shader_parameter("skin_tint")).a == 1.0, "%s 경직 중 skin_tint" % ch)
		a._fx_colors({})
		check(Color(ma.get_shader_parameter("skin_tint")).is_equal_approx(Color(RED.r, RED.g, RED.b, 1.0)), "%s 효과 뒤 몸 색" % ch)
		# 반투명 (유령화·무적): 같은 사본 메시, 투명 재질에도 플레이어 색·같은 툰 단·림, 외곽선 없음
		a.opacity = 0.5
		a._apply_opacity()
		var am := GhostDepth.inner(a.batch.mi.material_override) as ShaderMaterial
		check(am != ma and a.batch.mi.mesh == b.batch.mi.mesh and Color(am.get_shader_parameter("skin_tint")).a == 1.0, "%s 반투명 플레이어 색" % ch)
		check(Vector3(am.get_shader_parameter("toon_steps")).is_equal_approx(LK.TOON_STEPS) and is_equal_approx(float(am.get_shader_parameter("rim_strength")), float(LK.RIM[0])) and am.next_pass == null, "%s 반투명 툰 단·림" % ch)
		a.opacity = 1.0
		a._apply_opacity()
		check(a.batch.mi.material_override == ma, "%s 반투명 끝" % ch)
		a.free()
		b.free()


# 묶음·따로 그리는 툰 조각 외곽선 = OUTLINE_THICKNESS × 0.45, 툰 단·림 = 외부 모델 값. 먼 거리 외곽선 (W31)·설정 '외곽선' 도 얇은 것으로
func test_look_outline_thin() -> void:
	var was: bool = G3.outline_on
	G3.set_outline_on(true)
	var thin: float = C.OUTLINE_THICKNESS * LK.OUTLINE
	for ch in LK.LOOK:
		var b = _body(ch, RED, true)
		var m: ShaderMaterial = b.batch.mi.material_override
		var np := m.next_pass as ShaderMaterial
		# c7-u1: 양면 천 몸 (표의 outline_push — 탱크·사냥꾼·갈고리) 은 같은 굵기의 깊이로 민 외곽선, 나머지는 나눠 쓰는 얇은 것 그대로
		var push := float(LK.LOOK[ch].get("outline_push", 0.0))
		check((push > 0.0) == (Look.outline_for(ch) != G3.shared_outline(thin)) and is_equal_approx(_push_of(Look.outline_for(ch)), push), "%s 외곽선 재질 갈래 (push %s)" % [ch, push])
		check(np != null and np == Look.outline_for(ch) and is_equal_approx(float(np.get_shader_parameter("thickness")), thin), "%s 묶음 외곽선 굵기 × 0.45" % ch)
		check(Vector3(m.get_shader_parameter("toon_steps")).is_equal_approx(LK.TOON_STEPS), "%s 툰 단" % ch)
		check(is_equal_approx(float(m.get_shader_parameter("rim_strength")), float(LK.RIM[0])) and is_equal_approx(float(m.get_shader_parameter("rim_power")), float(LK.RIM[1])), "%s 림" % ch)
		# 따로 그리는 툰 조각 (바드 몸통·건축가 체크 무늬·근육 홈…) 도 같은 선·단
		for dr in b.drawn:
			var dm := (dr.mi as MeshInstance3D).material_override as ShaderMaterial
			if dm == null or dm == m or dr.m.get("kind") != "toon":
				continue
			check(Vector3(dm.get_shader_parameter("toon_steps")).is_equal_approx(LK.TOON_STEPS), "%s 따로 그리는 조각 툰 단" % ch)
			if dr.m.get("outline", true) and not dr.m.get("transparent", false):
				check(dm.next_pass != null and is_equal_approx(float((dm.next_pass as ShaderMaterial).get_shader_parameter("thickness")), thin), "%s 따로 그리는 조각 외곽선" % ch)
		# W31 먼 거리 외곽선: 얇은 외곽선 재질을 찾아 거리로 줄어드는 사본으로, 멀면 뗌
		b.set_outline_far(false)
		check(not b._ol.is_empty() and m.next_pass == G3.far_outline(Look.outline_for(ch)), "%s 가까움 = 얇은 외곽선의 먼 거리 사본" % ch)
		check(is_equal_approx(float((m.next_pass as ShaderMaterial).get_shader_parameter("thickness")), thin), "%s 먼 거리 사본 굵기" % ch)
		b.set_outline_far(true)
		check(m.next_pass == null, "%s 멀면 외곽선 뗌" % ch)
		b.set_outline_far(false)
		# 설정 '외곽선' 껐다 켜도 얇은 것
		G3.set_outline_on(false)
		check(m.next_pass == null, "%s 설정 끔" % ch)
		G3.set_outline_on(true)
		check(m.next_pass != null and is_equal_approx(float((m.next_pass as ShaderMaterial).get_shader_parameter("thickness")), thin), "%s 설정 다시 켬 = 얇은 외곽선" % ch)
		b.free()
	G3.set_outline_on(was)


# ---------- 순수 계산 (지어낸 작은 메시) ----------
# 네모 조각 하나 (정점 4·삼각형 2): 가운데 c, 반폭 h, 뼈 bind, 피부 여부·색
static func _quad(g: Dictionary, c: Vector3, h: float, bind: int, skin: bool, col: Color) -> void:
	var base: int = g.vs.size()
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		g.vs.append(c + Vector3(d.x * h, d.y * h, 0))
		g.cs.append(Color.WHITE if skin else col)
		g.u2.append(Vector2(1 if skin else 0, 0.25))
		g.bone.append(bind)
	for i in [0, 1, 2, 0, 2, 3]:
		g.idx.append(base + i)


static func _fake() -> Dictionary:
	var g := {"vs": PackedVector3Array(), "cs": PackedColorArray(), "u2": PackedVector2Array(), "bone": PackedInt32Array(), "idx": PackedInt32Array(),
		"names": PackedStringArray(["neck", "arm", "leg", "cape"]), "poses": [Transform3D(), Transform3D(Basis(), Vector3(0, 0, -1)), Transform3D(), Transform3D()]}
	_quad(g, Vector3(0, 0, 0.1), 0.1, 0, true, Color.WHITE) # 0: 얼굴 (낮음)
	_quad(g, Vector3(0, 0, 0.3), 0.1, 0, true, Color.WHITE) # 1: 모자 (높음)
	_quad(g, Vector3(0, 0, 1.0), 0.05, 1, true, Color.WHITE) # 2: 팔 (좁음) — 뼈 기준 높이 0
	_quad(g, Vector3(0, 0, 1.0), 0.12, 1, true, Color.WHITE) # 3: 띠 (넓음, 팔과 같은 높이)
	_quad(g, Vector3(1, 0, 0.0), 0.1, 2, true, Color.WHITE) # 4: 다리 (표에 없는 뼈)
	_quad(g, Vector3(2, 0, 0.0), 0.1, 3, true, Color.WHITE) # 5: 망토 (player)
	_quad(g, Vector3(0, 1, 0.05), 0.1, 0, false, Look.hex(0x222228)) # 6: 수염 (낮음, 재질 1 색)
	_quad(g, Vector3(0, 1, 0.4), 0.1, 0, false, Look.hex(0x222228)) # 7: 두건 (높음, 재질 1 색)
	_quad(g, Vector3(0, 2, 0.4), 0.1, 0, false, Look.hex(0x808080)) # 8: 다른 색
	_quad(g, Vector3(3, 0, 0.0), 0.1, 2, false, Look.hex(0x222228)) # 9: 바지 (재질 1 색, 높이 문턱 없는 promote)
	return g


func test_look_classify_pure() -> void:
	var g := _fake()
	var mats := [{"kind": "toon", "color": 0xffffff, "skin": true}, {"kind": "toon", "color": 0x222228}]
	var look := {"flesh": 0xE6B894, "roles": {"*": "flesh", "cape": "player"}, "split": {"neck": [0.2, "flesh", "player"]}, "wide": {"arm": [0.08, "flesh", "player"]},
		"promote": [["neck", 1, 0.2], ["leg", 1]]}
	# bare (옷 조각 → 살색): 문턱이 있으면 가운데 높이가 그 미만인 조각만 — 장갑 공 (낮음) 은 살색, 손목 띠 (높음) 는 그대로
	var gb := _fake()
	_quad(gb, Vector3(5, 0, 0.0), 0.1, 3, false, Look.hex(0x6a4428)) # 10: 장갑 공
	_quad(gb, Vector3(5, 0, 0.05), 0.09, 3, false, Look.hex(0x6a4428)) # 11: 손목 띠
	_quad(gb, Vector3(6, 0, 0.3), 0.1, 2, false, Look.hex(0x6a4428)) # 12: 다른 뼈의 같은 색 (문턱 없는 bare)
	var mats_b := [{"kind": "toon", "color": 0xffffff, "skin": true}, {"kind": "toon", "color": 0x222228}, {"kind": "toon", "color": 0x6a4428}]
	var look_b := look.duplicate(true)
	look_b["bare"] = [["cape", 2, 0.02], ["leg", 2]]
	var rb := Look.classify(look_b, mats_b, gb)
	check(rb[10 * 4] == Look.FLESH and rb[11 * 4] == Look.NONE and rb[12 * 4] == Look.FLESH, "bare: 문턱 미만 조각만 살색 (%d %d %d)" % [rb[10 * 4], rb[11 * 4], rb[12 * 4]])
	check(rb[7 * 4] == Look.PLAYER and rb[6 * 4] == Look.NONE and rb[5 * 4] == Look.PLAYER, "bare 가 있어도 promote·피부 역할 그대로")
	var pb := Look.paint(gb.cs, gb.u2, rb, Look.hex(0xE6B894))
	check((pb[0] as PackedColorArray)[10 * 4].is_equal_approx(Look.hex(0xE6B894)) and (pb[1] as PackedVector2Array)[10 * 4] == Vector2(0, 0.25), "bare 조각 = 살색·UV2.x 0")
	var r := Look.classify(look, mats, g)
	var want := [Look.FLESH, Look.PLAYER, Look.FLESH, Look.PLAYER, Look.FLESH, Look.PLAYER, Look.NONE, Look.PLAYER, Look.NONE, Look.PLAYER]
	for q in want.size():
		for v in 4:
			check(r[q * 4 + v] == want[q], "조각 %d 역할 %d (바람 %d)" % [q, r[q * 4 + v], want[q]])
	# 조각은 반으로 안 갈림: 문턱 (0.2) 에 걸친 조각도 가운데 높이 하나로
	var g2 := _fake()
	for v in 4:
		g2.vs[v] = g2.vs[v] + Vector3(0, 0, 0.05 if v >= 2 else 0.12) # 얼굴 조각이 0.15~0.22 에 걸침 (가운데 0.185)
	var r2 := Look.classify(look, mats, g2)
	check(r2[0] == Look.FLESH and r2[1] == Look.FLESH and r2[2] == Look.FLESH and r2[3] == Look.FLESH, "문턱에 걸친 조각은 한 역할")
	# keep: 피부 정점을 안 건드림 (= 예전처럼 플레이어 색)
	var r3 := Look.classify({"roles": {"*": "keep"}}, mats, g)
	for v in r3.size():
		check(r3[v] == Look.NONE, "keep 은 안 건드림")
	# 칠하기: 살색 + UV2.x 0 / 흰색 + UV2.x 1, 나머지 그대로 (UV2.y 도)
	var flesh := Look.hex(0xE6B894)
	var p := Look.paint(g.cs, g.u2, r, flesh)
	var pc: PackedColorArray = p[0]
	var pu: PackedVector2Array = p[1]
	check(pc[0].is_equal_approx(flesh) and pu[0] == Vector2(0, 0.25), "살 = 살색·UV2.x 0")
	check(pc[4] == Color.WHITE and pu[4] == Vector2(1, 0.25), "피부 플레이어 칸 = 흰색·UV2.x 1")
	check(pc[7 * 4] == Color.WHITE and pu[7 * 4] == Vector2(1, 0.25), "올린 조각 = 흰색·UV2.x 1")
	check(pc[6 * 4].is_equal_approx(Look.hex(0x222228)) and pu[6 * 4] == Vector2(0, 0.25) and pc[8 * 4].is_equal_approx(Look.hex(0x808080)), "나머지 그대로")
	check(g.cs[0] == Color.WHITE and g.u2[0] == Vector2(1, 0.25), "원본 배열은 안 바뀜")
	# 넓이: 플레이어 칸 = UV2.x 1 인 삼각형, 숨긴 뼈는 뺌
	var a := Look.area(g, pu, {"neck": true, "arm": true, "leg": true, "cape": true})
	var want_player := 0.04 + 0.0576 + 0.04 + 0.04 + 0.04 # 모자·띠·망토·두건·바지
	var want_total := 0.04 * 8 + 0.01 + 0.0576
	check(absf(a[0] - want_player) < 1e-5 and absf(a[1] - want_total) < 1e-5, "넓이 %s (바람 %.4f / %.4f)" % [a, want_player, want_total])
	var a2 := Look.area(g, pu, {"neck": true})
	check(absf(a2[1] - 0.04 * 5) < 1e-5, "숨긴 뼈 뺀 넓이 %s" % [a2])


# 팔면체 눈 하나 (정점 6·삼각형 8) 를 배열에 더함
static func _octa(vs: PackedVector3Array, idx: PackedInt32Array, c: Vector3, r: float) -> void:
	var base := vs.size()
	for d in [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
		vs.append(c + d)
	for i in [0, 2, 4, 2, 1, 4, 1, 3, 4, 3, 0, 4, 2, 0, 5, 1, 2, 5, 3, 1, 5, 0, 3, 5]:
		idx.append(base + i)


func test_look_eyes_pure() -> void:
	# 두 눈 (y −0.05·+0.05, 반지름 0.062 — 실제 흰자처럼 가운데서 겹침: 오른쪽 눈 정점이 y +0.012 까지) 을 0.5 배
	var vs := PackedVector3Array()
	var idx := PackedInt32Array()
	_octa(vs, idx, Vector3(0.1, -0.05, 0.13), 0.062)
	_octa(vs, idx, Vector3(0.1, 0.05, 0.13), 0.062)
	var sides := Look.eye_sides(vs, idx)
	for v in 6:
		check(sides[v] == 0 and sides[6 + v] == 1, "눈 가르기는 덩어리로 (정점 %d: %d·%d)" % [v, sides[v], sides[6 + v]])
	check(vs[2].y > 0.0 and sides[2] == 0, "가운데를 넘은 정점 (y %.3f) 도 제 눈" % vs[2].y)
	var cc := Look.eye_centers(vs, sides)
	check((cc[0] as Vector3).is_equal_approx(Vector3(0.1, -0.05, 0.13)) and (cc[1] as Vector3).is_equal_approx(Vector3(0.1, 0.05, 0.13)), "눈 가운데 %s" % [cc])
	var out := Look.scale_eyes(vs, sides, cc, 0.5)
	check(out[0].is_equal_approx(Vector3(0.131, -0.05, 0.13)) and out[2].is_equal_approx(Vector3(0.1, -0.019, 0.13)) and out[9].is_equal_approx(Vector3(0.1, 0.019, 0.13)), "제 눈 가운데 기준 절반")
	check(_edge_ratio_off(vs, out, idx, 0.5) < 1e-6, "모양 그대로 절반")
	var boxes := _eye_boxes(out, idx)
	check(boxes.size() == 2 and minf(boxes[0][1].y, boxes[1][1].y) < maxf(boxes[0][0].y, boxes[1][0].y), "줄인 두 눈은 떨어져 있음")
	# 눈동자 (작은 공, 흰자 앞) 는 흰자 가운데 기준 → 흰자 안 같은 자리
	var pv := PackedVector3Array()
	var pi := PackedInt32Array()
	_octa(pv, pi, Vector3(0.155, -0.05, 0.13), 0.028)
	_octa(pv, pi, Vector3(0.155, 0.05, 0.13), 0.028)
	var po := Look.scale_eyes(pv, Look.eye_sides(pv, pi), cc, 0.5)
	check(po[0].is_equal_approx(Vector3(0.1415, -0.05, 0.13)) and po[7].is_equal_approx(Vector3(0.1135, 0.05, 0.13)), "눈동자는 흰자 가운데 기준")
	# 한쪽 눈만 (안대 — 그 눈 정점 일부가 y < 0): 다 왼쪽 눈, 없는 쪽 가운데는 null
	var ov := PackedVector3Array()
	var oi := PackedInt32Array()
	_octa(ov, oi, Vector3(0.1, 0.045, 0.1), 0.062)
	var os := Look.eye_sides(ov, oi)
	var one := Look.eye_centers(ov, os)
	check(ov[3].y < 0.0 and os[3] == 1 and one[0] == null and (one[1] as Vector3).is_equal_approx(Vector3(0.1, 0.045, 0.1)), "한쪽 눈")
	check(_edge_ratio_off(ov, Look.scale_eyes(ov, os, one, 0.5), oi, 0.5) < 1e-6, "한쪽 눈도 모양 그대로 절반")


# c7-fix F10: style 은 캐릭터를 인자로 받음 (정적 변수에 적어 둔 '마지막에 만든 몸' 을 읽지 않음) — 다른 캐릭터 몸을 만든 뒤에 불러도 넘긴 캐릭터의 값.
# c7-fix F7: rim_tint 거짓 (1인칭 팔) 이면 림 틴트 없이, 예전 림은 그대로. 구운 조각 몸 (1인칭 팔 쌍둥이) 의 화풍 재질에 실제로 림 틴트가 없음
func test_c7_style_takes_char() -> void:
	const E := preload("res://chars/external.gd")
	var was: bool = G3.outline_on
	G3.set_outline_on(true)
	var mk := func() -> ShaderMaterial:
		var m: ShaderMaterial = G3.toon_material(Color.WHITE, {"vertex_color": true, "outline": true})
		m.set_shader_parameter("skin_tint", Color(RED.r, RED.g, RED.b, 1.0))
		return m
	for last in ["bard", "hook"]: # 마지막에 만든 몸이 무엇이든
		var b = _body(last, RED, true)
		var mh: ShaderMaterial = mk.call()
		Look.style(mh, true, "hook")
		check(E.Ext.is_double(mh) and mh.next_pass == Look.outline_for("hook") and _push_of(mh.next_pass) > 0.0, "%s 몸 뒤에 불러도 갈고리 재질 = 양면 + 민 외곽선" % last)
		var mb: ShaderMaterial = mk.call()
		Look.style(mb, true, "bard")
		check(not E.Ext.is_double(mb) and mb.next_pass == Look.outline_for("bard") and _push_of(mb.next_pass) == 0.0, "%s 몸 뒤에 불러도 바드 재질 = 보통 툰 + 얇은 외곽선" % last)
		b.free()
	check(not FileAccess.get_file_as_string("res://chars/baked_look.gd").contains("static var _char"), "캐릭터를 적어 두는 정적 변수가 없음")
	var on: ShaderMaterial = mk.call()
	Look.style(on, false, "ninja")
	var off: ShaderMaterial = mk.call()
	Look.style(off, false, "ninja", false)
	check(Vector2(on.get_shader_parameter("rim_tint")).is_equal_approx(Vector2(LK.RIM_TINT[0], LK.RIM_TINT[1])), "기본: 림 틴트")
	check(off.get_shader_parameter("rim_tint") == null or Vector2(off.get_shader_parameter("rim_tint")) == Vector2.ZERO, "rim_tint 거짓: 림 틴트 없음")
	check(is_equal_approx(float(off.get_shader_parameter("rim_strength")), float(LK.RIM[0])) and is_equal_approx(float(off.get_shader_parameter("rim_power")), float(LK.RIM[1])), "예전 림 (제 색) 은 그대로")
	# 구운 조각 몸 (merge 끔 = 1인칭 팔 쌍둥이): 화풍 재질·조각 재질 어디에도 림 틴트 없음
	var was_e: bool = Body.use_ext
	var was_l: bool = Body.use_look
	Body.use_ext = false
	Body.use_look = true
	for ch in ["ninja", "hook"]:
		var vm = Body.new()
		vm.build(ch, RED, false)
		var tinted := 0
		for m in vm.mats + ([vm.look_mat] if vm.look_mat != null else []):
			var rt = (m as ShaderMaterial).get_shader_parameter("rim_tint") if m is ShaderMaterial else null
			if rt != null and Vector2(rt) != Vector2.ZERO:
				tinted += 1
		check(vm.look_mat != null and tinted == 0, "%s 1인칭 조각 몸: 림 틴트 재질 %d개 (화풍 재질 %s)" % [ch, tinted, vm.look_mat])
		vm.free()
	Body.use_ext = was_e
	Body.use_look = was_l
	G3.set_outline_on(was)


# 외곽선 재질의 push (안 넣은 재질은 0)
static func _push_of(o) -> float:
	var v = (o as ShaderMaterial).get_shader_parameter("push") if o is ShaderMaterial else null
	return 0.0 if v == null else float(v)


# c7-u1: 구운 몸의 림 틴트·림 지수·틴트가 걸리는 면 = 외부 모델 json 넷과 같은 값. 양면 + 깊이로 민 외곽선은 천이 있는 탱크·사냥꾼·갈고리만 (m, 0.005~OUTLINE_PUSH_MAX — 외부 모델 json 과 같은 값), 묶음 재질에 실제로 들어감
func test_c7_baked_matches_ext_rim() -> void:
	const K := preload("res://chars/chars_config.gd")
	const E := preload("res://chars/external.gd")
	for ch in ["tank", "ninja", "hunter", "hook"]:
		var ep := "res://assets/models/ext/%s.json" % ch
		if not FileAccess.file_exists(ep):
			continue
		var ej: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ep))
		check(is_equal_approx(float(ej.rim_tint[0]), float(LK.RIM_TINT[0])) and is_equal_approx(float(ej.rim_tint[1]), float(LK.RIM_TINT[1])), "%s json rim_tint = 구운 몸 RIM_TINT" % ch)
		check(is_equal_approx(float(ej.rim[0]), float(LK.RIM[0])) and is_equal_approx(float(ej.rim[1]), float(LK.RIM[1])), "%s json rim = 구운 몸 RIM" % ch)
	check(LK.RIM_GATE == K.EXT_DEFAULTS.rim_gate, "틴트가 걸리는 면 = 외부 모델 기본값")
	var was: bool = G3.outline_on
	G3.set_outline_on(true)
	for ch in LK.LOOK:
		var want: bool = ch in ["tank", "hunter", "hook"]
		var lk: Dictionary = LK.LOOK[ch]
		check(bool(lk.get("double", false)) == want, "%s double 은 천 있는 몸만" % ch)
		var push := float(lk.get("outline_push", 0.0))
		check(push <= K.OUTLINE_PUSH_MAX and (push >= 0.005 if want else push == 0.0), "%s outline_push %s (얻음 %s)" % [ch, "0.005~%s m" % K.OUTLINE_PUSH_MAX if want else "0", push])
		var ejp := "res://assets/models/ext/%s.json" % ch
		if want and FileAccess.file_exists(ejp) and (JSON.parse_string(FileAccess.get_file_as_string(ejp)) as Dictionary).has("outline_push"):
			check(is_equal_approx(float(JSON.parse_string(FileAccess.get_file_as_string(ejp)).outline_push), push), "%s 구운 몸 밀기 = 외부 모델 json 값" % ch)
		var b = _body(ch, RED, true)
		var m: ShaderMaterial = b.batch.mi.material_override
		check(E.Ext.is_double(m) == want, "%s 묶음 재질 양면 = %s" % [ch, want])
		check(Vector2(m.get_shader_parameter("rim_tint")).is_equal_approx(Vector2(LK.RIM_TINT[0], LK.RIM_TINT[1])), "%s 묶음 재질 림 틴트" % ch)
		check(Vector2(m.get_shader_parameter("rim_gate")).is_equal_approx(Vector2(LK.RIM_GATE[0], LK.RIM_GATE[1])), "%s 묶음 재질 틴트 면" % ch)
		check(Color(m.get_shader_parameter("skin_tint")).is_equal_approx(Color(RED.r, RED.g, RED.b, 1.0)), "%s 림이 섞는 색 = 플레이어 색" % ch)
		check(m.next_pass == Look.outline_for(ch) and is_equal_approx(_push_of(m.next_pass), push), "%s 외곽선 push" % ch)
		b.free()
		# 끄면 (--no-look) 예전 그대로: 보통 툰·림 틴트 없음
		var o = _body(ch, RED, false)
		var om: ShaderMaterial = o.batch.mi.material_override
		check(not E.Ext.is_double(om) and om.get_shader_parameter("rim_tint") == null, "%s 끄면 양면·림 틴트 없음" % ch)
		o.free()
	G3.set_outline_on(was)
