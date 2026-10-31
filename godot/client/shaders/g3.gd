# G3 툰·외곽선·테마 (godot/PLAN.md 7절: shaders/ 는 G3, G1·G2 는 preload 해서 부름).
#   const G3 := preload("res://shaders/g3.gd")
#   mesh.material_override = G3.toon_material(Color(...))          # 툰 + 외곽선 (next_pass)
#   G3.set_hemi(...) / G3.add_sun(...)                             # 빛 (테마는 apply_theme 이 부름)
# JS 원본: client/toon.js (툰), render.js OutlineEffect (외곽선), 빛 세기는 three 값 그대로 받아 고도 값으로 바꿈 (/PI, toon.gdshader 주석)
extends RefCounted

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const K := preload("res://shaders/g3_config.gd")
const TOON := preload("res://shaders/toon.gdshader")
const TOON_ALPHA := preload("res://shaders/toon_alpha.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")
const SKY := preload("res://shaders/sky.gdshader")
const TERRAIN := preload("res://shaders/terrain.gdshader")
const BS := preload("res://shaders/block_style.gd")
const SPROUTS := preload("res://shaders/sprouts.gd")
const BATCH := preload("res://shaders/batch.gd")
const FLAT := preload("res://shaders/flat.gdshader")
const FLOOR := preload("res://shaders/floor.gdshader")

static var _globals := {} # 넣은 전역 셰이더 값 (RenderingServer 는 실행 중 읽기가 안 됨 — 테스트·확인용)


