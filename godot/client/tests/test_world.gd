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
	check(thrown.mat.get_shader_parameter("albedo_tex") == preload("res://world/chunk_tex.gd").sand(), "설치 블록 덩어리 = 모래 그림")
	check(build.mat.get_shader_parameter("albedo_tex") == preload("res://world/chunk_tex.gd").wood(), "건축가 덩어리 = 판자 그림")
	check(piece.mesh is ArrayMesh and piece.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] is PackedColorArray, "테트리미노 덩어리 = 테마 칸 모양 + 꼭짓점 색")
	check(piece.mat.get_shader_parameter("face_tex") != null, "테트리미노 덩어리 재질 = 테마 칸 재질 (면 그림)")
	var sky: Dictionary = hf.chunk_look({"v": 3, "sky": true}, col)
	check(absf(sky.mat.get_shader_parameter("albedo").a - float(C.SKY_PIECE_OPACITY)) < 0.001, "하늘 덩어리는 반투명")
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
