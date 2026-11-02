# 화면 또렷함 (W3, 2026-11-02 재혁 '고도판이 블러 느낌·표면 뭉개짐'): JS 렌더 설정과 같은 값인지
# render.js WebGLRenderer({ antialias: true }) · textures.js·bblocks.js anisotropy 4 + 밉맵 · figure.js plaidTexture (repeat·magFilter Nearest) · OutlineEffect calculateOutline (같음 확인)
extends RefCounted

const C := preload("res://core/config.gd")
const G3 := preload("res://shaders/g3.gd")
const WC := preload("res://world/world_config.gd")
const KC := preload("res://chars/chars_config.gd")
const Body := preload("res://chars/body.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_msaa_like_js_antialias() -> void:
	check(WC.MSAA_3D == Viewport.MSAA_4X, "판 화면 4× 다중 샘플 (JS antialias)")
	check(KC.VM_MSAA == Viewport.MSAA_4X, "1인칭 팔 SubViewport 도 4×")
	check(WC.MSAA_LOW == Viewport.MSAA_DISABLED, "그래픽 낮춤이면 끔")
	var W := preload("res://world/world.gd")
	check(W.msaa_for(false) == Viewport.MSAA_4X and W.msaa_for(true) == Viewport.MSAA_DISABLED, "World.msaa_for: 보통 4×, 낮춤 끔")
	check(_src("res://world/world.gd").contains("set_msaa(View.settings.lowGfx)"), "그래픽 낮춤을 바꾸면 곧바로")


func test_piece_textures_mipmapped_anisotropic() -> void:
	for s in ["toy", "wood", "sandstone", "gem", "obsidian", "marble", "jelly", "stone"]:
		var t: Texture2D = load("res://assets/pieces/%s.png" % s)
		check(t != null and t.get_image().has_mipmaps(), "칸 면 그림 밉맵 %s (three CanvasTexture 기본)" % s)
	check(_src("res://shaders/piece_common.gdshaderinc").contains("face_tex : source_color, filter_linear_mipmap_anisotropic"), "칸 면 그림 이방성 (textures.js anisotropy 4)")
	check(_src("res://world/bblock.gdshader").contains("albedo_tex : source_color, filter_linear_mipmap_anisotropic"), "건축가 블록 판자 이방성 (bblocks.js anisotropy 4)")
	check(int(ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level", 2)) == 2, "고도 이방성 단계 2 = 4× (JS anisotropy 4)")


func test_plaid_repeat_and_nearest() -> void:
	var opts := {}
	Body._plaid_opts(opts, [["#ffffff", 1.0, 0, 0, 32, 32], ["#ff0000", 0.55, 0, 10, 32, 6]])
	check(opts.map_repeat == C.FIGURE_PLAID_REPEAT, "체크 무늬 반복 = FIGURE_PLAID_REPEAT (figure.js tex.repeat)")
	check(opts.map_nearest == true, "체크 무늬 확대는 가장 가까운 칸 (figure.js magFilter Nearest)")
	check((opts.map as ImageTexture).get_image().has_mipmaps(), "체크 무늬 밉맵 (작게 볼 땐 three 처럼 부드럽게)")
	var m := G3.toon_material(Color.WHITE, opts)
	check(m.get_shader_parameter("uv_scale") == Vector2.ONE * C.FIGURE_PLAID_REPEAT, "재질 uv_scale")
	check(m.get_shader_parameter("tex_nearest_mag") == true, "재질 tex_nearest_mag")
	var plain := G3.toon_material(Color.WHITE)
	check(plain.get_shader_parameter("tex_nearest_mag") != true, "그림 없는 재질은 그대로")


func test_outline_like_three() -> void:
	# three OutlineEffect calculateOutline: vec4 norm = normalize(pos - pos2); pos + norm * thickness * pos.w (w 까지 vec4 그대로) — 고도도 같음
	var s := _src("res://shaders/outline.gdshader")
	check(s.contains("vec4 n = normalize(pos - pos2);") and s.contains("POSITION = pos + n * thickness * pos.w;"), "외곽선 = three calculateOutline (vec4 정규화)")


func test_game_light_grade_is_css_filter() -> void:
	# JS game-light.js: 캔버스 CSS filter saturate(1.28) contrast(1.1) brightness(1.02) (vivid). 정답 = CSS 행렬을 sRGB 에서 (python 으로 계산)
	var GL := preload("res://shaders/game_light.gd")
	var g: Array = C.GAME_LIGHT_PRESETS["vivid"].grade
	check(g == [1.28, 1.1, 1.02], "vivid grade 값")
	var cases := [[[200, 60, 40], [246, 45, 17]], [[60, 180, 70], [27, 199, 41]], [[40, 70, 200], [22, 65, 251]], [[128, 128, 128], [131, 131, 131]], [[230, 220, 90], [250, 236, 49]]]
	for cs in cases:
		var o: Color = GL.css_grade(Color8(cs[0][0], cs[0][1], cs[0][2]), g)
		var got := [int(round(o.r * 255)), int(round(o.g * 255)), int(round(o.b * 255))]
		check(absi(got[0] - cs[1][0]) <= 1 and absi(got[1] - cs[1][1]) <= 1 and absi(got[2] - cs[1][2]) <= 1, "CSS 색 보정 %s → %s (얻음 %s)" % [cs[0], cs[1], got])
	var t: ImageTexture3D = GL.grade_lut(g, 4)
	check(t.get_width() == 4 and t.get_depth() == 4, "LUT 크기")
	var c0: Color = GL.grade_images(g, 4)[1].get_pixel(2, 3) # 칸 (2,3,1) = 색 ((2.5, 3.5, 1.5) / 4) 의 보정 (반 텍셀 가운데)
	var want: Color = GL.css_grade(Color(2.5 / 4, 3.5 / 4, 1.5 / 4), g)
	check(absf(c0.r - want.r) < 0.01 and absf(c0.g - want.g) < 0.01 and absf(c0.b - want.b) < 0.01, "LUT 칸 = 텍셀 가운데 색의 CSS 보정")
	var gl = GL.new()
	check(gl.preset_name == C.GAME_LIGHT, "기본 프리셋 = config GAME_LIGHT")
	gl.free()


func test_hazard_light_like_three_point_light() -> void:
	# W3: 위험 빛 = hazard.js PointLight(색, 세기, LAVA_LIGHT_RANGE, 1.4) — 고도 OmniLight 대신 툰 셰이더 전역 값 (빛 패스 없이, light() 가 하늘빛을 겹쳐 더하지 않게)
	var inc := _src("res://shaders/hz_light.gdshaderinc")
	check(inc.contains("w * w / max(pow(dist, g3_hz_ld), 0.01)"), "three getDistanceAttenuation (1/max(d^decay,0.01) × 창)")
	for f in ["res://shaders/toon_common.gdshaderinc", "res://world/bblock.gdshader"]:
		check(_src(f).contains("#include \"res://shaders/hz_light.gdshaderinc\""), "위험 빛 include %s" % f)
	for f in ["res://shaders/toon_common.gdshaderinc", "res://shaders/floor.gdshader", "res://shaders/piece_common.gdshaderinc", "res://shaders/terrain.gdshader", "res://world/bblock.gdshader"]:
		check(_src(f).contains("g3_hz_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz"), "위험 빛 받음 %s" % f)
	check(WC.HAZARD_LIGHT_DECAY == 1.4, "감쇠 1.4 (hazard.js)")
	for g in ["g3_hz_lp", "g3_hz_lc", "g3_hz_ld"]:
		check(ProjectSettings.has_setting("shader_globals/" + g), "전역 셰이더 값 %s" % g)
	var src := _src("res://world/hazard_view.gd")
	check(not src.contains("OmniLight3D"), "고도 OmniLight 안 씀")
	var HV := preload("res://world/hazard_view.gd")
	var hv = HV.new()
	hv.G3 = G3
	hv.light_color = Color8(0xff, 0x6a, 0x20)
	hv.set_light(3.0, Vector3(1, 2, 3))
	check(G3.global_value("g3_hz_lp") == Vector4(1, 2, 3, 3.0), "빛 자리·세기 (three 값 그대로)")
	var lc: Vector4 = G3.global_value("g3_hz_lc")
	check(is_equal_approx(lc.w, C.LAVA_LIGHT_RANGE) and is_equal_approx(lc.x, 1.0) and absf(lc.y - Color8(0, 0x6a, 0).srgb_to_linear().g) < 1e-4, "빛 색 선형·거리")
	hv.set_light(0.0, Vector3.ZERO)
	hv.free()


func test_hazard_vignette_and_steps() -> void:
	# W3: 위험 화면 가장자리 경고 (hazard.js overlay·vigK) — 예전엔 값만 세고 그리는 곳이 없었음
	var HV := preload("res://world/hazard_view.gd")
	var hv = HV.new()
	hv.look = {"vignette": 0xff4010}
	hv._draw_vig(0.5, 1.0 / 60.0)
	check(is_equal_approx(hv.vig_k, 0.5 * (1.0 - exp(-6.0 / 60.0))), "vigK 부드럽게 따라감 (1 - e^(-6dt))")
	check(hv.vig.visible, "세기 0.01 넘으면 그림")
	hv._draw_vig(0.0, 0.0, true)
	check(hv.vig_k == 0.0 and not hv.vig.visible, "꺼지면 바로 0 (hazard.js vigK = 0)")
	var sh := _src("res://world/hazard_vignette.gdshader")
	check(sh.contains("vec2(1.25, 1.0)") and sh.contains("smoothstep(0.42, 0.8, length(d))") and sh.contains("* 0.35") and sh.contains("4.0 + k * 6.0"), "경고 모양 = hazard.js overlay")
	# 차오름 단계: 0 아래 (-2 → -1 → 0) 도 단계 (예전 step >= 0 확인은 놓침)
	check(not _src("res://world/hazard_view.gd").contains("elif step >= 0 and") and _src("res://world/hazard_view.gd").contains("elif has_step and s > step:"), "단계 '없음' 은 has_step 으로")
	hv.free()
	# 쌓인 칸 (건축·던진 칸) 재질: 물들임 받고 외곽선 없음 (render.js blockMeshes)
	check(_src("res://world/world.gd").contains("{\"vertex_color\": true, \"hz_tint\": true, \"outline\": false}"), "격자 칸 재질 hz_tint·외곽선 없음")
