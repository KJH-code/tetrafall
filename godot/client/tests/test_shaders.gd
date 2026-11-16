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
	check(tm.get_shader_parameter("tf_disp") > 0.0 and pm.get_shader_parameter("crack") > 0.0 and pm.get_shader_parameter("rim") > 0.0 and hm.shader == G3.hazard_shader(1, false, true), "보통 값")
	hm.set_shader_parameter("uZ", 2.5) # 판마다 바뀌는 값은 낮춤이 건드리지 않음
	G3.set_low(world, true)
	check(hm.get_shader_parameter("uZ") == 2.5, "위험 표면 높이 그대로")
	check(G3.low and tm.get_shader_parameter("tf_disp") == 0.0 and tm.get_shader_parameter("tf_step") == 0.0, "지형 낮춤 (흔들기·높낮이 끔)")
	check(pm.get_shader_parameter("crack") == 0.0 and pm.get_shader_parameter("fresnel") == 0.0 and pm.get_shader_parameter("rim") == 0.0, "칸 낮춤 (금·빛 테·테두리 끔)")
	check(hm.shader == G3.hazard_shader(1, false, false) and hm.get_meta("hz_low") == true, "위험 낮춤 (반짝임 끔·파도 반)")
	check(gl.low and not gl.is_on(), "판 빛 끔")
	check(G3.terrain_material("crystal").get_shader_parameter("tf_disp") == 0.0 and G3.piece_mesh("crystal") == G3.piece_mesh("crystal", true), "인자 없으면 G3.low")
	G3.set_low(world, false)
	check(tm.get_shader_parameter("tf_disp") > 0.0 and pm.get_shader_parameter("rim") > 0.0 and hm.shader == G3.hazard_shader(1, false, true) and not gl.low, "되돌림")
	world.free()


# 첫 진입 멈춤 줄이기: prewarm 이 G3 셰이더마다 보통 메시·MultiMesh 를 하나씩 + 몸 묶음 (SkinnedMesh) + 판 빛 무리를 그려 둠
func test_prewarm_covers_shaders() -> void:
	var world := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	var r := G3.prewarm(world, "crystal")
	var shaders := {}
	var kinds := {"mesh": 0, "multi": 0, "skin": 0}
	for n in r.find_children("*", "GeometryInstance3D", true, false):
		var m = n.material_override
		if m is ShaderMaterial:
			shaders[m.shader.resource_path] = true
			if "hazard.gdshaderinc" in m.shader.code:
				shaders["res://shaders/hazard.gdshader"] = true # 갈래 셰이더 (#define)
		if n is MultiMeshInstance3D:
			kinds.multi += 1
		elif n is MeshInstance3D and n.skin != null:
			kinds.skin += 1
		elif n is MeshInstance3D:
			kinds.mesh += 1
	for s in ["toon", "toon_alpha", "terrain", "floor", "piece", "piece_alpha", "hazard", "flat", "halo"]:
		check(shaders.has("res://shaders/%s.gdshader" % s), "prewarm 에 %s 셰이더" % s)
	check(kinds.multi >= 10 and kinds.mesh >= 10 and kinds.skin == 1, "보통·MultiMesh·SkinnedMesh 갈래 %s" % kinds)
	world.free()



# 재질별 빛 덮어쓰기 (1인칭 팔 노을 빛): 켜면 그 재질만 local_* (선형), 끄면 전역
func test_toon_local_light() -> void:
	var m := G3.toon_material(0xa3adb8)
	G3.toon_local_light(m)
	check(m.get_shader_parameter("local_light") == true, "켬")
	var sun: Vector3 = m.get_shader_parameter("local_sun")
	var want := Color.hex(int(C.SUN_COLOR) << 8 | 0xff).srgb_to_linear()
	check(sun.is_equal_approx(Vector3(want.r, want.g, want.b) * 1.25), "해 = SUN_COLOR × 1.25 (선형) %s" % sun)
	check(is_equal_approx(m.get_shader_parameter("local_hemi_energy"), 1.15), "하늘빛 세기 1.15")
	G3.toon_local_light(m, false)
	check(m.get_shader_parameter("local_light") == false, "끔")


