# W40 외부 몸 가산 동작의 순수 계산 (노드 없음): 시선·머리 추적, 숨쉬기, 착지 숙임, 맞음 방향별 반응.
# 코드 구동·클립 층 위에 뼈 회전을 조금 더 얹을 뿐이라 서버 판정·moves 시간·figure_motion 규칙은 안 건드림. 뼈에 쓰는 일은 external.gd (Ext) 가 함.
extends RefCounted

const K := preload("res://chars/chars_config.gd")

# 판 몸 (3인칭 외부 모델) 들 — 서로 쳐다보기용 정적 목록 (죽은 노드는 쓸 때 걸러 냄)
static var bodies: Array = []


# 몸 기준 (앞 +x, 오른쪽 +z) 좌표 → 위(Y) 축 회전 각 (라디안, 왼쪽으로 돌려야 하면 +). 고도 Y 회전은 +x 를 -z 쪽으로 돎
static func yaw_to(local: Vector3) -> float:
	return atan2(-local.z, local.x)


# 시선 목표 고르기: others = 몸 기준 좌표 목록 (다른 몸의 머리 높이 자리). 가장 가까운 것 (max_dist 안, 정면 ±fov 안) 의 yaw·거리, 없으면 {}.
static func pick_target(others: Array, max_dist: float, fov: float) -> Dictionary:
	var best := {}
	var bd := 1e9
	for o in others:
		var v: Vector3 = o
		var d := Vector2(v.x, v.z).length()
		if d < 0.2 or d > max_dist:
			continue
		var y := yaw_to(v)
		if absf(y) > fov:
			continue
		if d < bd:
			bd = d
			best = {"yaw": y, "dist": d}
	return best


# 한계 각 (도) 로 자른 목표 yaw (라디안)
static func clamp_yaw(y: float, lim_deg: float) -> float:
	var lim := deg_to_rad(lim_deg)
	return clampf(y, -lim, lim)


# 부드럽게 따라가기 (프레임 독립 지수)
static func follow(cur: float, target: float, dt: float, rate: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-rate * dt))


# 시선을 쓸 수 있는 상태인가 (맞음·경직·낙사·도발·승리·공격 중에는 끔 — 코드·클립이 얼굴 방향을 정함)
static func gaze_allowed(st: Dictionary) -> bool:
	if bool(st.get("stunned", false)) or float(st.get("recover", 0.0)) > 0.0 or float(st.get("tumble", 0.0)) > 0.0 or float(st.get("flip", -1.0)) >= 0.0:
		return false
	if float(st.get("dizzy", 0.0)) > 0.0 or float(st.get("whirl", -1.0)) >= 0.0 or float(st.get("airDash", 0.0)) > 0.0 or bool(st.get("glide", false)):
		return false
	if int(st.get("emote", -1)) >= 0 or float(st.get("victory", -1.0)) >= 0.0 or st.get("act") != null:
		return false
	var h = st.get("hit")
	if h is Dictionary and float(h.get("age", 9.0)) < K.EXT_GAZE_HIT_OFF_S:
		return false
	return true


# 캐릭터마다 다른 숨쉬기 위상·주기: id 글자에서 (같은 캐릭터는 늘 같은 값)
static func breath_phase(id: String) -> float:
	var h := 0
	for c in id.to_utf8_buffer():
		h = (h * 31 + c) & 0xffff
	return float(h % 628) / 100.0


static func breath_period(id: String) -> float:
	var h := 0
	for c in id.to_utf8_buffer():
		h = (h * 17 + c) & 0xffff
	return lerpf(K.EXT_BREATH_PERIOD.x, K.EXT_BREATH_PERIOD.y, float(h % 100) / 100.0)


# 숨쉬기 세기 (-1..1, 들숨이 +): 서 있고 아무것도 안 할 때만 (w 는 부드럽게 켜고 끄는 가중치는 호출 쪽)
static func breath(t: float, id: String) -> float:
	return sin(TAU * t / breath_period(id) + breath_phase(id))


# 숨쉬기를 쓸 수 있는 상태인가: 걷지 않고 공중이 아니고 공격·맞음·특수 자세가 아님
static func breath_allowed(st: Dictionary) -> bool:
	if bool(st.get("walking", false)) or bool(st.get("air", false)) or st.get("act") != null or st.get("hit") is Dictionary:
		return false
	if bool(st.get("stunned", false)) or float(st.get("recover", 0.0)) > 0.0 or float(st.get("tumble", 0.0)) > 0.0 or float(st.get("flip", -1.0)) >= 0.0:
		return false
	return int(st.get("emote", -1)) < 0 and float(st.get("victory", -1.0)) < 0.0


# 착지 숙임 세기 0..1: st.land (그 프레임 남은 비율 × 충격) 를 그대로 쓰되 상한
static func land_amount(st: Dictionary) -> float:
	return clampf(float(st.get("land", 0.0)), 0.0, 1.0)


# 맞음 방향별: 앞에서 맞음 (dx < 0, 뒤로 밀림) = 윗몸 뒤로 젖힘, 뒤에서 맞음 (dx > 0) = 앞으로 숙임 + 어깨 움츠림, 옆 = 몸통 비틀림 (맞은 쪽 반대로) + 기울기.
# 돌려줌 {back (z 축, +뒤로), side (x 축 기울기), twist (y 축 비틂), whip (치명이면 머리 채찍 진동), hand (무기 쥔 손 흔들림)} — 세기 amp 는 호출 쪽 (hit.pow·감쇠)
static func hit_react(hit: Dictionary) -> Dictionary:
	var dx: float = float(hit.get("dx", 0.0))
	var dy: float = float(hit.get("dy", 0.0))
	var pw: float = float(hit.get("pow", 1.0))
	var crit := pw >= K.EXT_HIT_CRIT_POW
	return {"back": -dx, "side": dy, "twist": -dy * K.EXT_HIT_TWIST, "front_hit": dx < -0.35, "back_hit": dx > 0.35, "crit": crit}
