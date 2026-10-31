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
