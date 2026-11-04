# 타격감 이펙트 (client/effects.js 자리): 파편 (MultiMesh 하나, 칸마다 색·투명도) · 충격파 고리 · 화면 흔들림 · 찌그러짐·팔 뻗음 타이머.
# W18 덧칠 (JS 에 없음, 수치 fx/fx_config.gd): 빛 (번쩍·불꽃 줄·빛 고리·불덩이 — 가산 MultiMesh 하나) · 연기·먼지 (MultiMesh 하나) ·
#   돌·흙 조각 (MultiMesh 하나, 한 번 튀고 멈춤) · 카메라 반동·시야 조임 · 1인칭 팔 반동 · 화면 히트스톱 시각.
#   종류마다 MultiMesh 하나 → 효과가 아무리 겹쳐도 그리기는 종류 수만큼 (비면 안 그림). 화질 낮음이면 덧칠 없이 JS 모습만 (lv)
# 부르는 쪽은 게임 좌표 (z 위). 시각은 ms (Time.get_ticks_msec), 화면 dt 는 KO 슬로모션 배율이 곱해져 들어옴
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const FM := preload("res://fx/fx_math.gd")
const FXC := preload("res://fx/fx_config.gd")
const GLOW_SHADER := preload("res://shaders/fx_glow.gdshader")
const SMOKE_SHADER := preload("res://shaders/fx_smoke.gdshader")

const MAX_PARTICLES := 160
const MAX_RINGS := FXC.MAX_RINGS
const MAX_GLOW := FXC.MAX_GLOW
const MAX_SMOKE := FXC.MAX_SMOKE
const MAX_CHUNKS := FXC.MAX_CHUNKS
const GRAVITY := 14.0
# 빛 모양 (fx_glow.gdshader CUSTOM.x)
const ROUND := 0
const STAR := 1
const SHOCK := 2
const STREAK := 3

var mm := MultiMesh.new()
var mmi := MultiMeshInstance3D.new()
# 파편 자리 (게임 좌표): 살아 있는 것만 MultiMesh 에 옮김
var p_pos: Array[Vector3] = []
var p_vel: Array[Vector3] = []
var p_rot: Array[Vector2] = []
var p_life := PackedFloat64Array()
var p_max := PackedFloat64Array()
var p_size := PackedFloat64Array()
var p_color: Array[Color] = []
var pi := 0
# 충격파 고리 (JS effects.js rings): MultiMesh 하나 (예전 MeshInstance 12개)
var ring_mm := MultiMesh.new()
var ring_mmi := MultiMeshInstance3D.new()
var ring_mat: StandardMaterial3D
var r_pos: Array[Vector3] = []
var r_color: Array[Color] = []
var r_life := PackedFloat64Array()
var r_max := PackedFloat64Array()
var r_grow := PackedFloat64Array()
var r_flat := PackedByteArray()
var ri := 0
# W18 빛
var glow_mm := MultiMesh.new()
var glow_mmi := MultiMeshInstance3D.new()
var glow_mat := ShaderMaterial.new()
var g_pos: Array[Vector3] = []
var g_vel: Array[Vector3] = []
var g_color: Array[Color] = []
var g_life := PackedFloat64Array()
var g_max := PackedFloat64Array()
var g_s0 := PackedFloat64Array()
var g_s1 := PackedFloat64Array()
var g_pow := PackedFloat64Array()
var g_grav := PackedFloat64Array()
var g_rot := PackedFloat64Array()
var g_hot := PackedFloat64Array()
var g_kind := PackedByteArray()
var g_flat := PackedByteArray()
var gi := 0
# W18 연기
var smoke_mm := MultiMesh.new()
var smoke_mmi := MultiMeshInstance3D.new()
var smoke_mat := ShaderMaterial.new()
var s_pos: Array[Vector3] = []
var s_vel: Array[Vector3] = []
var s_color: Array[Color] = []
var s_life := PackedFloat64Array()
var s_max := PackedFloat64Array()
var s_s0 := PackedFloat64Array()
var s_s1 := PackedFloat64Array()
var s_rot := PackedFloat64Array()
var s_spin := PackedFloat64Array()
var s_seed := PackedFloat64Array()
var si := 0
# W18 돌·흙 조각
var chunk_mm := MultiMesh.new()
var chunk_mmi := MultiMeshInstance3D.new()
var c_pos: Array[Vector3] = []
var c_vel: Array[Vector3] = []
var c_rot: Array[Vector3] = []
var c_spin: Array[Vector3] = []
var c_color: Array[Color] = []
var c_life := PackedFloat64Array()
var c_max := PackedFloat64Array()
var c_size := PackedFloat64Array()
var c_bounced := PackedByteArray()
var ci := 0
var solid := func(_x: float, _y: float, z: float) -> bool: return z < 0.0 # 조각이 닿는 땅 (fx.gd 가 world.solid_at 로 바꿈)

