# 타이틀 로고 계산이 JS (shared/title.js) 와 같은지 (tools/fixtures-fx.mjs → title.json): 칸·조각·떨어지는 시각·높이·빛·빠져나가기·떠돎·착지·테마
extends RefCounted

const TC := preload("res://title/title_calc.gd")
const C := preload("res://core/config.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func near(a, b, eps := 1e-9) -> bool:
	if a == null or b == null:
		return a == b
	return absf(float(a) - float(b)) <= eps * maxf(1.0, absf(float(b)))


func js():
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/title.json"))


static func _cells(list: Array) -> Array:
	return list.map(func(c): return [int(c.x), int(c.y)])


func test_cells_pieces_schedule_match_js() -> void:
	var d = js()
	var r := TC.cells(C.TITLE_TEXT, int(C.TITLE_GAP), int(C.TITLE_BOLD))
	check(r.width == int(d.width) and r.height == int(d.height), "크기 %d×%d vs JS %s×%s" % [r.width, r.height, d.width, d.height])
	check(_cells(r.cells) == _cells(d.cells), "칸 %d vs JS %d" % [r.cells.size(), d.cells.size()])
	var ps := TC.pieces(r.cells)
	check(ps.size() == d.pieces.size(), "조각 수 %d vs JS %d" % [ps.size(), d.pieces.size()])
	var same := true
	for i in mini(ps.size(), d.pieces.size()):
		same = same and ps[i].shape == d.pieces[i].shape and _cells(ps[i].cells) == _cells(d.pieces[i].cells) and ps[i].min_y == int(d.pieces[i].minY)
	check(same, "조각 모양·칸이 JS 와 다름")
	var iv := TC.interval(ps.size())
	check(near(iv, d.iv), "간격 %s vs JS %s" % [iv, d.iv])
	var st := TC.drop_schedule(ps, iv)
	var ok := true
	for i in st.size():
		ok = ok and near(st[i], d.start[i])
	check(ok, "출발 시각이 JS 와 다름")
	check(near(TC.done_at(st), d.done), "다 쌓임 %s vs JS %s" % [TC.done_at(st), d.done])
	var c2 := TC.cells("AB-1", 1, 1)
	check(_cells(c2.cells) == _cells(d.cells2.cells) and c2.width == int(d.cells2.width), "AB-1 칸")


func test_lift_light_exit_drift_match_js() -> void:
	var d = js()
	for r in d.lifts:
		check(near(TC.lift(r[0], r[1]), r[2]), "높이 %s: %s vs JS %s" % [r, TC.lift(r[0], r[1]), r[2]])
	for r in d.lights:
		var g := TC.light(r[0], d.done)
		check(near(g.lit, r[1].lit) and near(g.burst, r[1].burst) and near(g.glow, r[1].glow), "빛 %s: %s vs JS %s" % [r[0], g, r[1]])
	for r in d.exits:
		var g := TC.exit(r[0], r[1])
		check(near(g.push, r[2].push) and near(g.white, r[2].white) and g.show == r[2].show and g.done == r[2].done, "나가기 %s: %s vs JS %s" % [[r[0], r[1]], g, r[2]])
	for r in d.drift:
		var g := TC.menu_drift(r[0])
		check(near(g[0], r[1][0]) and near(g[1], r[1][1]) and near(g[2], r[1][2]), "떠돎 %s: %s vs JS %s" % [r[0], g, r[1]])
	for r in d.landed:
		var g := TC.landed_between(d.start, r[0], r[1])
		check(g == r[2].map(func(x): return int(x)), "착지 %s: %s vs JS %s" % [[r[0], r[1]], g, r[2]])


func test_cam_theme_match_js() -> void:
	var d = js()
	for r in d.camDist:
		check(near(TC.cam_dist(r[0][0], r[0][1], r[0][2]), r[1]), "카메라 거리 %s" % [r])
	for r in d.picks:
		check(TC.pick_theme(r[0]) == r[1], "테마 고르기 %s: %s vs JS %s" % [r[0], TC.pick_theme(r[0]), r[1]])
	for r in d.maps:
		check(TC.map_for(r[0]) == r[1], "테마 맵 %s: %s vs JS %s" % [r[0], TC.map_for(r[0]), r[1]])


# 타이틀 장면이 테마마다 만들어지고 한 바퀴 돎: 다 쌓이면 빛 터짐 한 번, 누르면 빠져나가 메뉴 카메라로 (소리 신호 순서)
func test_scene_runs_all_themes() -> void:
	var Scene = load("res://title/title_scene.gd")
	for th in TC.theme_ids():
		var sc = Scene.new()
		sc.setup(th, {"low": true})
		var got := []
		sc.landed.connect(func(n): if not got.has("land"): got.append("land"))
		sc.burst.connect(func(): got.append("burst"))
		sc.exit_started.connect(func(): got.append("exit"))
		var steps := 0
		while not sc.is_done() and steps < 600:
			sc.step(1.0 / 60.0)
			steps += 1
		sc.step(1.0 / 60.0)
		check(sc.is_done() and steps < 600, "%s 로고가 다 쌓임 (%d 걸음)" % [th, steps])
		sc.press()
		for i in 120:
			sc.step(1.0 / 60.0)
		check(sc.in_menu(), "%s 누르면 메뉴 카메라로" % th)
		check(got == ["land", "burst", "exit"], "%s 소리 신호 %s" % [th, got])
		sc.free()
	var m = Scene.new()
	m.setup("crystal", {"menu": true, "low": true})
	m.step(0.016)
	check(m.in_menu() and m.is_done(), "menu 모드는 처음부터 메뉴 카메라")
	m.free()


# 넓은 빛 안개 (W8, haze.gdshader): 테마 7개 모두 값 [세기, 밉 단계, 문턱], 세기 0~3, 셰이더가 화면 밉맵을 읽음
func test_haze_values() -> void:
	for th in TC.theme_ids():
		var hz: Array = TC.haze(th)
		check(hz.size() == 3 and float(hz[0]) > 0.0 and float(hz[0]) <= 3.0 and float(hz[1]) >= 3.0, "%s 안개 %s" % [th, str(hz)])
		check(TC.HAZE_THEME.has(th), "%s 안개는 JS 스샷에 맞춘 값" % th)
	check(near(TC.haze("mushroom")[0], 1.9) and near(TC.haze("crystal")[0], 0.2), "버섯 1.9 · 자수정 0.2")
	var code: String = load("res://title/haze.gdshader").code
	check(code.contains("hint_screen_texture") and code.contains("filter_linear_mipmap") and code.contains("blend_add"), "안개 셰이더: 화면 밉맵 + 더하기")


# 버섯 갓 = 열린 반구 (W8, three SphereGeometry 위 반쪽): 모든 점이 y ≥ 0, 바닥 뚜껑 없음 (y = 0 인 점은 테두리 고리뿐), 삼각형 수 = seg × (2·rings − 1)
func test_open_hemisphere() -> void:
	var F = load("res://title/title_fx.gd")
	var m: ArrayMesh = F.hemi_open(1.0, 20, 10)
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var low := 0
	for p in v:
		check(p.y >= -1e-5, "반구 아래로 나간 점 %s" % str(p))
		if absf(p.y) < 1e-5:
			low += 1
	check(low == 21, "바닥 높이 점은 테두리 고리 21개뿐 (%d)" % low)
	check(ids.size() / 3 == 20 * (2 * 10 - 1), "삼각형 %d" % (ids.size() / 3))
	# 앞면 (고도 시계 방향) 이 바깥을 봄: 첫 옆 삼각형의 면 법선 · 중심 방향 > 0
	var a: Vector3 = v[ids[60]]
	var b: Vector3 = v[ids[61]]
	var c: Vector3 = v[ids[62]]
	var n := (c - a).cross(b - a) # 고도: 시계 방향 = 앞면 → (c−a)×(b−a) 가 바깥
	check(n.dot((a + b + c) / 3.0) > 0.0, "반구 앞면이 바깥")


# 대기실 둘레 무대 (title_stage.gd, B4 lobby_dark 가 씀): 테마마다 만들어지고, 흩뿌릴 땐 섬 자리 (clear 반지름) 안 소품은 빼고 가운데 축으로 돌림
func test_ring_stage() -> void:
	var S = load("res://title/title_stage.gd")
	var F = load("res://title/title_fx.gd")
	for th in TC.theme_ids():
		var st = S.new(th, {"low": true, "logoW": 0, "logoH": 0, "camDist": 30.0, "ring": true, "clear": 30.0, "floorZ": -8.0})
		check(st is Node3D and st.back_light != null and st.lights.size() >= 2 and st.ring and is_equal_approx(st.floor_z, -8.0), "%s 무대" % th)
		st.update(1.0, 1.0, 360.0)
		if th == "crystal":
			st.ring_rnd = F.Rng.new(99)
			var list := [{"p": Vector3(5, 5, 0), "s": Vector3.ONE}, {"p": Vector3(40, 0, 1), "s": Vector3.ONE, "r": Basis()}, {"p": Vector3(0, -31, 2), "s": Vector3.ONE}]
			var mi: MultiMeshInstance3D = st._inst(BoxMesh.new(), StandardMaterial3D.new(), list)
			check(mi.multimesh.instance_count == 2, "섬 자리 안 소품 뺌 %d" % mi.multimesh.instance_count)
			check(is_equal_approx(Vector2(list[1].p.x, list[1].p.y).length(), 40.0) and not list[1].p.is_equal_approx(Vector3(40, 0, 1)), "가운데 축으로 돌림 (반지름 그대로) %s" % list[1].p)
			st.ring_rnd = null
			mi.free()
		st.free()


# ===== C8 (겉모습 3 — 타이틀 로고 색): 테마별 글자 빛·흰 심 표 (title/title_tune.gd) · 시작 안내 'Enter' 색 =====
const Tune := preload("res://title/title_tune.gd")
const Co := preload("res://core/coords.gd")


# 7테마 모두 [빛 배율, 바탕 빛 배율, 흰 심] 이 있고 범위 안. 화산은 빛 배율 0.5 그대로 + 흰 심, 흰 심은 로고 빛을 따라 켜짐. 장면이 셰이더에 넣음
func test_c8_title_tune_all_themes() -> void:
	for th in TC.theme_ids():
		check(Tune.LETTER.has(th), "%s: 표에 있음" % th)
		var v: Array = Tune.letter(th)
		check(v.size() == 3, "%s: 값 셋 %s" % [th, v])
		check(v[0] > 0.0 and v[0] <= 2.0 and v[1] > 0.0 and v[1] <= 2.0, "%s: 빛 배율·바탕 빛 배율 (0, 2] %s" % [th, v])
		check(v[2] >= 0.0 and v[2] <= 1.0, "%s: 흰 심 0~1 %s" % [th, v])
		check(Tune.core(th, 0.0) == 0.0 and is_equal_approx(Tune.core(th, C.TITLE_GLOW[1]), v[2]) and is_equal_approx(Tune.core(th, C.TITLE_GLOW[1] * 3.0), v[2]), "%s: 흰 심은 로고 빛이 다 켜지면 표 값 (넘어도 그대로)" % th)
		check(Tune.core(th, C.TITLE_GLOW[0]) <= v[2] * 0.5, "%s: 쌓이는 동안은 흰 심이 반 아래" % th)
	check(Tune.LETTER.size() == TC.theme_ids().size(), "표에 없는 테마 없음")
	check(Tune.letter("volcano")[0] == 0.5 and Tune.letter("volcano")[1] == 0.35 and Tune.letter("volcano")[2] >= 0.5, "화산: 빛 배율 0.5·바탕 0.35 그대로 + 흰 심 %s" % [Tune.letter("volcano")])
	check(Tune.letter("nope") == Tune.LETTER_DEFAULT and Tune.LETTER_DEFAULT == [1.0, 1.0, 0.0], "표에 없는 테마는 기본 (흰 심 없음)")
	check(Tune.CORE_EDGE.x > 0.0 and Tune.CORE_EDGE.x < Tune.CORE_EDGE.y and Tune.CORE_EDGE.y <= 1.0 and Tune.CORE_LIT > 0.0 and Tune.CORE_LIT <= 1.5, "흰 심 자리·빛 범위")
	var names := []
	for u in (load("res://title/letter.gdshader") as Shader).get_shader_uniform_list():
		names.append(u.name)
	for u in ["base_glow", "glow", "glow_col", "sweep_x", "core_white", "core_edge", "core_lit"]:
		check(names.has(u), "글자 셰이더 uniform %s" % u)
	var Scene = load("res://title/title_scene.gd")
	check(not FileAccess.get_file_as_string("res://title/title_scene.gd").contains("LETTER_THEME"), "장면의 예전 표 (LETTER_THEME) 는 title_tune.gd 로 옮김")
	for th in ["volcano", "meadow"]:
		var sc = Scene.new()
		sc.setup(th, {"low": true, "instant": true})
		sc.step(1.0 / 60.0)
		var want: float = Tune.letter(th)[2]
		var got: float = sc.letter_mat.get_shader_parameter("core_white")
		check(sc.is_done() and is_equal_approx(got, want), "%s: 다 쌓인 로고의 흰 심 %.2f = 표 %.2f" % [th, got, want])
		check((sc.letter_mat.get_shader_parameter("core_edge") as Vector2).is_equal_approx(Tune.CORE_EDGE) and is_equal_approx(sc.letter_mat.get_shader_parameter("core_lit"), Tune.CORE_LIT), "%s: 흰 심 자리·빛" % th)
		check(got >= 0.0 and got <= 1.0, "%s: uniform 0~1" % th)
		sc.free()


# 'Enter' 글자 색: 7테마 모두 밝기 하한 위, 빛깔은 테마 빛 색 (edge) 과 15° 안. 이미 밝은 색은 그대로
func test_c8_hint_color_floor() -> void:
	check(Tune.HINT_LUMA_MIN >= 0.6 and Tune.HINT_LUMA_MIN < 1.0, "하한 %.2f" % Tune.HINT_LUMA_MIN)
	var raised := 0
	for th in TC.theme_ids():
		var edge: Color = Co.color(C.TITLE_THEMES[th].edge)
		var c: Color = Tune.hint_color(edge)
		check(Tune.luma(c) >= Tune.HINT_LUMA_MIN - 1e-4 and Tune.luma(c) >= 0.6, "%s: 밝기 %.3f ≥ %.2f" % [th, Tune.luma(c), Tune.HINT_LUMA_MIN])
		var d := absf(c.h - edge.h) * 360.0
		check(minf(d, 360.0 - d) <= 15.0, "%s: 빛깔 차 %.1f° ≤ 15°" % [th, minf(d, 360.0 - d)])
		check(c.r >= edge.r - 1e-5 and c.g >= edge.g - 1e-5 and c.b >= edge.b - 1e-5 and c.a == edge.a, "%s: 어두워지는 성분 없음" % th)
		check(c.s > 0.05, "%s: 흰색이 되지는 않음 (채도 %.2f)" % [th, c.s])
		if Tune.luma(edge) >= Tune.HINT_LUMA_MIN:
			check(c == edge, "%s: 이미 밝은 색은 그대로" % th)
		else:
			raised += 1
			check(is_equal_approx(Tune.luma(c), Tune.HINT_LUMA_MIN), "%s: 딱 하한까지만 올림" % th)
	check(raised >= 2, "어두운 테마 빛 색 (화산·수정 등) 이 올려짐 %d" % raised)
	check(Tune.HINT_BACK.size() == 2 and Tune.HINT_BACK[0] > 14 and Tune.HINT_BACK[1] > 0.0 and Tune.HINT_BACK[1] <= 0.8, "받침 겹은 빛 겹 (14) 보다 넓고 반투명 %s" % [Tune.HINT_BACK])
	check(Tune.hint_color(Color.BLACK, 0.6).is_equal_approx(Color(0.6, 0.6, 0.6)) and Tune.hint_color(Color.WHITE) == Color.WHITE, "검정·흰색")
