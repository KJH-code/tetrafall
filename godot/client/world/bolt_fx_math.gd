# 돌발 이벤트 '번개' 모습의 순수 계산 (c9, 그리는 쪽은 world/bolt_fx.gd): 예고 고리 메시·반지름·채움·알파, 번개 띠 지그재그·화면 상한, 예고 목록.
# 노드 없음 → tests/test_round_events.gd test_bolt_* 가 고정. 수치는 전부 여기 (고도 판 전용 — core/config.gd 는 JS 에서 만든 파일이라 안 고침)
# 예고 고리는 F 준비 예고 고리 (world/ring_look.gd windup: 이어진 고리 + 쓴 사람 색) 와 모양으로 갈림: 8조각으로 끊긴 고리 · 사람 색 없음 (흰 심 + 잉크 테) · 안에서 차오르는 연노랑 원
extends RefCounted

const RL := preload("res://world/ring_look.gd")
const FM := preload("res://fx/fx_math.gd")
const G3C := preload("res://shaders/g3_config.gd")
const Co := preload("res://core/coords.gd")

# 예고 고리 (바깥 반지름 1 기준). bands = [안 반지름, 바깥 반지름, 안쪽 칠, 바깥쪽 칠] (칠 이름은 ring_look.paint) — 띠 폭 = 반지름의 24% (0.76 → 1.0)
const WARN := {
	"pieces": 8, # 끊긴 조각 수
	"gap": 0.3, # 조각 사이 틈 (조각 한 칸 각도 중 비율)
	"arc_seg": 5, # 조각 하나를 나누는 마디 수
	"bands": [[0.76, 0.80, "clear", "core"], [0.80, 0.90, "core", "core"], [0.90, 1.0, "ink", "ink"]],
	"fill_seg": 32, # 채운 원 둘레 마디 수
	"fill_color": 0xfff0a0, # 채운 원 색 (연노랑)
	"fill_alpha": 0.28,
	"fill_r0": 0.12, # 채운 원 처음 반지름 (바깥 반지름 기준) → 떨어지는 순간 고리 안쪽 끝 (bands 첫 안 반지름) 까지
	"pop": 1.18, # 처음 반지름 배율 (살짝 크게 떴다가 제 크기로)
	"pop_u": 0.12, # 제 크기가 되는 시각 (흐른 비율)
	"fade_u": 0.08, # 알파 0 → 1 이 되는 시각 (흐른 비율)
	"spin": 0.9, # 끊긴 고리가 도는 빠르기 (rad/초)
	"lift": 0.06, # 바닥에서 띄움 (칸) — 발밑 고리 0.04 · F 예고 고리 0.05 위
	"priority": 9, # 그리는 순서 (F 예고 고리와 같음, 이름표 외곽선 10 아래)
	"grace_ms": 400.0, # 떨어졌다는 이벤트를 못 받은 예고는 예정 시각 뒤 이만큼 지나면 지움
	"max": 16, # 한 번에 그리는 예고 수 (8명 판 한 차례 4개)
}
# 번개 띠: 하늘에서 바닥까지 꺾인 띠 3단 (바깥 → 안: 잉크 테 · 연노랑 · 흰 심)
const STRIKE := {
	"height": 7.0, # 띠 높이 (칸) — 화면 상한에 걸리면 줄어듦
	"joints": 7, # 꺾이는 마디 수 (바닥·꼭대기 포함 점 = joints + 1)
	"amp": 0.42, # 좌우로 꺾이는 폭 (칸)
	"layers": [[0.5, "ink", 1.0], [0.3, "glow", 1.0], [0.12, "core", 1.0]], # [띠 폭 (칸), 칠, 알파 배율]
	"glow": 0xfff0a0,
	"life_ms": 250.0,
	"hold": 0.4, # 수명의 이만큼은 알파 1, 그 뒤 곧게 0 으로
	"top_fade": 0.3, # 꼭대기에서 이 비율만큼은 위로 갈수록 옅게 (잘린 끝이 안 보이게)
	"overlap": 0.12, # 마디 이음: 토막을 이만큼 (칸) 더 길게 겹침 (바닥·꼭대기 끝은 빼고)
	"cap": 0.45, # 화면 높이 × 이 값까지만 (fx_config SCREEN_CAP 과 같은 값)
	"cap_seg": 8, "cap_steps": 12, "cap_near": 0.05, # fx_math.plume_cap 에 넘기는 값 (낙사 줄기와 같음)
	"flash_ms": 300.0, # 바닥 고리 (ring_look aura) 한 번
	"flash_r0": 0.55, "flash_r1": 1.25, # 바닥 고리 반지름: 맞는 반지름 × r0 → × r1
	"flash_alpha": 0.9,
	"max": 16, # 한 번에 그리는 번개 수
}

