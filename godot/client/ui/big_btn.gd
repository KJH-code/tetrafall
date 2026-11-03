# 메뉴 큰 버튼 꾸밈 (JS #rooms button.big, W8): 고도 StyleBoxFlat 은 테두리만 (안쪽 1px ga), 나머지는 이 두 겹이 그림.
#  뒤 겹 (show_behind_parent): 세로 그라데이션 바탕 rgba(30,18,52,.8)→rgba(8,5,18,.86) (hover·열림: g 36% 섞음 → rgba(10,6,22,.88))
#   + 안쪽 빛 inset 0 0 26px gc (가장자리 g 10% → 안쪽 투명, 띠 4개) + 왼쪽 빛 띠 inset 4px g (clip-path 사선에 잘려 왼쪽 아래 작은 세모만 보임, hover·열림은 흰)
#  앞 겹: 빛 줄기 반짝임 (::after 40% 폭, 100deg 투명→흰 .26→투명, 5.5초 중 70% 쉬고 왼쪽 -60% → 130%, 버튼마다 .25초 늦게) — 사선 안으로 잘라 그림.
#   움직임 줄이기·그래픽 낮춤이면 반짝임 없음 (JS 와 같음)
# 사선: JS clip-path polygon(18px 0, 100% 0, calc(100% - 18px) 100%, 0 100%) = 칸 안에 들어가는 평행사변형. 고도 StyleBoxFlat skew 는 가운데 기준이라
# 칸 밖으로 skew·h/2 씩 넘침 → fit() 이 expand_margin 을 그만큼 음수로 (아래 줄 버튼 사이 10px 이 겹치지 않게)
extends RefCounted

const S := preload("res://ui/ui_style.gd")

const SHEEN_MS := 5500.0
const SHEEN_IDLE := 0.7
const SHEEN_W := 0.4
const SHEEN_FROM := -0.6
const SHEEN_TO := 1.3
const SHEEN_A := 0.26
const SHEEN_SLANT := 0.176 # 100deg 그라데이션 = 세로선에서 10도 (tan 10°)
const SHEEN_DELAY := 250.0
const STRIP := 4.0
const GLOW_PX := 13.0 # inset 26px 흐림 → 빛이 실제로 보이는 폭 (절반)
const GLOW_A := 0.1 # gc = g 10%
const TOP := Color8(30, 18, 52, 204)
const BOT := Color8(8, 5, 18, 219)
const HOT_TOP_MIX := 0.36
const HOT_BOT := Color8(10, 6, 22, 224)


# 평행사변형 (칸 안, 왼쪽 위·오른쪽 위·오른쪽 아래·왼쪽 아래). k = 사선 가로 폭 (px)
static func shape(w: float, h: float, k: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(k, 0), Vector2(w, 0), Vector2(w - k, h), Vector2(0, h)])


# 왼쪽 빛 띠: x ∈ [0, 4] 와 평행사변형이 겹치는 곳 = 왼쪽 아래 세모 (사선이 4px 보다 좁으면 사다리꼴)
static func strip(h: float, k: float) -> PackedVector2Array:
	if k <= STRIP:
		return PackedVector2Array([Vector2(k, 0), Vector2(STRIP, 0), Vector2(STRIP, h), Vector2(0, h)])
	return PackedVector2Array([Vector2(STRIP, h * (1.0 - STRIP / k)), Vector2(STRIP, h), Vector2(0, h)])


# 반짝임 띠 왼쪽 끝 (칸 폭 비율, null = 쉼). ms = 이 버튼 시계 (늦춤 뺀 값)
static func sheen_x(ms: float):
	var u := fposmod(ms, SHEEN_MS) / SHEEN_MS
	if u < SHEEN_IDLE:
		return null
	return SHEEN_FROM + (SHEEN_TO - SHEEN_FROM) * (u - SHEEN_IDLE) / (1.0 - SHEEN_IDLE)


# x 를 그 높이 (y) 의 평행사변형 안으로
static func _clip_x(x: float, y: float, w: float, h: float, k: float) -> float:
	var lo := k * (1.0 - y / h)
	return clampf(x, lo, lo + w - k)


# 버튼에 붙임 (menu.gd _item·아래 줄). i = 반짝임 늦춤 차례
static func attach(b: Button, i: int, reduced: bool) -> void:
	var back := Control.new()
	back.name = "BigBack"
	back.show_behind_parent = true
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.draw.connect(_draw_back.bind(back, b))
	b.add_child(back)
	for sig in ["mouse_entered", "mouse_exited", "toggled", "resized"]:
		b.connect(sig, func(_a = null): back.queue_redraw())
	if reduced:
		return
	var front := Control.new()
	front.name = "BigSheen"
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	front.set_meta("delay", SHEEN_DELAY * i)
	front.draw.connect(_draw_sheen.bind(front, b))
	b.add_child(front)
	# 반짝이는 동안만 다시 그림 (쉬는 70% 는 안 그림)
	var tw := front.create_tween().set_loops()
	tw.tween_method(_tick.bind(front), 0.0, 1.0, 0.1)


