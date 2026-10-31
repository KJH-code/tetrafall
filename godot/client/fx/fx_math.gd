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


static func near_fade(m: BaseMaterial3D) -> void:
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = FX_NEAR_FADE[0]
	m.distance_fade_max_distance = FX_NEAR_FADE[1]


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
