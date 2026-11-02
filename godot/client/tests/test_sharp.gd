# 화면 또렷함 (W3, 2026-11-02 재혁 '고도판이 블러 느낌·표면 뭉개짐'): JS 렌더 설정과 같은 값인지
# render.js WebGLRenderer({ antialias: true }) · textures.js·bblocks.js anisotropy 4 + 밉맵 · figure.js plaidTexture (repeat·magFilter Nearest) · OutlineEffect calculateOutline (같음 확인)
extends RefCounted

const C := preload("res://core/config.gd")
const G3 := preload("res://shaders/g3.gd")
const WC := preload("res://world/world_config.gd")
const KC := preload("res://chars/chars_config.gd")
const Body := preload("res://chars/body.gd")
const HF := preload("res://world/hazard_field.gd")

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
	check(inc.contains("w * w / max(pow(dist, g3_hz_ld), 0.01)"), "three getDistanceAttenuation (1/max(d^decay,0.01) × 창)") # 셰이더 계산식 (헤드리스는 그리지 못해 글자로)
	# 판 재질 셰이더가 다 위험 빛 include 를 가짐 (재질별 hz_light 매개변수 = hz_light.gdshaderinc 에만 있음) + 그 셰이더가 실제로 g3_hz_light 를 부름
	var bb = preload("res://world/bblocks.gd").new()
	var mats := {"toon": G3.toon_material(Color.WHITE), "floor": G3.floor_material("volcano"), "piece": G3.piece_material("volcano", false), "terrain": G3.terrain_material("volcano", false), "bblock": bb.pools.wood.mm.mesh.material}
	for k in mats:
		var names := []
		for u in (mats[k] as ShaderMaterial).shader.get_shader_uniform_list():
			names.append(u.name)
		check(names.has("hz_light"), "위험 빛 include %s" % k)
	bb.free()
	for f in ["res://shaders/toon_common.gdshaderinc", "res://shaders/floor.gdshader", "res://shaders/piece_common.gdshaderinc", "res://shaders/terrain.gdshader", "res://world/bblock.gdshader"]:
		check(_src(f).contains("g3_hz_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz"), "위험 빛 받음 %s" % f) # fragment 안 부름 (글자로)
	check(WC.HAZARD_LIGHT_DECAY == 1.4, "감쇠 1.4 (hazard.js)")
	for g in ["g3_hz_lp", "g3_hz_lc", "g3_hz_ld"]:
		check(ProjectSettings.has_setting("shader_globals/" + g), "전역 셰이더 값 %s" % g)
	var HV := preload("res://world/hazard_view.gd")
	var hv = HV.new()
	hv.set_g3(G3, "volcano", false)
	hv._ready()
	check(hv.find_children("*", "Light3D", true, false).is_empty(), "고도 빛 노드 (OmniLight) 안 씀")
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
	var sh := _src("res://world/hazard_vignette.gdshader") # 셰이더 모양 (헤드리스는 그리지 못해 글자로)
	check(sh.contains("vec2(1.25, 1.0)") and sh.contains("smoothstep(0.42, 0.8, length(d))") and sh.contains("* 0.35") and sh.contains("4.0 + k * 6.0"), "경고 모양 = hazard.js overlay")
	hv.free()
	# 차오름 단계: 0 아래 (-2 → -1 → 0) 도 단계마다 번쩍 (예전 step >= 0 확인은 -2 → -1 → 0 을 놓침)
	for g in [["g3_fog_color", Vector3.ZERO], ["g3_fog_near", 0.0], ["g3_fog_far", 0.0]]: # 테마를 안 깐 테스트 (G3.apply_theme 이 정하는 값)
		if G3.global_value(g[0]) == null:
			G3._set_global(g[0], g[1])
	var w := Node3D.new()
	hv = HV.new()
	hv.set_g3(G3, "volcano", false)
	w.add_child(hv)
	var grid := PackedByteArray()
	grid.resize(10 * 10 * C.GRID_H)
	var st := {"field": {"w": 10, "d": 10, "h": C.GRID_H}, "lava": {"active": true, "z": -1.8}, "players": []}
	var seen := []
	for z in [-1.8, -1.6, -0.8, -0.6, 0.2, 1.2]:
		st.lava.z = z
		hv.pulse = 0.0
		hv.update(st, grid, 1, {}, 0.0)
		seen.append([HF.rise_step(z), hv.pulse == 1.0])
	check(seen.filter(func(a): return a[1]).size() == 4, "차오름 번쩍 = 시작 + 단계 바뀔 때 (0 아래 포함) %s" % [seen])
	check(seen[0][1] and not seen[1][1] and seen[2][1] and not seen[3][1] and seen[4][1] and seen[5][1], "번쩍 자리 %s" % [seen])
	w.free()
	# 쌓인 칸 (건축·던진 칸) 재질: 물들임 받고 외곽선 없음 (render.js blockMeshes)
	var gm: ShaderMaterial = preload("res://world/world.gd").grid_material(G3)
	check(gm.get_shader_parameter("hz_tint") == true and gm.get_shader_parameter("use_vertex_color") == true and gm.next_pass == null, "격자 칸 재질 hz_tint·정점 색·외곽선 없음")


