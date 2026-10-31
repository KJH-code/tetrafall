# 판 빛 (JS client/game-light.js GameLight): 판 중에만 색 보정 (Environment 밝기·대비·채도 — JS 캔버스 CSS filter 자리) · 가장자리 어둠 (CanvasLayer)
# · 하늘·배경·안개를 조금 어둡고 진하게 · 떨어지는 블록·아이템 빛 무리와 착지·KO·필살기 빛 터짐 (더하기 사각형 MultiMesh 하나). 블록 빛 테두리는 piece_material rim
# 값은 C.GAME_LIGHT_PRESETS (기본 C.GAME_LIGHT = vivid). 그래픽 낮춤이면 끔.
#   var gl := G3.game_light(world)   # world 아래 "G3Light" 하나 (apply_theme 뒤에 불러도 됨)
#   매 프레임 gl.frame(active, halos, dt): active = 판 중 (countdown·playing·over), halos = [[x, y, z, 색 0xRRGGBB, 크기 배수]] (게임 좌표, JS render.js 와 같은 목록)
#   gl.flash(x, y, z, 색, 크기 칸, ms) · gl.rim (블록 재질 rim 값) · gl.set_preset(이름) · gl.low = 그래픽 낮춤
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const HALO := preload("res://shaders/halo.gdshader")
const VIG := preload("res://shaders/vignette.gdshader")

var low := false
var preset_name := "off"
var p: Dictionary = {}
var mm := MultiMesh.new()
var flashes: Array = [] # {x, y, z, color, size, ms, t0}
var vig_layer := CanvasLayer.new()
var vig := ColorRect.new()
var sky_t := 0.0
var sky_k := -1.0
var base: Dictionary = {} # 테마 하늘 원래 값
var base_key = null
var env_root: Node3D # G3Env 를 가진 world


func _ready() -> void:
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = int(C.GAME_LIGHT_MAX)
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "Halos"
	mi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = HALO
	m.render_priority = 5 # JS renderOrder 5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3.ONE * -1000.0, Vector3.ONE * 2000.0)
	add_child(mi)
	vig_layer.layer = -1 # HUD 아래 (3D 바로 위)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.material = ShaderMaterial.new()
	vig.material.shader = VIG
	vig.visible = false
	vig_layer.add_child(vig)
	add_child(vig_layer)
	set_preset(C.GAME_LIGHT)


func set_preset(n: String) -> void:
	preset_name = n if C.GAME_LIGHT_PRESETS.has(n) else "off"
	p = C.GAME_LIGHT_PRESETS[preset_name]
	var v: Array = p.vignette
	var rgb := String(v[2]).split(",")
	vig.material.set_shader_parameter("color", Color(float(rgb[0]) / 255.0, float(rgb[1]) / 255.0, float(rgb[2]) / 255.0, float(v[0])))
	vig.material.set_shader_parameter("inner", float(v[1]))
	sky_k = -1.0


func is_on() -> bool:
	return not low and preset_name != "off"


var rim: float:
	get:
		return float(p.rim) if is_on() else 0.0


func flash(x: float, y: float, z: float, color, size: float, ms: float) -> void:
	if not is_on() or not p.flash:
		return
	if flashes.size() >= int(C.GAME_LIGHT_FLASH_MAX):
		flashes.pop_front()
	flashes.append({"x": x, "y": y, "z": z, "color": color, "size": size * float(p.flash), "ms": ms, "t0": Time.get_ticks_msec()})


func _add(n: int, x: float, y: float, z: float, color, size: float, a: float) -> int:
	if n >= mm.instance_count or a <= 0.0:
		return n
	mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3.ONE * size), Co.gxyz(x, y, z)))
	var c: Color = (color if color is Color else Co.color(color)).srgb_to_linear()
	c.a = a
	mm.set_instance_color(n, c)
	return n + 1