var sh := {"amp": 0.0, "ms": 1.0, "until": 0.0}
var squash_t := {} # 플레이어 id -> 맞은 시각 (ms)
var punch_t := {} # 플레이어 id -> 팔 뻗기 시작 (ms)
var cam: Camera3D = null # 고리가 바라볼 카메라 (update 때 받음)
# W18 화면 쪽
var lv: Dictionary = FXC.LEVELS.medium # 덧칠 수준 (fx.gd 가 화질로 정함)
var reduced := false # 움직임 줄이기
var stop_until := 0.0 # 화면 히트스톱 끝 (ms)
var kick := {"t0": -1e9, "ms": 1.0, "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "fov": 0.0} # 카메라 반동 (도)
var vm := {"t0": -1e9, "ms": 1.0, "off": Vector3.ZERO} # 1인칭 팔 반동 (카메라 좌표 칸)


static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


static func _pool_mmi(m: MultiMeshInstance3D, mmesh: MultiMesh, mesh: Mesh, n: int, custom: bool) -> void:
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.use_colors = true
	mmesh.use_custom_data = custom
	mmesh.mesh = mesh
	mmesh.instance_count = n
	mmesh.visible_instance_count = 0
	m.multimesh = mmesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.extra_cull_margin = 16384.0 # 효과는 필드 어디든 (frustumCulled false 자리)
	m.visible = false


func _init() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	FM.near_fade(mat) # 카메라 바로 앞이면 흐려짐 (화면을 덮지 않게)
	box.material = mat
	_pool_mmi(mmi, mm, box, MAX_PARTICLES, false)
	add_child(mmi)
	for i in MAX_PARTICLES:
		p_pos.append(Vector3.ZERO)
		p_vel.append(Vector3.ZERO)
		p_rot.append(Vector2.ZERO)
		p_color.append(Color.WHITE)
	p_life.resize(MAX_PARTICLES)
	p_max.resize(MAX_PARTICLES)
	p_size.resize(MAX_PARTICLES)
	p_max.fill(1.0)
	# 고리
	var rmesh := ring_mesh(0.8, 1.0, 40)
	ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ring_mat.vertex_color_use_as_albedo = true
	FM.near_fade(ring_mat)
	rmesh.surface_set_material(0, ring_mat)
	_pool_mmi(ring_mmi, ring_mm, rmesh, MAX_RINGS, false)
	add_child(ring_mmi)
	for i in MAX_RINGS:
		r_pos.append(Vector3.ZERO)
		r_color.append(Color.WHITE)
	r_life.resize(MAX_RINGS)
	r_max.resize(MAX_RINGS)
	r_max.fill(1.0)
	r_grow.resize(MAX_RINGS)
	r_flat.resize(MAX_RINGS)
	# 빛 (가산)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	glow_mat.shader = GLOW_SHADER
	glow_mat.render_priority = 1 # 연기 뒤에 (불덩이가 연기 위로)
	glow_mat.set_shader_parameter("near_fade", Vector2(FM.FX_NEAR_FADE[0], FM.FX_NEAR_FADE[1]))
	glow_mmi.material_override = glow_mat
	_pool_mmi(glow_mmi, glow_mm, quad, MAX_GLOW, true)
	add_child(glow_mmi)
	for i in MAX_GLOW:
		g_pos.append(Vector3.ZERO)
		g_vel.append(Vector3.ZERO)
		g_color.append(Color.WHITE)
	for arr in [g_life, g_max, g_s0, g_s1, g_pow, g_grav, g_rot, g_hot]:
		arr.resize(MAX_GLOW)
	g_max.fill(1.0)
	g_kind.resize(MAX_GLOW)
	g_flat.resize(MAX_GLOW)
	# 연기
	smoke_mat.shader = SMOKE_SHADER
	smoke_mat.set_shader_parameter("near_fade", Vector2(FM.FX_NEAR_FADE[0], FM.FX_NEAR_FADE[1]))
	smoke_mmi.material_override = smoke_mat
	_pool_mmi(smoke_mmi, smoke_mm, quad, MAX_SMOKE, true)
	add_child(smoke_mmi)
	for i in MAX_SMOKE:
		s_pos.append(Vector3.ZERO)
		s_vel.append(Vector3.ZERO)
		s_color.append(Color.WHITE)
	for arr in [s_life, s_max, s_s0, s_s1, s_rot, s_spin, s_seed]:
		arr.resize(MAX_SMOKE)
	s_max.fill(1.0)
	# 조각 (빛 받는 상자, 불투명 — 끝에 작아짐)
	var cbox := BoxMesh.new()
	cbox.size = Vector3.ONE
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.roughness = 1.0
	cbox.material = cmat
	_pool_mmi(chunk_mmi, chunk_mm, cbox, MAX_CHUNKS, false)
	add_child(chunk_mmi)
	for i in MAX_CHUNKS:
		c_pos.append(Vector3.ZERO)
		c_vel.append(Vector3.ZERO)
		c_rot.append(Vector3.ZERO)
		c_spin.append(Vector3.ZERO)
		c_color.append(Color.WHITE)
	c_life.resize(MAX_CHUNKS)
	c_max.resize(MAX_CHUNKS)
	c_max.fill(1.0)
	c_size.resize(MAX_CHUNKS)
	c_bounced.resize(MAX_CHUNKS)


# 납작한 고리 (고도 XY 면, +Z 를 봄 — three.js RingGeometry 와 같은 자리)
static func ring_mesh(inner: float, outer: float, seg: int) -> ArrayMesh:
	var v := PackedVector3Array()
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var i0 := Vector3(cos(a0), sin(a0), 0) * inner
		var o0 := Vector3(cos(a0), sin(a0), 0) * outer
		var i1 := Vector3(cos(a1), sin(a1), 0) * inner
		var o1 := Vector3(cos(a1), sin(a1), 0) * outer
		v.append_array([i0, o0, o1, i0, o1, i1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# pos 에서 dir ({x,y} 게임 바닥 방향, null = 사방) 쪽으로 퍼지는 파편
func burst(pos: Vector3, dir, color: int, count := int(C.FX_PARTICLES), speed := 5.0, size := 0.1, life := 0.45) -> void:
	var dx: float = float(dir.x) * speed if dir != null else 0.0
	var dy: float = float(dir.y) * speed if dir != null else 0.0
	for i in count:
		var k := pi % MAX_PARTICLES
		pi += 1
		var a := randf() * TAU
		var r := randf()
		p_vel[k] = Vector3(dx + cos(a) * r * speed * 0.6, dy + sin(a) * r * speed * 0.6, 1.5 + randf() * speed * 0.6)
		var l := life * (0.6 + randf() * 0.6)
		p_life[k] = l
		p_max[k] = l
		p_size[k] = size * (0.6 + randf() * 0.8)
		p_pos[k] = pos
		p_rot[k] = Vector2.ZERO
		p_color[k] = Co.color(color)


# 퍼지는 충격파 고리. horizontal 이면 바닥에 눕힘, 아니면 카메라를 바라봄
func ring(pos: Vector3, color := 0xffffff, grow := 2.2, life := 0.28, horizontal := false) -> void:
	var k := ri % MAX_RINGS
	ri += 1
	r_pos[k] = pos
	r_life[k] = life
	r_max[k] = life
	r_grow[k] = grow
	r_flat[k] = 1 if horizontal else 0
	var c := Co.color(color)
	c.a = 0.9
	r_color[k] = c


func alive_rings() -> int:
	var n := 0
	for k in MAX_RINGS:
		if r_life[k] > 0.0:
			n += 1
	return n


# ---------- W18 빛·연기·조각 (수준이 끄면 아무것도 안 함) ----------
# 빛 하나: size 칸에서 size × grow 까지 ms 동안, 세기 a × (1-t)^pw 로 사라짐. kind = ROUND·STAR·SHOCK·STREAK.
# o: vel (게임 칸/초), grav (아래로 칸/초²), rot (라디안), hot (가운데 하양 0~1), flat (바닥에 눕힘), grow, pw
func glow(pos: Vector3, color: int, size: float, ms: float, a := 1.0, kind := ROUND, o := {}) -> void:
	if not lv.get("glow", false) or ms <= 0.0 or size <= 0.0:
		return
	if kind != SHOCK and kind != STREAK:
		a *= FXC.reduced_k("flash", reduced)
	var k := gi % MAX_GLOW
	gi += 1
	g_pos[k] = pos
	g_vel[k] = o.get("vel", Vector3.ZERO)
	var c := Co.color(color)
	c.a = a
	g_color[k] = c
	g_life[k] = ms / 1000.0
	g_max[k] = ms / 1000.0
	g_s0[k] = size
	g_s1[k] = size * float(o.get("grow", 1.0))
	g_pow[k] = float(o.get("pw", 2.0))
	g_grav[k] = float(o.get("grav", 0.0))
	g_rot[k] = float(o.get("rot", randf() * TAU))
	g_hot[k] = float(o.get("hot", 0.6))
	g_kind[k] = kind
	g_flat[k] = 1 if o.get("flat", false) else 0


# 불꽃 줄 n 개: dir (게임 Vector3, 길이 무관, ZERO = 사방) 쪽으로 퍼짐, 길이 len 칸, 중력·감속
func sparks(pos: Vector3, dir: Vector3, color: int, n: int, speed: float, len: float, ms: float, spread := 0.7) -> void:
	if not lv.get("glow", false):
		return
	var d := dir.normalized() if dir.length() > 1e-4 else Vector3.ZERO
	for i in n:
		var r := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.3, 1.0)).normalized()
		var v := (d + r * spread).normalized() if d != Vector3.ZERO else r
		var sp := speed * (0.6 + randf() * 0.6)
		glow(pos, color, len * (0.7 + randf() * 0.6), ms * (0.7 + randf() * 0.6), 1.0, STREAK, {"vel": v * sp, "grav": 9.0, "pw": 1.0, "hot": 0.9, "rot": 0.0})


# 연기 뭉치 n 개: size 칸에서 커지며 ms 동안 rise 칸/초로 오름, 가로로 spread 만큼 퍼짐
func smoke(pos: Vector3, color: int, n: int, size: float, ms: float, rise := 0.6, spread := 0.6, a := 0.75) -> void:
	if not lv.get("smoke", false):
		return
	for i in n:
		var k := si % MAX_SMOKE
		si += 1
		var ang := randf() * TAU
		var r := randf() * spread
		s_pos[k] = pos + Vector3(cos(ang) * r * 0.5, sin(ang) * r * 0.5, randf() * 0.2)
		s_vel[k] = Vector3(cos(ang) * r, sin(ang) * r, rise * (0.6 + randf() * 0.8))
		var c := Co.color(color)
		c.a = a * (0.7 + randf() * 0.3)
		s_color[k] = c
		var l := ms / 1000.0 * (0.7 + randf() * 0.5)
		s_life[k] = l
		s_max[k] = l
		s_s0[k] = size * (0.5 + randf() * 0.3)
		s_s1[k] = size * (1.3 + randf() * 0.6)
		s_rot[k] = randf() * TAU
		s_spin[k] = randf_range(-1.2, 1.2)
		s_seed[k] = randf()


# 돌·흙 조각 n 개: dir ({x,y} 또는 null) 쪽으로 튀어 한 번 튀고 멈춘 뒤 작아짐
func chunks(pos: Vector3, dir, color: int, n: int, speed: float, size: float, life := 1.1) -> void:
	if not lv.get("chunks", false):
		return
	var col := Co.color(color)
	for i in n:
		var k := ci % MAX_CHUNKS
		ci += 1
		var a := randf() * TAU
		var r := 0.4 + randf() * 0.6
		var dx: float = float(dir.x) * speed * 0.6 if dir != null else 0.0
		var dy: float = float(dir.y) * speed * 0.6 if dir != null else 0.0
		c_pos[k] = pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(0.0, 0.2))
		c_vel[k] = Vector3(cos(a) * r * speed * 0.55 + dx, sin(a) * r * speed * 0.55 + dy, 2.0 + randf() * speed * 0.7)
		c_rot[k] = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		c_spin[k] = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-8, 8))
		var l := life * (0.7 + randf() * 0.5)
		c_life[k] = l
		c_max[k] = l
		c_size[k] = size * (0.6 + randf() * 0.8)
		c_bounced[k] = 0
		c_color[k] = col.darkened(randf() * 0.25)


