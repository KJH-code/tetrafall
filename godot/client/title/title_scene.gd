# 타이틀 3D (client/title-scene.js TitleScene 자리): 테마 무대 (title_world.gd) 가운데에 테트리미노 블록이 떨어져 쌓이며 로고 (title_calc.gd).
# 캄캄하게 시작 → 장면 빛이 천천히 → 블록이 닿을 때마다 번쩍 → 다 쌓이면 빛 터짐 (블룸·불티·렌즈 플레어) → 빛 띠·반짝임.
# press() 하면 카메라가 로고 위로 날아가 장면 안쪽을 보는 메뉴 카메라로 자리 잡고, 그대로 메뉴 배경 (천천히 떠돎). menu=true 면 처음부터 메뉴 카메라.
# 게임 장면과 따로: 자기 카메라 + 카메라 전용 Environment (안개·주변광·블룸). 소리 신호: landed(n) · burst · exit_started
extends Node3D

signal landed(n: int)
signal burst
signal exit_started

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const TC := preload("res://title/title_calc.gd")
const F := preload("res://title/title_fx.gd")
const World := preload("res://title/title_world.gd")
const Cells := preload("res://world/cells.gd")
const LETTER := preload("res://title/letter.gdshader")
const SHELL := preload("res://title/shell.gdshader")
# 블룸: three UnrealBloomPass (선형 HDR) → 고도 Compatibility 글로 (LDR) 는 같은 값이면 약해서 배수로 맞춤 (JS 스샷과 나란히 비교)
const GLOW_K := 3.0
const GLOW_THR_K := 0.5
const GLOW_BLOOM := 0.05
const LETTER_K := 1.7 # 글자 빛·빛 줄기 (JS 는 블룸이 더 세게 번져 글자가 하얗게 보임)

var theme := ""
var T := {}
var low := false
var instant := false
var t := 0.0 # 로고 시계 (ms)
var fast := false
var exit_t = null # 빠져나가기 시작 뒤 ms
var menu_t := 0.0
var quiet := false
var burst_fired := false
var pieces: Array = []
var start: Array = []
var done_at := 0.0
var size := Vector2i.ZERO
var slots: Array = [] # 인스턴스 → [조각 번호, Vector2i 칸]
var by_piece: Array = []
var flash := PackedFloat32Array()
var stage: Node3D
var logo := Node3D.new() # 무대 좌표 (게임 좌표) 안
var mm := MultiMesh.new()
var shell_mm := MultiMesh.new()
var letter_mat := ShaderMaterial.new()
var shell_mat := ShaderMaterial.new()
var halo: MeshInstance3D
var streak: MeshInstance3D
var sparks := {}
var flare_src := Vector3.ZERO
var flares: Array = []
var cam := Camera3D.new()
var dist := 40.0
var aspect := 16.0 / 9.0


