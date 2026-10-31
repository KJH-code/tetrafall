# G3 툰·외곽선 (shaders/): 재질 만들기·외곽선 붙이기·빛 전역 값이 JS (client/toon.js·render.js OutlineEffect) 값 그대로인지
extends RefCounted

const C := preload("res://core/config.gd")
const G3 := preload("res://shaders/g3.gd")
const K := preload("res://shaders/g3_config.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func test_toon_steps_match_js() -> void:
	# client/toon.js TOON_GRADIENT = [110, 175, 255] (바이트) → 0~1
	check(is_equal_approx(K.TOON_STEPS.x, 110.0 / 255.0) and is_equal_approx(K.TOON_STEPS.y, 175.0 / 255.0) and K.TOON_STEPS.z == 1.0, "툰 3단")
	var m := G3.toon_material(0xe0533a)
	check(m.get_shader_parameter("toon_steps") == K.TOON_STEPS, "재질에 3단")
	check(m.get_shader_parameter("albedo").is_equal_approx(Color8(0xe0, 0x53, 0x3a)), "색 (0xRRGGBB → sRGB 그대로)")


func test_outline_next_pass() -> void:
	var m := G3.toon_material(Color.WHITE)
	check(m.next_pass != null and m.next_pass.shader == G3.OUTLINE, "외곽선 기본 켬 (next_pass)")
	check(is_equal_approx(m.next_pass.get_shader_parameter("thickness"), C.OUTLINE_THICKNESS), "굵기 = config OUTLINE_THICKNESS")
	check(m.next_pass.get_shader_parameter("line_color") == K.OUTLINE_COLOR, "색 = render.js OutlineEffect [0.08, 0.05, 0.1]")
	check(G3.toon_material(Color.WHITE, {"outline": false}).next_pass == null, "outline false")
	check(G3.no_outline(G3.toon_material(Color.WHITE)).next_pass == null, "no_outline")
	var t := G3.toon_material(Color.WHITE, {"opacity": 0.5})
	check(t.shader == G3.TOON_ALPHA and t.next_pass == null, "반투명은 투명 셰이더·외곽선 없음 (불투명은 ALPHA 를 안 써야 그림자를 드리움)")
	var mats := [G3.toon_material(Color.RED), G3.toon_material(Color.BLUE)]
	G3.set_outline(mats, false)
	check(mats.all(func(x): return x.next_pass == null), "설정: 외곽선 끄기")
	G3.set_outline(mats, true)
	check(mats.all(func(x): return x.next_pass != null), "설정: 외곽선 켜기")


func test_light_globals() -> void:
	# three 빛 값 그대로 받아 선형 전역 값으로 (툰 셰이더가 / PI)
	G3.set_hemi(0xffffff, 0x000000, 1.15)
	check(G3.global_value("g3_hemi_sky") == Vector3(1, 1, 1), "하늘빛 위 (선형)")
	check(is_equal_approx(G3.global_value("g3_hemi_energy"), 1.15), "하늘빛 세기")
	var sun := DirectionalLight3D.new()
	G3.set_sun(sun, 0xffffff, 1.25, C.SUN_DIR)
	var s: Vector3 = G3.global_value("g3_sun")
	check(s.is_equal_approx(Vector3(1.25, 1.25, 1.25)), "해 색 × 세기 %s" % s)
	check(G3.global_value("g3_sun_on") == 1.0, "해 켬")
	# 해가 있는 쪽 = 게임 SUN_DIR (x, y, z위) → 고도 coords.gxyz: 빛은 그 반대로 비춤
	var want := -preload("res://core/coords.gd").gxyz(C.SUN_DIR[0], C.SUN_DIR[1], C.SUN_DIR[2]).normalized()
	check((-sun.transform.basis.z).is_equal_approx(want), "해 방향")
	sun.free()
