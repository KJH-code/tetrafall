# 판 그리기 (G1, godot/PLAN.md 7절): main 이 world/world.tscn 을 붙임. 하늘·빛·안개 (맵 테마) + 격자 칸 + 떨어지는 블록·그림자
# + 위험 + 사람 몸 자리 + 하늘 시점 도우미 + 아이템 + 카메라. 서버 상태는 Store 에서 읽기만
# 다른 묶음 자리: 몸 = G2 chars/chars.gd · 셰이더 = G3 shaders/ · 효과 = G5 fx/ (fx_root 에 붙임) · 건축가 블록 = G6 world/bblocks.gd
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Cells := preload("res://world/cells.gd")
const WC := preload("res://world/world_config.gd")
const GridView := preload("res://world/grid_view.gd")
const PiecesView := preload("res://world/pieces_view.gd")
const HazardView := preload("res://world/hazard_view.gd")
const Bodies := preload("res://world/bodies.gd")
const SkyAids := preload("res://world/sky_aids.gd")
const ItemsView := preload("res://world/items_view.gd")
const GhostAim := preload("res://world/ghost_aim.gd")
const Scenery := preload("res://world/scenery.gd")
const LP := preload("res://world/lobby_preview.gd")
const Prof := preload("res://core/prof.gd") # 성능 구간 재기 (--perf-log 만)
const Marks := preload("res://world/marks.gd")
const LightFx := preload("res://world/light_fx.gd")
const Shots := preload("res://world/shots.gd")
const HookFx := preload("res://world/hook_fx.gd")
const BodyFx := preload("res://world/body_fx.gd")
const CamRig := preload("res://world/cam_rig.gd")
const LobbyDark := preload("res://world/lobby_dark.gd")
const BBLOCKS := "res://world/bblocks.gd"
const FX := "res://fx/fx.gd" # G5 효과 (있으면 fx_root 에 붙이고 setup(rig): 카메라 흔들림·KO 줌은 rig.hook)
const G3_PATH := "res://shaders/g3.gd" # G3 툰·테마 (있으면 하늘·빛·안개·블록 재질을 G3 가 맡음)

