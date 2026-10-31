# 날아가는 것·조준 (render.js 의 renderer.* 중 투사체 부분): 폭탄 (state.bombs, 남은 시간 따라 빨갛게 깜빡) · 대포 포탄 (state.shells, 연기 꼬리)
# · 바드 음파 음표 (state.notes, 살랑 + 반짝이) · 닌자 표창 (star 이벤트) · 사냥꾼 조준점 (aim)·화살 (shot, 막히면 블록에 박힘)
# · 조종 줄 (updateBeams: 조종하는 사람 머리 → 그 블록) · 포구 불꽃·포탄 터짐·블록 부서짐·발밑 포격·대형 포탄 폭발 (effects = G5 파편·고리)
# 몸 동작 (표창 던지는 손·대포 반동) 은 G2, 흔들림·소리는 G5
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")

var effects = null # G5 fx/effects.gd
var marks = null # world/marks.gd (trail·block_pulse·neighbors)
var solid: Callable # World.solid_at
var bodies = null # world/bodies.gd (shown: 화면 위치)
var cam: Camera3D # 조준점이 카메라를 봄
var make_mat = null # Callable(Color) -> Material (G3 툰)

var bombs := [] # MeshInstance3D
var shells := {} # id -> {node, big, x, y, z, at, speed, smoke, dir}
var notes := {} # id -> {node, x, y, z, at, t0, spark, dir}
var stars := [] # {node, from, to, t0}
var aims := [] # {node, mat, target, who, t0, ms}
var arrows := [] # {node, from, to, t0, stuck, done}
var beams := [] # MeshInstance3D
var beam_mat: StandardMaterial3D
var _cache := {}


func _ready() -> void:
	Store.game_event.connect(on_event)
	beam_mat = _flat(0xd040d0, 0.5)


static func now_ms() -> float:
	return Time.get_ticks_msec() * 1.0