# ---------- W18 묶음 (타격·폭발·땅 충격) ----------
# 타격 임팩트: 밝은 번쩍 (별) → 빛 고리 → 밀린 쪽 불꽃 줄 (+ 강·치명은 흙먼지). dir = {x,y} 또는 null. 그리기 비용은 빛·연기 MultiMesh 몫
func impact(pos: Vector3, dir, tier_name: String) -> void:
	var T := FXC.tier(tier_name)
	var f: Array = T.flash
	var fc := int(FXC.HIT_FLASH_COLOR.get(tier_name, 0xffffff))
	glow(pos, fc, f[0], f[1], f[2], int(f[3]), {"grow": 1.35, "hot": 1.0, "pw": 2.0})
	glow(pos, 0xffffff, f[0] * 0.45, f[1] * 0.6, f[2], ROUND, {"hot": 1.0})
	var s: Array = T.shock
	if s[0] > 0.0:
		glow(pos, fc, 0.3, s[1], 0.85, SHOCK, {"grow": s[0] / 0.3, "pw": 1.4, "hot": 0.3})
	var sp: Array = T.sparks
	var d3 := Vector3(float(dir.x), float(dir.y), 0.35) if dir != null else Vector3.ZERO
	sparks(pos, d3, int(FXC.HIT_SPARK_COLOR.get(tier_name, 0xffe08a)), FXC.count(sp[0], lv), sp[1], sp[2], sp[3])
	var du: Array = T.dust
	if du[0] > 0:
		smoke(Vector3(pos.x, pos.y, pos.z - 0.9), FXC.HIT_DUST_COLOR, FXC.count(du[0], lv), du[1], 700.0, 0.5, 1.2, 0.55)


