# G3 지형 블록 계산이 JS (shared/block-style.js) 와 같은지 — 정답 tests/fixtures/block_style.json (tools/fixtures_g3.mjs)
extends RefCounted

const C := preload("res://core/config.gd")
const BS := preload("res://shaders/block_style.gd")
const Co := preload("res://core/coords.gd")
const EL := preload("res://world/edge_look.gd")
const G3 := preload("res://shaders/g3.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func near(a: float, b: float) -> bool:
	return absf(a - b) <= 1e-6 * maxf(1.0, absf(b))


func fx():
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/block_style.json"))


func grid_of(j) -> PackedByteArray:
	var g := PackedByteArray()
	for v in j.grid:
		g.append(int(v))
	return g


func skip_of(j) -> Dictionary:
	var s := {}
	for i in j.skip:
		s[int(i)] = true
	return s


func test_cell_rand() -> void:
	for r in fx().rands:
		var got := BS.cell_rand(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		check(near(got, float(r[4])), "cell_rand %s → %s" % [r, got])


func test_cell_looks() -> void:
	var j = fx()
	var l := BS.cell_looks(grid_of(j), int(j.W), int(j.D), int(j.H), skip_of(j))
	check(l.size() == j.looks.open.size(), "칸 수 %d" % l.size())
	for i in mini(l.size(), j.looks.open.size()):
		check(int(l[i].r) == int(j.looks.open[i]) and int(l[i].g) == int(j.looks.ao[i]) and near(l[i].b, j.looks.lift[i]), "칸 %d %s" % [i, l[i]])


func same(a, b) -> bool:
	if a is float or a is int:
		return (b is float or b is int) and near(float(a), float(b))
	if a is Array:
		if not b is Array or a.size() != b.size():
			return false
		for i in a.size():
			if not same(a[i], b[i]):
				return false
		return true
	if a is Dictionary:
		for k in a:
			if not b.has(k) or not same(a[k], b[k]):
				return false
		return true
	return a == b


func test_style_and_sprouts() -> void:
	var j = fx()
	var g := grid_of(j)
	for id in j.themes:
		var t = j.themes[id]
		var s = BS.style(C.WORLD_THEMES[id].terrain)
		check(s != null and same(t.style, s), "%s 스타일 %s" % [id, s])
		if s == null:
			continue
		var all := BS.sprout_spots(g, int(j.W), int(j.D), int(j.H), skip_of(j), s.sprout, 1000000000)
		check(same(t.sprouts, all), "%s 조각 %d / %d" % [id, all.size(), t.sprouts.size()])
		check(same(t.few, BS.sprout_spots(g, int(j.W), int(j.D), int(j.H), skip_of(j), s.sprout, 9)), "%s 조각 솎음" % id)


# ---- C7 (겉모습 2 — 바닥 읽힘): 낭떠러지 테 (world/edge_look.gd · floor.gdshader · terrain.gdshader)

# 띠가 어느 바닥에서든 읽힘: 띠 색과 바닥 (floor.a) 의 sRGB 밝기 차 ≥ 0.18, 밝은 바닥이라 그게 안 되면 띠와 안쪽 어두운 선의 차 ≥ 0.25
func test_c7_edge_color_contrast() -> void:
	check(C.WORLD_THEMES.size() == 7, "테마 7개")
	for id in C.WORLD_THEMES:
		var a: Color = Co.color(C.WORLD_THEMES[id].floor.a)
		var e: Color = EL.edge_color(id)
		var inner: Color = EL.inner_color(id)
		check(e.is_equal_approx(a.lerp(Color.WHITE, EL.EDGE.lift)), "%s 띠 색 = floor.a 를 흰 쪽으로" % id)
		var d1 := e.get_luminance() - a.get_luminance()
		var d2 := e.get_luminance() - inner.get_luminance()
		check(d1 >= 0.18 or d2 >= 0.25, "%s 띠 %.2f vs 바닥 %.2f (차 %.2f) · 안쪽 선 %.2f (차 %.2f)" % [id, e.get_luminance(), a.get_luminance(), d1, inner.get_luminance(), d2])
		check(inner.get_luminance() < a.get_luminance() and e.get_luminance() > a.get_luminance(), "%s: 안쪽 선 < 바닥 < 띠" % id)
		# 안쪽 선은 sRGB 로 바닥 × inner_shade 쯤 (셰이더는 선형에서 inner_shade^2.2 를 곱함)
		check(absf(inner.get_luminance() - a.get_luminance() * EL.EDGE.inner_shade) < 0.03, "%s 안쪽 선 ≈ 바닥 × %.2f (%.3f vs %.3f)" % [id, EL.EDGE.inner_shade, inner.get_luminance(), a.get_luminance() * EL.EDGE.inner_shade])
	check(is_equal_approx(EL.shade_linear(), pow(EL.EDGE.inner_shade, 2.2)) and EL.widths() == Vector3(EL.EDGE.w, EL.EDGE.inner_w, EL.shade_linear()), "셰이더에 넣는 폭 묶음")


# 띠가 위험 액체로 안 읽힘: 채도 ≤ 0.35 이고 그 테마 위험 액체 얕은 색보다 낮음 (플레이어 팔레트와는 안 견줌 — 팔레트에 무채색이 있음)
func test_c7_edge_not_hazard() -> void:
	for id in C.WORLD_THEMES:
		var e: Color = EL.edge_color(id)
		var hz: Color = Co.color(C.WORLD_THEMES[id].hazard.shallow)
		check(e.s <= 0.35 and e.s < hz.s, "%s 띠 채도 %.2f (위험 %.2f)" % [id, e.s, hz.s])


# 새 uniform 기본값은 0 → 값을 안 넣은 재질 (다른 길로 만든 것) 은 예전 화소 그대로
func test_c7_edge_uniforms_default_off() -> void:
	var fs := FileAccess.get_file_as_string("res://shaders/floor.gdshader")
	for u in ["uniform vec2 f_field = vec2(0.0);", "uniform vec3 f_edge = vec3(0.0);", "uniform vec3 f_edge_w = vec3(0.0);"]:
		check(fs.contains(u), "바닥: " + u)
	check(fs.contains("if (f_field.x > 0.0)"), "바닥: 판 크기 0 이면 끔")
	var ts := FileAccess.get_file_as_string("res://shaders/terrain.gdshader")
	for u in ["uniform vec2 tf_field = vec2(0.0);", "uniform vec3 tf_field_edge = vec3(0.0);", "uniform vec3 tf_field_w = vec3(0.0);"]:
		check(ts.contains(u), "지형: " + u)
	check(ts.contains("if (up > 0.5 && tf_field.x > 0.0)"), "지형: 윗면만, 판 크기 0 이면 끔")
	var fm: ShaderMaterial = G3.floor_material("meadow")
	var tm: ShaderMaterial = G3.terrain_material("meadow")
	check(fm.get_shader_parameter("f_field") == null and tm.get_shader_parameter("tf_field") == null, "G3 가 만든 재질은 기본 (끔)")
	EL.apply(fm, tm, "meadow", 12.0, 14.0)
	var c: Color = EL.edge_color("meadow").srgb_to_linear()
	check(fm.get_shader_parameter("f_field") == Vector2(12, 14) and tm.get_shader_parameter("tf_field") == Vector2(12, 14), "판 크기")
	check((fm.get_shader_parameter("f_edge") as Vector3).is_equal_approx(Vector3(c.r, c.g, c.b)) and tm.get_shader_parameter("tf_field_edge") == fm.get_shader_parameter("f_edge"), "띠 색 (선형), 바닥·지형 같은 색")
	check(fm.get_shader_parameter("f_edge_w") == EL.widths() and tm.get_shader_parameter("tf_field_w") == EL.widths(), "폭 묶음")
	var other := ShaderMaterial.new()
	other.shader = tm.shader
	EL.apply(other, StandardMaterial3D.new(), "meadow", 12.0, 14.0) # 바닥 자리에 다른 셰이더·지형 자리에 표준 재질 → 안 건드림
	check(other.get_shader_parameter("f_field") == null and other.get_shader_parameter("tf_field") == null, "다른 재질은 그대로")
	EL.apply(null, null, null, 0.0, 0.0)


# 거리 → 띠: 셰이더와 같은 문턱 (d < w 띠 · w ≤ d < w + inner_w 어두운 선). 셰이더엔 숫자를 안 박고 폭 묶음 uniform 만 씀
func test_c7_edge_band_math() -> void:
	var w: float = EL.EDGE.w
	var iw: float = EL.EDGE.inner_w
	check(EL.band(0.0) == Vector2(1, 0) and EL.band(w - 0.001) == Vector2(1, 0), "변에서 w 안쪽까지 띠")
	check(EL.band(w) == Vector2(0, 1) and EL.band(w + iw - 0.001) == Vector2(0, 1), "그 안쪽 inner_w 는 어두운 선")
	check(EL.band(w + iw) == Vector2.ZERO and EL.band(3.0) == Vector2.ZERO, "더 안쪽은 바닥 그대로")
	check(is_equal_approx(EL.edge_dist(0.05, 5.0, 10.0, 12.0), 0.05) and is_equal_approx(EL.edge_dist(9.9, 5.0, 10.0, 12.0), 0.1) and is_equal_approx(EL.edge_dist(5.0, 11.8, 10.0, 12.0), 0.2) and is_equal_approx(EL.edge_dist(5.0, 0.3, 10.0, 12.0), 0.3), "네 변 가운데 가장 가까운 거리")
	check(EL.band(EL.edge_dist(5.0, 6.0, 10.0, 12.0)) == Vector2.ZERO and EL.band(EL.edge_dist(0.01, 0.01, 10.0, 12.0)) == Vector2(1, 0), "가운데는 없음 · 모서리는 띠")
	for row in [["res://shaders/floor.gdshader", "f_field", "f_edge_w", "g"], ["res://shaders/terrain.gdshader", "tf_field", "tf_field_w", "v_flat"]]:
		var src := FileAccess.get_file_as_string(row[0])
		var q: String = row[3]
		check(src.contains("min(min(%s.x, %s.x - %s.x), min(%s.y, %s.y - %s.y))" % [q, row[1], q, q, row[1], q]), "%s: 변까지 거리 = edge_dist 와 같은 식" % row[0])
		check(src.contains("smoothstep(%s.x - aa, %s.x + aa, de)" % [row[2], row[2]]), "%s: 띠 문턱 = 폭 (w)" % row[0])
		check(src.contains("smoothstep(%s.x + %s.y - aa, %s.x + %s.y + aa, de)" % [row[2], row[2], row[2], row[2]]), "%s: 어두운 선 문턱 = w + inner_w" % row[0])
		check(src.contains("%s.z" % row[2]), "%s: 어두운 선 배율도 폭 묶음에서" % row[0])



# ---------- c11-u2 착지한 설치 블록 = 나무 상자 (world/crate_look.gd · grid_view.gd) ----------
const CL := preload("res://world/crate_look.gd")
const IL := preload("res://world/item_look.gd")
const IM := preload("res://world/item_models.gd")
const Cells := preload("res://world/cells.gd")
const GV := preload("res://world/grid_view.gd")


func test_c11_crate_mesh() -> void:
	var m = CL.mesh()
	check(m is ArrayMesh and m.get_surface_count() == 1, "상자: ArrayMesh 표면 하나 (그리기 한 번)")
	var tris: int = IM.tri_count(m)
	check(tris > 0 and tris <= 160 and tris <= int(CL.MAX_TRIS), "삼각형 %d ≤ 160" % tris)
	var box: AABB = m.get_aabb()
	check(absf(box.get_longest_axis_size() - 1.0) <= 0.01, "긴 변 %.3f = 1.0 ±0.01" % box.get_longest_axis_size())
	check(box.size.x <= 1.0 + 1e-4 and box.size.y <= 1.0 + 1e-4 and box.size.z <= 1.0 + 1e-4 and box.get_center().length() < 1e-4, "칸 하나 안 (가운데 0)")
	check(CL.mesh() == m, "한 번 만들어 나눠 씀")
	var a: Array = m.surface_get_arrays(0)
	check(a[Mesh.ARRAY_COLOR] is PackedColorArray and (a[Mesh.ARRAY_COLOR] as PackedColorArray).size() == (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "정점 색 배열")


func test_c11_crate_color() -> void:
	var wood: Color = Co.color(int(IL.MAIN.brick))
	check(Co.color(CL.WOOD).is_equal_approx(wood), "몸통 = 설치 블록 아이템 주색")
	# 가장 넓게 칠해진 색 = 몸통 색
	var a: Array = CL.mesh().surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var area := {}
	for i in range(0, ix.size(), 3):
		var k := cs[ix[i]].to_html(false)
		area[k] = float(area.get(k, 0.0)) + (vs[ix[i + 1]] - vs[ix[i]]).cross(vs[ix[i + 2]] - vs[ix[i]]).length() * 0.5
	var top := ""
	for k in area:
		if top == "" or float(area[k]) > float(area[top]):
			top = k
	check(top == wood.to_html(false) and area.size() == 3, "가장 넓은 색 = 몸통 나무 (%s), 색 셋 (나무·띠·쇠): %s" % [top, str(area.keys())])
	check(area.has(Co.color(CL.BAND).to_html(false)) and area.has(Co.color(CL.STEEL).to_html(false)), "어두운 띠·쇠 기둥이 칠해져 있음")
	for pc in C.PLAYER_PALETTE:
		var p: Color = Co.color(int(pc))
		var dist := Vector3(wood.r - p.r, wood.g - p.g, wood.b - p.b).length()
		check(dist >= 0.12, "몸통 색이 플레이어 색 %06x 과 RGB 거리 %.2f ≥ 0.12" % [int(pc), dist])
	# 재질: 툰 (정점 색), 외곽선 없음, 스스로 안 빛남, 위험 액체에 잠기면 물듦
	var mat: ShaderMaterial = CL.material()
	check(mat.shader == G3.toon_material(Color.WHITE, {"outline": false}).shader and mat.next_pass == null, "툰 재질·외곽선 없음")
	check(mat.get_shader_parameter("use_vertex_color") == true and mat.get_shader_parameter("hz_tint") == true and float(mat.get_shader_parameter("color_glow")) == 0.0, "정점 색·물듦 켬·빛남 0")


# 격자 → 묶음 나누기: 착지한 설치 블록 (THROWN) 은 상자 묶음, 모양 칸은 모양 묶음, 단색 묶음엔 THROWN 없음. 모양 칸 모습이 꺼져 있으면 예전 그대로 (다 단색)
func test_c11_thrown_split() -> void:
	var w := 4
	var d := 4
	var grid := PackedByteArray()
	grid.resize(w * d * 3)
	for i in [0, 1, 2, 3]: # 지형 4칸 (맨 아래 줄)
		grid[i] = Cells.TERRAIN
	var thrown := [5, 21] # 착지한 설치 블록 2칸
	for i in thrown:
		grid[i] = Cells.THROWN
	for i in [6, 7, 22]: # 쌓인 모양 칸 3칸
		grid[i] = Cells.SHAPE_BASE + 2
	var gv = GV.new()
	gv._ready()
	gv.set_piece_look(BoxMesh.new(), StandardMaterial3D.new(), C.SHAPE_COLORS)
	gv.rebuild(grid, w, d, 3)
	check(Array(gv.crate_cells) == thrown and gv.crate_mmi.visible and gv.crate_mmi.multimesh.instance_count == 2, "상자 2칸 (THROWN 칸 번호): %s" % str(gv.crate_cells))
	check(gv._pxf.size() == 3 and gv.piece_mmi.multimesh.instance_count == 3, "모양 칸 3칸: %d" % gv._pxf.size())
	check(gv.count == 4 and gv.mmi.multimesh.instance_count == 4, "단색 묶음엔 지형 4칸만 (THROWN 없음): %d" % gv.count)
	check(gv.crate_mmi.multimesh.mesh == CL.mesh() and gv.crate_mmi.material_override is ShaderMaterial and gv.crate_mmi.multimesh.use_colors, "상자 묶음 = 상자 메시·툰 재질·칸 색 (체커 명암)")
	gv.skip = {21: true} # 건너뛸 칸 (다른 쪽이 그림) 은 상자로도 안 그림
	gv.rebuild(grid, w, d, 3)
	check(Array(gv.crate_cells) == [5], "건너뛸 칸은 뺌: %s" % str(gv.crate_cells))
	gv.skip = {}
	grid[5] = 0
	grid[21] = 0
	gv.rebuild(grid, w, d, 3)
	check(gv.crate_cells.is_empty() and not gv.crate_mmi.visible and gv.crate_mmi.multimesh.instance_count == 0, "THROWN 이 없으면 상자 묶음 숨김")
	# 모양 칸 모습 끔 (테마 재질 없음): 예전 그대로 전부 단색 칸
	grid[5] = Cells.THROWN
	grid[21] = Cells.THROWN
	gv.set_piece_look(null, null, C.SHAPE_COLORS)
	gv.rebuild(grid, w, d, 3)
	check(gv.crate_cells.is_empty() and not gv.crate_mmi.visible and gv.count == 9, "모습 끔: 상자 0 · 단색 9칸 (예전 그대로): %d" % gv.count)
	gv.free()
