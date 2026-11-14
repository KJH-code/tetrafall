# 판 그리기 (G1, godot/PLAN.md 7절): main 이 world/world.tscn 을 붙임. 하늘·빛·안개 (맵 테마) + 격자 칸 + 떨어지는 블록·그림자
# + 위험 + 사람 몸 자리 + 하늘 시점 도우미 + 아이템 + 카메라. 서버 상태는 Store 에서 읽기만
# 다른 묶음 자리: 몸 = G2 chars/chars.gd · 셰이더 = G3 shaders/ · 효과 = G5 fx/ (fx_root 에 붙임) · 건축가 블록 = G6 world/bblocks.gd
extends Node3D
const Opts := preload("res://core/opts.gd")
const External := preload("res://chars/external.gd")

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
const Hitch := preload("res://core/hitch.gd")
const Marks := preload("res://world/marks.gd")
const LightFx := preload("res://world/light_fx.gd")
const Shots := preload("res://world/shots.gd")
const HookFx := preload("res://world/hook_fx.gd")
const BodyFx := preload("res://world/body_fx.gd")
const CamRig := preload("res://world/cam_rig.gd")
const LobbyDark := preload("res://world/lobby_dark.gd")
const Gfx := preload("res://world/gfx.gd") # 화질 (W6): 설정 화질·창 크기·GPU → lowGfx·3D 배율·MSAA
const ShadowCalc := preload("res://world/shadow_calc.gd") # W32: 그림자 거리
const PSched := preload("res://world/prewarm_sched.gd") # W41: 메뉴·대기실 미리 하기를 프레임 예산 안에서 한 조각씩
const WarmScan := preload("res://world/warm_scan.gd")
const Gate := preload("res://core/entry_gate.gd") # W42: 입장·카운트다운 큰 일을 한 프레임에 하나씩
const TexPre := preload("res://chars/tex_prefetch.gd")
const UiPrefs := preload("res://ui/ui_prefs.gd")
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
var _ext_requested := false # W30: 외부 모델 스레드 미리 읽기 요청함
var _ext_warm_done := false # W30: 외부 몸 미리 그리기 끝
var _prewarmed = null # 셰이더 미리 데운 테마 (G3.prewarm)
var _sched_setup_done := false # W41 스케줄러에 메뉴 작업을 넣었음
var _sched_prev_us := 0
const WARM_SCAN_PER_PIECE := 3
var _scan_done := {} # 미리 그린 재질 id
var _scan_queue: Array = []
var _ghost_warmed := false
var _std_warmed := false # W42 표준 재질 모양 표를 미리 그릴 줄에 넣었음
var _scan_root: Node3D = null
var _scan_wait := 0
var _pf_done := {} # 대기실에서 텍스처를 미리 요청한 캐릭터
var _jobs := {} # 캐릭터 → External.WarmJob (W41)
var dark = null # 대기실 어두운 무대 (lobby_dark.gd), 대기실 아니면 null
var _entered := false # W42: 입장 쪼개기가 끝남 (처음 한 바퀴 다 돌림) — 그 전엔 판 노드를 숨김 (반쯤 지어진 장면이 안 보이게)
var entry_frames := 0 # 확인용: 이번 입장에서 일을 미룬 프레임 수
var vm = null # G2 1인칭 팔·무기 (chars/viewmodel.gd)
var _halo_st = null # 판 빛 무리를 만든 스냅샷 (같으면 _halos 그대로)
var _halo_lit := false
var _halos: Array = []
const VIEWMODEL := "res://chars/viewmodel.gd"