# 폭발: 불덩이 + 번쩍 + 바닥 빛 고리 + 연기 + 조각 + 불꽃 줄. k = 크기 (FXC.BOOM_K), dir = {x,y} 또는 null
func explode(pos: Vector3, k := 1.0, dir = null, ground_z = null) -> void:
	var B := FXC.BOOM
	var fl: Array = B.flash
	glow(pos, 0xfff0c0, fl[0] * k, fl[1], 1.0, STAR, {"grow": 1.3, "hot": 1.0})
	var fi: Array = B.fire
	var cols: Array = B.fire_colors
	for i in FXC.count(fi[0] * (0.6 + 0.4 * k), lv):
		var off := Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.2, 0.5)) * k
		glow(pos + off, int(cols[i % cols.size()]), fi[1] * k * (0.7 + randf() * 0.5), fi[2] * (0.7 + randf() * 0.6), 0.9, ROUND, {"grow": 1.6, "vel": off * 2.0 + Vector3(0, 0, 1.2), "pw": 1.5, "hot": 0.8})
	var gz: float = float(ground_z) if ground_z != null else pos.z - 0.4
	var sk: Array = B.shock
	glow(Vector3(pos.x, pos.y, gz + 0.06), 0xffc070, 0.4, sk[1], 0.9, SHOCK, {"grow": sk[0] * k / 0.4, "flat": true, "pw": 1.3, "hot": 0.4})
	var sm: Array = B.smoke
	smoke(pos + Vector3(0, 0, 0.2), int(B.smoke_color), FXC.count(sm[0] * (0.6 + 0.4 * k), lv), sm[1] * k, sm[2], sm[3], 0.9 * k, 0.7)
	var ch: Array = B.chunks
	chunks(pos, dir, int(B.chunk_color), FXC.count(ch[0] * k, lv), ch[1] * (0.7 + 0.3 * k), ch[2])
	var sp: Array = B.sparks
	sparks(pos, Vector3(0, 0, 0.6), int(B.spark_color), FXC.count(sp[0] * k, lv), sp[1] * (0.7 + 0.3 * k), sp[2], sp[3], 1.0)


