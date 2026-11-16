# W31 외곽선 거리 (world/outline_far.gd, chars/body.gd set_outline_far, shaders/outline.gdshader far_taper): 먼 몸은 외곽선 껍질을 떼고 가까운 몸·내 몸은 그대로.
extends RefCounted

const C := preload("res://core/config.gd")
const WC := preload("res://world/world_config.gd")
const OF := preload("res://world/outline_far.gd")
const Body := preload("res://chars/body.gd")
const G3 := preload("res://shaders/g3.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func test_norm_dist_and_thickness() -> void:
	check(absf(OF.norm_dist(10.0, 70.0) - 10.0) < 0.01, "시야각 70° 기준이면 거리 그대로")
	check(OF.norm_dist(10.0, 100.0) > 10.0 and OF.norm_dist(10.0, 50.0) < 10.0, "시야각이 넓으면 같은 거리가 더 멀게 (더 작게 보임), 좁으면 가깝게")
	check(OF.thickness_k(0.0) == 1.0 and OF.thickness_k(WC.OUTLINE_FAR.taper_from) == 1.0, "가까운 몸 (taper_from 안) 굵기 그대로")
	check(absf(OF.thickness_k(WC.OUTLINE_FAR.gone) - WC.OUTLINE_FAR.min_k) < 0.001 and OF.thickness_k(100.0) == WC.OUTLINE_FAR.min_k, "gone 에서 min_k")
	var prev := 2.0
	for i in range(0, 41):
		var k: float = OF.thickness_k(float(i))
		check(k <= prev + 0.0001, "굵기는 거리에 따라 줄기만 함 (%d m)" % i)
		prev = k
	check(WC.OUTLINE_FAR.taper_from <= WC.POSE_LOD.far2 and WC.OUTLINE_FAR.gone > WC.POSE_LOD.far2, "줄기 시작은 몸 자세 LOD 둘째 단 (10m) 안, 떼는 거리는 그 밖")
	check(float(WC.OUTLINE_FAR.min_k) * 1.6 < 0.6, "껍질을 떼는 순간 굵기 (px) 가 0.6 미만 — 눈에 안 띔")


func test_far_state_hysteresis() -> void:
	var gone: float = WC.OUTLINE_FAR.gone
	var h: float = WC.OUTLINE_FAR.hyst
	check(not OF.far_state(5.0, 70.0, false) and not OF.far_state(gone, 70.0, false) and not OF.far_state(gone + h - 0.1, 70.0, false), "가까우면 붙임")
	check(OF.far_state(gone + h + 0.1, 70.0, false), "gone + hyst 넘으면 뗌")
	check(OF.far_state(gone, 70.0, true) and OF.far_state(gone - h + 0.1, 70.0, true), "뗀 몸은 gone − hyst 안으로 와야 다시 붙임")
	check(not OF.far_state(gone - h - 0.1, 70.0, true), "충분히 가까우면 다시 붙임")
	# 경계에서 흔들려도 (거리 ± 0.5) 바뀌지 않음
	var st := false
	var flips := 0
	for i in 200:
		var d: float = gone + sin(i * 0.7) * 0.5
		var ns := OF.far_state(d, 70.0, st)
		if ns != st:
			flips += 1
		st = ns
	check(flips == 0, "경계 근처에서 켰다 껐다 안 함 (%d번)" % flips)
	check(not OF.far_state(500.0, 70.0, true, true), "내 몸은 늘 붙임")
	check(OF.far_state(gone + h + 1.0, 70.0, false) and not OF.far_state(gone + h + 1.0, 140.0, true, true), "시야각도 반영 (같은 거리를 70°와 비교)")


func test_shader_and_globals() -> void:
	var sh := FileAccess.get_file_as_string("res://shaders/outline.gdshader")
	check(sh.contains("g3_outline_far") and sh.contains("far_taper") and sh.contains("0.70021"), "셰이더: 전역 g3_outline_far + far_taper (몸 외곽선만)")
	var pj := FileAccess.get_file_as_string("res://project.godot")
	check(pj.contains("g3_outline_far={"), "project.godot 에 전역 값 선언")
	# 셰이더 식 = outline_far.gd 식 (tan 35° 상수)
	check(absf(OF.TAN35 - 0.70021) < 0.00001, "tan 35° 상수가 셰이더와 같음")


# 진짜 몸 (닌자·새 모델): 외곽선 재질을 모아 먼 거리용 사본으로 바꾸고, 멀면 next_pass 를 떼고, 가까우면 되붙이고, 외곽선 설정이 꺼져 있으면 안 붙임
func test_body_outline_far_switch() -> void:
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build("ninja", Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	var was_on: bool = G3.outline_on
	G3.outline_on = true
	check(b.ext != null, "닌자 붙음")
	b.set_outline_far(false)
	check(b._ol.size() >= 1, "외곽선 재질을 모음 (%d)" % b._ol.size())
	for e in b._ol:
		var np: ShaderMaterial = (e[0] as Material).next_pass as ShaderMaterial
		check(np != null and float(np.get_shader_parameter("far_taper")) == 1.0, "가까울 땐 굵기가 거리로 줄어드는 사본")
		check(e[1] == np, "붙은 것 = 기억해 둔 사본")
	b.set_outline_far(true)
	var all_off := true
	for e in b._ol:
		all_off = all_off and (e[0] as Material).next_pass == null
	check(all_off and b.outline_far(), "멀면 외곽선 껍질을 뗌")
	b.set_outline_far(false)
	var all_on := true
	for e in b._ol:
		all_on = all_on and (e[0] as Material).next_pass == e[1]
	check(all_on and not b.outline_far(), "가까워지면 되붙임")
	# 설정 '외곽선' 꺼짐: 가까워도 안 붙임
	G3.outline_on = false
	b.set_outline_far(true)
	b.set_outline_far(false)
	var none := true
	for e in b._ol:
		none = none and (e[0] as Material).next_pass == null
	check(none, "외곽선 설정이 꺼져 있으면 안 붙임")
	G3.outline_on = true
	b.set_outline_far(false)
	check((b._ol[0][0] as Material).next_pass == b._ol[0][1], "설정을 다시 켜면 다음 부름에 붙음")
	# 두 번째 몸은 재질을 따로 가짐 (나눠 쓰지 않음) — 첫 몸을 떼도 둘째는 그대로
	Body.use_ext = true
	var b2 = Body.new()
	b2.build("ninja", Color(0.9, 0.2, 0.2), true)
	Body.use_ext = was
	b.set_outline_far(true)
	b2.set_outline_far(false)
	check(b2._ol.size() >= 1 and (b2._ol[0][0] as Material).next_pass == b2._ol[0][1] and (b._ol[0][0] as Material).next_pass == null, "몸마다 따로: 하나는 떼고 하나는 붙음")
	G3.outline_on = was_on
	b.free()
	b2.free()


# 예전 몸 (구운·코드 조립, 외부 모델 없음) 도 같은 길로 뗌
func test_old_body_outline_far() -> void:
	var was: bool = Body.use_ext
	Body.use_ext = false
	var on: bool = G3.outline_on
	G3.outline_on = true
	for ch in ["bard", "berserker"]:
		var b = Body.new()
		b.build(ch, Color(0.2, 0.5, 1.0), true)
		b.set_outline_far(false)
		check(b._ol.size() >= 1, "%s: 외곽선 재질을 모음 (%d)" % [ch, b._ol.size()])
		b.set_outline_far(true)
		var off := true
		for e in b._ol:
			off = off and (e[0] as Material).next_pass == null
		check(off, "%s: 멀면 뗌" % ch)
		b.free()
	Body.use_ext = was
	G3.outline_on = on


# c8-u3 가까운 몸 깎기 (toon_common·outline near_cut): 눈앞 몸 화소를 디더로 버림. 셰이더 글 — 유니폼은 공통, 버리기는 툰 공통 fragment (TOON_CUSTOM 밖 = 블록·지형·바닥은 안 깎음),
# 제 빛을 가진 몸 (1인칭 팔·초상)·직교 투영 (해 그림자 지도) 은 뺌. 외곽선은 몸 외곽선 사본 (G3.far_outline) 에만 값, 공용 외곽선·툰 재질 기본은 0
func test_c8_near_cut_shader() -> void:
	var K := preload("res://shaders/g3_config.gd")
	var tc := FileAccess.get_file_as_string("res://shaders/toon_common.gdshaderinc")
	check(tc.contains("uniform vec2 near_cut = vec2(0.0);"), "toon_common: near_cut 유니폼 (기본 0 = 끔)")
	check(tc.contains("near_cut.y > 0.0 && !local_light && PROJECTION_MATRIX[3][3] < 0.5"), "깎는 조건: 켜짐 · 제 빛 가진 몸 아님 (!local_light) · 원근 투영 (PROJECTION_MATRIX[3][3] < 0.5)")
	var a := tc.find("#ifndef TOON_CUSTOM")
	var b := tc.rfind("#endif")
	var d := tc.find("discard;")
	check(a >= 0 and b > a and d > a and d < b and tc.count("discard;") == 1, "버리기 (discard) 는 #ifndef TOON_CUSTOM 안 한 곳뿐 (자리 %d, 구간 %d~%d, %d번)" % [d, a, b, tc.count("discard;")])
	check(tc.find("uniform vec2 near_cut") < a, "유니폼 선언은 공통 (TOON_CUSTOM 밖)")
	check(tc.contains("52.9829189") and tc.contains("0.06711056, 0.00583715"), "디더 = interleaved gradient noise")
	var ol := FileAccess.get_file_as_string("res://shaders/outline.gdshader")
	check(ol.contains("uniform vec2 near_cut = vec2(0.0);") and ol.contains("PROJECTION_MATRIX[3][3] < 0.5") and ol.contains("ALPHA = line_color.a * keep;"), "outline: near_cut 유니폼 + 빠진 화소는 알파 0")
	check(not ol.contains("discard;"), "outline: 화소 버리기 (discard) 는 안 씀 — 소프트웨어 렌더에서 프레임이 느려졌음 (알파 0 으로 같은 결과)")
	check(ol.contains("52.9829189") and ol.contains("0.06711056, 0.00583715"), "outline: 몸과 같은 화소 난수 (같은 화소에서 같이 빠짐)")
	check(ol.contains("uniform float near_shell = 0.0;") and ol.contains("length(VERTEX) - near_shell - near_cut.x"), "outline: 몸 반대편 껍질 (속에서 본 면) 은 몸 두께만큼 가깝게 쳐서 같이 버림")
	# 값: 몸 외곽선 사본에만
	var o: ShaderMaterial = G3.outline_material()
	var f := G3.far_outline(o) as ShaderMaterial
	check(f != o and Vector2(f.get_shader_parameter("near_cut")) == K.NEAR_CUT and float(f.get_shader_parameter("far_taper")) == 1.0, "G3.far_outline 사본: near_cut = NEAR_CUT (%s)" % str(f.get_shader_parameter("near_cut")))
	check(o.get_shader_parameter("near_cut") == null or Vector2(o.get_shader_parameter("near_cut")) == Vector2.ZERO, "원본 외곽선은 0")
	check(float(f.get_shader_parameter("near_shell")) == K.NEAR_CUT_SHELL and o.get_shader_parameter("near_shell") == null, "사본에만 몸 두께 어림 %s" % str(f.get_shader_parameter("near_shell")))
	var so: ShaderMaterial = G3.shared_outline()
	check(so.get_shader_parameter("near_cut") == null or Vector2(so.get_shader_parameter("near_cut")) == Vector2.ZERO, "공용 외곽선 (블록·아이템) 은 0")
	var t: ShaderMaterial = G3.toon_material(Color.WHITE)
	check(t.get_shader_parameter("near_cut") == null or Vector2(t.get_shader_parameter("near_cut")) == Vector2.ZERO, "G3.toon_material 기본은 0 (소품·아이템·장식은 안 깎음)")
	var has := false
	for u in t.shader.get_shader_uniform_list():
		has = has or str(u.get("name", "")) == "near_cut"
	check(has, "툰 셰이더가 near_cut 유니폼을 가짐 (셰이더가 컴파일됨)")


# c8-u3 값: 0 < 다 버림 < 디더 끝 < 0.9 m. 몸 재질 (외부·구운 몸이 지나는 Ext.look) 은 NEAR_CUT, 1인칭 팔 쌍둥이 (style_cfg(cfg, false)) 는 0, cfg 로 바꿀 수 있음
func test_c8_near_cut_values() -> void:
	var K := preload("res://shaders/g3_config.gd")
	check(K.NEAR_CUT.x > 0.0 and K.NEAR_CUT.x < K.NEAR_CUT.y and K.NEAR_CUT.y < 0.9, "0 < %s < %s < 0.9" % [K.NEAR_CUT.x, K.NEAR_CUT.y])
	check(K.NEAR_CUT_SHELL > 0.0 and K.NEAR_CUT.y + K.NEAR_CUT_SHELL < C.PUSH_RANGE, "몸 두께 어림 %s: 외곽선은 %s m 밖에서 그대로 (밀치기 거리 %s 안쪽 값), %s~%s m 는 점점 옅어짐 (몸 면은 그대로), 그 안은 다 빠짐" % [K.NEAR_CUT_SHELL, K.NEAR_CUT.y + K.NEAR_CUT_SHELL, C.PUSH_RANGE, K.NEAR_CUT.x + K.NEAR_CUT_SHELL, K.NEAR_CUT.y + K.NEAR_CUT_SHELL])
	var E = load("res://chars/external.gd").Ext
	var cfg := {"rim_tint": [0.5, 1.0]}
	var m: ShaderMaterial = G3.toon_material(Color.WHITE)
	E.look(m, cfg)
	check(Vector2(m.get_shader_parameter("near_cut")) == K.NEAR_CUT, "Ext.look(cfg) 뒤 NEAR_CUT (%s)" % str(m.get_shader_parameter("near_cut")))
	var m2: ShaderMaterial = G3.toon_material(Color.WHITE)
	E.look(m2, E.style_cfg(cfg, false))
	check(Vector2(m2.get_shader_parameter("near_cut")) == Vector2.ZERO, "1인칭 팔 쌍둥이 (style_cfg(cfg, false)) 는 0 (%s)" % str(m2.get_shader_parameter("near_cut")))
	check(not cfg.has("near_cut") and is_same(E.style_cfg(cfg, true), cfg), "원래 cfg 는 안 바뀜 · 판 몸은 cfg 그대로")
	var m3: ShaderMaterial = G3.toon_material(Color.WHITE)
	E.look(m3, {"near_cut": [0.2, 0.5]})
	check(Vector2(m3.get_shader_parameter("near_cut")).is_equal_approx(Vector2(0.2, 0.5)), "cfg near_cut 으로 바꿀 수 있음")
	var ma: ShaderMaterial = G3.toon_material(Color.WHITE, {"opacity": 0.5})
	E.look(ma, cfg)
	check(Vector2(ma.get_shader_parameter("near_cut")) == K.NEAR_CUT, "반투명 갈래 (유령화·무적) 도 같은 값 — 몸 전체 반투명은 안 건드리고 눈앞 화소만")
	# 구운 몸: baked_look.style → Ext.look 길
	var mb: ShaderMaterial = G3.toon_material(Color.WHITE)
	load("res://chars/baked_look.gd").style(mb, false, "bard")
	check(Vector2(mb.get_shader_parameter("near_cut")) == K.NEAR_CUT, "구운 몸 재질도 NEAR_CUT")
	# 진짜 몸 (닌자·외부 모델): 그려지는 부품 (몸 표면 + 뼈에 붙인 단검) 재질과 그 외곽선 사본이 같은 값 — 몸이 빠진 화소에서 껍질도 빠지고 단검만 떠 있지 않음. 1인칭 쌍둥이는 0
	var was: bool = Body.use_ext
	var was_on: bool = G3.outline_on
	Body.use_ext = true
	G3.outline_on = true
	for third in [true, false]:
		var bd = Body.new()
		bd.build("ninja", Color(0.2, 0.5, 1.0), third)
		bd.set_outline_far(false)
		check(bd.ext != null and bd.ext.parts.size() >= 1, "닌자 %s 부품" % ("판 몸" if third else "1인칭 쌍둥이"))
		var lined := 0
		for pt in bd.ext.parts:
			var bm := (pt.mi as MeshInstance3D).material_override as ShaderMaterial
			var nc = bm.get_shader_parameter("near_cut")
			if third:
				check(nc != null and Vector2(nc) == K.NEAR_CUT, "판 몸 부품 %s near_cut %s" % [pt.mi.name, str(nc)])
				var np := bm.next_pass as ShaderMaterial
				if np != null:
					lined += 1
					check(Vector2(np.get_shader_parameter("near_cut")) == K.NEAR_CUT and float(np.get_shader_parameter("far_taper")) == 1.0, "부품 %s 외곽선 사본도 같은 값" % pt.mi.name)
			else:
				check(nc == null or Vector2(nc) == Vector2.ZERO, "1인칭 쌍둥이 부품 %s 는 0 (%s)" % [pt.mi.name, str(nc)])
		if third:
			check(lined >= 1 and bd.ext.parts.size() >= 3, "판 몸: 몸 표면 + 단검 둘 (%d), 외곽선 가진 부품 %d" % [bd.ext.parts.size(), lined])
		bd.free()
	Body.use_ext = was
	G3.outline_on = was_on


# 몸이 지금 그리는 재질들 (보이는 층의 메시, 반투명이면 깊이 선 안쪽 재질) — c8-fix 테스트 도움. 머리 위 어지러움 별 (몸 조각이 아닌 표시) 은 뺌
func _shown_mats(bd) -> Array:
	var GD = load("res://chars/ghost_depth.gd")
	var out := []
	for mi in bd.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.layers == 0 or g.material_override == null or bd.stars.has(g):
			continue
		out.append([g, GD.inner(g.material_override)])
	return out


# c8-fix F2·F6: 구운 몸 (웹 기본 = 외부 모델 끔, 8명 전부) 의 눈 흰자·눈동자 (빛 안 받는 조각) 도 가까운 몸 깎기를 툰 몸과 같은 값·같은 식·같은 화소 난수로 받음 —
# 예전엔 표준 재질이라 눈앞에서 몸은 점점이 빠지는데 눈알만 불투명하게 떠 있었음. 1인칭 팔 쌍둥이 (구운 조각 몸) 는 툰·눈 재질 모두 0 (예전엔 기본값을 받고 셰이더의 !local_light 로만 막았음)
func test_c8_fix_baked_eyes_near_cut() -> void:
	var K := preload("res://shaders/g3_config.gd")
	var tc := FileAccess.get_file_as_string("res://shaders/toon_common.gdshaderinc")
	var bc := FileAccess.get_file_as_string("res://shaders/basic_common.gdshaderinc")
	for line in ["return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));", "if (near_cut.y > 0.0 && !local_light && PROJECTION_MATRIX[3][3] < 0.5) {",
			"float nk = clamp((length(VERTEX) - near_cut.x) / (near_cut.y - near_cut.x), 0.0, 1.0);", "if (near_ign(FRAGCOORD.xy) >= nk) discard;"]:
		check(tc.contains(line) and bc.contains(line), "눈 셰이더가 툰 몸과 같은 줄을 씀: " + line)
	check(bc.contains("uniform vec2 near_cut = vec2(0.0);") and bc.contains("uniform bool local_light = false;"), "눈 셰이더: 기본은 끔 · 제 빛 가진 몸 표시 (초상·대기실 큰 캐릭터·1인칭 팔은 안 깎음)")
	for f in ["basic.gdshader", "basic_alpha.gdshader"]:
		var src := FileAccess.get_file_as_string("res://shaders/" + f)
		check(src.contains("render_mode unshaded;") and src.contains("#include \"res://shaders/basic_common.gdshaderinc\""), f + ": 빛 안 받음 + 공통 내용")
	var has_ll := false
	for u in G3.BASIC.get_shader_uniform_list():
		has_ll = has_ll or str(u.get("name", "")) == "local_light"
	check(has_ll, "눈 셰이더가 컴파일되고 local_light 유니폼을 가짐 (ui/portrait.gd stage_light 가 이것으로 고름)")
	var m0: ShaderMaterial = G3.basic_material(0x20e0e0)
	check(G3.is_basic(m0) and m0.shader == G3.BASIC and m0.get_shader_parameter("near_cut") == null and Color(m0.get_shader_parameter("albedo")) == Color8(0x20, 0xe0, 0xe0), "G3.basic_material: 불투명 갈래 · 깎기 기본 끔 · 색 그대로")
	check((G3.basic_material(Color(1, 1, 1, 0.5), {"alpha": true}) as ShaderMaterial).shader == G3.BASIC_ALPHA and not G3.is_basic(G3.toon_material(Color.WHITE)) and not G3.is_basic(StandardMaterial3D.new()), "반투명 갈래 · 툰·표준 재질은 아님")
	var was_ext: bool = Body.use_ext
	var was_look: bool = Body.use_look
	Body.use_ext = false
	Body.use_look = true
	for ch in C.FIGURE_CHARS:
		for third in [true, false]:
			var bd = Body.new()
			bd.build(str(ch), Color(0.2, 0.5, 1.0), third)
			var tag := "%s %s" % [ch, "판 몸" if third else "1인칭 쌍둥이"]
			check(bd.baked and bd.ext == null, tag + ": 구운 몸")
			var basic := 0
			var toon := 0
			for e in _shown_mats(bd):
				var sm := e[1] as ShaderMaterial
				check(sm != null, "%s 조각 %s: 셰이더 재질 (표준 재질이면 가까운 몸 깎기를 못 받음)" % [tag, e[0].name])
				if sm == null:
					continue
				var nc = sm.get_shader_parameter("near_cut")
				if G3.is_basic(sm):
					basic += 1
				else:
					toon += 1
				if third:
					check(nc != null and Vector2(nc) == K.NEAR_CUT, "%s 조각 %s (%s): near_cut %s = NEAR_CUT" % [tag, e[0].name, "눈" if G3.is_basic(sm) else "툰", str(nc)])
				else:
					check(nc != null and Vector2(nc) == Vector2.ZERO, "%s 조각 %s: near_cut %s = 0" % [tag, e[0].name, str(nc)])
			if third:
				check(basic >= 2 and toon >= 1, "%s: 눈 조각 %d · 툰 %d" % [tag, basic, toon])
			else:
				check(toon >= 1, "%s: 툰 조각 %d" % [tag, toon])
			for dr in bd.drawn:
				if dr.m.get("kind") == "basic":
					check(G3.is_basic((dr.mi as MeshInstance3D).material_override), "%s: 재질 표의 basic 조각은 G3.basic_material" % tag)
			# 유령화·무적 반투명: 눈이 사라지거나 null 이 되지 않음 — 반투명 갈래 눈 재질 (같은 색·같은 깎기 값) 을 깊이 선으로 감싼 것, 되돌리면 원래 재질
			if third:
				var GD = load("res://chars/ghost_depth.gd")
				bd.opacity = 0.4
				bd._apply_opacity()
				var eyes := 0
				for dr in bd.drawn:
					var mo: Material = (dr.mi as MeshInstance3D).material_override
					check(mo != null and mo != dr.solid, "%s 반투명: 조각 %s 재질이 바뀜" % [tag, dr.mi.name])
					if dr.m.get("kind") != "basic":
						continue
					eyes += 1
					var am := GD.inner(mo) as ShaderMaterial
					check(am != null and am == dr.alpha and am.shader == G3.BASIC_ALPHA and mo != am, "%s 반투명: 눈 = 깊이 선 + 반투명 눈 재질" % tag)
					if am == null:
						continue
					var a: Color = am.get_shader_parameter("albedo")
					var s: Color = (dr.solid as ShaderMaterial).get_shader_parameter("albedo")
					check(is_equal_approx(a.a, 0.4) and is_equal_approx(a.r, s.r) and is_equal_approx(a.g, s.g) and is_equal_approx(a.b, s.b), "%s 반투명: 눈 색 그대로 · 알파 0.4 (%s)" % [tag, a])
					check(Vector2(am.get_shader_parameter("near_cut")) == K.NEAR_CUT, "%s 반투명: 눈도 같은 깎기 값" % tag)
				check(eyes >= 2, "%s 반투명: 눈 조각 %d" % [tag, eyes])
				bd.opacity = 1.0
				bd._apply_opacity()
				for dr in bd.drawn:
					check((dr.mi as MeshInstance3D).material_override == dr.solid, "%s: 되돌리면 원래 재질 (%s)" % [tag, dr.mi.name])
			bd.free()
	# 광전사 분노: 눈 흰자가 충혈 (셰이더 재질의 albedo 가 바뀜)
	var bz = Body.new()
	bz.build("berserker", Color(0.2, 0.5, 1.0), true)
	var em: ShaderMaterial = bz.mats[int(bz.refs.rage.eyeMat.mat)] as ShaderMaterial
	check(G3.is_basic(em), "광전사 눈 흰자 재질")
	if em != null:
		bz.rage_k = 1.0
		bz._face({"dizzy": 0.0}, 0.0)
		var rc: Color = em.get_shader_parameter("albedo")
		check(is_equal_approx(rc.r, 1.0) and is_equal_approx(rc.g, 0.45) and is_equal_approx(rc.b, 0.4), "분노 1 이면 눈 흰자 충혈 (%s)" % rc)
	bz.free()
	# 화풍 끔 (--no-look): 툰 몸이 안 깎이니 눈도 안 깎음 (눈만 빠지지 않게)
	Body.use_look = false
	var bn = Body.new()
	bn.build("bard", Color(0.2, 0.5, 1.0), true)
	for e in _shown_mats(bn):
		var nc = (e[1] as ShaderMaterial).get_shader_parameter("near_cut") if e[1] is ShaderMaterial else null
		check(nc == null or Vector2(nc) == Vector2.ZERO, "--no-look 조각 %s: near_cut %s" % [e[0].name, str(nc)])
	bn.free()
	Body.use_ext = was_ext
	Body.use_look = was_look


class FakeBodies:
	var nodes := {}


# c8-fix F3: 승자 클로즈업·내 이모트 셀카 대상 몸은 가까운 몸 깎기에서 뺌 (카메라가 가슴에서 0.6 m 까지 다가감 = 깎는 거리 안 → 주인공이 방충망 무늬로 빠졌음).
# 대상인 동안 그 몸 재질·외곽선 사본의 near_cut 이 0, 대상이 바뀌거나 끝나면 원래 값. 카메라 동작 (pull_in·VICTORY_PULL) 은 그대로
func test_c8_fix_closeup_uncut() -> void:
	var K := preload("res://shaders/g3_config.gd")
	var CamRig = load("res://world/cam_rig.gd")
	check(WC.VICTORY_PULL == [0.3, 0.6] and float(WC.VICTORY_PULL[1]) < K.NEAR_CUT.y, "클로즈업 카메라는 깎는 거리 안까지 다가감 (값 그대로 %s)" % [WC.VICTORY_PULL])
	var was_ext: bool = Body.use_ext
	var was_look: bool = Body.use_look
	var was_on: bool = G3.outline_on
	Body.use_look = true
	G3.outline_on = true
	var made := []
	for spec in [["ninja", true], ["bard", false]]: # 외부 모델 (부품 + 단검) · 구운 몸 (묶음 + 눈)
		Body.use_ext = spec[1]
		var bd = Body.new()
		bd.build(spec[0], Color(0.2, 0.5, 1.0), true)
		bd.set_outline_far(false)
		made.append(bd)
		var tag := str(spec[0])
		check((bd.ext != null) == spec[1], tag + ": 몸 종류")
		var cut := 0
		var lined := []
		for e in _shown_mats(bd):
			var sm := e[1] as ShaderMaterial
			if sm != null and sm.get_shader_parameter("near_cut") != null and Vector2(sm.get_shader_parameter("near_cut")) == K.NEAR_CUT:
				cut += 1
			if sm != null and sm.next_pass != null:
				lined.append([sm, sm.next_pass])
		check(cut >= 3 and lined.size() >= 1 and not bd.near_cut_off(), "%s: 평소엔 재질 %d개가 NEAR_CUT, 외곽선 %d" % [tag, cut, lined.size()])
		for l in lined:
			check(Vector2((l[1] as ShaderMaterial).get_shader_parameter("near_cut")) == K.NEAR_CUT, tag + ": 평소 외곽선 사본도 NEAR_CUT")
		bd.set_near_cut_off(true)
		check(bd.near_cut_off(), tag + ": 끔")
		for e in _shown_mats(bd):
			var sm := e[1] as ShaderMaterial
			var nc = sm.get_shader_parameter("near_cut") if sm != null else null
			check(nc == null or Vector2(nc) == Vector2.ZERO, "%s 끈 동안 조각 %s near_cut %s = 0" % [tag, e[0].name, str(nc)])
		for l in lined:
			var np := (l[0] as ShaderMaterial).next_pass as ShaderMaterial
			var onc = np.get_shader_parameter("near_cut") if np != null else null
			check(np != null and np != l[1] and (onc == null or Vector2(onc) == Vector2.ZERO) and float(np.get_shader_parameter("far_taper")) == 1.0, "%s 끈 동안 외곽선 = 안 깎는 사본 (선은 남음, 거리 굵기 그대로)" % tag)
			check(Vector2((l[1] as ShaderMaterial).get_shader_parameter("near_cut")) == K.NEAR_CUT, tag + ": 나눠 쓰는 사본 값은 안 바뀜 (다른 몸은 그대로)")
		# 끈 동안 외곽선 거리·설정이 바뀌어도 안 깎는 사본
		bd.set_outline_far(true)
		bd.set_outline_far(false)
		for l in lined:
			check((l[0] as ShaderMaterial).next_pass != l[1] and (l[0] as ShaderMaterial).next_pass != null, tag + ": 멀어졌다 돌아와도 안 깎는 사본")
		# 끈 동안 유령화·무적 (새 반투명 재질) 도 0, 되돌리면 그 재질도 원래 값
		bd.opacity = 0.5
		if bd.ext != null:
			bd.ext.fx(bd.fx_colors({}, 0.0), 0.5)
		bd._apply_opacity()
		bd._nc_sweep()
		var ghosts := 0
		for e in _shown_mats(bd):
			var sm := e[1] as ShaderMaterial
			var nc = sm.get_shader_parameter("near_cut") if sm != null else null
			check(nc == null or Vector2(nc) == Vector2.ZERO, "%s 끈 동안 반투명 조각 %s near_cut %s = 0" % [tag, e[0].name, str(nc)])
			ghosts += 1
		bd.set_near_cut_off(false)
		var back := 0
		for e in _shown_mats(bd):
			var sm := e[1] as ShaderMaterial
			if sm != null and sm.get_shader_parameter("near_cut") != null and Vector2(sm.get_shader_parameter("near_cut")) == K.NEAR_CUT:
				back += 1
		check(ghosts >= 3 and back >= cut, "%s: 되돌리면 반투명 재질도 NEAR_CUT (%d ≥ %d)" % [tag, back, cut])
		bd.opacity = 1.0
		if bd.ext != null:
			bd.ext.fx(bd.fx_colors({}, 0.0), 1.0)
		bd._apply_opacity()
		var again := 0
		for e in _shown_mats(bd):
			var sm := e[1] as ShaderMaterial
			if sm != null and sm.get_shader_parameter("near_cut") != null and Vector2(sm.get_shader_parameter("near_cut")) == K.NEAR_CUT:
				again += 1
		check(again == cut and not bd.near_cut_off(), "%s: 되돌린 뒤 불투명 재질 %d개 NEAR_CUT (처음 %d)" % [tag, again, cut])
		for l in lined:
			check((l[0] as ShaderMaterial).next_pass == l[1], tag + ": 외곽선도 원래 사본")
	# 카메라: 대상이 생기면 끄고, 바뀌면 앞 몸을 되돌리고, 끝나면 다 되돌림
	var keep := [Store.state, Store._players_by_id, Store.my_id, View.victory_stage, View.victory_id]
	var p5 := {"id": 5, "slot": 0, "alive": true, "yaw": 0.0, "x": 3.0, "y": 3.0, "z": 0.0}
	var p6 := {"id": 6, "slot": 1, "alive": true, "yaw": 1.0, "x": 5.0, "y": 5.0, "z": 0.0}
	Store.my_id = 6
	Store._players_by_id = {5: p5, 6: p6}
	Store.state = {"phase": "over", "round": {"n": 1}, "field": {"w": 10, "d": 10}, "players": [p5, p6], "pieces": []}
	var rig = CamRig.new()
	var fb := FakeBodies.new()
	fb.nodes = {5: {"body": made[0]}, 6: {"body": made[1]}}
	rig.bodies = fb
	var shown := {5: Vector3(3, 3, 0), 6: Vector3(5, 5, 0)}
	var solid := func(_x, _y, _z): return false
	View.victory_stage = "lobby"
	View.victory_id = null
	rig.victory_camera(0.016, shown, {"x": 0.0, "y": 0.0, "z": 0.0}, solid)
	check(rig.close_id() == null and not made[0].near_cut_off() and not made[1].near_cut_off(), "대상 없음: 둘 다 그대로")
	View.victory_stage = "closeup"
	View.victory_id = 5
	rig.victory_camera(0.016, shown, {"x": 0.0, "y": 0.0, "z": 0.0}, solid)
	rig.victory_camera(0.016, shown, {"x": 0.0, "y": 0.0, "z": 0.0}, solid)
	check(rig.close_id() == 5 and made[0].near_cut_off() and not made[1].near_cut_off(), "승자 클로즈업: 승자 몸만 끔")
	View.victory_stage = "results"
	p6["emote"] = 2
	rig.victory_camera(0.016, shown, {"x": 0.0, "y": 0.0, "z": 0.0}, solid)
	check(rig.close_id() == 6 and not made[0].near_cut_off() and made[1].near_cut_off(), "대상이 내 이모트 셀카로 바뀜: 앞 몸은 되돌리고 내 몸을 끔")
	p6["emote"] = -1
	rig.victory_camera(0.016, shown, {"x": 0.0, "y": 0.0, "z": 0.0}, solid)
	check(rig.close_id() == null and not made[0].near_cut_off() and not made[1].near_cut_off(), "끝나면 다 되돌림")
	# 몸을 새로 만든 경우 (같은 id, 다른 노드): 새 몸을 끔. 몸 묶음이 없으면 (테스트·상자 몸) 아무것도 안 함
	p6["emote"] = 2
	rig.victory_camera(0.016, shown, {"x": 0.0, "y": 0.0, "z": 0.0}, solid)
	fb.nodes[6] = {"body": made[0]}
	rig.victory_camera(0.016, shown, {"x": 0.0, "y": 0.0, "z": 0.0}, solid)
	check(made[0].near_cut_off() and not made[1].near_cut_off(), "같은 id 의 몸이 바뀌면 새 몸을 끄고 앞 몸은 되돌림")
	rig.victory_camera(0.016, {}, {"x": 0.0, "y": 0.0, "z": 0.0}, solid)
	check(not made[0].near_cut_off(), "대상 자리를 모르면 (아직 안 보임) 되돌림")
	rig.bodies = null
	rig.close_uncut(6)
	check(not made[0].near_cut_off() and not made[1].near_cut_off(), "몸 묶음이 없으면 아무것도 안 함")
	var cam: Camera3D = rig.cam
	rig.free()
	if is_instance_valid(cam) and cam.get_parent() == null:
		cam.free()
	for bd in made:
		bd.free()
	Store.state = keep[0]
	Store._players_by_id = keep[1]
	Store.my_id = keep[2]
	View.victory_stage = keep[3]
	View.victory_id = keep[4]
	Body.use_ext = was_ext
	Body.use_look = was_look
	G3.outline_on = was_on
