# 놓인 폭탄 '내가 맞는 자리' 화면 신호 (c11-u1, ui/bolt_alert.gd 를 베껴 고침): 남이 놓은 폭탄의 맞는 범위 (world/hand_aim_math.gd bomb_in_range — 서버 Game.ExplodeBomb 과 같은 식) 안에
# 내가 있는 동안 화면에 따로 알림. 기본 1인칭에서는 발밑 가까운 폭탄과 고리가 화면 아래 끝보다 더 아래라 안 보임 (번개 예고와 같은 까닭).
#   · 번개 판과 같은 자리·모양의 어두운 판 + 주황 테: '폭탄! 고리 밖으로' + 남은 초 + 줄어드는 막대 (다 줄면 터짐). 범위 밖으로 나가면 바로 꺼짐
#   · 화면 가장자리 주황 테 (ui/screen_edge.gd) 가 깜빡임
#   · c11-fix F8: 판 안 (글과 남은 초 사이) 에 빠질 방향 화살표 — 폭탄 가운데 → 나 방향을 카메라가 보는 쪽 기준으로 돌린 도형 (hand_aim_math.escape_dir). 위 = 앞으로, 아래 = 뒤로.
#     폭탄과 겹쳐 서 있으면 (방향이 안 정해짐) 화살표만 비움 — 자리는 남겨 판 폭이 안 흔들림
# 내 폭탄·같은 팀 폭탄은 뺌 (서버가 안 맞게 함). 주인은 이벤트 bombPlace 로만 옴 → 놓인 x·y 칸으로 짝지어 폭탄 id 에 붙여 둠 (도화선 시간이 지난 기억은 버림), 모르는 폭탄 (판 중에 들어옴) 은 위험으로 침.
# 번개 판이 떠 있으면 숨김 (같은 자리). hud_extra.gd 가 만들어 넣고 이벤트·프레임마다 부름. 순수 계산·수치는 hand_aim_math.gd BOMB_ALERT (tests/test_round_events.gd test_c11_bomb_alert_*)
extends Control

const M := preload("res://world/hand_aim_math.gd")
const BM := preload("res://world/bolt_fx_math.gd")
const S := preload("res://ui/ui_style.gd")
const Edge := preload("res://ui/screen_edge.gd")
const Co := preload("res://core/coords.gd")

var pending := [] # 아직 폭탄 id 와 짝 못 지은 bombPlace (hand_aim_math.owner_note 항목)
var owners := {} # 폭탄 id → 주인 id
var edge: Edge
var plate: PanelContainer
var text: Label
var sec: Label
var bar: Control
var left01 := 0.0 # 남은 시간 ÷ 도화선 시간 (막대)
var arrow: Control # 빠질 방향 화살표 칸 (도형으로 그림)
var arrow_dir = null # 화면 기준 빠질 방향 (Vector2, hand_aim_math.escape_dir) — null 이면 안 그림
var hold_yaw = null # 확인용 (테스트): 숫자를 넣으면 카메라 yaw 를 그 값으로 고정


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var A: Dictionary = BM.ALERT # 판 모양은 번개 판 그대로
	var glow := Co.color(M.BOMB_ALERT.glow)
	edge = Edge.new()
	edge.paint(glow)
	add_child(edge)
	plate = PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(S.INK.r, S.INK.g, S.INK.b, float(A.plate_alpha))
	sb.border_color = glow
	sb.set_border_width_all(int(A.border))
	sb.set_corner_radius_all(int(A.corner))
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
	text = _label(int(A.font), glow)
	text.text = str(M.BOMB_ALERT.text)
	row.add_child(text)
	arrow = Control.new()
	arrow.custom_minimum_size = Vector2.ONE * float(M.BOMB_ALERT.arrow_px)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.draw.connect(func():
		if arrow_dir != null:
			arrow.draw_colored_polygon(M.arrow_points(arrow_dir, float(M.BOMB_ALERT.arrow_px), arrow.size / 2.0), S.TEXT))
	row.add_child(arrow)
	sec = _label(int(A.sec_font), S.TEXT)
	sec.custom_minimum_size.x = float(A.sec_w) # 숫자가 바뀌어도 판 폭이 안 흔들리게
	sec.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(sec)
	bar = Control.new()
	bar.custom_minimum_size.y = float(A.bar_h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(func():
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(glow.r, glow.g, glow.b, float(A.bar_dim)))
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


# 서버 이벤트: bombPlace 만 봄 (누가 어느 칸에 놓았는지). now = 판 시계 (ms, Net.now_ms — refresh 와 같은 시계)
func on_event(e: Dictionary, now: float) -> void:
	if str(e.get("type", "")) == "bombPlace":
		M.owner_note(pending, e, now)


func clear() -> void:
	pending.clear()
	owners.clear()
	plate.visible = false
	edge.set_level(0.0)


# 한 프레임: st = 스냅샷, me = 나 (없으면 {}), now = 판 시계 (ms), playing = 판 중인가 (아니면 다 비움), view_mode = View.mode (판 자리), bolt_on = 번개 판이 떠 있는가
func refresh(st: Dictionary, me: Dictionary, now: float, playing: bool, view_mode: String = "first", bolt_on := false) -> void:
	if not playing:
		if not pending.is_empty() or not owners.is_empty() or plate.visible or edge.visible:
			clear()
		return
	var bombs: Array = st.get("bombs", [])
	if bombs.is_empty() and owners.is_empty() and not plate.visible and not edge.visible: # 폭탄 없는 보통 프레임
		return
	M.owner_bind(owners, pending, bombs, now)
	var w := M.bomb_pick(bombs, owners, me, st)
	var on := M.bomb_alert_show(bolt_on, w)
	plate.visible = on
	if on:
		sec.text = BM.alert_sec(float(w.left))
		var k := float(w.left) / float(w.ms)
		if k != left01:
			left01 = k
			bar.queue_redraw()
		var dir = M.escape_dir(me, float(w.x), float(w.y), _cam_yaw(me))
		if dir != arrow_dir:
			arrow_dir = dir
			arrow.queue_redraw()
		if is_inside_tree(): # 트리 밖 (테스트) 이면 자리는 안 잡음
			var vp := get_viewport_rect().size
			var sz := plate.get_combined_minimum_size()
			plate.size = sz
			plate.position = Vector2((vp.x - sz.x) / 2.0, vp.y * BM.alert_y(view_mode) - sz.y / 2.0)
	edge.set_level(BM.alert_edge(on, now, -1.0e9))


# 카메라가 보는 쪽 (게임 yaw): 화면에 그리는 카메라 (1·3인칭 모두 내 시선 쪽 — 스냅샷 값보다 한 박자 빠름), 트리 밖 (테스트) 이면 스냅샷의 내 yaw
func _cam_yaw(me: Dictionary) -> float:
	if hold_yaw != null:
		return float(hold_yaw)
	if is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			return Co.yaw_of(cam)
	return float(me.get("yaw", 0.0))
