# 건축가 블록 그리기 (G6, client/bblocks.js + render.js updateBBlocks·bblockBorn·bbCollapse·blastChain·bbPop 자리, 시안 A '공사장 나무 상자').
# 격자엔 CELL.BUILD 로 있지만 world.gd 가 skip() 칸을 빼고, 여기서 부품마다 MultiMesh 하나로 그림 (칸이 늘어도 그리기 수 그대로):
# 생길 때 바닥을 뚫고 솟아 살짝 넘침 · 수명 끝 무렵 금이 퍼지고 하얗게 깜빡 · 같은 묶음 이웃 칸 윗면은 쇠 띠 · R 은 빛 판이 세지며 부풂
# · 연쇄 폭발은 칸마다 차례로 (대기 칸은 하얗게) · 수명 끝은 부서지며 내려앉음 · 판자 조각. 소리는 View.sound_cue "blast" (audio/)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const BL := preload("res://world/bblock_look.gd")
const Tex := preload("res://world/bblock_tex.gd")
const Bodies := preload("res://world/bodies.gd")
const SHADER := preload("res://world/bblock.gdshader")
const G3_PATH := "res://shaders/g3.gd"

# 게임 좌표 (x, y, z 위) → 고도 (x, z, -y)
const TB := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

var pools := {} # 이름 -> {mm: MultiMesh, n}
var part_list := {} # kind -> parts
var wood_tex: Texture2D
var born := {} # "x,y,z" -> 생긴 시각
var last := {} # "x,y,z" -> {kind, color} (지워진 뒤 무너짐·터짐 모습)
var ghosts: Array = [] # 연쇄 대기 칸 {x,y,z,kind,color,at,dir}
var collapses: Array = [] # 무너지는 중 {x,y,z,kind,color,t0,dir}
var skip_set := {}
var sig := ""
var shard_mm := MultiMesh.new()
var shards: Array = []
var G3 = null
var demo := false # 확인용 (명령줄 --bb-demo): 필드 가운데에 종류별 가짜 블록 + 2.5초마다 연쇄 폭발
var demo_next := 0.0


static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


func _init() -> void:
	if ResourceLoader.exists(G3_PATH):
		G3 = load(G3_PATH)
	var L: Dictionary = C.BB_LOOK
	var crack := Tex.crack_mask()
	wood_tex = Tex.planks(int(L.wood))
	var outline = G3.outline_material() if G3 != null else null
	var mk := func(opts: Dictionary) -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = SHADER
		for k in opts:
			m.set_shader_parameter(k, opts[k])
		if G3 != null:
			m.set_shader_parameter("toon_steps", load("res://shaders/g3_config.gd").TOON_STEPS)
			if not opts.get("unlit", false) and not opts.has("_no_outline"):
				m.next_pass = outline
		return m
	_pool("wood", mk.call({"albedo_tex": wood_tex, "use_tex": true, "crack_tex": crack, "use_crack": true}))
	_pool("woodPad", mk.call({"albedo_tex": Tex.planks(int(L.woodPad), true, false, 11), "use_tex": true, "crack_tex": crack, "use_crack": true}))
	_pool("woodBig", mk.call({"albedo_tex": Tex.planks(int(L.woodBig), false, true, 13), "use_tex": true, "crack_tex": crack, "use_crack": true}))
	_pool("corner", mk.call({"albedo": Co.color(L.steel)}))
	var st: Array = L.stripeRepeat
	_pool("band", mk.call({"albedo_tex": Tex.stripes(), "use_tex": true, "uv_scale": Vector2(3.0 * st[0], 2.0 * st[1]), "use_vertex_color": true}))
	_pool("plate", mk.call({"unlit": true, "use_vertex_color": true}), false)
	_pool("strap", mk.call({"albedo": Co.color(0x3a3a44), "_no_outline": true}), false)
	for k in BL.KINDS:
		part_list[k] = BL.parts(k)
	# 판자 조각 (client/shards.js): MultiMesh 하나, 칸마다 색
	var box := BoxMesh.new()
	box.material = G3.toon_material(Color.WHITE, {"map": wood_tex, "vertex_color": true}) if G3 != null else StandardMaterial3D.new()
	shard_mm.transform_format = MultiMesh.TRANSFORM_3D
	shard_mm.use_colors = true
	shard_mm.mesh = box
	shard_mm.instance_count = int(C.BB_SHARDS.max)
	shard_mm.visible_instance_count = 0
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = shard_mm
	smi.extra_cull_margin = 16384.0
	add_child(smi)


