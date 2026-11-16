# 효과 순수 계산 (client/effects.js · ko.js 의 식 그대로). 시각은 ms, 좌표는 게임 좌표 (z 위). 노드 없음 → tests/test_fx.gd 가 JS 와 비교
extends RefCounted

const C := preload("res://core/config.gd")


# 흔들림 받기: 지금 남은 세기 (amp × 남은 비율) 보다 약하면 무시 (더 센 흔들림이 이김). sh = {amp, ms, until}
static func shake_take(sh: Dictionary, now: float, amp: float, ms: float) -> bool:
	var cur: float = sh.amp * ((sh["until"] - now) / sh.ms) if now < sh["until"] else 0.0
	if amp < cur:
		return false
	sh.amp = amp
	sh.ms = ms
	sh["until"] = now + ms
	return true


# 지금 흔들림 세기 (0 = 없음): 남은 비율의 제곱으로 줄어듦
static func shake_amp(sh: Dictionary, now: float) -> float:
	if now >= sh["until"]:
		return 0.0
	var k: float = (sh["until"] - now) / sh.ms
	return sh.amp * k * k


# 맞은 몸 찌그러짐 0~ (t_ms = 맞은 뒤 시간, 끝나면 -1)
static func squash(t_ms: float) -> float:
	var t := t_ms / C.FX_SQUASH_MS
	if t >= 1.0:
		return -1.0
	return sin(PI * t) * (1.0 - t) * 1.6


# 밀치기 팔 뻗음 0~1 (끝나면 -1)
static func punch(t_ms: float) -> float:
	var t := t_ms / 220.0
	if t >= 1.0:
		return -1.0
	return t / 0.3 if t < 0.3 else 1.0 - (t - 0.3) / 0.7


# 프레임 dt 에 곱할 값: 압사 히트스톱이면 거의 멈춤, 마지막 킬이면 앞 60% 느리게 → 뒤 40% 동안 원래대로. slow = {} 또는 {start, until}
static func time_scale(now: float, stop_until: float, slow: Dictionary) -> float:
	if now < stop_until:
		return C.KO_CRUSH_STOP_SCALE
	if slow.is_empty() or now >= slow["until"]:
		return 1.0
	var t: float = (now - slow.start) / (slow["until"] - slow.start)
	return C.KO_FINAL_SCALE + (1.0 - C.KO_FINAL_SCALE) * maxf(0.0, (t - 0.6) / 0.4)


# 마지막 킬 줌 세기 0 → 1 → 0
static func final_k(now: float, slow: Dictionary) -> float:
	if slow.is_empty() or now >= slow["until"]:
		return 0.0
	var t: float = (now - slow.start) / (slow["until"] - slow.start)
	return sin(minf(1.0, t) * PI)


# 스매시 줄기 자리: 떨어진 쪽 필드 끝 (안으로 자름), 높이 -1~1
static func smash_at(p: Vector3, w: float, d: float) -> Vector3:
	return Vector3(clampf(p.x, 0.0, w), clampf(p.y, 0.0, d), clampf(p.z, -1.0, 1.0))


# 줄기 방향: 떨어진 쪽 + 위로 조금
static func smash_dir(out: Dictionary) -> Vector3:
	return Vector3(out.x, out.y, C.KO_SMASH_UP).normalized()


# 줄기 모양 (t = 나이 / 수명): 빠르게 뻗고 천천히 사라짐 → Vector3(옆 크기, 길이 크기, 투명도)
static func plume(t: float) -> Vector3:
	var grow := minf(1.0, t * 4.0)
	var side := 0.4 + grow * 0.8 * (1.0 - t * 0.5)
	return Vector3(side, 0.2 + grow, 0.9 * pow(1.0 - t, 1.5))


# 그래픽 낮춤이면 파편 수 줄임
static func parts(n: float, low: bool) -> int:
	return maxi(1, roundi(n * (C.KO_LOW_GFX_PARTICLES if low else 1.0)))