static func _tick(_v: float, front: Control) -> void:
	if sheen_x(Time.get_ticks_msec() - float(front.get_meta("delay"))) != null or front.get_meta("on", false):
		front.queue_redraw()


# 사선 가로 폭 = StyleBoxFlat skew × 높이
static func slant_px(b: Button) -> float:
	var sb = b.get_theme_stylebox("normal")
	return (sb.skew.x if sb is StyleBoxFlat else 0.0) * b.size.y


# StyleBoxFlat skew 넘침을 칸 안으로 (모든 상태 stylebox)
static func fit(b: Button, h: float) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb = b.get_theme_stylebox(st)
		if sb is StyleBoxFlat:
			var m: float = -sb.skew.x * h / 2.0
			sb.expand_margin_left = m
			sb.expand_margin_right = m


static func _hot(b: Button) -> bool:
	return b.is_hovered() or b.button_pressed


static func _draw_back(c: Control, b: Button) -> void:
	var w := c.size.x
	var h := c.size.y
	var k := slant_px(b)
	var g: Color = S.g()
	var hot := _hot(b)
	var top := TOP if not hot else Color(g.lerp(Color8(18, 12, 34), 1.0 - HOT_TOP_MIX), 0.8)
	var bot := BOT if not hot else HOT_BOT
	var p := shape(w, h, k)
	# 바탕·안쪽 빛 띠 4개·빛 세모를 삼각형 한 묶음으로 (그리기 1번 — 따로 그리면 버튼마다 6번, 메뉴 8개면 +40)
	var ga := Color(g, GLOW_A * (2.2 if hot else 1.0))
	var g0 := Color(g, 0.0)
	var d := GLOW_PX
	var q := PackedVector2Array([p[0] + Vector2(d, d), p[1] + Vector2(-d, d), p[2] + Vector2(-d, -d), p[3] + Vector2(d, -d)])
	# 사각형 5개 (바탕 + 빛 띠 4) — 꼭짓점·색을 차례로 (PackedArray 는 값 복사라 람다·함수에 넘기지 않고 여기서 채움)
	var quads := [[[p[0], p[1], p[2], p[3]], [top, top, bot, bot]]]
	for e in 4:
		var n := (e + 1) % 4
		quads.append([[p[e], p[n], q[n], q[e]], [ga, ga, g0, g0]])
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var ids := PackedInt32Array()
	for qd in quads:
		var o := pts.size()
		for i in 4:
			pts.append(qd[0][i])
			cols.append(qd[1][i])
		ids.append_array(PackedInt32Array([o, o + 1, o + 2, o, o + 2, o + 3]))
	var sc := Color.WHITE if hot else g
	var tri := strip(h, k)
	var o2 := pts.size()
	for v in tri:
		pts.append(v)
		cols.append(sc)
	for i in range(1, tri.size() - 1):
		ids.append_array(PackedInt32Array([o2, o2 + i, o2 + i + 1]))
	RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), ids, pts, cols)


static func _draw_sheen(c: Control, b: Button) -> void:
	var x = sheen_x(Time.get_ticks_msec() - float(c.get_meta("delay")))
	c.set_meta("on", x != null)
	if x == null:
		return
	var w := c.size.x
	var h := c.size.y
	var k := slant_px(b)
	var bw := SHEEN_W * w
	var x0: float = x * w
	var lean := SHEEN_SLANT * h # 100deg: 위가 오른쪽으로
	# 세 세로 줄 (투명 · 흰 · 투명) 을 위·아래 줄에서 평행사변형 안으로 잘라 두 사다리꼴
	var xs := [x0, x0 + bw / 2.0, x0 + bw]
	var col := [Color(1, 1, 1, 0), Color(1, 1, 1, SHEEN_A), Color(1, 1, 1, 0)]
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var ids := PackedInt32Array()
	for s in 2:
		var tl := _clip_x(xs[s] + lean, 0.0, w, h, k)
		var tr := _clip_x(xs[s + 1] + lean, 0.0, w, h, k)
		var br := _clip_x(xs[s + 1], h, w, h, k)
		var bl := _clip_x(xs[s], h, w, h, k)
		if tr - tl < 0.5 and br - bl < 0.5:
			continue
		var o := pts.size()
		pts.append_array(PackedVector2Array([Vector2(tl, 0), Vector2(tr, 0), Vector2(br, h), Vector2(bl, h)]))
		cols.append_array(PackedColorArray([col[s], col[s + 1], col[s + 1], col[s]]))
		ids.append_array(PackedInt32Array([o, o + 1, o + 2, o, o + 2, o + 3]))
	if not ids.is_empty(): # 두 사다리꼴을 한 번에 그림
		RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), ids, pts, cols)