# W3 검수: 판 중에 방을 나가면 (Store.state = {}) World 가 판 갱신을 멈춰 위험 update 가 더 안 불림 → 경고 판 (CanvasLayer 라 Node3D 를 숨겨도 그려짐)·
# 전역 위험 빛 g3_hz_lp·물들임 g3_hz 가 메뉴에 남던 것. World._process 가 방 밖이면 hazard_view.clear()
func test_leave_room_clears_hazard() -> void:
	const W := preload("res://world/world.gd")
	const HV := preload("res://world/hazard_view.gd")
	var w = W.new()
	var hv = HV.new()
	hv.set_g3(G3, "volcano", false)
	w.hazard_view = hv
	w.add_child(hv)
	for n in ["scenery", "grid_view", "pieces_view", "bodies", "sky_aids", "items_view", "ghost_aim", "marks", "light_fx", "shots", "hook_fx", "body_fx"]:
		var dummy := Node3D.new()
		w.set(n, dummy)
		w.add_child(dummy)
	for g in [["g3_fog_color", Vector3.ZERO], ["g3_fog_near", 0.0], ["g3_fog_far", 0.0]]: # 테마를 안 깐 테스트 (G3.apply_theme 이 정하는 값)
		if G3.global_value(g[0]) == null:
			G3._set_global(g[0], g[1])
	# 판 중: 용암이 차올라 내 발 바로 아래 → 경고·빛·물들임 켬
	var fw := 10
	var grid := PackedByteArray()
	grid.resize(fw * fw * C.GRID_H)
	var st := {"phase": "playing", "field": {"w": fw, "d": fw, "h": C.GRID_H}, "lava": {"active": true, "z": 2.0}, "players": [{"id": 1, "alive": true, "x": 5.0, "y": 5.0, "z": 2.3}]}
	for i in 30:
		hv.update(st, grid, 1, st.players[0], 0.1)
	check(hv.vig.visible and hv.vig_k > 0.01, "판 중 가장자리 경고 그림 (vig_k %.3f)" % hv.vig_k)
	check((G3.global_value("g3_hz_lp") as Vector4).w > 0.0, "판 중 위험 빛 세기 > 0")
	check((G3.global_value("g3_hz") as Vector4).w == 1.0, "판 중 물들임 켬")
	# 방을 나감 → World 한 프레임
	var keep_state := Store.state
	Store.state = {}
	w._process(1.0 / 60.0)
	check(not hv.vig.visible and hv.vig_k == 0.0, "나간 뒤 가장자리 경고 안 그림")
	check((G3.global_value("g3_hz_lp") as Vector4).w == 0.0, "나간 뒤 전역 위험 빛 세기 0")
	check((G3.global_value("g3_hz") as Vector4).w == 0.0, "나간 뒤 물들임 끔")
	check(hv.sinks.is_empty() and not hv.has_step and hv.pulse == 0.0, "잠기는 몸·차오름 단계 버림")
	# 메뉴에서 매 프레임 불려도 한 번만 (전역 값을 다시 쓰지 않음), 판에 다시 들어가면 update 가 다시 켬
	G3._set_global("g3_hz_lp", Vector4(0, 0, 0, 7.0))
	w._process(1.0 / 60.0)
	check((G3.global_value("g3_hz_lp") as Vector4).w == 7.0, "clear 는 한 번만")
	hv.update(st, grid, 1, st.players[0], 0.1)
	check((G3.global_value("g3_hz_lp") as Vector4).w > 0.0 and (G3.global_value("g3_hz") as Vector4).w == 1.0, "다시 판이면 켬")
	Store.state = {}
	w._process(1.0 / 60.0)
	check((G3.global_value("g3_hz_lp") as Vector4).w == 0.0, "두 번째로 나가도 끔")
	Store.state = keep_state
	w.sun.free() # _ready 없이 만든 World: 붙이지 않은 해·효과 자리도
	w.fx_root.free()
	w.free()