# 땅 충격 (내려찍기·착지): 바닥 빛 고리 (r 반지름) + 흙먼지 + 돌 조각
func quake(pos: Vector3, r: float, glow_color := -1, dust_color := -1) -> void:
	var Q := FXC.QUAKE
	var gc: int = int(Q.glow_color) if glow_color < 0 else glow_color
	var dc: int = int(Q.dust_color) if dust_color < 0 else dust_color
	var s: Array = Q.shock
	glow(Vector3(pos.x, pos.y, pos.z + 0.06), gc, 0.4, s[1], 0.8, SHOCK, {"grow": maxf(1.0, r * s[0]) / 0.4, "flat": true, "pw": 1.3, "hot": 0.3})
	var d: Array = Q.dust
	for i in FXC.count(d[0], lv):
		var a := TAU * i / maxf(1.0, d[0]) + randf() * 0.5
		smoke(pos + Vector3(cos(a) * r * 0.6, sin(a) * r * 0.6, 0.15), dc, 1, d[1], d[2], 0.4, 0.4 + r * 0.4, 0.6)
	var c: Array = Q.chunks
	chunks(pos + Vector3(0, 0, 0.1), null, 0x7a6e60, FXC.count(c[0], lv), c[1], c[2])


# ---------- 화면 (흔들림·반동·히트스톱) ----------
func shake(amp: float, ms := C.FX_SHAKE_MS) -> void:
	FM.shake_take(sh, now_ms(), amp * FXC.reduced_k("shake", reduced), ms)


