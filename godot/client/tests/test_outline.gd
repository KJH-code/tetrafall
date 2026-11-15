# W31 외곽선 거리 (world/outline_far.gd, chars/body.gd set_outline_far, shaders/outline.gdshader far_taper): 먼 몸은 외곽선 껍질을 떼고 가까운 몸·내 몸은 그대로.
extends RefCounted

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