var env := Environment.new()
var sky_mat := ProceduralSkyMaterial.new()
var sun := DirectionalLight3D.new()
var grid_view: Node3D
var pieces_view: Node3D
var hazard_view: Node3D
var bodies: Node3D
var sky_aids: Node3D
var items_view: Node3D
var ghost_aim: Node3D
var scenery: Node3D
var marks: Node3D # 판 쪽 연출 (잔상 줄·예고 칸·블록 출렁·솟는 땅·압사 납작 몸)
var light_fx: Node3D # 판 빛 무리·빛 터짐 (game-light.js 3D 부분)
var shots: Node3D # 폭탄·포탄·음표·표창·조준점·화살·조종 줄
var hook_fx: Node3D # 갈고리 밧줄·R 덩어리, 끌려오는 몸 (slides)
var body_fx: Node3D # 몸 둘레 따로 그리는 것 (필살기 고리·R 찬 빛·표식·취약·앰프·소용돌이·대기 표시·위험 고리)
var last_phase := ""
var marks_demo := false # 확인용 (명령줄 --marks-demo): 판 중 1.5초마다 내 앞에 가짜 잔상·예고·출렁·솟는 땅·빛
var _demo_next := 0.0
var rig: Node3D
var bblocks = null # G6 건축가 블록 (있으면 update(state)·skip() 을 부름)
var fx_root := Node3D.new() # G5 효과 노드가 붙을 자리
var theme_id = null
var theme := {}
var field := Vector3i.ZERO # 지금 판 크기 (w, d, h)
var built_version = -2 # 마지막으로 깐 격자 (서버 gridVersion 또는 미리보기 key)
var headless := false
var G3 = null
var preview = null # 대기실 지형 미리보기 {key, grid, top, w, d, h, off} (LP.build), 없으면 서버 격자
var sprouts = null # G3 튀어나온 조각 노드 (테마마다)
var _menu_since := -1.0 # 메뉴에 머문 시각 (prewarm)
var _prewarmed = null # 셰이더 미리 데운 테마 (G3.prewarm)
var dark = null # 대기실 어두운 무대 (lobby_dark.gd), 대기실 아니면 null
var vm = null # G2 1인칭 팔·무기 (chars/viewmodel.gd)
const VIEWMODEL := "res://chars/viewmodel.gd"


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	if ResourceLoader.exists(G3_PATH):
		G3 = load(G3_PATH)
	var we := WorldEnvironment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR # JS 판은 톤 매핑 없음
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	we.environment = env
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	if G3 == null:
		add_child(we)
		add_child(sun)
	else:
		we.free() # 하늘·빛·안개는 G3 의 'G3Env'
		sun.free()
		sun = null
	grid_view = GridView.new()
	pieces_view = PiecesView.new()
	hazard_view = HazardView.new()
	bodies = Bodies.new()
	bodies.pos_fn = shown_pos
	sky_aids = SkyAids.new()
	items_view = ItemsView.new()
	rig = CamRig.new()
	ghost_aim = GhostAim.new()
	scenery = Scenery.new()
	hazard_view.scenery = scenery # 먼 섬 잠김 테 (far_objects)
	hazard_view.bodies = bodies # 잠기는 몸
	marks = Marks.new()
	light_fx = LightFx.new()
	shots = Shots.new()
	hook_fx = HookFx.new()
	body_fx = BodyFx.new()
	rig.ghost_aim = ghost_aim
	for n in [scenery, grid_view, pieces_view, hazard_view, bodies, sky_aids, items_view, ghost_aim, marks, light_fx, shots, hook_fx, body_fx, rig, fx_root]:
		add_child(n)
	fx_root.name = "Fx"
	if ResourceLoader.exists(FX):
		var fx = load(FX).new()
		fx_root.add_child(fx)
		fx.setup(rig)
	if ResourceLoader.exists(VIEWMODEL):
		vm = load(VIEWMODEL).new()
		add_child(vm)
	if ResourceLoader.exists(BBLOCKS):
		bblocks = load(BBLOCKS).new()
		add_child(bblocks)
	if g3_has("game_light"):
		# 판 빛 (B3 game_light.gd = game-light.js 전부: 색 보정·비네트·하늘 어둡게·빛 무리·빛 터짐) — 내 light_fx (3D 부분만) 대신
		remove_child(light_fx)
		light_fx.queue_free()
		light_fx = G3.game_light(self)
	if G3 != null:
		grid_view.set_material(G3.toon_material(Color.WHITE, {"vertex_color": true}))
		grid_view.make_mat = func(c: Color): return G3.toon_material(c)
		bodies.make_mat = grid_view.make_mat
		marks.make_mat = grid_view.make_mat
		shots.make_mat = grid_view.make_mat
		hook_fx.make_mat = grid_view.make_mat
		body_fx.make_mat = grid_view.make_mat
		# 섬·먼 배경: G3.scenery_material 이 있으면 그것 (안개 끄기·빛 안 받음 포함), 없으면 툰 + 기본 재질
		if g3_has("scenery_material"):
			scenery.make_mat = G3.scenery_material
		else:
			scenery.make_mat = func(o: Dictionary):
				if o.get("unshaded", false):
					return null
				var opts := {"vertex_color": true, "outline": o.get("outline", true)}
				if o.has("emissive"):
					opts.emissive = o.emissive
				return G3.toon_material(Color.WHITE, opts)
		pieces_view.mats = [G3.toon_material(Color.WHITE, {"vertex_color": true}), G3.toon_material(Color.WHITE, {"vertex_color": true, "opacity": WC.PIECE_SKY_ALPHA})]
	apply_theme("")
	# 확인용 명령줄 (-- 뒤): --world-view over|third|first · --map <맵 id> · --mode <모드> · --hp (체력전) (방장이면 대기실에서 바꿈)
	var args := {}
	var list := OS.get_cmdline_user_args()
	for i in list.size():
		if list[i].begins_with("--") and i + 1 < list.size() and not list[i + 1].begins_with("--"):
			args[list[i].substr(2)] = list[i + 1]
	rig.force = str(args.get("world-view", ""))
	marks_demo = args.has("marks-demo") or OS.get_cmdline_user_args().has("--marks-demo")
	Store.joined.connect(func(_room, _re):
		if args.has("map"):
			Store.send_room({"type": "setMap", "map": args.map})
		if args.has("mode"):
			Store.send_room({"type": "setMode", "mode": args.mode})
		if list.has("--hp"):
			Store.send_room({"type": "hpMode", "on": true}))
	Store.game_event.connect(bodies.on_event)
	Store.game_event.connect(_light_event)
	marks.solid = solid_at
	marks.bodies = bodies
	shots.solid = solid_at
	shots.bodies = bodies
	shots.marks = marks
	shots.cam = rig.cam
	hook_fx.bodies = bodies
	hook_fx.marks = marks
	hook_fx.my_view_on = func() -> bool: return View.mode == "first"
	body_fx.bodies = bodies
	body_fx.marks = marks
	body_fx.slides = hook_fx.slides
	body_fx.third = func() -> bool: return View.mode != "first"
	for n in fx_root.get_children(): # G5 파편·고리 (유령 투하 펑·녹음 불티)
		if n.get("effects") != null:
			marks.effects = n.effects
			shots.effects = n.effects
			hook_fx.effects = n.effects
			body_fx.effects = n.effects
			hazard_view.effects = n.effects
	View.changed.connect(func(k):
		if k == "lowGfx":
			if g3_has("set_low"):
				G3.set_low(self, View.settings.lowGfx) # B3: 이미 만든 지형·칸·위험 재질·튀어나온 조각·판 빛·그림자를 곧바로
			set_shadows(not View.settings.lowGfx)
			apply_theme(str(theme_id))) # 지형 셰이더·튀어나온 조각도 낮춤으로
	if g3_has("set_low"):
		G3.set_low(self, bool(View.settings.get("lowGfx", false)))
	set_shadows(not View.settings.get("lowGfx", false))