# 내가 예고 고리 안일 때 화면 신호 (ui/bolt_alert.gd — c9 리뷰 F2): 가운데 아래 판 '번개! 고리 밖으로' + 남은 초·막대, 화면 가장자리 테.
# 1인칭 정면에서는 발밑 고리가 화면 밖 (눈높이 1.45 에서 반지름 1.2 고리는 수평선 아래 약 45°, 화면 아래 끝은 37.5°) 이라 고리만으론 내가 대상인지 모름
const ALERT := {
	"height": 3.0, # 맞는 발 높이 차 (칸) — 서버 EVENT_BOLT_HEIGHT (godot/server ConfigEvents.cs) 와 같은 값. 이벤트엔 반지름 r 만 와서 여기 둠
	"text": "번개! 고리 밖으로",
	"y": 0.66, # 1인칭: 판 가운데 ÷ 화면 높이 — 조준점·경직 글자 (가운데 + 30px) 아래, 아래 사람 판 위. 압사 경고는 위 묶음이라 안 겹침
	"y_up": 0.34, # 3인칭·하늘 시점: 조준점 위 (위 묶음 아래) — 0.66 이면 화면 가운데 아래의 내 몸과 발밑 고리를 판이 덮음 (고리 밖으로 나가려면 내 몸·고리가 보여야 함)
	"font": 24, "sec_font": 20, "sec_w": 56.0,
	"glow": 0xfff0a0, # 번개 연노랑 (예고 채운 원·번개 띠와 같은 색)
	"plate_alpha": 0.86, # 판 바탕 (잉크 남색) 알파
	"border": 3, "corner": 4, # 테 굵기·모서리 (px) — 압사 경고 (기울인 평행사변형·줄무늬) 와 다른 모양
	"bar_h": 5.0, "bar_dim": 0.25, # 남은 시간 막대 높이 (px)·빈 자리 알파
	"edge": [0.35, 0.7], # 고리 안에 있는 동안 화면 가장자리 테 알파 (깜빡임 낮음 ↔ 높음)
	"blink_ms": 240.0, # 깜빡임 한 번
	"hit_alpha": 1.0, "hit_ms": 400.0, # 내 자리에 떨어진 순간 테 알파 → 0 까지 걸리는 시간 (화면 번쩍 EDGE.fade 와 같은 길이)
}

static var _warn_mesh: ArrayMesh = null
static var _quad: ArrayMesh = null


# ---------- 예고: 시각 ----------
# 흐른 비율 u (0 = 예고가 뜬 순간, 1 = 떨어지는 순간)
static func warn_u(now: float, t0: float, ms: float) -> float:
	return clampf((now - t0) / ms, 0.0, 1.0) if ms > 0.0 else 1.0


# 고리 바깥 반지름 (칸): r = 맞는 반지름. 처음에 조금 크게 떴다가 pop_u 에 제 크기 — 그 뒤로는 맞는 범위 그대로
static func warn_radius(u: float, r: float) -> float:
	var k := clampf(u / float(WARN.pop_u), 0.0, 1.0)
	return r * lerpf(float(WARN.pop), 1.0, 1.0 - (1.0 - k) * (1.0 - k))


# 채운 원 반지름 ÷ 맞는 반지름: fill_r0 → 고리 안쪽 끝. 남은 시간을 읽는 눈금 (다 차면 떨어짐)
static func fill_frac(u: float) -> float:
	return lerpf(float(WARN.fill_r0), float(WARN.bands[0][0]), clampf(u, 0.0, 1.0))


static func warn_alpha(u: float) -> float:
	return clampf(u / float(WARN.fade_u), 0.0, 1.0)


# 띠 폭 ÷ 바깥 반지름
static func band_frac() -> float:
	var b: Array = WARN.bands
	return (float(b.back()[1]) - float(b[0][0])) / float(b.back()[1])