func _pool(name: String, mat: Material, shadow := true) -> void:
	var box := BoxMesh.new()
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	pools[name] = {"mm": mm, "mi": mi, "n": 0}


func _ready() -> void:
	Store.game_event.connect(on_event)
	demo = OS.get_cmdline_user_args().has("--bb-demo")


func _demo_list(st: Dictionary) -> Array:
	var f: Dictionary = st.get("field", {})
	var cx := int(f.get("w", 10)) / 2
	var cy := int(f.get("d", 10)) / 2
	var z := 0
	while z < 20 and _solid(cx + 0.5, cy + 0.5, z + 0.5):
		z += 1
	var t := fmod(now_ms(), 4000.0)
	var out := []
	for i in 3:
		out.append({"x": cx - 2 + i, "y": cy - 2, "z": z, "kind": "wall", "group": 1, "left": 6000 - t})
	out.append({"x": cx + 2, "y": cy - 2, "z": z, "kind": "pad", "group": 2, "left": 1200})
	out.append({"x": cx - 2, "y": cy + 1, "z": z, "kind": "third", "group": 3, "left": 9000})
	out.append({"x": cx + 1, "y": cy + 1, "z": z, "kind": "big", "group": 4, "left": 800 - fmod(t, 800.0)})
	var ps: Array = st.get("players", [])
	for b in out:
		b.owner = ps[0].id if not ps.is_empty() else null
	if now_ms() >= demo_next:
		demo_next = now_ms() + 2500.0
		blast_chain({"cells": [[cx - 2, cy + 3, z], [cx - 1, cy + 3, z], [cx, cy + 3, z]], "dir": {"x": 1, "y": 0}})
		collapse([[cx + 3, cy + 3, z]])
	return out


# 그리지 않을 격자 칸 번호 (world.gd → grid_view.skip)
func skip() -> Dictionary:
	return skip_set


# 지금 그리는 MultiMesh 수 (확인용, 칸 수와 상관없음)
func mesh_count() -> int:
	var n := 0
	for k in pools:
		if pools[k].mi.visible:
			n += 1
	return n


static func _key(x, y, z) -> String:
	return "%d,%d,%d" % [int(x), int(y), int(z)]


func _tint(owner, st: Dictionary) -> Color:
	var p := Store.player(owner) if owner != null else {}
	var c := Co.color(Bodies.player_color(p, st)) if not p.is_empty() else Co.color(0xc08040)
	return c.lerp(Color.WHITE, C.BB_TINT)


