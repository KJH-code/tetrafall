# 지형 블록에서 튀어나온 조각 (JS client/blocks.js BlockDecor 그대로): 수정 결정·현무암 기둥·버섯·튀어나온 벽돌·사암 덩어리·턱·풀.
# 부분 (모양) 마다 MultiMeshInstance3D 하나. 모양은 게임 좌표 (z 위) 로 만들고, 놓을 때 게임 → 고도 (core/coords.gd) 로 돌림.
# G1: var n := G3.sprout_node(theme_id) → world 에 add_child, 격자 바뀌면 G3.sprout_update(n, grid, w, d, h, skip, low). 테마에 sprout 없으면 null
extends Node3D

const C := preload("res://core/config.gd")
const BS := preload("res://shaders/block_style.gd")
const FACES := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const GAME_TO_GODOT := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)) # 열 = 게임 x·y·z 축의 고도 방향 (x, z, −y)

var s: Dictionary
var kind: Dictionary # {parts: [{mesh, color: Callable(r) → Color, glow, basic}], tilt, tilt_top, spin, align}
var mms: Array = []


static func _lin_scale(c: int, k: float) -> Color: # three Color.multiplyScalar (선형에서 곱함) → sRGB Color
	var l := Color.hex(c << 8 | 0xff).srgb_to_linear()
	return Color(l.r * k, l.g * k, l.b * k).linear_to_srgb()


static func _lerp_lin(a: int, b: int, t: float) -> Color:
	return Color.hex(a << 8 | 0xff).srgb_to_linear().lerp(Color.hex(b << 8 | 0xff).srgb_to_linear(), t)


# ---- 모양 만들기 (게임 좌표). 고도 기본 도형은 y 위 → x 축 90° 돌려 z 위 (JS zUp)
static func _zup() -> Transform3D:
	return Transform3D(Basis(Vector3(1, 0, 0), PI / 2), Vector3.ZERO)


static func _cyl(r1: float, r2: float, h: float, seg: int) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = r1
	m.bottom_radius = r2
	m.height = h
	m.radial_segments = seg
	m.rings = 0
	return m


static func _ball(r: float, seg: int, rings: int, hemi := false) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r if hemi else r * 2.0
	m.is_hemisphere = hemi
	m.radial_segments = seg
	m.rings = rings
	return m


static func _box(x: float, y: float, z: float) -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, z, y) # 게임 (x, y, z) 상자를 z 위로 세우면 고도 기본 상자는 (x, z높이, y)
	return m


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


static func _rot(x: float, y: float) -> Basis: # three Euler(x, y, 0) 'XYZ'
	return Basis.from_euler(Vector3(x, y, 0.0), EULER_ORDER_XYZ)


