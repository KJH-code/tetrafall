# 상승하는 위험(용암 자리) 화면 계산 (client/hazard-field.js 그대로). 판정은 서버 (state.lava.z), 여기는 모습에 쓸 값만
# 정답 자료: tests/fixtures/hazard.json
extends RefCounted

const C := preload("res://core/config.gd")

const MARGIN := 6 # 위험 판이 덮는 넓이: 필드 + 둘레 이 칸씩 (HAZARD_MARGIN)


# 칸 (x, y) 기둥의 표면 근처: pierce (표면 높이에 걸친 칸이 참 = 뚫고 나옴), ground (표면 아래 가장 높은 단단한 윗면)
static func column_at(grid: PackedByteArray, w: int, d: int, h: int, x: int, y: int, zs: float) -> Dictionary:
	if x < 0 or y < 0 or x >= w or y >= d:
		return {"pierce": false, "ground": -C.HAZARD_DEEP}
	if zs < 0:
		return {"pierce": true, "ground": 0.0}
	var iz := floori(zs)
	if _solid(grid, w, d, h, x, y, iz):
		return {"pierce": true, "ground": zs}
	for z in range(mini(iz - 1, h - 1), -1, -1):
		if _solid(grid, w, d, h, x, y, z):
			return {"pierce": false, "ground": float(z + 1)}
	return {"pierce": false, "ground": 0.0}


static func _solid(grid: PackedByteArray, w: int, d: int, h: int, x: int, y: int, z: int) -> bool:
	if z < 0 or z >= h:
		return false
	var i := (z * d + y) * w + x
	return i < grid.size() and grid[i] != 0


# 칸 (둘레 MARGIN 포함 cw × cd) 마다 column_at 값: [pierce PackedByteArray (1 = 뚫고 나옴), ground PackedFloat32Array].
# 같은 값이면 field() 결과도 같음 → hazard_view 가 격자가 바뀌어도 이 값이 그대로면 표를 다시 안 셈 (W17: 위험 위에 쌓이는 칸은 표를 안 바꿈)
static func columns(grid: PackedByteArray, w: int, d: int, h: int, zs: float) -> Array:
	var cw := w + 2 * MARGIN
	var cd := d + 2 * MARGIN
	var pierce := PackedByteArray()
	pierce.resize(cw * cd)
	var gr := PackedFloat32Array()
	gr.resize(cw * cd)
	gr.fill(-C.HAZARD_DEEP) # 필드 밖 (column_at 과 같은 값)
	var iz := floori(zs)
	var n := grid.size()
	var plane := w * d
	for y in d:
		for x in w:
			var ci := (y + MARGIN) * cw + x + MARGIN
			if zs < 0: # column_at: 표면이 바닥 아래 → 다 뚫림
				pierce[ci] = 1
				gr[ci] = 0.0
				continue
			var i0 := y * w + x
			if iz < h and iz * plane + i0 < n and grid[iz * plane + i0] != 0:
				pierce[ci] = 1
				gr[ci] = zs
				continue
			var g := 0.0
			for z in range(mini(iz - 1, h - 1), -1, -1):
				var i := z * plane + i0
				if i < n and grid[i] != 0:
					g = float(z + 1)
					break
			gr[ci] = g
	return [pierce, gr]


# 칸 값 (cw × cd) 을 칸마다 res × res 로 늘린 그림 (가장 가까운 값 = 칸 안은 다 같음) — 고도 Image 가 C++ 로 (GDScript 화소 돌기 없이)
static func _blow(data: PackedByteArray, fmt: int, cw: int, cd: int, res: int) -> PackedByteArray:
	var img := Image.create_from_data(cw, cd, false, fmt, data)
	if res != 1:
		img.resize(cw * res, cd * res, Image.INTERPOLATE_NEAREST)
	return img.get_data()