# G3 에 이 함수가 있나 (B3 가 차례로 올리는 재질: 합치는 순서가 달라도 됨)
func g3_has(fn: String) -> bool:
	if G3 == null:
		return false
	for m in G3.get_script_method_list():
		if m.name == fn:
			return true
	return false


func set_shadows(on: bool) -> void:
	if G3 != null:
		G3.set_shadows(self, on)
	else:
		sun.shadow_enabled = on


# 맵 id → 테마 (WORLD_MAP_THEME·WORLD_THEMES 색만, 꾸밈은 G3). 표에 없는 맵은 예전 노을 (SKY_*·FOG_*)
func apply_theme(map_id: String) -> void:
	theme = Cells.theme_of(map_id)
	theme_id = map_id
	grid_view.set_theme(theme)
	pieces_view.piece_colors = Cells.piece_colors(theme)
	hazard_view.set_theme(theme)
	built_version = -2 # 칸 색이 바뀜 → 다시 깖
	if G3 != null:
		var tid = C.WORLD_MAP_THEME.get(map_id)
		var low := bool(View.settings.get("lowGfx", false))
		G3.apply_theme(self, tid, low)
		grid_view.set_terrain_look(G3.terrain_mesh(tid), G3.terrain_material(tid, low), G3.terrain_custom)
		var fm = G3.floor_material(tid) if g3_has("floor_material") else null
		if fm != null:
			grid_view.floor_mesh.material_override = fm # 바닥 판: 윗면 체크·칸 선·테마 무늬, 옆면 테두리
		if sprouts != null:
			sprouts.queue_free()
		sprouts = G3.sprout_node(tid)
		if sprouts != null:
			grid_view.add_child(sprouts) # 판 밖 (메뉴) 에선 grid_view 와 같이 숨음
		if g3_has("hazard_material"):
			hazard_view.set_g3(G3, tid, low) # 위험 액체 (B3): 필드 판 + 지평선 바다, 물들임
		if g3_has("piece_mesh"):
			# 테트리미노 칸 (B3 PieceLook): 떨어지는 칸·쌓인 칸 모양·재질·조각 색, 빛 테두리 = GAME_LIGHT 안 rim (그래픽 낮춤이면 0)
			light_fx.low = low
			var rim: float = light_fx.rim
			var pm: Mesh = G3.piece_mesh(tid, low)
			var cols: Dictionary = G3.piece_colors(tid)
			pieces_view.set_look(pm, [G3.piece_material(tid, low, {"rim": rim}), G3.piece_material(tid, low, {"rim": rim, "transparent": true, "opacity": 1.0})], cols)
			grid_view.set_piece_look(pm, G3.piece_material(tid, low, {"rim": rim, "outline": false}), cols) # 쌓인 칸은 외곽선 없음 (render.js landed noOutline)
		return
	var sk: Dictionary = theme.get("sky", {})
	sky_mat.sky_top_color = Co.color(sk.get("top", C.SKY_TOP))
	sky_mat.sky_horizon_color = Co.color(sk.get("horizon", C.SKY_HORIZON))
	sky_mat.ground_horizon_color = Co.color(sk.get("horizon", C.SKY_HORIZON))
	sky_mat.ground_bottom_color = Co.color(sk.get("below", C.SKY_MID))
	sky_mat.sky_curve = 0.12
	var fog: Array = theme.get("fog", [C.SKY_HORIZON, C.FOG_NEAR, C.FOG_FAR])
	env.fog_light_color = Co.color(fog[0])
	env.fog_depth_begin = float(fog[1])
	env.fog_depth_end = float(fog[2])
	var hemi: Array = theme.get("hemi", [WC.AMBIENT_DEFAULT[0], 0x000000, WC.AMBIENT_DEFAULT[1] / WC.HEMI_ENERGY])
	env.ambient_light_color = Co.color(hemi[0]).lerp(Co.color(hemi[1]), 0.35)
	env.ambient_light_energy = float(hemi[2]) * WC.HEMI_ENERGY
	var sd: Array = theme.get("sunDir", C.SUN_DIR)
	var to_sun := Co.gxyz(sd[0], sd[1], sd[2]).normalized()
	sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD), Vector3.ZERO)
	sun.light_color = Co.color(theme.get("sunColor", 0xfff0d8))
	sun.light_energy = float(theme.get("sunIntensity", 1.0)) * WC.SUN_ENERGY