# 위험 액체 그래픽 낮춤 가벼운 판 (2026-10-31 재혁 실험2): 낮춤 갈래 (SHIMMER 0) 에서만 빛 띠 겹·비틀기·드문드문·반짝·거품 떨림·먼 섬 테·바탕 둘째 겹·종류 질감 (용암 빼고) 끔, 보통은 JS 그대로
func test_hazard_low_lite() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/hazard.gdshaderinc")
	for key in ["float fb = noise(wq + t * 0.05);", "float n = noise(q * 0.7 + t * 0.12) * 1.5;", "#if SHIMMER == 0 && STYLE != 1"]:
		check(inc.contains(key), "낮춤 갈래 있음: %s" % key)
	# 보통 갈래 (SHIMMER 1) 는 JS 식 그대로: 세 겹 빛 띠·비틀기·두 겹 바탕·먼 섬 테
	for key in ["noise(wq * 2.3 - t * 0.07) * 0.28 + noise(wq * 5.3 + t * 0.11) * 0.1", "vec2(noise(q * 0.13 + t * 0.04), noise(q * 0.13 - t * 0.035 + 5.2)) * 2.4", "0.5 * noise(q * 1.9 - t * 0.2)", "for (int i = 0; i < 16; i++)"]:
		check(inc.contains(key), "보통 갈래 그대로: %s" % key)
	var lo := G3.hazard_material("meadow", true)
	var hi := G3.hazard_material("meadow", false)
	check(lo.shader.code.contains("#define SHIMMER 0") and hi.shader.code.contains("#define SHIMMER 1"), "낮춤 = SHIMMER 0 갈래, 보통 = 1")


# 스텐실 (사냥꾼의 눈 x-ray 가 3인칭 내 몸 위엔 안 비침): 내 몸 툰은 STENCIL_MY_BODY 쓰기, x-ray 는 그 값이 아닌 칸만
func test_stencil_body_xray() -> void:
	var m := G3.toon_material(0xe0533a)
	G3.toon_stencil_write(m)
	check(m.shader != G3.TOON and m.shader.code.contains("stencil_mode write, compare_always, %d" % K.STENCIL_MY_BODY), "몸 툰 = 스텐실 쓰기 갈래")
	check(m.next_pass != null, "외곽선 그대로")
	G3.toon_stencil_write(m, false)
	check(m.shader == G3.TOON, "끄면 보통 툰")
	var x := StandardMaterial3D.new()
	G3.xray_skip_body(x)
	check(x.stencil_mode == BaseMaterial3D.STENCIL_MODE_CUSTOM and x.stencil_flags == BaseMaterial3D.STENCIL_FLAG_READ and x.stencil_compare == BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL and x.stencil_reference == K.STENCIL_MY_BODY, "x-ray = 그 값 아닌 칸만")
	check(x.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "x-ray 는 몸 다음에 그려짐 (투명 순서)")


# ===== C6 (겉모습 1 — 세계 바탕): 테마 고도 쪽 덮어쓰기 (world/theme_tune.gd) · 어두운 세 테마 밝기 · 하늘 띠 =====
const TT := preload("res://world/theme_tune.gd")


# G3.apply_theme·set_low 을 부르는 테스트가 전역 값 (안개·하늘빛·해) 과 G3.low 를 다음 테스트에 안 남기게
func _globals_keep() -> Dictionary:
	return G3._globals.duplicate(true)


func _globals_back(keep: Dictionary) -> void:
	for k in G3._globals.keys():
		if keep.has(k):
			G3._set_global(k, keep[k])
		else:
			G3._globals.erase(k) # 테마를 안 깐 상태 (뒤 테스트가 null 이면 자기 값을 넣음)
	G3.low = false


