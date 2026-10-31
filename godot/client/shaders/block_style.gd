# 테마 지형 블록 모습 계산 (JS shared/block-style.js 그대로, terrain.gdshader·지형 조각이 씀). 정답 자료: tests/fixtures/block_style.json (tools/fixtures_g3.mjs)
# 격자는 게임 좌표 그대로: grid[(z * D + y) * W + x], 지형 칸 = 1. skip: 그리지 않는 칸 번호 (건축가 블록) Dictionary {i: true}
extends RefCounted

const C := preload("res://core/config.gd")
const TERRAIN := 1
const DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]]


# 테마 terrain + 공통 스타일 (WORLD_BLOCK_STYLES) + terrain.block 덮어쓰기. 스타일·terrain 없으면 null
static func style(terrain, style_name: String = C.WORLD_BLOCK_STYLE):
	var st = C.WORLD_BLOCK_STYLES.get(style_name)
	if st == null or terrain == null:
		return null
	var s := {"lip": 0.0, "strata": [0.0, 0.0], "brick": null, "grid": [0.0, 0.0], "sheen": 0.0, "sideShade": 1.0, "ao": 0.0, "hi": 0.0, "selfLight": 0.0, "sprout": null}
	s.merge(st, true)
	s.merge(terrain, true)
	if terrain.has("block"):
		s.merge(terrain.block, true)
	s.erase("block")
	var tints: Array = (s.tints if s.get("tints") and s.tints.size() > 0 else [s.side]).slice(0, 3)
	while tints.size() < 3:
		tints.append(tints[tints.size() - 1])
	s.tints = tints
	if s.get("glow") == null:
		s.veins = 0.0
	return s


static func _at(grid: PackedByteArray, w: int, d: int, h: int, skip: Dictionary, x: int, y: int, z: int) -> bool:
	if x < 0 or y < 0 or z < 0 or x >= w or y >= d or z >= h:
		return false
	var i := (z * d + y) * w + x
	return grid[i] == TERRAIN and not skip.has(i)


static func _solid(grid: PackedByteArray, w: int, d: int, h: int, x: int, y: int, z: int) -> bool:
	return z < 0 or (x >= 0 and y >= 0 and x < w and y < d and z < h and grid[(z * d + y) * w + x] != 0)


# 지형 칸마다 이웃이 빈 방향 비트 (1 +x · 2 −x · 4 +y · 8 −y · 16 +z · 32 −z), 순서 z → y → x (지형 칸만)
static func open_bits(grid: PackedByteArray, w: int, d: int, h: int, skip: Dictionary = {}) -> PackedInt32Array:
	var out := PackedInt32Array()
	for z in h:
		for y in d:
			for x in w:
				var i := (z * d + y) * w + x
				if grid[i] != TERRAIN or skip.has(i):
					continue
				var m := 0
				if not _at(grid, w, d, h, skip, x + 1, y, z): m |= 1
				if not _at(grid, w, d, h, skip, x - 1, y, z): m |= 2
				if not _at(grid, w, d, h, skip, x, y + 1, z): m |= 4
				if not _at(grid, w, d, h, skip, x, y - 1, z): m |= 8
				if not _at(grid, w, d, h, skip, x, y, z + 1): m |= 16
				if z > 0 and not _at(grid, w, d, h, skip, x, y, z - 1): m |= 32
				out.append(m)
	return out


static func _imul(a: int, b: int) -> int: # Math.imul (부호 없는 32비트로)
	a &= 0xffffffff
	b &= 0xffffffff
	return ((a & 0xffff) * b + (((a >> 16) * b) << 16)) & 0xffffffff


# 칸 자리로 정하는 0..1 난수 (JS cellRand 와 비트까지 같음)
static func cell_rand(x: int, y: int, z: int, k: int = 0) -> float:
	var h := _imul(x + 1013, 73856093) ^ _imul(y + 2029, 19349663) ^ _imul(z + 4051, 83492791) ^ _imul(k + 7, 2654435761)
	h = _imul(h ^ (h >> 15), 2246822507)
	h = _imul(h ^ (h >> 13), 3266489909)
	return float(h ^ (h >> 16)) / 4294967296.0