static func _flat(color: int, a := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(Co.color(color), a)
	if a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _toon(color: int) -> Material:
	if not _cache.has(color):
		if make_mat != null:
			_cache[color] = make_mat.call(Co.color(color))
		else:
			var m := StandardMaterial3D.new()
			m.albedo_color = Co.color(color)
			_cache[color] = m
	return _cache[color]


static func _mesh_node(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	return n


# 고도 노드의 +x 를 게임 방향 d 로 (화살·표창 날아가는 쪽)
static func point_x(d: Vector3) -> Basis:
	var g := Co.gpos(d).normalized()
	if g.length() < 1e-6:
		return Basis()
	return Basis(Quaternion(Vector3.RIGHT, g))


func _burst(p: Vector3, dir, color: int, n: int, speed: float, size: float, life: float) -> void:
	if effects != null:
		effects.burst(p, dir, color, n, speed, size, life)


func _ring(p: Vector3, color: int, grow: float, life: float, horizontal := false) -> void:
	if effects != null:
		effects.ring(p, color, grow, life, horizontal)


# ---------- 이벤트 ----------
func on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"shellFire": # 포구 불꽃 + 연기 뭉치 (쏘는 쪽으로)
			var d = e.get("dir") if e.get("dir") != null else {"x": 1, "y": 0}
			var p := Vector3(e.x, e.y, e.z)
			var big: bool = e.get("big", false)
			_burst(p, {"x": d.x * 1.2, "y": d.y * 1.2}, 0xffd040, 22 if big else 12, 7 if big else 5, 0.15 if big else 0.1, 0.25)
			_burst(p, {"x": d.x * 0.6, "y": d.y * 0.6}, 0x888888, 26 if big else 14, 3.5 if big else 2.5, 0.2 if big else 0.14, 0.8)
			_ring(p, 0xffe0a0, 2.6 if big else 1.4, 0.2)
		"shellEnd": # 닿은 것에 따라: expire = 연기만, 보통 포탄 = 터짐 (대형은 bigShellBlast)
			var p := Vector3(e.x, e.y, e.z)
			if str(e.get("what", "")) == "expire":
				_burst(p, null, 0x999999, 6, 1.2, 0.12, 0.6)
			elif not e.get("big", false):
				_burst(p, null, 0xffb040, 12, 5, 0.1, 0.3)
				_burst(p, null, 0x777777, 12, 3, 0.14, 0.6)
				_ring(p, 0xffd080, 2, 0.25)
		"blockBreak": # 부서진 칸마다 번쩍 + 돌 파편 + 옆 블록 들썩
			var cells: Array = e.get("cells", [])
			if cells.is_empty():
				return
			var big: bool = e.get("big", false)
			if marks != null:
				marks.block_pulse(cells, 0xffffff, C.BLOCK_PULSE_MS, 0.0, 0.85)
				marks.block_pulse(marks.neighbors(cells), 0xffffff, C.BLOCK_PULSE_MS, C.BLOCK_JOLT, 0.4)
			for c in cells:
				var p := Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5)
				_burst(p, null, 0x8a8078, 10 if big else 16, 6 if big else 5, 0.16, 0.7)
				_burst(p, {"x": 0, "y": 0}, 0x6e665e, 3 if big else 5, 3, 0.28, 1.1)
				_burst(p, null, 0xb0a898, 6, 2, 0.12, 0.8)
		"groundShot": # 대포수 F 발밑 포격
			var p := Vector3(e.x, e.y, e.z + 0.1)
			_ring(p, 0xffc080, float(e.get("r", 1.8)) * 2, 0.35, true)
			_burst(p, null, 0xffb040, 16, 6, 0.12, 0.3)
			_burst(p, null, 0x9a8a78, 20, 4, 0.15, 0.7)
		"bigShellBlast": # 대포수 R 끝 폭발
			var p := Vector3(e.x, e.y, e.z)
			var r := float(e.get("r", 2.2))
			_ring(p, 0xffa040, r * 2.2, 0.4)
			_ring(Vector3(e.x, e.y, maxf(0.05, e.z - 0.5)), 0xffd080, r * 2, 0.45, true)
			_burst(p, null, 0xff8020, 40, 9, 0.16, 0.5)
			_burst(p, null, 0x666666, 30, 4, 0.22, 1.0)
		"star": # 닌자 표창 한 발: 아주 빠르게 직진 (판정은 즉시)
			star_shot(e)
		"aim": # 사냥꾼 R 조준: 대상마다 빨간 조준점이 조여 듦
			aim_at(e)
		"interrupt":
			aim_end(e.get("who"))
		"shot":
			shoot(e)


# ---------- 표창 ----------
func star_shot(e: Dictionary) -> void:
	if e.get("from") == null or e.get("to") == null:
		return
	if not _cache.has("star"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 8:
			var r0 := 0.05 if i % 2 else 0.17
			var r1 := 0.17 if i % 2 else 0.05
			var a0 := TAU * i / 8
			var a1 := TAU * (i + 1) / 8
			for v in [Vector3.ZERO, Vector3(cos(a0) * r0, sin(a0) * r0, 0), Vector3(cos(a1) * r1, sin(a1) * r1, 0)]:
				st.add_vertex(v)
		_cache.star = st.commit()
	var n := _mesh_node(_cache.star, _flat(0xd8e0ea))
	add_child(n)
	var f := Vector3(e.from.x, e.from.y, e.from.z)
	var t := Vector3(e.to.x, e.to.y, e.to.z)
	n.position = Co.gpos(f)
	stars.append({"node": n, "from": f, "to": t, "t0": now_ms()})


# ---------- 사냥꾼 조준·화살 ----------
func aim_at(e: Dictionary) -> void:
	var mat := _flat(0xff2a1a, 0.95)
	mat.no_depth_test = true
	mat.render_priority = 13
	for id in e.get("targets", []):
		var g := Node3D.new()
		g.add_child(_mesh_node(_ring_mesh(0.26, 0.33), mat))
		for k in 4:
			var q := QuadMesh.new()
			q.size = Vector2(0.06, 0.16)
			var tk := _mesh_node(q, mat)
			var a := k * PI / 2
			tk.position = Vector3(cos(a) * 0.4, sin(a) * 0.4, 0)
			tk.rotation.z = a + PI / 2
			g.add_child(tk)
		add_child(g)
		aims.append({"node": g, "target": id, "who": e.get("who"), "t0": now_ms(), "ms": float(e.get("ms", 500))})


func aim_end(who) -> void:
	for a in aims:
		if a.who == who:
			a.t0 = -1e12


static func _ring_mesh(inner: float, outer: float, seg := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p := [Vector3(cos(a0) * outer, sin(a0) * outer, 0), Vector3(cos(a0) * inner, sin(a0) * inner, 0), Vector3(cos(a1) * outer, sin(a1) * outer, 0), Vector3(cos(a1) * inner, sin(a1) * inner, 0)]
		for v in [p[0], p[1], p[2], p[2], p[1], p[3]]:
			st.add_vertex(v)
	return st.commit()


func shoot(e: Dictionary) -> void:
	aim_end(e.get("who"))
	if e.get("from") == null:
		return
	for sh in e.get("shots", []):
		var from := Vector3(e.from.x, e.from.y, e.from.z - 0.2)
		var to := Vector3(sh.to.x, sh.to.y, sh.to.z)
		var stuck = null
		if sh.get("blocked", false) and solid.is_valid():
			# 시선을 따라 가며 처음 만나는 블록 칸 앞에서 멈춤
			var dir := to - from
			var len := dir.length()
			dir = dir.normalized()
			var d := 0.3
			while d < len:
				var q := from + dir * d
				if solid.call(q.x, q.y, q.z):
					to = from + dir * (d - 0.15)
					stuck = [floori(q.x), floori(q.y), floori(q.z)]
					break
				d += 0.05
		var g := Node3D.new()
		var shaft := BoxMesh.new()
		shaft.size = Vector3(0.5, 0.03, 0.03)
		var s := _mesh_node(shaft, _toon(0x8a5a30))
		s.position.x = -0.25
		g.add_child(s)
		var head := CylinderMesh.new()
		head.top_radius = 0.0
		head.bottom_radius = 0.045
		head.height = 0.12
		head.radial_segments = 4
		var h := _mesh_node(head, _toon(0xb8c2cc))
		h.position.x = 0.04
		h.rotation.z = -PI / 2 # 뾰족한 쪽이 +x
		g.add_child(h)
		for r in [0.0, PI / 2]:
			var fm := BoxMesh.new()
			fm.size = Vector3(0.1, 0.008, 0.07)
			var f := _mesh_node(fm, _toon(0xd8352a))
			f.position.x = -0.46
			f.rotation.x = r
			g.add_child(f)
		g.basis = point_x(to - from)
		g.position = Co.gpos(from)
		add_child(g)
		arrows.append({"node": g, "from": from, "to": to, "t0": now_ms(), "stuck": stuck, "done": false})
		if marks != null:
			marks.trail(from, to, 0xff5040, C.ARROW_TRAIL_MS)


# ---------- 매 프레임 ----------
func update(st: Dictionary, dt: float) -> void:
	var now := now_ms()
	_bombs(st.get("bombs", []), now)
	_shells(st.get("shells", []), dt, now)
	_notes(st.get("notes", []), dt, now)
	_beams(st)
	for i in range(stars.size() - 1, -1, -1):
		var s: Dictionary = stars[i]
		var u: float = (now - s.t0) / C.STAR_FLY_MS
		if u >= 1:
			s.node.queue_free()
			stars.remove_at(i)
			continue
		s.node.position = Co.gpos(s.from.lerp(s.to, u))
		s.node.basis = Basis(Vector3.UP, now / 25.0) # 세워서 빙글 (원판 면이 수직)
	for i in range(aims.size() - 1, -1, -1):
		var a: Dictionary = aims[i]
		var pos = bodies.shown.get(int(a.target)) if bodies != null and a.target != null else null
		var u: float = (now - a.t0) / (a.ms + C.WARN_TAIL_MS)
		if u >= 1 or pos == null:
			a.node.queue_free()
			aims.remove_at(i)
			continue
		a.node.position = Co.gxyz(pos.x, pos.y, pos.z + C.PLAYER_HEIGHT * 0.6)
		if cam != null:
			a.node.global_basis = cam.global_basis
		var k := minf(1.0, u * 1.3)
		a.node.scale = Vector3.ONE * (1.7 - 0.7 * k * k * (3 - 2 * k)) # 조여 듦
	for i in range(arrows.size() - 1, -1, -1):
		var a: Dictionary = arrows[i]
		var u: float = (now - a.t0) / C.ARROW_FLY_MS
		if u < 1:
			a.node.position = Co.gpos(a.from.lerp(a.to, u))
			continue
		a.node.position = Co.gpos(a.to)
		if not a.done:
			a.done = true
			if a.stuck != null:
				_burst(a.to, null, 0x9a8a78, 10, 2.5, 0.08, 0.4) # 박힘: 나무 부스러기 + 블록 들썩
				if marks != null:
					marks.block_pulse([a.stuck], 0xffffff, C.BLOCK_PULSE_MS, C.BLOCK_JOLT, 0.6)
				View.sound_cue.emit("arrowStuck", {"x": a.to.x, "y": a.to.y, "z": a.to.z})
		if a.stuck == null or u * C.ARROW_FLY_MS > C.ARROW_FLY_MS + C.ARROW_STUCK_MS:
			a.node.queue_free()
			arrows.remove_at(i)


func _bombs(list: Array, now: float) -> void:
	while bombs.size() < list.size():
		var sp := SphereMesh.new()
		sp.radius = C.BOMB_MODEL_SIZE / 2
		sp.height = C.BOMB_MODEL_SIZE
		var m := StandardMaterial3D.new() # 폭탄마다 따로 깜빡
		m.albedo_color = Color8(0x22, 0x22, 0x22)
		m.emission_enabled = true
		var n := _mesh_node(sp, m)
		add_child(n)
		bombs.append(n)
	for i in bombs.size():
		var n: MeshInstance3D = bombs[i]
		n.visible = i < list.size()
		if not n.visible:
			continue
		var b: Dictionary = list[i]
		n.position = Co.gxyz(b.x + 0.5, b.y + 0.5, b.z + C.BOMB_MODEL_SIZE / 2)
		var period := 80 + minf(1.0, float(b.get("left", 0)) / C.BOMB_FUSE_MS) * 320 # 남은 시간이 짧을수록 빨리
		var on := int(floor(now / period)) % 2 == 0
		(n.material_override as StandardMaterial3D).emission = Color8(0xff, 0x20, 0) if on else Color.BLACK


func _shells(list: Array, dt: float, now: float) -> void:
	var seen := {}
	for sh in list:
		var id = sh.id
		seen[id] = true
		if not shells.has(id):
			var big: bool = sh.get("big", false)
			var ico := SphereMesh.new()
			ico.radial_segments = 8
			ico.rings = 4
			ico.radius = 1.0
			ico.height = 2.0
			var n := _mesh_node(ico, _toon(0x3a2a26 if big else 0x2a2c30))
			n.scale = Vector3.ONE * (C.SHELL_BIG_SIZE if big else C.SHELL_SIZE)
			if big:
				var band := TorusMesh.new()
				band.inner_radius = 0.9
				band.outer_radius = 1.14
				band.rings = 16
				band.ring_segments = 4
				n.add_child(_mesh_node(band, _flat(0xff6a20)))
			add_child(n)
			shells[id] = {"node": n, "big": big, "x": sh.x, "y": sh.y, "z": sh.z, "at": now, "speed": C.CANNON_R_SPEED if big else C.CANNON_SHELL_SPEED, "smoke": 0.0}
		var m: Dictionary = shells[id]
		if sh.x != m.x or sh.y != m.y or sh.z != m.z:
			m.merge({"x": sh.x, "y": sh.y, "z": sh.z, "at": now}, true)
		m.dir = sh.get("dir")
	for id in shells.keys():
		var m: Dictionary = shells[id]
		if not seen.has(id):
			m.node.queue_free()
			shells.erase(id)
			continue
		var ahead: float = minf(0.1, (now - m.at) / 1000.0) * m.speed # 다음 위치가 올 때까지 날아가는 쪽으로
		var d = m.get("dir") if m.get("dir") != null else {"x": 0, "y": 0, "z": 0}
		var p := Vector3(m.x + d.x * ahead, m.y + d.y * ahead, m.z + d.z * ahead)
		m.node.position = Co.gpos(p)
		m.node.rotation += Vector3(dt * 9, 0, dt * 6)
		m.smoke += dt * (60 if m.big else 30) # 꼬리: 보통은 회색 연기, 대형은 불꽃 + 진한 연기
		while m.smoke >= 1:
			m.smoke -= 1
			var back := p - Vector3(d.x, d.y, d.z) * 0.2
			_burst(back, {"x": 0, "y": 0}, (0xff7a20 if randf() < 0.5 else 0x555555) if m.big else 0xaaaaaa, 1, 0.4, 0.16 if m.big else 0.09, 0.5 if m.big else 0.45)


func _notes(list: Array, dt: float, now: float) -> void:
	var seen := {}
	for nt in list:
		var id = nt.id
		seen[id] = true
		if not notes.has(id):
			var mat := _flat(int(C.BARD_NOTE_COLOR))
			var g := Node3D.new() # 8분음표: 머리 + 기둥 + 깃발 (게임 z 위 = 고도 y)
			var hm := SphereMesh.new()
			hm.radius = 0.11
			hm.height = 0.22
			var head := _mesh_node(hm, mat)
			head.scale = Vector3(1.3, 0.9, 0.6)
			g.add_child(head)
			var sm := BoxMesh.new()
			sm.size = Vector3(0.03, 0.34, 0.03)
			var stem := _mesh_node(sm, mat)
			stem.position = Vector3(0.12, 0.17, 0)
			g.add_child(stem)
			var fm := BoxMesh.new()
			fm.size = Vector3(0.14, 0.05, 0.025)
			var flag := _mesh_node(fm, mat)
			flag.position = Vector3(0.18, 0.3, 0)
			flag.rotation.z = -0.6
			g.add_child(flag)
			add_child(g)
			notes[id] = {"node": g, "x": nt.x, "y": nt.y, "z": nt.z, "at": now, "t0": now, "spark": 0.0}
		var m: Dictionary = notes[id]
		if nt.x != m.x or nt.y != m.y or nt.z != m.z:
			m.merge({"x": nt.x, "y": nt.y, "z": nt.z, "at": now}, true)
		m.dir = nt.get("dir")
	for id in notes.keys():
		var m: Dictionary = notes[id]
		if not seen.has(id):
			m.node.queue_free()
			notes.erase(id)
			continue
		var d = m.get("dir") if m.get("dir") != null else {"x": 0, "y": 0, "z": 0}
		var ahead: float = minf(0.1, (now - m.at) / 1000.0) * C.BARD_NOTE_SPEED
		var p := Vector3(m.x + d.x * ahead, m.y + d.y * ahead, m.z + d.z * ahead + sin((now - m.t0) / 70.0) * 0.12) # 살랑
		m.node.position = Co.gpos(p)
		m.node.rotation = Vector3(0, Co.rot_y(atan2(d.y, d.x) + PI / 2), sin((now - m.t0) / 120.0) * 0.4) # 옆에서 보이게
		m.spark += dt * 18
		while m.spark >= 1:
			m.spark -= 1
			_burst(p, {"x": 0, "y": 0}, int(C.BARD_NOTE_COLOR) if randf() < 0.5 else 0xffe070, 1, 0.5, 0.05, 0.35)


# 조종 줄: 블록을 조종하는 사람 머리 → 그 블록 가운데 (render.js updateBeams)
func _beams(st: Dictionary) -> void:
	var pairs := []
	for pc in st.get("pieces", []):
		if str(pc.get("phase", "")) != "control" or pc.get("controller") == null or pc.cells.is_empty():
			continue
		var owner := Store.player(pc.controller)
		var s = bodies.shown.get(int(pc.controller)) if bodies != null else null
		if s == null or owner.is_empty() or not owner.alive:
			continue
		var c := Vector3.ZERO
		for q in pc.cells:
			c += Vector3(q[0], q[1], q[2])
		c = c / pc.cells.size() + Vector3(0.5, 0.5, 0.5)
		pairs.append([Vector3(s.x, s.y, s.z + C.PLAYER_HEIGHT), c])
	while beams.size() < pairs.size():
		var cy := CylinderMesh.new()
		cy.top_radius = C.BEAM_RADIUS
		cy.bottom_radius = C.BEAM_RADIUS
		cy.height = 1.0
		cy.radial_segments = 8
		cy.cap_top = false
		cy.cap_bottom = false
		var n := _mesh_node(cy, beam_mat)
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		beams.append(n)
	for i in beams.size():
		var n: MeshInstance3D = beams[i]
		n.visible = i < pairs.size()
		if not n.visible:
			continue
		var a: Vector3 = Co.gpos(pairs[i][0])
		var b: Vector3 = Co.gpos(pairs[i][1])
		var dir := b - a
		n.position = a + dir * 0.5
		n.basis = Basis(Quaternion(Vector3.UP, dir.normalized())).scaled_local(Vector3(1, dir.length(), 1)) if dir.length() > 1e-4 else Basis()
	beam_mat.albedo_color.a = C.BEAM_OPACITY + C.BEAM_PULSE * sin(now_ms() / 150.0) # 살짝 깜빡임