func frame(active: bool, halos: Array, dt := 1.0 / 60.0) -> void:
	var on := active and is_on()
	var env := _env()
	if env:
		var e: Environment = env.get_node("Env").environment
		var g: Array = p.grade
		e.adjustment_enabled = on and (g[0] != 1.0 or g[1] != 1.0 or g[2] != 1.0)
		e.adjustment_saturation = float(g[0])
		e.adjustment_contrast = float(g[1])
		e.adjustment_brightness = float(g[2])
	vig.visible = on and float(p.vignette[0]) > 0.0
	sky_t = clampf(sky_t + (1.0 if on else -1.0) * C.GAME_LIGHT_SKY_SPEED * minf(dt, 0.1), 0.0, 1.0)
	_paint_sky(sky_t if p.sky != null else 0.0)
	var n := 0
	if on:
		var h: Array = p.halo
		if float(h[0]) > 0.0:
			for it in halos:
				n = _add(n, it[0], it[1], it[2], it[3], float(h[1]) * (float(it[4]) if it.size() > 4 and it[4] else 1.0), float(h[0]))
		var now := Time.get_ticks_msec()
		flashes = flashes.filter(func(f): return now - f.t0 < f.ms)
		for f in flashes:
			var k: float = (now - f.t0) / f.ms
			n = _add(n, f.x, f.y, f.z, f.color, f.size * (0.6 + 0.6 * k), (1.0 - k) * (1.0 - k))
	else:
		flashes.clear()
	mm.visible_instance_count = n


func _g3():
	return load("res://shaders/g3.gd")


func _env() -> Node3D:
	var w := get_parent()
	return w.get_node_or_null("G3Env") if w else null


# 하늘·배경·안개: 원래 값 × (1 − (1 − dim) k) 에 채도 + sat k (three offsetHSL, 선형 색에서)
func _paint_sky(k: float) -> void:
	var env := _env()
	if env == null:
		return
	var sky: ShaderMaterial = env.get_node("Sky").material_override
	var e: Environment = env.get_node("Env").environment
	var key = sky.get_instance_id()
	if base_key != key or env.get_meta("g3_theme_ver", 0) != base.get("ver", -1):
		base_key = key
		base = {"ver": env.get_meta("g3_theme_ver", 0), "bg": e.background_color.srgb_to_linear(), "fog": _g3().global_value("g3_fog_color")}
		for s in ["top", "mid", "horizon", "below"]:
			base[s] = sky.get_shader_parameter(s)
		sky_k = -1.0
	if absf(k - sky_k) < 0.002 or p.sky == null and k == 0.0 and sky_k == 0.0:
		return
	sky_k = k
	var dim: float = p.sky[0] if p.sky != null else 1.0
	var sat: float = p.sky[1] if p.sky != null else 0.0
	for s in ["top", "mid", "horizon", "below"]:
		sky.set_shader_parameter(s, _dimv(base[s], dim, sat, k))
	var bg := _dimv(Vector3(base.bg.r, base.bg.g, base.bg.b), dim, sat, k)
	e.background_color = Color(bg.x, bg.y, bg.z).linear_to_srgb()
	if base.fog != null:
		_g3()._set_global("g3_fog_color", _dimv(base.fog, dim, sat, k))


static func _dimv(v: Vector3, dim: float, sat: float, k: float) -> Vector3:
	var c := v * (1.0 - (1.0 - dim) * k)
	return _offset_sat(c, sat * k)


# three Color.offsetHSL(0, ds, 0): HSL 로 바꿔 채도만 더하고 (0..1 로 자름) 되돌림
static func _offset_sat(c: Vector3, ds: float) -> Vector3:
	var mx := maxf(c.x, maxf(c.y, c.z))
	var mn := minf(c.x, minf(c.y, c.z))
	var l := (mx + mn) / 2.0
	var d := mx - mn
	var s := 0.0
	var h := 0.0
	if d > 0.0:
		s = d / (2.0 - mx - mn) if l > 0.5 else d / (mx + mn)
	if d == 0.0:
		pass # 회색: three 처럼 색상 0 (빨강 쪽) 으로 채도를 더함
	elif mx == c.x:
		h = (c.y - c.z) / d + (6.0 if c.y < c.z else 0.0)
	elif mx == c.y:
		h = (c.z - c.x) / d + 2.0
	else:
		h = (c.x - c.y) / d + 4.0
	h /= 6.0
	s = clampf(s + ds, 0.0, 1.0)
	if s == 0.0:
		return Vector3(l, l, l)
	var q := l * (1.0 + s) if l < 0.5 else l + s - l * s
	var pp := 2.0 * l - q
	return Vector3(_hue(pp, q, h + 1.0 / 3.0), _hue(pp, q, h), _hue(pp, q, h - 1.0 / 3.0))


static func _hue(p_: float, q: float, t: float) -> float:
	if t < 0.0: t += 1.0
	if t > 1.0: t -= 1.0
	if t < 1.0 / 6.0: return p_ + (q - p_) * 6.0 * t
	if t < 0.5: return q
	if t < 2.0 / 3.0: return p_ + (q - p_) * 6.0 * (2.0 / 3.0 - t)
	return p_
