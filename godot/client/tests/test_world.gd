# G1 판 그리기 계산이 JS 화면과 같은 값인지 (tools/fixtures.mjs 가 뽑은 정답): 관전 궤도·하늘 시점·칸 색·위험 + 좌표 손잡이
extends RefCounted

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Cam := preload("res://world/cam_math.gd")
const SkyV := preload("res://world/sky_view.gd")
const Cells := preload("res://world/cells.gd")
const HF := preload("res://world/hazard_field.gd")
const Labels := preload("res://world/labels.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func near(a: float, b: float, eps := 1e-6) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))


func load_json(name: String):
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name))


func grid_of(fx) -> PackedByteArray:
	var g := PackedByteArray()
	for v in fx.grid:
		g.append(int(v))
	return g


func test_coords_keep_handedness() -> void:
	# 게임 오른손 (x × y = z 위) → 고도도 오른손 (x × (−z) = y 위): 화면이 JS 와 거울이 아님
	var gx := Co.gxyz(1, 0, 0)
	var gy := Co.gxyz(0, 1, 0)
	var gz := Co.gxyz(0, 0, 1)
	check(gx.cross(gy).is_equal_approx(gz), "손잡이 그대로")
	check(Co.game(Co.gxyz(1.5, -2, 3)).is_equal_approx(Vector3(1.5, -2, 3)), "game() 은 반대 변환")
	# yaw 방향을 보는 몸: rot_y 로 돌린 +x 가 dir(yaw)
	for yaw in [0.0, 0.7, 2.0, -1.2]:
		var b := Basis(Vector3.UP, Co.rot_y(yaw))
		check((b * Vector3.RIGHT).is_equal_approx(Co.dir(yaw)), "rot_y·dir 같은 방향 %f" % yaw)
		check(Co.dir(yaw).is_equal_approx(Co.gxyz(cos(yaw), sin(yaw), 0)), "dir = 게임 방향 %f" % yaw)
	# 고도 카메라로 +x 를 보면 게임 −y (오른쪽, 반시계 yaw 의 오른편) 가 화면 오른쪽
	var cam := Basis.looking_at(Co.dir(0.0), Vector3.UP)
	check((cam.x).is_equal_approx(Co.gxyz(0, -1, 0)), "화면 오른쪽 = 게임 −y")


func test_orbit_matches_js() -> void:
	var fx = load_json("camera.json")
	var g := grid_of(fx)
	var w := int(fx.W)
	var d := int(fx.D)
	var h := int(fx.H)
	var solid := func(x: float, y: float, z: float) -> bool:
		var gx := floori(x)
		var gy := floori(y)
		var gz := floori(z)
		if gx < 0 or gy < 0 or gx >= w or gy >= d:
			return false
		if gz < 0:
			return true
		return gz < h and g[(gz * d + gy) * w + gx] != 0
	var bad := 0
	for o in fx.orbit:
		var e := Cam.orbit_eye(o[0], o[1], o[2], o[3], solid if o[4] else null, 0.1, o[5])
		var want: Dictionary = o[6]
		if not (near(e.x, want.x) and near(e.y, want.y) and near(e.z, want.z) and near(e.dist, want.dist)):
			bad += 1
	check(bad == 0, "궤도 카메라 %d/%d 다름" % [bad, fx.orbit.size()])
	for f in fx.follow:
		check(near(Cam.follow_dist(f[0], f[1], f[2], f[3]), f[4]), "followDist %s" % [f])
	for o in fx.over:
		check(near(Cam.overview_scale(o[0], o[1]), o[2]), "overviewScale %s" % [o])


func test_sky_view_matches_js() -> void:
	var fx = load_json("sky.json")
	var bad := 0
	for p in fx.poses:
		var got := SkyV.sky_pose(p[0], p[1], p[2], p[3])
		var want: Dictionary = p[4]
		for i in 3:
			if not near(got.pos[i], want.pos[i]) or not near(got.look[i], want.look[i]):
				bad += 1
		if not near(got.dist, want.dist) or not near(got.fov, want.fov):
			bad += 1
	check(bad == 0, "skyPose %d 다름" % bad)
	for t in fx.turns:
		check(near(SkyV.turn_yaw(t[0], int(t[1])), t[2]), "turnYaw %s" % [t])
	for e in fx.eases:
		check(near(SkyV.ease_yaw(e[0], e[1], e[2]), e[3]), "easeYaw %s" % [e])
	for l in fx.lands:
		var got := SkyV.landing_preview(l[0])
		check(str(got.cells) == str(l[1].cells), "착지 칸 %s ≠ %s" % [got.cells, l[1].cells])
		check(str(got.pillars) == str(l[1].pillars), "기둥 %s ≠ %s" % [got.pillars, l[1].pillars])
		check(got.ok == l[1].ok, "fits")


func test_cell_colors_match_js() -> void:
	var fx = load_json("cells.json")
	var meadow := Cells.piece_colors(Cells.theme_of("flat"))
	for c in fx.cells:
		check(Cells.cell_color(int(c[0])) == int(c[1]), "칸 %d 기본 색 %x ≠ %x" % [c[0], Cells.cell_color(int(c[0])), int(c[1])])
		check(Cells.cell_color(int(c[0]), meadow) == int(c[2]), "칸 %d 들판 색" % c[0])


func test_hazard_matches_js() -> void:
	var fx = load_json("hazard.json")
	var g := grid_of(fx)
	var w := int(fx.W)
	var d := int(fx.D)
	var h := int(fx.H)
	for c in fx.cols:
		var got := HF.column_at(g, w, d, h, int(c[0]), int(c[1]), c[2])
		check(got.pierce == c[3].pierce and near(got.ground, c[3].ground), "columnAt %s → %s" % [c, got])
	for f in fx.fields:
		var got := HF.field(g, w, d, h, f[0])
		var want: Dictionary = f[1]
		check(got.nx == want.nx and got.ny == want.ny and got.x0 == want.x0 and got.w == want.w, "표 크기")
		var sum := 0.0
		for v in got.dist:
			sum += v
		check(near(sum, want.sum, 1e-5), "거리 합 %f ≠ %f (zs %s)" % [sum, want.sum, f[0]])
		var bad := 0
		for p in want.pick:
			if not near(got.dist[int(p[0])], p[1], 1e-5) or not near(got.ground[int(p[0])], p[2]):
				bad += 1
		check(bad == 0, "거리·바닥 표본 %d 다름 (zs %s)" % [bad, f[0]])
		var same: bool = got.contacts.size() == want.contacts.size()
		for i in mini(got.contacts.size(), want.contacts.size()):
			var a: Dictionary = got.contacts[i]
			var b: Dictionary = want.contacts[i]
			same = same and near(a.x, b.x) and near(a.y, b.y) and a.nx == b.nx and a.ny == b.ny
		check(same, "닿는 점 (zs %s)" % f[0])
	for s in fx.steps:
		check(HF.rise_step(s[0]) == int(s[1]), "riseStep %s" % [s])
	for v in fx.vig:
		check(near(HF.vignette_strength(v[0], v[1]), v[2]), "vignette %s" % [v])
	for s in fx.drops:
		check(near(HF.sea_drop(s[0]), s[1]), "seaDrop %s" % [s])
	for r in fx.rings:
		var got := HF.far_rings(fx.objs, r[0], int(C.HAZARD_FAR_RINGS), 6, 5)
		check(got.size() == r[1].size(), "farRings 수 zs %s" % r[0])
		for i in mini(got.size(), r[1].size()):
			check(near(got[i].r, r[1][i].r) and near(got[i].x, r[1][i].x), "farRings %d" % i)


func test_label_sizes_match_js() -> void:
	for c in load_json("labels.json"):
		var got := Labels.label_sizes(c[0])
		check(_same(got, c[1]), "labelSizes %s → %s ≠ %s" % [c[0], got, c[1]])


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not near(a[i][0], b[i][0]) or not near(a[i][1], b[i][1]):
			return false
	return true


func test_victory_matches_js() -> void:
	const V := preload("res://world/victory.gd")
	var fx = load_json("victory.json")
	for p in fx.plans:
		var slow: float = INF if p[1] == null else float(p[1])
		if p[1] == null:
			slow = INF
		var got := V.plan(p[0], slow, p[2])
		for k in ["closeupAt", "resultsAt", "endAt"]:
			check(near(got[k], p[3][k]), "victoryPlan %s %s" % [p.slice(0, 3), k])
		for s in p[4]:
			check(V.stage(got, s[0]) == s[1], "victoryStage %s t %s → %s ≠ %s" % [p.slice(0, 3), s[0], V.stage(got, s[0]), s[1]])
	for s in fx.stars:
		var got = V.star_of(s[0])
		check((got == null and s[1] == null) or (got != null and s[1] != null and got == int(s[1])), "승자 고르기 %s → %s ≠ %s" % [s[0], got, s[1]])


func test_ghost_pick_matches_js() -> void:
	const GA := preload("res://world/ghost_aim.gd")
	var fx = load_json("ghost.json")
	var g := grid_of(fx)
	var w := int(fx.W)
	var d := int(fx.D)
	var h := int(fx.H)
	var solid := func(x: float, y: float, z: float) -> bool:
		var gx := floori(x)
		var gy := floori(y)
		var gz := floori(z)
		if gx < 0 or gy < 0 or gx >= w or gy >= d:
			return false
		if gz < 0:
			return true
		return gz < h and g[(gz * d + gy) * w + gx] != 0
	var top := func(x: int, y: int) -> int:
		for z in range(h - 1, -1, -1):
			if g[(z * d + y) * w + x] != 0:
				return z + 1
		return 0
	var bad := 0
	var hits := 0
	for r in fx.rays:
		var got = GA.pick(Vector3(r[0].x, r[0].y, r[0].z), Vector3(r[1].x, r[1].y, r[1].z), w, d, solid, top)
		var want = r[2]
		if want != null:
			hits += 1
		if (got == null) != (want == null) or (got != null and (got.x != int(want.x) or got.y != int(want.y) or got.z != int(want.z))):
			bad += 1
	check(bad == 0, "조준 기둥 %d/%d 다름" % [bad, fx.rays.size()])
	check(hits > 10, "닿는 시선이 충분 (%d)" % hits)


func test_lobby_preview_matches_js() -> void:
	const LP := preload("res://world/lobby_preview.gd")
	var fx = load_json("lobby.json")
	for t in fx.themes:
		var got = LP.lobby_theme(t[0], t[1])
		check(str(got) == str(t[2]), "lobbyTheme %s → %s ≠ %s" % [t[0].map, got, t[2]])
		check(LP.lobby_field_size(t[0]) == int(t[3]), "lobbyFieldSize %d ≠ %d" % [LP.lobby_field_size(t[0]), t[3]])
	for s in fx.sizes:
		check(LP.field_size_for(int(s[0])) == int(s[1]), "fieldSizeFor %s" % [s])
	for c in fx.cols: # world/map_columns.json = 지금 shared/maps.js mapColumns (맵 배치를 바꾸고 다시 안 뽑으면 실패)
		check(str(LP.columns(c[0], int(c[1]))) == str(c[2]), "map_columns.json %s %d 다름 → node godot/client/tools/gen-map-columns.mjs" % [c[0], c[1]])
	var built := {}
	for t in fx.tops:
		var key: String = "%s%d" % [t[0], t[1]]
		if not built.has(key):
			built[key] = LP.build(t[0], int(t[1]), int(C.GRID_H))
		check(near(LP.top_at(built[key], t[2], t[3]), t[4]), "previewTop %s" % [t])


func test_label_thinning() -> void:
	const L := preload("res://world/labels.gd")
	var it := func(x, y, d): return {"px": Vector2(x, y), "dist": d, "gap": Vector2(100, 40)}
	# 가까운 것이 이김: 겹치는 둘 중 먼 것 숨김, 떨어진 것은 그대로
	var got := L.thin([it.call(100, 100, 5.0), it.call(130, 110, 2.0), it.call(400, 100, 9.0)])
	check(got == [false, true, true], "겹침 숨김 %s" % [got])
	# 같은 거리면 앞 순서
	check(L.thin([it.call(0, 0, 1.0), it.call(10, 0, 1.0)]) == [true, false], "같은 거리")
	# UI 판 안이면 숨김 (가려진 것은 자리도 차지하지 않음)
	got = L.thin([it.call(50, 50, 1.0), it.call(60, 60, 3.0)], [Rect2(0, 0, 55, 55)])
	check(got == [false, true], "UI 판 뒤 %s" % [got])