func update(st: Dictionary) -> void:
	var list: Array = st.get("bblocks", [])
	if demo:
		list = list + _demo_list(st)
	var f: Dictionary = st.get("field", {})
	var W := int(f.get("w", C.GRID_W))
	var D := int(f.get("d", C.GRID_W))
	var s := ""
	for b in list:
		s += "%s|" % _key(b.x, b.y, b.z) + str(b.kind)
	s += "#%d,%d" % [W, D]
	if s != sig:
		sig = s
		skip_set = {}
		for b in list:
			skip_set[(int(b.z) * D + int(b.y)) * W + int(b.x)] = true
		var w := get_parent()
		if w != null and "built_version" in w:
			w.built_version = -2 # 칸을 다시 깖 (빠진 칸이 바뀜)
	var now := now_ms()
	var items := []
	for b in list:
		var color := _tint(b.get("owner"), st)
		var key := _key(b.x, b.y, b.z)
		last[key] = {"kind": str(b.kind), "color": color}
		var it := {"x": b.x, "y": b.y, "z": b.z, "kind": str(b.kind), "color": color, "sx": 1.0, "sz": 1.0, "crack": 0.0, "flash": 0.0, "glow": 0.0}
		if born.has(key):
			var u: float = (now - born[key]) / C.BB_POP_MS
			if u >= 1.0:
				born.erase(key)
			else:
				it.sz = BL.rise_scale(u)
		if b.kind == "big":
			var pr := BL.big_prep(float(b.get("left", 0)), now)
			it.sx = pr.swell
			it.sz *= pr.swell
			it.glow = pr.glow
		else:
			it.crack = BL.crack_of(b.get("left"))
			it.flash = BL.flash_of(b.get("left"), now)
		items.append(it)
	# 연쇄 대기 칸: 차례가 오면 터짐, 그 전엔 하얗게
	var wait := []
	for gh in ghosts:
		if now >= gh.at:
			pop(gh)
		else:
			wait.append(gh)
	ghosts = wait
	for gh in ghosts:
		items.append({"x": gh.x, "y": gh.y, "z": gh.z, "kind": gh.kind, "color": gh.color, "sx": 1.0, "sz": 1.0, "crack": 0.4, "flash": 0.9, "glow": 1.0})
	# 수명 끝: 부서지며 내려앉음
	collapses = collapses.filter(func(c): return now - c.t0 < C.BB_COLLAPSE_MS)
	for c in collapses:
		var k := BL.collapse_at((now - c.t0) / C.BB_COLLAPSE_MS)
		items.append({"x": c.x, "y": c.y, "z": c.z, "kind": c.kind, "color": c.color, "sx": 1.0, "sz": k.sz, "sink": k.sink, "tilt": k.tilt, "tilt_dir": c.dir, "crack": 1.0, "flash": 0.0})
	# 같은 묶음 이웃 칸: 윗면 이음매 쇠 띠
	var at := {}
	for b in list:
		at[_key(b.x, b.y, b.z)] = b
	var straps := []
	for b in list:
		for d in [[1, 0], [0, 1]]:
			var n = at.get(_key(b.x + d[0], b.y + d[1], b.z))
			if n != null and n.get("group") == b.get("group"):
				straps.append({"x": b.x + 0.5 + d[0] * 0.5, "y": b.y + 0.5 + d[1] * 0.5, "z": b.z + 1.01, "dx": d[0], "dy": d[1]})
	draw(items, straps)


# 게임 좌표 변환 m → 고도 (TB m TB⁻¹)
static func _g(m: Transform3D) -> Transform3D:
	return Transform3D(TB, Vector3.ZERO) * m * Transform3D(TB.inverse(), Vector3.ZERO)


func draw(items: Array, straps: Array) -> void:
	for k in pools:
		pools[k].n = 0
	var L: Dictionary = C.BB_LOOK
	for b in items:
		var parts: Array = part_list.get(b.kind, part_list.wall)
		var td: float = b.get("tilt_dir", 0.0)
		var axis := Vector3(-sin(td), cos(td), 0)
		var sx: float = b.get("sx", 1.0)
		var P := Transform3D(Basis(axis, b.get("tilt", 0.0)).scaled_local(Vector3(sx, sx, b.get("sz", 1.0))), Vector3(b.x + 0.5, b.y + 0.5, b.z - b.get("sink", 0.0)))
		var flash: float = b.get("flash", 0.0)
		for pt in parts:
			var M := P * Transform3D(Basis.from_scale(Vector3(pt.size[0], pt.size[1], pt.size[2])), Vector3(pt.at[0], pt.at[1], pt.at[2]))
			match pt.part:
				"base":
					_add(pt.mat, M, Color.WHITE, b.get("crack", 0.0), flash)
				"corner":
					_add("corner", M, Color.WHITE, 0.0, flash)
				"band":
					_add("band", M, (b.color as Color).lerp(Color.WHITE, flash) if flash > 0 else b.color)
				"plate":
					_add("plate", M, BL.plate_color(b.get("glow", 0.0)))
	for s in straps:
		_add("strap", Transform3D(Basis.from_scale(Vector3(0.55 if s.dx else 0.16, 0.55 if s.dy else 0.16, 0.06)), Vector3(s.x, s.y, s.z)))
	for k in pools:
		var p: Dictionary = pools[k]
		p.mm.visible_instance_count = p.n
		p.mi.visible = p.n > 0