# 위험 판 전체를 칸마다 res 개로 나눈 표: dist (가장 가까운 뚫린 칸까지, max 에서 자름 — 두 번 훑는 근사 거리) · ground · contacts (뚫린 칸 변 가운데 점)
#   · bytes (W17): 위험 셰이더 uField 그림 RGBA8 (r = 거리/3, g = (바닥+10)/40 — G3.hazard_field_texture 가 그대로 씀)
# W17: 값은 예전 (화소마다 두 번 훑기) 과 똑같고 빠르게 — 뚫린 칸 (0) 과 뚫린 칸에서 ceil(mx) 칸보다 먼 칸 (mx) 은 칸 단위로 정해 Image 로 늘리고,
#   그 사이 칸 화소만 훑음 (먼 칸·뚫린 칸 화소는 이웃을 줄이지 못함: mx + a > mx, 0 은 이미 최소). 처음 BIG 대신 mx 로 시작해도 mx 아래 값은 그대로
static func field(grid: PackedByteArray, w: int, d: int, h: int, zs: float, res: int = int(C.HAZARD_FIELD_RES), mx: float = C.HAZARD_FOAM_DIST, cols = null) -> Dictionary:
	var cw := w + 2 * MARGIN
	var cd := d + 2 * MARGIN
	var nx := cw * res
	var ny := cd * res
	if cols == null:
		cols = columns(grid, w, d, h, zs)
	var pierce: PackedByteArray = cols[0]
	var gr: PackedFloat32Array = cols[1]
	# 칸 종류: 0 먼 칸 (mx) · 1 뚫린 칸 (0) · 2 사이 칸 (훑음). 뚫린 칸이 체비쇼프 R = ceil(mx) 칸 안에 없으면 먼 칸:
	#   두 번 훑는 거리 (1, √2 가중) ≥ 유클리드 ≥ 체비쇼프 → 그 칸 화소는 뚫린 화소에서 R + 1/res 칸보다 멂 > mx
	var R := ceili(mx)
	var kind := PackedByteArray()
	kind.resize(cw * cd)
	# 가로로 먼저 (행마다 R 칸 안 뚫린 칸 있음), 다음 세로로 — 칸 수 × (2R+1) × 2
	var row_near := PackedByteArray()
	row_near.resize(cw * cd)
	for cy in cd:
		var last := -1000000
		var base := cy * cw
		for cx in cw:
			if pierce[base + cx]:
				last = cx
			if cx - last <= R:
				row_near[base + cx] = 1
		last = 1000000
		for cx in range(cw - 1, -1, -1):
			if pierce[base + cx]:
				last = cx
			if last - cx <= R:
				row_near[base + cx] = 1
	for cx in cw:
		var last := -1000000
		for cy in cd:
			if row_near[cy * cw + cx]:
				last = cy
			if cy - last <= R:
				kind[cy * cw + cx] = 2
		last = 1000000
		for cy in range(cd - 1, -1, -1):
			if row_near[cy * cw + cx]:
				last = cy
			if last - cy <= R:
				kind[cy * cw + cx] = 2
	var cdist := PackedFloat32Array()
	cdist.resize(cw * cd)
	var cbytes := PackedByteArray()
	cbytes.resize(cw * cd * 4)
	var far_b := roundi(mx / 3.0 * 255.0)
	for ci in cw * cd:
		if pierce[ci]:
			kind[ci] = 1
		cdist[ci] = 0.0 if kind[ci] == 1 else mx
		cbytes[ci * 4] = 0 if kind[ci] == 1 else far_b
		cbytes[ci * 4 + 1] = roundi(clampf((gr[ci] + 10.0) / 40.0, 0.0, 1.0) * 255.0)
		cbytes[ci * 4 + 3] = 255
	var dist := _blow(cdist.to_byte_array(), Image.FORMAT_RF, cw, cd, res).to_float32_array()
	var ground := _blow(gr.to_byte_array(), Image.FORMAT_RF, cw, cd, res).to_float32_array()
	var bytes := _blow(cbytes, Image.FORMAT_RGBA8, cw, cd, res)
	var a := 1.0 / res
	var b := sqrt(2.0) / res
	# 사이 칸 줄 (행마다 [화소 시작, 끝) 목록) — 칸 단위 그대로 res 줄에 씀
	var spans := []
	for cy in cd:
		var row := PackedInt32Array()
		var cx := 0
		while cx < cw:
			if kind[cy * cw + cx] != 2:
				cx += 1
				continue
			var s0 := cx
			while cx < cw and kind[cy * cw + cx] == 2:
				cx += 1
			row.append(s0 * res)
			row.append(cx * res)
		spans.append(row)
	for j in ny:
		var row: PackedInt32Array = spans[j / res]
		var rb := j * nx
		for q in range(0, row.size(), 2):
			for i in range(row[q], row[q + 1]):
				var k := rb + i
				var v := dist[k]
				if i > 0:
					v = minf(v, dist[k - 1] + a)
				if j > 0:
					v = minf(v, dist[k - nx] + a)
					if i > 0:
						v = minf(v, dist[k - nx - 1] + b)
					if i < nx - 1:
						v = minf(v, dist[k - nx + 1] + b)
				dist[k] = v
	for j in range(ny - 1, -1, -1):
		var row: PackedInt32Array = spans[j / res]
		var rb := j * nx
		for q in range(row.size() - 2, -1, -2):
			for i in range(row[q + 1] - 1, row[q] - 1, -1):
				var k := rb + i
				var v := dist[k]
				if i < nx - 1:
					v = minf(v, dist[k + 1] + a)
				if j < ny - 1:
					v = minf(v, dist[k + nx] + a)
					if i < nx - 1:
						v = minf(v, dist[k + nx + 1] + b)
					if i > 0:
						v = minf(v, dist[k + nx - 1] + b)
				dist[k] = v
				bytes[k * 4] = roundi(v / 3.0 * 255.0)
	var contacts := []
	for cy in cd:
		for cx in cw:
			if not pierce[cy * cw + cx]:
				continue
			for s in SIDES:
				var ox: int = cx + s[0]
				var oy: int = cy + s[1]
				if ox >= 0 and oy >= 0 and ox < cw and oy < cd and pierce[oy * cw + ox]:
					continue
				contacts.append({"x": cx - MARGIN + 0.5 + s[0] * 0.5, "y": cy - MARGIN + 0.5 + s[1] * 0.5, "nx": s[0], "ny": s[1]})
	return {"nx": nx, "ny": ny, "res": res, "x0": -MARGIN, "y0": -MARGIN, "w": cw, "d": cd, "dist": dist, "ground": ground, "contacts": contacts, "bytes": bytes}


