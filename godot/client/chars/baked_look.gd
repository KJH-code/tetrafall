# 구운 몸 화풍 맞추기 (c6-u1, 2026-11-15): 구운 몸 (.glb, chars/baked.gd) 이 외부 모델 (chars/external.gd tint "mask") 과 같은 규칙으로 보이게.
#   살은 살색, 플레이어 색은 옷 칸만 (묶음 메시 사본의 정점 색·UV2.x 만 바꿈 — 모양·뼈는 그대로), 작은 눈 (눈 메시 사본), 얇은 선·부드러운 툰 단 (재질 값).
# .glb 는 그대로 — 불러온 뒤 캐릭터마다 한 번 사본을 만들어 정적 캐시에 두고 같은 캐릭터 몸끼리 같이 씀. 표·수치는 baked_look_config.gd, 설명 BAKE.md '화풍 맞추기'.
# 쓰는 곳: baked_batch.gd apply_look (body.gd _build_glb 가 Body.use_look 일 때 부름). 끄기 = 실행 인자 --no-look
# 순수 계산 (classify·paint·pieces·eye_sides·scale_eyes·area) 은 노드 없이 배열만 받음 → tests/test_baked_look.gd
extends RefCounted

const C := preload("res://core/config.gd")
const G3 := preload("res://shaders/g3.gd")
const LK := preload("res://chars/baked_look_config.gd")

# 정점 역할 (classify 결과). NONE = 안 건드림
const NONE := 0
const FLESH := 1
const PLAYER := 2
const KEEP_FLAGS := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES # 사본이 원본과 같은 꼴로 저장되게 넘기는 표시

static var _cache := {} # 캐릭터 → {mesh, eyes {노드 번호 → 메시}, xf [[노드 번호, 자리, 크기 배율]]} 또는 null (표에 없음·못 만듦)


static func has_char(char_id: String) -> bool:
	return LK.LOOK.has(char_id)


static func clear_cache() -> void:
	_cache.clear()