func _exit_tree() -> void:
	# 끝낼 때 남은 미리 하기 작업을 놓음: 정적 스케줄러가 람다 (world·몸 데우기 잡을 붙잡음) 를 쥔 채로 엔진이 내려가면 힙이 깨져 종료 때 abort (W41 병합 검증: Linux 소프트웨어 렌더 실행이 rc=134)
	PSched.main.clear()
	WarmScan.clear_static()
	if G3 != null and G3.has_method("clear_static"):
		G3.clear_static() # W50: G3 정적 목록의 람다가 g3.gd 를 쥔 채 내려가던 것


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	var gfx := Gfx.new() # 맨 먼저: 아래·타이틀이 읽는 lowGfx 를 화질로 정함
	gfx.world = self
	add_child(gfx)
	set_msaa(bool(View.settings.get("lowGfx", false))) # 모서리 계단 없앰 (JS antialias). 확인용 --msaa 는 자동 조종이 뒤에 덮어씀
	if ResourceLoader.exists(G3_PATH):
		G3 = load(G3_PATH)
		G3.set_outline_far(float(WC.OUTLINE_FAR.taper_from), float(WC.OUTLINE_FAR.gone), float(WC.OUTLINE_FAR.min_k)) # W31: 몸 외곽선 거리 (셰이더 전역 값)
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
		gfx.sync_vm() # 화질 (W6): 팔 SubViewport 도 판과 같은 3D 배율
	if ResourceLoader.exists(BBLOCKS):
		bblocks = load(BBLOCKS).new()
		add_child(bblocks)
	if g3_has("xray_skip_body") and g3_has("toon_stencil_write"):
		# 사냥꾼의 눈: x-ray 는 사람 몸 (스텐실) 에 가린 곳엔 안 그림 — 블록·땅에 가린 곳만 (B3 스텐실)
		G3.xray_skip_body(body_fx.xray_mat)
		bodies.stencil_fn = func(m: ShaderMaterial): G3.toon_stencil_write(m, true)
	if g3_has("game_light"):
		# 판 빛 (B3 game_light.gd = game-light.js 전부: 색 보정·비네트·하늘 어둡게·빛 무리·빛 터짐) — 내 light_fx (3D 부분만) 대신
		remove_child(light_fx)
		light_fx.queue_free()
		light_fx = G3.game_light(self)
	if G3 != null:
		grid_view.set_material(grid_material(G3))
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
	var list := Opts.args()
	for i in list.size():
		if list[i].begins_with("--") and i + 1 < list.size() and not list[i + 1].begins_with("--"):
			args[list[i].substr(2)] = list[i + 1]
	rig.force = str(args.get("world-view", ""))
	marks_demo = args.has("marks-demo") or Opts.args().has("--marks-demo")
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
	bodies.cam = rig.cam # 몸 자세 LOD (W12)
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
			set_shadows(shadows_wanted())
			set_msaa(View.settings.lowGfx)
			apply_theme(str(theme_id)) # 지형 셰이더·튀어나온 조각도 낮춤으로
		elif k == "shadows": # 설정 '그림자'·'외곽선' (W12: 예전엔 듣는 쪽이 없어 체크가 아무것도 안 바꿈)
			set_shadows(shadows_wanted())
		elif k == "outline" and G3 != null:
			G3.set_outline_on(View.settings.get("outline", true) != false))
	if g3_has("set_low"):
		G3.set_low(self, bool(View.settings.get("lowGfx", false)))
	set_shadows(shadows_wanted())
	if G3 != null and G3.outline_on != (View.settings.get("outline", true) != false):
		G3.set_outline_on(View.settings.get("outline", true) != false)


# 해 그림자: 설정 '그림자' 켬이고 그래픽 낮춤 (화질 낮음) 이 아닐 때
static func shadows_wanted(settings: Dictionary = {}) -> bool:
	var s: Dictionary = settings if not settings.is_empty() else View.settings
	return not bool(s.get("lowGfx", false)) and s.get("shadows", true) != false


# 판 화면 다중 샘플: 보통 WC.MSAA_3D_PC·WC.MSAA_3D_WEB (JS antialias), 그래픽 낮춤이면 WC.MSAA_LOW (JS 는 낮춤에서 픽셀 비율 1 로 비용을 줄임 — 고도는 다중 샘플을 끔)
func set_msaa(low: bool) -> void:
	if get_viewport() != null:
		get_viewport().msaa_3d = msaa_for(low)


# 쌓인 칸 (건축·던진 칸 — 격자 칸) 재질: render.js blockMeshes = 위험 물들임 받음 (hazard.js tint), 외곽선 없음 (noOutline)
static func grid_material(g3) -> Material:
	return g3.toon_material(Color.WHITE, {"vertex_color": true, "hz_tint": true, "outline": false})


static func msaa_for(low: bool, web: bool = Opts.web()) -> Viewport.MSAA:
	return WC.msaa_3d(low, web)


# G3 에 이 함수가 있나 (B3 가 차례로 올리는 재질: 합치는 순서가 달라도 됨)
func g3_has(fn: String) -> bool:
	if G3 == null:
		return false
	for m in G3.get_script_method_list():
		if m.name == fn:
			return true
	return false