# 덮어쓰기 표는 하늘·하늘빛·해 세기·안개·절벽만 (floor·terrain·piece·hazard 는 JS 정답 테스트가 C.WORLD_THEMES 로 묶음)
func test_c6_tune_only_allowed_keys() -> void:
	check(TT.ALLOWED == ["sky", "hemi", "sunIntensity", "fog", "cliff"], "덮을 수 있는 키 %s" % [TT.ALLOWED])
	var sky_keys := ["top", "mid", "horizon", "below", "glow", "disc", "discSize", "stars"]
	for id in TT.TUNE:
		check(C.WORLD_THEMES.has(id), "%s: 있는 테마" % id)
		for k in TT.TUNE[id]:
			check(TT.ALLOWED.has(k), "%s: %s 는 못 덮음" % [id, k])
			check(typeof(TT.TUNE[id][k]) == typeof(C.WORLD_THEMES[id][k]) or (TT.TUNE[id][k] is float and C.WORLD_THEMES[id][k] is float), "%s.%s: 원래와 같은 꼴" % [id, k])
		for k in TT.TUNE[id].get("sky", {}):
			check(sky_keys.has(k), "%s: sky.%s 는 하늘 색 키가 아님" % [id, k])
		for k in ["hemi", "fog"]:
			if TT.TUNE[id].has(k):
				check(TT.TUNE[id][k].size() == C.WORLD_THEMES[id][k].size(), "%s.%s: 원래와 같은 길이" % [id, k])
	for id in C.WORLD_THEMES:
		var t := TT.theme(id)
		for k in ["floor", "terrain", "piece", "hazard", "seed", "sunDir", "sunColor", "sea", "cloud", "far", "props"]:
			check(t.get(k) == C.WORLD_THEMES[id].get(k), "%s.%s 는 그대로" % [id, k])


# 덮지 않은 키와 표에 없는 테마는 C.WORLD_THEMES 와 같다 (절벽 밝기 하한도 밝은 테마는 안 건드림). 결과는 기억해 둔 것 하나
func test_c6_tune_keeps_base() -> void:
	for id in C.WORLD_THEMES:
		var base: Dictionary = C.WORLD_THEMES[id]
		var t := TT.theme(id)
		check(is_same(t, TT.theme(id)), "%s: 같은 사전 (기억)" % id)
		check(t.keys() == base.keys(), "%s: 키 그대로" % id)
		if not TT.TUNE.has(id):
			check(t == base, "%s: 표에 없는 테마는 원래 그대로" % id)
			continue
		var over: Dictionary = TT.TUNE[id]
		for k in base:
			if k == "sky":
				for sk in base.sky:
					if not over.get("sky", {}).has(sk):
						check(t.sky[sk] == base.sky[sk], "%s: sky.%s 그대로" % [id, sk])
				check(t.sky.keys() == base.sky.keys(), "%s: sky 키 그대로" % id)
			elif not over.has(k) and k != "cliff":
				check(t[k] == base[k], "%s.%s 그대로" % [id, k])
		for k in over:
			if k == "sky":
				for sk in over.sky:
					check(int(t.sky[sk]) == int(over.sky[sk]), "%s: sky.%s 덮임" % [id, sk])
			else:
				check(t[k] == over[k], "%s.%s 덮임" % [id, k])
	check(TT.theme("nope").is_empty() and TT.theme(null).is_empty(), "없는 테마는 빈 사전")
	check(C.WORLD_THEMES.volcano.sky.horizon == 9186326.0 and C.WORLD_THEMES.volcano.hemi[2] == 1.45, "원래 표는 안 바뀜")


