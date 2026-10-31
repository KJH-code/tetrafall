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
const CamRig := preload("res://world/cam_rig.gd")
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
var rig: Node3D
var bblocks = null # G6 건축가 블록 (있으면 update(state)·skip() 을 부름)
var fx_root := Node3D.new() # G5 효과 노드가 붙을 자리
var theme_id = null
var theme := {}
var field := Vector3i.ZERO # 지금 판 크기 (w, d, h)
var built_version := -2
var headless := false
var G3 = null


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
	sky_aids = SkyAids.new()
	items_view = ItemsView.new()
	rig = CamRig.new()
	for n in [grid_view, pieces_view, hazard_view, bodies, sky_aids, items_view, rig, fx_root]:
		add_child(n)
	fx_root.name = "Fx"
	if ResourceLoader.exists(FX):
		var fx = load(FX).new()
		fx_root.add_child(fx)
		fx.setup(rig)
	if ResourceLoader.exists(BBLOCKS):
		bblocks = load(BBLOCKS).new()
		add_child(bblocks)
	if G3 != null:
		grid_view.set_material(G3.toon_material(Color.WHITE, {"vertex_color": true}))
		grid_view.make_mat = func(c: Color): return G3.toon_material(c)
		bodies.make_mat = grid_view.make_mat
		pieces_view.mats = [G3.toon_material(Color.WHITE, {"vertex_color": true}), G3.toon_material(Color.WHITE, {"vertex_color": true, "opacity": WC.PIECE_SKY_ALPHA})]
	apply_theme("")
	# 확인용 명령줄 (-- 뒤): --world-view over|third|first · --map <맵 id> · --mode <모드> (방장이면 대기실에서 바꿈)
	var args := {}
	var list := OS.get_cmdline_user_args()
	for i in list.size():
		if list[i].begins_with("--") and i + 1 < list.size() and not list[i + 1].begins_with("--"):
			args[list[i].substr(2)] = list[i + 1]
	rig.force = str(args.get("world-view", ""))
	Store.joined.connect(func(_room, _re):
		if args.has("map"):
			Store.send_room({"type": "setMap", "map": args.map})
		if args.has("mode"):
			Store.send_room({"type": "setMode", "mode": args.mode}))
	Store.game_event.connect(bodies.on_event)
	View.changed.connect(func(k): if k == "lowGfx": set_shadows(not View.settings.lowGfx))
	set_shadows(not View.settings.get("lowGfx", false))


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
		G3.apply_theme(self, C.WORLD_MAP_THEME.get(map_id), bool(View.settings.get("lowGfx", false)))
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
	return i < Store.grid.size() and Store.grid[i] != 0


func _process(dt: float) -> void:
	var st := Store.state
	if headless or st.is_empty() or not st.has("field"):
		return
	var now := Time.get_ticks_msec() * 1.0
	var mid := str(st.get("map", {}).get("id", ""))
	if mid != theme_id:
		apply_theme(mid)
	var f: Dictionary = st.field
	var fs := Vector3i(int(f.w), int(f.d), int(f.get("h", C.GRID_H)))
	if fs != field:
		field = fs
		grid_view.set_field(fs.x, fs.y)
		if G3 != null:
			G3.set_field(self, fs.x, fs.y)
		built_version = -2
	if bblocks != null:
		bblocks.update(st)
		grid_view.skip = bblocks.skip()
	if Store.grid_version != built_version and Store.grid.size() == fs.x * fs.y * fs.z:
		grid_view.rebuild(Store.grid, fs.x, fs.y, fs.z)
		built_version = Store.grid_version
	rig.pre(dt)
	var sky_on: bool = rig.sky_blend > 0.5
	bodies.update(st, Store.my_id, rig.hide_me(), sky_on, now)
	var me := Store.me()
	pieces_view.update(st, Store.my_id, me, rig.sky_blend)
	hazard_view.update(st, Store.grid, Store.grid_version, me)
	items_view.update(st, dt, now)
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
	rig.place(dt, bodies.shown, solid_at)
	bodies.thin_labels(rig.cam, sky_on)
