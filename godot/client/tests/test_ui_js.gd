# W4 화면 숫자가 JS (client/index.html·main.js·render.js) 와 같은지: 2026-11-02 JS 대 고도 대조에서 고친 값
extends RefCounted

const C := preload("res://core/config.gd")
const U := preload("res://ui/ui_calc.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# render.js damageColor: 0% 흰색 → 50% 노랑 → 100% 이상 rgb(255,40,0) (Math.round 반은 위로)
func test_damage_color_matches_js() -> void:
	var want := {0.0: [255, 255, 255], 25.0: [255, 255, 128], 33.0: [255, 255, 87], 50.0: [255, 255, 0], 75.0: [255, 148, 0], 100.0: [255, 40, 0], 180.0: [255, 40, 0]}
	for d in want:
		var got := U.damage_rgb(d)
		check(got == [float(want[d][0]), float(want[d][1]), float(want[d][2])], "피해 %s%% 색 %s / JS %s" % [d, got, want[d]])
	check(U.damage_color(100.0) == Color8(255, 40, 0), "100% 는 빨강 (예전 곡선은 주황)")


# index.html @media (max-height: 620px), (max-width: 1100px)
func test_small_window_rule() -> void:
	check(U.small(Vector2(960, 540)), "960×540 은 작은 창")
	check(not U.small(Vector2(1280, 720)), "1280×720 은 아님")
	check(U.small(Vector2(1100, 800)) and U.small(Vector2(1920, 620)), "경계 (폭 1100·높이 620) 포함")
	check(not U.small(Vector2(1101, 621)), "경계 밖")


# main.js fmt: 초 버림 · 킬 피드 원인 '낙사 (갈고리)' (WEAPON_KO)
func test_time_and_cause_text() -> void:
	check(U.fmt_time(59999.0) == "0:59" and U.fmt_time(60000.0) == "1:00" and U.fmt_time(125400.0) == "2:05", "시간 버림 %s %s %s" % [U.fmt_time(59999.0), U.fmt_time(60000.0), U.fmt_time(125400.0)])
	check(U.cause_text("fall", "hook") == "낙사 (갈고리)", "원인 (무기) %s" % U.cause_text("fall", "hook"))
	check(U.cause_text("crush", null) == "압사" and U.cause_text("lava", "") == "용암", "무기 없으면 원인만")
	check(U.cause_text("fall", "newthing") == "낙사 (newthing)", "모르는 무기는 이름 그대로")
	check(U.WEAPON_KO.size() == 28 and U.WEAPON_KO.amp == "앰프 음파" and U.WEAPON_KO.blockslam == "블록내려찍기", "무기 이름 28개 (main.js WEAPON_KO)")
