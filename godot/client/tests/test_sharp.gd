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
	check(_src("res://world/world.gd").contains("get_viewport().msaa_3d = WC.MSAA_3D"), "World 가 주 화면에 켬")


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