# 카메라에 더할 흔들림 (게임 좌표, 없으면 ZERO)
func shake_offset() -> Vector3:
	var a := FM.shake_amp(sh, now_ms())
	if a <= 0.0:
		return Vector3.ZERO
	return Vector3(randf_range(-1, 1) * a, randf_range(-1, 1) * a, randf_range(-1, 1) * a * 0.6)


# 카메라 반동 (도): 지금 남은 것보다 세면 바꿈
func cam_kick(pitch: float, yaw: float, roll: float, fov := 0.0, ms: float = FXC.KICK.ms) -> void:
	var m := FXC.reduced_k("kick", reduced)
	var fm := FXC.reduced_k("fov", reduced)
	var cur := kick_now()
	var amp := absf(pitch) + absf(yaw) + absf(roll) + fov * 40.0
	if amp * m <= absf(cur.x) + absf(cur.y) + absf(cur.z) + cur.w * 40.0 or (amp * m <= 0.0 and fov * fm <= 0.0):
		return
	kick = {"t0": now_ms(), "ms": ms, "pitch": pitch * m, "yaw": yaw * m, "roll": roll * m, "fov": fov * fm}


# 지금 반동 (pitch, yaw, roll 도, 시야 조임 0~1)
func kick_now(now := now_ms()) -> Vector4:
	var k := FXC.kick_k(now - float(kick.t0), float(kick.ms))
	return Vector4(kick.pitch * k, kick.yaw * k, kick.roll * k, kick.fov * k)


# 1인칭 팔 반동 (카메라 좌표: 오른쪽 +x, 위 +y, 뒤 +z)
func vm_kick(off: Vector3, ms: float = FXC.VM_KICK_MS) -> void:
	vm = {"t0": now_ms(), "ms": ms, "off": off * (0.5 if reduced else 1.0)}


func vm_offset(now := now_ms()) -> Vector3:
	return vm.off * FXC.kick_k(now - float(vm.t0), float(vm.ms))


# 화면 히트스톱 (ms 동안 화면 시계 FXC.HITSTOP_SCALE 배)
func hit_stop(ms: float) -> void:
	ms *= FXC.reduced_k("stop", reduced)
	if ms > 0.0:
		stop_until = maxf(stop_until, now_ms() + ms)