# W3 검수: 위험 빛은 전역 셰이더 값이라 자기 SubViewport 장면 (1인칭 팔·초상·대기실 큰 캐릭터, own_world_3d) 에도 걸림 — JS viewmodel·portrait 는 따로 된 scene 이라 안 받음.
# → 그 몸들 재질만 hz_light = false (hz_light.gdshaderinc), 판 몸은 그대로 받음
func _shader_mats(root: Node) -> Array:
	var out := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override is ShaderMaterial:
			out.append((mi as MeshInstance3D).material_override)
	return out


func test_own_scene_bodies_skip_hazard_light() -> void:
	const Chars := preload("res://chars/chars.gd")
	const VM := preload("res://chars/viewmodel.gd")
	const Portrait := preload("res://ui/portrait.gd")
	var names := []
	for u in G3.toon_material(Color.WHITE).shader.get_shader_uniform_list():
		names.append(u.name)
	check(names.has("hz_light"), "툰 셰이더에 재질별 hz_light")
	for ch in C.FIGURE_CHARS:
		var col := Color(0.9, 0.4, 0.2)
		var b = Chars.make_body(ch, col) # 판 몸
		var field_mats := _shader_mats(b)
		check(field_mats.size() > 0 and field_mats.all(func(m): return m.get_shader_parameter("hz_light") != false), "%s 판 몸은 위험 빛 받음" % ch)
		# 초상·대기실 큰 캐릭터 (portrait.gd·char_stage.gd 가 같이 씀)
		var s = Portrait.still_body(Chars, ch, col)
		var sm := _shader_mats(s)
		check(sm.size() > 0 and sm.all(func(m): return m.get_shader_parameter("hz_light") == false), "%s 초상 몸 재질 %d개 위험 빛 끔" % [ch, sm.size()])
		check(s.torso_mats.values().all(func(m): return m.get_shader_parameter("hz_light") == false), "%s 초상 바드 폼 몸통도" % ch)
		s.opacity = 0.5
		s._apply_opacity() # 나중에 만드는 반투명 재질도 따름
		check(_shader_mats(s).all(func(m): return m.get_shader_parameter("hz_light") == false), "%s 초상 반투명 재질도" % ch)
		s.free()
		# 1인칭 팔: 복제 몸·소품 (닌자 표창·대포 포탄·광전사 핏줄) 다
		var vm = VM.new()
		vm._ready()
		vm._sync(b)
		var am := _shader_mats(vm.anchor)
		check(am.size() > 0 and am.all(func(m): return m.get_shader_parameter("hz_light") == false), "%s 1인칭 팔 재질 %d개 위험 빛 끔" % [ch, am.size()])
		check(vm.twin.torso_mats.values().all(func(m): return m.get_shader_parameter("hz_light") == false), "%s 1인칭 바드 폼 몸통도" % ch)
		check(_shader_mats(b).all(func(m): return m.get_shader_parameter("hz_light") != false), "%s 1인칭 팔을 만들어도 판 몸은 그대로" % ch)
		vm.twin.free()
		vm.free()
		b.free()
