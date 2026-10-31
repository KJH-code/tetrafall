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


# 위험 판 전체를 칸마다 res 개로 나눈 표: dist (가장 가까운 뚫린 칸까지, max 에서 자름 — 두 번 훑는 근사 거리) · ground · contacts (뚫린 칸 변 가운데 점)
static func field(grid: PackedByteArray, w: int, d: int, h: int, zs: float, res: int = int(C.HAZARD_FIELD_RES), mx: float = C.HAZARD_FOAM_DIST) -> Dictionary:
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
			for s in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
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