func stop_scale(now := now_ms()) -> float:
	return FXC.hit_scale(now, stop_until)


func hit_squash(id) -> void:
	squash_t[int(id)] = now_ms()


# 0~ 찌그러짐 정도 (0 = 평상시) — 몸 (G2) 이 읽음
func squash_amount(id) -> float:
	return _timer(squash_t, id, FM.squash)


func start_punch(id) -> void:
	punch_t[int(id)] = now_ms()


# 0~1 팔 뻗은 정도 — 몸 (G2) 이 읽음
func punch_amount(id) -> float:
	return _timer(punch_t, id, FM.punch)


func _timer(d: Dictionary, id, f: Callable) -> float:
	if id == null or not d.has(int(id)):
		return 0.0
	var v: float = f.call(now_ms() - d[int(id)])
	if v < 0.0:
		d.erase(int(id))
		return 0.0
	return v


func alive_particles() -> int:
	return mm.visible_instance_count


# 지금 떠 있는 효과 수 (비용 확인용): {parts, rings, glow, smoke, chunks, draws (보이는 MultiMesh 수)}
func stats() -> Dictionary:
	var out := {"parts": mm.visible_instance_count, "rings": ring_mm.visible_instance_count, "glow": glow_mm.visible_instance_count, "smoke": smoke_mm.visible_instance_count, "chunks": chunk_mm.visible_instance_count}
	var d := 0
	for m in [mmi, ring_mmi, glow_mmi, smoke_mmi, chunk_mmi]:
		d += 1 if m.visible else 0
	out.draws = d
	return out


func update(dt: float, camera: Camera3D) -> void:
	cam = camera
	var cb := cam.global_basis.orthonormalized() if cam != null and cam.is_inside_tree() else Basis()
	var n := 0
	for k in MAX_PARTICLES:
		if p_life[k] <= 0.0:
			continue
		p_life[k] -= dt
		if p_life[k] <= 0.0:
			continue
		var v := p_vel[k]
		v.z -= GRAVITY * dt
		p_vel[k] = v
		p_pos[k] += v * dt
		p_rot[k] += Vector2(dt * 8.0, dt * 6.0)
		var c := p_color[k]
		c.a = minf(1.0, p_life[k] / p_max[k] * 1.5)
		var rot := p_rot[k]
		# 게임 x·y 축으로 돌림 (three.js rotation.x·y) → 고도 축 (x, z, -y)
		var b := Basis(Vector3.RIGHT, rot.x) * Basis(Vector3.FORWARD, rot.y)
		mm.set_instance_transform(n, Transform3D(b.scaled_local(Vector3.ONE * p_size[k]), Co.gpos(p_pos[k])))
		mm.set_instance_color(n, c)
		n += 1
	mm.visible_instance_count = n
	mmi.visible = n > 0
	_update_rings(dt, cb)
	_update_glow(dt, cb)
	_update_smoke(dt, cb)
	_update_chunks(dt)


func _update_rings(dt: float, cb: Basis) -> void:
	var n := 0
	var flat := Basis(Vector3.RIGHT, -PI / 2)
	for k in MAX_RINGS:
		if r_life[k] <= 0.0:
			continue
		r_life[k] -= dt
		if r_life[k] <= 0.0:
			continue
		var t: float = 1.0 - r_life[k] / r_max[k]
		var s: float = 0.2 + t * r_grow[k]
		var b := flat if r_flat[k] else cb
		ring_mm.set_instance_transform(n, Transform3D(b.scaled_local(Vector3(s, s, s)), Co.gpos(r_pos[k])))
		var c := r_color[k]
		c.a = 0.9 * (1.0 - t)
		ring_mm.set_instance_color(n, c)
		n += 1
	ring_mm.visible_instance_count = n
	ring_mmi.visible = n > 0


