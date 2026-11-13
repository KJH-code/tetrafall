# W40 외부 몸 가산 동작의 순수 계산 (노드 없음): 시선·머리 추적, 숨쉬기, 착지 숙임, 맞음 방향별 반응.
# 코드 구동·클립 층 위에 뼈 회전을 조금 더 얹을 뿐이라 서버 판정·moves 시간·figure_motion 규칙은 안 건드림. 뼈에 쓰는 일은 external.gd (Ext) 가 함.
extends RefCounted

const K := preload("res://chars/chars_config.gd")
const C := preload("res://core/config.gd")

# 판 몸 (3인칭 외부 모델) 들 — 서로 쳐다보기용 정적 목록 (죽은 노드는 쓸 때 걸러 냄)
static var bodies: Array = []

# W44 시계: 재연 (core/replay.gd) 은 가상 시계를 꽂아 느린 기계에서도 같은 시뮬 시간으로 돎. 없으면 실제 시계
static var clock: Callable = Callable()


static func now_s() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_ticks_msec() * 0.001


static func now_ms() -> float:
	return float(clock.call()) * 1000.0 if clock.is_valid() else Time.get_ticks_msec() * 1.0


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


# ---------- W43 방향 이동·기울임·방향 전환 (순수 계산) ----------

# 몸 기준 이동 (앞 mvF, 왼쪽 mvS, m/s) → 이동 방향을 앞 기준으로 접은 각 psi (라디안, + = 왼쪽) 와 '뒤로 걸음' 여부 (히스테리시스: prev_rev).
# 뒤로 걸음이면 (이동 방향이 앞에서 105° 넘게 벗어남) psi 는 뒤 방향에서 잰 각 — 다리는 거꾸로 재생하며 그 쪽으로 돌림.
static func move_fold(mv_f: float, mv_s: float, prev_rev: bool) -> Dictionary:
	var th := atan2(mv_s, mv_f) # (-π, π], 0 = 앞
	var a := absf(th)
	var rev := prev_rev
	if prev_rev:
		if a < deg_to_rad(K.EXT_DIR_REV_LEAVE_DEG):
			rev = false
	elif a > deg_to_rad(K.EXT_DIR_REV_ENTER_DEG):
		rev = true
	var psi := th
	if rev:
		psi = th - PI if th > 0.0 else th + PI
	return {"psi": psi, "rev": rev}


# 골반 yaw (라디안): 접은 이동 각 × gain, 한계 안
static func hip_yaw(psi: float) -> float:
	var lim := deg_to_rad(K.EXT_DIR_MAX_DEG)
	return clampf(psi * K.EXT_DIR_GAIN, -lim, lim)


# 앞으로 숙이는 양 (라디안, + = 앞): 속도 비례 + 가속도 (+ 가속 = 앞, − 급정지 = 뒤로 젖힘), 뒤로 걸으면 뒤로 살짝
static func lean_pitch(speed: float, acc_f: float, rev: bool, walking: bool) -> float:
	var sp := clampf(speed / maxf(0.1, float(C.MOVE_SPEED)), 0.0, 1.2)
	var p := K.EXT_LEAN_SPEED_RAD * sp if walking else 0.0
	if rev and walking:
		p = -K.EXT_LEAN_BACK_RAD * sp
	if is_finite(acc_f):
		p += clampf(acc_f * K.EXT_LEAN_ACC_K, -K.EXT_LEAN_ACC_MAX, K.EXT_LEAN_ACC_MAX)
	return p


# 이동 방향이 돌아가는 빠르기 (rad/s) → 윗몸 비틀림 (라디안, + = 왼쪽으로 돎)
static func turn_twist(rate: float) -> float:
	return clampf(rate * K.EXT_TURN_K, -K.EXT_TURN_MAX_RAD, K.EXT_TURN_MAX_RAD)