# 판 빛 vivid 가 하늘을 낮춘 뒤 (× 0.5, 채도 + 0.15) 에도 지평선이 하한 위 (예전 화산·수정은 아래 = 검정 덩어리)
func test_c6_dark_sky_floor() -> void:
	var GL := preload("res://shaders/game_light.gd")
	var sk: Array = C.GAME_LIGHT_PRESETS.vivid.sky
	check(sk == [0.5, 0.15], "vivid 하늘 %s" % [sk])
	for id in C.WORLD_THEMES:
		var dim: Vector3 = GL._dimv(G3._lin3(TT.theme(id).sky.horizon), sk[0], sk[1], 1.0)
		check(TT.lin_luma(dim) >= TT.SKY_DIM_LUMA_MIN, "%s: 낮춘 지평선 밝기 %.3f ≥ %.3f" % [id, TT.lin_luma(dim), TT.SKY_DIM_LUMA_MIN])
	for id in ["volcano", "crystal"]:
		var old: Vector3 = GL._dimv(G3._lin3(C.WORLD_THEMES[id].sky.horizon), sk[0], sk[1], 1.0)
		check(TT.lin_luma(old) < TT.SKY_DIM_LUMA_MIN, "%s: 예전 값은 하한 아래 (%.3f)" % [id, TT.lin_luma(old)])
	for id in TT.TUNE: # 밝힌 색: 성분마다 원래 이상·밤 순서 (꼭대기 < 중간 < 지평선) 그대로
		var b: Dictionary = C.WORLD_THEMES[id].sky
		var t: Dictionary = TT.theme(id).sky
		for s in ["top", "mid", "horizon", "below"]:
			var bv := G3._lin3(b[s])
			var tv := G3._lin3(t[s])
			check(tv.x >= bv.x and tv.y >= bv.y and tv.z >= bv.z, "%s.sky.%s: 원래보다 어둡지 않음" % [id, s])
		check(TT.luma(t.top) < TT.luma(t.mid) and TT.luma(t.mid) < TT.luma(t.horizon), "%s: 꼭대기 < 중간 < 지평선" % id)
		check(TT.theme(id).hemi[2] > C.WORLD_THEMES[id].hemi[2] and TT.theme(id).sunIntensity > C.WORLD_THEMES[id].sunIntensity, "%s: 하늘빛·해 세기 ↑" % id)
	# 그래픽 낮춤 (판 빛 꺼짐): 밝힌 하늘만 SKY_LOW_DIM 배로 그려 넣음, 나머지 테마·보통 화질은 표 값 그대로
	check(TT.sky_low_dim("volcano", true) == TT.SKY_LOW_DIM and TT.sky_low_dim("volcano", false) == 1.0 and TT.sky_low_dim("meadow", true) == 1.0 and TT.sky_low_dim(null, true) == 1.0, "낮춤 하늘 배율")
	check(TT.SKY_LOW_DIM > 0.5 and TT.SKY_LOW_DIM < 1.0, "낮춤 배율은 판 빛 (0.5) 과 1 사이")
	var keep := _globals_keep()
	var world := Node3D.new()
	G3.apply_theme(world, "volcano", false)
	var m: ShaderMaterial = world.get_node("G3Env/Sky").material_override
	check((m.get_shader_parameter("horizon") as Vector3).is_equal_approx(G3._lin3(TT.TUNE.volcano.sky.horizon)), "보통: 하늘 구에 덮어쓴 지평선 색")
	check(is_equal_approx(G3.global_value("g3_hemi_energy"), TT.TUNE.volcano.hemi[2]), "하늘빛 세기도 덮어쓴 값")
	check((G3.global_value("g3_fog_color") as Vector3).is_equal_approx(G3._lin3(TT.TUNE.volcano.fog[0])), "안개 색도")
	G3.apply_theme(world, "volcano", true)
	check((m.get_shader_parameter("horizon") as Vector3).is_equal_approx(G3._lin3(TT.TUNE.volcano.sky.horizon) * TT.SKY_LOW_DIM), "낮춤: 지평선 × SKY_LOW_DIM")
	check((m.get_shader_parameter("top") as Vector3).is_equal_approx(G3._lin3(TT.TUNE.volcano.sky.top) * TT.SKY_LOW_DIM), "낮춤: 꼭대기도")
	G3.apply_theme(world, "meadow", true)
	check((m.get_shader_parameter("horizon") as Vector3).is_equal_approx(G3._lin3(C.WORLD_THEMES.meadow.sky.horizon)), "밝은 테마는 낮춤이어도 원래 색")
	check(is_equal_approx(G3.global_value("g3_hemi_energy"), C.WORLD_THEMES.meadow.hemi[2]), "밝은 테마 하늘빛 그대로")
	world.free()
	_globals_back(keep)


