# 판 빛 3D 부분 (client/game-light.js 의 빛 무리·빛 터짐): 화면을 보는 가산 사각형 MultiMesh 하나 (그리기 1번).
# 떨어지는 블록·아이템 둘레 빛 무리 (halo), 착지·KO·필살기 짧은 빛 (flash). 안은 C.GAME_LIGHT (GAME_LIGHT_PRESETS), 판 중에만, 그래픽 낮춤이면 끔
# 색 보정·비네트·하늘 어둡게는 G3 (set_game_light) 몫
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")

var mmi := MultiMeshInstance3D.new()
var flashes := [] # {x, y, z, color, size, ms, t0}
var preset: Dictionary = C.GAME_LIGHT_PRESETS.get(C.GAME_LIGHT, {})
var low := false
var _n := 0


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = int(C.GAME_LIGHT_MAX)
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = glow_texture()
	m.render_priority = 5
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 1000.0
	add_child(mmi)


# 빛 한 점: 가운데서 바깥으로 (1 - d)^2.2 로 사라짐 (game-light.js FRAG)
static func glow_texture() -> Texture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in 9:
		var d := i / 8.0
		offs.append(d)
		cols.append(Color(1, 1, 1, pow(1.0 - d, 2.2)))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func on() -> bool:
	return not low and not preset.is_empty() and str(C.GAME_LIGHT) != "off"


# 블록 빛 테두리 (PieceLook rim, G3 game_light 와 같은 이름)
var rim: float:
	get:
		return float(preset.get("rim", 0.0)) if on() else 0.0


# 짧은 빛 (착지·KO·필살기): size 칸, ms 동안 커지며 사라짐
func flash(x: float, y: float, z: float, color: int, size: float, ms: float) -> void:
	if not on() or not preset.get("flash", 0):
		return
	if flashes.size() >= int(C.GAME_LIGHT_FLASH_MAX):
		flashes.pop_front()
	flashes.append({"x": x, "y": y, "z": z, "color": color, "size": size * float(preset.flash), "ms": ms, "t0": Time.get_ticks_msec() * 1.0})


func _add(x: float, y: float, z: float, color: int, size: float, a: float) -> void:
	if _n >= int(C.GAME_LIGHT_MAX) or a <= 0:
		return
	var mm := mmi.multimesh
	mm.set_instance_transform(_n, Transform3D(Basis().scaled(Vector3.ONE * size), Co.gxyz(x, y, z)))
	var c := Co.color(color)
	c.a = a
	mm.set_instance_color(_n, c)
	_n += 1


# 매 프레임: active = 판 중 (countdown·playing·over). halos = [[x, y, z, color, 크기 배수]]
func frame(active: bool, halos: Array, _dt := 0.0) -> void:
	_n = 0
	if active and on():
		var h: Array = preset.get("halo", [0, 0])
		if float(h[0]) > 0:
			for o in halos:
				_add(o[0], o[1], o[2], o[3], float(h[1]) * (o[4] if o.size() > 4 else 1.0), float(h[0]))
		var now := Time.get_ticks_msec() * 1.0
		var keep := []
		for f in flashes:
			var k: float = (now - f.t0) / f.ms
			if k < 1:
				keep.append(f)
				_add(f.x, f.y, f.z, f.color, f.size * (0.6 + 0.6 * k), (1 - k) * (1 - k))
		flashes = keep
	else:
		flashes.clear()
	mmi.multimesh.visible_instance_count = _n
	mmi.visible = _n > 0