var _shadow_reach := -1.0 # 지금 적용한 그림자 거리 (World 가 판 크기로 정하면 set_field 가 덮으므로, 판 크기가 바뀌면 -1 로 되돌려 다시 정함)


func set_shadows(on: bool) -> void:
	if G3 != null:
		G3.set_shadows(self, on)
	else:
		sun.shadow_enabled = on


var _theme_stage := 0 # W45: 맵 적용이 어디까지 갔나 (0 = 쉼·처음, 1·2 = 다음 단계 차례)


# 맵 id → 테마 (WORLD_MAP_THEME·WORLD_THEMES 색만, 꾸밈은 G3). 표에 없는 맵은 예전 노을 (SKY_*·FOG_*)
func apply_theme(map_id: String) -> void:
	_theme_stage = 0
	while apply_theme_step(map_id):
		pass


# W45: 맵 적용 한 단계 (G3 있으면 세 단계: ① 지형·바닥·칸 색·소품 ② 위험 액체 ③ 테트리미노 칸 모양·재질). 옛 한 덩어리는 11~17ms (소프트웨어 렌더, 테마마다 다름).
# 돌려줌: 더 남았으면 true. 단계 사이에 맵이 또 바뀌면 처음부터. G3 없으면 한 단계
func apply_theme_step(map_id: String) -> bool:
	if _theme_stage > 0 and map_id != theme_id:
		_theme_stage = 0
	if G3 != null and _theme_stage > 0:
		return _apply_theme_late(map_id)
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
		_theme_stage = 1
		return true
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
	return false


# 맵 적용 둘째·셋째 단계 (apply_theme_step)
func _apply_theme_late(map_id: String) -> bool:
	var tid = C.WORLD_MAP_THEME.get(map_id)
	var low := bool(View.settings.get("lowGfx", false))
	if _theme_stage == 1:
		if g3_has("hazard_material"):
			hazard_view.set_g3(G3, tid, low) # 위험 액체 (B3): 필드 판 + 지평선 바다, 물들임
		_theme_stage = 2
		return true
	_theme_stage = 0
	if g3_has("piece_mesh"):
		# 테트리미노 칸 (B3 PieceLook): 떨어지는 칸·쌓인 칸 모양·재질·조각 색, 빛 테두리 = GAME_LIGHT 안 rim (그래픽 낮춤이면 0)
		light_fx.low = low
		var rim: float = light_fx.rim
		var pm: Mesh = G3.piece_mesh(tid, low)
		var cols: Dictionary = G3.piece_colors(tid)
		hook_fx.g3 = G3 # W35 갈고리 덩어리가 맵 테마 칸 모습·돌·모래 재질을 씀
		hook_fx.theme_id = tid
		hook_fx.low = low
		pieces_view.set_look(pm, [G3.piece_material(tid, low, {"rim": rim}), G3.piece_material(tid, low, {"rim": rim, "transparent": true, "opacity": 1.0})], cols, G3.piece_mesh(tid, true))
		grid_view.set_piece_look(pm, G3.piece_material(tid, low, {"rim": rim, "outline": false}), cols, G3.piece_mesh(tid, true)) # 쌓인 칸은 외곽선 없음 (render.js landed noOutline)
	return false


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


func _no_sched() -> bool:
	return Opts.args().has("--no-prewarm-sched")


func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion or e is InputEventKey or e is InputEventMouseButton:
		PSched.main.note_input(Time.get_ticks_usec() / 1000.0)


# 예전 방식 (--no-prewarm-sched): 메뉴 1.5초 뒤 G3.prewarm 한 번, 그 뒤 외부 몸 데우기를 프레임마다 한 캐릭터
func _old_prewarm(live: bool) -> void:
	if not live and _prewarmed == null and g3_has("prewarm"):
		var tn := Time.get_ticks_msec() * 1.0
		if _menu_since < 0:
			_menu_since = tn
		elif tn - _menu_since > float(C.LOBBY_DARK.prewarmMs):
			_prewarmed = str(View.menu_theme)
			G3.prewarm(self, View.menu_theme)
	elif live:
		_menu_since = -1.0
	if not live and _prewarmed != null and not _ext_warm_done and Opts.args().has("--no-ext-warm") == false:
		if not _ext_requested:
			_ext_requested = true
			External.request_all()
		_ext_warm_done = External.warm_step(self, func(id, col): return bodies.chars_script.make_body(id, col)) if bodies != null and bodies.chars_script != null else true


