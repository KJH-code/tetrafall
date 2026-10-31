# 몸 둘레 따로 그리는 것 (render.js 의 사람마다 효과 — 몸 재질 색 바꾸기는 G2 몸 몫):
# 스킬·필살기 발밑 퍼지는 고리 + 필살기 반짝이 (aura) · R 게이지 찬 상대 둘레 빛 (updateUltAura) · 사냥꾼 표식 마름모 (updateHuntMarks)
# · 취약 음표·둔화 소용돌이 (updateStatusFx) · 메탈 앰프 (updateAmpFx·ampWaves) · 광전사 소용돌이 범위 (updateWhirlFx)
# · 조종 대기 표시 (waitMark) · 내 발밑 위험 고리 (dangerRing) · 바드·광전사 이벤트 파편 (glideRing·form·song·ampEnd·rushLand·spinEnd)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")

var effects = null # G5 fx/effects.gd
var marks = null # world/marks.gd (trail·block_pulse·neighbors)
var bodies = null # world/bodies.gd (shown)
var make_mat = null # Callable(Color) -> Material (G3 툰)
var third := func() -> bool: return false # 3인칭인가 (내 머리 위 표시)
var per := {} # id -> {ult, hunt, vuln, slow, amp, whirl, wait}
var auras := [] # {node, mat, t0, ms, grow, id}
var sparks := {} # id -> until (필살기 반짝이)
var waves := [] # {node, mat, t0}
var danger: MeshInstance3D
var ghosts := [] # 순간 베기 잔상 몸 {node, mat, t0} (G2 body.snapshot)
var ghost_next := {} # id -> 다음 잔상 시각
var slides = null # world/hook_fx.gd slides (미끄러지는 몸, to 가 있으면 순간 베기)
var xray_mat: StandardMaterial3D # 사냥꾼의 눈: 블록에 가린 부분만 빨갛게 (깊이 반대)
var _tex := {}


func _ready() -> void:
	Store.game_event.connect(on_event)
	danger = MeshInstance3D.new()
	danger.mesh = ring_mesh(0.42, 0.58, 24)
	var dm := _flat(0xff2020, 0.85)
	dm.no_depth_test = true
	dm.render_priority = 9
	danger.material_override = dm
	danger.visible = false
	add_child(danger)
	xray_mat = _flat(int(C.HUNT_EYE_COLOR))
	xray_mat.depth_test = BaseMaterial3D.DEPTH_TEST_INVERTED
	xray_mat.no_depth_test = false
	xray_mat.render_priority = 1


static func now_ms() -> float:
	return Time.get_ticks_msec() * 1.0


