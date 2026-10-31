# 떠 있는 섬·먼 배경 (client/world.js layout 그대로, 2026-10-31 총괄: 모양은 G1, 재질은 G3): 필드 아래 섬 · 섬 뿌리 바위 · 먼 떠 있는 섬 (소품 몇 개)
# · 구름 (섬 아래 구름 바다 + 하늘) · 구름 바다 판 (끝으로 투명) · 지평선 둘레 먼 산·성·수정 등. 맵 테마 (WORLD_THEMES) 가 있을 때만
# 난수는 world.js rng (LCG) 를 같은 순서로 불러 JS 판과 같은 자리. 모양은 전부 꼭짓점 색 + 묶음마다 메시 하나 (그리기 적게)
# 재질: make_mat (G3 toon, Callable(opts) -> Material) 이 있으면 그것, 없으면 StandardMaterial3D. 게임 좌표로 만들고 마지막에 Co.gxyz
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")

var drift := Node3D.new() # 천천히 도는 먼 섬·구름 (필드 가운데 축)
var make_mat = null # Callable(opts: Dictionary) -> Material 또는 null: G3 재질 (opts: vertex_color, outline, emissive, unshaded, no_fog)
var theme_id = null
var size := Vector2i.ZERO
var low := false
var far_objs := [] # 위험 액체에 잠길 먼 섬·산 {x, y, zBot, zTop, rBot, rTop, drift} (게임 좌표, hazard_field.far_rings)


func _ready() -> void:
	add_child(drift)


# world.js rng: s = s * 1664525 + 1013904223 (32비트), 0..1
class Rng:
	var s := 0

	func _init(seed: int) -> void:
		s = seed & 0xffffffff

	func next() -> float:
		s = (s * 1664525 + 1013904223) & 0xffffffff
		return s / 4294967296.0


# ---------- 모양 묶음 (world.js Parts): 삼각형 + 색, 게임 좌표 ----------
class Parts:
	var pos := PackedVector3Array()
	var col := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, k: Color) -> void:
		pos.append_array([a, b, c])
		col.append_array([k, k, k])

	# tris: 지역 좌표 삼각형 (z 위), xf: 게임 좌표 Transform3D
	func add(tris: PackedVector3Array, k: Color, xf: Transform3D) -> void:
		for i in tris.size():
			pos.append(xf * tris[i])
			col.append(k)

	func mesh() -> ArrayMesh:
		if pos.is_empty():
			return null
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(0, pos.size(), 3):
			# 게임 → 고도 좌표 (회전이라 감김 방향 그대로), 면 법선은 평평하게 (flatShading)
			var a := Co.gpos(pos[i])
			var b := Co.gpos(pos[i + 1])
			var c := Co.gpos(pos[i + 2])
			var n := (c - a).cross(b - a).normalized()
			for j in 3:
				st.set_color(col[i + j])
				st.set_normal(n)
				st.add_vertex([a, b, c][j])
		return st.commit()


# 색: 0xRRGGBB → 선형 Color (three.js Color 와 같은 공간 — 곱하기·섞기를 JS 처럼)
static func lin(c) -> Color:
	if c is Color:
		return c
	return Co.color(c).srgb_to_linear()


static func shade(c, k: float) -> Color:
	var l := lin(c)
	return Color(l.r * k, l.g * k, l.b * k)


