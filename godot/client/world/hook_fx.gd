# 갈고리 (render.js hookThrowRope·hookRope·hookCancel·updateRopes·blockGrab·blockSlam·updateGrabs):
# F 밧줄: 던짐 (던진 쪽으로 늘어지며 뻗음) → 걸림 (팽팽, 퉁 떨림) → 감김 (느슨해지며 손으로), 빗나가거나 끊기면 바로 감김
# R 덩어리: 뽑기 예고 (제자리 덜덜) → 끌려와 머리 위에서 모양 그대로 빙빙 → 앞으로 내려찍어 박힘 (필드 밖이면 떨어져 사라짐)
# 밧줄은 손 (G2 몸 hands[1]) 에서. 밧줄 모양은 매 프레임 튜브를 새로 (밧줄은 몇 개뿐)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Cells := preload("res://world/cells.gd")

var effects = null # G5 fx/effects.gd
var marks = null # world/marks.gd
var bodies = null # world/bodies.gd
var make_mat = null # Callable(Color) -> Material (G3 툰)
var piece_colors: Dictionary = C.SHAPE_COLORS
var my_view_on := func() -> bool: return false # 내 1인칭 (덩어리를 높이·반투명)
var ropes := [] # {who, target, block, miss, t0, fly_ms, land_at, caught, land_from, tip, chain}
var grabs := {} # who -> {node, mats, from, t0, ms, size, slam, chain, pulled}
var slides := {} # id -> {from, to, t0, ms} 끌려오는 몸 (World.shown_pos 가 읽음)
var _rope_mat: Material
var _head_mat: Material


func _ready() -> void:
	Store.game_event.connect(on_event)


static func now_ms() -> float:
	return Time.get_ticks_msec() * 1.0


func _mat(c: Color) -> Material:
	if make_mat != null:
		return make_mat.call(c)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"hookThrow":
			throw_rope(e.get("who"), float(e.get("yaw", 0)), float(e.get("ms", C.HOOK_FLY_MS)))
		"hook":
			hook_rope(e)
		"interrupt":
			if str(e.get("kind", "")) == "skill":
				hook_cancel(e.get("who"))
		"blockGrab":
			block_grab(e)
		"blockSlam":
			block_slam(e)
		"blink": # 닌자 순간 베기: 몸이 from → to 로 미끄러짐 (render.js blinkSlide)
			var f = e.get("from")
			var t = e.get("to")
			if f != null and t != null and e.get("who") != null:
				var fz: float = float(f.z) if f.get("z") != null else float(t.z)
				slides[int(e.who)] = {"from": Vector3(f.x, f.y, fz), "to": Vector3(t.x, t.y, t.z), "t0": now_ms(), "ms": C.BLINK_SLIDE_MS}


# 손 자리 (게임 좌표): 몸이 보이면 오른손, 아니면 화면 위치 + 1
func hand(id) -> Variant:
	if bodies == null or id == null:
		return null
	var n: Dictionary = bodies.nodes.get(int(id), {})
	if not n.is_empty() and n.root.visible and n.body.visible and n.body.get("hands") is Array and n.body.hands.size() > 1 and n.body.hands[1] != null:
		return Co.game(n.body.hands[1].global_position)
	var s = bodies.shown.get(int(id))
	return Vector3(s.x, s.y, s.z + 1) if s != null else null


# ---------- 밧줄 ----------
func make_chain() -> Dictionary:
	if _rope_mat == null:
		_rope_mat = _mat(Co.color(C.ROPE_COLOR))
		_head_mat = _mat(Co.color(0xa3adb8))
	var mesh := MeshInstance3D.new()
	mesh.mesh = ImmediateMesh.new()
	mesh.material_override = _rope_mat
	var head := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.065
	t.outer_radius = 0.115
	t.rings = 8
	t.ring_segments = 4
	head.mesh = t
	head.material_override = _head_mat
	add_child(mesh)
	add_child(head)
	return {"mesh": mesh, "head": head}


func drop_chain(c: Dictionary) -> void:
	c.mesh.queue_free()
	c.head.queue_free()