# 절벽 (섬 몸통 층 색) 7테마: sRGB 밝기 하한 위, 층 순서·구분 그대로, 밝은 테마는 원래 색
func test_c6_cliff_luma_floor() -> void:
	for id in C.WORLD_THEMES:
		var base: Array = C.WORLD_THEMES[id].cliff
		var got: Array = TT.theme(id).cliff
		check(got.size() == base.size() and got.size() == 5, "%s: 층 5개" % id)
		var dark := false
		for i in got.size():
			check(TT.luma(got[i]) >= TT.CLIFF_LUMA_MIN, "%s: 층 %d 밝기 %.3f ≥ %.2f" % [id, i, TT.luma(got[i]), TT.CLIFF_LUMA_MIN])
			check(int(got[i]) >= 0 and int(got[i]) <= 0xffffff and got[i] is float, "%s: 층 %d 색 값" % [id, i])
			dark = dark or TT.luma(base[i]) < TT.CLIFF_LUMA_MIN
		if not dark:
			check(got == base, "%s: 하한 위면 원래 색 그대로" % id)
			continue
		for i in range(1, got.size()):
			var db := TT.luma(base[i]) - TT.luma(base[i - 1])
			var dg := TT.luma(got[i]) - TT.luma(got[i - 1])
			check(signf(db) == signf(dg) and absf(dg) >= absf(db), "%s: 층 %d·%d 밝기 순서·차 (%.3f → %.3f)" % [id, i - 1, i, db, dg])
	check(["volcano", "crystal", "mushroom"].all(func(id): return TT.theme(id).cliff != C.WORLD_THEMES[id].cliff), "어두운 세 테마는 밝혀짐")
	var one := TT.cliff_floor([0x000000, 0x101010], 0.22)
	check(TT.luma(one[0]) >= 0.22 and TT.luma(one[1]) > TT.luma(one[0]), "검정도 하한 위 회색으로 %s" % [one])
	var keep_arr := [0x808080, 0x909090]
	check(is_same(TT.cliff_floor(keep_arr, 0.22), keep_arr), "하한 위면 받은 배열 그대로")
	check(TT.cliff_floor([0x0000ff, 0x000010], 0.9).all(func(c): return int(c) <= 0xffffff), "성분은 255 를 안 넘음")


# 하늘 띠: 보통 화질이면 band_k > 0 (밤 테마는 glow 섞기), 그래픽 낮춤이면 0 — apply_theme 도 set_low 도
# c6 리뷰 F4: 하늘 성 (spiral) 은 지평선·중간 색이 부드럽게 이어져 기본 띠가 바탕 기울기에 묻힘 → 그 테마만 띠 색 대비를 키움 (SKY_BAND_THEME). 나머지 테마는 기본값 그대로
static func _band_contrast(id) -> float:
	# 윗단 끝 (바탕이 거의 중간 색인 높이) 에서 띠 색과 바탕 색의 sRGB 거리 = 세기 × (1 - mix) × |지평선 - 중간|
	var sky: Dictionary = TT.theme(id).sky
	var b: Dictionary = TT.sky_band(id, false)
	var h := Color.hex((int(sky.horizon) << 8) | 0xff)
	var m := Color.hex((int(sky.mid) << 8) | 0xff)
	return float(b.band_k) * (1.0 - float(b.band_mix)) * Vector3(h.r - m.r, h.g - m.g, h.b - m.b).length()