# W41: 스케줄러 한 프레임. 판 중 (countdown·playing·over) 에는 쉼 (hold), 메뉴·대기실에서만 조각을 돌림
func _sched_tick(live: bool, st: Dictionary) -> void:
	var now_us := Time.get_ticks_usec()
	var prev_ms := (now_us - _sched_prev_us) / 1000.0 if _sched_prev_us > 0 else 0.0
	_sched_prev_us = now_us
	if not _sched_setup_done:
		_sched_setup_done = true
		_sched_setup()
	var ph := str(st.get("phase", "")) if live else ""
	if live and ph == "lobby" and not Opts.args().has("--no-tex-prefetch"):
		_lobby_prefetch(st)
	if live and ph == "lobby" and not PSched.main.has("warm.skin") and not _skin_started and not Opts.args().has("--no-skin-warm") and not _no_sched():
		_skin_started = true # W42 항목 5: 몸 종류마다 스킨 갈래 (반투명 유령화·무적, 잔상) 셰이더를 숨은 채 한 번 그림
		PSched.main.add("warm.skin", 3, _warm_skin_step, 3.0, "lobby", 500.0)
	var in_game := ph == "countdown" or ph == "playing" or ph == "over"
	if in_game:
		_pf_done.clear() # 판이 끝나 대기실로 돌아오면 다시 미리 읽음
	PSched.main.step(now_us / 1000.0, prev_ms, in_game)
	if in_game and TexPre.pending() > 0 and ph == "playing":
		TexPre.drain() # 판이 자리 잡으면 안 받은 텍스처 요청을 놓음 (영상 메모리)


# W41: 재질 미리 그리기 (world/warm_scan.gd) 한 조각 = 재질 몇 개를 카메라 앞에 작게 그림 → 두 프레임 뒤 치움. 한 번 한 재질은 다시 안 함 (맵을 바꿔 새 재질이 생기면 다음 scan 이 찾음)
func _warm_scan_step() -> bool:
	if _scan_root != null:
		_scan_wait -= 1
		if _scan_wait <= 0:
			_scan_root.queue_free()
			_scan_root = null
		return false
	if not is_visible_in_tree():
		return PSched.WAIT
	if _scan_queue.is_empty():
		_scan_queue = WarmScan.collect(self, _scan_done)
		if not _std_warmed: # W42: 이벤트 때 코드가 새로 만드는 표준 재질 모양들 (warm_scan.gd STD_KEYS)
			_std_warmed = true
			_scan_queue = WarmScan.std_entries() + _scan_queue # 작고 확실한 것부터
		if not _ghost_warmed and G3 != null:
			_ghost_warmed = true # 유령화·무적 몸 (반투명 + 깊이 선 묶음) 은 처음 켤 때 컴파일됨 — 같은 재질을 한 번 그림 (스킨 갈래는 몸 데우기가 맡음)
			_scan_queue.append([preload("res://chars/ghost_depth.gd").with_prepass(G3.toon_material(Color.WHITE, {"opacity": 0.5})), false])
			_scan_queue.append([preload("res://chars/ghost_depth.gd").with_prepass(WarmScan.std_material([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0])), false]) # 코드 몸 (조각 메시) 의 유령화·무적 — 표준 반투명을 깊이 선으로 감쌈
		if _scan_queue.is_empty():
			return true
	var take: Array = _scan_queue.slice(0, WARM_SCAN_PER_PIECE)
	_scan_queue = _scan_queue.slice(WARM_SCAN_PER_PIECE)
	_scan_root = WarmScan.spawn(self, take, get_viewport().get_camera_3d())
	_scan_wait = 1 # 붙인 프레임에 그려지고 다음 부름에 치움 (W42: 2 → 1, 재질이 140개 넘게 늘어서)
	Hitch.tag("미리 그리기", "재질 %d개 (남은 %d)" % [take.size(), _scan_queue.size()])
	return false


