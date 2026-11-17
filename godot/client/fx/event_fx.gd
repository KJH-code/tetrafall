# c9-u3 돌발 이벤트 세계 연출: 이벤트가 도는 동안 필드 안에 그 모습 — 돌풍 = dir 쪽으로 흐르는 바람 줄, 빙판 = 칸 윗면마다 하늘빛 판 + 반짝 줄, 저중력 = 바닥에서 오르는 마름모 티끌,
# 블록 폭우 = 필드 위에서 내려오는 세로 줄, 보급 = 새 아이템 자리마다 빛 기둥 + 바닥 고리 한 번. 위 띠 글 (ui/hud_extra.gd) 을 안 읽어도 무슨 이벤트인지, 돌풍이 어느 쪽인지.
# fx/fx.gd 의 자식. fx 가 프레임마다 update(dt, 카메라, 스냅샷, 그래픽 낮춤) 을, 게임 이벤트 roundEvent 마다 on_round_event(e) 를 부름 (자동 로드를 안 씀 → 도구·테스트가 그대로 돌림).
# 종류마다 MultiMeshInstance3D 하나 (수가 늘어도 그리기 한 번), 안 쓰는 것은 visible = false (평소 그리기 0). 재질은 표준 재질 한 모양 (event_fx_config.gd KEY — world/warm_scan.gd STD_KEYS 안, 새 셰이더 없음).
# 어디에·얼마나는 fx/event_fx_math.gd (순수 계산), 수치는 fx/event_fx_config.gd EVENT_FX
extends Node3D

const Co := preload("res://core/coords.gd")
const WS := preload("res://world/warm_scan.gd")
const RL := preload("res://world/ring_look.gd")
const FR := preload("res://world/foot_rings.gd")
const Cells := preload("res://world/cells.gd")
const M := preload("res://fx/event_fx_math.gd")
const K := preload("res://fx/event_fx_config.gd")

const CFG := K.EVENT_FX

var world = null # 판 (World: grid·grid_view·built_version) — 빙판이 칸 윗면을 찾을 때만. 없으면 빙판은 안 그림
var layers := {} # 이름 (wind·lowgrav·rain·ice·glint·pillar·ring) → MultiMeshInstance3D
var clock := 0.0 # 흐른 시간 (초, 화면 시계 — 슬로모션이면 같이 느려짐)
var kind := "" # 지금 그리는 종류 ("" = 없음)
var began := 0.0 # 그 종류를 처음 본 시각 (clock)
var total := 0.0 # 이벤트 길이 ms (게임 이벤트의 ms, 못 받았으면 처음 본 left)
var left := 0.0 # 남은 ms (스냅샷 사이엔 프레임 dt 로 줄임)
var seen_left := -1.0 # 마지막으로 본 스냅샷 left
var pending := {} # 게임 이벤트로 받은 {kind, ms} (스냅샷보다 먼저 올 때)
var ice_key := "" # 빙판을 깐 열쇠 (격자 버전·판 크기·위험 높이·화질) — 바뀌면 다시 깖
var ice_rows: Array = [] # event_fx_math.ice_cells
var glint_dists: Array = [] # 반짝 줄마다 가운데에서 거리 (가까운 순서)
var items_seen := {} # 앞 프레임 스냅샷의 아이템 자리
var armed := 0.0 # 보급 이벤트를 받고 새 아이템을 기다리는 남은 시간 (초)
var armed_prev := {} # 그때의 아이템 자리
var pillars: Array = [] # 빛 기둥 {x, y, z, key, t0}
var keep := false # 확인용 (테스트): 참이면 넣은 인스턴스를 put 에 남김 — 헤드리스에선 MultiMesh 값을 되읽을 수 없음
var put := {} # 겹 이름 → [[Transform3D, Color], ...] (keep 일 때만)
var tops := PackedInt32Array() # 기둥마다 꼭대기 높이 (줄·티끌이 바닥 위에 뜨게) — 격자가 바뀔 때만 다시 셈
var tops_key := ""
var lava_on := false # 위험 액체 (이번 프레임 스냅샷)
var lava_z := 0.0
var wind_z: Array = [] # 바람 줄마다 따라가는 바닥 높이
var wind_at: Array = [] # 바람 줄마다 지난 프레임 자리 (반대편에서 다시 나온 줄은 높이를 바로 맞춤)
var _box := Vector3i.ZERO # custom_aabb 를 맞춘 판 크기


