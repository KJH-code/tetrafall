# 타이틀 전용 어두운 '엔딩 아트' 무대 (client/title-world.js TitleStage 자리, 2026-10-30 재혁): 테마마다 밤·빛·안개 (config TITLE_THEMES)
# 로고는 원점, 글자는 x 로 늘어서고 z 가 위, 카메라는 -y 쪽에서 봄. 이 노드 아래는 전부 게임 좌표 (뿌리 basis 가 고도 좌표로 돌림).
# 재질은 JS 처럼 표준 (PBR) + 점광원 — G3 툰은 전역 빛 값 (판 장면) 을 바꿔서 안 씀. 하늘색·안개·주변광은 env (타이틀 카메라 전용 Environment)
# 빛 세기: three (물리 단위) → 고도 에너지는 LIGHT_K 배 (스샷 비교로 맞춤)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const F := preload("res://title/title_fx.gd")

const TB := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)) # 게임 (x, y, z 위) → 고도 (x, z, -y)
const LIGHT_K := 1.0 / PI # three 점광원 세기 (칸델라, 물리 단위 — 램버트 1/π) → 고도 OmniLight 에너지 (감쇠식은 둘이 같음)
const DIR_K := 1.0 / PI
const AMB_K := 0.5 / PI # 반: JS 스샷의 어두운 실루엣에 맞춤
const CURVE := false # JS 타이틀 (블룸 합성 판) 은 색이 한 번 더 선형으로 바뀌어 어두운 색이 눌림 (배경 #04071a → 검정) — 같은 곡선을 고도 화면 보정으로

var id := ""
var T := {}
var low := false
var floor_z := -4.6
var logo_w := 50.0
var cam_dist := 40.0
var env := Environment.new()
var lights: Array = [] # [빛, 원래 에너지]
var updaters: Array = [] # Callable(t, lit)
var dust: MultiMeshInstance3D
var mote_box = null
var rnd: F.Rng
var ring := false # 대기실 둘레 모드 (B4 lobby_dark): 소품을 가운데 둘레로 돌려 사방에, 가운데 clear 반지름 (섬 자리) 은 비움
var clear := 0.0
var ring_rnd = null # 만드는 동안만 (JS ringNow): 소품마다 돌릴 각
var back_light: OmniLight3D = null # 로고 뒤 빛 (대기실은 B4 가 자리 바꿈)
var mirror_vp: SubViewport = null
var mirror_cam: Camera3D = null
const MIRROR := preload("res://title/mirror.gdshader")
const MIRROR_LAYER := 20


func setup(theme: String, opts := {}) -> void:
	basis = TB
	id = theme if C.TITLE_THEMES.has(theme) else C.TITLE_THEMES.keys()[0]
	T = C.TITLE_THEMES[id]
	low = opts.get("low", false)
	logo_w = float(opts.get("logo_w", opts.get("logoW", 50.0))) # JS 이름 (logoW·logoH·camDist·floorZ) 도 받음
	var logo_h: float = float(opts.get("logo_h", opts.get("logoH", 7.0)))
	cam_dist = float(opts.get("cam_dist", opts.get("camDist", 40.0)))
	ring = bool(opts.get("ring", false))
	clear = float(opts.get("clear", 0.0))
	var fz = opts.get("floor_z", opts.get("floorZ"))
	floor_z = float(fz) if fz != null else -logo_h / 2.0 - C.TITLE_FLOOR_GAP
	rnd = F.Rng.new(F.seed_of(id))
	# 하늘 (단색)·안개·주변광 (three HemisphereLight(amb, bg) 를 반쯤 섞은 색)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Co.color(T.bg).srgb_to_linear() # JS 스샷의 하늘은 설정 색보다 훨씬 어두움 (블룸 합성 판이 배경색을 선형 값 그대로 냄) — 그 모습에 맞춤
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Co.color(T.fog[0])
	env.fog_density = 1.0
	env.fog_depth_begin = cam_dist + T.fog[1]
	env.fog_depth_end = cam_dist + T.fog[2]
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0 # three 안개는 배경색에 안 먹음
	if CURVE:
		env.adjustment_enabled = true
		env.adjustment_color_correction = _curve()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Co.color(T.amb[0]).lerp(Co.color(T.bg), 0.5)
	env.ambient_light_energy = float(T.amb[1]) * AMB_K
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var key := point(T.key[0], T.key[1] * C.TITLE_LIGHT[0], 0.0, 1.4, Vector3(-logo_w * 0.25, -cam_dist * 0.55, 10))
	back_light = point(T.back[0], T.back[1] * C.TITLE_LIGHT[1], 0.0, 1.3, Vector3(0, 9, 3))
	_floor()
	ring_rnd = F.Rng.new(99) if ring else null
	if has_method("_" + id):
		call("_" + id)
	ring_rnd = null
	var n := roundi(float(T.motes[1]) * (C.WORLD_LOW_DETAIL if low else 1.0))
	var box: Array = mote_box if mote_box != null else [-logo_w * 0.9, logo_w * 0.9, -cam_dist * 0.6, 40.0, floor_z, floor_z + 18.0]
	if ring:
		box = [-clear * 2, clear * 2, -clear * 2, clear * 2, box[4], box[5]] # 대기실: 섬 둘레
	dust = F.motes(n, T.motes[0], T.motes[2], T.motes[3], box, rnd, id == "meadow")
	add_child(dust)


