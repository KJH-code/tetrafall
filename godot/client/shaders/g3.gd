# G3 툰·외곽선·테마 (godot/PLAN.md 7절: shaders/ 는 G3, G1·G2 는 preload 해서 부름).
#   const G3 := preload("res://shaders/g3.gd")
#   mesh.material_override = G3.toon_material(Color(...))          # 툰 + 외곽선 (next_pass)
#   G3.set_hemi(...) / G3.add_sun(...)                             # 빛 (테마는 apply_theme 이 부름)
# JS 원본: client/toon.js (툰), render.js OutlineEffect (외곽선), 빛 세기는 three 값 그대로 받아 고도 값으로 바꿈 (/PI, toon.gdshader 주석)
extends RefCounted

const C := preload("res://core/config.gd")
const K := preload("res://shaders/g3_config.gd")
const TOON := preload("res://shaders/toon.gdshader")
const TOON_ALPHA := preload("res://shaders/toon_alpha.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

static var _globals := {} # 넣은 전역 셰이더 값 (RenderingServer 는 실행 중 읽기가 안 됨 — 테스트·확인용)


# 툰 재질 (three toon({...})). color: Color 또는 0xRRGGBB. opts: map (Texture2D), emissive (Color/숫자), emissive_energy,
# opacity (1 미만이면 투명), vertex_color (bool), outline (기본 true — 외곽선을 next_pass 로)
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
	if a < 1.0:
		m.render_priority = 1
	if opts.get("outline", true) and a >= 1.0:
		m.next_pass = outline_material()
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
	var d := Vector3(float(dir[0]), float(dir[2]), float(dir[1])).normalized() # 게임 (x, y, z위) → 고도 (x, z위, y)
	sun.look_at_from_position(Vector3.ZERO, -d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)
	sun.shadow_bias = K.SUN_SHADOW_BIAS
	sun.shadow_normal_bias = K.SUN_SHADOW_NORMAL_BIAS


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