func _add(pool: String, m: Transform3D, color := Color.WHITE, crack := 0.0, flash := 0.0) -> void:
	var p: Dictionary = pools[pool]
	var mm: MultiMesh = p.mm
	if p.n >= mm.instance_count:
		# 모자라면 두 배 (instance_count 를 바꾸면 내용이 지워짐 → 이번 프레임 앞 것은 다시 씀)
		var keep := []
		for i in p.n:
			keep.append([mm.get_instance_transform(i), mm.get_instance_color(i), mm.get_instance_custom_data(i)])
		mm.instance_count = maxi(int(C.INSTANCE_POOL_MIN), mm.instance_count * 2)
		for i in keep.size():
			mm.set_instance_transform(i, keep[i][0])
			mm.set_instance_color(i, keep[i][1])
			mm.set_instance_custom_data(i, keep[i][2])
	mm.set_instance_transform(p.n, _g(m))
	mm.set_instance_color(p.n, color)
	mm.set_instance_custom_data(p.n, Color(crack, flash, 0, 0))
	p.n += 1


# ---------- 이벤트 (main.js handleEvent bblock·bblockGone·blast·bigBombWarn·bigBomb) ----------
func on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"bblock", "bigBombWarn":
			born_cells(e.get("cells", []))
		"bblockGone":
			collapse(e.get("cells", []))
		"blast":
			blast_chain(e)
		"bigBomb":
			var cells: Array = e.get("cells", [])
			for i in cells.size():
				var c: Array = cells[i]
				pop({"x": c[0], "y": c[1], "z": c[2], "dir": e.get("dir")}, i == cells.size() / 2)


func _fx():
	var f = get_tree().get_first_node_in_group("fx") if is_inside_tree() else null
	return f.effects if f != null else null


func _low() -> bool:
	return bool(View.settings.get("lowGfx", false))


# 생김: 바닥을 뚫고 솟음 + 아래에 흙먼지
func born_cells(cells: Array) -> void:
	if cells.is_empty():
		return
	var now := now_ms()
	var fx = _fx()
	var bottom := INF
	for c in cells:
		bottom = minf(bottom, c[2])
	for c in cells:
		born[_key(c[0], c[1], c[2])] = now
		if fx != null and c[2] == bottom:
			fx.burst(Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.05), null, 0xa0835c, 2 if _low() else 6, 2.6, 0.1, 0.45)


# 수명 끝: 부서지며 내려앉음 + 판자 조각 + 먼지
func collapse(cells: Array) -> void:
	var now := now_ms()
	var fx = _fx()
	var L: Dictionary = C.BB_LOOK
	for c in cells:
		var key := _key(c[0], c[1], c[2])
		var l: Dictionary = last.get(key, {"kind": "wall", "color": Co.color(0xc08040)})
		last.erase(key)
		collapses.append({"x": c[0], "y": c[1], "z": c[2], "kind": l.kind, "color": l.color, "t0": now, "dir": randf() * TAU})
		var pos := Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.4)
		spawn_shards(pos, null, BL.shard_count("collapse", _low()), [int(L.wood), int(L.woodPad), 0x8a6a40], 2.5)
		if fx != null:
			fx.burst(pos, null, 0x9a9080, 3 if _low() else 8, 2.0, 0.1, 0.5)


# 망치로 쳐서 폭발: 서버는 한 번에 지웠지만 화면에선 cells 순서대로 차례로 터짐
func blast_chain(e: Dictionary) -> void:
	var now := now_ms()
	var o := Store.player(e.get("who")) if e.get("who") != null else {}
	var hex: int = Bodies.player_color(o, Store.state) if not o.is_empty() else 0xc08040
	var tint := Co.color(hex).lerp(Color.WHITE, C.BB_TINT)
	var cells: Array = e.get("cells", [])
	for i in cells.size():
		var c: Array = cells[i]
		var l = last.get(_key(c[0], c[1], c[2]))
		ghosts.append({"x": c[0], "y": c[1], "z": c[2], "kind": l.kind if l != null else "wall", "color": l.color if l != null else tint, "at": now + i * C.BB_CHAIN_STEP_MS, "dir": e.get("dir")})