# W42 항목 5: 스킨 몸 (뼈로 움직이는 메시) 의 반투명 갈래 — 유령화·무적 (깊이 선 + 반투명 툰), 잔상·낙사 잔상 (표준 반투명) — 은 그 재질이 스킨 메시를 처음 그릴 때 컴파일됨.
# 앞의 재질 미리 그리기 (warm_scan) 는 상자 메시로만 그려 스킨 갈래를 못 덮음. 대기실에 있는 몸 종류마다 몸을 복제해 (body.snapshot) 그 재질들을 입혀 카메라 앞에 아주 작게 두 프레임 그림
var _skin_started := false
var _skin_done := {} # 몸 종류 → true
var _skin_queue: Array = [] # [몸, 종류, 재질 번호]
var _skin_root: Node3D = null
var _skin_wait := 0


func _skin_mat(i: int) -> Material:
	if i == 0:
		return preload("res://chars/ghost_depth.gd").with_prepass(G3.toon_material(Color.WHITE, {"opacity": 0.5})) if G3 != null else null
	return WarmScan.std_material(WarmScan.SKIN_KEYS[i - 1])


func _warm_skin_step() -> Variant:
	if _skin_root != null:
		_skin_wait -= 1
		if _skin_wait <= 0:
			_skin_root.queue_free()
			_skin_root = null
		return false
	if not is_visible_in_tree() or bodies == null or G3 == null:
		return PSched.WAIT
	if _skin_queue.is_empty():
		for id in bodies.nodes:
			var b = bodies.nodes[id].get("body")
			if b == null or not is_instance_valid(b) or not b.has_method("snapshot") or not b.is_inside_tree():
				continue
			var key := BodyFx.skin_key(b)
			if _skin_done.has(key):
				continue
			_skin_done[key] = true
			for i in WarmScan.SKIN_KEYS.size() + 1:
				_skin_queue.append([b, key, i])
		if _skin_queue.is_empty():
			return PSched.WAIT
	var job: Array = _skin_queue.pop_front()
	var body = job[0]
	if not is_instance_valid(body) or not body.is_inside_tree():
		return false
	var t0 := Hitch.t()
	_skin_root = Node3D.new()
	_skin_root.name = "WarmSkin"
	add_child(_skin_root)
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.is_inside_tree():
		_skin_root.global_transform = cam.global_transform.translated_local(Vector3(0, 0, -2.0))
	var g: Node3D = body.snapshot(_skin_mat(int(job[2])))
	g.scale = Vector3.ONE * 0.002
	_skin_root.add_child(g)
	_skin_wait = 2
	Hitch.span("미리 그리기", "skin %s %d" % [job[1], job[2]], t0)
	return false


# W41: 대기실에 있는 사람들의 캐릭터 (+ 나) 의 판 몸·큰 캐릭터·초상 텍스처를 미리 스레드로 요청 — 판 시작 때 몸·초상을 만들며 동기로 읽던 것 (몸당 10~50ms)
func _lobby_prefetch(st: Dictionary) -> void:
	var want := {}
	for p in st.get("players", []):
		if p.get("spectator", false) or p.get("dummy", false) or p.get("char") == null:
			continue
		want[str(p.char)] = true
	var rank := 0
	for id in want:
		if _pf_done.has(id) or not C.FIGURE_CHARS.has(id):
			continue
		_pf_done[id] = true
		if not PSched.main.has("warm.scan.lobby"):
			PSched.main.add("warm.scan.lobby", 4, _warm_scan_step, 3.0, "lobby", 300.0) # 맵·인원에 따라 새로 생긴 재질
		var job = External.WarmJob.new(str(id), true, true, false)
		PSched.main.add("lobby.prefetch." + str(id), 0 + rank, func(): return job.step(self, Callable()), 4.0, "lobby")
		rank += 1