func setup(theme_id: String, opts := {}) -> void:
	theme = theme_id if C.TITLE_THEMES.has(theme_id) else TC.theme_ids()[0]
	T = C.TITLE_THEMES[theme]
	low = opts.get("low", false)
	var menu: bool = opts.get("menu", false)
	instant = opts.get("instant", false) or menu
	var r := TC.cells(C.TITLE_TEXT, int(C.TITLE_GAP), int(C.TITLE_BOLD))
	size = Vector2i(r.width, r.height)
	pieces = TC.pieces(r.cells)
	start = TC.drop_schedule(pieces, TC.interval(pieces.size()))
	done_at = 0.0 if instant else TC.done_at(start)
	if instant:
		t = C.TITLE_DARK_MS + C.TITLE_BURST_MS
	burst_fired = instant
	if menu:
		fast = true
		exit_t = C.TITLE_EXIT_MS + C.TITLE_EXIT_FADE_MS * 2
		quiet = true
	var s: float = C.TITLE_SCALE
	var logo_w := size.x * s
	var logo_h := size.y * s
	dist = TC.cam_dist(logo_w, C.TITLE_FOV, aspect)
	stage = World.new()
	stage.setup(theme, {"low": low, "logo_w": logo_w, "logo_h": logo_h, "cam_dist": dist})
	add_child(stage)
	stage.add_child(logo)
	# 글자 블록: 그 테마의 칸 색에 글자 색을 섞음 + 스스로 빛남
	var n: int = r.cells.size()
	flash.resize(n)
	var cols := Cells.piece_colors(C.WORLD_THEMES.get(theme, {}))
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for m in [mm, shell_mm]:
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = true
		m.use_custom_data = true
		m.mesh = box
		m.instance_count = n
	letter_mat.shader = LETTER
	letter_mat.set_shader_parameter("base_glow", C.TITLE_PIECE_GLOW + float(T.get("pieceGlow", 0.0)))
	letter_mat.set_shader_parameter("glow_col", Co.color(T.glow))
	letter_mat.set_shader_parameter("sweep_w", C.TITLE_SWEEP_W)
	shell_mat.shader = SHELL
	shell_mat.set_shader_parameter("col", Co.color(T.edge))
	var i := 0
	for pi in pieces.size():
		var p: Dictionary = pieces[pi]
		var col := Co.color(cols.get(p.shape, 0xffffff)).lerp(Co.color(T.letter[pi % T.letter.size()]), C.TITLE_LETTER_MIX)
		for c in p.cells:
			mm.set_instance_color(i, col)
			slots.append([pi, c])
			i += 1
	by_piece.resize(pieces.size())
	for k in pieces.size():
		by_piece[k] = []
	for k in slots.size():
		by_piece[slots[k][0]].append(k)
	for pair in [[mm, letter_mat], [shell_mm, shell_mat]]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = pair[0]
		mi.material_override = pair[1]
		mi.extra_cull_margin = 16384.0
		logo.add_child(mi)
	# 빛 터짐: 로고 뒤 큰 빛 + 가로 줄기 + 불티
	halo = F.glow_sprite(T.glow, logo_w * 1.5, logo_h * 4.5, 0.0)
	halo.position = Vector3(0, 3, 0)
	streak = F.glow_sprite(T.flare, logo_w * 2.4, 1.6, 0.0)
	streak.position = Vector3(0, -1, 0)
	logo.add_child(halo)
	logo.add_child(streak)
	_make_sparks(int(C.TITLE_SPARKS[1 if low else 0]))
	flare_src = Vector3(-logo_w * 0.4, 8, logo_h * 1.9)
	if not low:
		for f in [[0, 1.4, 0.6], [0.35, 0.5, 0.25], [0.6, 0.3, 0.35], [0.85, 0.9, 0.15], [1.25, 0.4, 0.25], [1.6, 1.4, 0.12]]:
			var sp := F.glow_sprite(T.flare, f[1], f[1], 0.0)
			var mat: StandardMaterial3D = sp.material_override
			mat.no_depth_test = true
			mat.render_priority = 10
			sp.set_meta("f", f)
			sp.layers = 1 << (World.MIRROR_LAYER - 1) # 거울에 안 비침
			add_child(sp) # 고도 좌표 (카메라 앞에 놓음)
			flares.append(sp)
	# 카메라 + 블룸 (그래픽 낮춤이면 블룸 없음)
	cam.fov = C.TITLE_FOV
	cam.near = 0.1
	cam.far = 400.0
	var env: Environment = stage.env
	if not low:
		env.glow_enabled = true
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_hdr_threshold = C.TITLE_BLOOM[2] * GLOW_THR_K
		env.glow_intensity = C.TITLE_BLOOM[0] * GLOW_K
		env.glow_bloom = GLOW_BLOOM
		for lv in 7:
			env.set_glow_level(lv, 1.0 if lv >= 1 and lv <= 5 else 0.0)
	cam.environment = env
	add_child(cam)
	_place()
	step(0.0)


func _make_sparks(n: int) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.mesh = q
	m.instance_count = n
	m.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_fog = true
	mat.albedo_texture = F.glow_tex()
	var c := Co.color(T.edge) * 1.6
	c.a = 0.0
	mat.albedo_color = c
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = m
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	logo.add_child(mi)
	sparks = {"mm": m, "mat": mat, "pos": PackedVector3Array(), "vel": PackedVector3Array(), "n": n, "age": INF}
	sparks.pos.resize(n)
	sparks.vel.resize(n)