const SIDES := [[1, 0], [-1, 0], [0, 1], [0, -1]]


# 예전 (W17 전) 표 — 화소마다 두 번 훑기. 테스트가 새 field() 와 값이 똑같은지 대조 (tests/test_perf.gd)
static func field_ref(grid: PackedByteArray, w: int, d: int, h: int, zs: float, res: int = int(C.HAZARD_FIELD_RES), mx: float = C.HAZARD_FOAM_DIST) -> Dictionary:
	var cw := w + 2 * MARGIN
	var cd := d + 2 * MARGIN
	var nx := cw * res
	var ny := cd * res
	var pierce := PackedByteArray()
	pierce.resize(cw * cd)
	var gr := PackedFloat32Array()
	gr.resize(cw * cd)
	for cy in cd:
		for cx in cw:
			var c := column_at(grid, w, d, h, cx - MARGIN, cy - MARGIN, zs)
			pierce[cy * cw + cx] = 1 if c.pierce else 0
			gr[cy * cw + cx] = c.ground
	const BIG := 1e9
	var dist := PackedFloat32Array()
	dist.resize(nx * ny)
	var ground := PackedFloat32Array()
	ground.resize(nx * ny)
	for j in ny:
		for i in nx:
			var ci := (j / res) * cw + (i / res)
			dist[j * nx + i] = 0.0 if pierce[ci] else BIG
			ground[j * nx + i] = gr[ci]
	var a := 1.0 / res
	var b := sqrt(2.0) / res
	for j in ny:
		for i in nx:
			var k := j * nx + i
			var v := dist[k]
			if i > 0:
				v = minf(v, dist[k - 1] + a)
			if j > 0:
				v = minf(v, dist[k - nx] + a)
				if i > 0:
					v = minf(v, dist[k - nx - 1] + b)
				if i < nx - 1:
					v = minf(v, dist[k - nx + 1] + b)
			dist[k] = v
	for j in range(ny - 1, -1, -1):
		for i in range(nx - 1, -1, -1):
			var k := j * nx + i
			var v := dist[k]
			if i < nx - 1:
				v = minf(v, dist[k + 1] + a)
			if j < ny - 1:
				v = minf(v, dist[k + nx] + a)
				if i < nx - 1:
					v = minf(v, dist[k + nx + 1] + b)
				if i > 0:
					v = minf(v, dist[k + nx - 1] + b)
			dist[k] = v
	for k in dist.size():
		dist[k] = minf(mx, dist[k])
	var contacts := []
	for cy in cd:
		for cx in cw:
			if not pierce[cy * cw + cx]:
				continue
			for s in SIDES:
				var ox: int = cx + s[0]
				var oy: int = cy + s[1]
				if ox >= 0 and oy >= 0 and ox < cw and oy < cd and pierce[oy * cw + ox]:
					continue
				contacts.append({"x": cx - MARGIN + 0.5 + s[0] * 0.5, "y": cy - MARGIN + 0.5 + s[1] * 0.5, "nx": s[0], "ny": s[1]})
	return {"nx": nx, "ny": ny, "res": res, "x0": -MARGIN, "y0": -MARGIN, "w": cw, "d": cd, "dist": dist, "ground": ground, "contacts": contacts}