func test_hunt_marks_match_js() -> void:
	const H := preload("res://world/hunt_marks.gd")
	var fx = load_json("hunt_marks.json")
	for p in fx.picks:
		var got = H.pick_mark(p[0], p[1])
		var want = p[2]
		check((got == null) == (want == null), "pickMark 있음 %s" % [p])
		if got != null and want != null:
			check(int(got.by) == int(want.by) and int(got.n) == int(want.n) and got.mine == want.mine, "pickMark %s → %s ≠ %s" % [p[0], got, want])
	for p in fx.pips:
		var got := H.mark_pips(int(p[0]))
		check(str(got.pips) == str(p[1].pips) and got.full == p[1].full and got.n == int(p[1].n), "markPips %s" % p[0])
		check(H.pip_text(int(p[0])) == p[2], "pipText %s" % p[0])
	for p in fx.pops:
		check(near(H.pop_scale(p[0]), p[1]), "popScale %s" % [p])
	for e in fx.edges:
		var age: float = INF if e[1] == null else float(e[1])
		check(near(H.edge_level(e[0], C.HUNTER_MARK_MAX, age, e[2]), e[3]), "edgeLevel %s" % [e])
	for b in fx.blinks:
		check(H.mark_blink(b[0], b[1]) == b[2], "markBlink %s" % [b])


# W35: 사냥꾼 표식 칸 그림 (JS canvas 마름모) — 찬 칸은 가운데가 칸 색, 빈 칸은 가운데 반투명, 꼭짓점 밖은 투명, 키가 가로보다 큼
func test_hunt_pip_texture_matches_js_shape() -> void:
	const BF := preload("res://world/body_fx.gd")
	var on: Image = BF.pip_texture("on").get_image()
	var off: Image = BF.pip_texture("off").get_image()
	var full: Image = BF.pip_texture("full").get_image()
	check(_close(on.get_pixel(16, 16), Color(1.0, 0.227, 0.165)), "찬 칸 가운데 = U.on")
	check(_close(full.get_pixel(16, 16), Color(1.0, 0.824, 0.227)), "꽉 참 가운데 = U.full")
	check(off.get_pixel(16, 16).a > 0.3 and off.get_pixel(16, 16).a < 0.4, "빈 칸 가운데 = 검정 35%")
	check(on.get_pixel(1, 1).a < 0.01, "마름모 밖 모서리는 투명")
	var w := 0
	var h := 0
	for i in 32:
		if on.get_pixel(i, 16).a > 0.5:
			w += 1
		if on.get_pixel(16, i).a > 0.5:
			h += 1
	check(h > w, "키 큰 마름모 (세로 %d > 가로 %d)" % [h, w])


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02 and a.a > 0.98


# W35: 취약 ♫ 그림 — 글꼴 없이 그린 분홍 음표 + 어두운 테두리
func test_vuln_note_texture() -> void:
	const BF := preload("res://world/body_fx.gd")
	var im: Image = BF.note_texture().get_image()
	var pink := 0
	var edge := 0
	for y in 64:
		for x in 64:
			var c := im.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.9 and c.g > 0.35:
				pink += 1
			elif c.a > 0.5 and c.r < 0.3:
				edge += 1
	check(pink > 300 and edge > 100, "분홍 음표 (%d) + 테두리 (%d)" % [pink, edge])
	check(im.get_pixel(0, 0).a < 0.01, "그림 밖은 투명")


# W35: 갈고리 R 덩어리 재질 — 종류마다 JS 처럼 (지형 돌·쌓기 나무·설치 모래·테트리미노 = 맵 테마 칸)
func test_hook_chunk_materials() -> void:
	var hf = preload("res://world/hook_fx.gd").new()
	hf.g3 = load("res://shaders/g3.gd")
	hf.theme_id = "volcano"
	var col := Color(0.8, 0.5, 0.2)
	var terr: Dictionary = hf.chunk_look({"v": 1}, col)
	var build: Dictionary = hf.chunk_look({"v": 2, "builder": true}, col)
	var thrown: Dictionary = hf.chunk_look({"v": 3}, col)
	var piece: Dictionary = hf.chunk_look({"v": 5}, col)
	check(terr.mat.get_shader_parameter("use_tex") == true and terr.mat.get_shader_parameter("albedo_tex") == preload("res://world/chunk_tex.gd").stone(), "지형 덩어리 = 돌 그림")
	# c11-fix F6: 설치 블록 덩어리 = 쌓였을 때·떨어질 때와 같은 나무 상자 (예전 모래 그림 상자 — 집어 올리는 순간 모습이 바뀌었음)
	const CrateLook := preload("res://world/crate_look.gd")
	check(thrown.mesh == CrateLook.mesh() and thrown.mat.get_shader_parameter("use_vertex_color") == true and thrown.mat.get_shader_parameter("use_tex") != true, "설치 블록 덩어리 = 나무 상자 메시 + 정점 색 툰 재질")
	check(thrown.mat.next_pass != null or not hf.g3.outline_on, "설치 블록 덩어리: 떨어지는 칸처럼 외곽선")
	check(build.mat.get_shader_parameter("albedo_tex") == preload("res://world/chunk_tex.gd").wood(), "건축가 덩어리 = 판자 그림")
	check(piece.mesh is ArrayMesh and piece.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] is PackedColorArray, "테트리미노 덩어리 = 테마 칸 모양 + 꼭짓점 색")
	check(piece.mat.get_shader_parameter("face_tex") != null, "테트리미노 덩어리 재질 = 테마 칸 재질 (면 그림)")
	var sky: Dictionary = hf.chunk_look({"v": 3, "sky": true}, col)
	check(absf(sky.mat.get_shader_parameter("albedo").a - float(C.SKY_PIECE_OPACITY)) < 0.001, "하늘 덩어리는 반투명")
	check(sky.mat.get_shader_parameter("albedo_tex") == preload("res://world/chunk_tex.gd").sand() and sky.mesh is BoxMesh, "하늘 덩어리 (반투명) 는 예전 모래 그림 상자 그대로")
	check(terr.mat.get_shader_parameter("albedo_tex").get_image().get_pixel(10, 10).r > 0.4, "돌 그림이 칠해짐")
	hf.free()


# W35: 탱크 R 솟는 땅 칸이 돌 그림을 입음 (JS quakeMat map: tex.stone)
func test_quake_cells_use_stone_texture() -> void:
	var mk = preload("res://world/marks.gd").new()
	var G3 = load("res://shaders/g3.gd")
	mk.make_mat = func(c: Color): return G3.toon_material(c)
	mk.quake_rise([[1, 1, 1], [2, 1, 1]], 1000.0, 7)
	var m: ShaderMaterial = mk._quake_mat
	check(m.get_shader_parameter("use_tex") == true and m.get_shader_parameter("albedo_tex") == preload("res://world/chunk_tex.gd").stone(), "솟는 땅 재질 = 돌 그림")
	check(mk.quakes.size() == 1 and mk.quakes[0].nodes.size() == 2, "솟는 땅 칸 2개")
	mk.free()


class _GlowSpy:
	var calls := 0
	const ROUND := 0
	const STAR := 1
	func glow(_p, _c, _s, _ms, _a = 1.0, _k = 0, _o = {}) -> void:
		calls += 1


# W35: 갈고리 사슬이 팽팽한 동안 빛 알갱이 (간격마다 한 번, 알갱이 수 + 끝 번쩍), 효과 풀이 없으면 아무 일 없음
func test_hook_tension_light() -> void:
	var hf = preload("res://world/hook_fx.gd").new()
	var chain := {}
	hf.tension_light(chain, Vector3.ZERO, Vector3(3, 0, 0), 1000.0) # 효과 풀 없음
	check(not chain.has("tn_next"), "효과 풀이 없으면 안 그림")
	var spy := _GlowSpy.new()
	hf.effects = spy
	hf.tension_light(chain, Vector3.ZERO, Vector3(3, 0, 0), 1000.0)
	var T: Dictionary = preload("res://fx/fx_config.gd").HOOK_TENSION
	check(spy.calls == int(T.dots) + 1, "알갱이 %d + 끝 번쩍 1 (%d)" % [int(T.dots), spy.calls])
	hf.tension_light(chain, Vector3.ZERO, Vector3(3, 0, 0), 1010.0)
	check(spy.calls == int(T.dots) + 1, "간격 안에서는 또 안 터뜨림")
	hf.tension_light(chain, Vector3.ZERO, Vector3(3, 0, 0), 1000.0 + float(T.every) + 1.0)
	check(spy.calls == 2 * (int(T.dots) + 1), "간격 뒤 다시")
	hf.free()


# W35: 1인칭이면 내 발밑 고리만 숨김
func test_own_ring_hidden_in_first_person() -> void:
	const BF := preload("res://world/body_fx.gd")
	check(BF.hide_own_ring(3, 3, false), "1인칭 내 고리 숨김")
	check(not BF.hide_own_ring(3, 3, true), "3인칭 내 고리 보임")
	check(not BF.hide_own_ring(4, 3, false), "남의 고리는 1인칭에서도 보임")
	check(not BF.hide_own_ring(3, null, false), "내 id 모르면 보임")


# W35: 탱크 아머 맞음 반응 (JS hitReact) — 버틴 타는 약하게·멈칫 없음, 깨진 타는 크게·멈칫 ×1.5, 오래되면 보통 타
func test_armor_hit_reaction() -> void:
	const B := preload("res://chars/body.gd")
	var held: Dictionary = B.armor_reaction(0.05, 99.0)
	check(held.pow == C.FIGURE_HIT_ARMOR and held.stop == 0.0 and not held.breaks, "버틴 타 = 얼굴만 찡그림, 멈칫 없음")
	var br: Dictionary = B.armor_reaction(99.0, 0.05)
	check(br.pow == C.FIGURE_HIT_ARMOR_BREAK and absf(br.stop - C.HITSTOP_MS * 1.5 / 1000.0) < 1e-9 and br.breaks, "깨진 타 = 크게, 멈칫 ×1.5")
	check(B.armor_reaction(0.3, 0.3).is_empty(), "200ms 지나면 보통 타")
	check(B.armor_reaction(0.1, 0.1).pow == C.FIGURE_HIT_ARMOR, "둘 다면 버틴 쪽 먼저")


# W35: 반투명 몸 깊이 선 — 반투명 재질 앞에 깊이만 쓰는 재질을 붙임 (같은 재질이면 하나만), 깊이 선 → 원래 재질 순서, 같은 그리기 순서
func test_ghost_depth_wrap() -> void:
	const GD := preload("res://chars/ghost_depth.gd")
	var alpha := G3_toon_alpha()
	var w: ShaderMaterial = GD.with_prepass(alpha)
	check(w != alpha and w.next_pass == alpha, "깊이 선 재질 → 반투명 재질 순서")
	var holder := {"alpha": alpha}
	check(GD.wrap_in(holder) == GD.wrap_in(holder) and GD.wrap_in(holder).next_pass == alpha and GD.inner(GD.wrap_in(holder)) == alpha, "칸마다 한 번만 만들고 안쪽 재질을 되찾음")
	check(GD.inner(alpha) == alpha, "감싸지 않은 재질은 그대로")
	check(w.render_priority == alpha.render_priority, "그리기 순서 같음")
	check(w.shader.code.contains("depth_draw_always") and w.shader.code.contains("shadows_disabled"), "깊이만 쓰고 그림자 안 만듦")
	check(GD.with_prepass(null) == null, "재질 없으면 없음")


func G3_toon_alpha() -> ShaderMaterial:
	return load("res://shaders/g3.gd").toon_material(Color.WHITE, {"opacity": 0.5, "outline": false})


# ---- c7-u1 발밑 색 고리 (world/foot_ring_math.gd 순수 계산, world/foot_rings.gd 그리기, 수치 WC.FOOT_RING) ----
const FRM := preload("res://world/foot_ring_math.gd")
const FR := preload("res://world/foot_rings.gd")
const FWC := preload("res://world/world_config.gd")


# 사람 둘 (id 1 = 나, 2 = 남) 이 판 가운데 바닥 (높이 gz) 에 선 판 상태
func _ring_state(phase := "playing") -> Dictionary:
	return {"phase": phase, "players": [{"id": 1, "alive": true}, {"id": 2, "alive": true}], "lava": {"active": false, "z": 0.0}}