# ---------- 기본 도형 (three.js 도형 + Z_UP: 축이 z 위, 가운데 원점) ----------
static func cylinder(rt: float, rb: float, h: float, seg: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var b0 := Vector3(sin(a0) * rb, cos(a0) * rb, -h / 2)
		var b1 := Vector3(sin(a1) * rb, cos(a1) * rb, -h / 2)
		var t0 := Vector3(sin(a0) * rt, cos(a0) * rt, h / 2)
		var t1 := Vector3(sin(a1) * rt, cos(a1) * rt, h / 2)
		out.append_array([t0, b0, b1])
		if rt > 0:
			out.append_array([t0, b1, t1])
			out.append_array([Vector3(0, 0, h / 2), t0, t1])
		out.append_array([Vector3(0, 0, -h / 2), b1, b0])
	return out


static func cone(r: float, h: float, seg: int) -> PackedVector3Array:
	return cylinder(0.0, r, h, seg)


# 꼭대기 점이 칸마다 따로 밀린 원뿔 (먼 봉우리): tips[i] = i 번째 꼭대기 점 x 밀기 (three 는 y 위 기준 x — z 위로 세워도 x 그대로)
static func peak(r: float, h: float, seg: int, tips: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var b0 := Vector3(sin(a0) * r, cos(a0) * r, -h / 2)
		var b1 := Vector3(sin(a1) * r, cos(a1) * r, -h / 2)
		var t0 := Vector3(tips[i], 0, h / 2)
		var t1 := Vector3(tips[i + 1], 0, h / 2)
		out.append_array([t0, b0, t1, b0, b1, t1, Vector3(0, 0, -h / 2), b1, b0])
	return out


static func box(sx: float, sy: float, sz: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var h := Vector3(sx, sy, sz) / 2
	for a in 3:
		for s in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[a] = s
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(a + 1) % 3] = 1
			v[(a + 2) % 3] = 1
			if s < 0:
				var t := u
				u = v
				v = t
			var c := n * h
			var p := [c - u * h - v * h, c + u * h - v * h, c + u * h + v * h, c - u * h + v * h]
			out.append_array([p[0], p[1], p[2], p[0], p[2], p[3]])
	return out


# 정이십면체 (반지름 r) — 돌의 십이면체도 이것으로 (저폴리 덩어리면 충분)
static func ico(r: float) -> PackedVector3Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var out := PackedVector3Array()
	for tri in f:
		for i in [0, 2, 1]: # 바깥이 앞면 (게임 좌표 오른손)
			out.append((v[tri[i]] as Vector3).normalized() * r)
	return out


static func octa(r: float) -> PackedVector3Array:
	var v := [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]
	var out := PackedVector3Array()
	for z in [4, 5]:
		for q in [[0, 2], [2, 1], [1, 3], [3, 0]]:
			var a: Vector3 = v[q[0]]
			var b: Vector3 = v[q[1]]
			if z == 4:
				out.append_array([a, b, v[z]])
			else:
				out.append_array([b, a, v[z]])
	return out


# 반구 (위로 볼록, 버섯 갓): 가로 seg, 세로 rings
static func dome(r: float, seg: int, rings: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var pt := func(i: int, j: int) -> Vector3:
		var a := TAU * i / seg
		var e := (PI / 2) * j / rings
		return Vector3(cos(a) * cos(e) * r, sin(a) * cos(e) * r, sin(e) * r)
	for j in rings:
		for i in seg:
			var a: Vector3 = pt.call(i, j)
			var b: Vector3 = pt.call(i + 1, j)
			var c: Vector3 = pt.call(i, j + 1)
			var d: Vector3 = pt.call(i + 1, j + 1)
			out.append_array([a, b, d])
			if j < rings - 1:
				out.append_array([a, d, c])
	return out


# world.js at(x, y, z, rz, s): 자리 + z 축 돌림 + 크기 (도형이 이미 z 위라 Z_UP 은 필요 없음)
static func at(x: float, y: float, z: float, rz := 0.0, s := 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3(0, 0, 1), rz).scaled(Vector3(s, s, s)), Vector3(x, y, z))


# three Euler (x, y, z) 순서 XYZ = Rx·Ry·Rz
static func euler(ex: float, ey: float, ez: float) -> Basis:
	return Basis(Vector3(1, 0, 0), ex) * Basis(Vector3(0, 1, 0), ey) * Basis(Vector3(0, 0, 1), ez)


static func pick(r: Rng, list: Array):
	return list[floori(r.next() * list.size())]


# ---------- 섬 (world.js islandGeometry): 위는 판 모양 사각, 아래로 둥글게 좁아져 뾰족 ----------
static func island(p: Parts, w: float, d: float, depth: float, seed: int, bands: Array, xf: Transform3D) -> void:
	var r := Rng.new(seed)
	var n := 36
	var spec := [[0.0, 1.0, 0.0], [-1.1, 0.985, 0.02], [-0.3 * depth, 0.82, 0.08], [-0.55 * depth, 0.58, 0.12], [-0.8 * depth, 0.33, 0.15], [-0.95 * depth, 0.14, 0.2]]
	var rings := []
	for k in spec.size():
		var ring := []
		for i in n:
			var a := TAU * i / n + PI / 4
			var c := cos(a)
			var sn := sin(a)
			var sq := 1.0 / maxf(absf(c), absf(sn))
			var round_ := lerpf(sq, 1.05, minf(1.0, k / 2.5))
			var j: float = 1.0 + (r.next() - 0.5) * 2 * spec[k][2]
			var z: float = spec[k][0] * (0.9 + r.next() * 0.2 if k > 1 else 1.0)
			ring.append(Vector3(c * round_ * (w / 2) * spec[k][1] * j, sn * round_ * (d / 2) * spec[k][1] * j, z))
		rings.append(ring)
	var tip := Vector3((r.next() - 0.5) * 1.5, (r.next() - 0.5) * 1.5, -depth * 1.1)
	var last := rings.size() - 1
	for k in last:
		var base := lin(bands[mini(k, bands.size() - 1)])
		for i in n:
			var a: Vector3 = rings[k][i]
			var b: Vector3 = rings[k][(i + 1) % n]
			var c: Vector3 = rings[k + 1][i]
			var e: Vector3 = rings[k + 1][(i + 1) % n]
			var m := 0.92 + ((i * 7 + k * 3) % 5) * 0.035
			var v := Color(base.r * m, base.g * m, base.b * m)
			p.tri(xf * a, xf * c, xf * b, v)
			p.tri(xf * b, xf * c, xf * e, v)
	var tc := shade(bands[bands.size() - 1], 0.75)
	for i in n:
		p.tri(xf * rings[last][i], xf * tip, xf * rings[last][(i + 1) % n], tc)


# ---------- 소품 (world.js prop) ----------
static func prop(solid: Parts, glow: Parts, kind: String, L: Dictionary, r: Rng, x: float, y: float, z: float, s: float) -> void:
	var rz := r.next() * TAU
	var leaf = pick(r, L.leaf) if L.has("leaf") else 0x60a040
	match kind:
		"pine":
			solid.add(cylinder(0.1, 0.15, 0.6, 5), lin(L.trunk), at(x, y, z + 0.3 * s, rz, s))
			for k in 3:
				solid.add(cone(0.7 - k * 0.17, 0.85, 6), shade(leaf, 1 - k * 0.04), at(x, y, z + (0.85 + k * 0.42) * s, rz + k, s))
		"round":
			solid.add(cylinder(0.1, 0.15, 0.9, 5), lin(L.trunk), at(x, y, z + 0.45 * s, rz, s))
			solid.add(ico(0.65), lin(leaf), at(x, y, z + 1.3 * s, rz, s))
			solid.add(ico(0.42), shade(leaf, 1.1), at(x + 0.4 * s, y, z + 1.0 * s, rz, s))
		"rock", "lavarock":
			solid.add(ico(0.45), lin(L.rock), at(x, y, z + 0.15 * s, rz, s) * Transform3D(Basis().scaled(Vector3(1, 0.8, 0.6)), Vector3.ZERO))
			if kind == "lavarock":
				glow.add(ico(0.2), lin(pick(r, L.glow)), at(x + 0.25 * s, y, z + 0.3 * s, rz, s))
		"cactus":
			solid.add(cylinder(0.16, 0.18, 1.3, 6), lin(leaf), at(x, y, z + 0.65 * s, rz, s))
			for side in [-1, 1]:
				var ax: float = x + cos(rz) * 0.3 * side * s
				var ay: float = y + sin(rz) * 0.3 * side * s
				var hz: float = z + (0.55 + (0.2 if side > 0 else 0.0)) * s
				solid.add(cylinder(0.1, 0.1, 0.45, 6), lin(leaf), at(ax, ay, hz + 0.22 * s, rz, s))
				solid.add(cylinder(0.1, 0.1, 0.3, 6), lin(leaf), at((ax + x) / 2, (ay + y) / 2, hz, rz, s) * Transform3D(Basis(Vector3(0, 1, 0), PI / 2), Vector3.ZERO))
		"palm":
			var px := x
			var py := y
			var lean := r.next() * TAU
			for k in 4:
				solid.add(cylinder(0.09, 0.12, 0.45, 5), lin(L.trunk), at(px, py, z + (0.22 + k * 0.42) * s, rz, s))
				px += cos(lean) * 0.08 * s
				py += sin(lean) * 0.08 * s
			var top := z + 1.75 * s
			for k in 5:
				var a := TAU * k / 5 + rz
				var m := Transform3D(Basis(Vector3(0, 0, 1), a).scaled(Vector3(s, s, s)), Vector3(px + cos(a) * 0.4 * s, py + sin(a) * 0.4 * s, top - 0.1 * s))
				m = m * Transform3D(Basis(Vector3(0, 1, 0), PI / 2 + 0.5), Vector3.ZERO) # 잎을 바깥으로 눕힘
				solid.add(cone(0.16, 0.9, 4), lin(leaf), m)
		"pyramid":
			solid.add(cone(1.0, 1.1, 4), lin(L.terrain.top), at(x, y, z + 0.55 * s, PI / 4 + rz, s))
		"crystal":
			var col = pick(r, L.glow)
			var n := 3 + floori(r.next() * 2)
			for k in n:
				var h := (0.7 + r.next() * 0.9) * s
				var px := x + (r.next() - 0.5) * 0.5 * s
				var py := y + (r.next() - 0.5) * 0.5 * s
				var b := euler((r.next() - 0.5) * 0.7, (r.next() - 0.5) * 0.7, r.next() * 3)
				glow.add(octa(1.0), shade(col, 0.85 + r.next() * 0.3), Transform3D(b.scaled_local(Vector3(0.22 * s, 0.22 * s, h)), Vector3(px, py, z + h * 0.45)))
		"mushroom":
			var h := (0.8 + r.next() * 0.8) * s
			solid.add(cylinder(0.12 * s, 0.18 * s, h, 6), lin(L.trunk), at(x, y, z + h / 2, rz))
			var cap := Transform3D(Basis(Vector3(0, 0, 1), rz).scaled_local(Vector3(s, s, s * 0.55)), Vector3(x, y, z + h))
			glow.add(dome(0.6, 7, 3), lin(pick(r, L.glow)), cap)
		"deadtree":
			solid.add(cylinder(0.07, 0.14, 1.4, 5), lin(L.trunk), at(x, y, z + 0.7 * s, rz, s))
			for k in 3:
				var a := rz + k * 2.1
				var m := Transform3D(Basis(Vector3(0, 0, 1), a).scaled(Vector3(s, s, s)), Vector3(x + cos(a) * 0.22 * s, y + sin(a) * 0.22 * s, z + (0.9 + k * 0.18) * s))
				solid.add(cylinder(0.03, 0.06, 0.6, 4), lin(L.trunk), m * Transform3D(Basis(Vector3(0, 1, 0), 0.9), Vector3.ZERO))
		"tower", "spire":
			var tall := kind == "spire"
			var h := (2.2 if tall else 1.4) * s
			var rad := (0.32 if tall else 0.45) * s
			solid.add(cylinder(rad, rad * 1.08, h, 8), lin(L.wall), at(x, y, z + h / 2, rz))
			solid.add(cone(rad * 1.35, (1.1 if tall else 0.8) * s, 8), lin(L.roof), at(x, y, z + h + (0.55 if tall else 0.4) * s, rz))
			if L.get("flag") != null:
				solid.add(cylinder(0.02 * s, 0.02 * s, 0.6 * s, 4), lin(L.trunk), at(x, y, z + h + 1.0 * s, rz))
				solid.add(box(0.35 * s, 0.02 * s, 0.22 * s), lin(L.flag), at(x + 0.18 * s, y, z + h + 1.15 * s))
		"house":
			solid.add(box(0.9 * s, 0.8 * s, 0.7 * s), lin(L.wall), at(x, y, z + 0.35 * s, rz))
			solid.add(cone(0.78 * s, 0.6 * s, 4), lin(L.roof), at(x, y, z + 1.0 * s, rz + PI / 4))


# 먼 떠 있는 작은 섬 (world.js islet)
func islet(solid: Parts, glow: Parts, L: Dictionary, r: Rng, x: float, y: float, z: float) -> void:
	var s := 1.6 + r.next() * 2.4
	far_objs.append({"x": x, "y": y, "zTop": z + 0.3, "zBot": z - s * 2, "rTop": s * 1.1, "rBot": 0.0, "drift": true})
	island(solid, s * 2, s * 2, s * 1.8, floori(r.next() * 1e6), L.cliff, at(x, y, z))
	solid.add(box(s * 2, s * 2, 0.3), lin(L.floor.a), at(x, y, z + 0.15))
	var n := 1 + floori(r.next() * 3)
	for k in n:
		prop(solid, glow, pick(r, L.props), L, r, x + (r.next() - 0.5) * s * 1.2, y + (r.next() - 0.5) * s * 1.2, z + 0.3, 0.8 + r.next() * 0.6)


# 구름 한 덩이 (world.js cloud)
static func cloud(p: Parts, color, r: Rng, x: float, y: float, z: float, s: float) -> void:
	var n := 3 + floori(r.next() * 3)
	for k in n:
		var b := (1.1 + r.next() * 1.5) * s
		var pos := Vector3(x + (k - n / 2.0) * 1.5 * s, y + (r.next() - 0.5) * 1.4 * s, z + (r.next() - 0.3) * 0.7 * s)
		var bs := euler(r.next(), r.next(), r.next()).scaled_local(Vector3(b, b, b * 0.6))
		p.add(ico(1.0), lin(color), Transform3D(bs, pos))


# 먼 배경 (world.js farShapes): 지평선 둘레, 지평선 색을 미리 섞어 멀게 (안개 없이)
func far_shapes(solid: Parts, glow: Parts, L: Dictionary, r: Rng, cx: float, cy: float, n: int) -> void:
	var f: Dictionary = L.far
	var S: Dictionary = C.WORLD_FAR
	for k in n:
		var a := TAU * k / n + r.next() * 0.35
		var dist: float = S.dist[0] + r.next() * (S.dist[1] - S.dist[0])
		var h: float = S.height[0] + r.next() * (S.height[1] - S.height[0])
		var rad: float = S.radius[0] + r.next() * (S.radius[1] - S.radius[0])
		var kind: String = pick(r, f.shapes)
		var x := cx + cos(a) * dist
		var y := cy + sin(a) * dist
		var tint := lin(f.color).lerp(lin(L.sky.horizon), f.haze[0] + r.next() * (f.haze[1] - f.haze[0]))
		var base: float = f.base
		var shape: Array = {"mesa": [0.6, 1, 0.7], "volcano": [1, 1, 0.22], "peak": [1, 1, 0], "pyramid": [1, 1, 0]}.get(kind, [1, 0.6, 0.1])
		far_objs.append({"x": x, "y": y, "zBot": base, "zTop": base + h * shape[0], "rBot": rad * shape[1], "rTop": rad * shape[2], "drift": false})
		match kind:
			"mesa":
				solid.add(cylinder(rad * 0.7, rad, h * 0.6, 7), tint, at(x, y, base + h * 0.3, r.next() * 3))
			"pyramid":
				solid.add(cone(rad, h, 4), tint, at(x, y, base + h / 2, r.next() * 3))
			"volcano":
				solid.add(cylinder(rad * 0.22, rad, h, 8), tint, at(x, y, base + h / 2, r.next() * 3))
				glow.add(cylinder(rad * 0.2, rad * 0.21, 0.6, 8), lin(pick(r, L.glow)), at(x, y, base + h + 0.1))
			"crystal":
				for j in 3:
					var hh := h * (0.6 + r.next() * 0.6)
					var px := x + (r.next() - 0.5) * rad
					var py := y + (r.next() - 0.5) * rad
					var b := euler((r.next() - 0.5) * 0.4, (r.next() - 0.5) * 0.4, r.next() * 3)
					glow.add(octa(1.0), lin(pick(r, L.glow)).lerp(lin(L.sky.horizon), 0.35), Transform3D(b.scaled_local(Vector3(rad * 0.25, rad * 0.25, hh * 0.6)), Vector3(px, py, base + hh * 0.5)))
			"cumulus":
				for j in 5:
					var b := rad * (0.5 + r.next() * 0.4) * (1 - j * 0.12)
					var px := x + (r.next() - 0.5) * rad * 0.8
					var py := y + (r.next() - 0.5) * rad * 0.8
					var bs := euler(r.next(), r.next(), r.next()).scaled_local(Vector3(b, b, b * 0.75))
					glow.add(ico(1.0), shade(tint, 0.94 + j * 0.03), Transform3D(bs, Vector3(px, py, base + j * b * 0.9)))
			"bigshroom":
				solid.add(cylinder(rad * 0.12, rad * 0.18, h, 6), tint, at(x, y, base + h / 2))
				glow.add(dome(1.0, 8, 3), lin(pick(r, L.glow)).lerp(lin(L.sky.horizon), 0.3), Transform3D(Basis().scaled(Vector3(rad * 0.7, rad * 0.7, rad * 0.35)), Vector3(x, y, base + h)))
			"castle":
				var wv := rad * 1.2
				solid.add(box(wv, wv * 0.5, h * 0.4), tint, at(x, y, base + h * 0.2, a))
				for side in [-1, 1]:
					var tx: float = x + cos(a + PI / 2) * side * wv * 0.5
					var ty: float = y + sin(a + PI / 2) * side * wv * 0.5
					solid.add(cylinder(rad * 0.18, rad * 0.18, h * 0.65, 7), tint, at(tx, ty, base + h * 0.33))
					solid.add(cone(rad * 0.24, h * 0.25, 7), shade(tint, 0.85), at(tx, ty, base + h * 0.78))
			_:
				# 봉우리를 살짝 비틀기: three ConeGeometry 의 꼭대기 점 (칸마다 하나, seg + 1 개) 을 하나씩 x 로 밂 → 꼭대기가 갈라짐
				var seg := 5 + floori(r.next() * 3)
				var tips := []
				for i in seg + 1:
					tips.append((r.next() - 0.5) * 2)
				solid.add(peak(rad, h, seg, tips), tint, at(x, y, base + h / 2, r.next() * 3))


# 테마·판 크기가 바뀌면 다시 만듦 (world.js layout). theme_id null 이면 비움
func build(id, w: int, d: int, low_gfx: bool, h: int = int(C.GRID_H)) -> void:
	if id == theme_id and size == Vector2i(w, d) and low_gfx == low:
		return
	motes = {}
	theme_id = id
	size = Vector2i(w, d)
	low = low_gfx
	for n in get_children():
		if n != drift:
			n.queue_free()
	for n in drift.get_children():
		n.queue_free()
	far_objs = []
	if id == null or not C.WORLD_THEMES.has(id):
		return
	var L: Dictionary = C.WORLD_THEMES[id]
	var cx := w / 2.0
	var cy := d / 2.0
	var rand := Rng.new(int(L.seed))
	var k: float = C.WORLD_LOW_DETAIL if low else 1.0
	# 필드 아래 섬 (윗면은 바닥 판 바로 아래)
	var isl := Parts.new()
	island(isl, w, d, maxf(w, d) * 0.85, int(L.seed), L.cliff, at(cx, cy, -0.3))
	_add(isl.mesh(), {"vertex_color": true}, self, true)
	# 섬 뿌리 바위 + 먼 섬 (한 메시) + 빛나는 소품 (한 메시)
	var solid := Parts.new()
	var glow := Parts.new()
	for i in 6:
		var a := rand.next() * TAU
		prop(solid, glow, "rock", L, rand, cos(a) * w * 0.3, sin(a) * d * 0.3, -2.5 - rand.next() * 4, 1.2 + rand.next() * 1.5)
	var islets := roundi(L.islets * k)
	for i in islets:
		var a := TAU * i / islets + rand.next() * 0.6
		var dist := w * 0.5 + 14 + rand.next() * 26
		islet(solid, glow, L, rand, cos(a) * dist, sin(a) * dist, -7 + rand.next() * 13)
	var sky := Parts.new()
	var clouds := roundi(L.clouds * k)
	for i in clouds:
		var a := rand.next() * TAU
		var low_cloud := i < clouds * 0.7 # 대부분은 섬 아래 구름 바다, 나머지는 멀리 하늘에
		var dist := 6 + rand.next() * 55 if low_cloud else 45 + rand.next() * 40
		var z: float = L.sea[1] + 1.5 - rand.next() * 2.5 if low_cloud else 16 + rand.next() * 14
		cloud(sky, L.cloud, rand, cos(a) * dist, sin(a) * dist, z, 1 + rand.next() * 1.4)
	_add(solid.mesh(), {"vertex_color": true, "outline": false}, drift, true)
	_add(glow.mesh(), {"vertex_color": true, "unshaded": true}, drift, false)
	_add(sky.mesh(), {"vertex_color": true, "outline": false, "emissive": shade(L.cloud, float(L.get("cloudGlow", 0.45)))}, drift, false)
	drift.position = Co.gxyz(cx, cy, 0)
	# 구름 바다: 넓은 원판, 끝으로 갈수록 투명
	var sea := MeshInstance3D.new()
	sea.mesh = sea_mesh(lin(L.sea[0]), C.WORLD_SEA_FADE[0], C.WORLD_SEA_FADE[1])
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.disable_fog = true
	sm.render_priority = -1
	sea.material_override = sm
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.position = Co.gxyz(cx, cy, L.sea[1])
	add_child(sea)
	# 먼 배경: 안개 없이 (멀리서도 실루엣)
	var fs := Parts.new()
	var fg := Parts.new()
	far_shapes(fs, fg, L, rand, cx, cy, roundi(L.far.count * (0.6 if low else 1.0)))
	_add(fs.mesh(), {"vertex_color": true, "outline": false, "no_fog": true}, self, false)
	_add(fg.mesh(), {"vertex_color": true, "unshaded": true, "no_fog": true}, self, false)
	# 떠다니는 빛: 필드 둘레 (반딧불은 떠돌고, 불씨는 위로) — world.js motes, 같은 난수 순서
	if L.get("motes") != null:
		var M: Dictionary = L.motes
		var rise: bool = M.get("rise", false)
		var n := roundi(M.count * k)
		var base := []
		for i in n:
			var bx := cx + (rand.next() - 0.5) * (w + 10)
			var by := cy + (rand.next() - 0.5) * (d + 10)
			var bz := rand.next() * (h * 0.6 if rise else 7.0) + (0.0 if rise else 0.5)
			base.append([bx, by, bz, rand.next()])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var q := QuadMesh.new()
		q.size = Vector2.ONE * float(M.size)
		mm.mesh = q
		mm.instance_count = n
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.no_depth_test = false
		mat.disable_fog = true
		mat.albedo_color = Co.color(M.color)
		mat.albedo_texture = dot_texture()
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1000.0
		add_child(mi)
		motes = {"mi": mi, "mat": mat, "base": base, "speed": float(M.get("speed", 1.0)), "rise": rise, "top": h * 0.6}


# 구름 바다 판 (world.js seaMaterial: 1 - smoothstep(inner, outer, 거리) 를 고리마다 꼭짓점 알파로)
static func sea_mesh(c: Color, inner: float, outer: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 48
	var radii := [0.0, inner]
	for i in range(1, WC.SEA_RINGS + 1):
		radii.append(inner + (outer - inner) * i / float(WC.SEA_RINGS))
	var alpha := func(r: float) -> float:
		var t := clampf((r - inner) / (outer - inner), 0.0, 1.0)
		return 1.0 - t * t * (3.0 - 2.0 * t)
	for k in radii.size() - 1:
		var r0: float = radii[k]
		var r1: float = radii[k + 1]
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p := [Vector2(cos(a0), sin(a0)) * r0, Vector2(cos(a1), sin(a1)) * r0, Vector2(cos(a0), sin(a0)) * r1, Vector2(cos(a1), sin(a1)) * r1]
			var al := [alpha.call(r0), alpha.call(r0), alpha.call(r1), alpha.call(r1)]
			for q in [[0, 1, 2], [1, 3, 2]]: # 위 (고도 +y) 에서 볼 때 시계 방향 = 고도 앞면 (예전 순서는 뒤집혀 위에서 안 보였음)
				for j in q:
					st.set_color(Color(c, al[j]))
					st.set_normal(Vector3.UP)
					st.add_vertex(Co.gxyz(p[j].x, p[j].y, 0))
	return st.commit()


func _add(m: ArrayMesh, opts: Dictionary, parent: Node3D, shadow: bool) -> void:
	if m == null:
		return
	var n := MeshInstance3D.new()
	n.mesh = m
	var mat = make_mat.call(opts) if make_mat != null else null # G3 가 null 을 주면 (빛 안 받는 것 등) 아래 기본
	if mat != null:
		n.material_override = mat
	else:
		var sm := StandardMaterial3D.new()
		sm.vertex_color_use_as_albedo = true
		sm.vertex_color_is_srgb = false
		sm.roughness = 1.0
		if opts.get("unshaded", false):
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if opts.has("emissive"):
			sm.emission_enabled = true
			sm.emission = opts.emissive
		sm.disable_fog = opts.get("no_fog", false)
		n.material_override = sm
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(n)


# 떠다니는 빛 한 점 그림: 가운데 밝은 동그라미 (world.js dotTexture)
static func dot_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


var motes := {} # 떠다니는 빛 {mi, mat, base: [[x, y, z, 위상]], speed, rise, top}


# 매 프레임: 먼 섬·구름을 천천히 돌리고, 떠다니는 빛을 움직임 (world.js update)
func step(dt: float) -> void:
	drift.rotation.y += dt * C.WORLD_DRIFT_SPEED
	if motes.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	var mm: MultiMesh = motes.mi.multimesh
	var top: float = motes.top
	for i in motes.base.size():
		var b: Array = motes.base[i]
		var ph: float = b[3]
		var p: Vector3
		if motes.rise: # 불씨: 위로 올라가다 맨 위에서 아래로 다시
			var z := fposmod(b[2] + t * motes.speed * (0.6 + ph), top) - 2.0
			p = Vector3(b[0] + sin(t * 0.8 + ph * 9) * 0.4, b[1] + cos(t * 0.7 + ph * 7) * 0.4, z)
		else:
			p = Vector3(b[0] + sin(t * 0.5 + ph * 9) * 0.8, b[1] + cos(t * 0.43 + ph * 7) * 0.8, b[2] + sin(t * 0.9 + ph * 5) * 0.5)
		mm.set_instance_transform(i, Transform3D(Basis(), Co.gpos(p)))
	(motes.mat as StandardMaterial3D).albedo_color.a = 0.65 + 0.35 * sin(t * 2.3)


# 위험 액체에 잠길 먼 섬·산 (world.js farObjects): 도는 섬은 지금 돈 각만큼 돌려 월드 자리로
func far_objects() -> Array:
	var a := drift.rotation.y
	var ca := cos(a)
	var sa := sin(a)
	var c := Co.game(drift.position)
	var out := []
	for o in far_objs:
		if o.drift:
			var q: Dictionary = o.duplicate()
			q.x = c.x + o.x * ca - o.y * sa
			q.y = c.y + o.x * sa + o.y * ca
			out.append(q)
		else:
			out.append(o)
	return out