# 차오름 단계: HAZARD_RISE_STEP 칸마다 1
static func rise_step(z: float) -> int:
	return floori(z / C.HAZARD_RISE_STEP + 1e-6)


# 화면 가장자리 경고 세기 (0~HAZARD_VIGNETTE_MAX). gap = 내 z - 표면 z
static func vignette_strength(gap: float, pulse := 0.0) -> float:
	if not (gap < C.HAZARD_VIGNETTE_DIST):
		return minf(C.HAZARD_VIGNETTE_MAX, pulse * 0.15)
	var k := 1.0 - maxf(0.0, gap) / C.HAZARD_VIGNETTE_DIST
	return minf(C.HAZARD_VIGNETTE_MAX, C.HAZARD_VIGNETTE_MAX * k * k + pulse * 0.2)


# 먼 바다가 지평선 쪽으로 둥글게 내려가는 깊이 (필드 가운데에서 r 칸)
static func sea_drop(r: float) -> float:
	var d := maxf(0.0, r - C.HAZARD_CURVE_FROM)
	return d * d * C.HAZARD_CURVE


# 먼 섬·산이 표면에 걸친 곳: objs [{x, y, zBot, zTop, rBot, rTop}] → 큰 것부터 mx 개 [{x, y, r}]
static func far_rings(objs: Array, zs: float, mx: int = int(C.HAZARD_FAR_RINGS), cx := 0.0, cy := 0.0) -> Array:
	var out := []
	for o in objs:
		var zl: float = zs - sea_drop(sqrt((o.x - cx) * (o.x - cx) + (o.y - cy) * (o.y - cy)))
		if not (zl > o.zBot and zl < o.zTop + C.HAZARD_RING_ABOVE):
			continue
		var k := minf(1.0, (zl - o.zBot) / maxf(1e-6, o.zTop - o.zBot))
		var r: float = o.rBot + (o.rTop - o.rBot) * k
		if r > 0.05:
			out.append({"x": o.x, "y": o.y, "r": r})
	out.sort_custom(func(a, b): return a.r > b.r)
	return out.slice(0, mx)