# a → b 밧줄 (게임 좌표). sag: 가운데가 아래로 처지는 정도, wave: 옆으로 출렁이는 폭 (시간에 따라)
func set_chain(c: Dictionary, a: Vector3, b: Vector3, t: float, sag := 0.0, wave := 0.0) -> void:
	var len := a.distance_to(b)
	if not is_finite(len):
		return
	var dir := (b - a).normalized()
	var side := Vector3(-dir.y, dir.x, 0)
	if side.length_squared() < 1e-6:
		side = Vector3(1, 0, 0)
	side = side.normalized()
	var pts := []
	var n := 16
	for i in n + 1:
		var u := float(i) / n
		var bow := 4 * u * (1 - u)
		var p := a.lerp(b, u)
		p.z -= sag * bow
		p += side * (wave * sin(PI * u) * sin(t / 45.0 + u * 6))
		pts.append(Co.gpos(p))
	var im: ImmediateMesh = c.mesh.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var r: float = C.ROPE_RADIUS
	var rings := []
	for i in pts.size():
		var fwd: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var up := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var s1 := fwd.cross(up).normalized()
		var s2 := fwd.cross(s1).normalized()
		var ring := []
		for k in 6:
			var ang := TAU * k / 6
			ring.append([pts[i] + (s1 * cos(ang) + s2 * sin(ang)) * r, s1 * cos(ang) + s2 * sin(ang)])
		rings.append(ring)
	for i in rings.size() - 1:
		for k in 6:
			var q := [rings[i][k], rings[i][(k + 1) % 6], rings[i + 1][k], rings[i + 1][(k + 1) % 6]]
			for j in [0, 2, 1, 1, 2, 3]:
				im.surface_set_normal(q[j][1])
				im.surface_add_vertex(q[j][0])
	im.surface_end()
	c.head.position = Co.gpos(b)
	c.head.rotation = Vector3(0, t / 60.0, PI / 2)


func throw_rope(who, yaw: float, ms: float) -> void:
	var s = bodies.shown.get(int(who)) if bodies != null and who != null else null
	if s == null:
		return
	drop_rope(who)
	var miss := Vector3(s.x + cos(yaw) * C.HOOK_RANGE, s.y + sin(yaw) * C.HOOK_RANGE, s.z + C.HOOK_RAY_HEIGHT)
	ropes.append({"who": who, "target": null, "block": null, "miss": miss, "t0": now_ms(), "fly_ms": ms, "land_at": 0.0, "caught": false, "land_from": null, "tip": null, "chain": make_chain()})


func _flying(who):
	for r in ropes:
		if r.who == who and r.land_at == 0.0:
			return r
	return null


func hook_rope(e: Dictionary) -> void:
	var now := now_ms()
	var who = e.get("who")
	var r = _flying(who)
	if r == null:
		throw_rope(who, float(e.get("yaw", 0)), C.HOOK_FLY_MS)
		r = _flying(who)
		if r == null:
			return
	var target = e.get("target")
	var b = e.get("block")
	r.block = Vector3(b[0] + 0.5, b[1] + 0.5, b[2] + 0.5) if b != null else null
	r.target = target
	r.caught = b != null or target != null
	r.land_at = maxf(now, r.t0 + 1)
	r.land_from = r.tip
	if target != null and bodies != null and bodies.shown.has(int(target)):
		# 끌려오는 쪽: 닿은 지금부터 질질 끌려옴 (서버 위치로)
		slides[int(target)] = {"from": bodies.shown[int(target)], "to": null, "t0": now, "ms": C.HOOK_PULL_SLIDE_MS}


func hook_cancel(who) -> void:
	var r = _flying(who)
	if r != null:
		r.land_at = now_ms()
		r.caught = false
		r.land_from = r.tip


func drop_rope(who) -> void:
	for i in range(ropes.size() - 1, -1, -1):
		if ropes[i].who == who:
			drop_chain(ropes[i].chain)
			ropes.remove_at(i)


# ---------- R 덩어리 ----------
func block_grab(e: Dictionary) -> void:
	var now := now_ms()
	var cells: Array = e.cells if e.get("cells") != null and not e.cells.is_empty() else [e.from]
	var v := int(e.get("v", 0))
	var col := Color.WHITE if e.get("builder", false) else Co.color(Cells.cell_color(v, piece_colors))
	if e.get("sky", false):
		col = col.lerp(Color.WHITE, C.SKY_PIECE_WHITEN)
	var center := Vector3.ZERO
	for c in cells:
		center += Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5)
	center /= cells.size()
	var g := Node3D.new()
	var mat := _mat(col)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.98
	var size := 0.0
	for c in cells:
		var m := MeshInstance3D.new()
		m.mesh = bm
		m.material_override = mat
		var off := Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5) - center
		m.position = Co.gpos(off)
		g.add_child(m)
		size = maxf(size, off.length())
	g.position = Co.gpos(center)
	add_child(g)
	end_grab(e.get("who"))
	grabs[e.get("who")] = {"node": g, "from": center, "t0": now, "ms": float(e.get("ms", 300)), "size": size, "slam": null, "chain": make_chain(), "pulled": false, "rot": 0.0}
	# 잡히는 순간: 덩어리 칸이 번쩍 + 옆 블록 들썩
	if marks != null:
		var cs := []
		for c in cells:
			cs.append([floori(c[0]), floori(c[1]), floori(c[2])])
		marks.block_pulse(cs, 0xffffff, float(e.get("ms", 300)), 0.0, 0.6)
		marks.block_pulse(marks.neighbors(cs), 0xffffff, C.BLOCK_PULSE_MS, C.BLOCK_JOLT, 0.35)


