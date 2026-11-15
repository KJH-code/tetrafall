# W40 외부 몸 가산 동작의 순수 계산 (노드 없음): 시선·머리 추적, 숨쉬기, 착지 숙임, 맞음 방향별 반응.
# 코드 구동·클립 층 위에 뼈 회전을 조금 더 얹을 뿐이라 서버 판정·moves 시간·figure_motion 규칙은 안 건드림. 뼈에 쓰는 일은 external.gd (Ext) 가 함.
extends RefCounted

const K := preload("res://chars/chars_config.gd")
const C := preload("res://core/config.gd")

# 판 몸 (3인칭 외부 모델) 들 — 서로 쳐다보기용 정적 목록 (죽은 노드는 쓸 때 걸러 냄)
static var bodies: Array = []

# W49 NaN 추적 (tools/nan_hunt.gd): 몸 한 프레임 (Ext.sync) 의 단계마다 (몸, 단계 이름) 으로 불림. 비어 있으면 (평소) 비용은 is_valid 한 번
static var probe: Callable = Callable()

# W44 시계: 재연 (core/replay.gd) 은 가상 시계를 꽂아 느린 기계에서도 같은 시뮬 시간으로 돎. 없으면 실제 시계
static var clock: Callable = Callable()


static func now_s() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_ticks_msec() * 0.001


static func now_ms() -> float:
	return float(clock.call()) * 1000.0 if clock.is_valid() else Time.get_ticks_msec() * 1.0


# W49 모션 가산 층 켬·끔 (설정 창·실행 인자 → chars_config.gd flag). 꺼진 층은 비용 0 으로 건너뜀
static func flag(name: String) -> bool:
	return K.flag(name)


# 영벡터 가드: 점이 겹치면 normalized() 가 "cannot be normalized"·Quaternion(a, b) 가 "must be normalized" 를 프레임마다 찍음 (재연 20MB 로그, 로그 출력 자체가 CPU 비용).
# 길이 제곱이 SAFE_EPS2 보다 작으면 fallback (직전·쉬는 방향) 을 돌려줌. 정상일 땐 v.normalized() 와 같은 값
const SAFE_EPS2 := 1e-8


static func safe_dir(v: Vector3, fallback: Vector3) -> Vector3:
	return v.normalized() if v.length_squared() > SAFE_EPS2 else fallback


# 회전으로 쓸 수 있는 basis 인가: 세 열 길이² 가 모두 유한하고 SAFE_EPS2 보다 큼 (영 스케일·NaN·inf 는 거짓 — NaN 은 '< eps' 비교가 거짓이라 따로 걸러야 함)
static func basis_ok(b: Basis) -> bool:
	var lx := b.x.length_squared()
	var ly := b.y.length_squared()
	var lz := b.z.length_squared()
	return is_finite(lx + ly + lz) and lx > SAFE_EPS2 and ly > SAFE_EPS2 and lz > SAFE_EPS2


# W49 NaN·inf 를 기본값으로 (입력 값이 깨져도 가산 층이 NaN 을 뼈에 쓰지 않게 — tools/nan_fuzz.gd 가 찾은 입구)
static func fin(x: float, d := 0.0) -> float:
	return x if is_finite(x) else d


# 단위 사원수로 쓸 수 있나 (모든 성분이 유한하고 길이가 1 근처)
static func quat_ok(q: Quaternion) -> bool:
	var l2 := q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
	return is_finite(l2) and absf(l2 - 1.0) < 0.05


# W52 길 이어 슬러프: Quaternion.slerp 는 매번 짧은 쪽 호를 골라서 (a·b 부호로), 크로스페이드 도중 목표가 움직여 a·b 가 0 을 지나면 호가 갑자기 반대쪽으로 뒤집혀 한 프레임에 최대 180° 튐
# (닌자 표창 → 대시: 오른팔 129°). 목표 b 의 부호를 앞 프레임 ref (같은 페이드 안 지난 프레임 값) 와 같은 쪽으로 고정하고 (ref 가 영이면 a 와 같은 쪽 = 짧은 호로 시작),
# 뒤집지 않는 슬러프를 씀 → 페이드 안에서 연속. 돌려줌 [섞은 사원수, 쓴 b (다음 프레임 ref)]
static func slerp_cont(a: Quaternion, b: Quaternion, t: float, ref: Quaternion) -> Array:
	var rf := ref if (ref.x != 0.0 or ref.y != 0.0 or ref.z != 0.0 or ref.w != 0.0) else a
	var bb := b if b.dot(rf) >= 0.0 else -b
	var c := clampf(a.dot(bb), -1.0, 1.0)
	var out: Quaternion
	if absf(c) > 0.9995:
		out = Quaternion(lerpf(a.x, bb.x, t), lerpf(a.y, bb.y, t), lerpf(a.z, bb.z, t), lerpf(a.w, bb.w, t)).normalized()
	else:
		var th := acos(c)
		var s := sin(th)
		var wa := sin((1.0 - t) * th) / s
		var wb := sin(t * th) / s
		out = Quaternion(a.x * wa + bb.x * wb, a.y * wa + bb.y * wb, a.z * wa + bb.z * wb, a.w * wa + bb.w * wb).normalized()
	return [out, bb]


# W52 크로스페이드 길이: 기본 길이 base (초) 와 시작점 ↔ 지금 클립 자세의 가장 큰 뼈 차이 dist_deg 로. 차이가 EXT_FADE_ADAPT_DPS 도/초 × base 를 넘으면 그 비율로 늘림 (상한 EXT_FADE_ADAPT_MAX_S)
static func fade_len_for(base: float, dist_deg: float) -> float:
	return clampf(maxf(base, dist_deg / K.EXT_FADE_ADAPT_DPS), base, maxf(base, K.EXT_FADE_ADAPT_MAX_S))


# a → b 최단 회전. 둘 중 하나가 영벡터에 가까우면 회전 없음 (항등)
static func rot_between(a: Vector3, b: Vector3) -> Quaternion:
	if a.length_squared() <= SAFE_EPS2 or b.length_squared() <= SAFE_EPS2:
		return Quaternion.IDENTITY
	return Quaternion(a.normalized(), b.normalized())


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
	var dx: float = fin(float(hit.get("dx", 0.0))) # W49: 깨진 값 (NaN·inf) 은 0 — 움찔 수식이 NaN 을 뼈에 쓰던 입구
	var dy: float = fin(float(hit.get("dy", 0.0)))
	var pw: float = fin(float(hit.get("pow", 1.0)), 1.0)
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
	var lim := deg_to_rad(K.dir_max_deg())
	return clampf(psi * K.dir_gain(), -lim, lim)


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
