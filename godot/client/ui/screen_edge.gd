# c7 화면 가장자리 테 (ui/hud_extra.gd 가 씀): 맞음·조준당함·노래·연습 초기화 번쩍과 경직 알림을 화면 전체 막 대신 가장자리 띠로만.
# 예전: 번쩍 = 화면 전체 ColorRect (맞으면 노랑 45% 막이 장면·아래 사람 판까지 덮음), 경직 = 가운데까지 번지는 둥근 붉은 빛.
# 지금: 바깥 가는 진한 띠 (화면 높이의 EDGE.outer) + 안쪽으로 0 까지 번지는 띠 (EDGE.inner) 네 변, 가운데는 비움. 두께는 가로·세로 모두 화면 높이 기준.
# c7-fix F6: 알파가 바깥에서 안으로 끊김 없이 이어짐 (stops — 이웃 띠가 경계 알파를 같이 씀). 예전엔 안쪽 띠가 바깥 띠의 0.55배에서 시작해 경계에서 한 화소 만에 밝기가 떨어져
# 굵은 단색 띠 + 옅은 띠 두 겹으로 보였음. 번지는 띠는 꺾임 하나 (EDGE.knee) 로 처음엔 빨리·뒤엔 천천히 줄어 '가장자리에서 번지는 빛' 으로.
# HUD 판·시계·핑보다 먼저 그림 (z_index EDGE.z — JS 도 #flash 가 #players 아래). 셰이더 없이 정점 색 사다리꼴 12개 (c8: 옆 변을 나눠 18개) 를 삼각형 묶음 하나로 (_draw, 그리기 1번 —
# 사다리꼴마다 draw_polygon 이면 테 하나에 그리기 12번).
# c8: 윗변 쪽을 옅게 (EDGE.top·top_ramp) — 위 HUD (시계·점수 띠·킬 피드·알림·핑) 가 진한 테 위에 얹혀 덜 읽히던 것. 알파 배율 m(y) 를 자리 (y) 로만 정해
# 모든 꼭짓점에 곱함 (변마다 다른 배율이 아님 → 모서리 45도 선에서 두 변이 같은 값, 계단 없음). 옆 변 사다리꼴은 m 이 1 이 되는 높이에서 둘로 나눠 그 자리에 꼭짓점.
# c10: 옆변을 가로로 가늘게 (EDGE.side) — 16:9 화면에서 옆변 띠가 옆 시야 (가장자리에 선 사람·낭떠러지) 를 위·아래 변보다 넓게 덮던 것. 변까지 거리를 옆변만 ÷ side 로 재서
# (alpha_at) 띠 사각형이 (d × side, d) 로 들어가고 (_rect), 모서리 꺾임선은 그 축척 대각선. 윗·아랫변 두께·알파·꺾임·그리기 1번은 그대로.
# 순수 계산 (띠 두께·알파·사다리꼴) 은 tests/test_feel.gd test_c7_*·test_c8_edge_top_dim·test_c10_edge_side_thin 이 고정
extends Control

const EDGE := {
	"outer": 0.008, # 바깥 진한 띠 두께 ÷ 화면 높이 (가는 선 — 굵으면 단색 띠로 보임)
	"inner": 0.107, # 안쪽 번지는 띠 두께 ÷ 화면 높이 (바깥 띠 알파에서 0 까지)
	"knee": [0.35, 0.4], # 번지는 띠의 꺾임: [띠 안 자리 0~1, 그 자리 알파 배율] — 바깥 띠 알파 1 → 여기 → 0 (끊김 없이 이어짐)
	"side": 0.55, # c10 옆변 띠의 가로 두께 배율 (윗·아랫변 두께 × 이만큼)
	"top": 0.4, # c8 윗변 (y = 0) 알파 배율 — 위 HUD 를 덜 덮게
	"top_ramp": 0.3, # c8 화면 높이 × 이만큼 내려오면 배율 1 (사이는 곧게). 띠 두께 합보다 커야 옆 변을 그 높이에서 나눔
	"gain": 1.8, # 번쩍: 바깥 띠 알파 = min(1, 받은 색 알파 × gain) — 좁아진 만큼 진하게
	"fade": 0.4, # 번쩍이 사라지는 시간 (초, 예전 그대로)
	"stun": Color(1, 0, 0, 0.75), # 경직 테 색 (알파 = 바깥 띠 알파)
	"stun_fade": 0.15, # 경직 테가 켜지고 꺼지는 시간 (초, 예전 그대로)
	"z": -1, # 그리는 순서: HUD (0) 아래
}