func test_c6_sky_band_theme_contrast() -> void:
	check(G3.SKY.code.contains("uniform float band_mix = %s;" % TT.SKY_BAND_MIX) and G3.SKY.code.contains("uniform float band_lift = %s;" % TT.SKY_BAND_LIFT), "셰이더 기본값 = 기본 상수 (안 넣어도 예전 띠 색)")
	check(G3.SKY.code.contains("mix(horizon, mid, band_mix)") and G3.SKY.code.contains("(1.0 + band_lift)"), "띠 색이 uniform 을 씀")
	for id in TT.SKY_BAND_THEME:
		check(C.WORLD_THEMES.has(id), "%s: 있는 테마" % id)
		var o: Dictionary = TT.SKY_BAND_THEME[id]
		for k in o:
			check(["k", "mix", "lift"].has(k), "%s: 띠 값 키 %s" % [id, k])
		check(float(o.get("k", TT.SKY_BAND_K)) > 0.0 and float(o.get("k", TT.SKY_BAND_K)) <= 1.0 and float(o.get("mix", TT.SKY_BAND_MIX)) >= 0.0 and float(o.get("mix", TT.SKY_BAND_MIX)) <= 1.0 and float(o.get("lift", TT.SKY_BAND_LIFT)) >= 0.0 and float(o.get("lift", TT.SKY_BAND_LIFT)) <= 0.5, "%s: 띠 값 범위 %s" % [id, o])
	check(TT.SKY_BAND_THEME.has("skycastle"), "하늘 성 띠 값이 있음")
	var sc: Dictionary = TT.sky_band("skycastle", false)
	check(is_equal_approx(sc.band_k, TT.SKY_BAND_THEME.skycastle.k) and is_equal_approx(sc.band_mix, TT.SKY_BAND_THEME.skycastle.mix) and is_equal_approx(sc.band_lift, TT.SKY_BAND_THEME.skycastle.lift) and sc.band_glow == 0.0, "하늘 성: 표 값 %s" % sc)
	var sl: Dictionary = TT.sky_band("skycastle", true)
	check(sl.band_k == 0.0 and sl.band_glow == 0.0, "하늘 성도 낮춤이면 띠 없음")
	var others := 0.0
	for id in C.WORLD_THEMES:
		if TT.SKY_BAND_THEME.has(id):
			continue
		var b: Dictionary = TT.sky_band(id, false)
		check(b.band_k == TT.SKY_BAND_K and b.band_mix == TT.SKY_BAND_MIX and b.band_lift == TT.SKY_BAND_LIFT, "%s: 띠 값 기본 그대로 (다른 테마는 안 바뀜)" % id)
		others = maxf(others, _band_contrast(id))
	check(C.WORLD_THEMES.size() - TT.SKY_BAND_THEME.size() == 6, "나머지 여섯 테마")
	var was: float = TT.SKY_BAND_K * (1.0 - TT.SKY_BAND_MIX) * _band_contrast("skycastle") / (float(sc.band_k) * (1.0 - float(sc.band_mix)))
	check(was < 0.1 and _band_contrast("skycastle") > others, "하늘 성 띠 대비 %.3f (예전 %.3f — 일곱 테마 중 가장 낮았음) > 다른 테마 최대 %.3f" % [_band_contrast("skycastle"), was, others])
	# 판에 실제로 들어감 + 낮춤이면 꺼짐
	var keep := _globals_keep()
	var world := Node3D.new()
	G3.apply_theme(world, "skycastle", false)
	var m: ShaderMaterial = world.get_node("G3Env/Sky").material_override
	check(is_equal_approx(m.get_shader_parameter("band_k"), sc.band_k) and is_equal_approx(m.get_shader_parameter("band_mix"), sc.band_mix) and is_equal_approx(m.get_shader_parameter("band_lift"), sc.band_lift), "하늘 성 하늘 재질에 띠 값")
	G3.set_low(world, true)
	check(m.get_shader_parameter("band_k") == 0.0, "set_low 켬: 하늘 성 띠 끔")
	G3.set_low(world, false)
	check(is_equal_approx(m.get_shader_parameter("band_k"), sc.band_k), "set_low 끔: 하늘 성 띠 다시")
	G3.apply_theme(world, "meadow", false)
	check(is_equal_approx(m.get_shader_parameter("band_mix"), TT.SKY_BAND_MIX) and is_equal_approx(m.get_shader_parameter("band_lift"), TT.SKY_BAND_LIFT) and is_equal_approx(m.get_shader_parameter("band_k"), TT.SKY_BAND_K), "다른 테마로 바꾸면 띠 값이 기본으로 돌아옴")
	world.free()
	_globals_back(keep)


