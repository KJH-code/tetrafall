# W9 UI 배율 (core/ui_scale.gd): 자동 배율 (min(창 폭/1280, 창 높이/720), 그보다 작은 창은 1, 최소 0.75 · 최대 2.5) · 고정 배율 · 기준 좌표 · 화면 배율 (윈도우 DPI) ·
# 처음 창 크기 · 실제 창에 넣은 뒤 UI 좌표 · 설정 창 'UI 크기' 줄 · 초상·큰 캐릭터를 화면 픽셀로 그림 · 마우스 시선은 창 픽셀 (screen_relative)
extends RefCounted

const UiScale := preload("res://core/ui_scale.gd")
const U := preload("res://ui/ui_calc.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _near(a: float, b: float, eps := 0.002) -> bool:
	return absf(a - b) <= eps


# 자동 배율: 완료 기준 창 크기마다 (UI 좌표 = 창 / 배율)
func test_auto_scale_table() -> void:
	var rows := [
		# [창, 배율, UI 좌표, 작은 창]
		[Vector2(960, 540), 1.0, Vector2(960, 540), true], # W4 가 맞춘 작은 창 그대로
		[Vector2(1280, 720), 1.0, Vector2(1280, 720), false], # W4 기준 그대로
		[Vector2(1920, 1080), 1.5, Vector2(1280, 720), false],
		[Vector2(2560, 1440), 2.0, Vector2(1280, 720), false],
		[Vector2(2880, 1800), 2.25, Vector2(1280, 800), false], # 재혁 노트북 16:10 전체 화면 — 폭 기준 (1280 이 다 들어감)
		[Vector2(3840, 2160), 2.5, Vector2(1536, 864), false], # 최대 2.5
		[Vector2(1440, 900), 1.125, Vector2(1280, 800), false], # 16:10
		[Vector2(2560, 1080), 1.5, Vector2(1706.667, 720), false], # 21:9
		[Vector2(1600, 1200), 1.25, Vector2(1280, 960), false], # 4:3
		[Vector2(1024, 768), 1.0, Vector2(1024, 768), true], # 4:3 작은 창 — JS 와 같은 1배 작은 창 배치
		[Vector2(1100, 650), 1.0, Vector2(1100, 650), true], # 1280×720 보다 작은 창은 1
		[Vector2(800, 450), 0.8333, Vector2(960, 540), true], # 960×540 이 들어가게 줄임
		[Vector2(480, 270), 0.75, Vector2(640, 360), true], # 최소 0.75
	]
	for r in rows:
		var s := UiScale.auto_scale(r[0])
		var ui := UiScale.ui_size(r[0], s)
		check(_near(s, r[1], 0.001), "%s 자동 배율 %.4f (기대 %.4f)" % [str(r[0]), s, r[1]])
		check(_near(ui.x, r[2].x, 0.5) and _near(ui.y, r[2].y, 0.5), "%s UI 좌표 %s (기대 %s)" % [str(r[0]), str(ui), str(r[2])])
		check(U.small(ui) == r[3], "%s 작은 창 %s" % [str(r[0]), str(r[3])])
	check(UiScale.auto_scale(Vector2.ZERO) == 1.0, "창 크기 0 이면 1")


# 비율이 달라도 UI 좌표가 기준 1280×720 (1 아래 창은 작은 창 배치 960×540) 보다 작아지지 않음 (가장자리 HUD·대기실 판이 안 잘림) —
# 최소 0.75 에 걸리는 아주 작은 창만 예외. 넓은 창 (16:9 이상) 은 UI 높이 720, 좁은 창 (16:10·4:3) 은 UI 폭 1280
func test_auto_keeps_layout_room() -> void:
	for w in [800, 960, 1024, 1280, 1366, 1440, 1600, 1920, 2560, 2880, 3440, 3840, 5120]:
		for h in [450, 540, 600, 720, 768, 800, 900, 1080, 1200, 1440, 1600, 1800, 2160]:
			var win := Vector2(w, h)
			var s := UiScale.auto_scale(win)
			var ui := UiScale.ui_size(win, s)
			check(s >= UiScale.AUTO_MIN and s <= UiScale.AUTO_MAX, "%s 배율 범위 %.3f" % [str(win), s])
			if s > UiScale.AUTO_MIN:
				var need: Vector2 = UiScale.BASE if s > 1.0 else UiScale.SMALL_BASE
				check(ui.x >= need.x - 0.1 and ui.y >= need.y - 0.1, "%s UI 좌표 %s 가 %s 이상" % [str(win), str(ui), str(need)])
			if s > 1.0 and s < UiScale.AUTO_MAX:
				check(_near(ui.y, 720.0, 0.5) if w * 9 >= h * 16 else _near(ui.x, 1280.0, 0.5), "%s 넓으면 UI 높이 720, 좁으면 폭 1280 (%s)" % [str(win), str(ui)])


# 고정 배율 (설정 'UI 크기' 80~200%): 그대로, 단 UI 좌표가 720×405 아래로 가면 줄임 (설정 창을 다시 열 수 있게)
func test_fixed_scale() -> void:
	check(UiScale.scale_for(1.25, Vector2(1920, 1080)) == 1.25, "125% 그대로")
	check(UiScale.scale_for(0.8, Vector2(1280, 720)) == 0.8, "80% 그대로 (UI 1600×900)")
	check(UiScale.scale_for(2.0, Vector2(2880, 1800)) == 2.0, "200% 노트북 = 1440×900 (JS 브라우저와 같은 CSS 크기)")
	check(_near(UiScale.scale_for(2.0, Vector2(1280, 720)), 1280.0 / 720.0, 0.001), "1280×720 에 200% → UI 720×405 까지만")
	check(_near(UiScale.scale_for("auto", Vector2(1920, 1080)), 1.5), "auto 는 자동")
	check(_near(UiScale.scale_for("이상한 값", Vector2(1920, 1080)), 1.5), "모르는 값도 자동")
	check(UiScale.normalize(1.25) == 1.25 and UiScale.normalize(1) == 1.0 and UiScale.normalize(1.3) == "auto" and UiScale.normalize("auto") == "auto" and UiScale.normalize(null) == "auto", "설정 값 정리")
	check(UiScale.label("auto") == "자동" and UiScale.label(0.8) == "80%" and UiScale.label(1.25) == "125%" and UiScale.label(2.0) == "200%", "글자")
	check(UiScale.CHOICES == ["auto", 0.8, 1.0, 1.25, 1.5, 2.0], "선택지 자동·80·100·125·150·200")


# 화면 배율 k (윈도우 200%·브라우저 DPR 2): 논리 크기 (창 / k = JS CSS 픽셀) 로 자동 배율 × k, 고정은 그 값 × k (JS 브라우저 확대와 같음)
func test_scale_with_screen_scale() -> void:
	var rows := [
		# [창 (물리), k, 자동 배율, UI 좌표]
		[Vector2(2560, 1440), 2.0, 2.0, Vector2(1280, 720)], # 웹 DPR 2 · CSS 1280×720 = JS 와 같음 / 윈도우 200% 처음 창 (startup_window)
		[Vector2(1920, 1080), 2.0, 2.0, Vector2(960, 540)], # 웹 DPR 2 · CSS 960×540 → JS 처럼 2배 작은 창 배치
		[Vector2(2880, 1800), 2.0, 2.25, Vector2(1280, 800)], # 재혁 노트북 200% 전체 화면 (논리 1440×900 → 1.125 × 2)
		[Vector2(3840, 2160), 2.0, 2.5, Vector2(1536, 864)], # 논리 1920×1080 → 1.5 × 2 = 3 → 최대 2.5
		[Vector2(1920, 1080), 1.5, 1.5, Vector2(1280, 720)], # 150% 노트북 전체 화면 (논리 1280×720)
		[Vector2(1824, 1026), 1.5, 1.5, Vector2(1216, 684)], # 150% 노트북 처음 창 (논리 1216×684 → 1 × 1.5) — 글자 1.5배
		[Vector2(1280, 720), 2.0, 1.5, Vector2(853.333, 480)], # 200% 화면의 물리 1280×720 창 = 논리 640×360 → 0.75 × 2
	]
	for r in rows:
		var sc := UiScale.scale_for("auto", r[0], r[1])
		var ui := UiScale.ui_size(r[0], sc)
		check(_near(sc, r[2], 0.001), "%s k=%.1f 자동 %.4f (기대 %.4f)" % [str(r[0]), r[1], sc, r[2]])
		check(_near(ui.x, r[3].x, 0.5) and _near(ui.y, r[3].y, 0.5), "%s k=%.1f UI 좌표 %s (기대 %s)" % [str(r[0]), r[1], str(ui), str(r[3])])
	check(U.small(UiScale.ui_size(Vector2(1920, 1080), UiScale.scale_for("auto", Vector2(1920, 1080), 2.0))), "DPR 2 · CSS 960×540 은 작은 창")
	check(_near(UiScale.scale_for(1.0, Vector2(2880, 1800), 2.0), 2.0) and _near(UiScale.scale_for(1.25, Vector2(2880, 1800), 2.0), 2.5), "고정 100%·125% × 화면 배율 (JS 브라우저 확대)")
	check(_near(UiScale.scale_for("auto", Vector2(1920, 1080), 0.5), 1.5), "k 는 1 아래로 안 감")


# 고도 canvas_items + expand 기본 배율 × content_scale_factor = 고른 배율
func test_content_factor() -> void:
	for win in [Vector2(960, 540), Vector2(1280, 720), Vector2(1920, 1080), Vector2(2880, 1800), Vector2(1024, 768), Vector2(2560, 1080)]:
		for s in [0.75, 1.0, 1.5, 2.5]:
			check(_near(UiScale.stretch_base(win) * UiScale.content_factor(s, win), s, 1e-5), "%s 배율 %.2f" % [str(win), s])
	check(_near(UiScale.stretch_base(Vector2(2880, 1800)), 2.25), "16:10 은 폭 기준 (2880/1280)")


# 화면 배율: 윈도우는 고도 screen_get_scale 이 1 이라 DPI / 96 (150% = 144, 200% = 192), 다른 데는 screen_get_scale
func test_screen_scale() -> void:
	check(UiScale.screen_scale(1.0, 192.0, true) == 2.0, "윈도우 200%")
	check(UiScale.screen_scale(1.0, 144.0, true) == 1.5, "윈도우 150%")
	check(UiScale.screen_scale(1.0, 96.0, true) == 1.0, "윈도우 100%")
	check(UiScale.screen_scale(2.0, 96.0, false) == 2.0, "macOS·웹 = screen_get_scale")
	check(UiScale.screen_scale(1.0, 200.0, false) == 1.0, "리눅스 X11 DPI 는 안 믿음")


# 처음 창 크기: 화면 배율만큼 키우고 쓸 수 있는 화면에 맞춤
func test_startup_window() -> void:
	var base := Vector2i(1280, 720)
	check(UiScale.startup_window(base, 1.0, Vector2i(1920, 1040)) == base, "100% 면 그대로")
	check(UiScale.startup_window(base, 2.0, Vector2i(2880, 1704)) == Vector2i(2560, 1440), "재혁 노트북 200% → 2560×1440 (자동 UI 2배)")
	var w15 := UiScale.startup_window(base, 1.5, Vector2i(1920, 1032)) # 1920×1080 150%, 작업 표시줄 48
	check(w15.y <= 1032 - 64 and absf(float(w15.x) / w15.y - 16.0 / 9.0) < 0.01 and w15.y > 900, "150%% 노트북은 화면 안에서 비율 지켜 (%s)" % str(w15))
	check(UiScale.scale_for("auto", Vector2(w15), 1.5) >= 1.5, "그 창의 자동 UI 배율 %.2f (글자가 작지 않게)" % UiScale.scale_for("auto", Vector2(w15), 1.5))
	check(UiScale.startup_window(base, 2.0, Vector2i(1200, 700)) == base, "화면이 작으면 예전 그대로")


# 실제 창에 넣기: 2880×1800 크기 창 → UI 좌표 1280×800 (자동), 고정 200% → 1440×900
func test_apply_to_window() -> void:
	var w := Window.new()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(1280, 720)
	w.size = Vector2i(2880, 1800)
	check(_near(UiScale.apply(w, "auto", 1.0), 2.25) and _near(w.content_scale_factor, 1.0, 1e-4), "자동 2.25 = 고도 expand 기본 그대로 (factor %.4f)" % w.content_scale_factor)
	check(_near(UiScale.apply(w, 2.0, 1.0), 2.0) and _near(w.content_scale_factor, 2.0 / 2.25, 1e-4), "고정 200%")
	w.size = Vector2i(960, 540)
	check(_near(UiScale.apply(w, "auto", 1.0), 1.0) and _near(w.content_scale_factor, 1.0 / 0.75, 1e-4), "960×540 자동 1 (factor %.4f)" % w.content_scale_factor)
	w.free()
	var ps = ProjectSettings
	check(str(ps.get_setting("display/window/stretch/mode")) == "canvas_items" and str(ps.get_setting("display/window/stretch/aspect")) == "expand", "project.godot: canvas_items + expand")
	check(int(ps.get_setting("display/window/size/viewport_width")) == 1280 and int(ps.get_setting("display/window/size/viewport_height")) == 720 and bool(ps.get_setting("display/window/dpi/allow_hidpi")), "기준 1280×720 · hidpi")


# 설정 창 'UI 크기': 자동·80~200% 칸, 고른 칸만 주 버튼 모양, 기본값이 자동으로 되돌림
func test_settings_row() -> void:
	var keep = View.settings.get("uiScale", "auto")
	var s = load("res://ui/settings.gd").new()
	s._ready()
	check(s.scale_btns.keys() == ["자동", "80%", "100%", "125%", "150%", "200%"], "칸 %s" % str(s.scale_btns.keys()))
	View.settings.uiScale = 1.25 # (set_setting 은 설정 파일을 씀 → 값만)
	s._show_scale()
	check(s.scale_btns["125%"].get_meta("kind") == "go" and s.scale_btns["자동"].get_meta("kind") == "ghost", "고른 칸 = 주 버튼")
	View.settings.uiScale = "auto"
	s._show_scale()
	check(s.scale_btns["자동"].get_meta("kind") == "go" and s.scale_btns["125%"].get_meta("kind") == "ghost", "자동으로 바꾸면 그 칸")
	check(_src("res://ui/settings.gd").contains("[\"uiScale\", \"auto\"]"), "기본값 = 자동")
	check(s.KEYS_ROOM == 510.0 and s.KEYS_MIN == 60.0, "키 목록 높이에서 UI 크기 줄 만큼 더 뺌 (960×540 에서 설정 창 높이 예전 그대로)")
	s.keys_scroll.custom_minimum_size.y = s.KEYS_MIN
	var h_small: float = s.box.get_combined_minimum_size().y
	check(h_small <= 470.0, "작은 창 설정 창 최소 높이 %.0f (예전 468 — 키 목록 90 일 때)" % h_small)
	View.settings.uiScale = keep
	s.free()
	check(_src("res://core/view.gd").contains("\"uiScale\": \"auto\""), "View 기본 설정 uiScale = auto (user://settings.json 에 저장·복원)")


# 마우스 시선·이모트 바퀴: 창 픽셀 (relative 는 UI 배율로 나뉘어 창 크기마다 감도가 바뀜)
func test_mouse_uses_screen_relative() -> void:
	var src := _src("res://core/player_input.gd")
	check(src.contains("e.screen_relative.x * C.MOUSE_SENSITIVITY") and src.contains("wheel += e.screen_relative") and not src.contains("e.relative"), "screen_relative")


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)
