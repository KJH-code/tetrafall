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