func _marks_demo() -> void:
	var p := Store.me()
	if p.is_empty():
		return
	var x := floori(p.x)
	var y := floori(p.y)
	var z := 0.0
	marks.trail(Vector3(p.x, p.y, p.z + 0.9), Vector3(p.x + 3, p.y + 1, p.z + 0.9), 0xffffff, 1200)
	marks.mark_circle(p.x + 2, p.y - 2, p.z, 1.5, 0xff3020, 1400)
	marks.mark_cells([[x - 2, y + 2, int(p.z)], [x - 1, y + 2, int(p.z)], [x - 2, y + 3, int(p.z)]], 0xffd23a, 1400)
	marks.streak_up(Vector3(p.x - 1, p.y - 1, p.z), 2.4, 0xffffff, 900)
	var top := []
	for dx in 3:
		top.append([x + dx, y + 3, column_top(x + dx, y + 3) - 1])
	marks.block_pulse(top, 0xffffff, 600, 0.3, 0.75)
	marks.quake_rise([[x + 3, y - 1, int(p.z)], [x + 3, y, int(p.z)]], 1000, 999)
	light_fx.flash(p.x + 1, p.y, p.z + 1, light_color(), 5, 560)


# 판 빛 터짐 (main.js 의 renderer.lightLand·lightBurst 자리): 착지 = 칸마다 그 블록 색, KO (압사·낙사)·필살기 = 테마 빛 색
func _light_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"land":
			var L: Array = C.GAME_LIGHT_FLASH.land
			for c in e.get("cells", []):
				var i := (int(c[2]) * field.y + int(c[1])) * field.x + int(c[0])
				var v: int = Store.grid[i] if i >= 0 and i < Store.grid.size() else 0
				light_fx.flash(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5, Cells.cell_color(v, pieces_view.piece_colors) if v else 0xffffff, L[0], L[1])
		"death":
			var cause := str(e.get("cause", ""))
			var t := Store.player(e.get("who"))
			if (cause == "crush" or cause == "fall") and not t.is_empty():
				var K: Array = C.GAME_LIGHT_FLASH.ko
				light_fx.flash(t.x, t.y, t.z + 0.8, light_color(), K[0], K[1])
		"ult":
			var a := Store.player(e.get("who"))
			if not a.is_empty():
				var U: Array = C.GAME_LIGHT_FLASH.ult
				light_fx.flash(a.x, a.y, a.z + 1, int(C.ULT_AURA_COLOR), U[0], U[1])