# 툰 재질 (three toon({...})). color: Color 또는 0xRRGGBB. opts: map (Texture2D), emissive (Color/숫자), emissive_energy,
# opacity (1 미만이면 투명), vertex_color (bool), outline (기본 true — 외곽선을 next_pass 로), no_fog (안개 안 받음), color_glow
static func toon_material(color = Color.WHITE, opts := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var c := _col(color)
	var a: float = opts.get("opacity", 1.0)
	m.shader = TOON if a >= 1.0 else TOON_ALPHA
	m.set_shader_parameter("albedo", Color(c.r, c.g, c.b, a))
	m.set_shader_parameter("toon_steps", K.TOON_STEPS)
	if opts.has("map"):
		m.set_shader_parameter("albedo_tex", opts.map)
		m.set_shader_parameter("use_tex", true)
	if opts.has("emissive"):
		m.set_shader_parameter("emissive", _col(opts.emissive))
	m.set_shader_parameter("emissive_energy", opts.get("emissive_energy", 1.0))
	m.set_shader_parameter("use_vertex_color", opts.get("vertex_color", false))
	m.set_shader_parameter("color_glow", opts.get("color_glow", 0.0))
	m.set_shader_parameter("no_fog", opts.get("no_fog", false)) # JS fog: false
	if a < 1.0:
		m.render_priority = 1
	if opts.get("outline", true) and a >= 1.0:
		m.next_pass = outline_material()
		m.next_pass.set_shader_parameter("no_fog", opts.get("no_fog", false))
	return m


# 외곽선만 (three OutlineEffect 의 뒤집은 껍데기). 다른 셰이더 재질 next_pass 로 붙여도 됨
static func outline_material(thickness: float = C.OUTLINE_THICKNESS) -> ShaderMaterial:
	var o := ShaderMaterial.new()
	o.shader = OUTLINE
	o.set_shader_parameter("thickness", thickness)
	o.set_shader_parameter("line_color", K.OUTLINE_COLOR)
	return o


# 외곽선 끄기 (JS noOutline: 하늘·용암·그림자 판·파편 등)
static func no_outline(m: Material) -> Material:
	m.next_pass = null
	return m


# 외곽선 켜기·끄기 (설정 '외곽선'): 재질들에 한 번에
static func set_outline(mats: Array, on: bool) -> void:
	for m in mats:
		if m is ShaderMaterial and (m.shader == TOON or m.shader == TOON_ALPHA):
			m.next_pass = outline_material() if on else null


# 하늘빛 (three HemisphereLight(sky, ground, intensity)) — 툰 셰이더 전역 값
static func set_hemi(sky, ground, intensity: float) -> void:
	var s := _col(sky).srgb_to_linear()
	var g := _col(ground).srgb_to_linear()
	_set_global("g3_hemi_sky", Vector3(s.r, s.g, s.b))
	_set_global("g3_hemi_ground", Vector3(g.r, g.g, g.b))
	_set_global("g3_hemi_energy", intensity)


# 해 (three DirectionalLight(color, intensity), 게임 좌표 방향 dir = 해가 있는 쪽). 색·세기는 툰 셰이더 전역 값 g3_sun (선형),
# 고도 빛은 방향·그림자만 (세기 1 — 툰 셰이더는 LIGHT_COLOR 를 안 씀, 색 공간 주석 toon_common.gdshaderinc)
static func set_sun(sun: DirectionalLight3D, color, intensity: float, dir: Array) -> void:
	var c := _col(color).srgb_to_linear()
	_set_global("g3_sun", Vector3(c.r, c.g, c.b) * intensity)
	_set_global("g3_sun_on", 1.0 if intensity > 0.0 and sun.visible else 0.0)
	sun.light_color = Color.WHITE
	sun.light_energy = 1.0
	var d := Co.gxyz(float(dir[0]), float(dir[1]), float(dir[2])).normalized()
	sun.look_at_from_position(Vector3.ZERO, -d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)
	sun.shadow_bias = K.SUN_SHADOW_BIAS
	sun.shadow_normal_bias = K.SUN_SHADOW_NORMAL_BIAS


# ===== 테마: 하늘·안개·해·하늘빛 (JS world.js apply + render.js 생성자의 노을) =====
# world (G1 의 World Node3D) 아래 'G3Env' 하나에 WorldEnvironment·해 DirectionalLight3D·하늘 구를 만들어 둠 (있으면 값만 바꿈).
# theme_id: config WORLD_MAP_THEME[map.id] (없으면 null = 예전 노을). low: 그래픽 낮춤 (지금은 같음)
static func apply_theme(world: Node3D, theme_id, low := false) -> void:
	var env := _env_node(world)
	var L = C.WORLD_THEMES.get(theme_id) if theme_id != null else null
	var sky := {}
	var sun_dir: Array = C.SUN_DIR
	var sun_col = C.SUN_COLOR
	var sun_int: float = K.SUNSET_SUN
	var hemi: Array = K.SUNSET_HEMI
	var fog: Array = [C.SKY_HORIZON, C.FOG_NEAR, C.FOG_FAR]
	if L == null:
		# 예전 노을 (render.js skyDome 기본값)
		sky = {"top": _lin3(C.SKY_TOP), "mid": _lin3(C.SKY_MID), "horizon": _lin3(C.SKY_HORIZON), "below": _lin3(C.SKY_HORIZON) * 0.55,
			"glow": K.SKY_GLOW, "disc": K.SKY_DISC, "disc_size": K.SKY_DISC_SIZE, "stars": 0.0, "bg": C.SKY_HORIZON}
	else:
		var S: Dictionary = L.sky
		sky = {"top": _lin3(S.top), "mid": _lin3(S.mid), "horizon": _lin3(S.horizon), "below": _lin3(S.below),
			"glow": _lin3(S.glow) if S.has("glow") else K.SKY_GLOW, "disc": _lin3(S.disc) if S.has("disc") else K.SKY_DISC,
			"disc_size": float(S.get("discSize", K.SKY_DISC_SIZE)), "stars": float(S.get("stars", 0.0)), "bg": S.horizon}
		sun_dir = L.sunDir
		sun_col = L.sunColor
		sun_int = L.sunIntensity
		hemi = L.hemi
		fog = L.fog
	var dome: MeshInstance3D = env.get_node("Sky")
	var m: ShaderMaterial = dome.material_override
	for k in ["top", "mid", "horizon", "below", "glow", "disc", "disc_size", "stars"]:
		m.set_shader_parameter(k, sky[k])
	var sd := Vector3(float(sun_dir[0]), float(sun_dir[1]), float(sun_dir[2])).normalized()
	m.set_shader_parameter("sun_dir", sd)
	var we: WorldEnvironment = env.get_node("Env")
	we.environment.background_color = _col(sky.bg)
	set_hemi(hemi[0], hemi[1], float(hemi[2]))
	set_sun(env.get_node("Sun"), sun_col, sun_int, sun_dir)
	set_fog(fog[0], float(fog[1]), float(fog[2]))
	env.set_meta("theme", theme_id)


# 안개 (three Fog(color, near, far)) — 툰·외곽선 셰이더 전역 값. far <= 0 이면 끔
static func set_fog(color, near: float, far: float) -> void:
	_set_global("g3_fog_color", _lin3(color))
	_set_global("g3_fog_near", near)
	_set_global("g3_fog_far", far)


# 판 크기가 바뀌면 (G1): 하늘 구 가운데·그림자 거리 (JS render.js setField: 하늘 구는 판 가운데, 그림자 상자는 판 대각선 + 여백)
static func set_field(world: Node3D, w: float, d: float) -> void:
	var env := _env_node(world)
	env.get_node("Sky").position = Co.gxyz(w / 2.0, d / 2.0, 0.0)
	var sun: DirectionalLight3D = env.get_node("Sun")
	sun.directional_shadow_max_distance = sqrt(w * w + d * d) / 2.0 + K.SHADOW_REACH_PAD * 4.0


# 그림자 켜기·끄기 (JS 대기 화면 설정 '그림자', render.js setShadows)
static func set_shadows(world: Node3D, on: bool) -> void:
	(_env_node(world).get_node("Sun") as DirectionalLight3D).shadow_enabled = on


static func _env_node(world: Node3D) -> Node3D:
	var env: Node3D = world.get_node_or_null("G3Env")
	if env:
		return env
	env = Node3D.new()
	env.name = "G3Env"
	world.add_child(env)
	var we := WorldEnvironment.new()
	we.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.BLACK # 하늘빛은 툰 셰이더 (g3_hemi_*)
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.fog_enabled = false # 안개는 툰 셰이더 (three 와 같은 smoothstep)
	we.environment = e
	env.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = K.SHADOW_MAX_DISTANCE
	env.add_child(sun)
	var dome := MeshInstance3D.new()
	dome.name = "Sky"
	var sm := SphereMesh.new()
	sm.radius = K.SKY_RADIUS
	sm.height = K.SKY_RADIUS * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	dome.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = SKY
	mat.render_priority = -100
	dome.material_override = mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	env.add_child(dome)
	return env


static func _lin3(c) -> Vector3:
	var l := _col(c).srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


# 전역 셰이더 값 (project.godot [shader_globals] 에 g3_* 로 등록됨)
static func _set_global(name: String, value) -> void:
	_globals[name] = value
	RenderingServer.global_shader_parameter_set(name, value)


static func global_value(name: String):
	return _globals.get(name)


static func _col(c) -> Color:
	if c is Color:
		return c
	var i := int(c)
	return Color8((i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff)


# ---- 지형 블록 (JS client/blocks.js, world.js 의 tfOn 블록). G1 이 지형 칸 (값 1) 만 MultiMesh 하나로:
#   mesh = G3.terrain_mesh(id), material_override = G3.terrain_material(id, low), use_custom_data = true,
#   custom_data = G3.terrain_custom(grid, w, d, h, skip) 의 n 번째 (순서 z → y → x, 지형 칸만, skip 칸 뺌), 칸 자리 Co.gxyz(x+.5, y+.5, z+.5)
# 테마에 지형 스타일이 없으면 셋 다 null (예전처럼 칸 색 블록)
static func terrain_style(theme_id):
	var t = C.WORLD_THEMES.get(theme_id) if theme_id != null else null
	return BS.style(t.terrain) if t != null and t.has("terrain") else null


static func terrain_mesh(theme_id) -> Mesh:
	var s = terrain_style(theme_id)
	if s == null:
		return null
	var m := BoxMesh.new()
	var k := int(s.segs) - 1
	m.subdivide_width = k
	m.subdivide_height = k
	m.subdivide_depth = k
	return m


static func terrain_material(theme_id, low := false) -> ShaderMaterial:
	var s = terrain_style(theme_id)
	if s == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = TERRAIN
	var mean := Vector3.ZERO
	for t in s.tints:
		mean += _lin3(t) / 3.0
	for i in 3:
		var c := _lin3(s.tints[i])
		m.set_shader_parameter("tf_tint%d" % i, Vector3(c.x / maxf(mean.x, 0.02), c.y / maxf(mean.y, 0.02), c.z / maxf(mean.z, 0.02)))
	var brick: Array = s.brick if s.brick != null else [1, 1, 0, 0]
	var p := {
		"tf_top": _lin3(s.top), "tf_side": _lin3(s.side), "tf_rim": _lin3(s.rim), "tf_glow": _lin3(s.get("glow") if s.get("glow") != null else 0),
		"tf_disp": 0.0 if low else float(s.disp), "tf_chamfer": _v2(s.chamfer), "tf_step": 0.0 if low else float(s.step),
		"tf_blotch": _v2(s.blotch), "tf_edge": float(s.edge), "tf_height": _v2(s.height), "tf_vein": float(s.get("veins", 0.0)),
		"tf_vein_scale": float(s.get("veinScale", 1.0)), "tf_mottle": float(s.get("mottle", 0.0)), "tf_wear": float(s.get("wear", 0.0)),
		"tf_top_lift": float(s.get("topLift", 1.0)), "tf_grid": _v2(s.grid), "tf_lip": float(s.lip), "tf_strata": _v2(s.strata),
		"tf_brick": Vector4(brick[0], brick[1], brick[2], brick[3]), "tf_sheen": float(s.sheen), "tf_side_shade": float(s.sideShade),
		"tf_ao": float(s.ao), "tf_hi": float(s.hi), "tf_self": float(s.selfLight),
	}
	for k in p:
		m.set_shader_parameter(k, p[k])
	return m


static func terrain_custom(grid: PackedByteArray, w: int, d: int, h: int, skip: Dictionary = {}) -> PackedColorArray:
	return BS.cell_looks(grid, w, d, h, skip)


static func _v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


# ---- 튀어나온 조각 (JS BlockDecor, sprouts.gd). 테마에 sprout 없으면 null. 격자 바뀔 때마다 sprout_update (그래픽 낮춤이면 비움)
static func sprout_node(theme_id) -> Node3D:
	var s = terrain_style(theme_id)
	if s == null or s.sprout == null:
		return null
	var t: Dictionary = C.WORLD_THEMES[theme_id]
	var pal: Array = t.glow if t.get("glow") is Array else ([s.glow] if s.get("glow") != null else [])
	var n = SPROUTS.new()
	n.name = "G3Sprouts"
	n.setup(s, pal, toon_material)
	return n


static func sprout_update(node: Node3D, grid: PackedByteArray, w: int, d: int, h: int, skip: Dictionary = {}, low := false) -> void:
	if node:
		node.refresh(grid, w, d, h, skip, low)


# ---- 몸 묶기 (JS batch.js, batch.gd): body 아래 G3 툰 조각을 SkinnedMesh 하나로 (툰 1 + 외곽선 1). outline: 외곽선 붙임
static func batch_mesh(body: Node3D, outline := true) -> Node3D:
	var b = BATCH.new()
	b.name = "G3Batch"
	body.add_child(b)
	b.build(body, toon_material(Color.WHITE, {"vertex_color": true, "outline": outline}))
	return b


# ---- 떠 있는 섬·먼 배경 (G1 world/scenery.gd make_mat 이 부름): opts vertex_color (꼭짓점 색 선형), outline, emissive (선형 Color), unshaded, no_fog
static func scenery_material(opts: Dictionary) -> Material:
	if opts.get("unshaded", false):
		var m := ShaderMaterial.new()
		m.shader = FLAT
		m.set_shader_parameter("use_vertex_color", opts.get("vertex_color", true))
		m.set_shader_parameter("no_fog", opts.get("no_fog", false))
		return m
	var o := {"vertex_color": opts.get("vertex_color", false), "outline": opts.get("outline", true), "no_fog": opts.get("no_fog", false)}
	var t := toon_material(Color.WHITE, o)
	t.set_shader_parameter("vertex_color_linear", true)
	if opts.has("emissive"):
		t.set_shader_parameter("emissive", (opts.emissive as Color).linear_to_srgb())
	return t


# ---- 바닥 판 (JS floorTexture + 옆면 rim): BoxMesh 하나에 이것 하나 (윗면만 무늬). 테마 없으면 null
const FLOOR_PAINT := {"grass": 0, "sand": 1, "stone": 2, "moss": 3, "cracks": 4, "marble": 5}


static func floor_material(theme_id) -> ShaderMaterial:
	var t = C.WORLD_THEMES.get(theme_id) if theme_id != null else null
	if t == null or not t.has("floor"):
		return null
	var f: Dictionary = t.floor
	var m := ShaderMaterial.new()
	m.shader = FLOOR
	m.set_shader_parameter("f_a", _lin3(f.a))
	m.set_shader_parameter("f_b", _lin3(f.b))
	m.set_shader_parameter("f_rim", _lin3(f.rim))
	m.set_shader_parameter("f_glow", _lin3(f.get("glow", 0)))
	m.set_shader_parameter("f_paint", FLOOR_PAINT.get(f.get("paint", "grass"), 0))
	var rgba := String(f.line).replace("rgba(", "").replace(")", "").split(",")
	var lc := Color(float(rgba[0]) / 255.0, float(rgba[1]) / 255.0, float(rgba[2]) / 255.0).srgb_to_linear()
	m.set_shader_parameter("f_line", Vector4(lc.r, lc.g, lc.b, float(rgba[3])))
	return m
