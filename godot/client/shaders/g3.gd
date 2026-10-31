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
const PIECE := preload("res://shaders/piece.gdshader")
const PIECE_ALPHA := preload("res://shaders/piece_alpha.gdshader")
const HAZARD := preload("res://shaders/hazard.gdshader")
const GAME_LIGHT := preload("res://shaders/game_light.gd")

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
	m.set_shader_parameter("hz_tint", opts.get("hz_tint", false)) # 위험에 잠기면 물들임 (블록·바닥 재질만)
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
static func apply_theme(world: Node3D, theme_id, low_arg = null) -> void:
	var low := _low(low_arg)
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
	env.set_meta("g3_theme_ver", int(env.get_meta("g3_theme_ver", 0)) + 1) # 판 빛 (game_light.gd) 이 원래 하늘 값을 다시 읽게
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


static func terrain_material(theme_id, low_arg = null) -> ShaderMaterial:
	var low := _low(low_arg)
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
	_track(m, func(l): return terrain_material(theme_id, l))
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


static func sprout_update(node: Node3D, grid: PackedByteArray, w: int, d: int, h: int, skip: Dictionary = {}, low_arg = null) -> void:
	var low := _low(low_arg)
	if node:
		node.set_meta("g3_last", [grid, w, d, h, skip]) # set_low 이 다시 깔 때
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


# ---- 테트리미노 칸 (JS piece-look.js PieceLook + shared/piece-look.js pieceSpec). 모양·면 그림은 JS 에서 뽑은 자산 (tools/piece_assets.mjs)
#   mm.mesh = G3.piece_mesh(theme_id, low) · material_override = G3.piece_material(theme_id, low, {transparent, opacity, rim})
#   칸 색은 인스턴스 색 (MultiMesh use_colors, sRGB, 알파는 transparent 일 때 곱함) = G3.piece_colors(theme_id)[모양 글자]
# theme_id 가 null 이거나 테마에 piece 가 없으면 기본 장난감 블록 ('toy')
static var _piece_shapes = null
static var _piece_meshes := {}


static func piece_spec(theme_id) -> Dictionary:
	var s := {"style": "toy", "shape": "round", "segs": 2, "fresnel": 0.0, "crack": 0.0, "accent": [0xffffff, 0xffffff], "opacity": 1.0}
	s.merge(C.PIECE_LOOK, true)
	s.colors = C.SHAPE_COLORS.duplicate()
	var t = C.WORLD_THEMES.get(theme_id) if theme_id != null else null
	if t != null and t.has("piece"):
		var cols: Dictionary = s.colors
		s.merge(t.piece, true)
		cols.merge(t.piece.get("colors", {}), true)
		s.colors = cols
	return s


static func piece_colors(theme_id) -> Dictionary:
	return piece_spec(theme_id).colors


static func _piece_key(theme_id) -> String:
	var t = C.WORLD_THEMES.get(theme_id) if theme_id != null else null
	return theme_id if t != null and t.has("piece") else "toy"