var tint := Color(1, 1, 1, 0) # 색 + 바깥 띠 알파 (사라짐은 modulate.a 가 맡음 → 다시 안 그림)
var _tw: Tween


# 띠 두께 (화소): x = 바깥 진한 띠, y = 안쪽 번지는 띠
static func band_px(size: Vector2) -> Vector2:
	return Vector2(size.y * float(EDGE.outer), size.y * float(EDGE.inner))


# 번쩍 색 (화면 전체 막일 때 쓰던 색·알파) → 테 색 (알파 = 바깥 띠 알파)
static func flash_tint(col: Color) -> Color:
	return Color(col.r, col.g, col.b, minf(1.0, col.a * float(EDGE.gain)))


# 알파 꺾임 점들 (가장자리에서 안쪽으로): [거리 (화소), 알파 배율]. 이웃 띠가 같은 점을 같이 써서 경계에 계단이 없음 — 바깥 띠 1 → 1, 번지는 띠 1 → knee → 0
static func stops(size: Vector2) -> Array:
	var b := band_px(size)
	var kn: Array = EDGE.knee
	return [[0.0, 1.0], [b.x, 1.0], [b.x + b.y * float(kn[0]), float(kn[1])], [b.x + b.y, 0.0]]


# c8 윗변 줄임 배율 m(y): y = 0 이면 EDGE.top, y ≥ 화면 높이 × EDGE.top_ramp 이면 1, 사이는 곧게
static func top_mul(size: Vector2, y: float) -> float:
	var ramp := size.y * float(EDGE.top_ramp)
	if ramp <= 0.0 or y >= ramp:
		return 1.0
	return lerpf(float(EDGE.top), 1.0, maxf(0.0, y) / ramp)


# 화면 한 점의 알파 (바깥 띠 알파 a 일 때): 가장 가까운 변까지 거리로 — stops 사이를 곧게 이음 (바깥 띠 안 = a, 번지는 띠 = a 에서 0 으로, 그 안쪽 = 0), 거기에 윗변 줄임 m(y).
# c10: 옆변까지 거리는 ÷ EDGE.side (옆변 띠가 그만큼 가늘어짐)
static func alpha_at(size: Vector2, pt: Vector2, a: float) -> float:
	var d := minf(minf(pt.x, size.x - pt.x) / float(EDGE.side), minf(pt.y, size.y - pt.y))
	if d < 0.0:
		return 0.0
	a *= top_mul(size, pt.y)
	var st := stops(size)
	for i in st.size() - 1:
		var d0 := float(st[i][0])
		var d1 := float(st[i + 1][0])
		if d <= d1:
			return a * lerpf(float(st[i][1]), float(st[i + 1][1]), (d - d0) / (d1 - d0) if d1 > d0 else 1.0)
	return 0.0


# 띠 사다리꼴 (변마다 stops 사이 띠 하나씩 = 12개, 위 → 오른 → 아래 → 왼 순): [꼭짓점 넷 (바깥 둘 → 안 둘), 꼭짓점마다 꺾임 점 알파 배율]. 모서리는 축척 대각선 (d × side, d) 으로 맞물림.
# 윗변 줄임 m(y) 는 아직 안 곱한 값 — 그리는 쪽 (tri_arrays) 이 옆 변을 나누고 꼭짓점마다 곱함
static func quads(size: Vector2) -> Array:
	var st := stops(size)
	var out := []
	for s in st.size() - 1:
		var r0 := _rect(size, float(st[s][0]))
		var r1 := _rect(size, float(st[s + 1][0]))
		var al := PackedFloat32Array([st[s][1], st[s][1], st[s + 1][1], st[s + 1][1]])
		for i in 4:
			var j := (i + 1) % 4
			out.append([PackedVector2Array([r0[i], r0[j], r1[j], r1[i]]), al])
	return out