func _fire_sparks() -> void:
	var s: float = C.TITLE_SCALE
	for i in sparks.n:
		var c: Vector2i = slots[randi() % slots.size()][1]
		sparks.pos[i] = Vector3((c.x - size.x / 2.0 + 0.5) * s, -0.4, (c.y - size.y / 2.0 + 0.5) * s)
		var a := randf() * TAU
		var sp := 3 + randf() * 9
		sparks.vel[i] = Vector3(cos(a) * sp, -randf() * 4, sin(a) * sp * 0.7 + 3)
	sparks.age = 0.0
	sparks.mm.visible_instance_count = sparks.n


func _step_sparks(dt: float) -> void:
	if sparks.age == INF:
		return
	sparks.age += dt
	for i in sparks.n:
		var v: Vector3 = sparks.vel[i]
		v.z -= 6 * dt
		v *= 1.0 - 1.4 * dt
		sparks.vel[i] = v
		sparks.pos[i] += v * dt
		sparks.mm.set_instance_transform(i, Transform3D(Basis(), sparks.pos[i]))
	sparks.mat.albedo_color.a = maxf(0.0, 1.0 - sparks.age / 1.6)
	if sparks.age > 1.6:
		sparks.age = INF
		sparks.mm.visible_instance_count = 0


# 블록 자리 (지금 시계로)
func _place() -> void:
	var s: float = C.TITLE_SCALE
	var one := s * 0.97
	var big := s * (1.0 + C.TITLE_OUTLINE)
	for i in slots.size():
		var pi: int = slots[i][0]
		var c: Vector2i = slots[i][1]
		var lift = 0.0 if instant else TC.lift(t, start[pi])
		var pos := Vector3((c.x - size.x / 2.0 + 0.5) * s, 0, (c.y - size.y / 2.0 + 0.5 + (lift if lift != null else 0.0)) * s)
		var k := 0.0 if lift == null else 1.0
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * one * k), pos))
		shell_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * big * k), pos))
		mm.set_instance_custom_data(i, Color(flash[i], pos.x, one, 0))


func is_done() -> bool:
	return t >= done_at


func ready_hint() -> bool:
	return instant or t >= done_at + C.TITLE_HINT_DELAY_MS


func press() -> void:
	fast = true


func exit_state():
	return null if exit_t == null else TC.exit(exit_t, instant)


func in_menu() -> bool:
	var e = exit_state()
	return e != null and e.done