func _rings(st: Dictionary, my_id, hide_me: bool, sky: bool, shown: Dictionary, ground := func(_x, _y, _z): return 2.0) -> Array:
	return FRM.rings(st, my_id, hide_me, sky, shown, {1: 0xff0000, 2: 0x00ff00}, Vector3i(10, 10, 32), ground, FWC.FOOT_RING)


# 고리 자리: 발 아래 기둥 꼭대기 + lift, 필드 밖은 안 그림, 위험 액체가 바닥보다 높으면 그 표면 위. 머리 위 지붕 (블록 밑) 은 건너뛰고 발 아래 칸
func test_c7_foot_ring_ground() -> void:
	var cfg: Dictionary = FWC.FOOT_RING
	check(near(FRM.surface(3.0, true, false, 9.0), 3.0) and near(FRM.surface(3.0, true, true, 1.0), 3.0), "기둥 꼭대기 (위험 꺼짐·더 낮음)")
	check(near(FRM.surface(3.0, true, true, 4.5), 4.5), "위험 액체가 더 높으면 그 표면")
	check(is_nan(FRM.surface(3.0, false, false, 0.0)) and is_nan(FRM.surface(3.0, false, true, 9.0)), "필드 밖은 없음")
	var shown := {1: Vector3(4.5, 5.5, 3.0), 2: Vector3(-0.5, 5.5, 0.0)}
	var asked := []
	var ground := func(cx: int, cy: int, _z: float) -> float:
		asked.append(Vector2i(cx, cy))
		return 3.0
	var r := _rings(_ring_state(), null, false, false, shown, ground)
	check(r.size() == 1 and asked == [Vector2i(4, 5)], "필드 밖 사람은 고리 없음·바닥도 안 물음 (줄 %d, 물은 칸 %s)" % [r.size(), asked])
	check(near(r[0][0], 4.5) and near(r[0][1], 5.5) and near(r[0][2], 3.0 + float(cfg.lift)), "발 아래 기둥 꼭대기 + lift")
	check(near(r[0][3], float(cfg.r)) and Color(r[0][4]).is_equal_approx(Color(1, 0, 0, float(cfg.alpha))), "바닥에 서면 온 크기·온 진하기·플레이어 색")
	for edge in [Vector3(10.2, 5.0, 0.0), Vector3(5.0, 10.0, 0.0), Vector3(5.0, -0.01, 0.0)]:
		check(_rings(_ring_state(), null, false, false, {1: edge}).is_empty(), "필드 밖 %s" % edge)
	var st := _ring_state()
	st.lava = {"active": true, "z": 4.25}
	r = _rings(st, null, false, false, {1: Vector3(4.5, 5.5, 5.0)})
	check(near(r[0][2], 4.25 + float(cfg.lift)), "위험 액체가 바닥 (2) 보다 높으면 액체 위")
	st.lava = {"active": true, "z": 1.0}
	r = _rings(st, null, false, false, {1: Vector3(4.5, 5.5, 2.0)})
	check(near(r[0][2], 2.0 + float(cfg.lift)), "액체가 더 낮으면 바닥")
	st.lava = {"active": false, "z": 9.0}
	r = _rings(st, null, false, false, {1: Vector3(4.5, 5.5, 2.0)})
	check(near(r[0][2], 2.0 + float(cfg.lift)), "위험이 꺼져 있으면 z 값 무시")
	# 기둥: 칸 0·1 단단, 2~4 빈칸, 5 단단 (지붕) → 꼭대기 6. 발 2.0 에 서면 지붕이 아니라 2
	var col := [true, true, false, false, false, true]
	var solid := func(z: int) -> bool: return z >= 0 and z < col.size() and col[z]
	var step := float(cfg.step)
	check(FRM.ground_under(6, 2.0, solid, step) == 2, "지붕 밑: 발 아래 칸")
	check(FRM.ground_under(6, 6.0, solid, step) == 6 and FRM.ground_under(6, 8.3, solid, step) == 6, "지붕 위·그 위 공중: 기둥 꼭대기")
	check(FRM.ground_under(6, 5.6, solid, step) == 6, "꼭대기에 오르는 중 (step 안) 은 꼭대기")
	check(FRM.ground_under(6, 3.7, solid, step) == 2, "지붕 밑 공중 (점프) 도 발 아래 칸")
	check(FRM.ground_under(4, 1.0, func(_z): return false, step) == 0, "아래에 단단한 칸이 없으면 바닥 0")


# 공중: 바닥에서 높이 오를수록 반지름·알파가 단조 감소, 하한 fade_min
func test_c7_foot_ring_fade() -> void:
	var cfg: Dictionary = FWC.FOOT_RING
	check(near(FRM.fade(0.0, cfg), 1.0) and near(FRM.fade(-0.3, cfg), 1.0), "바닥·바닥 아래 (잠김) 는 1")
	var prev := 1.0
	var prev_r := INF
	var prev_a := INF
	for i in 80:
		var h := i * 0.1
		var k := FRM.fade(h, cfg)
		check(k <= prev + 1e-9 and k >= float(cfg.fade_min) - 1e-9, "높이 %.1f 배율 %.3f: 단조 감소·하한" % [h, k])
		prev = k
		var r := _rings(_ring_state(), null, false, false, {1: Vector3(4.5, 5.5, 2.0 + h)})
		check(r.size() == 1 and float(r[0][3]) <= prev_r + 1e-9 and Color(r[0][4]).a <= prev_a + 1e-9, "높이 %.1f 반지름·알파 단조 감소" % h)
		check(near(r[0][3], float(cfg.r) * k, 1e-5) and near(Color(r[0][4]).a, float(cfg.alpha) * k, 1e-5), "높이 %.1f 반지름·알파 = 온 값 × 배율" % h)
		check(near(r[0][2], 2.0 + float(cfg.lift)), "공중이어도 고리는 바닥에")
		prev_r = float(r[0][3])
		prev_a = Color(r[0][4]).a
	check(near(FRM.fade(1.0, cfg), 1.0 - float(cfg.fade)) and near(FRM.fade(50.0, cfg), float(cfg.fade_min)), "1칸 위 값·하한 값")
	check(near(float(cfg.fade_min), 0.45) and near(float(cfg.fade), 0.12) and near(float(cfg.r), 0.42) and near(float(cfg.inner), 0.72) and near(float(cfg.alpha), 0.85) and near(float(cfg.lift), 0.04), "FOOT_RING 수치")


# 안 그림: 죽음·블록 마스터·하늘 시점 (전부)·1인칭의 나·판 중이 아닐 때 (대기실·결과). 3인칭의 나는 그리고 안쪽 흰 테가 붙음
func test_c7_foot_ring_hidden() -> void:
	var cfg: Dictionary = FWC.FOOT_RING
	var shown := {1: Vector3(4.5, 5.5, 2.0), 2: Vector3(6.5, 5.5, 2.0)}
	check(_rings(_ring_state(), 1, true, false, shown).size() == 1 and near(_rings(_ring_state(), 1, true, false, shown)[0][0], 6.5), "1인칭: 내 고리 없음, 남 고리만")
	var third := _rings(_ring_state(), 1, false, false, shown)
	check(third.size() == 3, "3인칭: 내 고리 + 흰 안쪽 테 + 남 고리 (%d줄)" % third.size())
	check(Color(third[0][4]).is_equal_approx(Color(1, 0, 0, float(cfg.alpha))) and near(third[0][3], float(cfg.r)), "내 색 고리")
	check(Color(third[1][4]).is_equal_approx(Color(1, 1, 1, float(cfg.me_alpha))) and near(third[1][3], float(cfg.r) * float(cfg.me_r)), "흰 안쪽 테: 반지름 × me_r, 흰색")
	check(near(third[1][0], third[0][0]) and near(third[1][1], third[0][1]) and float(third[1][2]) > float(third[0][2]), "흰 테는 같은 자리, 색 고리 바로 위")
	check(Color(third[2][4]).is_equal_approx(Color(0, 1, 0, float(cfg.alpha))), "남은 흰 테 없이 색 고리만")
	check(_rings(_ring_state(), null, false, false, shown).size() == 2, "내 id 를 모르면 (관전) 둘 다 색 고리만")
	check(_rings(_ring_state(), 1, false, true, shown).is_empty() and _rings(_ring_state(), 1, true, true, shown).is_empty(), "하늘 시점이면 전부 안 그림")
	for ph in ["lobby", "over", "results", ""]:
		check(_rings(_ring_state(ph), 1, false, false, shown).is_empty(), "판 중이 아니면 (%s) 안 그림" % ph)
	check(_rings(_ring_state("countdown"), 1, false, false, shown).size() == 3, "카운트다운엔 그림")
	var st := _ring_state()
	st.players[1].alive = false
	check(_rings(st, 1, false, false, shown).size() == 2, "죽은 사람 고리 없음")
	st = _ring_state()
	st.players[1].master = true
	check(_rings(st, 1, false, false, shown).size() == 2, "블록 마스터 고리 없음")
	st = _ring_state()
	st.players[0].alive = false
	check(_rings(st, 1, false, false, shown).size() == 1, "내가 죽으면 (관전) 내 고리·흰 테 없음")
	check(_rings(_ring_state(), 1, false, false, {2: Vector3(6.5, 5.5, 2.0)}).size() == 1, "화면 자리가 없는 사람은 건너뜀")
	check(FRM.wanted({"alive": true}, "playing", false, true, false, cfg) and not FRM.wanted({"alive": true}, "playing", false, true, true, cfg), "wanted: 1인칭의 나만 뺌")
	# 그리는 쪽: 줄 수만큼만 보임, 없으면 노드도 숨김. 판 (World) 이 없으면 안 그림
	var fr = FR.new()
	check(not fr.visible and fr.multimesh.visible_instance_count == 0 and fr.multimesh.use_colors, "처음엔 숨김")
	fr.show_rings(third)
	check(fr.visible and fr.multimesh.visible_instance_count == 3, "세 줄 → 인스턴스 셋")
	var t0: Transform3D = FR.xform(third[0]) # (헤드리스 렌더 서버는 인스턴스 값을 안 돌려줘서 변환 계산을 직접 봄)
	check(t0.origin.is_equal_approx(Co.gxyz(4.5, 5.5, 2.0 + float(cfg.lift))) and near(t0.basis.x.length(), float(cfg.r), 1e-5) and near(t0.basis.z.length(), float(cfg.r), 1e-5) and near(t0.basis.y.length(), 1.0, 1e-5), "인스턴스 자리·반지름 배율")
	fr.show_rings([third[0]])
	check(fr.visible and fr.multimesh.visible_instance_count == 1, "줄이 줄면 인스턴스도 줆")
	fr.update(null, _ring_state(), 1, false, false, shown, {1: 0xff0000, 2: 0x00ff00})
	check(not fr.visible and fr.multimesh.visible_instance_count == 0, "판이 없으면 안 그림")
	fr.free()


