# 판 쪽 연출 (render.js 의 renderer.* 중 판에 남는 것, main.js handleEvent 가 부르던 자리를 이벤트로 받음):
# 잔상 줄 trail · 위로 솟는 줄 streakUp · 예고 칸 markCells · 예고 원 markCircle (+ updateMarks 깜빡·사라짐)
# · 블록 출렁 blockPulse (+ blockNeighbors) · 탱크 R 솟는 땅 quakeRise·quakeFall·clearQuakes · 압사 납작 몸 crushFlat · 녹음 melt · 유령 투하 펑 ghostDropFx
# 파편·고리는 G5 fx 의 effects (World 가 넣어 줌, 없으면 안 냄). 몸 동작·흔들림·KO 는 G2·G5 몫
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")

var effects = null # G5 fx/effects.gd (burst·ring), 없으면 null
var solid: Callable # World.solid_at (blockNeighbors)
var bodies = null # world/bodies.gd (crushFlat 이 몸을 복제)
var marks := [] # {node, until, ms, pulse, grow, mats}
var pulses := [] # {node, mat, t0, ms, jolt, base, opacity}
var quakes := [] # {id, cells, t0, ms, sink_at, nodes}
var flats := [] # {node, t0}
var _pulse_mesh: BoxMesh
var _quake_mat: Material
var make_mat = null # Callable(Color) -> Material (G3 툰, 솟는 땅), 없으면 StandardMaterial3D


func _ready() -> void:
	_pulse_mesh = BoxMesh.new()
	_pulse_mesh.size = Vector3.ONE * 1.04
	Store.game_event.connect(on_event)


static func now_ms() -> float:
	return Time.get_ticks_msec() * 1.0


static func flat_mat(color: int, opacity: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_fog = true
	m.albedo_color = Color(Co.color(color), opacity)
	m.render_priority = 8
	return m


func _p(id) -> Dictionary:
	return Store.player(id) if id != null else {}


# ---------- 이벤트 (main.js handleEvent 의 renderer.* 줄) ----------
func on_event(e: Dictionary) -> void:
	var t := str(e.get("type", ""))
	match t:
		"leapWarn": # 사냥꾼 추적 도약 예고: 덮칠 대상까지 바닥에 빨간 줄
			var a := _p(e.get("who"))
			var tg := _p(e.get("target"))
			if not a.is_empty() and not tg.is_empty():
				trail(Vector3(a.x, a.y, a.z + 0.08), Vector3(tg.x, tg.y, tg.z + 0.08), 0xff3020, float(e.get("ms", 0)) + C.HUNTER_LEAP_MS)
		"blink": # 닌자 순간 베기: 지나간 길에 흰 줄 (+ blinkSlide 의 바람 줄 셋)
			trail(Vector3(e.from.x, e.from.y, e.to.z + 0.9), Vector3(e.to.x, e.to.y, e.to.z + 0.9), 0xffffff, 280)
			for dz in [0.35, 0.9, 1.4]:
				trail(Vector3(e.from.x, e.from.y, e.to.z + dz), Vector3(e.to.x, e.to.y, e.to.z + dz), 0xffffff, 260 + dz * 60)
		"wallKick": # 닌자 벽 차기: 위로 솟는 줄
			streak_up(Vector3(e.x, e.y, e.z + 0.2), 2.4, 0xffffff, 300)
		"quakeRise":
			quake_rise(e.cells, float(e.get("ms", C.TANK_RING_MS)), e.get("id"))
		"quakeFall":
			var g = e.get("gone") if e.get("gone") != null else e.get("cells")
			quake_fall(g if g != null else [], e.get("id"))
		"mapChange":
			clear_quakes()
		"ninjaTouch": # 닌자가 밟은 떨어지는 블록이 번쩍하며 꾹 눌림
			for pc in Store.state.get("pieces", []):
				if pc.get("id") == e.get("piece"):
					block_pulse(pc.cells, 0xffffff, C.BLOCK_PULSE_MS * 0.8, -C.BLOCK_JOLT * 1.5, 0.6)
		"charge": # 탱크 방패 돌진: 가는 길에 흙먼지 줄
			trail(Vector3(e.x, e.y, e.z + 0.15), Vector3(e.x + cos(e.yaw) * 3, e.y + sin(e.yaw) * 3, e.z + 0.15), 0xc0a070, 400)
		"slamWarn": # 탱크 내려찍기: 떨어질 범위
			mark_circle(e.x, e.y, e.z, e.r, 0xff3020, float(e.ms) + C.WARN_TAIL_MS)
		"wallWarn": # 건축가 솟는 벽: 솟을 자리를 노랗게
			mark_cells(e.cells, 0xffd23a, float(e.ms))
		"hook": # 갈고리가 블록에 걸림: 블록이 들썩 + 끌려가는 길에 바람 줄
			if e.get("target") == null and e.get("block") != null:
				block_pulse([e.block], 0xffffff, C.BLOCK_PULSE_MS, 0.08, 0.75)
				var a := _p(e.get("who"))
				if not a.is_empty():
					var c := Vector3(e.block[0] + 0.5, e.block[1] + 0.5, e.block[2] + 0.5)
					for dz in [0.4, 0.9, 1.4]:
						trail(Vector3(a.x, a.y, a.z + dz), Vector3(c.x, c.y, a.z + dz), 0xffffff, 300)
		"ghostDrop": # 유령 블록 생김: 그 사람 색 연기 펑 + 하얀 고리
			if effects != null:
				var pos := Vector3(e.x + 0.5, e.y + 0.5, e.z + 0.5)
				var ci = e.get("color", e.get("slot", 0))
				var col := int(C.PLAYER_PALETTE[int(ci if ci != null else 0) % C.PLAYER_PALETTE.size()])
				effects.burst(pos, null, col, 14, 2.5, 0.14, 0.6)
				effects.burst(pos, null, 0xffffff, 10, 1.6, 0.1, 0.5)
				effects.ring(pos, 0xffffff, 1.4, 0.3, true)
		"melt": # 하늘 계단 블록이 용암에 녹음
			var cells := []
			for c in e.get("cells", []):
				cells.append(c)
			if not cells.is_empty():
				block_pulse(cells, 0xff7020, C.BLOCK_PULSE_MS * 1.6, 0.0, 0.8)
				if effects != null:
					for c in cells:
						var p := Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.3)
						effects.burst(p, null, 0xffa030, 6, 3, 0.08, 0.4)
						effects.burst(p + Vector3(0, 0, 0.4), {"x": 0, "y": 0}, 0x555555, 5, 1.2, 0.18, 1.1)
		"land": # 내려앉은 블록이 꾹 눌렸다 돌아옴 + 받친 블록도 살짝
			var cz := INF
			for c in e.cells:
				cz = minf(cz, c[2])
			block_pulse(e.cells, 0xffffff, C.BLOCK_PULSE_MS, -C.LAND_JOLT, 0.35)
			var under := []
			for c in neighbors(e.cells):
				if c[2] < cz:
					under.append(c)
			block_pulse(under, 0xffffff, C.BLOCK_PULSE_MS, -C.LAND_JOLT, 0.2)
		"death":
			if str(e.get("cause", "")) == "crush":
				crush_flat(e.get("who"))