static func _flat(color: int, a := 1.0, add := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(Co.color(color), a)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 1.0 or add else BaseMaterial3D.TRANSPARENCY_DISABLED
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	return m


# 바닥에 눕힌 고리 (고도 xz 평면). arc: 호 각 (TAU = 한 바퀴), start: 시작 각
static func ring_mesh(inner: float, outer: float, seg := 40, arc := TAU, start := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := start + arc * i / seg
		var a1 := start + arc * (i + 1) / seg
		# 게임 각 a → 고도 (cos a, 0, -sin a)
		var p := [Vector3(cos(a0) * outer, 0, -sin(a0) * outer), Vector3(cos(a0) * inner, 0, -sin(a0) * inner), Vector3(cos(a1) * outer, 0, -sin(a1) * outer), Vector3(cos(a1) * inner, 0, -sin(a1) * inner)]
		for v in [p[0], p[1], p[2], p[2], p[1], p[3]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _burst(p: Vector3, dir, color: int, n: int, speed: float, size: float, life: float) -> void:
	if effects != null:
		effects.burst(p, dir, color, n, speed, size, life)


func _ring(p: Vector3, color: int, grow: float, life: float, horizontal := false) -> void:
	if effects != null:
		effects.ring(p, color, grow, life, horizontal)


func _shown(id):
	return bodies.shown.get(int(id)) if bodies != null and id != null else null


# ---------- 이벤트 ----------
func on_event(e: Dictionary) -> void:
	var t := str(e.get("type", ""))
	match t:
		"skill", "ult", "ultRefund":
			aura(e.get("who"), t != "skill")
		"glideRing": # 음유 천천히 낙하 음파 고리
			var p := Vector3(e.x, e.y, e.z + 0.9)
			var r := float(e.get("r", 1.5))
			_ring(p, int(C.BARD_NOTE_COLOR), r - 0.2, 0.3, true)
			_ring(p, 0xffffff, (r - 0.2) * 0.8, 0.22, true)
			_burst(p, null, int(C.BARD_NOTE_COLOR), 10, 3, 0.06, 0.3)
		"form": # 메탈 = 리프 충격파 + 끊어진 류트 줄, 음유 = 초록 치유파
			var s = _shown(e.get("who"))
			var p := Vector3(float(e.get("x", s.x if s != null else 0.0)), float(e.get("y", s.y if s != null else 0.0)), float(e.get("z", s.z if s != null else 0.0)) + 0.1)
			if str(e.get("form", "")) == "metal":
				var r := float(e.get("r", 1.8))
				_ring(p, 0xff3040, r * 2, 0.35, true)
				_ring(p + Vector3(0, 0, 1), 0x4060ff, r * 1.6, 0.3)
				_burst(p + Vector3(0, 0, 1), null, 0xff4050, 22, 6, 0.1, 0.4)
				_burst(p + Vector3(0, 0, 1.1), null, 0xf0e8d0, 6, 7, 0.04, 0.35)
				View.sound_cue.emit("blast", {"x": p.x, "y": p.y, "z": p.z, "big": false, "wood": false})
			else:
				_ring(p, 0x60ff90, 4, 0.5, true)
				_burst(p + Vector3(0, 0, 0.8), {"x": 0, "y": 0}, 0x80ffa0, 18, 2.5, 0.08, 0.9)
				for h in e.get("healed", []):
					var ts = _shown(h.get("id"))
					if ts != null:
						_burst(Vector3(ts.x, ts.y, ts.z + 1), {"x": 0, "y": 0}, 0x80ffa0, 14, 2, 0.08, 1.0)
		"song": # 앞 부채꼴로 분홍 음표 물결 + 걸린 사람마다 분홍 번쩍
			var half := deg_to_rad(C.BARD_SONG_ANGLE_DEG / 2)
			for k in 14:
				var ang: float = e.yaw + (randf() * 2 - 1) * half
				var r := 0.8 + randf() * 1.2
				_burst(Vector3(e.x + cos(ang) * r, e.y + sin(ang) * r, e.z + 0.9 + randf() * 0.6), {"x": cos(ang) * 1.5, "y": sin(ang) * 1.5}, 0xff6ad5, 1, 4, 0.08, 0.6)
			_ring(Vector3(e.x, e.y, e.z + 1), 0xff6ad5, C.BARD_SONG_RANGE * 0.9, 0.4)
			for id in e.get("targets", []):
				var ts = _shown(id)
				if ts != null:
					_burst(Vector3(ts.x, ts.y, ts.z + 1.4), null, 0xff6ad5, 12, 3, 0.08, 0.5)
		"ampEnd": # 앞 원뿔 끝까지 큰 전격 쾅
			var r: float = C.BARD_AMP_RANGE * 0.6
			var p := Vector3(e.x + cos(e.yaw) * r, e.y + sin(e.yaw) * r, e.z + 1)
			_ring(p, int(C.BARD_AMP_COLOR), 4, 0.35)
			_burst(p, {"x": cos(e.yaw) * 1.5, "y": sin(e.yaw) * 1.5}, 0xffffff, 26, 8, 0.08, 0.35)
			_burst(p, null, int(C.BARD_AMP_COLOR), 20, 5, 0.1, 0.5)
			View.sound_cue.emit("blast", {"x": p.x, "y": p.y, "z": p.z, "big": true, "wood": false})
		"rushLand": # 광전사 도약 착지
			var p := Vector3(e.x, e.y, e.z + 0.08)
			_ring(p, 0xffc080, float(e.get("r", 1.5)) * 2, 0.35, true)
			_burst(p, null, 0x9a8a78, 22, 4.5, 0.14, 0.6)
			if marks != null:
				var under := []
				for c in marks.neighbors([[floori(e.x), floori(e.y), floori(e.z)]]):
					if c[2] < floori(e.z + 0.01):
						under.append(c)
				marks.block_pulse(under, 0xffffff, C.BLOCK_PULSE_MS, -C.BLOCK_JOLT, 0.35)
			View.sound_cue.emit("blast", {"x": p.x, "y": p.y, "z": p.z, "big": false, "wood": false})
		"spinEnd": # 광전사 소용돌이 끝 (어지러움 별은 G2 몸)
			var p := Vector3(e.x, e.y, e.z + 0.08)
			var r := float(e.get("r", 2))
			_ring(p, 0xff7040, r * 2.2, 0.4, true)
			_ring(Vector3(e.x, e.y, e.z + 0.9), 0xffffff, r * 1.6, 0.3)
			_burst(Vector3(e.x, e.y, e.z + 0.6), null, 0xffb060, 26, 7, 0.13, 0.45)
			_burst(p, null, 0x9a8a78, 18, 4, 0.14, 0.6)
			View.sound_cue.emit("blast", {"x": p.x, "y": p.y, "z": p.z, "big": float(e.get("rage", 1)) > 1.3, "wood": false})


# 스킬·필살기 빛: 발밑 고리가 퍼짐 (스킬 하양 순간, 필살기 하늘색 두 겹 + 반짝이). 캐릭터를 따라다님
func aura(id, ult: bool) -> void:
	if id == null or _shown(id) == null:
		return
	var color := int(C.ULT_AURA_COLOR if ult else C.SKILL_AURA_COLOR)
	var ms: float = C.ULT_AURA_MS if ult else C.SKILL_AURA_MS
	var now := now_ms()
	for delay in ([0.0, ms * 0.25] if ult else [0.0]):
		var mat := _flat(color, 0.85)
		var n := _mi(ring_mesh(0.5, 0.58), mat)
		n.visible = false
		add_child(n)
		auras.append({"node": n, "mat": mat, "t0": now + delay, "ms": ms * 0.6, "grow": 2.6 if ult else 1.8, "id": id})
	if ult:
		sparks[int(id)] = now + ms


# ---------- 매 프레임 ----------
func update(st: Dictionary, my_id, dt: float) -> void:
	var now := now_ms()
	var seen := {}
	for p in st.get("players", []):
		var id := int(p.id)
		seen[id] = true
		var s = _shown(id)
		if s == null:
			continue
		var d: Dictionary = per.get(id, {})
		per[id] = d
		var mine: bool = my_id != null and id == int(my_id)
		_ult_ready(d, p, s, mine, dt)
		_hunt(d, p, s, my_id, mine, now)
		_status(d, p, s, mine, now)
		_amp(d, p, s, dt, now)
		_whirl(d, p, s, dt)
		_wait(d, p, s, now)
		if sparks.has(id):
			if now > sparks[id] or not p.alive:
				sparks.erase(id)
			elif randf() < dt * 40:
				var a := randf() * TAU
				_burst(Vector3(s.x + cos(a) * 0.45, s.y + sin(a) * 0.45, s.z + randf() * 1.2), {"x": 0, "y": 0}, int(C.ULT_AURA_COLOR), 1, 1.5, 0.06, 0.5)
	for id in per.keys():
		if not seen.has(id):
			for k in per[id]:
				if per[id][k] is Dictionary and per[id][k].has("node"):
					per[id][k].node.queue_free()
			per.erase(id)
	for i in range(auras.size() - 1, -1, -1):
		var a: Dictionary = auras[i]
		var s = _shown(a.id)
		var u: float = (now - a.t0) / a.ms
		if u >= 1 or s == null:
			a.node.queue_free()
			auras.remove_at(i)
			continue
		a.node.visible = u >= 0
		if u < 0:
			continue
		a.node.position = Co.gxyz(s.x, s.y, s.z + 0.04)
		var sc: float = 1 + a.grow * u
		a.node.scale = Vector3(sc, 1, sc)
		a.mat.albedo_color.a = 0.85 * (1 - u)
	for i in range(waves.size() - 1, -1, -1):
		var w: Dictionary = waves[i]
		var u: float = (now - w.t0) / C.BARD_AMP_WAVE_LIFE_MS
		if u >= 1:
			w.node.queue_free()
			waves.remove_at(i)
			continue
		var sc: float = 0.4 + u * (C.BARD_AMP_RANGE - 0.4)
		w.node.scale = Vector3(sc, 1, sc)
		w.mat.albedo_color.a = 0.8 * (1 - u)
	_ghosts(st, now)
	# 내 발밑 위험 고리: 떨어지는 블록이 내 머리 위 (me.danger)
	var me := Store.me()
	var ms = _shown(my_id) if my_id != null else null
	danger.visible = ms != null and not me.is_empty() and me.alive and me.get("danger") != null
	if danger.visible:
		danger.position = Co.gxyz(ms.x, ms.y, ms.z + 0.04)
		var k := 1 + 0.25 * sin(now / 60.0)
		danger.scale = Vector3(k, 1, k)


# R 게이지가 찬 상대: 발밑~몸 둘레에 옅은 하늘색 빛 (나는 안 그림)
func _ult_ready(d: Dictionary, p: Dictionary, s: Vector3, mine: bool, dt: float) -> void:
	var full: bool = p.alive and not p.get("master", false) and str(p.get("char", "")) != "" and not mine and float(p.get("ult", 0)) >= float(p.get("ultMax", C.ULT_MAX) if p.get("ultMax") != null else C.ULT_MAX)
	if not full:
		if d.has("ult"):
			d.ult.node.visible = false
		return
	if not d.has("ult"):
		var g := Node3D.new()
		var h: float = C.PLAYER_HEIGHT * 1.1
		var cy := CylinderMesh.new()
		cy.top_radius = 0.42
		cy.bottom_radius = 0.5
		cy.height = h
		cy.radial_segments = 20
		cy.cap_top = false
		cy.cap_bottom = false
		var wall_mat := _flat(int(C.ULT_AURA_COLOR), C.ULT_READY_AURA_OPACITY, true)
		wall_mat.albedo_texture = _grad("wall")
		var wall := _mi(cy, wall_mat)
		wall.position.y = h / 2
		var floor_mat := _flat(int(C.ULT_AURA_COLOR), C.ULT_READY_AURA_OPACITY, true)
		floor_mat.albedo_texture = _grad("floor")
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.5, 1.5)
		var fl := _mi(pm, floor_mat)
		fl.position.y = 0.03
		g.add_child(wall)
		g.add_child(fl)
		add_child(g)
		d.ult = {"node": g, "mats": [wall_mat, floor_mat]}
	d.ult.node.visible = true
	d.ult.node.position = Co.gpos(s)
	var breathe := 0.75 + 0.25 * sin(now_ms() / 420.0)
	for m in d.ult.mats:
		m.albedo_color.a = C.ULT_READY_AURA_OPACITY * breathe
	if randf() < dt * C.ULT_READY_SPARKLE_RATE:
		var a := randf() * TAU
		_burst(Vector3(s.x + cos(a) * 0.4, s.y + sin(a) * 0.4, s.z + 0.2 + randf() * 0.8), {"x": 0, "y": 0}, int(C.ULT_AURA_COLOR), 1, 0.6, 0.05, 0.6)


# 빛기둥 옆면 (아래가 밝고 위로 사라짐) / 바닥 (가운데가 밝은 원)
func _grad(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var g := Gradient.new()
	var t := GradientTexture2D.new()
	t.gradient = g
	if kind == "wall":
		g.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 1)]) # 위 (v 0) → 아래 (v 1)
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(0, 1)
		t.width = 4
		t.height = 64
	else:
		g.offsets = PackedFloat32Array([0.0, 0.0625, 0.7, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
	_tex[kind] = t
	return t


func _label(text: String, color: Color, outline: Color, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = px
	l.font_size = 48
	l.outline_size = 12
	l.modulate = color
	l.outline_modulate = outline
	l.render_priority = 12
	add_child(l)
	return l


# 분홍 음표 (머리·기둥·깃발 두 개 = 이어진 8분음표 둘), 화면을 덮지 않게 작게
func _note() -> Node3D:
	var g := Node3D.new()
	var mat := _flat(0xff6ad5)
	mat.no_depth_test = false
	for k in 2:
		var hm := SphereMesh.new()
		hm.radius = 0.08
		hm.height = 0.12
		var head := _mi(hm, mat)
		head.position = Vector3(-0.1 + k * 0.2, 0, 0)
		g.add_child(head)
		var sm := BoxMesh.new()
		sm.size = Vector3(0.025, 0.28, 0.025)
		var stem := _mi(sm, mat)
		stem.position = Vector3(-0.03 + k * 0.2, 0.14, 0)
		g.add_child(stem)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.04, 0.025)
	var beam := _mi(bm, mat)
	beam.position = Vector3(0.07, 0.27, 0)
	g.add_child(beam)
	add_child(g)
	return g


# 사냥꾼 표식: 머리 위 이름표 위에 빨간 마름모 1~3개, 사라지기 직전 깜빡. 내가 붙인 것이 있으면 그것 (블록 뒤에서도 보임), 없으면 가장 많은 것
func _hunt(d: Dictionary, p: Dictionary, s: Vector3, my_id, mine: bool, now: float) -> void:
	var list: Array = p.get("marks", [])
	var m = null
	var by_me := false
	for x in list:
		if my_id != null and x.get("by") != null and int(x.by) == int(my_id):
			m = x
			by_me = true
	if m == null:
		for x in list:
			if m == null or x.n > m.n:
				m = x
	if m == null and not d.has("hunt"):
		return
	if not d.has("hunt"):
		d.hunt = {"node": _label("", Color8(0xff, 0x3a, 0x2a), Color8(0x30, 0, 0), 0.0012)}
	var l: Label3D = d.hunt.node
	var n: int = mini(int(C.HUNTER_MARK_MAX), int(m.n)) if m != null and p.alive else 0
	var blink: bool = m != null and float(m.get("left", 0)) < C.MARK_BLINK_MS and int(floor(now / C.MARK_BLINK_PERIOD_MS)) % 2 == 1
	_hunt_eye(d, p, by_me and p.alive and not mine)
	l.text = "◆".repeat(n)
	l.visible = n > 0 and not blink and not (mine and not third.call())
	l.no_depth_test = by_me
	l.position = Co.gxyz(s.x, s.y, s.z + C.PLAYER_HEIGHT + C.LABEL_ABOVE_HEAD + 0.75)


# 사냥꾼의 눈: 내가 표식을 붙인 대상 몸이 블록 너머에서 빨갛게 (몸 위 한 겹, G2 body.set_overlay). 바뀔 때만 부름
func _hunt_eye(d: Dictionary, p: Dictionary, on: bool) -> void:
	if d.get("eye", false) == on or bodies == null:
		return
	var n: Dictionary = bodies.nodes.get(int(p.id), {})
	if n.is_empty() or not n.body.has_method("set_overlay"):
		return
	n.body.set_overlay(xray_mat if on else null)
	d.eye = on


# 순간 베기 잔상: 미끄러지는 동안 BLINK_GHOST_MS 마다 지금 자세 복사본 (그 사람 색 반투명) 이 남아 BLINK_GHOST_FADE_MS 동안 사라짐
func _ghosts(st: Dictionary, now: float) -> void:
	if slides != null and bodies != null:
		for id in slides:
			var sl: Dictionary = slides[id]
			if sl.get("to") == null:
				continue # 갈고리에 끌려오는 몸은 잔상 없음
			if now < ghost_next.get(id, 0.0):
				continue
			ghost_next[id] = now + C.BLINK_GHOST_MS
			var n: Dictionary = bodies.nodes.get(int(id), {})
			if n.is_empty() or not n.body.has_method("snapshot"):
				continue
			var p := Store.player(id)
			var mat := _flat(bodies.player_color(p, st) if not p.is_empty() else 0xffffff, 0.4)
			mat.no_depth_test = false
			var g: Node3D = n.body.snapshot(mat)
			add_child(g)
			g.global_transform = n.body.global_transform
			ghosts.append({"node": g, "mat": mat, "t0": now})
	for i in range(ghosts.size() - 1, -1, -1):
		var gh: Dictionary = ghosts[i]
		var u: float = (now - gh.t0) / C.BLINK_GHOST_FADE_MS
		if u >= 1:
			gh.node.queue_free()
			ghosts.remove_at(i)
			continue
		gh.mat.albedo_color.a = 0.4 * (1 - u)


# 취약: 머리 위 분홍 음표 통통 / 둔화: 발밑 옅은 파란 소용돌이
func _status(d: Dictionary, p: Dictionary, s: Vector3, mine: bool, now: float) -> void:
	var vuln: bool = p.alive and float(p.get("vulnLeft", 0)) > 0
	var slow: bool = p.alive and float(p.get("slowLeft", 0)) > 0
	if not d.has("vuln") and not vuln and not slow:
		return
	if not d.has("vuln"):
		d.vuln = {"node": _note()}
		var ring := _mi(ring_mesh(0.42, 0.5, 24, PI * 1.5), _flat(0x6aa8ff, 0.35))
		add_child(ring)
		d.slow = {"node": ring}
	var l: Node3D = d.vuln.node
	l.visible = vuln and not (mine and not third.call())
	if l.visible:
		l.position = Co.gxyz(s.x, s.y, s.z + C.PLAYER_HEIGHT + C.LABEL_ABOVE_HEAD + 0.75 + 0.25 * absf(sin(now / 160.0)))
		l.rotation.y = now / 500.0
	var r: MeshInstance3D = d.slow.node
	r.visible = slow
	if slow:
		r.position = Co.gxyz(s.x, s.y, s.z + 0.04)
		r.rotation.y = Co.rot_y(-now / 300.0)


# 메탈 R 앰프: 뒤에서 한 박자 늦게 따라오는 앰프 + 앞 원뿔로 퍼지는 음파 호 + 전격 줄
func _amp(d: Dictionary, p: Dictionary, s: Vector3, dt: float, now: float) -> void:
	var bard = p.get("bard")
	var on: bool = bard != null and float(bard.get("ampLeft", 0)) > 0 and p.alive
	if not on and not d.has("amp"):
		return
	if not d.has("amp"):
		var cab := Node3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 0.7, 0.6) # 게임 (x 0.45, y 0.6, z 0.7) → 고도 (x, z 높이, y)
		cab.add_child(_mi(box, make_mat.call(Co.color(0x1a1a1e)) if make_mat != null else _flat(0x1a1a1e)))
		var grille := _mi(ring_mesh(0.0, 0.2, 16), _flat(0x3a3a44))
		grille.rotation.z = PI / 2
		grille.position = Vector3(0.23, 0.05, 0)
		cab.add_child(grille)
		var edge := BoxMesh.new()
		edge.size = Vector3(0.47, 0.05, 0.62)
		var em := _mi(edge, make_mat.call(Co.color(0xd8202a)) if make_mat != null else _flat(0xd8202a))
		em.position.y = 0.33
		cab.add_child(em)
		add_child(cab)
		d.amp = {"node": cab, "x": s.x, "y": s.y, "bolt": 0.0, "wave": 0.0}
	var a: Dictionary = d.amp
	a.node.visible = on
	if not on:
		return
	var yaw: float = float(bard.ampYaw) if bard.get("ampYaw") != null else float(p.yaw)
	var back := yaw + PI * 0.75 # 몸 왼쪽 뒤 비스듬히 1.1칸으로 늦게 따라옴, 바닥에 놓인 채 통통
	var k := 1 - exp(-6 * dt)
	a.x += (s.x + cos(back) * 1.1 - a.x) * k
	a.y += (s.y + sin(back) * 1.1 - a.y) * k
	a.node.position = Co.gxyz(a.x, a.y, s.z + 0.35 + absf(sin(now / 90.0)) * 0.06)
	a.node.rotation.y = Co.rot_y(yaw)
	a.wave += dt * 1000
	if a.wave >= C.BARD_AMP_WAVE_MS:
		a.wave = 0.0
		var half := deg_to_rad(C.BARD_AMP_ANGLE_DEG / 2)
		for dz in [0.75, 1.3]:
			var mat := _flat(int(C.BARD_AMP_COLOR), 0.8)
			var m := _mi(ring_mesh(0.86, 1.0, 20, half * 2, -half), mat)
			m.position = Co.gxyz(s.x, s.y, s.z + dz)
			m.rotation.y = Co.rot_y(yaw)
			add_child(m)
			waves.append({"node": m, "mat": mat, "t0": now})
	a.bolt += dt * 14
	while a.bolt >= 1 and marks != null:
		a.bolt -= 1
		var ang := yaw + (randf() - 0.5) * deg_to_rad(C.BARD_AMP_ANGLE_DEG)
		var r1 := 0.6 + randf() * (C.BARD_AMP_RANGE - 1.2)
		var r2 := r1 + 0.4 + randf() * 0.5
		var z := s.z + 0.6 + randf() * 0.8
		marks.trail(Vector3(s.x + cos(ang) * r1, s.y + sin(ang) * r1, z), Vector3(s.x + cos(ang + 0.08) * r2, s.y + sin(ang + 0.08) * r2, z + (randf() - 0.5) * 0.4), 0xffffff if randf() < 0.5 else int(C.BARD_AMP_COLOR), 90)


# 광전사 소용돌이: 발밑 빨간 범위 고리 + 도끼 높이에서 빙글 도는 궤적 호 + 몸 둘레 바람
func _whirl(d: Dictionary, p: Dictionary, s: Vector3, dt: float) -> void:
	var bz = p.get("berserker")
	var on: bool = bz != null and float(bz.get("spinLeft", 0)) > 0 and p.alive
	if not on and not d.has("whirl"):
		return
	if not d.has("whirl"):
		var r: float = C.BERSERKER_SPIN_RANGE
		var g := Node3D.new()
		var ring := _mi(ring_mesh(r - 0.07, r), _flat(int(C.BERSERK_SPIN_RING_COLOR), 0.55))
		var disc := _mi(ring_mesh(0.0, r - 0.07), _flat(int(C.BERSERK_SPIN_RING_COLOR), 0.12))
		g.add_child(ring)
		g.add_child(disc)
		var tr := _mi(ring_mesh(r * 0.55, r * 0.95, 32, PI * 1.2), _flat(0xffffff, 0.6))
		add_child(g)
		add_child(tr)
		d.whirl = {"node": g, "trail": tr}
	var w: Dictionary = d.whirl
	w.node.visible = on
	w.trail.visible = on
	if not on:
		return
	w.node.position = Co.gxyz(s.x, s.y, s.z + 0.04)
	w.trail.position = Co.gxyz(s.x, s.y, s.z + 0.9)
	w.trail.rotation.y -= dt * TAU * C.BERSERK_SPIN_TURNS_PER_S
	if randf() < dt * 30:
		var ang := randf() * TAU
		_burst(Vector3(s.x + cos(ang) * 0.5, s.y + sin(ang) * 0.5, s.z + 1.3 + randf() * 0.5), {"x": cos(ang) * 1.2, "y": sin(ang) * 1.2}, 0xffffff, 1, 2.5, 0.06, 0.25)


# 조종 대기 표시: 조종권은 있는데 아직 조종 안 함 → 머리 위 청록 팔면체가 빙글
func _wait(d: Dictionary, p: Dictionary, s: Vector3, now: float) -> void:
	var on: bool = p.alive and p.get("hasControl", false) and not p.get("controlling", false)
	if not on and not d.has("wait"):
		return
	if not d.has("wait"):
		var sp := SphereMesh.new() # 팔면체 자리 (작은 마름모)
		sp.radial_segments = 4
		sp.rings = 2
		sp.radius = 0.12
		sp.height = 0.24
		d.wait = {"node": _mi(sp, _flat(0x20e0e0))}
		add_child(d.wait.node)
	var n: MeshInstance3D = d.wait.node
	n.visible = on
	if on:
		n.position = Co.gxyz(s.x, s.y, s.z + C.PLAYER_HEIGHT + 0.2)
		n.rotation.y = now / 400.0
