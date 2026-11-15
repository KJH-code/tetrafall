# 화면 전환 슬래시 (JS #wipe, main.js playWipe): 기울어진 띠가 화면을 긋고 지나감. 띠 시간표는 ui_calc.wipe_plan (JS shared/wipe.js 그대로).
# short (메뉴↔방·결과→대기실) = 테마 빛 색 줄 + 어두운 본 띠, big (판 시작·결과 등장) = 노랑·주황 줄 + 남색 본 띠. 그래픽 낮춤·움직임 줄이기 = 페이드.
# covered 신호 = 띠가 화면을 다 덮은 순간 (그때 뒤 화면을 바꿈)
extends Control

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const U := preload("res://ui/ui_calc.gd")

signal covered

const SKEW_DEG := 18.0 # CSS skewX(-18deg)
const BAND_W := 210.0 # 띠 폭 (vw)
const TOP := -12.0 # 띠 위·아래 (vh)
const BOTTOM := 112.0

var plan = null
var t0 := 0.0
var fired := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func play(kind, reduced: bool) -> bool:
	plan = U.wipe_plan(kind, reduced)
	if plan == null:
		return false
	t0 = Time.get_ticks_msec()
	fired = false
	visible = true
	queue_redraw()
	return true


func busy() -> bool:
	return plan != null


func _process(_d: float) -> void:
	if plan == null:
		return
	var t := Time.get_ticks_msec() - t0
	if not fired and t >= plan.coverMs:
		fired = true
		covered.emit()
	if t >= plan.ms:
		plan = null
		visible = false
		return
	queue_redraw()


# 띠 색 칸: [시작 %, 끝 %, 색] (CSS linear-gradient 90deg 그대로, 오른쪽 = 앞)
func _segments(i: int, last: bool) -> Array:
	var short: bool = plan.kind == "short"
	var a := S.g() if short else S.ACCENT
	var b := S.g2() if short else S.HOT
	if last:
		var dark := Color("0b0616") if short else S.PANEL2
		var mid := Color("1b1030") if short else S.PANEL
		# JS: dark 2–30% → (그라데이션) mid 70% → (그라데이션) dark 97.6% — 그라데이션 구간은 칸을 잘게 나눠 칠함
		var segs := [[0.0, 0.8, b], [0.8, 2.0, Color.WHITE if short else S.ACCENT], [2.0, 30.0, dark]]
		for j in 8:
			segs.append([30.0 + 5.0 * j, 30.0 + 5.0 * (j + 1), dark.lerp(mid, (j + 0.5) / 8.0)])
		for j in 8:
			segs.append([70.0 + 3.45 * j, 70.0 + 3.45 * (j + 1), mid.lerp(dark, (j + 0.5) / 8.0)])
		segs.append([97.6, 100.0, a])
		return segs
	if i == 0:
		return [[86.0, 97.0, a], [97.0, 100.0, Color.WHITE if short else Color("fff3b0")]]
	return [[91.0, 100.0, b]]


func _draw() -> void:
	if plan == null:
		return
	var vp := get_viewport_rect().size
	var vw := vp.x / 100.0
	var vh := vp.y / 100.0
	var t := Time.get_ticks_msec() - t0
	if plan.fade:
		draw_rect(Rect2(Vector2.ZERO, vp), S.alpha(S.INK, U.fade_alpha(t, plan.ms))) # JS easing ease-out
		return
	var k := tan(deg_to_rad(SKEW_DEG))
	var y0 := TOP * vh
	var y1 := BOTTOM * vh
	var cy := (y0 + y1) / 2.0
	var bands: Array = plan.bands
	for i in bands.size():
		var x0: float = U.band_x_eased(bands[i], t) * vw # JS WAAPI cubic-bezier(.6,0,.3,1) — 예전엔 직선이라 띠가 고른 빠르기로 지나감
		for seg in _segments(i, i == bands.size() - 1):
			var l: float = x0 + seg[0] / 100.0 * BAND_W * vw
			var r: float = x0 + seg[1] / 100.0 * BAND_W * vw
			# skewX(-18deg) 가운데 기준: 위는 오른쪽으로, 아래는 왼쪽으로
			var pts := PackedVector2Array([
				Vector2(l + k * (cy - y0), y0), Vector2(r + k * (cy - y0), y0),
				Vector2(r - k * (y1 - cy), y1), Vector2(l - k * (y1 - cy), y1),
			])
			draw_colored_polygon(pts, seg[2])