# c7-fix F3: 고리 높이가 칸 윗면의 실제 높낮이를 따라감 (테마 지형 꼭대기 칸은 칸마다 정수 높이에서 오르내림 — 예전엔 정수 높이 + lift 라 높이 올라온 칸에서 지형에 묻힘).
# ① 고리가 쓰는 칸 난수 = 지형 셰이더가 받는 값 (block_style cell_looks 의 custom.b) · 셰이더가 그 값에 tf_step 을 곱해 윗면을 올림 ② 맵 7개 꼭대기 칸마다 고리가 윗면보다 위 (묻히는 칸 0)
# ③ 걸친 이웃 칸이 더 올라와 있으면 그 높이 · 낮은 칸·벽은 안 봄 · 위험 액체 위·bump 없음 (그래픽 낮춤) 은 예전 그대로
func test_c7_foot_ring_follows_top() -> void:
	const BS := preload("res://shaders/block_style.gd")
	const G3f := preload("res://shaders/g3.gd")
	const LPf := preload("res://world/lobby_preview.gd")
	var cfg: Dictionary = FWC.FOOT_RING
	# ① 셰이더와 같은 값
	var w := 4
	var h := 3
	var grid := PackedByteArray()
	grid.resize(w * w * h)
	for y in w:
		for x in w:
			grid[y * w + x] = 1
			if (x + y) % 2 == 0:
				grid[(1 * w + y) * w + x] = 1
	var looks: PackedColorArray = BS._cell_looks(grid, w, w, h, {}, h)
	var n := 0
	var off := 0
	for z in h:
		for y in w:
			for x in w:
				if grid[(z * w + y) * w + x] != 1:
					continue
				if absf(looks[n].b - FR.top_rand(x, y, z)) > 1e-6:
					off += 1
				n += 1
	check(n == looks.size() and n == 24 and off == 0, "칸 난수 = 지형 셰이더 custom.b (%d칸 중 어긋남 %d)" % [n, off])
	var src: String = (load("res://shaders/terrain.gdshader") as Shader).code
	check(src.contains("v_lift = INSTANCE_CUSTOM.b * tf_step") and src.contains("tr.z += v_lift"), "셰이더: 윗면 높이 += custom.b × tf_step")
	check(src.contains("- 0.5) * tf_disp * vec3(1.0, 1.0, 0.6)") and absf(float(cfg.disp_k) - 0.5 * 0.6) < 1e-9, "셰이더: 잡음 밀림 위로 가장 많이 0.5 × 0.6 × tf_disp = disp_k")
	check(absf(FR.top_bump(3, 5, 2, 0.14, 0.07) - (FR.top_rand(3, 5, 2) * 0.14 + 0.3 * 0.07)) < 1e-9 and FR.top_bump(3, 5, 2, 0.0, 0.0) == 0.0, "윗면 올라온 양 = 난수 × step + disp 여유 (낮춤이면 0)")
	check(FR.terrain_steps(null) == [0.0, 0.0], "판이 없으면 높낮이 0")
	# ② 맵 7개: 8명 판 시작 지형의 꼭대기 칸 가운데에 서면 고리가 그 칸 윗면 (잡음 밀림 포함) 보다 위. 예전 높이 (정수 + lift) 는 묻히는 칸이 있었음
	var fs: int = LPf.field_size_for(8)
	var buried_old := 0
	var all_tops := 0
	for m in C.MAPS:
		var s = G3f.terrain_style(C.WORLD_MAP_THEME.get(m))
		var step: float = float(s.step) if s != null else 0.0
		var disp: float = float(s.disp) if s != null else 0.0
		var P = LPf.build(str(m), fs, int(C.GRID_H))
		var field := Vector3i(fs, fs, int(C.GRID_H))
		var ground := func(cx: int, cy: int, _fz: float) -> float: return float(P.top[cy * fs + cx])
		var bump := func(cx: int, cy: int, top: int) -> float: return FR.top_bump(cx, cy, top - 1, step, disp) if top > 0 else 0.0
		var buried := 0
		var tops := 0
		for y in fs:
			for x in fs:
				var t := int(P.top[y * fs + x])
				if t <= 0:
					continue
				tops += 1
				var surf: float = t + FR.top_rand(x, y, t - 1) * step + 0.3 * disp # 그 칸 윗면이 가장 높이 올라온 곳
				var st := {"phase": "playing", "players": [{"id": 2, "alive": true}], "lava": {"active": false, "z": 0.0}}
				var out: Array = FRM.rings(st, 1, false, false, {2: Vector3(x + 0.5, y + 0.5, float(t))}, {2: 0x00ff00}, field, ground, cfg, bump)
				if out.size() != 1 or float(out[0][2]) <= surf:
					buried += 1
				if float(t) + float(cfg.lift) <= surf:
					buried_old += 1
		all_tops += tops
		check(buried == 0, "%s: 꼭대기 %d칸 중 고리가 윗면 아래인 칸 %d" % [m, tops, buried])
	check(all_tops > 300 and buried_old > 0, "예전 높이 (정수 + lift) 는 묻히는 칸이 있었음 (%d칸) — 이 테스트가 그 문제를 잡음" % buried_old)
	# ③ 이웃·위험 액체·bump 없음
	var flat := func(_x, _y, _z): return 2.0
	var bmp := func(cx: int, cy: int, _top: int) -> float: return 0.07 if cx == 6 and cy == 5 else (-0.05 if cx == 5 and cy == 5 else 0.0)
	var one := {"phase": "playing", "players": [{"id": 2, "alive": true}], "lava": {"active": false, "z": 0.0}}
	var f10 := Vector3i(10, 10, 32)
	var mid: Array = FRM.rings(one, 1, false, false, {2: Vector3(5.5, 5.5, 2.0)}, {2: 0x00ff00}, f10, flat, cfg, bmp)
	check(near(mid[0][2], 2.0 - 0.05 + float(cfg.lift)), "칸 가운데: 제 칸 윗면 (내려간 칸이면 고리도 내려감) %s" % mid[0][2])
	var edge: Array = FRM.rings(one, 1, false, false, {2: Vector3(5.9, 5.5, 2.0)}, {2: 0x00ff00}, f10, flat, cfg, bmp)
	check(near(edge[0][2], 2.0 + 0.07 + float(cfg.lift)), "칸 가장자리: 고리가 걸친 더 올라온 이웃 칸 높이 %s" % edge[0][2])
	var wall := func(cx, _y, _z): return 3.0 if cx == 6 else 2.0
	var by_wall: Array = FRM.rings(one, 1, false, false, {2: Vector3(5.9, 5.5, 2.0)}, {2: 0x00ff00}, f10, wall, cfg, bmp)
	check(near(by_wall[0][2], 2.0 - 0.05 + float(cfg.lift)), "높이가 다른 이웃 (벽·낭떠러지) 은 안 봄 %s" % by_wall[0][2])
	var lava := {"phase": "playing", "players": [{"id": 2, "alive": true}], "lava": {"active": true, "z": 2.6}}
	var on_lava: Array = FRM.rings(lava, 1, false, false, {2: Vector3(5.9, 5.5, 2.6)}, {2: 0x00ff00}, f10, flat, cfg, bmp)
	check(near(on_lava[0][2], 2.6 + float(cfg.lift)), "위험 액체 표면 위면 칸 높낮이를 안 더함 %s" % on_lava[0][2])
	var me: Array = FRM.rings({"phase": "playing", "players": [{"id": 1, "alive": true}], "lava": {}}, 1, false, false, {1: Vector3(5.9, 5.5, 2.0)}, {1: 0xff0000}, f10, flat, cfg, bmp)
	check(me.size() == 2 and near(me[1][2], 2.0 + 0.07 + float(cfg.lift) + float(cfg.me_lift)), "내 흰 테도 같은 기준 + me_lift")
	var plain: Array = FRM.rings(one, 1, false, false, {2: Vector3(5.9, 5.5, 2.0)}, {2: 0x00ff00}, f10, flat, cfg)
	check(near(plain[0][2], 2.0 + float(cfg.lift)), "bump 없음 (그래픽 낮춤·테마 없음) = 정수 높이 + lift")
	check(FRM.top_bump(0.2, 0.2, 0.42, 2.0, 2.0, f10, flat, func(_x, _y, _t): return 0.03) == 0.03 and FRM.top_bump(5.5, 5.5, 0.42, 2.0, 2.0, f10, func(_x, _y, _z): return 1.0, bmp) == 0.0, "판 가장자리 (격자 밖 칸은 안 봄)·맞는 칸 없음 = 0")


# 재질: 표준 재질 모양 (warm_scan STD_KEYS 안 — 새 셰이더 모양 없음), 빛 안 받음·반투명·정점 색·깊이 검사 켬, 순서는 이름표 외곽선 아래. 메시: 납작한 고리, 한 번에 그림
func test_c7_foot_ring_material() -> void:
	const WS := preload("res://world/warm_scan.gd")
	const MF := preload("res://core/mat_first.gd")
	var cfg: Dictionary = FWC.FOOT_RING
	var m: StandardMaterial3D = FR.material()
	var keys := []
	for k in WS.STD_KEYS:
		keys.append(MF.mat_key(WS.std_material(k)))
	check(keys.has(MF.mat_key(m)), "재질 열쇠가 미리 그리기 표 안 (%s)" % MF.mat_key(m))
	check(WS.STD_KEYS.has(cfg.key), "config 의 key 가 STD_KEYS 의 한 줄")
	check(m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and m.vertex_color_use_as_albedo and not m.no_depth_test, "빛 안 받음·반투명·정점 색·깊이 검사")
	check(m.render_priority == int(cfg.order) and m.render_priority < FWC.LABEL_PRIORITY - 1, "순서 %d < 이름표 외곽선 %d" % [m.render_priority, FWC.LABEL_PRIORITY - 1])
	var fr = FR.new()
	check(fr.material_override != null and MF.mat_key(fr.material_override) == MF.mat_key(m) and fr.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "노드 재질·그림자 없음")
	check(fr.multimesh.instance_count >= int(C.ROOM_MAX) + 1, "방 최대 인원 + 내 흰 테")
	var mesh: ArrayMesh = fr.multimesh.mesh
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var rmin := INF
	var rmax := 0.0
	var flat := true
	for v in vs:
		rmin = minf(rmin, Vector2(v.x, v.z).length())
		rmax = maxf(rmax, Vector2(v.x, v.z).length())
		flat = flat and v.y == 0.0
	check(flat and near(rmax, 1.0, 1e-5) and near(rmin, float(cfg.inner), 1e-5), "납작한 고리: 바깥 1, 안쪽 inner (%.3f~%.3f)" % [rmin, rmax])
	check(mesh.get_surface_count() == 1 and idx.size() == int(cfg.segs) * 6, "표면 하나, 조각마다 삼각형 둘")
	# 앞면이 위를 봄 (고도 앞면 = 시계 방향 → 삼각형 법선 (b-a)×(c-a) 가 아래)
	var up := true
	for i in range(0, idx.size(), 3):
		var n := (vs[idx[i + 1]] - vs[idx[i]]).cross(vs[idx[i + 2]] - vs[idx[i]])
		up = up and n.y < 0.0
	check(up, "모든 삼각형 앞면이 위")
	fr.free()


# ---------- c10-u2 아이템 종류별 코드 모델 (world/item_look.gd · item_models.gd · item_view_math.gd · items_view.gd · shots.gd _bombs) ----------
const IL := preload("res://world/item_look.gd")
const IM := preload("res://world/item_models.gd")
const IVM := preload("res://world/item_view_math.gd")
const IV := preload("res://world/items_view.gd")


# 표면 0 의 삼각형마다 [넓이, 첫 꼭짓점 색]
func _c10_tris(m: Mesh) -> Array:
	var a := m.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var out := []
	for i in range(0, ix.size(), 3):
		out.append([(vs[ix[i + 1]] - vs[ix[i]]).cross(vs[ix[i + 2]] - vs[ix[i]]).length() * 0.5, cs[ix[i]]])
	return out


