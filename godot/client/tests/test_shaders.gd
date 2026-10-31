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


# 판 빛 하늘 어둡게 = three Color.multiplyScalar(1 − (1 − dim) k).offsetHSL(0, sat k, 0) (값은 node three 로 뽑음)
func test_game_light_sky() -> void:
	var GL := preload("res://shaders/game_light.gd")
	for r in [[0.2, 0.4, 0.8, 0.5, 0.15, 1, 0.0625, 0.1875, 0.4375], [0.9, 0.3, 0.1, 0.7, 0.1, 0.5, 0.78625, 0.244375, 0.06375], [0.05, 0.05, 0.06, 0.5, 0.15, 1, 0.020875, 0.020875, 0.034125], [0.6, 0.6, 0.6, 0.75, 0.08, 1, 0.486, 0.414, 0.414]]:
		var got: Vector3 = GL._dimv(Vector3(r[0], r[1], r[2]), r[3], r[4], r[5])
		check(got.distance_to(Vector3(r[6], r[7], r[8])) < 1e-4, "하늘 어둡게 %s → %s" % [r, got])
	check(C.GAME_LIGHT_PRESETS.has(C.GAME_LIGHT), "기본 안 %s" % C.GAME_LIGHT)


# 그래픽 낮춤 한데 묶기: G3.low 가 기준 (인자 없으면), set_low 이 이미 만든 재질을 그 자리에서 바꾸고 되돌림
func test_low_gfx_switch() -> void:
	G3.low = false
	var tm := G3.terrain_material("crystal")
	var pm := G3.piece_material("volcano", null, {"rim": 0.75})
	var hm := G3.hazard_material("volcano", null, false)
	var world := Node3D.new()
	var gl = G3.game_light(world)
	check(tm.get_shader_parameter("tf_disp") > 0.0 and pm.get_shader_parameter("crack") > 0.0 and pm.get_shader_parameter("rim") > 0.0 and hm.get_shader_parameter("SHIMMER") == 1, "보통 값")
	hm.set_shader_parameter("uZ", 2.5) # 판마다 바뀌는 값은 낮춤이 건드리지 않음
	G3.set_low(world, true)
	check(hm.get_shader_parameter("uZ") == 2.5, "위험 표면 높이 그대로")
	check(G3.low and tm.get_shader_parameter("tf_disp") == 0.0 and tm.get_shader_parameter("tf_step") == 0.0, "지형 낮춤 (흔들기·높낮이 끔)")
	check(pm.get_shader_parameter("crack") == 0.0 and pm.get_shader_parameter("fresnel") == 0.0 and pm.get_shader_parameter("rim") == 0.0, "칸 낮춤 (금·빛 테·테두리 끔)")
	check(hm.get_shader_parameter("SHIMMER") == 0 and hm.get_meta("hz_low") == true, "위험 낮춤 (반짝임 끔·파도 반)")
	check(gl.low and not gl.is_on(), "판 빛 끔")
	check(G3.terrain_material("crystal").get_shader_parameter("tf_disp") == 0.0 and G3.piece_mesh("crystal") == G3.piece_mesh("crystal", true), "인자 없으면 G3.low")
	G3.set_low(world, false)
	check(tm.get_shader_parameter("tf_disp") > 0.0 and pm.get_shader_parameter("rim") > 0.0 and hm.get_shader_parameter("SHIMMER") == 1 and not gl.low, "되돌림")
	world.free()
