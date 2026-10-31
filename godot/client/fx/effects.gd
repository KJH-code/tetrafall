# 타격감 이펙트 (client/effects.js 자리): 파편 (MultiMesh 하나, 칸마다 색·투명도) · 충격파 고리 · 화면 흔들림 · 찌그러짐·팔 뻗음 타이머.
# 부르는 쪽은 게임 좌표 (z 위). 시각은 ms (Time.get_ticks_msec), 화면 dt 는 KO 슬로모션 배율이 곱해져 들어옴
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const FM := preload("res://fx/fx_math.gd")

const MAX_PARTICLES := 160
const MAX_RINGS := 12
const GRAVITY := 14.0

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
var rings: Array[MeshInstance3D] = []
var ring_u: Array[Dictionary] = []
var ri := 0
var sh := {"amp": 0.0, "ms": 1.0, "until": 0.0}
var squash_t := {} # 플레이어 id -> 맞은 시각 (ms)
var punch_t := {} # 플레이어 id -> 팔 뻗기 시작 (ms)
var cam: Camera3D = null # 고리가 바라볼 카메라 (update 때 받음)


static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


func _init() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = MAX_PARTICLES
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0 # 파편은 필드 어디든 (frustumCulled false 자리)
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
	var ring_mesh := ring_mesh(0.8, 1.0, 40)
	for i in MAX_RINGS:
		var m := MeshInstance3D.new()
		m.mesh = ring_mesh
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.cull_mode = BaseMaterial3D.CULL_DISABLED
		rm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.material_override = rm
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		rings.append(m)
		ring_u.append({"life": 0.0, "max": 1.0, "grow": 1.0, "horizontal": false})


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
	var m := rings[k]
	ring_u[k] = {"life": life, "max": life, "grow": grow, "horizontal": horizontal}
	m.position = Co.gpos(pos)
	var c := Co.color(color)
	c.a = 0.9
	(m.material_override as StandardMaterial3D).albedo_color = c
	_ring_basis(k, 0.2)
	m.visible = true


func _ring_basis(k: int, s: float) -> void:
	var m := rings[k]
	var b := Basis(Vector3.RIGHT, -PI / 2) if ring_u[k].horizontal else (cam.global_basis.orthonormalized() if cam != null else Basis())
	m.basis = b.scaled_local(Vector3(s, s, s))


func shake(amp: float, ms := C.FX_SHAKE_MS) -> void:
	FM.shake_take(sh, now_ms(), amp, ms)


# 카메라에 더할 흔들림 (게임 좌표, 없으면 ZERO)
func shake_offset() -> Vector3:
	var a := FM.shake_amp(sh, now_ms())
	if a <= 0.0:
		return Vector3.ZERO
	return Vector3(randf_range(-1, 1) * a, randf_range(-1, 1) * a, randf_range(-1, 1) * a * 0.6)


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


func update(dt: float, camera: Camera3D) -> void:
	cam = camera
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
	for k in MAX_RINGS:
		var m := rings[k]
		if not m.visible:
			continue
		var u: Dictionary = ring_u[k]
		u.life -= dt
		if u.life <= 0.0:
			m.visible = false
			continue
		var t: float = 1.0 - u.life / u.max
		_ring_basis(k, 0.2 + t * u.grow)
		(m.material_override as StandardMaterial3D).albedo_color.a = 0.9 * (1.0 - t)