# 화면 보정 곡선: x → srgb_to_linear(x) (JS 합성 판 색 그대로)
static func _curve() -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in 33:
		var x := i / 32.0
		var y := Color(x, x, x).srgb_to_linear().r
		offs.append(x)
		cols.append(Color(y, y, y))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


# 점광원 (three PointLight(color, intensity, distance, decay))
func point(color, intensity: float, distance: float, decay: float, at: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = Co.color(color)
	l.omni_range = distance if distance > 0.0 else 400.0
	l.omni_attenuation = decay
	l.position = at
	l.shadow_enabled = false
	add_child(l)
	lights.append([l, intensity * LIGHT_K])
	l.light_energy = intensity * LIGHT_K
	return l


func dir_light(color, intensity: float, at: Vector3) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.light_color = Co.color(color)
	add_child(l)
	l.basis = Basis.looking_at(-at.normalized(), Vector3(0, 0, 1)) # 무대 로컬 (게임 좌표): 그 자리에서 원점 쪽으로
	lights.append([l, intensity * DIR_K])
	return l


# 빛 하나 더 (JS light(l, base) — 대기실이 0 세기 빛을 채울 때). l 은 무대 좌표
func light(l: Light3D, base: float) -> Light3D:
	if l.get_parent() == null:
		add_child(l)
	lights.append([l, base])
	return l


# 인스턴스 모음 (F.instanced) + 대기실 둘레 모드: 가운데 clear 안 소품은 빼고, 남은 것은 가운데 축으로 무작위로 돌림 (JS instanced ringNow)
func _inst(m: Mesh, mat: Material, list: Array, geo := Transform3D()) -> MultiMeshInstance3D:
	if ring_rnd != null:
		var keep := []
		for it in list:
			if Vector2(it.p.x, it.p.y).length() >= clear:
				keep.append(it)
		for it in keep:
			var a: float = ring_rnd.next() * TAU
			it.p = Vector3(it.p.x * cos(a) - it.p.y * sin(a), it.p.x * sin(a) + it.p.y * cos(a), it.p.z)
			if it.has("r"):
				it.r = it.r * Basis(Vector3.BACK, a) # Euler z + a (three 'XYZ' = Rx·Ry·Rz)
		list = keep
	return F.instanced(m, mat, list, geo)


# 울퉁불퉁한 원통 벽 (안쪽을 봄, JS rockRing): 반지름 r, 높이 h, 밑 z0
func _rock_ring(r: float, h: float, color, z0: float) -> void:
	var cm := F.cyl(r, r * 1.1, h, 48, 8, true)
	var arr := cm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var k := 1.0 + (rnd.next() - 0.5) * 0.12
		v[i] = Vector3(v[i].x * k, v[i].y, v[i].z * k) # 원통 축 = 로컬 y (나중에 x 로 90도 돌려 z 위)
	arr[Mesh.ARRAY_VERTEX] = v
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := F.std(color, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_FRONT # 안쪽 (BackSide)
	mesh(F.flat(am), mat, Vector3(0, 0, z0 + h / 2), F.rot_x(PI / 2))


func put(n: Node3D, at := Vector3.ZERO) -> Node3D:
	n.position = at
	add_child(n)
	return n


func mesh(m: Mesh, mat: Material, at := Vector3.ZERO, geo := Transform3D()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.transform = Transform3D(Basis(), at) * geo
	add_child(mi)
	return mi


# 바닥: 보통이면 거울 (반사 카메라 SubViewport, 테마 바닥 색으로 흐리게) + 그 위 반투명 바닥 판. 거울 없는 테마 (mirror: false) 는 테마가 바닥을 만듦
# 거울·바닥 판은 MIRROR_LAYER 에 둬서 반사 카메라가 안 그림
func _floor() -> void:
	if T.get("mirror", true) == false:
		return
	var p := PlaneMesh.new()
	p.size = Vector2(400, 400)
	p.orientation = PlaneMesh.FACE_Z
	if not low:
		mirror_vp = SubViewport.new()
		mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		mirror_vp.size = Vector2i(640, 360)
		mirror_cam = Camera3D.new()
		mirror_cam.cull_mask = 0xfffff & ~(1 << (MIRROR_LAYER - 1))
		if not ring:
			mirror_cam.environment = env # 대기실은 판 장면 Environment 그대로
		mirror_vp.add_child(mirror_cam)
		add_child(mirror_vp)
		var mm := ShaderMaterial.new()
		mm.shader = MIRROR
		mm.set_shader_parameter("refl", mirror_vp.get_texture())
		mm.set_shader_parameter("tint", Co.color(T.floor).lerp(Color.WHITE, C.TITLE_REFLECT))
		var m := mesh(p, mm, Vector3(0, 0, floor_z - 0.02))
		m.layers = 1 << (MIRROR_LAYER - 1)
	var over := F.std(T.floor, 0.9)
	if not low:
		over.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		over.albedo_color.a = 0.62
	var o := mesh(p, over, Vector3(0, 0, floor_z))
	o.layers = 1 << (MIRROR_LAYER - 1)


# 거울 카메라: 보는 카메라를 바닥 면에 비춘 자리·방향 (좌우는 셰이더가 뒤집음). 화면 크기의 반
func mirror_update(cam: Camera3D) -> void:
	if mirror_cam == null:
		return
	var vp := cam.get_viewport().get_visible_rect().size
	var want := Vector2i(maxi(1, int(vp.x * 0.5)), maxi(1, int(vp.y * 0.5)))
	if mirror_vp.size != want:
		mirror_vp.size = want
	var fy := (global_transform * Vector3(0, 0, floor_z)).y # 바닥 면 높이 (고도 y)
	var g := cam.global_transform
	var refl := func(v: Vector3) -> Vector3: return Vector3(v.x, -v.y, v.z)
	var pos := g.origin
	pos.y = 2.0 * fy - pos.y
	var b := Basis(-refl.call(g.basis.x), refl.call(g.basis.y), refl.call(g.basis.z)) # 비추면 손잡이가 바뀜 → x 를 뒤집어 바른 회전 (화면 좌우는 셰이더가)
	mirror_cam.global_transform = Transform3D(b, pos)
	mirror_cam.fov = cam.fov
	mirror_cam.near = cam.near
	mirror_cam.far = cam.far


# ===== 테마별 소품 (title-world.js 그대로, 난수 순서도 같게) =====

func _crystal() -> void:
	var ceil_z := 13.0
	var rock := F.std(T.rock, 0.95)
	var ceil := mesh(F.rock_plane(260, 160, 60, 3.5, rnd), rock, Vector3(0, 0 if ring else 40, ceil_z))
	ceil.basis = Basis(Vector3.RIGHT, PI) # 아래를 봄
	if ring:
		ceil.basis = ceil.basis.scaled_local(Vector3(1.2, 1.9, 1)) # 대기실: 머리 위 전체
		_rock_ring(clear * 2.6, ceil_z - floor_z + 6, T.rock, floor_z - 3)
	else:
		var wall := mesh(F.rock_plane(260, 60, 50, 5, rnd), rock, Vector3(0, 75, ceil_z - 25))
		wall.basis = Basis(Vector3.RIGHT, PI / 2)
	var st := []
	for i in 30 if low else 70:
		var x := (rnd.next() - 0.5) * 180
		var y := -30 + rnd.next() * 100
		var h := 2 + rnd.next() * 6
		if absf(x) < logo_w * 0.6 and y < 10:
			continue
		st.append({"p": Vector3(x, y, ceil_z - h / 2), "s": Vector3(0.6 + rnd.next() * 1.4, 0.6 + rnd.next() * 1.4, h), "r": F.euler(-PI / 2, 0, 0)})
	add_child(_inst(F.flat(F.cone(1, 1, 5)), F.std(T.rock, 1.0), st, F.rot_x(-PI / 2)))
	var cr := []
	for i in 10 if low else 22:
		var x := (rnd.next() - 0.5) * 160
		var y := -20 + rnd.next() * 90
		if absf(x) < logo_w * 0.6 and y < 18:
			continue
		_crystal_cluster(cr, Vector3(x, y, ceil_z - 0.5), -1, 1.5 + rnd.next() * 2.5, T.crystals)
	for i in 14 if low else 34:
		var x := (rnd.next() - 0.5) * 170
		var y := -26 + rnd.next() * 100
		if absf(x) < logo_w * 0.55 and y < 6:
			continue
		_crystal_cluster(cr, Vector3(x, y, floor_z), 1, 1.2 + rnd.next() * (4.0 if y > 20 else 2.2), T.crystals)
	add_child(_inst(F.octahedron(), F.glow_inst(0.5, 0.25), cr))
	for i in 3:
		point(T.crystals[i % T.crystals.size()], C.TITLE_LIGHT[2], 50, 1.6, Vector3((i - 1) * 40, 18 + rnd.next() * 20, floor_z + 3))
	var rocks := []
	for i in 26:
		var x := (rnd.next() - 0.5) * 150
		var y := -24 + rnd.next() * 80
		if absf(x) < logo_w * 0.5 and y < 8:
			continue
		var s := 0.8 + rnd.next() * 2.2
		rocks.append({"p": Vector3(x, y, floor_z + s * 0.3), "s": Vector3(s, s * (0.7 + rnd.next() * 0.5), s * 0.7), "r": F.euler(rnd.next(), rnd.next(), rnd.next())})
	add_child(_inst(F.flat(F.sphere(1, 5, 3)), F.std(T.rock, 1.0), rocks))
	mote_box = [-90, 90, -30, 60, floor_z, ceil_z]


func _crystal_cluster(list: Array, at: Vector3, dir: float, size: float, colors: Array) -> void:
	var n := 3 + floori(rnd.next() * 5)
	for i in n:
		var h := size * (0.6 + rnd.next() * 1.0) * (1.5 if i == 0 else 1.0)
		var r := h * (0.18 + rnd.next() * 0.1)
		var tilt := 0.0 if i == 0 else 0.25 + rnd.next() * 0.6
		var a := rnd.next() * TAU
		var k := 1.0 if i else 0.0
		var p := at + Vector3(cos(a) * size * 0.3 * k, sin(a) * size * 0.3 * k, dir * h * 0.35)
		var e := F.euler(cos(a) * tilt * dir, sin(a) * tilt * dir, rnd.next() * PI)
		list.append({"p": p, "s": Vector3(r, r, h), "r": e, "c": colors[floori(rnd.next() * colors.size())]})


func _volcano() -> void:
	var seg := []
	for k in 10 if low else 22:
		var x := (rnd.next() - 0.5) * 160
		var y := -24 + rnd.next() * 90
		var a := rnd.next() * TAU
		var s := 0
		while s < 8 + rnd.next() * 10:
			var len := 1.5 + rnd.next() * 3
			a += (rnd.next() - 0.5) * 1.2
			var nx := x + cos(a) * len
			var ny := y + sin(a) * len
			seg.append({"p": Vector3((x + nx) / 2, (y + ny) / 2, floor_z + 0.03), "s": Vector3(len, 0.12 + rnd.next() * 0.3, 0.06), "r": F.euler(0, 0, a)})
			x = nx
			y = ny
			s += 1
	var lava := F.basic(T.lava, 2.2)
	add_child(_inst(F.box(), lava, seg))
	var cone_mat := F.std(T.rock, 1.0)
	for c in [[-45, 95, 34, 34], [55, 110, 42, 44], [5, 130, 30, 26]]:
		mesh(F.flat(F.cyl(c[2] * 0.15, c[2], c[3], 9, 3)), cone_mat, Vector3(c[0], c[1], floor_z + c[3] / 2.0), F.rot_x(PI / 2))
		put(F.glow_sprite(T.lava, c[2] * 1.2, c[2] * 0.6, 0.9), Vector3(c[0], c[1], floor_z + c[3] + 2))
	put(F.glow_sprite(0xff3a08, 260, 70, 0.35), Vector3(0, 140, 20))
	for i in 2:
		point(T.lava, 80, 60, 1.5, Vector3(30 if i else -30, 15, floor_z + 1.5))
	var base := Co.color(T.lava)
	updaters.append(func(t, _lit): lava.albedo_color = base * (1.9 + 0.5 * sin(t * 1.7)))
	var rocks := []
	for i in 24:
		var x := (rnd.next() - 0.5) * 160
		var y := -24 + rnd.next() * 80
		if absf(x) < logo_w * 0.5 and y < 8:
			continue
		var s := 1 + rnd.next() * 2.5
		rocks.append({"p": Vector3(x, y, floor_z + s * 0.2), "s": Vector3(s, s, s * 0.8), "r": F.euler(rnd.next(), rnd.next(), rnd.next())})
	add_child(_inst(F.flat(F.sphere(1, 5, 3)), cone_mat, rocks))
	mote_box = [-90, 90, -20, 70, floor_z, floor_z + 30]


func _moon(r: float, at: Vector3, glow_w: float, glow_a: float) -> void:
	mesh(F.sphere(r, 24, 16), F.basic(T.moon, 1.0, false), at)
	put(F.glow_sprite(T.moon, glow_w, glow_w, glow_a), at)


func _desert() -> void:
	add_child(F.stars(500 if low else 1400, rnd, 150.0, ring))
	_moon(6, Vector3(-60, 130, 48), 50, 0.22)
	var sand := F.std(T.sand, 1.0)
	var p := PlaneMesh.new()
	p.size = Vector2(400, 400)
	p.orientation = PlaneMesh.FACE_Z
	mesh(p, sand, Vector3(0, 0, floor_z))
	var dunes := []
	for i in 14:
		dunes.append({"p": Vector3((rnd.next() - 0.5) * 220, 20 + rnd.next() * 110, floor_z - 2), "s": Vector3(30 + rnd.next() * 30, 14 + rnd.next() * 14, 4 + rnd.next() * 5), "r": F.euler(0, 0, rnd.next() * 3)})
	add_child(_inst(F.sphere(1, 20, 10), sand, dunes))
	var pyr := F.std(T.stone, 0.9)
	var geo := Transform3D(Basis(Vector3.BACK, PI / 4) * Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO) # rotateX(PI/2) 다음 rotateZ(PI/4)
	for q in [[-38, 70, 26], [28, 95, 36], [75, 60, 16]]:
		var s: float = q[2]
		mesh(F.flat(F.cone(s, s * 0.9, 4)), pyr, Vector3(q[0], q[1], floor_z + s * 0.45), geo)
		var at := Vector3(q[0], q[1], floor_z + s * 0.9 - s * 0.05)
		mesh(F.flat(F.cone(s * 0.12, s * 0.11, 4)), F.basic(T.cap, 2.0), at, geo)
		put(F.glow_sprite(T.cap, s * 0.9, s * 0.9, 0.7), at)
	mote_box = [-90, 90, -30, 60, floor_z, floor_z + 6]


func _mushroom() -> void:
	var stem := F.std(T.stem, 0.9, 0.0, T.stem, 0.25)
	var stems := []
	var caps := []
	var spots := []
	var big := []
	for i in 14 if low else 30:
		var x := (rnd.next() - 0.5) * 170
		var y := -22 + rnd.next() * 110
		if absf(x) < logo_w * 0.55 and y < 8:
			continue
		var h := (6.0 if y > 15 else 2.0) + rnd.next() * (16.0 if y > 15 else 4.0)
		var r := h * (0.45 + rnd.next() * 0.25)
		var lean := (rnd.next() - 0.5) * 0.3
		stems.append({"p": Vector3(x, y, floor_z + h / 2), "s": Vector3(h * 0.09, h * 0.09, h), "r": F.euler(lean, 0, 0)})
		var c = T.caps[floori(rnd.next() * T.caps.size())]
		caps.append({"p": Vector3(x, y - lean * h * 0.5, floor_z + h), "s": Vector3(r, r, r * 0.55), "c": c})
		for k in 5:
			var a := rnd.next() * TAU
			var e := 0.3 + rnd.next() * 0.9
			spots.append({"p": Vector3(x + cos(a) * cos(e) * r, y - lean * h * 0.5 + sin(a) * cos(e) * r, floor_z + h + sin(e) * r * 0.55), "s": Vector3(r * 0.09, r * 0.09, r * 0.05)})
		if h > 14 and big.size() < 3:
			big.append([x, y, h, c])
	add_child(_inst(F.cyl(0.7, 1, 1, 8), stem, stems, F.rot_x(PI / 2)))
	add_child(_inst(F.sphere(1, 20, 10, true), F.glow_inst(0.9, 0.5), caps, F.rot_x(PI / 2)))
	add_child(_inst(F.sphere(1, 8, 6), F.basic(0xffffff), spots))
	for b in big:
		point(b[3], 90, 40, 1.5, Vector3(b[0], b[1], floor_z + b[2] - 1))
	mote_box = [-90, 90, -25, 70, floor_z, floor_z + 20]


func _skycastle() -> void:
	add_child(F.stars(500 if low else 1400, rnd, 150.0, ring))
	_moon(8, Vector3(55, 140, 55), 60, 0.2)
	dir_light(T.moon, 1.4, Vector3(55, 140, 55))
	var cloud := F.std(T.cloud, 1.0, 0.0, T.cloud, 0.15)
	var cl := []
	for i in 120 if low else 260:
		var x := (rnd.next() - 0.5) * 300
		var y := -40 + rnd.next() * 200
		var s := 5 + rnd.next() * 9
		cl.append({"p": Vector3(x, y, floor_z - 1 - s * 0.45 + rnd.next() * 0.8), "s": Vector3(s * 1.6, s, s * 0.45)})
	add_child(_inst(F.sphere(1, 14, 8), cloud, cl))
	var wall := F.std(T.wall, 0.9)
	var roof := F.std(T.roof, 0.8)
	var wins := []
	for cs in [[-30, 85, 1.4], [48, 120, 1.1], [-80, 130, 0.9]]:
		var cx: float = cs[0]
		var cy: float = cs[1]
		var k: float = cs[2]
		for tw in [[-8, 0, 3, 22], [8, 0, 3, 22], [0, 4, 4, 32], [-14, 6, 2.2, 16], [14, 6, 2.2, 16]]:
			var r: float = tw[2]
			var h: float = tw[3]
			mesh(F.flat(F.cyl(r * k, r * k, h * k, 10)), wall, Vector3(cx + tw[0] * k, cy + tw[1] * k, floor_z + h * k / 2 - 2), F.rot_x(PI / 2))
			mesh(F.flat(F.cone(r * k * 1.3, r * k * 2.6, 10)), roof, Vector3(cx + tw[0] * k, cy + tw[1] * k, floor_z + h * k - 2 + r * k * 1.3), F.rot_x(PI / 2))
			for j in 3:
				wins.append({"p": Vector3(cx + tw[0] * k, cy + tw[1] * k - r * k - 0.05, floor_z - 2 + h * k * (0.35 + j * 0.2)), "s": Vector3(0.6 * k, 0.2, 1.1 * k)})
		var b := BoxMesh.new()
		b.size = Vector3(16 * k, 3 * k, 10 * k)
		mesh(b, wall, Vector3(cx, cy, floor_z + 5 * k - 2))
	add_child(_inst(F.box(), F.basic(T.window, 1.6), wins))
	mote_box = [-90, 90, -30, 80, floor_z, floor_z + 25]


func _brick_tex() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var base := Co.color(T.wall)
	img.fill(base * 0.5)
	for row in 8:
		for col in range(-1, 4):
			var v := 0.75 + rnd.next() * 0.5
			var c := Color(minf(1, base.r * v), minf(1, base.g * v), minf(1, base.b * v))
			var r := Rect2i(col * 40 + (row % 2) * 20 + 2, row * 16 + 2, 36, 12).intersection(Rect2i(0, 0, 128, 128))
			if r.has_area():
				img.fill_rect(r, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _castle() -> void:
	var tex := _brick_tex()
	var wall_mat := F.std(0xffffff, 0.95)
	wall_mat.albedo_texture = tex
	wall_mat.uv1_scale = Vector3(30 * 3, 5 * 2, 1) # three repeat (30, 5) × 고도 BoxMesh 면 3×2 나눔
	var wall_y := 22.0
	var wall_h := 24.0
	var tm := F.std(T.wall, 1.0)
	var tower_mat := F.std(0xffffff, 0.95)
	tower_mat.albedo_texture = tex
	tower_mat.uv1_scale = Vector3(30, 5, 1)
	var spots := []
	if ring:
		# 대기실: 섬 둘레 둥근 성벽 (마당 안), 톱니·탑 넷, 횃불 여덟
		var R := clear * 1.5
		var rw := F.std(0xffffff, 0.95)
		rw.albedo_texture = tex
		rw.uv1_scale = Vector3(40, 5, 1)
		rw.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh(F.cyl(R, R, wall_h, 64, 1, true), rw, Vector3(0, 0, floor_z + wall_h / 2), F.rot_x(PI / 2))
		var cren := []
		var nc := roundi(TAU * R / 5.0)
		for k in nc:
			var a := float(k) / nc * TAU
			cren.append({"p": Vector3(cos(a) * R, sin(a) * R, floor_z + wall_h + 1.2), "s": Vector3(6, 2.6, 2.4), "r": F.euler(0, 0, a)})
		add_child(F.instanced(F.box(), tm, cren)) # 성벽 톱니는 제자리 (흩뿌리지 않음)
		for k in 4:
			var a := PI / 4 + k * PI / 2
			mesh(F.cyl(7, 7, wall_h + 14, 12), tower_mat, Vector3(cos(a) * R, sin(a) * R, floor_z + (wall_h + 14) / 2), F.rot_x(PI / 2))
		for k in 8:
			var a := float(k) / 8.0 * TAU
			spots.append([cos(a) * (R - 3.3), sin(a) * (R - 3.3), a])
	else:
		var b := BoxMesh.new()
		b.size = Vector3(220, 6, wall_h)
		mesh(b, wall_mat, Vector3(0, wall_y, floor_z + wall_h / 2))
		var cren := []
		var x := -108
		while x <= 108:
			cren.append({"p": Vector3(x, wall_y, floor_z + wall_h + 1.2), "s": Vector3(2.6, 6, 2.4)})
			x += 5
		add_child(_inst(F.box(), tm, cren))
		for tx in [-62, 62]:
			mesh(F.cyl(8, 8, wall_h + 14, 12), tower_mat, Vector3(tx, wall_y - 3, floor_z + (wall_h + 14) / 2), F.rot_x(PI / 2))
		spots = [-48, -32, -16, 16, 32, 48].map(func(sx): return [sx, wall_y - 3.3, PI / 2])
	var flames := []
	var stick_mat := F.std(0x2a1a10, 1.0)
	for i in spots.size():
		var sp: Array = spots[i]
		var z := floor_z + 7
		mesh(F.cyl(0.25, 0.18, 2.2, 6), stick_mat, Vector3(sp[0], sp[1], z), F.rot_x(PI / 2))
		var at := Vector3(sp[0] - cos(sp[2]) * 0.1, sp[1] - sin(sp[2]) * 0.1, z + 1.8)
		var f := put(F.glow_sprite(T.torch, 3.2, 4.4, 1.0), at)
		var core := put(F.glow_sprite(0xffe2a0, 1.4, 2, 1.0), at)
		var halo := put(F.glow_sprite(T.torch, 16, 16, 0.35), at)
		var fl := [f, core, halo, rnd.next() * 10, null]
		if (i % 3 == 0) if ring else (not low or i % 2 == 0): # 대기실은 3개만
			fl[4] = point(T.torch, 45, 30, 1.6, Vector3(sp[0] - cos(sp[2]) * 1.7, sp[1] - sin(sp[2]) * 1.7, z + 2))
		flames.append(fl)
	updaters.append(func(t, _lit):
		for fl in flames:
			var ph: float = fl[3]
			var k := 0.85 + 0.15 * sin(t * 13 + ph) * sin(t * 7.3 + ph * 2)
			fl[0].scale = Vector3(3.2 * k, 4.4 * (0.9 + 0.2 * sin(t * 11 + ph)), 1)
			fl[1].scale = Vector3(1.4 * k, 2 * k, 1)
			F.set_opacity(fl[2], 0.3 * k)
			if fl[4] != null:
				fl[4].set_meta("flicker", k))
	mote_box = [-80, 80, -20, 20, floor_z, floor_z + 26]


func _meadow() -> void:
	add_child(F.stars(600 if low else 1600, rnd, 150.0, ring))
	_moon(5, Vector3(60, 130, 45), 45, 0.2)
	dir_light(T.moon, 0.3, Vector3(60, 130, 45))
	mesh(F.rock_plane(400, 400, 50, 1.2, rnd), F.std(T.grass, 0.95), Vector3(0, 0, floor_z - 0.3))
	var blades := []
	for i in 900 if low else 2600:
		var x := (rnd.next() - 0.5) * 180
		var y := -30 + rnd.next() * 100
		if absf(x) < logo_w * 0.5 and y > -12 and y < 4:
			continue
		var h := 0.6 + rnd.next() * 1.4
		var g := Co.color(T.grass) * (0.8 + rnd.next() * 0.8)
		blades.append({"p": Vector3(x, y, floor_z + h / 2 - 0.1), "s": Vector3(0.12, 0.12, h), "r": F.euler((rnd.next() - 0.5) * 0.5, (rnd.next() - 0.5) * 0.5, 0), "c": g})
	add_child(_inst(F.cone(1, 1, 3), F.std(0xffffff, 1.0), blades, F.rot_x(PI / 2)))
	var tm := F.std(T.tree, 1.0)
	var cones := []
	for i in 40:
		var x := (rnd.next() - 0.5) * 240
		var y := 35 + rnd.next() * 100
		var h := 10 + rnd.next() * 16
		for k in 3:
			cones.append({"p": Vector3(x, y, floor_z + h * (0.35 + k * 0.22)), "s": Vector3(h * (0.32 - k * 0.07), h * (0.32 - k * 0.07), h * 0.45)})
	add_child(_inst(F.flat(F.cone(1, 1, 7)), tm, cones, F.rot_x(PI / 2)))
	mote_box = [-80, 80, -30, 50, floor_z + 0.3, floor_z + 9]


# 매 프레임: t 초, lit 장면 밝기 0~1, px (JS 점 크기 — 고도는 지금 카메라 시야각으로 빛 가루 크기를 정해서 안 씀). 거울 카메라도 지금 카메라 따라
func update(t: float, lit: float, _px := 0.0) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var fov: float = cam.fov if cam != null else float(C.TITLE_FOV)
	if cam != null:
		mirror_update(cam)
	for pair in lights:
		var l: Light3D = pair[0]
		l.light_energy = pair[1] * lit * float(l.get_meta("flicker", 1.0))
	var m: ShaderMaterial = dust.material_override
	m.set_shader_parameter("time", t)
	m.set_shader_parameter("lit", 0.3 + 0.7 * lit)
	m.set_shader_parameter("tan_half", tan(deg_to_rad(fov) / 2.0))
	for f in updaters:
		f.call(t, lit)
	for c in get_children():
		if c is MultiMeshInstance3D and c != dust and c.material_override is ShaderMaterial and c.material_override.shader == F.MOTES:
			c.material_override.set_shader_parameter("tan_half", tan(deg_to_rad(fov) / 2.0))
