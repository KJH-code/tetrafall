# W37 최적화 4차: 프레임 구성 도구 (core/budget.gd) · 1인칭 팔 MSAA 상한 · (뒤 항목들은 아래에 이어 붙임)
extends RefCounted

const WC := preload("res://world/world_config.gd")
const Budget := preload("res://core/budget.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 1인칭 팔 MSAA: 판 값이 4× 이상이면 2× 까지, 그 아래는 판과 같음. 상한을 끄면 (--no-vm-msaa-cap) 판과 같은 값
func test_vm_msaa_cap() -> void:
	var keep := WC.vm_msaa_cap
	WC.vm_msaa_cap = true
	check(WC.vm_msaa(false, false, "high") == Viewport.MSAA_2X, "높음 PC: 판 4× → 팔 2×")
	check(WC.msaa_3d(false, false, "high") != WC.vm_msaa(false, false, "high") or WC.msaa_3d(false, false, "high") == Viewport.MSAA_2X, "판 값은 그대로")
	check(WC.vm_msaa(false, false, "medium") == WC.msaa_3d(false, false, "medium"), "보통: 판과 같음 (이미 2× 이하)")
	check(WC.vm_msaa(true, false, "high") == WC.msaa_3d(true, false, "high"), "그래픽 낮춤: 판과 같음")
	check(WC.vm_msaa(false, true, "high") == WC.msaa_3d(false, true, "high") or WC.msaa_3d(false, true, "high") == Viewport.MSAA_4X, "웹: 4× 면 2×, 아니면 같음")
	WC.vm_msaa_cap = false
	check(WC.vm_msaa(false, false, "high") == WC.msaa_3d(false, false, "high"), "상한 끔: 판과 같은 값")
	WC.vm_msaa_cap = keep


# 프레임 구성 분류: 외부 몸 몸·1인칭 팔·이름표·스크립트 없는 것
func test_budget_categories() -> void:
	var l3 := Label3D.new()
	check(Budget.category_of(l3) == Budget.LABEL_CAT, "Label3D 는 이름표")
	var root := Node3D.new()
	var ext := Node3D.new()
	ext.name = "ext"
	var mi := MeshInstance3D.new()
	root.add_child(ext)
	ext.add_child(mi)
	check(Budget.category_of(mi) == "몸 (외부 몸)", "ext 아래 메시는 외부 몸 몸: %s" % Budget.category_of(mi))
	check(Budget.cpu_category("몸 figureAnim") == "몸 (코드 몸)" or Budget.cpu_category("몸 figureAnim").begins_with("몸"), "CPU 분류: 몸")
	check(Budget.cpu_category("net (스냅샷 받기)") == "통신 (스냅샷 처리)", "CPU 분류: 네트")
	check(Budget.cpu_category("ui (HUD)") == "HUD / 2D", "CPU 분류: HUD")
	check(Budget.cpu_category("zzz") == "기타 (스크립트)", "표에 없는 이름은 기타")
	l3.free()
	root.free()


# 코드 몸 그림자 쌍둥이: 보이는 합친 메시는 그림자를 끄고 껍질 없는 쌍둥이가 같은 메시·스킨·뼈대로 던짐. 두 번 불러도 하나, 끄면 (set_shadow_off) 쌍둥이도 꺼짐·켜면 복원
func test_batch_shadow_twin() -> void:
	var Body := preload("res://chars/body.gd")
	for ch in ["bard", "berserker", "builder", "cannon"]:
		var b = Body.new()
		b.build(ch, Color(0.2, 0.5, 1.0), true)
		b.add_batch_shadow_twin()
		b.add_batch_shadow_twin()
		var twins := b.find_children("batch_sh*", "MeshInstance3D", true, false)
		check(twins.size() == 1, "%s: 쌍둥이 하나 (%d)" % [ch, twins.size()])
		if twins.size() == 1:
			var tw := twins[0] as MeshInstance3D
			var src: MeshInstance3D = b.batch.mi
			check(tw.mesh == src.mesh and tw.skin == src.skin, "%s: 같은 메시·스킨" % ch)
			check(tw.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and tw.material_override == null, "%s: 그림자 전용·재질 없음 (껍질 없음)" % ch)
			check(src.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: 보이는 메시는 그림자 끔" % ch)
			check(tw.get_node(tw.skeleton) == b.batch.skel, "%s: 같은 뼈대" % ch)
			b.set_shadow_off(true)
			check(not tw.visible, "%s: 먼 몸 그림자 끄기가 쌍둥이를 숨김" % ch)
			b.set_shadow_off(false)
			check(tw.visible and src.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: 켜면 복원 (보이는 메시는 그림자 끈 채)" % ch)
		b.free()
	var keep := WC.batch_twin_on
	WC.batch_twin_on = false
	var b2 = Body.new()
	b2.build("bard", Color(0.2, 0.5, 1.0), true)
	b2.add_batch_shadow_twin()
	check(b2.find_children("batch_sh*", "MeshInstance3D", true, false).is_empty(), "--no-batch-twin: 쌍둥이 없음")
	b2.free()
	WC.batch_twin_on = keep


# G3 재질 기록 (_mats·_outlined) 정리: 몸을 만들고 지울 때마다 사라진 재질의 WeakRef·Callable 이 쌓이던 누수. 한계 (512) 를 넘으면 사라진 것만 버려서 길이가 한없이 늘지 않음
func test_g3_material_registry_pruned() -> void:
	var G3 := preload("res://shaders/g3.gd")
	var held := []
	for i in 3000:
		var m = G3.toon_material(Color(0.1, 0.2, 0.3), {"vertex_color": true, "outline": true})
		if i % 50 == 0:
			held.append(m) # 일부는 살아 있어야 함 (정리가 산 재질을 버리면 안 됨)
	check(G3._mats.size() < 1600, "재질 기록이 한없이 안 늘어남 (%d)" % G3._mats.size())
	check(G3._outlined.size() < 1600, "외곽선 기록도 (%d)" % G3._outlined.size())
	var tracked := 0
	for m in held:
		for e in G3._outlined:
			if e[0].get_ref() == m:
				tracked += 1
				break
	check(tracked == held.size(), "정리 뒤에도 산 재질의 외곽선 기록은 그대로 (%d/%d)" % [tracked, held.size()])
	check(not G3._mats_busy, "set_low 밖에서는 정리 가능 상태")