# 화면 끝 번쩍 자리: 화면에 비춘 자리 (NDC -1~1, 위 +) → 가장 가까운 화면 끝, 백분율 (왼쪽 위 0). 카메라 뒤면 반대쪽
static func edge_pos(sx: float, sy: float, behind: bool) -> Vector2:
	if behind:
		sx = -sx
		sy = -sy
	var m := maxf(maxf(absf(sx), absf(sy)), 1e-6)
	sx /= m
	sy /= m
	return Vector2((sx + 1.0) / 2.0 * 100.0, (1.0 - sy) / 2.0 * 100.0)


# 화면 끝 번쩍 세기 (k = 남은 비율)
static func edge_alpha(k: float) -> float:
	return minf(1.0, k * 1.5)


# 효과 재질: 카메라에서 FX_NEAR_FADE[0] 안이면 안 보이고 [1] 까지 점점 보임. 3인칭 카메라 앞을 지나는 파편·고리·스매시 줄기 안쪽이
# 화면 반을 덮는 큰 반투명 판으로 보이던 것 (2026-10-31 B4 스샷). JS 판엔 없는 고도 쪽 보정
const FX_NEAR_FADE := [0.4, 1.6]


# dither (c6 고침 F1): 불투명 재질용 — 알파 대신 화소를 점점이 버림 (버린 화소는 깊이도 안 씀 → 흐려진 조각이 뒤 효과를 도려내지 않음). 고리·파편은 알파 흐림 그대로
static func near_fade(m: BaseMaterial3D, dither := false) -> void:
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER if dither else BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = FX_NEAR_FADE[0]
	m.distance_fade_max_distance = FX_NEAR_FADE[1]


# 화면 덮기 상한 (c6): 카메라 앞 dist 칸 (보는 방향 깊이) 에 있는 지름 size 칸짜리 효과를 화면 높이의 frac 배까지만.
# 그 깊이에서 화면 높이 = 2 × dist × tan(세로 시야각 / 2). 작은 것은 그대로, 카메라 뒤 (dist ≤ 0) 면 0
static func cap_size(size: float, dist: float, fov_deg: float, frac: float) -> float:
	return minf(size, frac * 2.0 * maxf(0.0, dist) * tan(deg_to_rad(fov_deg) / 2.0))


# 낙사 줄기를 원근 투영해 화면에 비친 크기 (÷ 화면 높이): 꼭짓점 apex 에서 축 axis 쪽으로 길이 len_m, 끝 원 지름 width_m 인 원뿔의
# 비친 길이 (꼭짓점 ~ 끝 원 가운데) 와 비친 끝 지름 (끝 원 둘레 seg 점 가운데 가장 먼 두 점 사이) 중 큰 쪽 — 상한이 재는 '줄기 길이·끝 지름 중 큰 쪽' 을 그 자리·그 방향 그대로 비춘 것.
# apex·axis = 카메라 공간 (고도 카메라: x 오른쪽 · y 위 · 보는 쪽이 −z → 깊이 = −z), axis 는 단위 벡터. 점 하나라도 카메라 가까이·뒤 (깊이 < near_m) 면 INF (화면을 넘는 것으로 침)
static func plume_span(len_m: float, width_m: float, apex: Vector3, axis: Vector3, fov_deg: float, seg: int, near_m: float) -> float:
	var tip := apex + axis * len_m
	if -apex.z < near_m or -tip.z < near_m:
		return INF
	var t := 2.0 * tan(deg_to_rad(fov_deg) / 2.0) # 깊이 1 에서 화면 높이
	var far2 := (Vector2(apex.x, apex.y) / (-apex.z * t)).distance_squared_to(Vector2(tip.x, tip.y) / (-tip.z * t))
	var u := axis.cross(Vector3.UP)
	u = u.normalized() if u.length() > 1e-6 else Vector3.RIGHT
	var v := axis.cross(u).normalized()
	var rim := PackedVector2Array()
	for i in seg:
		var ang := TAU * i / seg
		var p := tip + (u * cos(ang) + v * sin(ang)) * (width_m / 2.0)
		if -p.z < near_m:
			return INF
		rim.append(Vector2(p.x, p.y) / (-p.z * t))
	for i in rim.size():
		for j in range(i + 1, rim.size()):
			far2 = maxf(far2, rim[i].distance_squared_to(rim[j]))
	return sqrt(far2)


