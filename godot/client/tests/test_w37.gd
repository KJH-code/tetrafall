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
