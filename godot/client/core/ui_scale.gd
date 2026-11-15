# UI 배율 (W9, 재혁 '고도판 UI 가 너무 작다'): 화면 판·글자는 기준 화면 1280×720 (W4 가 JS 와 맞춘 크기) 으로 만들고 창 크기에 맞춰 키움.
# project.godot [display] window/stretch = canvas_items + expand + 1280×720 → 고도가 넣는 기본 배율은 min(창 폭/1280, 창 높이/720).
# 여기서 고른 배율 s 가 되게 Window.content_scale_factor = s / 기본 배율 (apply). 그러면 UI 좌표 (get_visible_rect·get_viewport_rect·마우스 위치·
# unproject_position) = 창 픽셀 / s, 3D 는 창 픽셀 그대로 (canvas_items 는 2D 만 키움). '작은 창' (ui_calc.small) 은 이 UI 좌표로 판단.
# JS 판은 브라우저가 CSS 픽셀로 키움 (화면 배율·브라우저 확대) — 설정 'UI 크기' 의 고정 값이 브라우저 확대 자리.
# 순수 계산 (창 크기·선택 → 배율) 은 static, tests/test_ui_scale.gd 가 고정. 적용은 View (core/view.gd) 가 창 크기가 바뀔 때·설정이 바뀔 때
extends RefCounted

const BASE := Vector2(1280, 720) # UI 기준 화면 (project.godot viewport_width·height)
const SMALL_BASE := Vector2(960, 540) # 작은 창 배치 (ui_calc.small, JS @media max-height 620 · max-width 1100) 를 맞춘 화면
const AUTO_MIN := 0.75
const AUTO_MAX := 2.5
const CHOICES := ["auto", 0.8, 1.0, 1.25, 1.5, 2.0] # 설정 'UI 크기' (View.settings.uiScale)
const MIN_UI := Vector2(720, 405) # 고정 배율이라도 UI 좌표가 이보다 작아지지 않게 (= 960×540 × 0.75 — 설정 창이 화면 밖으로 나가 되돌릴 수 없게 되는 것 막기)
const DPI_BASE := 96.0 # 윈도우 화면 배율 100% 의 DPI


# 자동: 기준 1280×720 이 다 들어가는 가장 큰 배율 = min(창 폭/1280, 창 높이/720) — 16:9 면 창 높이 / 720 (1080 → 1.5, 1440 → 2),
# 16:10·4:3 처럼 높이에 비해 좁으면 폭 기준 (2880×1800 → 2.25, UI 1280×800 — 높이 기준 2.5 면 UI 1152×720 이라 대기실 판이 넘쳐 스크롤).
# 1 보다 작은 창은 1 (작은 창 배치를 W4 가 맞춘 크기 그대로 — 960×540·1024×768 은 예전 모습, JS 와 같음), 960×540 도 안 들어가면 그만큼 줄임.
# 최소 0.75 · 최대 2.5
static func auto_scale(win: Vector2) -> float:
	if win.x <= 0.0 or win.y <= 0.0:
		return 1.0
	var s := minf(win.x / BASE.x, win.y / BASE.y)
	if s < 1.0:
		s = minf(1.0, minf(win.x / SMALL_BASE.x, win.y / SMALL_BASE.y))
	return clampf(s, AUTO_MIN, AUTO_MAX)


# 설정 값 → 배율. k = 화면 배율 (screen_scale: 윈도우 200% · 브라우저 devicePixelRatio 2 → 2).
# 'auto' (또는 모르는 값) 는 논리 크기 (창 픽셀 / k — JS 의 CSS 픽셀) 로 자동 배율을 정해 k 를 곱함 → 웹 DPR 2 의 CSS 960×540 은 JS 처럼 2배 작은 창 배치.
# 숫자는 JS 브라우저 확대처럼 그 값 × k (100% = JS 100%). 최종 0.75~2.5, 고정 배율은 UI 좌표가 MIN_UI 보다 작아지면 그만큼 줄임
static func scale_for(choice, win: Vector2, k := 1.0) -> float:
	k = maxf(1.0, k)
	if not _fixed(choice):
		return clampf(k * auto_scale(win / k), AUTO_MIN, AUTO_MAX)
	var s := float(choice) * k
	if win.x > 0.0 and win.y > 0.0:
		s = minf(s, minf(win.x / MIN_UI.x, win.y / MIN_UI.y))
	return maxf(s, 0.1)