func block_slam(e: Dictionary) -> void:
	var who = e.get("who")
	var g = grabs.get(who)
	var s = bodies.shown.get(int(who)) if bodies != null and who != null else null
	if g == null or s == null:
		return
	var cells: Array = e.cells if e.get("cells") != null and not e.cells.is_empty() else ([e.cell] if e.get("cell") != null else [])
	var to: Vector3
	var dir = e.get("dir") if e.get("dir") != null else {"x": 1, "y": 0}
	if not cells.is_empty():
		to = Vector3.ZERO
		for c in cells:
			to += Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5)
		to /= cells.size()
		# 박힌 모양이 뽑은 모양과 다르면 (필드 밖 칸을 버림) 큐브를 박힌 칸에 맞춤
		var kids: Array = g.node.get_children()
		if kids.size() != cells.size():
			for k in range(kids.size() - 1, cells.size() - 1, -1):
				kids[k].queue_free()
			for k in mini(cells.size(), kids.size()):
				kids[k].position = Co.gpos(Vector3(cells[k][0] + 0.5, cells[k][1] + 0.5, cells[k][2] + 0.5) - to)
	else:
		var len := float(e.get("len", 0))
		to = Vector3(s.x + dir.x * (len + 1.5), s.y + dir.y * (len + 1.5), s.z - 3)
	g.slam = {"t0": now_ms(), "from": Co.game(g.node.position), "rot": fmod(g.rot, TAU), "to": to, "cells": cells, "dir": dir, "line": s, "done": false, "fall_at": 0.0}


func end_grab(who) -> void:
	var g = grabs.get(who)
	if g == null:
		return
	g.node.queue_free()
	drop_chain(g.chain)
	grabs.erase(who)


func _burst(p: Vector3, dir, color: int, n: int, speed: float, size: float, life: float) -> void:
	if effects != null:
		effects.burst(p, dir, color, n, speed, size, life)