# 판 시작·끝 (서버가 솟은 땅을 이벤트 없이 버림): World 가 phase 가 바뀔 때 부름
func phase_changed() -> void:
	clear_quakes()


# ---------- 표시 (render.js addMark·trail·streakUp·markCells·markCircle·updateMarks) ----------
func add_mark(node: Node3D, ms: float, pulse := true, grow := 0.0) -> void:
	add_child(node)
	var mats := []
	for n in [node] + node.find_children("*", "MeshInstance3D", true, false):
		if n is MeshInstance3D and n.material_override is StandardMaterial3D:
			mats.append([n.material_override, n.material_override.albedo_color.a])
	marks.append({"node": node, "until": now_ms() + ms, "ms": ms, "pulse": pulse, "grow": grow, "mats": mats})


func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# 두 점 사이 잔상 (베기·돌진): 가는 막대, 서서히 사라짐
func trail(a: Vector3, b: Vector3, color: int, ms: float) -> void:
	var len := maxf(0.01, a.distance_to(b))
	var bm := BoxMesh.new()
	bm.size = Vector3(len, 0.08, 0.08) # 게임 x 방향 막대 → 고도에선 x 그대로 (z 위 = 고도 y)
	var m := _mi(bm, flat_mat(color, 0.85))
	var mid := (a + b) / 2.0
	m.position = Co.gpos(mid)
	# 게임 바닥 방향 (atan2) 으로 돌리고 높낮이도 기울임
	var yaw := atan2(b.y - a.y, b.x - a.x)
	var pitch := atan2(b.z - a.z, Vector2(b.x - a.x, b.y - a.y).length())
	m.basis = Basis(Vector3.UP, Co.rot_y(yaw)) * Basis(Vector3(0, 0, 1), pitch)
	add_mark(m, ms, false)