# 낙사 줄기 화면 상한 (c8-u3 · c8-fix F1): 줄기가 화면에 비친 크기 (plume_span: 비친 길이·비친 끝 지름 중 큰 쪽) 가 화면 높이 × frac 을 넘으면 줄이는 배율 (≤ 1 — 길이·폭에 같이 곱함, 넘지 않으면 1).
# apex·axis 는 plume_span 과 같음 (카메라 공간). 꼭짓점이 카메라 뒤·바로 앞 (깊이 < near_m) 이면 0.
# 예전 식은 줄기 전체가 밑동 깊이에서 화면과 나란히 서 있다고 보고 쟀음 → 멀어지는 줄기는 상한 안인데도 줄었음 (밑동 6 m: 배율 0.38, 맞는 배율은 1) → 실제로 비친 크기를 재고 배율을 이분법 steps 번으로 풂.
# 배율을 키우면 줄기 점마다 화면에서 꼭짓점 자리에서 멀어지기만 하고 (3D 직선의 투영은 직선) 늘 넘지 않는 쪽 값을 돌려줌. 카메라 쪽으로 오는 줄기는 끝 원이 카메라에 다가와 커지면 (또는 가까이·뒤로 가면) 거기서 멈춤.
# 화면 가운데 쪽에서 옆으로 뻗는 줄기 (화면과 나란함) 는 예전 식과 같은 값, 멀어지는·다가오는 줄기는 더 큼 (tests/test_fx.gd test_c8_plume_capped)
static func plume_cap(len_m: float, width_m: float, apex: Vector3, axis: Vector3, fov_deg: float, frac: float, seg: int, steps: int, near_m: float) -> float:
	if maxf(len_m, width_m) <= 0.0:
		return 1.0
	if -apex.z < near_m:
		return 0.0
	if plume_span(len_m, width_m, apex, axis, fov_deg, seg, near_m) <= frac:
		return 1.0
	var lo := 0.0
	var hi := 1.0
	for i in steps:
		var mid := (lo + hi) / 2.0
		if plume_span(len_m * mid, width_m * mid, apex, axis, fov_deg, seg, near_m) <= frac:
			lo = mid
		else:
			hi = mid
	return lo


# 카메라가 스매시 줄기 (꼭짓점 = 원점, 축 axis, 길이 KO_SMASH_LEN × len_k, 끝 반지름 KO_SMASH_WIDTH × side_k) 안이면 옅게 (0.2), 가장자리 1칸 안쪽에서 점점.
# 3인칭 카메라가 필드 끝에 있을 때 줄기가 화면 전체를 하얗게 덮던 것 (고도 쪽 보정, rel = 카메라 - 꼭짓점, 게임 좌표)
static func plume_inside_fade(rel: Vector3, axis: Vector3, side_k: float, len_k: float) -> float:
	var along := rel.dot(axis)
	var length := C.KO_SMASH_LEN * len_k
	if along <= 0.0 or along >= length:
		return 1.0
	var r := C.KO_SMASH_WIDTH * side_k * along / length
	var off := (rel - axis * along).length()
	var edge := minf(1.0, r) # 가장자리에서 안쪽으로 이만큼 들어가면 다 옅게 (가는 꼭짓점 쪽은 반지름만큼)
	return lerpf(0.2, 1.0, clampf((off - (r - edge)) / maxf(edge, 1e-6), 0.0, 1.0))