# 메뉴 작업 목록 (우선순위 작을수록 먼저): 셰이더 데우기 → 내 캐릭터 → 판 빛 LUT → 나머지 캐릭터 몸. 시작 1.5초 뒤부터 (타이틀 첫 장면이 자리 잡은 뒤)
func _sched_setup() -> void:
	var S = PSched.main
	var after := float(C.LOBBY_DARK.prewarmMs)
	if g3_has("prewarm"):
		var pi := [0]
		S.add("g3.prewarm", 1, func():
			if not is_visible_in_tree():
				return PSched.WAIT # 타이틀·메뉴 동안 world 는 숨김 (title.gd) — 숨은 채로 그리면 셰이더가 안 만들어짐: 대기실에서 (조각으로 나눠)
			G3.prewarm(self, View.menu_theme, 3, pi[0])
			pi[0] += 1
			if pi[0] >= G3.prewarm_parts():
				_prewarmed = str(View.menu_theme)
				return true
			return false, 3.0, "menu", after)
	S.add("warm.scan", 3, _warm_scan_step, 3.0, "menu", after + 300.0)
	if G3 != null and ResourceLoader.exists(LobbyDark.STAGE): # W42: 대기실 무대 스크립트 컴파일 (~22ms) 을 메뉴에서 미리 — 타이틀을 거치면 이미 있음. 정적 함수라 world 를 안 붙잡음 (종료 때 스케줄러 람다가 죽은 노드를 쥐는 abort 방지)
		S.add("stage.script", 5, LobbyDark.preload_stage, 22.0, "menu", after + 400.0)
	if light_fx != null and light_fx.has_method("warm_lut_step"):
		S.add("light.lut", 6, func(): return light_fx.warm_lut_step(), 0.7, "menu", after)
		S.add("hazard.vignette", 7, func(): return PSched.WAIT if not is_visible_in_tree() else hazard_view.warm_canvas_step(), 0.2, "menu", after)
		S.add("light.vignette", 7, func(): return PSched.WAIT if not is_visible_in_tree() else light_fx.warm_canvas_step(), 0.2, "menu", after)
	if Opts.args().has("--no-ext-warm") or bodies == null or bodies.get("chars_script") == null:
		return
	var mine := str(UiPrefs.get_value("char", ""))
	var order: Array = C.FIGURE_CHARS.duplicate()
	if mine != "" and order.has(mine):
		order.erase(mine)
		order.push_front(mine)
	var rank := 0
	for id in order:
		var job = External.WarmJob.new(str(id))
		_jobs[id] = job
		S.add("ext.warm." + str(id), 2 + rank, func(): return job.step(self, func(i, col): return bodies.chars_script.make_body(i, col)), 4.0, "menu", after + 200.0 * rank)
		rank += 1


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
		n.visible = live and (_entered or not Gate.on()) and ((n != hazard_view and n != ghost_aim) or n.visible) and (n != scenery or dark == null) # 어두운 무대면 떠 있는 섬·먼 배경 숨김
	if not live and vm != null:
		vm.update(null, false, dt) # 방 밖: 1인칭 팔 끔
	# 첫 진입 멈춤 줄이기 (render.js prewarmLobby): 메뉴·대기실에서 미리 하기 — W41 부터 프레임 예산 스케줄러 (world/prewarm_sched.gd) 가 조각으로 나눠 돌림.
	# 끄고 예전 방식 (한 프레임에 몰아서) 으로 되돌리기: --no-prewarm-sched
	if _no_sched():
		_old_prewarm(live)
	else:
		_sched_tick(live, st)
	if not live:
		_entered = false
		entry_frames = 0
		Gate.entered = true
		hazard_view.clear() # 판 중에 나가면 위험 경고·전역 위험 빛·물들임이 메뉴에 남던 것 (update 가 더 안 불림)
	if headless or not live:
		return
	dt *= View.time_scale # KO 슬로모션 (G5 가 정함)
	Prof.begin()
	var now: float = Net.now_ms() # (= 고도 시작부터 ms, 재연이면 가상 시계 — core/replay.gd)
	var f: Dictionary = st.field
	var fs := Vector3i(int(f.w), int(f.d), int(f.get("h", C.GRID_H)))
	# 대기실: 고른 맵의 시작 지형을 지금 인원 판 크기로 미리 깖 (render.js lobbyPreview), 테마도 그 맵
	var pk = LP.pick(st, View.menu_theme)
	var mid := str(pk) if pk != null else str(st.get("map", {}).get("id", ""))
	if mid != theme_id or _theme_stage > 0:
		if not Gate.ok("world.theme"):
			_entry_wait()
			return
		var tg := Gate.t()
		var more_t := false
		if Gate.on() and not Gate.no_split("theme"): # W45: 맵 적용을 세 단계로 (단계마다 한 프레임)
			more_t = apply_theme_step(mid)
		else:
			apply_theme(mid)
		Gate.done("world.theme", tg)
		Prof.lap("world 섬·대기실 ·맵 바꿈")
		if more_t:
			_entry_wait()
			return
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
	Prof.lap("world 섬·대기실 ·미리보기 지형")
	if fs != field:
		field = fs
		grid_view.set_field(fs.x, fs.y)
		if G3 != null:
			G3.set_field(self, fs.x, fs.y)
			_shadow_reach = -1.0
		built_version = -2
	Prof.lap("world 섬·대기실 ·판 크기 변경")
	if _lobby_dark(st, fs):
		_entry_wait()
		return
	Prof.lap("world 섬·대기실 ·어두운 무대")
	var sc_low := bool(View.settings.get("lowGfx", false))
	var sc_id = C.WORLD_MAP_THEME.get(theme_id)
	if scenery.stale(sc_id, fs.x, fs.y, sc_low) or scenery.building():
		if not Gate.ok("world.scenery"):
			_entry_wait()
			return
		var ts := Gate.t()
		if Gate.on() and not Gate.no_split("scene"): # W45: 지형 (섬·먼 배경) 을 네 단계로 — 단계마다 한 프레임 (옛 17~23ms 한 덩어리)
			var began := true
			if scenery.stale(sc_id, fs.x, fs.y, sc_low) or not scenery.building(): # 짓는 중에 맵이 또 바뀌면 처음부터
				began = scenery.build_begin(sc_id, fs.x, fs.y, sc_low, fs.z)
			var more: bool = began and scenery.build_step()
			Gate.done("world.scenery", ts)
			if more:
				_entry_wait()
				return
		else:
			scenery.build(sc_id, fs.x, fs.y, sc_low, fs.z)
			Gate.done("world.scenery", ts)
	else:
		scenery.build(sc_id, fs.x, fs.y, sc_low, fs.z) # 바꿀 게 없으면 바로 돌아옴 (테마 없음 → 비움도 여기)
	Prof.lap("world 섬·대기실 ·지형 만들기")
	scenery.step(dt)
	Prof.lap("world 섬·대기실")
	if bblocks != null:
		bblocks.update(st)
		grid_view.skip = bblocks.skip()
	var gkey = preview.key if preview != null else Store.grid_version
	var g := grid()
	var grid_ran := false
	if str(gkey) != str(built_version) and g.size() == fs.x * fs.y * fs.z:
		if not Gate.ok("world.grid"):
			_entry_wait()
			return
		var tgr := Gate.t()
		grid_view.rebuild(g, fs.x, fs.y, fs.z)
		built_version = gkey
		if sprouts != null:
			G3.sprout_update(sprouts, g, fs.x, fs.y, fs.z, grid_view.skip, bool(View.settings.get("lowGfx", false)))
		Gate.done("world.grid", tgr)
		grid_ran = true
	Prof.lap("world 격자·건축 블록")
	if grid_ran and not _entered and Gate.on() and not Gate.no_split("tail"):
		# W51: 입장 첫 바퀴의 끝 프레임에 칸 깔기 (격자·튀어나온 조각·칸 값 ~8ms) 와 몸 자세·몸 효과·위험·1인칭 팔 첫 갱신 (~19ms) 이 한꺼번에 몰리던 것 — 칸 깔기만 하고 다음 프레임으로 (끄기 --no-tail-split)
		_entry_wait()
		return
	if not _entered and Hitch.on: # W45: 입장 첫 바퀴가 몇 프레임 걸렸나 (미룬 프레임 수) — 입장 쪼개기 전후 비교
		Hitch.tag("입장 첫 바퀴 끝", "대기 %d프레임" % entry_frames)
	_entered = true # 입장 한 바퀴 끝 (지형·무대·칸까지 다 지음)
	Gate.entered = true
	rig.pre(dt)
	grid_view.regroup() # W39: 쌓인 칸 먼/가까움 (카메라가 움직였을 때만)
	var sky_on: bool = rig.sky_blend > 0.5
	bodies.update(st, Store.my_id, rig.hide_me(), sky_on, now)
	Prof.lap("world bodies.update (몸 자세)")
	rig.field_size = Vector2(fs.x, fs.y)
	if G3 != null and WC.shadow_opt and rig.cam.is_inside_tree(): # W32: 그림자 거리를 카메라 자리에 맞춤 (판 크기 값 이하)
		var cg: Vector3 = rig.cam.global_position
		var full: float = G3.shadow_full(fs.x, fs.y)
		var rch: float = ShadowCalc.reach_next(_shadow_reach, Vector3(cg.x, -cg.z, cg.y), fs.x, fs.y, full)
		if not is_equal_approx(rch, _shadow_reach):
			_shadow_reach = rch
			G3.set_shadow_reach(self, rch)
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
	var lit := ph == "countdown" or ph == "playing" or ph == "over"
	# 빛 무리 목록은 스냅샷 (떨어지는 칸·아이템 자리 = 스냅샷 값 그대로) 이 바뀔 때만 다시 (W15: 120fps 면 같은 목록을 4번씩 만들던 것)
	if not (is_same(st, _halo_st) and lit == _halo_lit):
		_halo_st = st
		_halo_lit = lit
		_halos = halos_of(st, pieces_view.piece_colors) if lit else []
	var halos: Array = _halos
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