# 위로 솟는 줄 (벽 차기)
func streak_up(a: Vector3, len: float, color: int, ms: float) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, len, 0.1)
	var m := _mi(bm, flat_mat(color, 0.85))
	m.position = Co.gxyz(a.x, a.y, a.z + len / 2.0)
	add_mark(m, ms, false)


# 칸들 바닥 (기둥마다 맨 아래 높이) 에 색 판
func mark_cells(cells: Array, color: int, ms: float) -> void:
	var low := {}
	for c in cells:
		var k := int(c[0]) * 100 + int(c[1])
		if not low.has(k) or c[2] < low[k][2]:
			low[k] = c
	var pm := PlaneMesh.new()
	pm.size = Vector2(WC.MARK_CELL, WC.MARK_CELL)
	for c in low.values():
		var m := _mi(pm, flat_mat(color, 0.6))
		m.position = Co.gxyz(c[0] + 0.5, c[1] + 0.5, c[2] + 0.05)
		add_mark(m, ms)


# 바닥에 둥근 범위 (테두리 + 옅은 속)
func mark_circle(x: float, y: float, z: float, r: float, color: int, ms: float) -> void:
	var g := Node3D.new()
	g.position = Co.gxyz(x, y, z + 0.06)
	var ring := _mi(disc_mesh(r - 0.12, r), flat_mat(color, 0.9))
	var fill := _mi(disc_mesh(0.0, r), flat_mat(color, 0.22))
	g.add_child(ring)
	g.add_child(fill)
	add_mark(g, ms)