static func hex(v: int) -> Color:
	return Color.from_rgba8((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff)


static func rgb8(c: Color) -> int:
	return (roundi(c.r * 255.0) << 16) | (roundi(c.g * 255.0) << 8) | roundi(c.b * 255.0)


static func role_id(name: String) -> int:
	return FLESH if name == "flesh" else (PLAYER if name == "player" else NONE)


# ---------- 순수 계산 ----------
# 묶음 메시 자료 g: {vs 정점, cs 정점 색 (sRGB 값 그대로), u2 (x = 1 이면 피부), bone (정점 → bind 번호), idx 삼각형,
#   names (bind 번호 → manifest 노드 이름), poses (bind 번호 → 메시 자리 → 뼈 기준 자리)}

# flags 가 0 이 아닌 정점들을 조각 (같은 뼈·같은 flags 값에서 삼각형으로 이어졌거나 같은 자리에 있는 정점 덩어리) 으로 묶음.
# 돌려줌: {root: 정점 → 조각 대표 정점 (-1 = 조각 아님), box: 대표 → [뼈 기준 작은 모서리, 큰 모서리], tris: 대표 → 삼각형 수}
static func pieces(g: Dictionary, flags: PackedByteArray) -> Dictionary:
	var vs: PackedVector3Array = g.vs
	var vb: PackedInt32Array = g.bone
	var idx: PackedInt32Array = g.idx
	var n := vs.size()
	var par := PackedInt32Array()
	par.resize(n)
	var weld := {}
	for v in n:
		par[v] = v
		if flags[v] == 0:
			continue
		var p := vs[v] * LK.WELD
		var key := Vector4i(roundi(p.x), roundi(p.y), roundi(p.z), vb[v] * 256 + flags[v])
		var w: int = weld.get(key, -1)
		if w < 0:
			weld[key] = v
		else:
			par[v] = w # w 는 늘 앞 번호 (제 대표거나 더 앞을 가리킴)
	var tris := {}
	for t in idx.size() / 3:
		var a := idx[t * 3]
		if flags[a] == 0:
			continue
		var ra := _find(par, a)
		for j in [1, 2]:
			var b := idx[t * 3 + j]
			if flags[b] != flags[a] or vb[b] != vb[a]:
				continue
			var rb := _find(par, b)
			if rb != ra:
				par[rb] = ra
	var root := PackedInt32Array()
	root.resize(n)
	var box := {}
	var poses: Array = g.poses
	for v in n:
		if flags[v] == 0:
			root[v] = -1
			continue
		var r := _find(par, v)
		root[v] = r
		var lp: Vector3 = poses[vb[v]] * vs[v]
		var bx = box.get(r)
		if bx == null:
			box[r] = [lp, lp]
		else:
			bx[0] = (bx[0] as Vector3).min(lp)
			bx[1] = (bx[1] as Vector3).max(lp)
	for t in idx.size() / 3:
		var r := root[idx[t * 3]]
		if r >= 0:
			tris[r] = int(tris.get(r, 0)) + 1
	return {"root": root, "box": box, "tris": tris}


static func _find(par: PackedInt32Array, i: int) -> int:
	while par[i] != i:
		par[i] = par[par[i]]
		i = par[i]
	return i


# 정점마다 역할 (NONE·FLESH·PLAYER). 바뀌는 건 피부 정점 (UV2.x = 1) 과 promote·bare 정점뿐 — 나머지는 NONE.
# 피부: roles 의 뼈 역할 ("*" = 표에 없는 뼈), 그 뼈에 split·wide 가 있으면 조각마다 가운데 높이·반폭으로. keep = NONE (그대로 = 플레이어 색)
# promote: [뼈, 재질 번호(, 높이 문턱)] — 그 뼈에서 정점 색이 그 재질 색인 조각 (문턱이 있으면 가운데 높이가 그 이상인 조각만) → PLAYER
# bare: [뼈, 재질 번호(, 높이 문턱)] — 같은 식으로 고른 조각 (문턱이 있으면 가운데 높이가 그 미만인 조각만) → FLESH (장갑 → 맨손)
static func classify(look: Dictionary, mats: Array, g: Dictionary) -> PackedByteArray:
	var cs: PackedColorArray = g.cs
	var u2: PackedVector2Array = g.u2
	var vb: PackedInt32Array = g.bone
	var names: PackedStringArray = g.names
	var n := cs.size()
	var roles: Dictionary = look.get("roles", {})
	var split: Dictionary = look.get("split", {})
	var wide: Dictionary = look.get("wide", {})
	var dflt := role_id(str(roles.get("*", "keep")))
	# bind 번호마다 규칙: [피부 역할, split, wide, 옷 조각 규칙 [[색, 문턱 또는 null, 역할, 문턱 아래쪽인가]]] (promote → PLAYER·문턱 이상, bare → FLESH·문턱 미만)
	var rule := []
	for k in names.size():
		var nm := names[k]
		var pr := []
		for e in look.get("promote", []):
			if str(e[0]) == nm:
				pr.append([int(mats[int(e[1])].color), e[2] if e.size() > 2 else null, PLAYER, false])
		for e in look.get("bare", []):
			if str(e[0]) == nm:
				pr.append([int(mats[int(e[1])].color), e[2] if e.size() > 2 else null, FLESH, true])
		rule.append([role_id(str(roles[nm])) if roles.has(nm) else dflt, split.get(nm), wide.get(nm), pr])
	var out := PackedByteArray()
	out.resize(n)
	# 조각이 필요한 정점 표시: 1 = 피부 (split·wide), 2 + j = 옷 조각 규칙 j 번 (문턱 있음)
	var flags := PackedByteArray()
	flags.resize(n)
	var any := false
	for v in n:
		var r: Array = rule[vb[v]]
		if u2[v].x > 0.5:
			if r[1] != null or r[2] != null:
				flags[v] = 1
				any = true
			else:
				out[v] = r[0]
			continue
		var pr: Array = r[3]
		if pr.is_empty():
			continue
		var c := rgb8(cs[v])
		for j in pr.size():
			if int(pr[j][0]) != c:
				continue
			if pr[j][1] == null:
				out[v] = pr[j][2]
			else:
				flags[v] = 2 + j
				any = true
			break
	if not any:
		return out
	var ps := pieces(g, flags)
	var root: PackedInt32Array = ps.root
	var decided := {} # 조각 대표 → 역할
	for v in n:
		if flags[v] == 0:
			continue
		var rt := root[v]
		if not decided.has(rt):
			var bx: Array = ps.box[rt]
			var mn: Vector3 = bx[0]
			var mx: Vector3 = bx[1]
			var r: Array = rule[vb[v]]
			var role := NONE
			if flags[v] == 1:
				if r[1] != null:
					role = role_id(str(r[1][1] if (mn.z + mx.z) * 0.5 < float(r[1][0]) else r[1][2]))
				else:
					role = role_id(str(r[2][1] if maxf(mx.x - mn.x, mx.y - mn.y) * 0.5 < float(r[2][0]) else r[2][2]))
			else:
				var e: Array = r[3][flags[v] - 2]
				if ((mn.z + mx.z) * 0.5 < float(e[1])) == bool(e[3]):
					role = e[2]
			decided[rt] = role
		out[v] = decided[rt]
	return out


# 역할대로 정점 색·UV2.x 를 바꾼 [색, UV2]. flesh = 살색 (sRGB 값 그대로 — BAKE.md 정점 색 규칙) + UV2.x 0, player = 흰색 + UV2.x 1 (skin_tint 가 칠함)
static func paint(cs: PackedColorArray, u2: PackedVector2Array, roles: PackedByteArray, flesh: Color) -> Array:
	var oc := cs.duplicate()
	var ou := u2.duplicate()
	for v in roles.size():
		match roles[v]:
			FLESH:
				oc[v] = Color(flesh.r, flesh.g, flesh.b, cs[v].a)
				ou[v] = Vector2(0.0, u2[v].y)
			PLAYER:
				oc[v] = Color(1.0, 1.0, 1.0, cs[v].a)
				ou[v] = Vector2(1.0, u2[v].y)
	return [oc, ou]


# 눈 메시 (두 눈이 한 메시, 목 관절 기준 — 앞 +x·왼쪽 +y) 의 정점마다 어느 눈인지 (0 = 오른쪽 y < 0, 1 = 왼쪽).
# 삼각형으로 이어진 덩어리 (눈 공 하나) 마다 정점 평균의 y 부호로 정함 — 두 흰자 공은 가운데에서 겹쳐 있어 (y −0.11~+0.01)
# 정점 y 부호로 나누면 겹친 쪽 정점이 반대쪽 눈에 묶여 두 눈이 한 띠로 늘어남 (c6-u1 테스트 2)
static func eye_sides(vs: PackedVector3Array, idx: PackedInt32Array) -> PackedByteArray:
	var n := vs.size()
	var par := PackedInt32Array()
	par.resize(n)
	for v in n:
		par[v] = v
	for t in idx.size() / 3:
		var a := _find(par, idx[t * 3])
		for j in [1, 2]:
			var b := _find(par, idx[t * 3 + j])
			if b != a:
				par[b] = a
	var sum := {} # 덩어리 대표 → [y 합, 정점 수]
	for v in n:
		var r := _find(par, v)
		var e = sum.get(r)
		if e == null:
			sum[r] = [vs[v].y, 1]
		else:
			e[0] += vs[v].y
			e[1] += 1
	var out := PackedByteArray()
	out.resize(n)
	for v in n:
		var e: Array = sum[_find(par, v)]
		out[v] = 0 if float(e[0]) / int(e[1]) < 0.0 else 1
	return out


# 눈마다 상자 가운데 [오른쪽, 왼쪽] (그쪽 눈이 없으면 null). sides = eye_sides
static func eye_centers(vs: PackedVector3Array, sides: PackedByteArray) -> Array:
	var out := [null, null]
	var mn := [Vector3.ZERO, Vector3.ZERO]
	var mx := [Vector3.ZERO, Vector3.ZERO]
	for i in vs.size():
		var v := vs[i]
		var s := sides[i]
		if out[s] == null:
			out[s] = v
			mn[s] = v
			mx[s] = v
		else:
			mn[s] = (mn[s] as Vector3).min(v)
			mx[s] = (mx[s] as Vector3).max(v)
	for s in 2:
		if out[s] != null:
			out[s] = ((mn[s] as Vector3) + (mx[s] as Vector3)) * 0.5
	return out


# 눈마다 centers (흰자 가운데 — 눈동자도 흰자 가운데 기준이라 흰자 안 자리가 그대로) 기준으로 k 배. 노드 크기를 바꾸면 목 관절 기준으로 줄어 눈이 밀림
static func scale_eyes(vs: PackedVector3Array, sides: PackedByteArray, centers: Array, k: float) -> PackedVector3Array:
	var out := vs.duplicate()
	for i in vs.size():
		var c = centers[sides[i]]
		if c != null:
			out[i] = (c as Vector3) + (vs[i] - (c as Vector3)) * k
	return out


# manifest 에서 눈 노드: {white: [노드 번호], pupil: [노드 번호]} — 묶음 밖 basic 재질 (흰자 EYE_WHITE·눈동자 EYE_PUPIL)
static func eye_nodes(cd: Dictionary) -> Dictionary:
	var out := {"white": [], "pupil": []}
	var mn: Array = cd.nodes
	for i in mini(int(cd.get("batchStart", mn.size())), mn.size()):
		var e: Dictionary = mn[i]
		if not e.has("mat") or e.get("batch", false):
			continue
		var m: Dictionary = cd.mats[int(e.mat)]
		if m.kind != "basic" or m.get("transparent", false):
			continue
		if int(m.color) == LK.EYE_WHITE:
			out.white.append(i)
		elif int(m.color) == LK.EYE_PUPIL:
			out.pupil.append(i)
	return out


# 처음 보이는 노드 (숨긴 노드와 그 자손 빼고) 이름 표
static func shown_names(cd: Dictionary) -> Dictionary:
	var out := {}
	var hid := []
	for e in cd.nodes:
		var p := int(e.parent)
		var h: bool = e.get("hidden", false) or (p >= 0 and hid[p])
		hid.append(h)
		if not h:
			out[str(e.name)] = true
	return out


# [플레이어 칸 넓이, 전체 넓이] — 처음 보이는 뼈의 삼각형만, 플레이어 칸 = UV2.x 1 (u2 는 바꾼 뒤 값)
static func area(g: Dictionary, u2: PackedVector2Array, shown: Dictionary) -> Array:
	var vs: PackedVector3Array = g.vs
	var vb: PackedInt32Array = g.bone
	var idx: PackedInt32Array = g.idx
	var names: PackedStringArray = g.names
	var player := 0.0
	var total := 0.0
	for t in idx.size() / 3:
		var a := idx[t * 3]
		if not shown.has(names[vb[a]]):
			continue
		var s := (vs[idx[t * 3 + 1]] - vs[a]).cross(vs[idx[t * 3 + 2]] - vs[a]).length() * 0.5
		total += s
		if u2[a].x > 0.5:
			player += s
	return [player, total]


# ---------- 메시·노드 ----------
# 묶음 SkinnedMesh → 순수 계산 자료 (g). 못 읽으면 빈 표
static func geometry(mesh: Mesh, skin: Skin, sk: Skeleton3D, cd: Dictionary) -> Dictionary:
	if mesh == null or skin == null or mesh.get_surface_count() != 1:
		return {}
	var arr: Array = mesh.surface_get_arrays(0)
	var vs = arr[Mesh.ARRAY_VERTEX]
	var bones = arr[Mesh.ARRAY_BONES]
	if vs == null or arr[Mesh.ARRAY_COLOR] == null or arr[Mesh.ARRAY_TEX_UV2] == null or bones == null or arr[Mesh.ARRAY_INDEX] == null or vs.size() == 0:
		return {}
	var per: int = bones.size() / vs.size()
	var vb := PackedInt32Array()
	vb.resize(vs.size())
	for v in vs.size():
		vb[v] = int(bones[v * per]) # 정점마다 뼈 하나 (가중치 1 — BAKE.md)
	var names := PackedStringArray()
	var poses := []
	for k in skin.get_bind_count():
		var bn := str(skin.get_bind_name(k))
		if bn == "" and sk != null:
			bn = sk.get_bone_name(skin.get_bind_bone(k))
		var i := int(bn.substr(2)) if bn.begins_with("B_") else -1
		names.append(str(cd.nodes[i].name) if i >= 0 and i < cd.nodes.size() else "")
		poses.append(skin.get_bind_pose(k))
	return {"arrays": arr, "vs": vs, "cs": arr[Mesh.ARRAY_COLOR], "u2": arr[Mesh.ARRAY_TEX_UV2], "bone": vb, "idx": arr[Mesh.ARRAY_INDEX], "names": names, "poses": poses}


# 원본과 같은 꼴 (표면 하나·같은 형식) 의 사본 메시
static func copy_mesh(src: Mesh, arrays: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	var a := src as ArrayMesh
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, (a.surface_get_format(0) & KEEP_FLAGS) if a != null else 0)
	if a != null:
		am.surface_set_name(0, a.surface_get_name(0))
		am.custom_aabb = a.custom_aabb
		am.shadow_mesh = a.shadow_mesh
	return am


# 캐릭터의 화풍 사본 (한 번 만들어 둠). mi = 묶음 SkinnedMesh, nodes = body.gd 노드 표 (manifest 순서). 표에 없거나 못 만들면 null
static func for_char(char_id: String, cd: Dictionary, mi: MeshInstance3D, sk: Skeleton3D, nodes: Array):
	if _cache.has(char_id):
		return _cache[char_id]
	var out = null
	var look = LK.LOOK.get(char_id)
	if look is Dictionary:
		var g := geometry(mi.mesh, mi.skin, sk, cd)
		if not g.is_empty():
			var roles := classify(look, cd.mats, g)
			var painted := paint(g.cs, g.u2, roles, hex(int(look.flesh)))
			var arr: Array = g.arrays
			arr[Mesh.ARRAY_COLOR] = painted[0]
			arr[Mesh.ARRAY_TEX_UV2] = painted[1]
			out = {"mesh": copy_mesh(mi.mesh, arr), "eyes": {}, "xf": []}
			_eyes(cd, nodes, float(look.get("eye_scale", 1.0)), out)
	_cache[char_id] = out
	return out


# 눈: 합친 눈 메시 (목 아래 잎 — 흰자 둘·눈동자 둘) 는 눈마다 줄인 사본, 눈마다 노드가 따로면 (광전사: 흰자 노드 아래 눈동자) 노드 크기 —
# 눈동자·어지러움 궤도 (body._face 가 흰자 기준 자리를 줌) 가 같이 줄어 흰자 안에 남음. 분노 눈썹은 가까운 흰자 쪽으로 같은 배율
static func _eyes(cd: Dictionary, nodes: Array, k: float, out: Dictionary) -> void:
	if k == 1.0:
		return
	var en := eye_nodes(cd)
	var leaf := int(cd.get("leafStart", cd.nodes.size()))
	var centers := {} # 부모 노드 번호 → 흰자 가운데 둘
	var singles := [] # 따로 노드인 흰자 번호
	for i in en.white:
		var wm := nodes[i] as MeshInstance3D
		if wm == null or wm.mesh == null:
			continue
		if int(i) < leaf:
			singles.append(i)
			out.xf.append([i, wm.position, k])
			continue
		var arr: Array = wm.mesh.surface_get_arrays(0)
		if arr[Mesh.ARRAY_INDEX] == null:
			continue
		var ws := eye_sides(arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX])
		var cc := eye_centers(arr[Mesh.ARRAY_VERTEX], ws)
		centers[int(cd.nodes[i].parent)] = cc
		arr[Mesh.ARRAY_VERTEX] = scale_eyes(arr[Mesh.ARRAY_VERTEX], ws, cc, k)
		out.eyes[i] = copy_mesh(wm.mesh, arr)
	for i in en.pupil:
		var pm := nodes[i] as MeshInstance3D
		var par := int(cd.nodes[i].parent)
		if pm == null or pm.mesh == null or int(i) < leaf or not centers.has(par):
			continue # 흰자 노드 아래 눈동자는 부모 크기를 따름
		var arr: Array = pm.mesh.surface_get_arrays(0)
		if arr[Mesh.ARRAY_INDEX] == null:
			continue
		arr[Mesh.ARRAY_VERTEX] = scale_eyes(arr[Mesh.ARRAY_VERTEX], eye_sides(arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX]), centers[par], k)
		out.eyes[i] = copy_mesh(pm.mesh, arr)
	var rage = cd.refs.get("rage")
	if rage is Dictionary and not singles.is_empty():
		for b in rage.get("brows", []):
			var bi := int(b.get("mesh", {}).get("node", -1))
			if bi < 0 or bi >= nodes.size():
				continue
			var bn: Node3D = nodes[bi]
			var c: Vector3 = (nodes[singles[0]] as Node3D).position
			for i in singles:
				var p: Vector3 = (nodes[i] as Node3D).position
				if p.distance_to(bn.position) < c.distance_to(bn.position):
					c = p
			out.xf.append([bi, c + (bn.position - c) * k, k])


# 재질에 외부 모델과 같은 툰 단·림 (+ outline 이면 얇은 외곽선 — G3 가 설정 '외곽선' 켜고 끌 때도 이 굵기로). 툰 재질이 아니면 그대로
static func style(m: Material, outline: bool) -> void:
	var sm := m as ShaderMaterial
	if sm == null or sm.get_shader_parameter("toon_steps") == null:
		return
	sm.set_shader_parameter("toon_steps", LK.TOON_STEPS)
	sm.set_shader_parameter("rim_strength", float(LK.RIM[0]))
	sm.set_shader_parameter("rim_power", float(LK.RIM[1]))
	if outline:
		# G3 기록 (set_outline_on 이 차례로 다시 붙임) 에 얇은 것을 한 줄 더 — 뒤 줄이 이김. no_outline 으로 앞 줄을 지우면 기록을 다 훑어 몸마다 재질 수만큼 느려짐
		G3.attach_outline(sm, G3.shared_outline(C.OUTLINE_THICKNESS * LK.OUTLINE))
