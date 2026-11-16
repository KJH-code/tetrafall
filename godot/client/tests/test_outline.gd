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
	check(K.NEAR_CUT_SHELL > 0.0 and K.NEAR_CUT.y + K.NEAR_CUT_SHELL < C.PUSH_RANGE, "몸 두께 어림 %s: 외곽선이 빠지기 시작하는 거리 %s m 가 밀치기 거리 %s 안쪽 (싸우는 거리의 몸 외곽선은 그대로)" % [K.NEAR_CUT_SHELL, K.NEAR_CUT.y + K.NEAR_CUT_SHELL, C.PUSH_RANGE])
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