# 바닥에 눕힌 고리 (inner 0 이면 원판), 고도 xz 평면
static func disc_mesh(inner: float, outer: float, seg := 40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var o0 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		var i0 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		for v in [o0, i0, o1, o1, i0, i1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


# ---------- 블록 출렁 (render.js blockPulse·blockNeighbors·updatePulses) ----------
func block_pulse(cells: Array, color := 0xffffff, ms: float = C.BLOCK_PULSE_MS, jolt := 0.0, opacity := 0.75) -> void:
	if cells.is_empty():
		return
	var mat := flat_mat(color, opacity)
	mat.render_priority = 5
	for c in cells:
		if c == null or c.size() < 3:
			continue
		var m := _mi(_pulse_mesh, mat)
		m.position = Co.gxyz(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5)
		add_child(m)
		pulses.append({"node": m, "mat": mat, "t0": now_ms(), "ms": ms, "jolt": jolt, "base": c[2] + 0.5, "opacity": opacity, "xy": Vector2(c[0] + 0.5, c[1] + 0.5)})


# cells 바로 옆 (6방향) 에 붙은 격자 블록
func neighbors(cells: Array) -> Array:
	var own := {}
	for c in cells:
		own[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = true
	var out := {}
	for c in cells:
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var q: Vector3i = Vector3i(int(c[0]), int(c[1]), int(c[2])) + d
			if q.z >= 0 and not own.has(q) and solid.is_valid() and solid.call(q.x + 0.5, q.y + 0.5, q.z + 0.5):
				out[q] = [q.x, q.y, q.z]
	return out.values()


# ---------- 탱크 R 솟는 땅 (render.js quakeRise·quakeFall·clearQuakes·updateQuakes) ----------
func quake_rise(cells: Array, ms: float, id) -> void:
	if _quake_mat == null:
		if make_mat != null:
			_quake_mat = make_mat.call(Co.color(C.QUAKE_COLOR))
		else:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Co.color(C.QUAKE_COLOR)
			_quake_mat = sm
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var nodes := []
	for c in cells:
		var m := MeshInstance3D.new()
		m.mesh = bm
		m.material_override = _quake_mat
		m.set_meta("cell", c)
		add_child(m)
		nodes.append(m)
	quakes.append({"id": id, "cells": cells, "t0": now_ms(), "ms": ms, "sink_at": 0.0, "nodes": nodes})
	block_pulse(cells, 0xffe8c0, C.QUAKE_RISE_MS + 120, 0.0, 0.5)


# id 로 맞춰 가라앉힘. id 가 없으면 칸으로, 못 맞추면 가장 먼저 솟은 것 (화면에만 남는 유령 블록이 안 되게)
func quake_fall(cells: Array, id) -> void:
	var now := now_ms()
	if id != null:
		for q in quakes:
			if q.id == id and q.sink_at == 0.0:
				q.sink_at = now
		return
	var gone := {}
	for c in cells:
		gone[str(c)] = true
	var any := false
	for q in quakes:
		if q.sink_at == 0.0:
			for c in q.cells:
				if gone.has(str(c)):
					q.sink_at = now
					any = true
					break
	if not any:
		for q in quakes:
			if q.sink_at == 0.0:
				q.sink_at = now
				break


func clear_quakes() -> void:
	for q in quakes:
		for n in q.nodes:
			n.queue_free()
	quakes.clear()


# ---------- 압사 납작 몸 (render.js crushFlat·updateFlats) ----------
func crush_flat(who) -> void:
	if bodies == null or who == null or not bodies.nodes.has(int(who)):
		return
	var n: Dictionary = bodies.nodes[int(who)]
	var root: Node3D = n.root
	var flat: Node3D = root.duplicate(0) # 몸 노드 그대로 복제 (스크립트 없이 — 지금 자세로 굳음)
	for l in flat.find_children("*", "Label3D", true, false):
		l.queue_free()
	flat.visible = true
	flat.top_level = true
	add_child(flat)
	flat.global_transform = root.global_transform
	flat.position += Vector3(0, 0.02, 0)
	flat.set_meta("base", flat.basis)
	flats.append({"node": flat, "t0": now_ms()})
	_flat_scale(flat, 1.5, C.CRUSH_FLAT_Z)


func _flat_scale(f: Node3D, s: float, z: float) -> void:
	f.basis = (f.get_meta("base") as Basis).orthonormalized() * Basis().scaled(Vector3(s, z, s)) # 게임 z (위) = 고도 y


# ---------- 매 프레임 ----------
func step() -> void:
	var now := now_ms()
	for i in range(marks.size() - 1, -1, -1):
		var mk: Dictionary = marks[i]
		var left: float = mk.until - now
		if left <= 0:
			mk.node.queue_free()
			marks.remove_at(i)
			continue
		var k: float = 0.7 + 0.3 * sin(now / maxf(40.0, left / 6.0)) if mk.pulse else left / mk.ms
		if mk.grow > 0:
			var sc: float = 1 + mk.grow * (1 - left / mk.ms)
			mk.node.scale = Vector3(sc, mk.node.scale.y, sc)
		for pair in mk.mats:
			pair[0].albedo_color.a = pair[1] * k
	for i in range(pulses.size() - 1, -1, -1):
		var p: Dictionary = pulses[i]
		var u: float = (now - p.t0) / p.ms
		if u >= 1:
			p.node.queue_free()
			pulses.remove_at(i)
			continue
		p.node.scale = Vector3.ONE * (1 + 0.25 * u)
		p.node.position = Co.gxyz(p.xy.x, p.xy.y, p.base + p.jolt * sin(PI * minf(1.0, u * 2)))
		p.mat.albedo_color.a = p.opacity * (1 - u) * (1 - u)
	for i in range(quakes.size() - 1, -1, -1):
		var q: Dictionary = quakes[i]
		if q.sink_at == 0.0 and q.id == null and now - q.t0 > q.ms + C.QUAKE_FALL_GRACE_MS:
			q.sink_at = now
		var h: float
		if q.sink_at > 0.0:
			var u: float = (now - q.sink_at) / C.QUAKE_SINK_MS
			if u >= 1:
				for n in q.nodes:
					n.queue_free()
				quakes.remove_at(i)
				continue
			h = 1 - u * u
		else:
			var u := minf(1.0, (now - q.t0) / C.QUAKE_RISE_MS)
			h = 1 + 0.3 * sin(PI * u) - (1 - u) * (1 - u) if u < 1 else 1.0
		var shake: float = C.QUAKE_SINK_SHAKE if q.sink_at > 0.0 else 0.0
		for n in q.nodes:
			var c: Array = n.get_meta("cell")
			n.position = Co.gxyz(c[0] + 0.5 + (randf() - 0.5) * shake, c[1] + 0.5 + (randf() - 0.5) * shake, c[2] - 0.5 + h)
	for i in range(flats.size() - 1, -1, -1):
		var f: Dictionary = flats[i]
		var age: float = now - f.t0
		if age > C.CRUSH_FLAT_MS:
			f.node.queue_free()
			flats.remove_at(i)
			continue
		# 처음엔 납작하게 퍼졌다가 (살짝 튐) 끝 0.3초에 종잇장처럼 얇아지며 사라짐
		var pop := 1 + 0.25 * sin(PI * age / 120.0) if age < 120 else 1.0
		var fade := maxf(0.0, (age - (C.CRUSH_FLAT_MS - 300)) / 300.0)
		_flat_scale(f.node, 1.5 * pop, C.CRUSH_FLAT_Z * (1 - fade * 0.9))