# 테마 빛 색 (KO·필살기 빛, render.js lightColor): 테마 glow 첫 색, 없으면 따뜻한 흰빛
func light_color() -> int:
	var g = theme.get("glow")
	if g is Array and not g.is_empty():
		return int(g[0])
	var tg = theme.get("terrain", {}).get("glow")
	return int(tg) if tg != null else int(C.GAME_LIGHT_FLASH.color)


# 지금 그리는 격자: 대기실 미리보기면 그것, 아니면 서버 격자
func grid() -> PackedByteArray:
	return preview.grid if preview != null else Store.grid


# 대기실 미리보기: 사람은 화면만 큰 판 가운데·그 칸 위로 (render.js render 의 previewOff·previewTop)
func shown_pos(p: Dictionary, pos: Vector3) -> Vector3:
	# 끌려오는·미끄러지는 몸 (render.js slides): from → 서버 자리 (또는 to) 로 ease-out
	var sl = hook_fx.slides.get(int(p.id)) if hook_fx != null else null
	if sl != null and p.alive:
		var u: float = (Time.get_ticks_msec() - sl.t0) / sl.ms
		var k := 0.0 if u <= 0 else 1 - (1 - u) * (1 - u)
		var to: Vector3 = sl.to if sl.to != null else pos
		pos = Vector3(lerpf(sl.from.x, to.x, k), lerpf(sl.from.y, to.y, k), lerpf(sl.from.z, pos.z, k))
	if preview == null:
		return pos
	pos += Vector3(preview.off, preview.off, 0)
	if p.alive:
		pos.z = maxf(pos.z, LP.top_at(preview, pos.x, pos.y))
	return pos


# 격자 칸이 단단한가 (게임 좌표, render.js solidAt): 필드 밖 = 빈칸, 바닥 아래 = 단단함
func solid_at(x: float, y: float, z: float) -> bool:
	var gx := floori(x)
	var gy := floori(y)
	var gz := floori(z)
	if gx < 0 or gy < 0 or gx >= field.x or gy >= field.y:
		return false
	if gz < 0:
		return true
	if gz >= field.z:
		return false
	var i := (gz * field.y + gy) * field.x + gx
	var g := grid()
	return i < g.size() and g[i] != 0