static func _merge(list: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for it in list:
		st.append_from(it[0], 0, it[1])
	st.deindex()
	st.set_smooth_group(-1) # 평평한 면 (JS flatShading)
	st.generate_normals()
	return st.commit()


static func _prism(r: float, h: float, tip: float) -> Array: # [[Mesh, Transform3D]]
	return [[_cyl(r, r, h, 6), _t(0, 0, h / 2) * _zup()], [_cyl(0.0, r, tip, 6), _t(0, 0, h + tip / 2) * _zup()]]


static func _place(parts: Array, xf: Transform3D) -> Array:
	var out := []
	for p in parts:
		out.append([p[0], xf * p[1]])
	return out


static func _kind(k: String, st: Dictionary, palette: Array) -> Dictionary:
	var pick := func(r: float) -> Color: return Color.hex(int(palette[int(floor(r * palette.size())) % palette.size()]) << 8 | 0xff)
	var shade: float = st.get("sideShade", 1.0)
	match k:
		"crystal":
			var l := []
			l += _place(_prism(0.09, 0.42, 0.18), _t(0, 0, -0.06))
			l += _place(_prism(0.07, 0.28, 0.13), _t(0.1, 0.03, -0.04) * Transform3D(_rot(0.1, 0.5)))
			l += _place(_prism(0.06, 0.22, 0.11), _t(-0.09, -0.05, -0.04) * Transform3D(_rot(-0.4, -0.35)))
			l += _place(_prism(0.05, 0.16, 0.09), _t(0.0, -0.1, -0.03) * Transform3D(_rot(0.6, 0.0)))
			l += _place(_prism(0.04, 0.12, 0.07), _t(-0.05, 0.1, -0.02) * Transform3D(_rot(-0.2, 0.6)))
			return {"parts": [{"mesh": _merge(l), "color": pick, "glow": 0.4}], "tilt": 0.45, "tilt_top": 0.3, "spin": true}
		"basalt":
			var geo := _merge([[_cyl(0.085, 0.085, 0.26, 6), _t(0, 0, 0.13) * _zup()], [_cyl(0.075, 0.075, 0.18, 6), _t(0.15, 0.02, 0.09) * _zup()], [_cyl(0.07, 0.07, 0.12, 6), _t(0.06, 0.14, 0.06) * _zup()]])
			var lava := _merge([[_ball(0.07, 4, 2), _t(0.08, 0.07, 0.03)], [_ball(0.05, 4, 2), _t(-0.07, 0.05, 0.02)], [_ball(0.045, 4, 2), _t(0.11, -0.07, 0.02)]])
			var top: int = st.top
			var glow: int = st.glow if st.get("glow") != null else 0xff7a24
			return {"parts": [{"mesh": geo, "color": func(r: float) -> Color: return _lin_scale(top, 0.9 + r * 0.35)}, {"mesh": lava, "color": func(_r: float) -> Color: return Color.hex(glow << 8 | 0xff), "basic": true}], "tilt": 0.0, "tilt_top": 0.0, "spin": true}
		"mushroom":
			var cap := _merge([[_ball(0.13, 8, 4, true), _t(0, 0, 0.14) * _zup() * Transform3D(Basis.from_scale(Vector3(1, 0.75, 1)))]])
			var stem := _merge([[_cyl(0.035, 0.045, 0.16, 6), _t(0, 0, 0.08) * _zup()]])
			return {"parts": [{"mesh": cap, "color": pick, "glow": 0.3}, {"mesh": stem, "color": func(_r: float) -> Color: return Color.hex(0xe8dcc0ff)}], "tilt": 1.0, "tilt_top": 0.15, "spin": true}
		"brick":
			var b: Array = st.brick if st.get("brick") != null else [0.62, 0.333]
			var side: int = st.side
			return {"parts": [{"mesh": _merge([[_box(b[0] * 0.9, b[1] * 0.82, 0.12), _t(0, 0, 0.02)]]), "color": func(r: float) -> Color: return _lin_scale(side, (0.72 + r * 0.22) * shade / 0.66)}], "tilt": 0.0, "tilt_top": 0.0, "align": "brick"}
		"rubble":
			var geo := _merge([[_ball(0.16, 5, 3), _t(0, 0.02, 0.02) * Transform3D(Basis.from_scale(Vector3(1.2, 0.9, 0.8)))], [_ball(0.11, 5, 3), _t(0.2, 0.0, 0.08) * Transform3D(Basis.from_scale(Vector3(1, 0.85, 0.8)))], [_ball(0.08, 5, 3), _t(-0.17, 0.02, 0.1)]])
			var a: int = st.side
			var b2: int = st.top
			return {"parts": [{"mesh": geo, "color": func(r: float) -> Color: var c := _lerp_lin(a, b2, 0.3) * (0.88 + r * 0.2); c.a = 1.0; return c.linear_to_srgb()}], "tilt": 0.0, "tilt_top": 0.0, "align": "ground"}
		"ledge":
			var side: int = st.side
			return {"parts": [{"mesh": _merge([[_box(0.8, 0.08, 0.2), _t(0, 0, 0.04)]]), "color": func(r: float) -> Color: return _lin_scale(side, (0.8 + r * 0.15) * shade / 0.66)}], "tilt": 0.0, "tilt_top": 0.0, "align": "ledge"}
	# tuft: 풀 포기
	var blades := []
	for i in 5:
		var a := float(i) / 5.0 * TAU
		blades.append([_cyl(0.0, 0.022, 0.2 - (i % 2) * 0.05, 4), _t(cos(a) * 0.035, sin(a) * 0.035, 0.09) * Transform3D(_rot(sin(a) * 0.4, -cos(a) * 0.4)) * _zup()])
	var top: int = st.top
	return {"parts": [{"mesh": _merge(blades), "color": func(r: float) -> Color: return _lin_scale(top, 0.8 + r * 0.35)}], "tilt": 0.6, "tilt_top": 0.0, "spin": true}


func setup(style: Dictionary, palette: Array, toon: Callable) -> void:
	s = style
	kind = _kind(String(style.sprout.kind), style, palette if palette.size() else [style.get("glow") if style.get("glow") != null else style.top])
	for p in kind.parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = p.mesh
		mm.instance_count = int(C.BLOCK_SPROUT_MAX)
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		if p.get("basic", false):
			var um := StandardMaterial3D.new()
			um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			um.vertex_color_use_as_albedo = true
			mi.material_override = um
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mi.material_override = toon.call(Color.WHITE, {"vertex_color": true, "outline": false, "color_glow": p.get("glow", 0.0)})
			if p.get("glow", 0.0) > 0.0:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200)) # JS frustumCulled = false
		add_child(mi)
		mms.append(mm)