static func _fixed(choice) -> bool:
	return (typeof(choice) == TYPE_FLOAT or typeof(choice) == TYPE_INT) and float(choice) > 0.0


# 설정 값 정리 (저장된 글·모르는 숫자 → 'auto'): CHOICES 중 하나
static func normalize(choice):
	if _fixed(choice):
		for c in CHOICES:
			if typeof(c) != TYPE_STRING and absf(float(c) - float(choice)) < 0.001:
				return c
	return "auto"


# 설정 창 글자 ('자동' · '125%')
static func label(choice) -> String:
	return "자동" if not _fixed(choice) else "%d%%" % roundi(float(choice) * 100.0)


# 고도 canvas_items + expand 가 기준 화면에서 넣는 기본 배율
static func stretch_base(win: Vector2) -> float:
	if win.x <= 0.0 or win.y <= 0.0:
		return 1.0
	return minf(win.x / BASE.x, win.y / BASE.y)


# 배율 s 가 되게 하는 Window.content_scale_factor
static func content_factor(s: float, win: Vector2) -> float:
	return s / stretch_base(win)


# 배율 s 일 때 UI 좌표 크기 (= get_visible_rect().size)
static func ui_size(win: Vector2, s: float) -> Vector2:
	return win / s


# 화면 배율 (윈도우 125%·150%·200% → 1.25·1.5·2). 고도 screen_get_scale 은 윈도우에서 늘 1 (macOS·Wayland·웹만) → 윈도우는 DPI / 96
static func screen_scale(scale: float, dpi: float, windows: bool) -> float:
	var s := scale
	if windows and s <= 1.0 and dpi > 0.0:
		s = dpi / DPI_BASE
	return clampf(s, 1.0, 4.0)


# 처음 창 크기 (PC 창 모드): 1280×720 은 '논리' 크기라 화면 배율만큼 키움 (200% 노트북 → 2560×1440 — 안 그러면 2880×1800 화면에 작은 창).
# 쓸 수 있는 화면 (작업 표시줄·제목 줄 여유 margin 뺌) 을 넘으면 비율 지켜 줄임. 배율 1 이면 그대로
static func startup_window(base: Vector2i, scr_scale: float, usable: Vector2i, margin := Vector2i(0, 64)) -> Vector2i:
	if scr_scale <= 1.0:
		return base
	var want := Vector2(base) * scr_scale
	var room := Vector2(usable - margin)
	if room.x > 0.0 and room.y > 0.0:
		want *= minf(1.0, minf(room.x / want.x, room.y / want.y))
	var out := Vector2i(want.round())
	return Vector2i(maxi(base.x, out.x), maxi(base.y, out.y)) # 화면이 1280×720 보다 작으면 예전 그대로 (고도가 맞춤)


# 창 하나에 적용: 고른 배율이 되게 content_scale_factor 를 넣고 그 배율을 돌려줌 (View.apply_ui_scale). k < 0 이면 그 창 화면의 배율
static func apply(w: Window, choice, k := -1.0) -> float:
	var win := Vector2(w.size)
	if k < 0.0:
		k = screen_scale(DisplayServer.screen_get_scale(w.current_screen), DisplayServer.screen_get_dpi(w.current_screen), OS.has_feature("windows"))
	var s := scale_for(choice, win, k)
	var f := content_factor(s, win)
	if absf(w.content_scale_factor - f) > 1e-4:
		w.content_scale_factor = f
	return s


# 화면 픽셀 크기 (SubViewport 를 선명하게 그릴 크기): UI 좌표 크기 × 최종 배율 (root 창이면 = 창 픽셀)
static func pixel_size(vp: Viewport) -> Vector2i:
	var sc := vp.get_final_transform().get_scale()
	return Vector2i((vp.get_visible_rect().size * sc).round())