# 한 칸 터짐: 판자·쇠 조각 (치는 방향으로) + 먼지 + 불꽃 + 고리, 소리 신호 + 가까우면 흔들림 (main.js renderer.onBlast)
func pop(gh: Dictionary, big := false) -> void:
	var key := _key(gh.x, gh.y, gh.z)
	var kind := "big" if big else str(gh.get("kind", last.get(key, {}).get("kind", "wall")))
	last.erase(key)
	var pos := Vector3(gh.x + 0.5, gh.y + 0.5, gh.z + 0.5)
	var dir = {"x": gh.dir.x * 1.2, "y": gh.dir.y * 1.2} if gh.get("dir") != null else null
	var L: Dictionary = C.BB_LOOK
	var colors := [int(L.woodBig), int(L.woodBig), int(L.steel), 0xff7a20] if kind == "big" else [int(L.wood), int(L.wood), int(L.woodPad), int(L.steel)]
	spawn_shards(pos, dir, BL.shard_count(kind, _low()), colors, 8.0 if big else C.BB_SHARDS.speed)
	var fx = _fx()
	if fx != null:
		fx.burst(pos, null, 0x8a8478, roundi((16 if big else 7) * (C.BB_LOW_FX if _low() else 1.0)), 4.0, 0.12, 0.7)
		fx.burst(pos, dir, 0xffc040, 3 if _low() else 8, 8.0, 0.1, 0.3)
		fx.ring(pos, 0xffd080, 5.0 if big else 2.6, 0.3)
		var me := Store.me()
		if not me.is_empty():
			var d := pos.distance_to(Vector3(me.x, me.y, me.z))
			if d < (7.0 if big else 4.0):
				fx.shake(0.4 if big else 0.15, 450.0 if big else 200.0)
	View.sound_cue.emit("blast", {"x": pos.x, "y": pos.y, "z": pos.z, "big": big, "wood": true})


# ---------- 판자 조각 (client/shards.js) ----------
func spawn_shards(pos: Vector3, dir, n: int, colors: Array, speed: float) -> void:
	var S: Dictionary = C.BB_SHARDS
	for i in n:
		if shards.size() >= int(S.max):
			shards.pop_front()
		var a := randf() * TAU
		var r := 0.4 + randf() * 0.6
		var life: float = S.life * (0.7 + randf() * 0.5)
		shards.append({
			"p": pos + Vector3((randf() - 0.5) * 0.6, (randf() - 0.5) * 0.6, (randf() - 0.5) * 0.5),
			"v": Vector3(cos(a) * r * speed * 0.55 + (dir.x * speed * 0.6 if dir != null else 0.0), sin(a) * r * speed * 0.55 + (dir.y * speed * 0.6 if dir != null else 0.0), 1.5 + randf() * speed * 0.7),
			"r": Vector3(randf() * 6, randf() * 6, randf() * 6),
			"w": Vector3((randf() - 0.5) * 16, (randf() - 0.5) * 16, (randf() - 0.5) * 10),
			"k": 0.6 + randf() * 0.7, "life": life, "max": life,
			"color": Co.color(colors[randi() % colors.size()]), "bounced": false,
		})


func _solid(x: float, y: float, z: float) -> bool:
	var w := get_parent()
	return w.solid_at(x, y, z) if w != null and w.has_method("solid_at") else z < 0


func _process(dt: float) -> void:
	dt = minf(dt * View.time_scale, 0.05)
	var S: Dictionary = C.BB_SHARDS
	var keep := []
	var n := 0
	for p in shards:
		p.life -= dt
		if p.life <= 0:
			continue
		keep.append(p)
		var v: Vector3 = p.v
		v.z -= 14.0 * dt
		var nz: float = p.p.z + v.z * dt
		if v.z < 0 and _solid(p.p.x, p.p.y, nz - 0.03):
			if not p.bounced:
				v = Vector3(v.x * 0.5, v.y * 0.5, -v.z * 0.35)
				p.bounced = true
			else:
				v.z = 0.0
			p.w = Vector3(p.w.x * 0.4, p.w.y * 0.4, p.w.z)
		else:
			p.p.z = nz
		p.p.x += v.x * dt
		p.p.y += v.y * dt
		p.v = v
		p.r += p.w * dt
		var fade := minf(1.0, p.life / (p.max * 0.3)) # 끝 30% 에 작아짐
		var sz: Array = S.size
		var m := Transform3D(Basis.from_euler(p.r).scaled_local(Vector3(sz[0], sz[1], sz[2]) * p.k * fade), p.p)
		shard_mm.set_instance_transform(n, _g(m))
		shard_mm.set_instance_color(n, p.color)
		n += 1
	shards = keep
	shard_mm.visible_instance_count = n