func refresh(grid: PackedByteArray, w: int, d: int, h: int, skip: Dictionary, low: bool) -> void:
	var spots := [] if low else BS.sprout_spots(grid, w, d, h, skip, s.sprout, int(C.BLOCK_SPROUT_MAX))
	var up := Vector3(0, 0, 1)
	var step: float = s.step
	for i in spots.size():
		var p: Dictionary = spots[i]
		var cx: float = p.x + 0.5
		var cy: float = p.y + 0.5
		var lift := (BS.cell_rand(p.x, p.y, p.z, 1) - 0.5) * step
		var pos: Vector3
		var X: Vector3
		var Z: Vector3
		if p.face < 4:
			var nx: int = FACES[p.face][0]
			var ny: int = FACES[p.face][1]
			var n := Vector3(nx, ny, 0)
			var t := Vector3(-ny, nx, 0)
			var u: float = p.u
			var zc: float = p.z + 0.5 + p.v
			if kind.get("align") == "brick" and s.get("brick") != null:
				var bw: float = s.brick[0]
				var bh: float = s.brick[1]
				var base: float = (p.y + 0.5) if p.face < 2 else (p.x + 0.5)
				var sg: float = nx if p.face < 2 else -ny
				var wu: float = base + p.u * sg
				var row: float = floor(zc / bh)
				var id: float = floor(wu / bw + row * 0.5)
				zc = (row + 0.5) * bh
				u = ((id + 0.5 - row * 0.5) * bw - base) * sg
			elif kind.get("align") == "ledge" and s.strata[0] > 0:
				zc = round(zc * s.strata[0]) / s.strata[0]
			elif kind.get("align") == "ground":
				zc = p.z + 0.1
			pos = Vector3(cx, cy, 0) + n * 0.5 + t * u
			pos.z = minf(zc, p.z + 0.9)
			Z = (n * cos(kind.tilt) + up * sin(kind.tilt)).normalized()
			X = t
		else:
			pos = Vector3(cx + p.u, cy + p.v, p.z + 1 + lift)
			var ex: int = FACES[p.edge][0]
			var ey: int = FACES[p.edge][1]
			Z = Vector3(ex * sin(kind.tilt_top), ey * sin(kind.tilt_top), cos(kind.tilt_top)).normalized()
			X = Vector3(-ey, ex, 0)
		X = (X - Z * X.dot(Z)).normalized()
		var Y := Z.cross(X)
		var b := Basis(X, Y, Z)
		if kind.get("spin", false):
			b = b * Basis(Vector3(0, 0, 1), p.spin * TAU)
		b = b.scaled_local(Vector3.ONE * p.s)
		var xf := Transform3D(GAME_TO_GODOT, Vector3.ZERO) * Transform3D(b, pos)
		for k in kind.parts.size():
			mms[k].set_instance_transform(i, xf)
			mms[k].set_instance_color(i, kind.parts[k].color.call(p.spin))
	for mm in mms:
		mm.visible_instance_count = spots.size()
