# 타이틀 무대 도움 (client/title-world.js 의 rng·glowTex·glowSprite·motes·stars·instanced·rockPlane 자리). 모두 게임 좌표 (z 위) — 무대 뿌리가 고도 좌표로 돌림
extends RefCounted

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const MOTES := preload("res://title/motes.gdshader")
const GLOWINST := preload("res://title/glow_inst.gdshader")

static var _glow_tex: Texture2D = null


# 0~1 결정적 난수 (JS rng — mulberry32 꼴, 32비트 정수 연산 그대로)
class Rng:
	var s := 1

	func _init(seed: int) -> void:
		s = seed & 0xffffffff
		if s == 0:
			s = 1

	static func imul(a: int, b: int) -> int:
		a &= 0xffffffff
		b &= 0xffffffff
		var lo := (a & 0xffff) * b
		var hi := ((a >> 16) * b) & 0xffffffff
		return (lo + (hi << 16)) & 0xffffffff

	func next() -> float:
		s = (s + 0x6d2b79f5) & 0xffffffff
		var t := s
		t = imul(t ^ (t >> 15), t | 1)
		t ^= (t + imul(t ^ (t >> 7), t | 61)) & 0xffffffff
		return float((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0


# 테마 이름 → 씨앗 ([...id].reduce((a, ch) => a * 31 + ch.charCodeAt(0), 7) >>> 0)
static func seed_of(id: String) -> int:
	var a := 7.0 # JS 수 (실수) 그대로: 9글자면 2^53 안
	for ch in id:
		a = a * 31.0 + ch.unicode_at(0)
	return int(fmod(a, 4294967296.0))


static func euler(x: float, y: float, z: float) -> Basis:
	return Basis(Vector3.RIGHT, x) * Basis(Vector3.UP, y) * Basis(Vector3.BACK, z) # three Euler 'XYZ' (Rx·Ry·Rz)


# 부드러운 빛 점 텍스처 (가운데 하얗고 가장자리 투명)
static func glow_tex() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_glow_tex = t
	return _glow_tex


# 빛 번짐 판 (더하기 섞기, 카메라를 봄): w×h, 안개 안 받음
static func glow_sprite(color, w: float, h := -1.0, opacity := 1.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_fog = true
	mat.albedo_texture = glow_tex()
	var c := Co.color(color)
	c.a = opacity
	mat.albedo_color = c
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3(w, h if h > 0 else w, 1)
	return m


static func set_opacity(m: MeshInstance3D, a: float) -> void:
	(m.material_override as StandardMaterial3D).albedo_color.a = a


# 떠다니는 빛 가루: n 개, box = [x0, x1, y0, y1, z0, z1], 셰이더가 흔들고 rise 만큼 올림. blink 면 반딧불
static func motes(n: int, color, size: float, rise: float, box: Array, rnd: Rng, blink := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = n
	for i in n:
		var p := Vector3(box[0] + rnd.next() * (box[1] - box[0]), box[2] + rnd.next() * (box[3] - box[2]), box[4] + rnd.next() * (box[5] - box[4]))
		mm.set_instance_transform(i, Transform3D())
		mm.set_instance_custom_data(i, Color(rnd.next(), p.x, p.y, p.z)) # 위상·자리 (셰이더가 움직임)
	var mat := ShaderMaterial.new()
	mat.shader = MOTES
	mat.set_shader_parameter("color", Co.color(color))
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("rise", rise)
	mat.set_shader_parameter("zr", Vector2(box[4], box[5]))
	mat.set_shader_parameter("blink", 1.0 if blink else 0.0)
	mat.set_shader_parameter("move", 1.0)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# 하늘 별 (위쪽 반구, 지름 0.7 점)
static func stars(n: int, rnd: Rng, r := 150.0) -> MultiMeshInstance3D:
	var mi := motes(0, 0xffffff, 0.7, 0.0, [0, 0, 0, 0, 0, 1], rnd)
	var mm := mi.multimesh
	mm.instance_count = n
	for i in n:
		var a := rnd.next() * TAU
		var e := 0.05 + rnd.next() * 1.4
		var p := Vector3(cos(a) * cos(e) * r, absf(sin(a)) * cos(e) * r + 20.0, sin(e) * r * 0.8 - 10.0)
		mm.set_instance_transform(i, Transform3D())
		mm.set_instance_custom_data(i, Color(0.5, p.x, p.y, p.z))
	var mat: ShaderMaterial = mi.material_override
	mat.set_shader_parameter("move", 0.0)
	mat.set_shader_parameter("star", 1.0)
	return mi


# 면마다 법선 (three flatShading): 메시를 풀어 삼각형마다 법선
static func flat(mesh: Mesh) -> ArrayMesh:
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, idx.size(), 3):
		var a := v[idx[i]]
		var b := v[idx[i + 1]]
		var c := v[idx[i + 2]]
		var n := (c - a).cross(b - a).normalized() # 고도 앞면 = 시계 방향
		for p in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(p)
	return st.commit()


# 팔면체 (three OctahedronGeometry(1, 0))
static func octahedron() -> ArrayMesh:
	var v := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var faces := [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 2, 5], [1, 5, 3], [1, 3, 4], [1, 4, 2]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		var n := (b - a).cross(c - a).normalized()
		for p in [a, c, b]: # 고도는 시계 방향이 앞면
			st.set_normal(n)
			st.add_vertex(p)
	return st.commit()


static func cone(r: float, h: float, seg: int) -> CylinderMesh:
	return cyl(0.0, r, h, seg)


static func cyl(top: float, bottom: float, h: float, seg: int, rings := 1, open := false) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = rings
	c.cap_top = not open
	c.cap_bottom = not open
	return c


static func sphere(r: float, seg: int, rings: int, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * (1.0 if hemi else 2.0)
	s.radial_segments = seg
	s.rings = rings
	s.is_hemisphere = hemi
	return s


static func box() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return b


# 울퉁불퉁한 판 (three rockPlane): w×h, seg 칸, amp 높낮이 — 꼭짓점 순서를 three PlaneGeometry 와 같게 (난수 순서), 면 법선
static func rock_plane(w: float, h: float, seg: int, amp: float, rnd: Rng) -> ArrayMesh:
	var sx := seg
	var sy := maxi(2, roundi(seg * h / w))
	var pts := []
	for iy in sy + 1:
		for ix in sx + 1:
			var x := -w / 2 + w * ix / sx
			var y := h / 2 - h * iy / sy
			pts.append(Vector3(x, y, (rnd.next() - 0.5) * amp + sin(x * 0.15) * amp * 0.4))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iy in sy:
		for ix in sx:
			var a: Vector3 = pts[iy * (sx + 1) + ix]
			var b: Vector3 = pts[(iy + 1) * (sx + 1) + ix]
			var c: Vector3 = pts[(iy + 1) * (sx + 1) + ix + 1]
			var d: Vector3 = pts[iy * (sx + 1) + ix + 1]
			for tri in [[a, b, d], [b, c, d]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				for p in [tri[0], tri[2], tri[1]]:
					st.set_normal(n)
					st.add_vertex(p)
	return st.commit()


# 표준 재질 (three MeshStandardMaterial)
static func std(color, rough := 0.9, metal := 0.0, emissive = null, e_energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Co.color(color)
	m.roughness = rough
	m.metallic = metal
	if emissive != null:
		m.emission_enabled = true
		m.emission = Co.color(emissive)
		m.emission_energy_multiplier = e_energy
	return m


# 빛나는 재질: 인스턴스 색 그대로 빛남 (three 'totalEmissiveRadiance *= diffuseColor')
static func glow_inst(glow: float, rough := 0.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOWINST
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("rough", rough)
	return m


static func basic(color, mult := 1.0, fog := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c := Co.color(color)
	m.albedo_color = Color(c.r * mult, c.g * mult, c.b * mult)
	m.disable_fog = not fog
	return m


# 인스턴스 모음: mesh 하나를 [{p: Vector3, s: Vector3, r: Basis?, c: 색?}] 자리마다. geo = 메시에 먼저 붙는 변환 (three geometry.rotateX 등)
static func instanced(mesh: Mesh, mat: Material, list: Array, geo := Transform3D()) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var colored := false
	for it in list:
		if it.has("c"):
			colored = true
	mm.use_colors = colored
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var it: Dictionary = list[i]
		var b: Basis = it.get("r", Basis())
		mm.set_instance_transform(i, Transform3D(b.scaled_local(it.s), it.p) * geo)
		if colored:
			var c = it.get("c", 0xffffff)
			mm.set_instance_color(i, c if c is Color else Co.color(c))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	if colored and mat is StandardMaterial3D:
		mat.vertex_color_use_as_albedo = true
	return mi


static func rot_x(a: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO)