# ---------- 매 프레임 ----------
func step() -> void:
	var now := now_ms()
	for id in slides.keys():
		if now - slides[id].t0 >= slides[id].ms:
			slides.erase(id)
	for i in range(ropes.size() - 1, -1, -1):
		var r: Dictionary = ropes[i]
		var age: float = now - r.t0
		var a = hand(r.who)
		if a == null or (r.land_at == 0.0 and age > r.fly_ms + 1000):
			drop_chain(r.chain)
			ropes.remove_at(i)
			continue
		var ts = bodies.shown.get(int(r.target)) if r.target != null else null
		var len0: float = a.distance_to(r.miss)
		var end: Vector3
		var sag: float
		var wave: float
		if r.land_at == 0.0:
			var u := minf(1.0, age / r.fly_ms) # 날아감: 던진 방향으로 늘어지고 살짝 휜 채로
			end = a.lerp(r.miss, maxf(0.02, u))
			sag = len0 * u * C.ROPE_SAG
			wave = C.ROPE_WOBBLE * 0.6 * (1 - u)
		else:
			var since: float = now - r.land_at
			var hold: float = C.HOOK_HOLD_MS if r.caught else 0.0
			var goal: Vector3 = Vector3(ts.x, ts.y, ts.z + 1) if ts != null else (r.block if r.block != null else (r.land_from if r.land_from != null else r.miss))
			if since > hold + C.HOOK_FLY_MS:
				drop_chain(r.chain)
				ropes.remove_at(i)
				continue
			var len: float = a.distance_to(goal)
			if since < hold: # 걸림: 팽팽하게 (걸린 순간 짧게 퉁 떨림)
				end = goal
				sag = 0.0
				wave = C.ROPE_WOBBLE * 0.4 * exp(-since / 60.0)
			else: # 감김: 느슨해지며 손으로 돌아옴
				var v: float = (since - hold) / C.HOOK_FLY_MS
				end = a.lerp(goal, maxf(0.02, 1 - v))
				sag = len * C.ROPE_SAG * 0.8 * (1 - v)
				wave = C.ROPE_WOBBLE * (1 - v * 0.5)
		r.tip = end
		set_chain(r.chain, a, end, now, sag, wave)
	for who in grabs.keys():
		var g: Dictionary = grabs[who]
		var s = bodies.shown.get(int(who)) if bodies != null else null
		var h = hand(who)
		if s == null or h == null or now - g.t0 > 3000:
			end_grab(who)
			continue
		var mine: bool = Store.my_id != null and int(who) == Store.my_id and my_view_on.call() # 내 1인칭: 덩어리가 화면을 덮지 않게 높이
		var over := Vector3(s.x, s.y, s.z + C.PLAYER_HEIGHT + 0.9 + g.size * 0.5 + (C.HOOK_GRAB_FP_RAISE if mine else 0.0))
		var swing_r: float = C.HOOK_GRAB_SWING_R + g.size
		var pos: Vector3
		if g.slam == null:
			var t: float = now - g.t0
			var shake_ms: float = g.ms * C.HOOK_GRAB_SHAKE_PART
			if t < shake_ms: # 예고: 제자리에서 덜덜 (점점 세게)
				var k := t / shake_ms * C.HOOK_GRAB_SHAKE
				pos = g.from + Vector3((randf() - 0.5) * k, (randf() - 0.5) * k, randf() * k * 0.5)
			else:
				if not g.pulled: # 뽑힘: 빈 자리에서 돌 조각·흙
					g.pulled = true
					_burst(g.from, null, 0x8a7a68, 14 + 4 * g.node.get_child_count(), 4, 0.12, 0.55)
					_burst(g.from, {"x": 0, "y": 0}, 0x6a5e52, 8, 5, 0.18, 0.6)
				var u := minf(1.0, (t - shake_ms) / maxf(1.0, g.ms - shake_ms)) # 끌려옴 → 머리 위에서 빙빙 (눕힌 채 z 축으로만)
				var ang := now / 90.0
				var circle := over + Vector3(cos(ang) * swing_r, sin(ang) * swing_r, 0)
				pos = g.from.lerp(circle, u * u * (3 - 2 * u))
				g.rot = ang * 0.5 * u
		else:
			var sl: Dictionary = g.slam # 내려찍음: 위로 솟았다 앞으로 떨어지는 호, 박힐 때 도는 각 0
			var u := minf(1.0, (now - sl.t0) / C.HOOK_SLAM_FLY_MS)
			pos = sl.from.lerp(sl.to, u)
			pos.z += sin(PI * u) * 1.2
			g.rot = sl.rot * (1 - u)
			if u >= 1 and not sl.done:
				sl.done = true
				if not sl.cells.is_empty(): # 박힘: 칸마다 흙먼지 + 쾅 + 내려찍은 줄을 따라 먼지
					var cs := []
					for c in sl.cells:
						cs.append([floori(c[0]), floori(c[1]), floori(c[2])])
					for c in cs:
						_burst(Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5), null, 0x8a7a68, ceili(26.0 / cs.size()) + 4, 6, 0.13, 0.7)
					if effects != null:
						effects.ring(Vector3(sl.to.x, sl.to.y, sl.to.z - 0.45), 0xc0a880, 3.5 + g.size, 0.35, true)
					for k in range(1, int(C.HOOK_SLAM_LEN) + 1):
						_burst(Vector3(sl.line.x + sl.dir.x * k, sl.line.y + sl.dir.y * k, sl.line.z + 0.1), null, 0x9a8a78, 4, 2.5, 0.1, 0.5)
					if marks != null:
						marks.block_pulse(cs, 0xffffff, C.BLOCK_PULSE_MS, -C.BLOCK_JOLT, 0.85)
						marks.block_pulse(marks.neighbors(cs), 0xffffff, C.BLOCK_PULSE_MS, C.BLOCK_JOLT * 1.5, 0.4)
					View.sound_cue.emit("blast", {"x": sl.to.x, "y": sl.to.y, "z": sl.to.z, "big": true, "wood": false})
					end_grab(who)
					continue
				sl.fall_at = now
			if sl.fall_at > 0: # 필드 밖: 계속 떨어지며 사라짐
				pos.z -= (now - sl.fall_at) / 60.0
				if now - sl.fall_at > 500:
					end_grab(who)
					continue
		g.node.position = Co.gpos(pos)
		g.node.rotation = Vector3(0, Co.rot_y(g.rot), 0)
		for m in g.node.get_children():
			if m is MeshInstance3D:
				m.transparency = 1.0 - C.HOOK_GRAB_FP_OPACITY if mine else 0.0
		var taut: bool = g.slam != null or now - g.t0 < g.ms * C.HOOK_GRAB_SHAKE_PART # 덜덜·내려찍기는 팽팽, 돌릴 땐 살짝 출렁
		set_chain(g.chain, h, pos, now, 0.0, 0.0 if taut else C.ROPE_WOBBLE * 0.4)