func _c10_rgb_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func test_c10_item_models_cover_kinds() -> void:
	check(IL.KINDS == ["bomb", "knockback", "speed", "jump", "ghost", "brick", "counter"], "종류표 7종·순서")
	var meshes: Array = IL.KINDS.map(func(k): return IM.mesh(k))
	meshes.append(IM.proj_mesh())
	for i in meshes.size():
		var name := str(IL.KINDS[i]) if i < IL.KINDS.size() else "투사체"
		var m = meshes[i]
		check(m is ArrayMesh and m.get_surface_count() == 1, "%s: ArrayMesh 표면 하나 (그리기 한 번)" % name)
		if not m is ArrayMesh:
			continue
		var a: Array = m.surface_get_arrays(0)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var tris := IM.tri_count(m)
		check(tris > 0 and tris <= int(IL.MAX_TRIS), "%s: 삼각형 %d ≤ %d" % [name, tris, IL.MAX_TRIS])
		check(a[Mesh.ARRAY_COLOR] is PackedColorArray and (a[Mesh.ARRAY_COLOR] as PackedColorArray).size() == vs.size(), "%s: 정점 색 배열" % name)
		var unit := true
		for n in (a[Mesh.ARRAY_NORMAL] as PackedVector3Array):
			unit = unit and absf(n.length() - 1.0) < 1e-3
		check(unit and (a[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == vs.size(), "%s: 법선 길이 1" % name)
		var box: AABB = m.get_aabb()
		var long := box.get_longest_axis_size()
		if i < IL.KINDS.size():
			check(long >= 0.5 and long <= 0.62 and near(long, IL.SIZE, 1e-4), "%s: 긴 변 %.3f (0.5~0.62)" % [name, long])
			check(IM.mesh(IL.KINDS[i]) == m, "%s: 한 번 만들어 나눠 씀" % name)
		else:
			check(near(long, C.PROJECTILE_RADIUS * 2.0, 1e-4), "투사체: 긴 변 = 지름 (%.3f)" % long)
			check(absf(box.position.x + box.end.x) < 1e-4, "투사체: 좌우 대칭")
		check(absf(box.position.y + box.end.y) < 1e-4, "%s: 세로 가운데가 0" % name)
	for k in ["control", "zzz", ""]:
		var b = IM.mesh(k)
		check(b is BoxMesh and near((b as BoxMesh).size.x, FWC.ITEM_SIZE), "표에 없는 종류 '%s' 는 예전 상자" % k)
		check(IVM.kind_of(k) == IL.BOX, "'%s' → 상자 묶음" % k)
	for k in C.ITEM_POOL:
		check(IL.PARTS.has(k) and IL.MAIN.has(k), "판에 나오는 아이템 '%s' 에 모델·주색" % k)
	# 놓인 폭탄: 몸통 + 빛나는 조각 = 바닥 아이템 폭탄 (같은 삼각형 수·같은 테두리 상자)
	var sp: Array = IM.bomb_split(C.BOMB_MODEL_SIZE)
	var whole := IM.build(IL.PARTS.bomb, C.BOMB_MODEL_SIZE)
	check(IM.tri_count(sp[0]) + IM.tri_count(sp[1]) == IM.tri_count(whole) and IM.tri_count(sp[1]) > 0, "폭탄 나눔: 몸통 %d + 빛남 %d = %d" % [IM.tri_count(sp[0]), IM.tri_count(sp[1]), IM.tri_count(whole)])
	var both: AABB = (sp[0] as ArrayMesh).get_aabb().merge((sp[1] as ArrayMesh).get_aabb())
	check(both.position.is_equal_approx(whole.get_aabb().position) and both.size.is_equal_approx(whole.get_aabb().size), "폭탄 나눔: 겹치면 같은 크기·자리")
	check(near(whole.get_aabb().size.y, C.BOMB_MODEL_SIZE, 1e-4), "놓인 폭탄: 키 = BOMB_MODEL_SIZE (바닥에 닿음)")


func test_c10_item_colors() -> void:
	for k in IL.KINDS:
		var main: Color = Co.color(int(IL.MAIN[k]))
		check(main.s <= 0.72, "%s 주색 채도 %.2f ≤ 0.72" % [k, main.s])
		for o in IL.KINDS:
			if o != k:
				check(_c10_rgb_dist(main, Co.color(int(IL.MAIN[o]))) >= 0.2, "%s·%s 주색 거리 %.2f ≥ 0.2" % [k, o, _c10_rgb_dist(main, Co.color(int(IL.MAIN[o])))])
		if k != "ghost": # 유령은 흰빛 — 흰 플레이어 색과 가까워도 됨 (모양·눈으로 가름)
			for pc in C.PLAYER_PALETTE:
				check(_c10_rgb_dist(main, Co.color(int(pc))) >= 0.12, "%s 주색이 플레이어 색 %06x 과 거리 %.2f ≥ 0.12" % [k, int(pc), _c10_rgb_dist(main, Co.color(int(pc)))])
		var total := 0.0
		var dark := 0.0
		var has_main := false
		for t in _c10_tris(IM.mesh(k)):
			var c: Color = t[1]
			total += float(t[0])
			if c.get_luminance() < 0.12:
				dark += float(t[0])
			has_main = has_main or c.is_equal_approx(main)
		check(has_main, "%s: 주색이 모델에 칠해져 있음" % k)
		check(total > 0.0 and dark / total <= 0.1, "%s: 어두운 (밝기 < 0.12) 면 %.0f%% ≤ 10%%" % [k, 100.0 * dark / maxf(total, 1e-9)])


func test_c10_item_groups() -> void:
	var names: Array = IVM.order()
	check(names == ["bomb", "knockback", "speed", "jump", "ghost", "brick", "counter", "box"], "묶음 순서: 표 + 상자")
	var list := [{"type": "ghost", "x": 1, "y": 2, "z": 0}, {"type": "control", "x": 3, "y": 2, "z": 1}, {"type": "bomb", "x": 4, "y": 4, "z": 0}, {"type": "ghost", "x": 5, "y": 5, "z": 2}, {"x": 6, "y": 6, "z": 0}]
	var g: Array = IVM.groups(list)
	check(g.map(func(e): return e[0]) == names, "묶음은 늘 같은 순서로 빠짐없이")
	check(g.map(func(e): return e[1]) == [[2], [], [], [], [0, 3], [], [], [1, 4]], "종류별 번호 (스냅샷 순서), 모르는 종류·종류 없음 → 상자: %s" % str(g))
	check(IVM.groups([]).all(func(e): return (e[1] as Array).is_empty()), "빈 목록 → 전부 0개")
	# 자리·출렁임 = 예전 식
	var p: Vector3 = IVM.item_pos(list[3], 3, 1234.0)
	check(p.is_equal_approx(Vector3(5.5, 5.5, 2 + FWC.ITEM_BOB[0] + sin(1234.0 / FWC.ITEM_BOB[2] + 3) * FWC.ITEM_BOB[1])), "자리·출렁임이 예전 식 그대로")
	var row: Array = IVM.ring_row(list[1])
	check(near(row[0], 3.5) and near(row[1], 2.5) and near(row[2], 1.02) and near(row[3], 0.38) and (row[4] as Color).a <= 0.55 and _c10_rgb_dist(row[4], Co.color(C.GAME_LIGHT_ITEM)) < 1e-4, "받침 고리: 칸 윗면 + 0.02, 반지름 0.38, 알파 ≤ 0.55, 아이템 빛 노랑")
	# 노드: 0개인 묶음은 숨김, 있는 묶음만 보임
	var iv = IV.new()
	var shown := func() -> Array:
		var out := []
		for n in names:
			if (iv.models[n] as MultiMeshInstance3D).visible:
				out.append("%s%d" % [n, (iv.models[n] as MultiMeshInstance3D).multimesh.visible_instance_count])
		return out
	check(shown.call() == [] and not iv.rings.visible and not iv.casters.visible and not iv.projs.visible, "처음엔 전부 숨김")
	iv.update({"items": list, "projectiles": [{"x": 1.0, "y": 2.0, "z": 3.0}]}, 0.016, 1000.0)
	check(shown.call() == ["bomb1", "ghost2", "box2"], "있는 종류만 보임: %s" % str(shown.call()))
	check(iv.rings.visible and iv.rings.multimesh.visible_instance_count == 5 and iv.casters.visible and iv.casters.multimesh.visible_instance_count == 5, "받침 고리·그림자 상자는 아이템마다")
	check(iv.projs.visible and iv.projs.multimesh.visible_instance_count == 1 and iv.projs.multimesh.mesh == IM.proj_mesh(), "투사체 = 글러브 공")
	check(FR.xform(row).origin.is_equal_approx(Co.gxyz(3.5, 2.5, 1.02)) and near(FR.xform(row).basis.x.length(), 0.38), "고리 인스턴스 변환 (자리·반지름) — 헤드리스는 MultiMesh 값을 못 읽어 변환 식으로 확인")
	check(iv.casters.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and names.all(func(n): return (iv.models[n] as MultiMeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "그림자는 그림자 상자 하나로")
	iv.update({"items": [{"type": "speed", "x": 0, "y": 0, "z": 0}]}, 0.016, 2000.0)
	check(shown.call() == ["speed1"] and not iv.projs.visible and iv.rings.multimesh.visible_instance_count == 1, "줄면 나머지는 다시 숨김: %s" % str(shown.call()))
	iv.update({}, 0.016, 3000.0)
	check(shown.call() == [] and not iv.rings.visible and not iv.casters.visible, "0개면 전부 숨김")
	iv.free()


func test_c10_item_px() -> void:
	for k in IL.KINDS:
		var long: float = (IM.mesh(k) as ArrayMesh).get_aabb().get_longest_axis_size()
		var px: float = IVM.px(long, 6.0, 75.0, 720.0)
		check(px >= 30.0, "%s: 6칸·시야 75°·720p 에서 긴 변 %.1fpx ≥ 30" % [k, px])
	check(near(IVM.px(1.0, 1.0, 90.0, 720.0), 360.0, 1e-5), "거리 1·시야 90° 면 1칸 = 화면 높이의 반")
	check(near(IVM.px(0.55, 12.0, 75.0, 720.0) * 2.0, IVM.px(0.55, 6.0, 75.0, 720.0), 1e-5), "거리 두 배면 반")


func test_c10_item_mats() -> void:
	const G3 := preload("res://shaders/g3.gd")
	const WS := preload("res://world/warm_scan.gd")
	const MF := preload("res://core/mat_first.gd")
	var iv = IV.new()
	var warm: ShaderMaterial = G3.toon_material(Color.WHITE, {"vertex_color": true, "outline": false}) # G3.prewarm 이 데우는 갈래
	check(iv.mat.shader == warm.shader and iv.mat.shader.resource_path.get_file() == "toon.gdshader", "모델 재질 = 툰 셰이더 (새 셰이더 없음)")
	check(iv.mat.get_shader_parameter("use_vertex_color") == true, "정점 색 켬")
	check(MF.mat_key(iv.mat) == MF.mat_key(G3.toon_material(Color.WHITE)), "외곽선까지 툰 재질과 같은 열쇠 (%s)" % MF.mat_key(iv.mat))
	for k in IL.KINDS:
		check((iv.models[k] as MultiMeshInstance3D).material_override == iv.mat, "%s: 재질 하나를 나눠 씀" % k)
	check(iv.projs.material_override == iv.mat, "투사체도 같은 재질")
	var keys := []
	for k in WS.STD_KEYS:
		keys.append(MF.mat_key(WS.std_material(k)))
	check(keys.has(MF.mat_key(iv.rings.material_override)), "고리 재질 열쇠가 미리 그리기 표 안 (%s)" % MF.mat_key(iv.rings.material_override))
	check(MF.mat_key(iv.rings.material_override) == MF.mat_key(FR.material()), "고리 = 발밑 고리 재질 모양")
	var old := StandardMaterial3D.new() # 예전 아이템 상자 재질 모양
	old.emission_enabled = true
	check(MF.mat_key(iv.items.material_override) == MF.mat_key(old), "상자 묶음 재질은 예전 그대로")
	iv.free()
	# 놓인 폭탄 (shots.gd): 툰 재질 둘 (몸통·빛남), 표준 재질 없음
	const Shots := preload("res://world/shots.gd")
	var sh = Shots.new()
	sh._bombs([{"x": 2, "y": 3, "z": 1, "left": C.BOMB_FUSE_MS}], 0.0)
	var n: MeshInstance3D = sh.bombs[0]
	var glow: MeshInstance3D = n.get_child(0)
	check(n.visible and n.position.is_equal_approx(Co.gxyz(2.5, 3.5, 1 + C.BOMB_MODEL_SIZE / 2)), "놓인 폭탄 자리")
	check(n.material_override is ShaderMaterial and glow.material_override is ShaderMaterial and (n.material_override as ShaderMaterial).shader == warm.shader and (glow.material_override as ShaderMaterial).shader == warm.shader, "놓인 폭탄 재질 = 툰")
	check(n.mesh == IM.bomb_split(C.BOMB_MODEL_SIZE)[0] and glow.mesh == IM.bomb_split(C.BOMB_MODEL_SIZE)[1], "놓인 폭탄 = 아이템 폭탄 모델 (몸통 + 빛남)")
	check((glow.material_override as ShaderMaterial).get_shader_parameter("emissive") == Co.color(IL.BOMB_GLOW), "켜진 반 주기 (시각 0): 띠·불씨 발광")
	sh._bombs([{"x": 2, "y": 3, "z": 1, "left": C.BOMB_FUSE_MS}], IVM.bomb_period(C.BOMB_FUSE_MS) * 1.5)
	check((glow.material_override as ShaderMaterial).get_shader_parameter("emissive") == Color.BLACK and (n.material_override as ShaderMaterial).get_shader_parameter("emissive") == Color.BLACK, "꺼진 반 주기: 발광 없음")
	sh._bombs([], 0.0)
	check(not n.visible, "폭탄이 없으면 숨김")
	sh.free()


func test_c10_bomb_blink_same() -> void:
	for left in [0.0, 1.0, 150.0, 750.0, 1499.0, 1500.0, 2200.0, 9000.0]:
		var old := 80 + minf(1.0, float(left) / C.BOMB_FUSE_MS) * 320 # 예전 shots.gd 식
		check(near(IVM.bomb_period(left), old), "남은 %dms: 주기 %.1f = 예전 %.1f" % [int(left), IVM.bomb_period(left), old])
		for now in [0.0, 79.0, 81.0, 399.0, 401.0, 12345.0, 98765.4]:
			check(IVM.bomb_on(now, left) == (int(floor(float(now) / old)) % 2 == 0), "남은 %dms·시각 %.1f: 켜짐이 예전과 같음" % [int(left), now])
	check(IVM.bomb_period(0.0) < IVM.bomb_period(C.BOMB_FUSE_MS), "남은 시간이 짧을수록 빨리")


# ---------- c10-fix F3 아이템 나옴·사라짐 신호 (world/item_look.gd SIGNAL · item_view_math.gd · items_view.gd) ----------

# 판 중 스냅샷 모양 (신호 판단에 쓰는 값만)
func _c10_item_st(time: float, items: Array, round_n := 1, phase := "playing") -> Dictionary:
	return {"phase": phase, "time": time, "mode": "survival", "practice": null, "round": {"n": round_n}, "items": items, "projectiles": []}


# 순수 계산: 열쇠 (종류·칸 — 높이는 뺌) · 신호를 내도 되는 스냅샷 쌍 · 나옴·사라짐 고르기 · 시간에 따른 모양 · 수치가 화풍 기준서 안
func test_c10_fix_item_signal_math() -> void:
	var S: Dictionary = IL.SIGNAL
	for k in ["born", "gone"]:
		check(float(S[k].ms) >= 350.0 and float(S[k].ms) <= 600.0, "%s 길이 %dms 가 0.35~0.6초 안" % [k, int(S[k].ms)])
	check(float(S.born.alpha) <= 0.55 and float(S.born.ring_alpha) <= 0.55 and float(S.gone.alpha) <= 0.55 and float(S.born.core_alpha) <= 1.0, "알파 0.55 이하 (흰 심만 예외)")
	check(float(S.born.h) >= 2.0 and float(S.born.h) < float(preload("res://fx/event_fx_config.gd").EVENT_FX.supply.h), "기둥은 사람 키보다 높고 보급 이벤트 기둥보다 낮음 (%s)" % S.born.h)
	check(int(S.born_max) == 1 and float(S.gap_ms) == 500.0 and int(S.max) >= 8, "한 번에 하나 · 시각 차 500ms · 상한")
	var a := {"type": "bomb", "x": 3, "y": 4, "z": 1}
	check(IVM.item_key(a) == "bomb:3:4" and IVM.item_key({"type": "bomb", "x": 3, "y": 4, "z": 5}) == IVM.item_key(a), "열쇠 = 종류·칸 (높이는 기둥 꼭대기를 따라 바뀌니 뺌)")
	check(IVM.item_key({"type": "jump", "x": 3, "y": 4, "z": 1}) != IVM.item_key(a) and IVM.item_key({"type": "bomb", "x": 4, "y": 3, "z": 1}) != IVM.item_key(a), "종류·칸이 다르면 다른 열쇠")
	var seen: Dictionary = IVM.seen_of([a, {"type": "jump", "x": 0, "y": 0, "z": 2}])
	check(seen.size() == 2 and seen["bomb:3:4"] == [3, 4, 1.0, "bomb"] and IVM.seen_of(null).is_empty() and IVM.seen_of([]).is_empty(), "스냅샷 items → 열쇠 표 (%s)" % [seen])
	# 신호를 내도 되는 쌍
	var m1: Array = IVM.meta_of(_c10_item_st(1000.0, []))
	var m2: Array = IVM.meta_of(_c10_item_st(1033.0, []))
	check(m1 == [1, "playing", 1000.0, false], "meta = [판 번호, 단계, 서버 시각, 연습인가] (%s)" % [m1])
	check(IVM.signal_ok(m1, m2, 500.0), "판 중 이어진 두 스냅샷: 냄")
	check(not IVM.signal_ok([], m2, 500.0), "첫 스냅샷: 안 냄")
	check(not IVM.signal_ok(m1, IVM.meta_of(_c10_item_st(1033.0, [], 2)), 500.0), "판이 바뀜: 안 냄")
	check(not IVM.signal_ok(m1, IVM.meta_of(_c10_item_st(1033.0, [], 1, "over")), 500.0) and not IVM.signal_ok(IVM.meta_of(_c10_item_st(990.0, [], 1, "countdown")), m1, 500.0), "판 끝·카운트다운: 안 냄")
	check(not IVM.signal_ok(m1, IVM.meta_of(_c10_item_st(1700.0, [])), 500.0) and IVM.signal_ok(m1, IVM.meta_of(_c10_item_st(1500.0, [])), 500.0), "서버 시각이 0.5초 넘게 뜀 (재접속·멈춤): 안 냄")
	check(not IVM.signal_ok(m2, m1, 500.0) and not IVM.signal_ok(m1, m1, 500.0), "시각이 거꾸로·그대로: 안 냄")
	var pr := _c10_item_st(1033.0, [])
	pr["practice"] = {"dummies": []}
	var tu := _c10_item_st(1033.0, [])
	tu["mode"] = "practice"
	check(not IVM.signal_ok(m1, IVM.meta_of(pr), 500.0) and not IVM.signal_ok(IVM.meta_of(tu), m2, 500.0), "연습·튜토리얼 (단계 깔기): 안 냄")
	# 견주기
	var b := {"type": "jump", "x": 0, "y": 0, "z": 2}
	var c := {"type": "ghost", "x": 7, "y": 7, "z": 0}
	var d: Dictionary = IVM.item_diff(IVM.seen_of([a]), IVM.seen_of([a, b]), 1)
	check(d.born == [[0, 0, 2.0, "jump"]] and d.gone == [], "새로 나옴 (%s)" % [d])
	d = IVM.item_diff(IVM.seen_of([a, b]), IVM.seen_of([b]), 1)
	check(d.born == [] and d.gone == [[3, 4, 1.0, "bomb"]], "없어짐 — 자리·높이는 앞 스냅샷 것 (%s)" % [d])
	d = IVM.item_diff(IVM.seen_of([a]), IVM.seen_of([{"type": "bomb", "x": 3, "y": 4, "z": 3}]), 1)
	check(d.born == [] and d.gone == [], "높이만 바뀜 (밑에 블록이 쌓임): 신호 없음")
	d = IVM.item_diff(IVM.seen_of([a]), IVM.seen_of([b, c]), 1)
	check(d.born == [] and d.gone == [[3, 4, 1.0, "bomb"]], "한 스냅샷에 둘 이상 나옴 (보급 이벤트·단계 깔기): 나옴 신호 없음, 사라짐은 냄 (%s)" % [d])
	d = IVM.item_diff(IVM.seen_of([a, b, c]), {}, 1)
	check(d.gone.size() == 3, "사라짐은 여럿이어도 냄")
	# 시간에 따른 모양
	var at0: Array = IVM.born_at(0.0, S.born)
	check(near(at0[0], 1.0) and near(at0[1], float(S.born.ring[0])) and near(at0[2], 1.0), "나온 순간: 기둥 1 · 고리 처음 반지름 (%s)" % [at0])
	var last_r := 0.0
	var last_a := 2.0
	for i in 20:
		var at: Array = IVM.born_at(float(S.born.ms) * i / 20.0, S.born)
		check(float(at[1]) >= last_r and float(at[2]) <= last_a and float(at[0]) <= 1.0 and float(at[0]) >= 0.0, "고리는 퍼지며 흐려짐 (%d)" % i)
		last_r = at[1]
		last_a = at[2]
	check(near(IVM.born_at(float(S.born.ms) * float(S.born.hold), S.born)[0], 1.0) and float(IVM.born_at(float(S.born.ms) * 0.9, S.born)[0]) < 0.2, "기둥: hold 까지 그대로, 끝엔 거의 0")
	check(IVM.born_at(float(S.born.ms), S.born) == [0.0, 0.0, 0.0] and IVM.born_at(-1.0, S.born) == [0.0, 0.0, 0.0] and last_r <= float(S.born.ring[1]), "끝나면 0")
	var g0: Array = IVM.gone_at(0.0, S.gone)
	var g1: Array = IVM.gone_at(float(S.gone.ms) * 0.5, S.gone)
	check(near(g0[0], float(S.gone.ring[0])) and near(g0[1], 1.0) and near(g0[2], 1.0) and float(g1[0]) > float(g0[0]) and near(g1[1], 0.5) and near(g1[2], 0.25) and IVM.gone_at(float(S.gone.ms), S.gone) == [0.0, 0.0, 0.0], "사라짐: 고리는 퍼지며 흐려지고 빛 줄은 더 빨리 꺼지고, 끝나면 0")
	check(float(S.gone.h) < float(S.born.h) * 0.5 and float(S.gone.width) > float(S.born.width), "사라짐 빛 줄은 나옴 기둥보다 훨씬 짧고 굵음 (둘이 갈림)")
	var y := Co.color(C.GAME_LIGHT_ITEM)
	var gc: Color = IVM.gone_color("knockback", float(S.gone.mix))
	check(_c10_rgb_dist(gc, y) > 0.05 and _c10_rgb_dist(gc, y) < _c10_rgb_dist(gc, Co.color(IL.MAIN.knockback)) and _c10_rgb_dist(IVM.gone_color("control", 0.25), y) < 1e-6, "사라짐 색 = 아이템 빛 노랑에 종류 주색 조금 (모르는 종류는 노랑)")
	var row: Array = IVM.signal_ring_row({"x": 3, "y": 4, "z": 1.0}, 0.7, y, float(S.lift))
	check(near(row[0], 3.5) and near(row[1], 4.5) and near(row[2], 1.0 + float(S.lift)) and near(row[3], 0.7) and float(S.lift) > float(IL.RING.lift), "신호 고리 줄: 칸 가운데·받침 고리 바로 위")


# 노드: 스냅샷이 바뀔 때 나옴·사라짐 신호가 생기고, 고리는 받침 고리 묶음에 얹히고, 기둥 묶음은 나오는 동안만 보임. 첫 스냅샷·판 바뀜·연습·한꺼번에 둘은 조용히
func test_c10_fix_item_signal_view() -> void:
	const CellLod := preload("res://world/cell_lod.gd")
	const G3 := preload("res://shaders/g3.gd")
	const WS := preload("res://world/warm_scan.gd")
	const MF := preload("res://core/mat_first.gd")
	var S: Dictionary = IL.SIGNAL
	var keep_cam = CellLod.test_cam
	var keep_low: bool = G3.low
	G3.low = false
	CellLod.test_cam = {"pos": Co.gxyz(5.5, -6.0, 1.45), "fov": 75.0}
	var iv = IV.new()
	check(not iv.pillars.visible and iv.sigs.is_empty() and iv.pillars.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "처음엔 신호·기둥 없음")
	var keys := []
	for k in WS.STD_KEYS:
		keys.append(MF.mat_key(WS.std_material(k)))
	check(keys.has(MF.mat_key(iv.pillars.material_override)), "기둥 재질 열쇠가 미리 그리기 표 안 — 새 셰이더 없음 (%s)" % MF.mat_key(iv.pillars.material_override))
	var a := {"type": "bomb", "x": 3, "y": 4, "z": 1}
	var b := {"type": "jump", "x": 6, "y": 2, "z": 0}
	var c := {"type": "ghost", "x": 8, "y": 8, "z": 0}
	var t := 1000.0
	var now := 50000.0
	# 첫 스냅샷에 이미 있던 아이템: 신호 없음
	iv.update(_c10_item_st(t, [a]), 0.016, now)
	check(iv.sigs.is_empty() and iv.rings.multimesh.visible_instance_count == 1 and not iv.pillars.visible, "첫 스냅샷: 조용히 (받침 고리 1)")
	# 새 아이템 하나: 나옴 신호 (기둥 1 + 고리 1 을 받침 고리 2 뒤에)
	t += 33.0
	now += 33.0
	var st2 := _c10_item_st(t, [a, b])
	iv.update(st2, 0.016, now)
	check(iv.sigs.size() == 1 and iv.sigs[0].kind == "born" and iv.sigs[0].x == 6 and iv.sigs[0].y == 2 and iv.sigs[0].type == "jump" and iv.sigs[0].t0 == now, "새 아이템: 나옴 신호 (%s)" % [iv.sigs])
	check(iv.rings.multimesh.visible_instance_count == 3 and iv.pillars.visible and iv.pillars.multimesh.visible_instance_count == 1, "고리 2 + 신호 고리 1 (같은 묶음), 기둥 1")
	iv.update(st2, 0.016, now + 100.0)
	check(iv.sigs.size() == 1 and iv.pillars.multimesh.visible_instance_count == 1, "같은 스냅샷을 다시 그려도 신호는 하나")
	# 눈앞 (1.5 m 안) 기둥은 안 그림, 그래픽 낮춤이면 고리만
	CellLod.test_cam = {"pos": Co.gxyz(6.5, 2.5, 1.45), "fov": 75.0}
	iv.update(st2, 0.016, now + 120.0)
	check(not iv.pillars.visible and iv.rings.multimesh.visible_instance_count == 3, "카메라 바로 앞 기둥은 뺌 (화면을 덮는 번쩍 금지) — 고리는 그대로")
	CellLod.test_cam = {"pos": Co.gxyz(5.5, -6.0, 1.45), "fov": 75.0}
	G3.low = true
	iv.update(st2, 0.016, now + 140.0)
	check(not iv.pillars.visible and iv.rings.multimesh.visible_instance_count == 3, "그래픽 낮춤: 기둥 없이 고리만")
	G3.low = false
	# 길이가 지나면 신호가 빠지고 기둥 묶음은 숨김
	iv.update(st2, 0.016, now + float(S.born.ms) + 1.0)
	check(iv.sigs.is_empty() and not iv.pillars.visible and iv.rings.multimesh.visible_instance_count == 2, "0.5초 뒤: 신호 끝 (받침 고리 2 만)")
	# 아이템이 없어짐 (누가 주움): 사라짐 신호 = 겹 고리 2, 기둥 없음. 마지막 아이템이 없어져도 고리 묶음은 신호 동안 보임
	t += 33.0
	now += 1000.0
	var st3 := _c10_item_st(t, [b])
	iv.update(st3, 0.016, now)
	check(iv.sigs.size() == 1 and iv.sigs[0].kind == "gone" and iv.sigs[0].x == 3 and iv.sigs[0].y == 4 and iv.sigs[0].z == 1.0 and iv.sigs[0].type == "bomb", "없어짐: 사라짐 신호 — 앞 스냅샷의 자리·높이 (%s)" % [iv.sigs])
	check(iv.rings.multimesh.visible_instance_count == 3 and iv.pillars.visible and iv.pillars.multimesh.visible_instance_count == 1, "받침 고리 1 + 겹 고리 2 + 짧은 빛 줄 1")
	G3.low = true
	iv.update(st3, 0.016, now + 10.0)
	check(iv.rings.multimesh.visible_instance_count == 3 and not iv.pillars.visible, "그래픽 낮춤: 사라짐도 고리만")
	G3.low = false
	t += 33.0
	var st4 := _c10_item_st(t, [])
	iv.update(st4, 0.016, now + 33.0)
	check(iv.sigs.size() == 2 and iv.rings.visible and iv.rings.multimesh.visible_instance_count == 4 and not iv.casters.visible and iv.pillars.multimesh.visible_instance_count == 2, "아이템 0 이어도 사라짐 신호는 그림 (겹 고리 2 × 2 · 빛 줄 2)")
	iv.update(st4, 0.016, now + 33.0 + float(S.gone.ms) + 1.0)
	check(iv.sigs.is_empty() and not iv.rings.visible and not iv.pillars.visible, "끝나면 다 숨김 (그리기 0)")
	# 한 스냅샷에 둘 (보급 이벤트): 나옴 신호 없음
	t += 33.0
	iv.update(_c10_item_st(t, [a, c]), 0.016, now + 2000.0)
	check(iv.sigs.is_empty(), "한꺼번에 둘: 조용히 (보급은 이벤트 효과가 제 빛 기둥을 그림)")
	# 판 끝·새 판: 아이템이 사라져도 신호 없음, 남은 신호도 지움
	t += 33.0
	iv.update(_c10_item_st(t, [a, c, b]), 0.016, now + 2033.0)
	check(iv.sigs.size() == 1, "하나 더 나옴: 신호 1")
	t += 33.0
	iv.update(_c10_item_st(t, [], 1, "over"), 0.016, now + 2066.0)
	check(iv.sigs.is_empty(), "판 끝: 신호 없음 · 남은 신호 지움")
	iv.update(_c10_item_st(0.0, [a], 2, "countdown"), 0.016, now + 9000.0)
	iv.update(_c10_item_st(33.0, [a, b], 2, "countdown"), 0.016, now + 9033.0)
	check(iv.sigs.is_empty(), "카운트다운: 신호 없음")
	# 재접속처럼 서버 시각이 뜀: 그 사이 바뀐 아이템은 조용히 받아들이고, 그 뒤부터 다시 냄
	iv.update(_c10_item_st(1000.0, [a], 2), 0.016, now + 10000.0)
	iv.update(_c10_item_st(9000.0, [b, c], 2), 0.016, now + 10033.0)
	check(iv.sigs.is_empty(), "시각이 뜀: 조용히")
	iv.update(_c10_item_st(9033.0, [b], 2), 0.016, now + 10066.0)
	check(iv.sigs.size() == 1 and iv.sigs[0].kind == "gone" and iv.sigs[0].type == "ghost", "그 뒤부터 다시")
	# 연습·튜토리얼: 안 냄
	var pv = IV.new()
	var p1 := _c10_item_st(1000.0, [])
	var p2 := _c10_item_st(1033.0, [a])
	var p3 := _c10_item_st(1066.0, [])
	for p in [p1, p2, p3]:
		p["mode"] = "practice"
		p["practice"] = {"dummies": []}
		pv.update(p, 0.016, now)
	check(pv.sigs.is_empty() and not pv.pillars.visible and not pv.rings.visible, "연습·튜토리얼: 신호 없음")
	# 상한
	for i in int(S.max) + 5:
		pv.add_signal("gone", [i, 0, 0.0, "bomb"], now)
	check(pv.sigs.size() == int(S.max) and pv.sigs[0].x == 5, "상한을 넘으면 오래된 것부터 버림")
	pv.free()
	iv.free()
	CellLod.test_cam = keep_cam
	G3.low = keep_low



# ---------- c11-u2 든 아이템 (world/item_look.gd HELD · held_math.gd · held_view.gd) ----------
const HM := preload("res://world/held_math.gd")
const HV := preload("res://world/held_view.gd")


# 스냅샷 players 한 줄 (든 아이템 판단에 쓰는 값만)
func _c11_man(id: int, held, alive := true, master := false, yaw := 0.0) -> Dictionary:
	return {"id": id, "alive": alive, "master": master, "yaw": yaw, "held": held}


# 누구 것을 그리나: 든 것 없음·죽음·블록 마스터·1인칭의 나는 0줄, 3인칭의 나는 1줄
func test_c11_held_rows() -> void:
	var shown := {1: Vector3(5.5, 5.5, 1.0), 2: Vector3(2.5, 3.5, 0.0)}
	var P := "playing"
	check(HM.rows([_c11_man(1, null)], null, false, shown, P).is_empty(), "든 것 없음 → 0줄")
	check(HM.rows([_c11_man(1, "bomb", false)], null, false, shown, P).is_empty(), "죽음 → 0줄")
	check(HM.rows([_c11_man(1, "bomb", true, true)], null, false, shown, P).is_empty(), "블록 마스터 → 0줄")
	check(HM.rows([_c11_man(1, "bomb")], 1, true, shown, P).is_empty(), "1인칭의 나 → 0줄")
	var mine: Array = HM.rows([_c11_man(1, "bomb")], 1, false, shown, P)
	check(mine.size() == 1 and mine[0][0] == "bomb" and (mine[0][1] as Vector3).is_equal_approx(HM.slot(shown[1], 0.0)), "3인칭의 나 → 1줄 (어깨 옆 자리): %s" % str(mine))
	check(HM.rows([_c11_man(2, "brick")], 1, true, shown, P).size() == 1, "1인칭이어도 남은 그림")
	check(HM.rows([_c11_man(1, "control"), _c11_man(2, "zzz")], null, false, shown, P).is_empty(), "표에 없는 종류 → 0줄")
	check(HM.rows([_c11_man(7, "bomb")], null, false, shown, P).is_empty(), "화면 자리가 없는 사람 → 0줄")
	check(IL.HELD.kinds == ["bomb", "knockback", "brick"] and (IL.HELD.kinds as Array).all(func(k): return IL.PARTS.has(k)), "그리는 종류 = 서버가 보내는 든 것 셋 (모델 있음)")
	var both: Array = HM.rows([_c11_man(1, "knockback"), _c11_man(2, "bomb", true, false, 1.0), _c11_man(3, "bomb")], null, false, shown, P)
	check(both.size() == 2 and both[0][0] == "knockback" and both[1][0] == "bomb" and (both[1][1] as Vector3).is_equal_approx(HM.slot(shown[2], 1.0)), "스냅샷 순서, 저마다 자기 자리·보는 쪽")
	# 노드: 종류마다 묶음 하나, 아무도 안 들면 숨김, 그림자 없음, 재질 하나 (바닥 아이템과 같은 갈래)
	var hv = HV.new()
	var vis := func() -> Array:
		var out := []
		for k in IL.HELD.kinds:
			var n: MultiMeshInstance3D = hv.models[k]
			if n.visible:
				out.append("%s%d" % [k, n.multimesh.visible_instance_count])
		return out
	check(vis.call() == [] and hv.models.size() == 3 and hv.get_child_count() == 3, "처음엔 전부 숨김 (묶음 셋)")
	hv.update([_c11_man(1, "bomb"), _c11_man(2, "bomb"), _c11_man(3, "brick")], null, false, {1: Vector3.ZERO, 2: Vector3.ONE, 3: Vector3.ONE}, 1000.0, "playing")
	check(vis.call() == ["bomb2", "brick1"], "든 종류만 보임: %s" % str(vis.call()))
	hv.update([_c11_man(1, "bomb"), _c11_man(2, null), _c11_man(3, "brick", false)], 1, true, {1: Vector3.ZERO, 2: Vector3.ONE, 3: Vector3.ONE}, 2000.0, "playing")
	check(vis.call() == [], "아무도 안 들면 (1인칭의 나만 듦) 전부 숨김: %s" % str(vis.call()))
	const G3 := preload("res://shaders/g3.gd")
	const MF := preload("res://core/mat_first.gd")
	for k in IL.HELD.kinds:
		var n: MultiMeshInstance3D = hv.models[k]
		check(n.multimesh.mesh == IM.mesh(k) and n.material_override == hv.mat, "%s: 바닥 아이템 모델·재질 하나를 나눠 씀" % k)
		check(n.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: 그림자 없음" % k)
		check(n.multimesh.instance_count >= int(C.ROOM_MAX), "%s: 사람 수만큼 자리" % k)
	check(MF.mat_key(hv.mat) == MF.mat_key(G3.toon_material(Color.WHITE)), "재질 = 바닥 아이템과 같은 툰 갈래 (새 셰이더 없음)")
	hv.free()


# c11-fix F3: 판 단계 — 발밑 고리와 같은 단계 (countdown·playing) 에서만. 판 끝 (over) 승자 클로즈업에서 얼굴 옆에 든 폭탄이 뜨지 않음 (서버는 든 것을 판 시작·부활 때만 비움)
func test_c11_fix_held_phase() -> void:
	var shown := {1: Vector3(5.5, 5.5, 1.0), 2: Vector3(2.5, 3.5, 0.0)}
	var men := [_c11_man(1, "bomb"), _c11_man(2, "brick")]
	for ph in ["countdown", "playing"]:
		check(HM.rows(men, 1, false, shown, ph).size() == 2 and HM.wanted(men[0], true, false, ph), "%s: 그림" % ph)
	for ph in ["over", "lobby", "results", ""]:
		check(HM.rows(men, 1, false, shown, ph).is_empty() and not HM.wanted(men[0], false, false, ph), "%s: 0줄" % ph)
	check((FWC.FOOT_RING.phases as Array) == ["countdown", "playing"], "발밑 고리와 같은 단계 표: %s" % [FWC.FOOT_RING.phases])
	# 노드: 판 중에 보이던 것이 판 끝 스냅샷에서 숨음 (그리기 0)
	var hv = HV.new()
	hv.update(men, 1, false, shown, 1000.0, "playing")
	check(hv.models["bomb"].visible and hv.models["brick"].visible, "판 중: 보임")
	hv.update(men, 1, false, shown, 1033.0, "over")
	check(not hv.models["bomb"].visible and not hv.models["brick"].visible and hv.models["bomb"].multimesh.visible_instance_count == 0, "판 끝: 전부 숨김")
	hv.free()


# c11-fix F7: 관전에서 시선을 막아 옅어진 몸 (world/cam_rig.gd thin: id → {k, at}) 의 든 아이템은 안 그림. 1·3인칭에서는 thin 이 비어 예전과 같음.
# cam_rig.spec_thin 이 그 표를 bodies.held_thin 에 넣고 bodies.update 가 held_view.update 로 넘김
func test_c11_fix_held_thin() -> void:
	var shown := {1: Vector3(5.5, 5.5, 1.0), 2: Vector3(2.5, 3.5, 0.0), 3: Vector3(1.5, 1.5, 0.0)}
	var men := [_c11_man(1, "bomb"), _c11_man(2, "brick"), _c11_man(3, "bomb")]
	var all: Array = HM.rows(men, null, false, shown, "playing")
	check(all.size() == 3 and HM.rows(men, null, false, shown, "playing", {}) == all, "thin 이 비면 (1·3인칭) 예전과 같음")
	var thin := {2: {"k": 0.32, "at": 1000.0}}
	var cut: Array = HM.rows(men, null, false, shown, "playing", thin)
	check(cut.size() == 2 and cut[0] == all[0] and cut[1] == all[2], "옅어진 P2 것만 빠짐: %s" % str(cut))
	check(HM.thinned(thin, 2) and not HM.thinned(thin, 1) and not HM.thinned({}, 2), "thinned 판정")
	check(HM.thinned({2: {"k": 0.99, "at": 0.0}}, 2) and not HM.thinned({2: {"k": 1.0, "at": 0.0}}, 2), "되돌아오는 중 (k < 1) 에도 안 그림, 다 돌아오면 (1) 그림")
	# 노드로 넘기는 길
	var hv = HV.new()
	hv.update(men, null, false, shown, 1000.0, "playing", thin)
	check(hv.models["bomb"].multimesh.visible_instance_count == 2 and not hv.models["brick"].visible, "노드: 옅어진 사람의 설치 블록은 숨김")
	hv.update(men, null, false, shown, 1033.0, "playing", {})
	check(hv.models["brick"].visible, "노드: 시선에서 벗어나면 다시")
	hv.free()
	# 넘기는 길 (소스 고정 — 몸·카메라 노드는 트리 밖에서 못 돌림): 카메라가 옅게 한 표를 몸 묶음에 넣고, 몸 묶음이 든 아이템 갱신에 넘김
	var rig_src := FileAccess.get_file_as_string("res://world/cam_rig.gd")
	var bodies_src := FileAccess.get_file_as_string("res://world/bodies.gd")
	check(rig_src.contains("bodies.held_thin = next"), "cam_rig.spec_thin → bodies.held_thin")
	check(bodies_src.contains("held_view.update(st.get(\"players\", []), my_id, hide_me, shown, now_ms, str(st.get(\"phase\", \"\")), held_thin)"), "bodies.update → held_view.update (단계·옅어진 몸)")
	# 표를 만드는 쪽 (순수 계산): 시선을 막는 몸은 k < 1 로 들어오고, 관전이 아니면 (막는 몸 없음·앞 표 없음) 비어 있음
	const SC := preload("res://world/spec_cam.gd")
	var step: Dictionary = SC.thin_step({}, [2], [2], 1000.0, 0.016)
	check(step.has(2) and float(step[2].k) < 1.0 and HM.thinned(step, 2), "thin_step 이 낸 표를 그대로 읽음: %s" % [step])
	check(SC.thin_step({}, [], [], 1000.0, 0.016).is_empty(), "막는 몸이 없으면 빈 표")


# 어깨 옆 자리: 보는 쪽을 90° 돌리면 옆 방향도 90° 돎, 높이·옆 거리 = 그 캐릭터 값 (HELD.by_char, 없으면 HELD.side·h), 오른쪽에 뜸
func test_c11_held_slot() -> void:
	var pos := Vector3(4.0, 7.0, 2.0)
	var a: Vector3 = HM.slot(pos, 0.0) - pos
	check(near(a.z, IL.HELD.h) and near(a.y, -float(IL.HELD.side)) and near(a.x, IL.HELD.fwd), "+x 를 보면 오른쪽 = −y: 옆 %.2f·앞 %.2f·높이 %.2f" % [-a.y, a.x, a.z])
	for ch in ["", "tank", "bard"]:
		var pl: Array = HM.place(ch)
		for yaw in [0.0, 0.7, PI / 2.0, 2.5, -1.2]:
			var d0: Vector3 = HM.slot(pos, yaw, ch) - pos
			var d1: Vector3 = HM.slot(pos, yaw + PI / 2.0, ch) - pos
			check(near(d1.x, -d0.y, 1e-5) and near(d1.y, d0.x, 1e-5), "%s yaw %.1f: 90° 돌리면 옆 방향도 90° (반시계)" % [ch, yaw])
			check(near(d0.z, pl[1]) and near(d1.z, pl[1]), "%s yaw %.1f: 높이 = 그 캐릭터 값" % [ch, yaw])
			check(near(Vector2(d0.x, d0.y).length(), Vector2(pl[0], IL.HELD.fwd).length(), 1e-5), "%s yaw %.1f: 몸에서 거리 그대로" % [ch, yaw])
			var right := Vector2(sin(yaw), -cos(yaw)) # 보는 쪽의 오른쪽
			check(near(Vector2(d0.x, d0.y).dot(right), pl[0], 1e-5), "%s yaw %.1f: 오른쪽으로 그 캐릭터 옆 거리" % [ch, yaw])
	# 고도 좌표 인스턴스 변환: 자리 = gpos(slot), 오른쪽 = 고도 +z (몸이 +x 를 볼 때)
	var x: Transform3D = HM.xform(["bomb", HM.slot(pos, 0.0)], 0.0)
	check(x.origin.is_equal_approx(Co.gpos(HM.slot(pos, 0.0))) and near(x.origin.z - Co.gpos(pos).z, IL.HELD.side), "인스턴스 자리 = 어깨 옆 (고도 좌표)")
	check(near(HM.spin_at(1000.0), fmod(FWC.ITEM_BOB[3] * float(IL.HELD.spin), TAU)) and float(IL.HELD.spin) < 1.0, "도는 빠르기 = 바닥 아이템 × HELD.spin (더 느림)")


# c11-fix F4: 자리는 캐릭터마다 (몸 폭·어깨 높이가 다름). 예전 한 값 (옆 0.55·높이 1.6 = 정수리) 은 좁은 몸에서 머리 옆 허공에 떠 바닥 아이템·남의 것처럼 읽혔음
func test_c11_fix_held_by_char() -> void:
	var t: Dictionary = IL.HELD.by_char
	for ch in C.FIGURE_CHARS:
		check(t.has(ch), "%s: 표에 있음" % ch)
		var pl: Array = HM.place(ch)
		var side := float(pl[0])
		var h := float(pl[1])
		# 어깨 높이: 모델 가운데가 정수리 (C.PLAYER_HEIGHT) 보다 아래, 가슴 (키의 0.7) 보다 위 — 머리 옆 허공도 허리춤도 아님
		check(h <= C.PLAYER_HEIGHT - 0.15 and h >= C.PLAYER_HEIGHT * 0.7, "%s: 높이 %.2f 가 어깨 근처 (%.2f ~ %.2f)" % [ch, h, C.PLAYER_HEIGHT * 0.7, C.PLAYER_HEIGHT - 0.15])
		# 몸 밖: 판정 상자 반 폭 + 모델 반 폭보다 멀리 (몸에 안 묻힘), 한 칸보다는 가까이 (그 사람 것으로 읽힘)
		check(side >= C.PLAYER_HALF + float(IL.HELD.size) * 0.5 - 0.03 and side <= 0.8, "%s: 옆 %.2f (%.2f ~ 0.8)" % [ch, side, C.PLAYER_HALF + float(IL.HELD.size) * 0.5 - 0.03])
		# 이름표 (머리 위) 보다 아래: 모델 꼭대기 < 이름표 가운데 − 0.3칸
		check(h + float(IL.HELD.size) * 0.5 <= C.PLAYER_HEIGHT + C.LABEL_ABOVE_HEAD + FWC.LABEL_LIFT - 0.3, "%s: 모델 꼭대기 %.2f 가 이름표 (%.2f) 아래" % [ch, h + float(IL.HELD.size) * 0.5, C.PLAYER_HEIGHT + C.LABEL_ABOVE_HEAD + FWC.LABEL_LIFT])
	# 넓은 몸 (탱크·광전사·대포수) 은 좁은 몸 (닌자·바드) 보다 멀리 — 어깨 갑옷에 안 묻히고, 좁은 몸에선 허공에 안 뜸
	for wide in ["tank", "berserker", "cannon"]:
		for slim in ["ninja", "bard"]:
			check(float(HM.place(wide)[0]) >= float(HM.place(slim)[0]) + 0.1, "%s (%.2f) 가 %s (%.2f) 보다 0.1칸 넘게 멀리" % [wide, HM.place(wide)[0], slim, HM.place(slim)[0]])
	# 표에 없는 캐릭터 (캐릭터 끔): 기본 값 — 같은 범위
	var d: Array = HM.place("")
	check(d == [IL.HELD.side, IL.HELD.h] and HM.place("zzz") == d and float(d[1]) <= C.PLAYER_HEIGHT - 0.15, "표에 없으면 HELD.side·h: %s" % [d])
	check(float(d[1]) + float(IL.HELD.size) * 0.5 <= C.PLAYER_HEIGHT + C.LABEL_ABOVE_HEAD + FWC.LABEL_LIFT - 0.3, "기본 값도 이름표 아래")
	# rows 가 캐릭터 값을 씀
	var shown := {1: Vector3(5.5, 5.5, 1.0)}
	var man := _c11_man(1, "bomb")
	man["char"] = "tank"
	var row: Array = HM.rows([man], null, false, shown, "playing")
	check(row.size() == 1 and (row[0][1] as Vector3).is_equal_approx(HM.slot(shown[1], 0.0, "tank")) and not (row[0][1] as Vector3).is_equal_approx(HM.slot(shown[1], 0.0, "bard")), "rows: 그 사람 캐릭터의 자리")


# 크기: 긴 변 = HELD.size (바닥 아이템보다 작음)
func test_c11_held_size() -> void:
	check(float(IL.HELD.size) < float(IL.SIZE), "바닥 아이템 (%.2f) 보다 작음" % IL.SIZE)
	for k in IL.HELD.kinds:
		for ang in [0.0, 1.3]:
			var x: Transform3D = HM.xform([k, Vector3.ZERO], ang)
			var long: float = (IM.mesh(k) as ArrayMesh).get_aabb().get_longest_axis_size() * x.basis.get_scale().x
			check(absf(long - float(IL.HELD.size)) <= 0.01, "%s: 긴 변 %.3f = HELD.size ±0.01" % [k, long])
			check(x.basis.get_scale().is_equal_approx(Vector3.ONE * HM.shrink()), "%s: 고르게 줄임" % k)


# 화면 크기: 720p·시야 75° 에서 3칸 앞 ≥ 40px, 8칸 앞 ≥ 14px
func test_c11_held_px() -> void:
	var s := float(IL.HELD.size)
	check(IVM.px(s, 3.0, 75.0, 720.0) >= 40.0, "3칸 앞 %.1fpx ≥ 40" % IVM.px(s, 3.0, 75.0, 720.0))
	check(IVM.px(s, 8.0, 75.0, 720.0) >= 14.0, "8칸 앞 %.1fpx ≥ 14" % IVM.px(s, 8.0, 75.0, 720.0))
