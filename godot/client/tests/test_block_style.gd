# G3 지형 블록 계산이 JS (shared/block-style.js) 와 같은지 — 정답 tests/fixtures/block_style.json (tools/fixtures_g3.mjs)
extends RefCounted

const C := preload("res://core/config.gd")
const BS := preload("res://shaders/block_style.gd")

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