# ---------- 예고: 메시 ----------
# 한 메시에 두 모양: 끊긴 고리 (x·z 평면, 반지름 1) + 채운 원 (y·z 평면, 반지름 1, 흰색). MultiMesh 인스턴스의 기저로 하나만 고름 —
# 고리 인스턴스는 y 기둥이 0 (원이 선으로 눌려 넓이 0 = 안 그려짐), 원 인스턴스는 x 기둥이 0 (고리가 눌림) 이고 y 기둥이 바닥 x 쪽. → 고리와 원이 MultiMesh 하나·그리기 한 번
static func warn_mesh() -> ArrayMesh:
	if _warn_mesh != null:
		return _warn_mesh
	var v := PackedVector3Array()
	var vc := PackedColorArray()
	var pieces := int(WARN.pieces)
	var arc_seg := int(WARN.arc_seg)
	var span := TAU / pieces * (1.0 - float(WARN.gap))
	for i in pieces:
		var a_from := TAU * i / pieces
		for j in arc_seg:
			var a0 := a_from + span * j / arc_seg
			var a1 := a_from + span * (j + 1) / arc_seg
			var d0 := Vector3(cos(a0), 0, -sin(a0))
			var d1 := Vector3(cos(a1), 0, -sin(a1))
			for b in WARN.bands:
				var ri := float(b[0])
				var ro := float(b[1])
				var ci := RL.paint(str(b[2]), Color.WHITE)
				var co := RL.paint(str(b[3]), Color.WHITE)
				v.append_array([d0 * ro, d0 * ri, d1 * ro, d1 * ro, d0 * ri, d1 * ri])
				vc.append_array([co, ci, co, co, ci, ci])
	var fs := int(WARN.fill_seg)
	for i in fs:
		var a0 := TAU * i / fs
		var a1 := TAU * (i + 1) / fs
		v.append_array([Vector3.ZERO, Vector3(0, cos(a0), -sin(a0)), Vector3(0, cos(a1), -sin(a1))])
		vc.append_array([Color.WHITE, Color.WHITE, Color.WHITE])
	_warn_mesh = _mesh(v, vc)
	return _warn_mesh


# 고리 인스턴스 기저: 바닥 (고도 x·z) 에 반지름 r, 위축 둘레로 spin (rad) 만큼 돎. y 기둥 0 → 채운 원은 안 그려짐
static func ring_basis(r: float, spin: float) -> Basis:
	var b := Basis(Vector3.UP, spin)
	return Basis(b.x * r, Vector3.ZERO, b.z * r)


# 채운 원 인스턴스 기저: 메시의 y 를 바닥 x 로 눕힘 (반지름 r). x 기둥 0 → 고리는 안 그려짐
static func fill_basis(r: float) -> Basis:
	return Basis(Vector3.ZERO, Vector3(r, 0, 0), Vector3(0, 0, r))


static func ring_color(alpha: float) -> Color:
	return Color(1, 1, 1, alpha)


static func fill_color(alpha: float) -> Color:
	var c := Co.color(WARN.fill_color)
	return Color(c.r, c.g, c.b, float(WARN.fill_alpha) * alpha)


# ---------- 번개 띠 ----------
# 띠 토막 메시: x −0.5~0.5 (폭), y 0~1 (길이), 흰색 — 인스턴스 기저가 토막 하나의 폭·방향·길이, 인스턴스 색이 단 색
static func quad_mesh() -> ArrayMesh:
	if _quad != null:
		return _quad
	var v := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	var vc := PackedColorArray()
	for i in 6:
		vc.append(Color.WHITE)
	_quad = _mesh(v, vc)
	return _quad