func _process(dt: float) -> void:
	var st := Store.state
	# 방 밖 (메뉴): 판 노드를 숨김 (크기 안 정한 바닥·절벽 상자가 원점 카메라 앞을 가르던 것). 하늘·빛 (G3Env)·효과는 그대로
	var live: bool = not st.is_empty() and st.has("field")
	for n in [scenery, grid_view, pieces_view, hazard_view, bodies, sky_aids, items_view, ghost_aim, marks, light_fx, shots, hook_fx, body_fx]:
		n.visible = live and ((n != hazard_view and n != ghost_aim) or n.visible) and (n != scenery or dark == null) # 어두운 무대면 떠 있는 섬·먼 배경 숨김
	if not live and vm != null:
		vm.update(null, false, dt) # 방 밖: 1인칭 팔 끔
	# 첫 진입 멈춤 줄이기 (render.js prewarmLobby): 메뉴에 LOBBY_DARK.prewarmMs 머문 뒤 이번 창 테마로 한 번 (B3 G3.prewarm)
	if not live and _prewarmed == null and g3_has("prewarm"):
		var tn := Time.get_ticks_msec() * 1.0
		if _menu_since < 0:
			_menu_since = tn
		elif tn - _menu_since > float(C.LOBBY_DARK.prewarmMs):
			_prewarmed = str(View.menu_theme)
			G3.prewarm(self, View.menu_theme)
	elif live:
		_menu_since = -1.0
	if headless or not live:
		return
	dt *= View.time_scale # KO 슬로모션 (G5 가 정함)
	Prof.begin()
	var now := Time.get_ticks_msec() * 1.0
	var f: Dictionary = st.field
	var fs := Vector3i(int(f.w), int(f.d), int(f.get("h", C.GRID_H)))
	# 대기실: 고른 맵의 시작 지형을 지금 인원 판 크기로 미리 깖 (render.js lobbyPreview), 테마도 그 맵
	var pk = LP.pick(st, View.menu_theme)
	var mid := str(pk) if pk != null else str(st.get("map", {}).get("id", ""))
	if mid != theme_id:
		apply_theme(mid)
	if pk != null:
		var n := LP.lobby_field_size(st)
		var key := "%s:%d:%d" % [pk, n, fs.z]
		if preview == null or preview.key != key:
			preview = LP.build(pk, n, fs.z)
			preview.key = key
		preview.off = (n - fs.x) / 2.0
		fs = Vector3i(n, n, fs.z)
	else:
		preview = null
	if fs != field:
		field = fs
		grid_view.set_field(fs.x, fs.y)
		if G3 != null:
			G3.set_field(self, fs.x, fs.y)
		built_version = -2
	_lobby_dark(st, fs)
	scenery.build(C.WORLD_MAP_THEME.get(theme_id), fs.x, fs.y, bool(View.settings.get("lowGfx", false)), fs.z)
	scenery.step(dt)
	Prof.lap("world 섬·대기실")
	if bblocks != null:
		bblocks.update(st)
		grid_view.skip = bblocks.skip()
	var gkey = preview.key if preview != null else Store.grid_version
	var g := grid()
	if str(gkey) != str(built_version) and g.size() == fs.x * fs.y * fs.z:
		grid_view.rebuild(g, fs.x, fs.y, fs.z)
		built_version = gkey
		if sprouts != null:
			G3.sprout_update(sprouts, g, fs.x, fs.y, fs.z, grid_view.skip, bool(View.settings.get("lowGfx", false)))
	Prof.lap("world 격자·건축 블록")
	rig.pre(dt)
	var sky_on: bool = rig.sky_blend > 0.5
	bodies.update(st, Store.my_id, rig.hide_me(), sky_on, now)
	Prof.lap("world bodies.update (몸 자세)")
	rig.field_size = Vector2(fs.x, fs.y)
	var ph := str(st.get("phase", ""))
	if ph != last_phase:
		marks.phase_changed() # 판 시작·끝: 서버가 솟은 땅을 버림
		last_phase = ph
	if marks_demo and ph == "playing" and now >= _demo_next:
		_demo_next = now + 1500.0
		_marks_demo()
	marks.step()
	shots.update(st, dt)
	hook_fx.piece_colors = pieces_view.piece_colors
	hook_fx.step()
	Prof.lap("world 표식·투사체·갈고리")
	if marks_demo and ph == "playing": # 확인용: 다른 사람마다 내 표식 (1.5초마다 하나씩 늘어남 → 꽉 차면 다시)
		var k := int(now / 1500.0) % 4
		var i := 0
		for p in st.players:
			if Store.my_id != null and int(p.id) == Store.my_id:
				continue
			var n := (k + i) % 4
			var had: int = int(p.marks[0].n) if p.get("marks") is Array and not p.marks.is_empty() else 0
			p.marks = [{"by": Store.my_id, "n": n, "left": 9000.0}] if n > 0 else []
			if n > had:
				body_fx.on_event({"type": "mark", "by": Store.my_id, "target": p.id, "n": n})
			i += 1
	body_fx.update(st, Store.my_id, dt)
	Prof.lap("world body_fx")
	light_fx.low = bool(View.settings.get("lowGfx", false))
	var halos := []
	var lit := ph == "countdown" or ph == "playing" or ph == "over"
	if lit:
		for pc in st.get("pieces", []):
			if pc.get("thrown", false):
				continue
			var col: int = 0xffffff if str(pc.get("shape", "")) == "ghost" else (WC.CONTROLLED_COLOR if pc.get("controller") != null else int(pieces_view.piece_colors.get(str(pc.get("shape", "")), 0xffffff)))
			for c in pc.cells:
				halos.append([c[0] + 0.5, c[1] + 0.5, c[2] + 0.5, col, 0.7 if pc.get("sky", false) else 1.0])
		for it in st.get("items", []):
			halos.append([it.x + 0.5, it.y + 0.5, it.z + 0.5, int(C.GAME_LIGHT_ITEM), 0.6])
	light_fx.frame(lit, halos, dt)
	Prof.lap("world 판 빛")
	var me := Store.me()
	pieces_view.update(st, Store.my_id, me, rig.sky_blend)
	Prof.lap("world 떨어지는 칸")
	hazard_view.update(st, Store.grid, Store.grid_version, me, dt)
	Prof.lap("world 위험")
	grid_view.cliff.visible = scenery.theme_id == null and (hazard_view.G3 != null or not hazard_view.visible) # 테마 섬이 있으면 상자 절벽 대신 · 단순 위험 표면은 반투명이라 절벽이 비침 (G3 재질은 깊이로 가림)
	items_view.update(st, dt, now)
	Prof.lap("world 아이템")
	var my_piece := {}
	var people := []
	if sky_on:
		for pc in st.get("pieces", []):
			if str(pc.get("phase", "")) == "control" and pc.get("controller") != null and Store.my_id != null and int(pc.controller) == Store.my_id:
				my_piece = pc
		for p in st.players:
			if not p.alive or p.get("master", false) or (Store.my_id != null and int(p.id) == Store.my_id):
				continue
			var s: Vector3 = bodies.shown.get(int(p.id), Vector3(p.x, p.y, p.z))
			people.append({"x": s.x, "y": s.y, "z": s.z, "color": Co.color(Bodies.player_color(p, st))})
	sky_aids.update(sky_on, my_piece, people, now)
	Prof.lap("world 하늘 도우미")
	rig.place(dt, bodies.shown, solid_at)
	Prof.lap("world 카메라")
	bodies.thin_labels(rig.cam, sky_on)
	Prof.lap("world 이름표")
	if vm != null: # 1인칭 팔·무기: 살아 있고 1인칭 (몸을 숨긴 때) 만
		var mine = bodies.nodes.get(Store.my_id, {}).get("body") if Store.my_id != null else null
		vm.update(mine, mine != null and rig.hide_me() and View.mode == "first" and not me.is_empty() and me.alive, dt)
	var gcd = me.get("ghostCd") if not me.is_empty() else null
	ghost_aim.update(rig.spectating() and gcd != null and rig.sky_blend == 0.0, rig.cam, Bodies.player_color(me, st) if not me.is_empty() else 0xffffff, gcd != null and float(gcd) == 0.0, field.x, field.y, solid_at, column_top, now)
	Prof.lap("world 1인칭 팔·유령 조준")


