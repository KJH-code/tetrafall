# 번개 예고 '내가 대상' 화면 신호 (c9 리뷰 F2): 기본 1인칭 (고개 각 0·눈높이 1.45·세로 시야 75°) 에서는 내 발밑 예고 고리가 화면 아래 끝보다 더 아래라 안 보임 →
# 내가 예고 고리 안에 있는 동안 (world/bolt_fx_math.gd in_ring — 소리 audio.gd 의 '내 고리' 와 같은 판정) 화면에 따로 알림:
#   · 가운데 아래 (조준점·경직 글자 밑, 아래 사람 판 위) 어두운 판 + 연노랑 테: '번개! 고리 밖으로' + 남은 초 + 줄어드는 막대 (다 줄면 떨어짐). 고리 밖으로 나가면 바로 꺼짐.
#     3인칭·하늘 시점에서는 조준점 위로 (가운데 아래엔 내 몸과 발밑 고리가 있어 덮으면 안 됨 — bolt_fx_math alert_y)
#   · 화면 가장자리 연노랑 테 (ui/screen_edge.gd) 가 깜빡임. 내 자리에 번개가 떨어진 순간엔 테가 한 번 진하게 — 내 자리 번개 띠는 화면 상한 (strike_cap 0) 으로 안 그려져서.
#     화면 가운데·HUD 판은 안 덮음 (화풍 기준서: 화면 번쩍은 가장자리 테만)
# 압사 경고 ('머리 위 블록!' — hud_extra.gd: 위 묶음, 빨강 줄무늬 평행사변형) 와 자리·모양·글이 달라 같은 순간에 둘 다 떠도 갈림.
# 예고는 이벤트로만 옴 (스냅샷에 없음) → 자기 목록을 따로 둠 (world/bolt_fx.gd 와 같은 bolt_fx_math 목록 함수). 시각은 부르는 쪽이 줌 (판 시계 Net.now_ms — 녹화 재연에서도 스냅샷과 같은 빠르기).
# hud_extra.gd 가 만들어 넣고 이벤트·프레임마다 부름. 순수 계산·수치는 bolt_fx_math.gd ALERT (tests/test_round_events.gd test_bolt_alert_*)
extends Control

const M := preload("res://world/bolt_fx_math.gd")
const S := preload("res://ui/ui_style.gd")
const Edge := preload("res://ui/screen_edge.gd")
const Co := preload("res://core/coords.gd")

var warns := [] # 아직 안 떨어진 예고 (bolt_fx_math.warn_add 항목)
var hit_t0 := -1.0e9 # 내 자리에 번개가 떨어진 시각 (테 번쩍)
var edge: Edge
var plate: PanelContainer
var text: Label
var sec: Label
var bar: Control
var left01 := 0.0 # 남은 시간 ÷ 예고 시간 (막대)


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := Co.color(M.ALERT.glow)
	edge = Edge.new()
	edge.paint(glow)
	add_child(edge)
	plate = PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(S.INK.r, S.INK.g, S.INK.b, float(M.ALERT.plate_alpha))
	sb.border_color = glow
	sb.set_border_width_all(int(M.ALERT.border))
	sb.set_corner_radius_all(int(M.ALERT.corner))
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	plate.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	text = _label(int(M.ALERT.font), glow)
	text.text = str(M.ALERT.text)
	row.add_child(text)
	sec = _label(int(M.ALERT.sec_font), S.TEXT)
	sec.custom_minimum_size.x = float(M.ALERT.sec_w) # 숫자가 바뀌어도 판 폭이 안 흔들리게
	sec.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(sec)
	bar = Control.new()
	bar.custom_minimum_size.y = float(M.ALERT.bar_h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(func():
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(glow.r, glow.g, glow.b, float(M.ALERT.bar_dim)))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * left01, bar.size.y)), glow))
	col.add_child(bar)
	plate.visible = false
	add_child(plate)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


# 서버 이벤트: me = 나 (스냅샷 players[] 한 명, 없으면 {}), now = 판 시계 (ms)
func on_event(e: Dictionary, me: Dictionary, now: float) -> void:
	match str(e.get("type", "")):
		"boltWarn":
			M.warn_add(warns, e, now)
		"bolt":
			M.warn_remove(warns, e.get("id"))
			if M.struck(me, e):
				hit_t0 = now


func clear() -> void:
	warns.clear()
	hit_t0 = -1.0e9
	plate.visible = false
	edge.set_level(0.0)


# 한 프레임: me = 나 (없으면 {}), now = 판 시계 (ms), playing = 판 중인가 (아니면 다 비움 — 서버도 판이 끝나면 남은 예고를 버림), view_mode = View.mode (판 자리)
func refresh(me: Dictionary, now: float, playing: bool, view_mode: String = "first") -> void:
	if not playing:
		if not warns.is_empty() or plate.visible or edge.visible:
			clear()
		return
	M.warn_expire(warns, now)
	var w := M.alert_pick(warns, me, now)
	var on := not w.is_empty()
	plate.visible = on
	if on:
		sec.text = M.alert_sec(float(w.left))
		var k := float(w.left) / float(w.ms)
		if k != left01:
			left01 = k
			bar.queue_redraw()
		if is_inside_tree(): # 트리 밖 (테스트) 이면 자리는 안 잡음
			var vp := get_viewport_rect().size
			var sz := plate.get_combined_minimum_size()
			plate.size = sz
			plate.position = Vector2((vp.x - sz.x) / 2.0, vp.y * M.alert_y(view_mode) - sz.y / 2.0)
	edge.set_level(M.alert_edge(on, now, hit_t0))