func _update_glow(dt: float, cb: Basis) -> void:
	var n := 0
	var flat := Basis(Vector3.RIGHT, -PI / 2)
	var cz := cb.z
	for k in MAX_GLOW:
		if g_life[k] <= 0.0:
			continue
		g_life[k] -= dt
		if g_life[k] <= 0.0:
			continue
		var v := g_vel[k]
		if g_grav[k] != 0.0:
			v.z -= g_grav[k] * dt
			v *= exp(-2.5 * dt) # 불꽃 줄 감속
			g_vel[k] = v
		g_pos[k] += v * dt
		var t: float = 1.0 - g_life[k] / g_max[k]
		var e := 1.0 - (1.0 - t) * (1.0 - t)
		var s: float = lerpf(g_s0[k], g_s1[k], e)
		var gp := Co.gpos(g_pos[k])
		var tr: Transform3D
		if g_kind[k] == STREAK:
			var gv := Co.gpos(v)
			var along := gv - cz * gv.dot(cz)
			if along.length() < 1e-4:
				along = cb.x
			along = along.normalized()
			var side := cz.cross(along).normalized()
			var w := s * 0.16
			tr = Transform3D(Basis(along * s, side * w, cz), gp - along * (s * 0.5))
		elif g_flat[k]:
			tr = Transform3D(flat.scaled_local(Vector3(s, s, s)), gp)
		else:
			tr = Transform3D(cb.scaled_local(Vector3(s, s, s)), gp)
		glow_mm.set_instance_transform(n, tr)
		var c := g_color[k]
		c.a *= pow(1.0 - t, g_pow[k])
		glow_mm.set_instance_color(n, c)
		glow_mm.set_instance_custom_data(n, Color(g_kind[k], g_rot[k], g_hot[k], 0.0))
		n += 1
	glow_mm.visible_instance_count = n
	glow_mmi.visible = n > 0


func _update_smoke(dt: float, cb: Basis) -> void:
	var n := 0
	for k in MAX_SMOKE:
		if s_life[k] <= 0.0:
			continue
		s_life[k] -= dt
		if s_life[k] <= 0.0:
			continue
		var v := s_vel[k]
		v.x *= exp(-1.5 * dt)
		v.y *= exp(-1.5 * dt)
		s_vel[k] = v
		s_pos[k] += v * dt
		s_rot[k] += s_spin[k] * dt
		var t: float = 1.0 - s_life[k] / s_max[k]
		var s: float = lerpf(s_s0[k], s_s1[k], 1.0 - (1.0 - t) * (1.0 - t))
		smoke_mm.set_instance_transform(n, Transform3D(cb.scaled_local(Vector3(s, s, s)), Co.gpos(s_pos[k])))
		var c := s_color[k]
		c.a *= minf(1.0, t * 8.0) * (1.0 - t) # 들어올 땐 빨리, 나갈 땐 천천히
		smoke_mm.set_instance_color(n, c)
		smoke_mm.set_instance_custom_data(n, Color(s_rot[k], s_seed[k], 0.0, 0.0))
		n += 1
	smoke_mm.visible_instance_count = n
	smoke_mmi.visible = n > 0


func _update_chunks(dt: float) -> void:
	var n := 0
	for k in MAX_CHUNKS:
		if c_life[k] <= 0.0:
			continue
		c_life[k] -= dt
		if c_life[k] <= 0.0:
			continue
		var v := c_vel[k]
		var p := c_pos[k]
		v.z -= GRAVITY * dt
		var nz := p.z + v.z * dt
		if v.z < 0.0 and solid.call(p.x, p.y, nz - 0.03):
			if not c_bounced[k]:
				v = Vector3(v.x * 0.45, v.y * 0.45, -v.z * 0.3)
				c_bounced[k] = 1
				c_spin[k] *= 0.4
			else:
				v = Vector3(v.x * 0.2, v.y * 0.2, 0.0)
				c_spin[k] = Vector3.ZERO
		else:
			p.z = nz
		p.x += v.x * dt
		p.y += v.y * dt
		c_vel[k] = v
		c_pos[k] = p
		c_rot[k] += c_spin[k] * dt
		var fade := minf(1.0, c_life[k] / (c_max[k] * 0.3)) # 끝 30% 에 작아짐
		var r := c_rot[k]
		chunk_mm.set_instance_transform(n, Transform3D(Basis.from_euler(r).scaled_local(Vector3.ONE * c_size[k] * fade), Co.gpos(p)))
		chunk_mm.set_instance_color(n, c_color[k])
		n += 1
	chunk_mm.visible_instance_count = n
	chunk_mmi.visible = n > 0