# 입장 쪼개기: 이번 프레임에 이 큰 일 차례가 아님 → 나머지는 다음 프레임에 (그동안 판 노드는 숨은 채 / 맵 바꿈이면 옛 장면이 잠깐 그대로)
func _entry_wait() -> void:
	entry_frames += 1
	Gate.entered = false # W45: 입장 첫 바퀴가 아직 — 초상·큰 캐릭터는 기다림
	if Hitch.on:
		Hitch.tag("entry split", "deferred frame %d" % entry_frames)
	Prof.lap("world entry split (deferred)")


# 판 빛 무리: 떨어지는 블록 칸·아이템마다 [x, y, z, 색, 크기 배수] (game-light.js)
static func halos_of(st: Dictionary, piece_colors: Dictionary) -> Array:
	var halos := []
	for pc in st.get("pieces", []):
		if pc.get("thrown", false):
			continue
		var col: int = 0xffffff if str(pc.get("shape", "")) == "ghost" else (WC.CONTROLLED_COLOR if pc.get("controller") != null else int(piece_colors.get(str(pc.get("shape", "")), 0xffffff)))
		for c in pc.cells:
			halos.append([c[0] + 0.5, c[1] + 0.5, c[2] + 0.5, col, 0.7 if pc.get("sky", false) else 1.0])
	for it in st.get("items", []):
		halos.append([it.x + 0.5, it.y + 0.5, it.z + 0.5, int(C.GAME_LIGHT_ITEM), 0.6])
	return halos