# 칸 (x, y) 기둥 꼭대기 높이 (render.js columnTopAt)
func column_top(x: int, y: int) -> int:
	for z in range(field.z - 1, -1, -1):
		var i := (z * field.y + y) * field.x + x
		if i < grid().size() and grid()[i] != 0:
			return z + 1
	return 0


# 대기실 어두운 무대 (render.js 의 dark): 고른 맵 테마의 어두운 엔딩 장면, 맵 바꾸면 그 테마 + 빛 번쩍, 판 시작하면 밝은 판으로
func _lobby_dark(st: Dictionary, fs: Vector3i) -> void:
	if G3 == null:
		return
	var low := bool(View.settings.get("lowGfx", false))
	var dk = LP.lobby_theme(st, View.menu_theme)
	var swap := false
	if dark != null and not dark.fits(dk, fs.x, fs.y, low):
		swap = dk != null and dk != dark.theme
		dark.dispose(self)
		dark = null
		if dk == null:
			G3.apply_theme(self, C.WORLD_MAP_THEME.get(theme_id), low) # 밝은 판 (하늘 구·안개·해 다시)
	if dk != null and dark == null and str(dk) != str(_prewarmed) and g3_has("prewarm"):
		_prewarmed = str(dk)
		G3.prewarm(self, dk) # 대기실 맵 바꿈: 그 테마 셰이더 미리
	if dk != null and dark == null:
		dark = LobbyDark.new()
		add_child(dark)
		dark.setup(self, G3, dk, fs.x, fs.y, low, swap)
	if dark != null:
		dark.step(self, G3)
