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


# 핑 칸 색 단계 (index.html #netPing[data-level]): warn 노랑 + 검정 글, bad 빨강 + 흰 글
func test_net_ping_levels() -> void:
	var ok := U.net_look("ok")
	var w := U.net_look("warn")
	var b := U.net_look("bad")
	check(ok.fg == Color("9fabcd") and is_equal_approx(ok.bg.a, 0.6), "보통: 흐린 글 + rgba(8,12,26,.6)")
	check(w.fg == Color("1a1300") and w.bg.r > 0.99 and w.bg.g > 0.8 and w.bg.b < 0.4, "warn 노랑 %s" % w.bg)
	check(b.fg == Color.WHITE and b.bg.r > 0.8 and b.bg.g < 0.2, "bad 빨강 %s" % b.bg)


# 전환 슬래시 시간 곡선 (main.js playWipe: 띠 cubic-bezier(.6,0,.3,1), 페이드 ease-out) — CSS 곡선 값 (브라우저 계산과 같은 식)
func test_wipe_easing_like_js() -> void:
	check(U.cubic_bezier(0.0, 0.6, 0.0, 0.3, 1.0) == 0.0 and U.cubic_bezier(1.0, 0.6, 0.0, 0.3, 1.0) == 1.0, "끝점")
	# 정답: 이분법 60번으로 푼 값 (node, 2026-11-02)
	for kv in [[0.25, 0.08765322155179213], [0.5, 0.6026803188313119], [0.75, 0.941474642813966]]:
		check(absf(U.cubic_bezier(kv[0], 0.6, 0.0, 0.3, 1.0) - kv[1]) < 1e-6, "cubic-bezier(.6,0,.3,1) %s → %s (%s)" % [kv[0], kv[1], U.cubic_bezier(kv[0], 0.6, 0.0, 0.3, 1.0)])
	check(absf(U.cubic_bezier(0.5, 0.0, 0.0, 0.58, 1.0) - 0.6846431874274606) < 1e-6, "ease-out 0.5 (%s)" % U.cubic_bezier(0.5, 0.0, 0.0, 0.58, 1.0))
	var plan: Dictionary = U.wipe_plan("big")
	var band: Dictionary = plan.bands[0]
	check(U.band_x_eased(band, band.delay) == band.frames[0].x and U.band_x_eased(band, band.delay + band.ms) == band.frames[-1].x, "띠 처음·끝 자리는 그대로")
	var mid_t: float = band.delay + band.ms * 0.1
	check(absf(U.band_x_eased(band, mid_t) - U.band_x(band, band.delay + band.ms * U.cubic_bezier(0.1, 0.6, 0.0, 0.3, 1.0))) < 1e-9, "곡선 진행으로 키프레임 보간")
	check(U.fade_alpha(0.0, 300.0) == 0.0 and U.fade_alpha(300.0, 300.0) == 0.0, "페이드 처음·끝 0")


# 화면 스크립트가 다 읽힘 (문법·타입 오류는 화면을 띄워야 보여서 — 2026-11-02 menu.gd 파싱 오류를 스샷에서야 봄)
func test_ui_scripts_load() -> void:
	var n := 0
	for f in DirAccess.get_files_at("res://ui"):
		if not f.ends_with(".gd"):
			continue
		var sc = load("res://ui/" + f)
		check(sc != null and sc.can_instantiate(), "읽기 실패: ui/%s" % f)
		n += 1
	check(n >= 15, "ui 스크립트 %d개" % n)