# 칸마다 셰이더 값: Color(open, ao, lift, 0) — MultiMesh custom_data (INSTANCE_CUSTOM). 순서 = open_bits
static func cell_looks(grid: PackedByteArray, w: int, d: int, h: int, skip: Dictionary = {}) -> PackedColorArray:
	var open := open_bits(grid, w, d, h, skip)
	var out := PackedColorArray()
	out.resize(open.size())
	var n := 0
	for z in h:
		for y in d:
			for x in w:
				var i := (z * d + y) * w + x
				if grid[i] != TERRAIN or skip.has(i):
					continue
				var a := 0
				for k in 4:
					if _solid(grid, w, d, h, x + DIRS[k][0], y + DIRS[k][1], z + 1): a |= 1 << k
					if _solid(grid, w, d, h, x + DIRS[k][0], y + DIRS[k][1], z - 1): a |= 16 << k
				out[n] = Color(open[n], a, cell_rand(x, y, z, 1) - 0.5, 0.0)
				n += 1
	return out


# 튀어나온 조각 자리 (JS sproutSpots): [{x, y, z, face (0..3 옆 · 4 윗면), u, v, s, spin, edge}], max 넘으면 고르게 솎음
static func sprout_spots(grid: PackedByteArray, w: int, d: int, h: int, skip: Dictionary, sp, max_n: int) -> Array:
	var all := _all_sprouts(grid, w, d, h, skip, sp)
	if all.size() <= max_n:
		return all
	var out := []
	for i in max_n:
		out.append(all[int(floor(float(i) * all.size() / max_n))])
	return out


static func _all_sprouts(grid: PackedByteArray, w: int, d: int, h: int, skip: Dictionary, sp) -> Array:
	var out := []
	if sp == null:
		return out
	var looks := open_bits(grid, w, d, h, skip)
	var n := 0
	var s0: float = sp.size[0]
	var s1: float = sp.size[1]
	var side: float = sp.get("side", 0.0)
	var top: float = sp.get("top", 0.0)
	var ground: bool = bool(sp.get("ground", false))
	for z in h:
		for y in d:
			for x in w:
				var i := (z * d + y) * w + x
				if grid[i] != TERRAIN or skip.has(i):
					continue
				var m := looks[n]
				n += 1
				for f in 4:
					if not (m & (1 << f)) or cell_rand(x, y, z, 10 + f) >= side:
						continue
					if ground and not _solid(grid, w, d, h, x + DIRS[f][0], y + DIRS[f][1], z - 1):
						continue
					var v := -0.5 if ground else (cell_rand(x, y, z, 30 + f) - 0.5) * 0.5
					out.append({"x": x, "y": y, "z": z, "face": f, "u": (cell_rand(x, y, z, 20 + f) - 0.5) * 0.6, "v": v, "s": s0 + cell_rand(x, y, z, 40 + f) * (s1 - s0), "spin": cell_rand(x, y, z, 50 + f)})
				if m & 16 and top > 0.0 and cell_rand(x, y, z, 14) < top:
					var edges := []
					for f in 4:
						if m & (1 << f):
							edges.append(f)
					var f: int = edges[int(floor(cell_rand(x, y, z, 15) * edges.size()))] if edges.size() else int(floor(cell_rand(x, y, z, 15) * 4))
					var along := (cell_rand(x, y, z, 16) - 0.5) * 0.7
					var sgn := -1.0 if f % 2 else 1.0
					var u := sgn * 0.38 if f < 2 else along
					var v := along if f < 2 else sgn * 0.38
					out.append({"x": x, "y": y, "z": z, "face": 4, "u": u, "v": v, "s": (s0 + cell_rand(x, y, z, 44) * (s1 - s0)) * C.BLOCK_SPROUT_TOP_SCALE, "spin": cell_rand(x, y, z, 54), "edge": f})
	return out