func test_c6_sky_band_low_off() -> void:
	var tone := {"band_mix": TT.SKY_BAND_MIX, "band_lift": TT.SKY_BAND_LIFT} # 색 대비 기본 (c6 리뷰 F4 — 테마마다 덮을 수 있음)
	check(TT.sky_band("meadow", true) == {"band_k": 0.0, "band_glow": 0.0}.merged(tone) and TT.sky_band("volcano", true) == {"band_k": 0.0, "band_glow": 0.0}.merged(tone), "낮춤이면 띠 없음")
	check(TT.sky_band("meadow", false) == {"band_k": TT.SKY_BAND_K, "band_glow": 0.0}.merged(tone), "낮 테마: 띠만")
	check(TT.sky_band("volcano", false) == {"band_k": TT.SKY_BAND_K, "band_glow": TT.SKY_BAND_GLOW}.merged(tone), "밤 테마 (sky.glow 있음): glow 섞기")
	check(TT.sky_band(null, false) == {"band_k": TT.SKY_BAND_K, "band_glow": 0.0}.merged(tone), "예전 노을: 띠만")
	check(TT.SKY_BAND_K > 0.0 and TT.SKY_BAND_K <= 1.0 and TT.SKY_BAND_GLOW >= 0.0 and TT.SKY_BAND_GLOW <= 1.0, "띠 값 범위")
	var names := []
	for u in G3.SKY.get_shader_uniform_list():
		names.append(u.name)
	for u in ["top", "mid", "horizon", "below", "sun_dir", "glow", "disc", "disc_size", "stars", "band_k", "band_glow", "band_mix", "band_lift"]:
		check(names.has(u), "하늘 셰이더 uniform %s (예전 이름 그대로 + 띠 넷)" % u)
	check(not G3.SKY.code.contains("sampler2D"), "띠는 텍스처 없이")
	var keep := _globals_keep()
	var world := Node3D.new()
	G3.apply_theme(world, "crystal", false)
	var m: ShaderMaterial = world.get_node("G3Env/Sky").material_override
	check(is_equal_approx(m.get_shader_parameter("band_k"), TT.SKY_BAND_K) and is_equal_approx(m.get_shader_parameter("band_glow"), TT.SKY_BAND_GLOW), "보통: 띠 켬")
	G3.set_low(world, true)
	check(m.get_shader_parameter("band_k") == 0.0 and m.get_shader_parameter("band_glow") == 0.0, "set_low 켬: 띠 끔")
	G3.set_low(world, false)
	check(is_equal_approx(m.get_shader_parameter("band_k"), TT.SKY_BAND_K) and is_equal_approx(m.get_shader_parameter("band_glow"), TT.SKY_BAND_GLOW), "set_low 끔: 띠 다시 (그 테마 값)")
	G3.apply_theme(world, "crystal", true)
	check(m.get_shader_parameter("band_k") == 0.0, "낮춤으로 테마 적용: 띠 끔")
	G3.apply_theme(world, "meadow", false)
	check(is_equal_approx(m.get_shader_parameter("band_k"), TT.SKY_BAND_K) and m.get_shader_parameter("band_glow") == 0.0, "낮 테마: glow 섞기 없음")
	G3.apply_theme(world, null, false)
	check(is_equal_approx(m.get_shader_parameter("band_k"), TT.SKY_BAND_K), "예전 노을에도 띠")
	var bare := Node3D.new() # 테마를 안 깐 판에 set_low: 하늘 노드가 없어도 조용히
	G3.set_low(bare, true)
	G3.set_low(bare, false)
	check(bare.get_node_or_null("G3Env") == null, "set_low 가 하늘 노드를 만들지 않음")
	bare.free()
	world.free()
	_globals_back(keep)
