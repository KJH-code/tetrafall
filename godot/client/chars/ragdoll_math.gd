# 액티브 래그돌 순수 계산 (JS client/ragdoll-math.js 그대로, 테스트 tests/test_chars.gd ↔ fixtures/ragdoll_math.json).
# 벡터는 게임 좌표 Vector3 (위 +z), 쿼터니언은 Quaternion (x, y, z, w)
extends RefCounted

const C := preload("res://core/config.gd")


static func _ease(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# 모터 세기 (0~): 평소 1, 공격 중 세게, 맞은 직후·경직·낙사 중엔 힘이 빠짐. snap = 화면 자세를 목표 자세로 섞는 비율
# st: {stunned, sinceStun (경직이 풀린 지 초, 없으면 INF), hitAge (맞은 지 초, 없으면 null), falling, act ('wind'·'strike'·'rec'·'pose' 또는 null)}
static func motor(st: Dictionary) -> Dictionary:
	var m := 1.0
	var snap := 0.0
	var act = st.get("act")
	if act == "wind" or act == "strike":
		m = C.RAGDOLL_MOTOR_ATTACK
		snap = C.RAGDOLL_ATTACK_SNAP
	elif act == "rec":
		m = C.RAGDOLL_MOTOR_ATTACK
	elif act == "pose":
		m = C.RAGDOLL_MOTOR_ATTACK
		snap = C.RAGDOLL_POSE_SNAP
	var ha = st.get("hitAge")
	if ha != null and float(ha) < C.RAGDOLL_HIT_RECOVER_S:
		m = minf(m, C.RAGDOLL_HIT_MOTOR + (1.0 - C.RAGDOLL_HIT_MOTOR) * _ease(float(ha) / C.RAGDOLL_HIT_RECOVER_S))
		snap = 0.0
	var ss = st.get("sinceStun")
	if ss != null and is_finite(float(ss)) and float(ss) < C.RAGDOLL_STUN_RECOVER_S:
		m = minf(m, C.RAGDOLL_STUN_MOTOR + (1.0 - C.RAGDOLL_STUN_MOTOR) * _ease(float(ss) / C.RAGDOLL_STUN_RECOVER_S))
	if st.get("stunned", false):
		m = minf(m, C.RAGDOLL_STUN_MOTOR)
		snap = 0.0
	if st.get("falling", false):
		m = minf(m, C.RAGDOLL_FALL_MOTOR)
		snap = 0.0
	return {"motor": m, "snap": snap}


# 쿼터니언 차이 q·conj(b) 를 회전 벡터 (축 × 각, 짧은 쪽) 로
static func quat_diff_vec(q: Quaternion, b: Quaternion) -> Vector3:
	var bx := -b.x
	var by := -b.y
	var bz := -b.z
	var bw := b.w
	var x := q.w * bx + q.x * bw + q.y * bz - q.z * by
	var y := q.w * by - q.x * bz + q.y * bw + q.z * bx
	var z := q.w * bz + q.x * by - q.y * bx + q.z * bw
	var w := q.w * bw - q.x * bx - q.y * by - q.z * bz
	if w < 0.0:
		x = -x
		y = -y
		z = -z
		w = -w
	var s := sqrt(x * x + y * y + z * z)
	if s < 1e-9:
		return Vector3(2.0 * x, 2.0 * y, 2.0 * z)
	var ang := 2.0 * atan2(s, w)
	return Vector3(x / s * ang, y / s * ang, z / s * ang)


# 관절 모터: 지금 자세 q·각속도 w 에서 목표 t (목표 각속도 tw) 로 가는 각가속도. 목표 각속도도 따라감 (feed-forward)
static func pd_angular(q: Quaternion, t: Quaternion, w: Vector3, tw: Vector3, m: float) -> Vector3:
	var e := quat_diff_vec(t, q)
	var kp: float = C.RAGDOLL_KP * m
	var kd: float = C.RAGDOLL_KD * sqrt(maxf(0.0, m))
	var f := minf(1.0, m)
	return kp * e + kd * (tw * f - w)


# 골반: 판정 (보간) 위치 t 로 스프링 (중력 보정 포함), 너무 멀면 snap. 힘이 빠지면 RAGDOLL_SLUMP 까지 아래로 처져도 봐줌 (쓰러져 누움)
static func root_pull(p: Vector3, v: Vector3, t: Vector3, tv: Vector3, m := 1.0) -> Dictionary:
	var slump: float = C.RAGDOLL_SLUMP * (1.0 - clampf(m, 0.0, 1.0))
	var dx := t.x - p.x
	var dy := t.y - p.y
	var dz := t.z - p.z
	if dz > 0.0:
		dz = maxf(0.0, dz - slump)
	if sqrt(dx * dx + dy * dy + dz * dz) > C.RAGDOLL_MAX_DRIFT:
		return {"snap": true, "a": Vector3.ZERO}
	var kp: float = C.RAGDOLL_ROOT_KP
	var kd: float = C.RAGDOLL_ROOT_KD
	var lift: float = 1.0 - slump / maxf(1e-6, C.RAGDOLL_SLUMP if C.RAGDOLL_SLUMP != 0.0 else 1.0)
	return {"snap": false, "a": Vector3(kp * dx + kd * (tv.x - v.x), kp * dy + kd * (tv.y - v.y), kp * dz + kd * (tv.z - v.z) * lift + C.RAGDOLL_GRAVITY * maxf(C.RAGDOLL_LIMP_LIFT, lift))}


# 팔다리·몸통 조각: 자기 목표 위치로 (모터 세기만큼, 중력 보정도 세기만큼)
static func limb_pull(p: Vector3, v: Vector3, t: Vector3, tv: Vector3, m: float) -> Vector3:
	var kp: float = C.RAGDOLL_LIN_KP * m
	var kd: float = C.RAGDOLL_LIN_KD * sqrt(maxf(0.0, m))
	var f := minf(1.0, m)
	return kp * (t - p) + kd * (tv * f - v) + Vector3(0, 0, C.RAGDOLL_GRAVITY * f)