static func piece_mesh(theme_id, low_arg = null) -> ArrayMesh:
	var low := _low(low_arg)
	var key := "%s:%s" % [_piece_key(theme_id), low]
	if _piece_meshes.has(key):
		return _piece_meshes[key]
	if _piece_shapes == null:
		_piece_shapes = JSON.parse_string(FileAccess.get_file_as_string("res://assets/pieces/shapes.json"))
	var g: Dictionary = _piece_shapes[_piece_key(theme_id)]["low" if low else "normal"]
	var n: int = g.pos.size() / 3
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	pos.resize(n)
	nrm.resize(n)
	uv.resize(n)
	uv2.resize(n)
	for i in n:
		var j: int = i - i % 3 + [0, 2, 1][i % 3] # 고도 앞면은 시계 방향 → 삼각형 2·3번 꼭짓점 바꿈
		pos[i] = Co.gxyz(g.pos[j * 3], g.pos[j * 3 + 1], g.pos[j * 3 + 2])
		nrm[i] = Co.gxyz(g.nrm[j * 3], g.nrm[j * 3 + 1], g.nrm[j * 3 + 2])
		uv[i] = Vector2(g.uv[j * 2], 1.0 - g.uv[j * 2 + 1]) # three 그림은 아래가 v 0
		uv2[i] = Vector2(g.acc[j], 0.0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_piece_meshes[key] = m
	return m


# opts: transparent (알파 = opacity × 인스턴스 색 a, 그림자 안 드리움), opacity, rim (판 빛 테두리, set_game_light 가 바꿈), extra_glow (타이틀), outline (불투명만, 기본 true)
static func piece_material(theme_id, low_arg = null, opts := {}) -> ShaderMaterial:
	var low := _low(low_arg)
	var s := piece_spec(theme_id)
	var m := ShaderMaterial.new()
	var tr: bool = opts.get("transparent", false) or float(s.opacity) < 1.0
	m.shader = PIECE_ALPHA if tr else PIECE
	m.set_shader_parameter("face_tex", load("res://assets/pieces/%s.png" % s.style))
	m.set_shader_parameter("accent0", _col(s.accent[0]))
	m.set_shader_parameter("accent1", _col(s.accent[1]))
	m.set_shader_parameter("glow", float(s.get("glow", 0.0)) + float(opts.get("extra_glow", 0.0)))
	m.set_shader_parameter("crack", 0.0 if low else float(s.crack))
	m.set_shader_parameter("fresnel", 0.0 if low else float(s.fresnel))
	m.set_shader_parameter("rim", 0.0 if low else float(opts.get("rim", 0.0)))
	m.set_shader_parameter("opacity", float(opts.get("opacity", s.opacity)))
	if not tr and opts.get("outline", true):
		m.next_pass = outline_material()
	_track(m, func(l): return piece_material(theme_id, l, opts))
	return m


# ---- 상승하는 위험 (JS client/hazard.js). G1 world/hazard_view.gd 가 부름:
#   표면 두 판: near = MeshInstance (mesh = hazard_mesh(false, low), 자리 = 필드 가운데 표면 높이, 크기 = 필드 + 둘레 HZ_MARGIN×2 로 scale)
#              far  = MeshInstance (mesh = hazard_mesh(true, low), 자리 = 필드 가운데 표면 높이, scale 1)
#   재질 = hazard_material(theme_id, low, far) 둘 — 매 프레임 hazard_update([near_mat, far_mat], world, {...}) 로 같은 값
#   잠긴 블록 물들임은 전역 값이라 hazard_update 가 함께 (지형·바닥·칸 재질은 늘, toon_material 은 opts hz_tint = true 인 것만)
const HZ_STYLE := {"water": 0, "lava": 1, "swamp": 2, "energy": 3, "storm": 4}
const HZ_MARGIN := 6 # world/hazard_field.gd MARGIN (JS HAZARD_MARGIN)


static func hazard_look(theme_id) -> Dictionary:
	var t = C.WORLD_THEMES.get(theme_id) if theme_id != null else null
	return t.hazard if t != null and t.has("hazard") else C.WORLD_THEMES[C.HAZARD_FALLBACK].hazard


static func hazard_mesh(far: bool, low_arg = null) -> PlaneMesh:
	var low := _low(low_arg)
	var m := PlaneMesh.new()
	var seg: int = int(C.HAZARD_FAR_SEG) if far else int(C.HAZARD_SEG[1 if low else 0])
	m.size = Vector2.ONE * (2.0 * C.HAZARD_FAR_SIZE if far else 1.0)
	m.subdivide_width = seg - 1
	m.subdivide_depth = seg - 1
	return m


static func hazard_material(theme_id, low_arg = null, far := false) -> ShaderMaterial:
	var low := _low(low_arg)
	var L := hazard_look(theme_id)
	var m := ShaderMaterial.new()
	m.shader = HAZARD
	m.render_priority = 1 # JS renderOrder 1: 블록 뒤에
	m.set_shader_parameter("STYLE", HZ_STYLE.get(L.style, 1))
	m.set_shader_parameter("FAR", 1 if far else 0)
	m.set_shader_parameter("SHIMMER", 0 if low else 1)
	m.set_shader_parameter("HZ_CURVE_FROM", C.HAZARD_CURVE_FROM)
	m.set_shader_parameter("HZ_CURVE", C.HAZARD_CURVE)
	m.set_shader_parameter("HZ_NOISE_WAVE", C.HAZARD_NOISE_WAVE)
	m.set_shader_parameter("HZ_SHIMMER_N", C.HAZARD_SHIMMER_NORMAL)
	m.set_shader_parameter("HZ_FOG_MIX", C.HAZARD_FOG_MIX)
	for k in ["deep", "mid", "shallow", "foam"]:
		m.set_shader_parameter("u" + k.capitalize(), _lin3(L[k]))
	m.set_shader_parameter("uAlpha", _v2(L.alpha))
	m.set_shader_parameter("uReflect", float(L.reflect))
	m.set_shader_parameter("uDepthFade", float(L.depthFade))
	m.set_shader_parameter("uMargin", float(HZ_MARGIN))
	m.set_meta("hz_low", low)
	m.set_meta("hz_theme", theme_id)
	_track(m, func(l): return hazard_material(theme_id, l, far))
	return m


# 닿는 곳 거리 표 (world/hazard_field.gd field() 결과) → 그림 (r = 거리/3, g = (바닥+10)/40, JS uploadField 그대로)
static func hazard_field_texture(f: Dictionary) -> ImageTexture:
	var nx: int = f.nx
	var ny: int = f.ny
	var data := PackedByteArray()
	data.resize(nx * ny * 4)
	for i in nx * ny:
		data[i * 4] = roundi(f.dist[i] / 3.0 * 255.0)
		data[i * 4 + 1] = roundi(clampf((f.ground[i] + 10.0) / 40.0, 0.0, 1.0) * 255.0)
		data[i * 4 + 3] = 255
	return ImageTexture.create_from_image(Image.create_from_data(nx, ny, false, Image.FORMAT_RGBA8, data))


# 매 프레임. p: {on, time (초, 화면 시계), z (표면), pulse (0..1, 차오름 번쩍 — JS HAZARD_PULSE_DECAY 로 줄임),
#   bulge: Vector4 (발 밑 들썩 x, y, 세기, 0 — 게임 좌표), field: field() 결과 (바뀔 때만 주면 됨), rings: far_rings() 결과 [{x, y, r}]}
static func hazard_update(mats: Array, world: Node3D, p: Dictionary) -> void:
	var on: bool = p.get("on", false)
	var theme_id = mats[0].get_meta("hz_theme") if mats.size() else null
	var L := hazard_look(theme_id)
	var t: float = p.get("time", 0.0)
	var zs: float = p.get("z", -99.0)
	# 잠긴 블록 물들임 (전역)
	_set_global("g3_hz", Vector4(zs, float(L.tintDepth), float(L.band[1]) * (0.85 + 0.15 * sin(t * 5.0)), 1.0 if on else 0.0))
	_set_global("g3_hz_tint", _lin3(L.tint))
	_set_global("g3_hz_band", _lin3(L.band[0]))
	_set_global("g3_hz_mode", 1.0 if L.band[2] else 0.0)
	# 하늘 지평선 아래도 액체 색으로 (JS dome below), 꺼지면 되돌림
	var env := world.get_node_or_null("G3Env")
	var sky: ShaderMaterial = env.get_node("Sky").material_override if env else null
	if sky:
		if on:
			if not sky.has_meta("below0"):
				sky.set_meta("below0", sky.get_shader_parameter("below"))
			var fog: Vector3 = global_value("g3_fog_color")
			var liq := _lin3(L.deep).lerp(fog if fog != null else Vector3.ZERO, C.HAZARD_FOG_MIX)
			sky.set_shader_parameter("below", (sky.get_meta("below0") as Vector3).lerp(liq, 0.9))
		elif sky.has_meta("below0"):
			sky.set_shader_parameter("below", sky.get_meta("below0"))
			sky.remove_meta("below0")
	if not on:
		return
	var tex = hazard_field_texture(p.field) if p.has("field") else null
	var rings: Array = p.get("rings", [])
	var ring_v: Array[Vector4] = []
	for i in 16:
		ring_v.append(Vector4(rings[i].x, rings[i].y, rings[i].r, 1.0) if i < rings.size() else Vector4.ZERO)
	for m: ShaderMaterial in mats:
		var low: bool = m.get_meta("hz_low", false)
		m.set_shader_parameter("uTime", t)
		m.set_shader_parameter("uZ", zs)
		m.set_shader_parameter("uPulse", p.get("pulse", 0.0))
		m.set_shader_parameter("uWave", Vector2(float(L.wave[0]) * (0.5 if low else 1.0), float(L.wave[1])))
		m.set_shader_parameter("uBulge", p.get("bulge", Vector4.ZERO))
		m.set_shader_parameter("uRings", ring_v if not low else [])
		m.set_shader_parameter("uFog", global_value("g3_fog_color"))
		m.set_shader_parameter("uFogRange", Vector3(global_value("g3_fog_near"), global_value("g3_fog_far"), C.HAZARD_FAR_SIZE))
		if sky:
			m.set_shader_parameter("uHorizon", sky.get_shader_parameter("horizon"))
			m.set_shader_parameter("uSky", (sky.get_shader_parameter("mid") as Vector3).lerp(sky.get_shader_parameter("horizon"), 0.5))
			m.set_shader_parameter("uSunDir", sky.get_shader_parameter("sun_dir"))
		if tex:
			m.set_shader_parameter("uField", tex)
			m.set_shader_parameter("uFieldRect", Vector4(p.field.x0, p.field.y0, p.field.w, p.field.d))


# ---- 판 빛 (JS game-light.js, game_light.gd): world 아래 "G3Light" 하나
static func game_light(world: Node3D) -> Node3D:
	var n = world.get_node_or_null("G3Light")
	if n:
		return n
	n = GAME_LIGHT.new()
	n.name = "G3Light"
	n.low = low
	world.add_child(n)
	return n



# ---- 그래픽 낮춤 한데 묶기 (설정 lowGfx 하나 = JS render.js setLowGfx): G3.low 가 기준, low 인자를 안 주면 이 값.
# set_low(world, on): 이미 만든 G3 재질 (지형·칸·위험) 을 그 자리에서 낮은 판 값으로, 튀어나온 조각 비움/다시, 판 빛 끔, 그림자 끔.
# 모양이 다른 것 (칸 모양 low = 둥근 상자·위험 판 격자 수) 은 G1 이 world 를 다시 깔 때 (apply_theme) 새로 받음 — JS 도 setPieceLook 으로 다시 만듦
static var low := false
static var _mats: Array = [] # [WeakRef 재질, Callable(low) → 같은 설정의 새 재질]
static var _sprouts: Array = [] # WeakRef 조각 노드


static func _low(arg) -> bool:
	return low if arg == null else bool(arg)


static func _track(m: ShaderMaterial, make: Callable) -> void:
	_mats.append([weakref(m), make])


static func set_low(world: Node3D, on: bool) -> void:
	low = on
	var keep := []
	for e in _mats:
		var m = e[0].get_ref()
		if m == null:
			continue
		keep.append(e)
		var fresh: ShaderMaterial = e[1].call(on)
		var other: ShaderMaterial = e[1].call(not on)
		_mats.pop_back() # 새로 만든 둘은 따라가지 않음 (방금 _track 에 들어감)
		_mats.pop_back()
		if fresh.shader != m.shader:
			m.shader = fresh.shader
		for u in fresh.shader.get_shader_uniform_list(): # 낮춤에 따라 다른 값만 (판마다 바뀌는 값 — 위험 표면 높이·거리 표 등 — 은 그대로)
			var v = fresh.get_shader_parameter(u.name)
			if v != other.get_shader_parameter(u.name):
				m.set_shader_parameter(u.name, v)
		for k in fresh.get_meta_list():
			m.set_meta(k, fresh.get_meta(k))
	_mats = keep
	if world:
		for n in world.find_children("G3Sprouts", "", true, false):
			if n.has_meta("g3_last"):
				var a: Array = n.get_meta("g3_last")
				n.refresh(a[0], a[1], a[2], a[3], a[4], on)
		var gl = world.get_node_or_null("G3Light")
		if gl:
			gl.low = on
		if world.get_node_or_null("G3Env"):
			set_shadows(world, not on)


# ---- 첫 진입 멈춤 줄이기 (JS render.js prewarmLobby): 고도는 처음 그릴 때 셰이더를 만듦 (Compatibility 는 미리 만들기 없음) →
# 메뉴에서 쉴 때 G3 셰이더를 쓰는 모든 갈래 (보통 메시·MultiMesh (인스턴스 색·custom)·SkinnedMesh, 그림자 패스 포함) 를 카메라 앞에 아주 작게 한 번씩 그려 둠.
# 만든 셰이더는 Shader 자원 (g3.gd preload) 에 남아 판에서 다시 안 만듦. frames 뒤 스스로 치움. 반환: 그 노드 (done 신호)
static func prewarm(world: Node3D, theme_id = null, frames := 3) -> Node3D:
	var cam := world.get_viewport().get_camera_3d() if world.is_inside_tree() else null
	var root := Node3D.new()
	root.name = "G3Prewarm"
	world.add_child(root)
	if cam:
		root.global_transform = cam.global_transform.translated_local(Vector3(0, 0, -2.0))
	var tid = theme_id if theme_id != null else "volcano"
	var mats: Array = [
		toon_material(Color.WHITE), toon_material(Color.WHITE, {"opacity": 0.5}), toon_material(Color.WHITE, {"vertex_color": true, "outline": false}),
		toon_material(Color.WHITE, {"hz_tint": true}), terrain_material(tid), floor_material(tid), piece_material(tid), piece_material(null), piece_material(tid, null, {"transparent": true}), # 테마가 늘 투명이어도 (수정) 불투명 갈래까지
		hazard_material(tid, null, false), scenery_material({"unshaded": true}), scenery_material({"vertex_color": true}),
	]
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.001
	var i := 0
	for m in mats:
		if m == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = m
		mi.position = Vector3(i * 0.002, 0, 0)
		root.add_child(mi)
		var mm := MultiMesh.new() # 인스턴스 갈래 (지형·칸·조각·판 빛은 이것)
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = box
		mm.instance_count = 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.position = Vector3(i * 0.002, 0.002, 0)
		root.add_child(mmi)
		i += 1
	# 몸 묶음 (SkinnedMesh 갈래)
	var body := Node3D.new()
	var piece := MeshInstance3D.new()
	piece.mesh = box
	piece.material_override = toon_material(Color.WHITE)
	body.add_child(piece)
	body.position = Vector3(0, -0.002, 0)
	root.add_child(body)
	batch_mesh(body)
	var gl := game_light(world) # 판 빛 무리 (빈 프레임도 셰이더는 그림) 는 halos 하나로

	var halo := MultiMeshInstance3D.new()
	halo.multimesh = MultiMesh.new()
	halo.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	halo.multimesh.use_colors = true
	halo.multimesh.mesh = QuadMesh.new()
	halo.multimesh.instance_count = 1
	halo.material_override = gl.get_node("Halos").material_override
	halo.scale = Vector3.ONE * 0.001
	root.add_child(halo)
	var t := Engine.get_main_loop() as SceneTree # 트리 밖 world 여도
	var left := [frames]
	var rid := root.get_instance_id() # 노드를 직접 잡지 않음 (먼저 지워져도 됨)
	var tick := func(): pass
	tick = func():
		left[0] -= 1
		if left[0] > 0:
			return
		t.process_frame.disconnect(tick)
		var n = instance_from_id(rid)
		if n != null:
			n.queue_free()
	t.process_frame.connect(tick)
	return root