# 지그재그 점들 (바닥 → 꼭대기): Vector2(옆으로 벗어난 칸, 높이 칸). 바닥 점은 한가운데 (0, 0), 꼭대기는 (·, height). 마디마다 좌우를 번갈아 amp 의 0.45~1 배.
# 시드 = 예고 id → 같은 번개는 프레임마다·다시 찍어도 같은 모양
static func zigzag(id: int, height: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 77
	var n := int(STRIKE.joints)
	var out := PackedVector2Array([Vector2.ZERO])
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	for i in range(1, n + 1):
		var step := float(i) # 마디 높이: 고르게 나눈 자리에서 위아래로 조금 흔듦 (꼭대기는 제자리)
		if i < n:
			step += (rng.randf() - 0.5) * 0.4
		var h := height * step / n
		out.append(Vector2(side * float(STRIKE.amp) * rng.randf_range(0.45, 1.0), h))
		side = -side
	return out


# 화면 상한 배율 (≤ 1, 높이·폭에 같이 곱함): 띠 (높이 height, 가장 넓은 폭 = 꺾임 폭 × 2 + 바깥 단 폭) 가 화면 높이 × cap 을 넘으면 줄임 — 낙사 줄기와 같은 원근 투영 길 (fx_math.plume_cap).
# foot = 바닥 점, up = 위쪽 단위 벡터 (둘 다 카메라 공간: 보는 쪽이 −z). 바닥 점이 카메라 뒤·바로 앞이면 0 (안 그림)
static func strike_cap(height: float, foot: Vector3, up: Vector3, fov_deg: float) -> float:
	return FM.plume_cap(height, strike_width(), foot, up, fov_deg, float(STRIKE.cap), int(STRIKE.cap_seg), int(STRIKE.cap_steps), float(STRIKE.cap_near))


static func strike_width() -> float:
	return float(STRIKE.amp) * 2.0 + float(STRIKE.layers[0][0])


# 띠 알파 (t = 떨어진 뒤 ms): hold 까지 1, 그 뒤 곧게 0. 수명이 지나면 -1 (지움)
static func strike_alpha(t_ms: float) -> float:
	var u := t_ms / float(STRIKE.life_ms)
	if u >= 1.0:
		return -1.0
	var h := float(STRIKE.hold)
	return 1.0 if u <= h else 1.0 - (u - h) / (1.0 - h)


# 높이에 따른 알파 (h01 = 토막 가운데 높이 ÷ 띠 높이): 꼭대기 top_fade 구간은 위로 갈수록 0 으로
static func top_alpha(h01: float) -> float:
	return clampf((1.0 - h01) / float(STRIKE.top_fade), 0.0, 1.0)


static func layer_color(kind: String, alpha: float) -> Color:
	var c := Color.WHITE
	match kind:
		"ink":
			c = Color(G3C.OUTLINE_COLOR.r, G3C.OUTLINE_COLOR.g, G3C.OUTLINE_COLOR.b, RL.INK_ALPHA)
		"glow":
			c = Co.color(STRIKE.glow)
	return Color(c.r, c.g, c.b, c.a * alpha)


# 바닥 고리 (떨어진 순간 한 번): t = 떨어진 뒤 ms → Vector2(반지름 (칸), 알파). 끝나면 알파 -1
static func flash(t_ms: float, r: float) -> Vector2:
	var u := t_ms / float(STRIKE.flash_ms)
	if u >= 1.0:
		return Vector2(r * float(STRIKE.flash_r1), -1.0)
	return Vector2(r * lerpf(float(STRIKE.flash_r0), float(STRIKE.flash_r1), 1.0 - (1.0 - u) * (1.0 - u)), float(STRIKE.flash_alpha) * (1.0 - u))


# ---------- 예고 목록 ----------
# 서버 이벤트 boltWarn {id, x, y, z, r, ms} → 목록에 더함 (한 항목 = {id, x, y, z, r, t0, ms}). 같은 id 가 이미 있거나 값이 빠졌으면 무시. 더했으면 true
static func warn_add(list: Array, e: Dictionary, now: float) -> bool:
	if e.get("id") == null or e.get("x") == null or e.get("y") == null:
		return false
	var id := int(e.id)
	var ms := float(e.get("ms", 0.0))
	var r := float(e.get("r", 0.0))
	if ms <= 0.0 or r <= 0.0 or warn_find(list, id) >= 0:
		return false
	list.append({"id": id, "x": float(e.x), "y": float(e.y), "z": float(e.get("z", 0.0)), "r": r, "t0": now, "ms": ms})
	return true


static func warn_find(list: Array, id: int) -> int:
	for i in list.size():
		if int(list[i].id) == id:
			return i
	return -1


# 떨어진 예고를 지움 (서버 이벤트 bolt 의 id). 모르는 id 면 그대로 두고 false
static func warn_remove(list: Array, id) -> bool:
	var i := warn_find(list, int(id)) if id != null else -1
	if i < 0:
		return false
	list.remove_at(i)
	return true


# 예정 시각 + grace_ms 가 지나도 남은 예고 (떨어졌다는 이벤트를 못 받음) 를 지움. 지운 수
static func warn_expire(list: Array, now: float) -> int:
	var n := 0
	for i in range(list.size() - 1, -1, -1):
		if now > float(list[i].t0) + float(list[i].ms) + float(WARN.grace_ms):
			list.remove_at(i)
			n += 1
	return n


# ---------- 내가 대상인가 (화면 신호 ui/bolt_alert.gd · 소리 audio.gd) ----------
# 나 (스냅샷 players[] 한 명) 가 (x, y, z) 반지름 r 고리 안인가 — 서버 Game.BoltStrike 판정과 같은 식: 수평 거리 ≤ r, 발 높이 차 ≤ ALERT.height.
# 살아서 필드에 있을 때만 (c9 리뷰 F6): 서버는 죽은 사람의 마지막 자리도 스냅샷에 보내고, 블록 마스터는 살아 있지만 필드에 없음
static func in_ring(me: Dictionary, x: float, y: float, z: float, r: float) -> bool:
	if me.is_empty() or not bool(me.get("alive", false)) or bool(me.get("master", false)) or me.get("x") == null or me.get("y") == null:
		return false
	return Vector2(x - float(me.x), y - float(me.y)).length() <= r and absf(float(me.get("z", z)) - z) <= float(ALERT.height)


# 내가 안에 있는 예고 가운데 가장 먼저 떨어질 것: {left (남은 ms, 0 이상), ms (예고 시간)}. 없으면 {}
static func alert_pick(list: Array, me: Dictionary, now: float) -> Dictionary:
	var out := {}
	for w in list:
		if not in_ring(me, float(w.x), float(w.y), float(w.z), float(w.r)):
			continue
		var left := maxf(0.0, float(w.t0) + float(w.ms) - now)
		if out.is_empty() or left < float(out.left):
			out = {"left": left, "ms": float(w.ms)}
	return out


# 떨어진 번개 (서버 이벤트 bolt) 가 내 자리인가: 맞은 사람 목록에 내가 있거나, 떨어진 고리 안에 내가 있음 (무적·경직이라 안 맞았어도 내 자리)
static func struck(me: Dictionary, e: Dictionary) -> bool:
	if me.is_empty():
		return false
	var hits = e.get("hits", [])
	if hits is Array and me.get("id") != null:
		for h in hits:
			if int(h) == int(me.id):
				return true
	if e.get("x") == null or e.get("y") == null:
		return false
	return in_ring(me, float(e.x), float(e.y), float(e.get("z", 0.0)), float(e.get("r", 0.0)))


# 판 가운데 높이 ÷ 화면 높이: 1인칭 (View.mode "first") 은 조준점 아래, 그 밖 (3인칭·하늘 시점) 은 조준점 위
static func alert_y(view_mode: String) -> float:
	return float(ALERT.y) if view_mode == "first" else float(ALERT.y_up)


# 남은 초 글자 (0.1초 단위 — 압사 경고 초 칸과 같은 꼴)
static func alert_sec(left_ms: float) -> String:
	return "%.1f초" % (maxf(0.0, left_ms) / 1000.0)


# 화면 가장자리 테 알파 (0 = 끔): 고리 안이면 edge[0] ↔ edge[1] 사이를 blink_ms 마다 깜빡, 내 자리에 떨어졌으면 (hit_t0) hit_alpha 에서 hit_ms 동안 0 으로 — 둘 중 큰 값
static func alert_edge(inside: bool, now: float, hit_t0: float) -> float:
	var k := 0.0
	if inside:
		var e: Array = ALERT.edge
		k = lerpf(float(e[0]), float(e[1]), 0.5 - 0.5 * cos(TAU * now / float(ALERT.blink_ms)))
	var t := now - hit_t0
	if t >= 0.0 and t < float(ALERT.hit_ms):
		k = maxf(k, float(ALERT.hit_alpha) * (1.0 - t / float(ALERT.hit_ms)))
	return k


# 판 중이 아니면 (판 끝·대기실·카운트다운) 예고·번개를 다 비움 — 서버도 판이 끝나면 남은 예고를 버림
static func keep(phase: String) -> bool:
	return phase == "playing"


static func _mesh(v: PackedVector3Array, vc: PackedColorArray) -> ArrayMesh:
	var nrm := PackedVector3Array()
	nrm.resize(v.size())
	nrm.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = vc
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func clear_static() -> void: # 종료 때 정적 상태를 비움 (메시 리소스를 쥔 채 엔진이 내려가지 않게)
	_warn_mesh = null
	_quad = null