# 화면에서 위·아래 d 화소, 옆 d × EDGE.side 화소 들어간 사각형의 네 꼭짓점 (왼위 → 오른위 → 오른아래 → 왼아래)
static func _rect(size: Vector2, d: float) -> Array:
	var dx := d * float(EDGE.side)
	return [Vector2(dx, d), Vector2(size.x - dx, d), Vector2(size.x - dx, size.y - d), Vector2(dx, size.y - d)]


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = int(EDGE.z)
	visible = false # 켜질 때만 그림
	modulate.a = 0.0
	resized.connect(queue_redraw)


# c8 사다리꼴 하나를 높이 y 에서 둘로 (옆 변 = 바깥 변 q[0][0]→[1] 과 안쪽 변 [3]→[2] 가 세로이고 둘 다 y 를 지날 때만. 아니면 그대로 하나).
# 나눈 자리의 새 꼭짓점은 그 변의 꺾임 점 알파 그대로 (세로 변 위에선 알파가 한 값)
static func split_at(q: Array, y: float) -> Array:
	var p: PackedVector2Array = q[0]
	var a: PackedFloat32Array = q[1]
	var vertical: bool = p[0].x == p[1].x and p[3].x == p[2].x
	if not vertical or (p[0].y - y) * (p[1].y - y) >= 0.0 or (p[3].y - y) * (p[2].y - y) >= 0.0:
		return [q]
	var mo := Vector2(p[0].x, y)
	var mi := Vector2(p[3].x, y)
	return [
		[PackedVector2Array([p[0], mo, mi, p[3]]), PackedFloat32Array([a[0], a[0], a[3], a[3]])],
		[PackedVector2Array([mo, p[1], p[2], mi]), PackedFloat32Array([a[0], a[1], a[2], a[3]])],
	]


# quads 를 한 번에 그릴 삼각형 묶음으로: [꼭짓점 번호 (사다리꼴마다 삼각형 둘), 꼭짓점, 꼭짓점마다 알파 배율].
# c8: 옆 변 사다리꼴은 윗변 줄임이 끝나는 높이 (화면 높이 × EDGE.top_ramp) 에서 둘로 (12 → 18개), 꼭짓점 알파 = 꺾임 점 알파 × m(그 꼭짓점 y) = alpha_at
static func tri_arrays(size: Vector2) -> Array:
	var idx := PackedInt32Array()
	var pts := PackedVector2Array()
	var al := PackedFloat32Array()
	var ramp_y := size.y * float(EDGE.top_ramp)
	for q0 in quads(size):
		for q in split_at(q0, ramp_y):
			var o := pts.size()
			pts.append_array(q[0])
			for i in 4:
				al.append(q[1][i] * top_mul(size, q[0][i].y))
			idx.append_array([o, o + 1, o + 2, o, o + 2, o + 3])
	return [idx, pts, al]


func _draw() -> void:
	if tint.a <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var t := tri_arrays(size)
	var cols := PackedColorArray()
	for a in t[2]:
		cols.append(Color(tint.r, tint.g, tint.b, tint.a * a))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), t[0], t[1], cols)


# 테 색을 정함 (알파 = 바깥 띠 알파)
func paint(col: Color) -> void:
	if tint != col:
		tint = col
		queue_redraw()


# 세기 0~1 (경직 테: 켜고 끌 때 hud_extra 가 프레임마다)
func set_level(k: float) -> void:
	modulate.a = k
	visible = k > 0.0


# 번쩍 한 번: col = 화면 전체 막일 때의 색·알파. EDGE.fade 초 동안 사라짐
func fire(col: Color) -> void:
	paint(flash_tint(col))
	set_level(1.0)
	if _tw != null and _tw.is_valid():
		_tw.kill()
	if not is_inside_tree():
		return
	_tw = create_tween()
	_tw.tween_property(self, "modulate:a", 0.0, float(EDGE.fade))
	_tw.tween_callback(func(): visible = false)