# 각 차 (-π, π] 로 접기
static func wrap_pi(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


# 달릴 때 팔 흔들림 배율: 지금 속도 / 클립이 가정한 속도 (걷기 = 0.5 MOVE_SPEED, 달리기 = MOVE_SPEED), 범위 안
static func arm_swing_scale(speed: float, run_clip: bool) -> float:
	var nominal := float(C.MOVE_SPEED) * (1.0 if run_clip else 0.5)
	return clampf(speed / maxf(0.1, nominal), K.EXT_ARM_SWING_RANGE.x, K.EXT_ARM_SWING_RANGE.y)


# ---------- W43 일어나기 (순수 계산) ----------

# 일어나기 곡선: u = 0..1 (경과 비율) → {env 들어가고 나오는 가중치, torso 윗몸 앞 숙임 (1 → 0), arm 손 짚으러 뻗음 (뻗고 → 밀고 → 놓음), step 한 발 내딛기 (종 모양)}
static func getup_curves(u: float) -> Dictionary:
	var x := clampf(u, 0.0, 1.0)
	var env := _sstep(0.0, 0.15, x) * (1.0 - _sstep(0.8, 1.0, x))
	var reach := _sstep(0.0, 0.35, x)
	var push := _sstep(0.4, 0.8, x)
	return {"env": env, "torso": 1.0 - x, "arm": reach * (1.0 - 0.8 * push), "step": sin(PI * x)}


static func _sstep(a: float, b: float, v: float) -> float:
	var t := clampf((v - a) / maxf(b - a, 1e-6), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# 래그돌 모터 세기 → 일어나기를 섞는 비율 (축 늘어진 몸 0 … 돌아온 몸 1). 래그돌 없으면 (모터 < 0 로 넘김) 1
static func getup_motor_w(motor: float) -> float:
	if motor < 0.0:
		return 1.0
	return _sstep(K.EXT_GETUP_MOTOR.x, K.EXT_GETUP_MOTOR.y, motor)


# 일어나기를 시작·계속해도 되는 상태인가 (공격·새로 맞음·다시 경직이면 끊음)
static func getup_blocked(st: Dictionary) -> bool:
	if bool(st.get("stunned", false)) or st.get("act") != null or bool(st.get("air", false)) or int(st.get("emote", -1)) >= 0 or float(st.get("victory", -1.0)) >= 0.0:
		return true
	var h = st.get("hit")
	return h is Dictionary and float(h.get("age", 9.0)) < 0.25


# ---------- W43 무기 무게·흔들림 (순수 계산) ----------

# 용수철-댐퍼 한 걸음 (반암시적 오일러): θ'' = −kθ − cθ' + input. 돌려줌 [θ, ω]
static func spring_step(theta: float, omega: float, input: float, dt: float, k: float, c: float) -> Array:
	var h := minf(dt, 1.0 / 30.0)
	var w := omega + (-k * theta - c * omega + input) * h
	var t := theta + w * h
	return [t, w]


# 가속도 (m/s²) 자르기 — 공격 휘두름·순간이동 스파이크가 무기를 날려 보내지 않게
static func clamp_acc(a: float) -> float:
	return clampf(a, -K.EXT_WEAPON_ACC_MAX, K.EXT_WEAPON_ACC_MAX) if is_finite(a) else 0.0


# 무기 흔들림을 쓸 수 있는 상태: 걷기·서기·공중 (공격·도발·승리·이모트·경직·착지 직후 맞음 아님)
static func weapon_allowed(st: Dictionary) -> bool:
	if bool(st.get("stunned", false)) or st.get("act") != null or int(st.get("emote", -1)) >= 0 or float(st.get("victory", -1.0)) >= 0.0:
		return false
	if float(st.get("recover", 0.0)) > 0.0 or float(st.get("tumble", 0.0)) > 0.0 or float(st.get("flip", -1.0)) >= 0.0 or float(st.get("airDash", 0.0)) > 0.0:
		return false
	var h = st.get("hit")
	return not (h is Dictionary and float(h.get("age", 9.0)) < 0.45)