func _init() -> void:
	var c: Dictionary = CFG.common
	var air := int(c.order_air)
	_layer("wind", strip_mesh(two_tier(CFG.wind, float(CFG.wind.alpha), float(CFG.wind.core_alpha)), CFG.wind.prof), air, int(CFG.wind.n[1]))
	_layer("lowgrav", mote_mesh(float(CFG.lowgrav.tail), float(CFG.lowgrav.tail_w), float(CFG.lowgrav.tail_alpha)), air, int(CFG.lowgrav.n))
	_layer("rain", strip_mesh(two_tier(CFG.rain, float(CFG.rain.alpha), float(CFG.rain.core_alpha)), CFG.rain.prof), air, int(CFG.rain.n))
	var plate := PlaneMesh.new()
	plate.size = Vector2.ONE
	_layer("ice", plate, int(c.order_floor), 0)
	_layer("glint", plate, int(CFG.ice.glint.order), 0)
	_layer("pillar", strip_mesh(two_tier(CFG.supply, 1.0, 1.0), CFG.supply.prof), air, int(CFG.supply.max))
	_layer("ring", RL.mesh("aura", int(CFG.supply.color)), air, int(CFG.supply.max))


func _layer(id: String, mesh: Mesh, order: int, cap: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var n := MultiMeshInstance3D.new()
	n.name = id
	n.multimesh = mm
	n.material_override = material(order)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.visible = false
	layers[id] = n
	add_child(n)


# 빛 안 받는 반투명 정점 색 (인스턴스 색 = 색 + 알파), 깊이 검사 켬 (블록 뒤면 가려짐)
static func material(order: int) -> StandardMaterial3D:
	var m: StandardMaterial3D = WS.std_material(K.KEY)
	m.render_priority = order
	return m


static func col(v) -> Color:
	return v if v is Color else Co.color(v)


# 2단 줄의 폭 띠 [[y0, y1, 색 (알파 포함)]]: 가운데 core (폭 비율) = 심 (알파 core_a), 양옆 = 바깥 색 (알파 out_a)
static func two_tier(k: Dictionary, out_a: float, core_a: float) -> Array:
	var h := float(k.core) * 0.5
	var out_c := col(k.color)
	var core_c := col(k.core_color)
	out_c.a = out_a
	core_c.a = core_a
	return [[-0.5, -h, out_c], [-h, h, core_c], [h, 0.5, out_c]]


# 줄 메시: 긴 축 X −0.5~0.5 (길이 1) · 폭 Y −0.5~0.5 · 앞면 +Z. bands = 폭 띠 [[y0, y1, 색]], prof = 길이 따라 알파 [[x, 배율]] — 정점 색으로 칠함
static func strip_mesh(bands: Array, prof: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var vc := PackedColorArray()
	var nrm := PackedVector3Array()
	for b in bands:
		var y0 := float(b[0])
		var y1 := float(b[1])
		var c: Color = b[2]
		for j in prof.size() - 1:
			var x0 := float(prof[j][0])
			var x1 := float(prof[j + 1][0])
			var c0 := Color(c.r, c.g, c.b, c.a * float(prof[j][1]))
			var c1 := Color(c.r, c.g, c.b, c.a * float(prof[j + 1][1]))
			# +Z 에서 봐서 시계 방향 = 앞면
			v.append_array([Vector3(x0, y0, 0), Vector3(x0, y1, 0), Vector3(x1, y1, 0), Vector3(x0, y0, 0), Vector3(x1, y1, 0), Vector3(x1, y0, 0)])
			vc.append_array([c0, c0, c1, c0, c1, c1])
			for i in 6:
				nrm.append(Vector3.BACK)
	return _mesh(v, nrm, vc)


# 티끌 메시 (흰색 — 색은 인스턴스 색으로): 긴 축 X −0.5~0.5 (위쪽 = +X), 폭 Y −0.5~0.5, 앞면 +Z. 위 끝에 마름모 (길이의 1 / (1 + tail)), 그 아래로 가늘어지며 흐려지는 꼬리.
# 인스턴스 배율 = (마름모 크기 × (1 + tail), 마름모 크기) → 마름모는 가로세로 같은 크기
static func mote_mesh(tail: float, tail_w: float, tail_alpha: float) -> ArrayMesh:
	var hd := 1.0 / (1.0 + tail)
	var xc := 0.5 - hd * 0.5
	var w := Color.WHITE
	var ta := Color(1, 1, 1, tail_alpha)
	# +Z 에서 봐서 시계 방향 = 앞면
	var v := PackedVector3Array([
		Vector3(xc, 0.5, 0), Vector3(0.5, 0, 0), Vector3(xc, -0.5, 0), Vector3(xc, 0.5, 0), Vector3(xc, -0.5, 0), Vector3(0.5 - hd, 0, 0),
		Vector3(xc, tail_w * 0.5, 0), Vector3(xc, -tail_w * 0.5, 0), Vector3(-0.5, 0, 0)])
	var vc := PackedColorArray([w, w, w, w, w, w, ta, ta, Color(1, 1, 1, 0)])
	var nrm := PackedVector3Array()
	for i in v.size():
		nrm.append(Vector3.BACK)
	return _mesh(v, nrm, vc)


static func _mesh(v: PackedVector3Array, nrm: PackedVector3Array, vc: PackedColorArray) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = vc
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# 게임 이벤트 roundEvent {kind, ms, dir}: 보급이면 새 아이템을 기다림, 도는 종류면 길이 (ms) 를 기억
func on_round_event(e: Dictionary) -> void:
	var k := str(e.get("kind", ""))
	if k == "supply":
		armed = float(CFG.supply.arm)
		armed_prev = items_seen.duplicate()
	elif K.RUNNING.has(k):
		var ms := float(e.get("ms", 0.0)) if e.get("ms") != null else 0.0
		pending = {"kind": k, "ms": ms}
		if k == kind and ms > 0.0:
			total = ms


# 프레임마다: st = 스냅샷 (roundEvent {kind, left, dir}·items·field·lava), cam = 보는 카메라 (없으면 가까운 것 빼기·돌려 세우기를 원점 기준으로), low = 그래픽 낮춤
func update(dt: float, cam: Camera3D, st: Dictionary, low: bool) -> void:
	clock += dt
	var ev = st.get("roundEvent") if str(st.get("phase", "")) == "playing" else null
	var k := M.running_kind(ev, K.RUNNING)
	if k != kind:
		kind = k
		began = clock
		total = 0.0
		seen_left = -1.0
		ice_key = ""
		wind_z = []
		wind_at = []
		if k == "":
			pending = {}
	var f: Dictionary = st.get("field", {}) if st.get("field") is Dictionary else {}
	var field := Vector3i(int(f.get("w", 0)), int(f.get("d", 0)), int(f.get("h", 0)))
	var cam_xf := Transform3D.IDENTITY
	if cam != null:
		cam_xf = cam.global_transform if cam.is_inside_tree() else cam.transform
	var a := 0.0
	if k != "":
		var l := float(ev.left)
		if l != seen_left: # 새 스냅샷
			seen_left = l
			left = l
		else:
			left = maxf(0.0, left - dt * 1000.0)
		if total <= 0.0:
			total = float(pending.ms) if pending.get("kind") == k and float(pending.get("ms", 0.0)) > 0.0 else left
		a = M.fade(left, total, CFG.common)
		_fit_box(field)
		_ground(st, field)
	if k == "wind" and field.x > 0:
		_wind(M.wind_dir(ev.get("dir")), field, a, cam_xf.origin, low, dt)
	else:
		_hide("wind")
	if k == "lowgrav" and field.x > 0:
		_lowgrav(field, a, cam_xf.origin, low)
	else:
		_hide("lowgrav")
	if k == "rain" and field.x > 0:
		_rain(field, a, cam_xf.origin, low)
	else:
		_hide("rain")
	if k == "ice" and field.x > 0 and world != null and world.has_method("grid"):
		_ice(field, a, low)
	else:
		_hide("ice")
		_hide("glint")
	_supply(dt, st, field, cam_xf.origin)


func _hide(id: String) -> void:
	var n: MultiMeshInstance3D = layers[id]
	if n.visible:
		n.visible = false
		n.multimesh.visible_instance_count = 0


# 그 겹의 MultiMesh (n 개가 들어가게)
func _mm(id: String, n: int) -> MultiMesh:
	var mm: MultiMesh = (layers[id] as MultiMeshInstance3D).multimesh
	if mm.instance_count < n:
		mm.visible_instance_count = 0
		mm.instance_count = n
	if keep:
		put[id] = []
	return mm


# 인스턴스 하나 (변환 + 색)
func _inst(mm: MultiMesh, id: String, i: int, xf: Transform3D, c: Color) -> void:
	mm.set_instance_transform(i, xf)
	mm.set_instance_color(i, c)
	if keep:
		put[id].append([xf, c])


func _show(id: String, n: int) -> void:
	var node: MultiMeshInstance3D = layers[id]
	node.multimesh.visible_instance_count = n
	node.visible = n > 0


# 가려내기 상자를 판 크기에 한 번 맞춤 (인스턴스가 프레임마다 움직여도 상자를 다시 안 셈): 필드 + margin, 높이는 격자 높이 + 폭우 높이까지
func _fit_box(field: Vector3i) -> void:
	if field == _box or field.x <= 0:
		return
	_box = field
	var m := float(CFG.common.margin) + 1.0
	var top := float(field.z) + float(CFG.rain.z[1]) + 1.0
	var box := AABB(Vector3(-m, -1.0, -(field.y + m)), Vector3(field.x + m * 2.0, top + 1.0, field.y + m * 2.0))
	for id in layers:
		(layers[id] as MultiMeshInstance3D).multimesh.custom_aabb = box


# 바닥 높이 재료: 기둥 꼭대기 (격자 버전이 바뀔 때만 다시 셈, 판이 없으면 빈 배열 = 높이 0) + 위험 액체
func _ground(st: Dictionary, field: Vector3i) -> void:
	var lava: Dictionary = st.get("lava", {}) if st.get("lava") is Dictionary else {}
	lava_on = lava.get("active", false)
	lava_z = float(lava.get("z", 0.0)) if lava_on else 0.0
	if world == null or not world.has_method("grid"):
		tops = PackedInt32Array()
		tops_key = ""
		return
	var key := "%s|%s" % [world.get("built_version"), field]
	if key != tops_key:
		tops_key = key
		tops = M.column_tops(world.grid(), field)


# 돌풍: dir 쪽으로 흐르는 바람 줄 (긴 축 = dir, 카메라 쪽으로 돌려 세움). 높이는 지나는 자리의 바닥 위 (계단을 넘으면 부드럽게 따라감)
func _wind(dir: Vector2, field: Vector3i, a: float, cam: Vector3, low: bool, dt: float) -> void:
	var w: Dictionary = CFG.wind
	var n := M.count("wind", field, low, CFG)
	var rows := M.wind_rows(n, field, clock, dir, w, float(CFG.common.margin))
	var mm := _mm("wind", n)
	var axis := Co.gxyz(dir.x, dir.y, 0.0)
	var thin := float(CFG.common.thin)
	for i in n:
		var r: Array = rows[i]
		var gp: Vector3 = r[0]
		var base := M.surface_at(tops, field, gp.x, gp.y, lava_on, lava_z)
		if i >= wind_z.size():
			wind_z.append(base)
			wind_at.append(gp)
		elif absf(gp.x - wind_at[i].x) + absf(gp.y - wind_at[i].y) > float(CFG.common.margin) * 2.0: # 반대편에서 다시 나옴
			wind_z[i] = base
		else:
			wind_z[i] = M.follow(wind_z[i], base, dt, float(w.follow))
		wind_at[i] = gp
		var c := Co.gxyz(gp.x, gp.y, gp.z + float(wind_z[i]))
		var half := axis * (float(r[1]) * 0.5)
		var al := a * float(r[2]) * M.near_k(M.seg_dist(cam, c - half, c + half), CFG.common)
		_inst(mm, "wind", i, M.streak_xform(c, axis, float(r[1]), M.wide(float(w.width), cam.distance_to(c), thin), cam), Color(1, 1, 1, al))
	_show("wind", n)


# 저중력: 바닥에서 오르는 마름모 티끌 (꼬리가 아래, 카메라 쪽으로 돌려 세움)
func _lowgrav(field: Vector3i, a: float, cam: Vector3, low: bool) -> void:
	var g: Dictionary = CFG.lowgrav
	var n := M.count("lowgrav", field, low, CFG)
	var rows := M.mote_rows(n, field, clock, g)
	var mm := _mm("lowgrav", n)
	var thin := float(CFG.common.thin_mote)
	var long := 1.0 + float(g.tail)
	var cols := [col(g.colors[0]), col(g.colors[1])]
	for i in n:
		var r: Array = rows[i]
		var gp: Vector3 = r[0]
		var p := Co.gxyz(gp.x + float(r[3]), gp.y, gp.z + M.surface_at(tops, field, gp.x, gp.y, lava_on, lava_z))
		var c: Color = cols[int(r[1])]
		var d := cam.distance_to(p)
		var s := M.wide(float(g.size), d, thin)
		_inst(mm, "lowgrav", i, M.streak_xform(p, Vector3.UP, s * long, s, cam), Color(c.r, c.g, c.b, float(g.alpha) * a * float(r[2]) * M.near_k(d, CFG.common)))
	_show("lowgrav", n)


# 블록 폭우: 필드 위에서 내려오는 세로 줄 (메시 꼬리가 위)
func _rain(field: Vector3i, a: float, cam: Vector3, low: bool) -> void:
	var r: Dictionary = CFG.rain
	var n := M.count("rain", field, low, CFG)
	var rows := M.rain_rows(n, field, clock, r)
	var mm := _mm("rain", n)
	var half := Vector3.UP * (float(r.len) * 0.5)
	var thin := float(CFG.common.thin)
	for i in n:
		var e: Array = rows[i]
		var gp: Vector3 = e[0]
		var c := Co.gxyz(gp.x, gp.y, gp.z + M.surface_at(tops, field, gp.x, gp.y, lava_on, lava_z))
		_inst(mm, "rain", i, M.streak_xform(c, Vector3.UP, float(r.len), M.wide(float(r.width), cam.distance_to(c), thin), cam), Color(1, 1, 1, a * float(e[1]) * M.near_k(M.seg_dist(cam, c - half, c + half), CFG.common)))
	_show("rain", n)


# 빙판: 위험 액체에 안 잠긴 칸 윗면마다 하늘빛 판 (+ 반짝 줄). 격자가 바뀌면 다시 깔고, 프레임마다는 퍼짐 (보이는 수)·알파 (재질) 만
func _ice(field: Vector3i, a: float, low: bool) -> void:
	var ic: Dictionary = CFG.ice
	var steps: Array = FR.terrain_steps(world)
	var key := "%s|%s|%s|%s|%s|%s" % [world.get("built_version"), field, lava_on, floor(lava_z), low, steps]
	if key != ice_key:
		ice_key = key
		_lay_ice(field, steps, low)
	var t := clock - began
	var plates: MultiMeshInstance3D = layers.ice
	var glints: MultiMeshInstance3D = layers.glint
	var r := M.ice_radius(t, float(ice_rows.back()[3]) if not ice_rows.is_empty() else 0.0, float(ic.spread))
	var n := ice_rows.size() if t >= float(ic.spread) else M.ice_shown(ice_rows, r)
	var gn := 0
	for d in glint_dists:
		if float(d) > r:
			break
		gn += 1
	(plates.material_override as StandardMaterial3D).albedo_color.a = a
	(glints.material_override as StandardMaterial3D).albedo_color.a = a
	_show("ice", n)
	_show("glint", gn)


func _lay_ice(field: Vector3i, steps: Array, low: bool) -> void:
	var ic: Dictionary = CFG.ice
	var gl: Dictionary = ic.glint
	ice_rows = M.ice_cells(world.grid(), field, lava_on, lava_z, _bump(steps, field))
	var mm := _mm("ice", ice_rows.size())
	var size := 1.0 - float(ic.inset)
	var pb := Basis.from_scale(Vector3(size, 1, size))
	var pc := col(ic.color)
	pc.a = float(ic.alpha)
	var glints := []
	for i in ice_rows.size():
		var e: Array = ice_rows[i]
		_inst(mm, "ice", i, Transform3D(pb, Co.gxyz(e[0] + 0.5, e[1] + 0.5, float(e[2]) + float(ic.lift))), pc)
		if not low and M.glint_at(e[0], e[1], int(gl.every)):
			glints.append(e)
	var gm := _mm("glint", glints.size())
	var gc := col(gl.color)
	gc.a = float(gl.alpha)
	var gs := Basis.from_scale(Vector3(float(gl.len), 1, float(gl.width)))
	glint_dists = []
	for i in glints.size():
		var e: Array = glints[i]
		var turn := PI * 0.25 if M.glint_dir(e[0], e[1]) == 0 else -PI * 0.25
		_inst(gm, "glint", i, Transform3D(Basis(Vector3.UP, turn) * gs, Co.gxyz(e[0] + 0.5, e[1] + 0.5, float(e[2]) + float(ic.lift) + float(gl.lift))), gc)
		glint_dists.append(e[3])


# 꼭대기 칸이 테마 지형 칸이면 그 칸 윗면의 실제 높낮이 (world/foot_rings.gd 발밑 고리와 같은 길 — 고리는 여기에 lift 0.04, 판은 0.015). 쌓인 블록·건축가 블록·바닥판은 평평 (0)
func _bump(steps: Array, field: Vector3i) -> Callable:
	if float(steps[0]) == 0.0 and float(steps[1]) == 0.0:
		return Callable()
	var g: PackedByteArray = world.grid()
	var gv = world.get("grid_view")
	var skip: Dictionary = gv.skip if gv != null else {}
	return func(cx: int, cy: int, top: int) -> float:
		var i := ((top - 1) * field.y + cy) * field.x + cx
		if top <= 0 or i >= g.size() or g[i] != Cells.TERRAIN or skip.has(i):
			return 0.0
		return FR.top_bump(cx, cy, top - 1, float(steps[0]), float(steps[1]))


# 보급: 이벤트 뒤 새로 나타난 아이템 자리마다 빛 기둥 (life 초에 흐려짐, 먹히면 바로 지움) + 바닥 고리 한 번
func _supply(dt: float, st: Dictionary, field: Vector3i, cam: Vector3) -> void:
	var s: Dictionary = CFG.supply
	var items = st.get("items", [])
	var cur := M.item_cells(items)
	if armed > 0.0:
		var fresh := M.new_cells(armed_prev, items)
		if fresh.is_empty():
			armed -= dt
		else:
			armed = 0.0
			for e in fresh:
				if pillars.size() < int(s.max):
					pillars.append({"x": e[0], "y": e[1], "z": e[2], "key": e[3], "t0": clock})
	for i in range(pillars.size() - 1, -1, -1):
		if clock - float(pillars[i].t0) >= float(s.life) or not cur.has(pillars[i].key):
			pillars.remove_at(i)
	items_seen = cur
	if pillars.is_empty():
		_hide("pillar")
		_hide("ring")
		return
	_fit_box(field)
	var pm := _mm("pillar", pillars.size())
	var rm := _mm("ring", pillars.size())
	var h := float(s.h)
	var rings := 0
	for i in pillars.size():
		var p: Dictionary = pillars[i]
		var age := clock - float(p.t0)
		var base := Co.gxyz(p.x + 0.5, p.y + 0.5, p.z)
		var c := base + Vector3.UP * (h * 0.5)
		var al := float(s.alpha) * M.pillar_k(age, float(s.life)) * M.near_k(M.seg_dist(cam, base, base + Vector3.UP * h), CFG.common)
		_inst(pm, "pillar", i, M.streak_xform(c, Vector3.UP, h, M.wide(float(s.width), cam.distance_to(c), float(CFG.common.thin)), cam), Color(1, 1, 1, al))
		var ring: Array = M.ring_at(age, s.ring)
		if float(ring[1]) > 0.0:
			_inst(rm, "ring", rings, Transform3D(Basis.from_scale(Vector3(ring[0], 1, ring[0])), base + Vector3.UP * float(s.ring.lift)), Color(1, 1, 1, float(s.ring.alpha) * float(ring[1])))
			rings += 1
	_show("pillar", pillars.size())
	_show("ring", rings)