func step(dt: float) -> void:
	var ms := dt * 1000.0
	var t0 := t
	if not is_done():
		t = minf(done_at, t + ms * (C.TITLE_FAST if fast else 1.0))
	else:
		t += ms
		if fast and exit_t == null:
			exit_t = 0.0
			if not quiet:
				exit_started.emit()
	if exit_t != null:
		exit_t += ms
	if in_menu():
		menu_t += ms
	if not instant:
		var got := TC.landed_between(start, t0, minf(t, done_at))
		for pi in got:
			for k in by_piece[pi]:
				flash[k] = 1.0
		if not got.is_empty():
			landed.emit(got.size())
	if not burst_fired and t >= done_at:
		burst_fired = true
		_fire_sparks()
		burst.emit()
	if t > done_at + C.TITLE_BURST_MS * 0.5:
		var want: float = C.TITLE_TWINKLE * (slots.size() / 100.0) * dt
		for k in 4:
			if randf() < want / 4.0:
				flash[randi() % flash.size()] = 0.7
	var fall := exp(-dt * 1000.0 / C.TITLE_LAND_FLASH_MS * 3.0)
	for k in flash.size():
		flash[k] *= fall
	_place()
	_step_sparks(dt)
	var L := TC.light(t, done_at)
	var ex = exit_state()
	var push: float = ex.push if ex != null else 0.0
	var wh: float = ex.white if ex != null else 0.0
	letter_mat.set_shader_parameter("glow", L.glow * (1.0 + wh * 2.0) * LETTER_K)
	var sweep_u := t - done_at - C.TITLE_BURST_MS * 0.7
	var sweep_p := fposmod(sweep_u, C.TITLE_SWEEP_MS) / C.TITLE_SWEEP_MS
	var lw := size.x * C.TITLE_SCALE
	letter_mat.set_shader_parameter("sweep_x", -1e4 if sweep_u < 0 else -lw * 0.8 + sweep_p * lw * 2.4)
	shell_mat.set_shader_parameter("k", minf(3.0, 0.3 + L.glow * 1.6))
	F.set_opacity(halo, minf(1.0, L.burst * 0.18 + (0.04 if t >= done_at else 0.0)) * (1.0 - push))
	halo.scale = Vector3(size.x * C.TITLE_SCALE * (1.15 + L.burst * 0.3), size.y * C.TITLE_SCALE * (1.8 + L.burst * 1.4), 1)
	F.set_opacity(streak, minf(1.0, (L.burst * 0.8 + (0.15 if t >= done_at else 0.0)) * LETTER_K) * (1.0 - push))
	stage.update(t / 1000.0, minf(1.0, L.lit + L.burst * 0.5))
	# 카메라 (게임 좌표로 계산, 마지막에 고도 좌표)
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	var a := vp.x / maxf(1.0, vp.y)
	if absf(a - aspect) > 1e-4:
		aspect = a
		dist = TC.cam_dist(lw, C.TITLE_FOV, aspect)
	var ts := t / 1000.0
	var build := minf(1.0, t / maxf(1.0, done_at + C.TITLE_BURST_MS))
	var d := dist * (1.0 + C.TITLE_CAM_PUSH * (1.0 - build))
	var sway := sin(ts * 0.5) * C.TITLE_CAM_SWAY
	var shake: float = L.burst * L.burst * 0.25
	var fly: Array = C.TITLE_EXIT_FLY
	var ey: float = -d + push * d * (1.0 - fly[0])
	var ez: float = C.TITLE_CAM_UP + sin(ts * 0.37) * 0.4 + push * fly[1]
	var dr := TC.menu_drift(menu_t)
	var px: float = (C.TITLE_CAM_SIDE + sway) * (1.0 - push) + dr[0] + (randf() - 0.5) * shake
	var eye := Vector3(px, ey, ez + dr[1] + (randf() - 0.5) * shake)
	var ly: float = push * d * fly[2] - ey
	var look := Vector3(eye.x * push + sin(dr[2]) * ly, ey + cos(dr[2]) * ly, push * fly[3])
	cam.fov = C.TITLE_FOV + push * 18.0
	var g_eye := Co.gxyz(eye.x, eye.y, eye.z)
	var g_look := Co.gxyz(look.x, look.y, look.z)
	cam.transform = Transform3D(Basis.looking_at(g_look - g_eye, Vector3.UP), g_eye)
	_place_flares(L.burst * (1.0 - push), t >= done_at and push < 0.3)
	if cam.is_inside_tree():
		stage.mirror_update(cam) # (update 는 카메라를 놓기 전에 불려서 여기서 한 번 더)
	if stage.env.glow_enabled:
		stage.env.glow_intensity = (C.TITLE_BLOOM[0] + (C.TITLE_BLOOM_BURST - C.TITLE_BLOOM[0]) * maxf(L.burst, wh)) * GLOW_K


# 렌즈 플레어: 빛 자리를 화면에 비춰, 화면 가운데를 지나 반대쪽으로 동그라미 (카메라 앞 일정 거리)
func _place_flares(b: float, lit: bool) -> void:
	if flares.is_empty() or not cam.is_inside_tree():
		return
	var src := Co.gxyz(flare_src.x, flare_src.y, flare_src.z)
	var vp := get_viewport().get_visible_rect().size
	var sp := cam.unproject_position(src)
	var ndc := Vector2(sp.x / vp.x * 2.0 - 1.0, 1.0 - sp.y / vp.y * 2.0)
	var on := minf(1.0, b * 1.3 + (0.25 if lit else 0.0))
	var depth := 6.0
	var hh := tan(deg_to_rad(cam.fov) / 2.0) * depth
	for f in flares:
		var m: Array = f.get_meta("f")
		var q: Vector2 = ndc * (1.0 - 2.0 * m[0])
		var scr := Vector2((q.x + 1.0) / 2.0 * vp.x, (1.0 - q.y) / 2.0 * vp.y)
		f.global_position = cam.project_position(scr, depth)
		var s: float = m[1] * hh / 8.0
		f.scale = Vector3(s, s, 1)
		F.set_opacity(f, on * m[2])