# 칸 (x, y) 기둥 꼭대기 높이 (render.js columnTopAt)
func column_top(x: int, y: int) -> int:
	for z in range(field.z - 1, -1, -1):
		var i := (z * field.y + y) * field.x + x
		if i < grid().size() and grid()[i] != 0:
			return z + 1
	return 0


# 대기실 어두운 무대 (render.js 의 dark): 고른 맵 테마의 어두운 엔딩 장면, 맵 바꾸면 그 테마 + 빛 번쩍, 판 시작하면 밝은 판으로
func _lobby_dark(st: Dictionary, fs: Vector3i) -> bool: # 참 = 이번 프레임엔 큰 일 차례가 아님 (미룸)
	if G3 == null:
		return false
	var low := bool(View.settings.get("lowGfx", false))
	var dk = LP.lobby_theme(st, View.menu_theme)
	var swap := false
	var needs: bool = (dark != null and not dark.fits(dk, fs.x, fs.y, low)) or (dark == null and dk != null)
	if needs and not Gate.ok("world.dark"):
		return true
	if needs and dark == null and ResourceLoader.exists(LobbyDark.STAGE) and not ResourceLoader.has_cached(LobbyDark.STAGE):
		# 무대 스크립트 (title_world.gd 큰 파일) 컴파일 ~22ms — 타이틀을 안 거친 입장 (?room= 링크) 은 여기서 처음. 따로 한 칸 (메뉴 미리 하기가 이미 했으면 건너뜀)
		if not Gate.ok("world.dark.load"):
			return true
		var tl := Gate.t()
		load(LobbyDark.STAGE)
		Gate.done("world.dark.load", tl)
	var tg := Gate.t()
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
		dark.setup(self, G3, dk, fs.x, fs.y, low, swap, Gate.on())
	if needs:
		Gate.done("world.dark", tg)
	if dark != null and not dark.ready(): # 소품·빛 가루는 프레임마다 한 조각씩 (큰 일 한 칸)
		if Gate.ok("world.dark.part"):
			var tp := Gate.t()
			dark.stage_step()
			Gate.done("world.dark.part", tp)
		if not dark.ready() and not _entered:
			return true # 입장 첫 바퀴: 무대가 다 지어질 때까지 (아직 숨은 채) 기다림
	if dark != null:
		dark.step(self, G3)
	return false
