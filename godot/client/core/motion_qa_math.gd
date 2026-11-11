# W44 모션 QA 순수 계산 (노드·엔진 상태 없음 — 합성 뼈 열로 검출기를 시험함, tests/test_motion_qa.gd).
# 단위: 각도는 도(°), 길이는 m, 표본은 60Hz 한 칸 ('프레임'). 검출기는 한 표본씩 먹이는 (streaming) 모양이라 재연 전체 (core/motion_qa.gd) 와
# 판 중 가벼운 카운터 (--motion-qa) 가 같은 코드를 씀.
extends RefCounted

const R := preload("res://core/motion_qa_rot.gd")
const HZ := 60.0 # 표본 빠르기 (표본 사이 1/HZ 초). 임계는 이 표본 한 칸당

# ---- 임계 (표본 한 칸당 °, 지시서 W44 기준) ----
const POP_TORSO := 35.0 # 몸통·팔다리 뼈 (Hips·Spine·어깨·팔·다리)
const POP_END := 60.0 # 손·발·머리·목
const POP_CLOTH := 80.0 # 천 사슬 (물리라 더 빠름)
const POP_SOFT_K := 0.5 # '약한 팝' 보조 지표 = 임계 × 이 값
const JIT_WIN := 30 # 떨림 창 (표본 수, 0.5초)
const JIT_RMS := 0.25 # 창 안 각가속도 RMS (°/표본²) 가 이 이상이고
const JIT_FLIP := 0.35 # 속도 방향이 뒤집힌 표본 비율이 이 이상이면 떨림 창
const JIT_MIN_V := 0.03 # 이보다 느린 속도의 뒤집힘은 안 셈 (°/표본)
const SLIDE_LIFT := 0.025 # 발이 '땅에 닿음' 높이 (m, 서 있을 때 발 높이보다 위로)
const SLIDE_MIN_RUN := 3 # 닿음이 이 표본 이상 이어져야 한 번의 디딤
const SLIDE_MOVE_MIN := 0.12 # 몸이 이만큼 (m) 이상 가는 디딤은 '걸음' (비 = 발 끌림 ÷ 몸 이동)
const SLIDE_BAD_RATIO := 0.35 # 걸음 디딤에서 이 비를 넘으면 미끄러짐
const SLIDE_IDLE_BAD := 0.04 # 거의 안 가는 디딤 (몸 이동 < 0.05) 에서 발이 이만큼 (m) 끌리면 '정지 중 끌림'
const SUNK_LIFT := -0.03 # 접지 발이 서 있는 높이보다 이만큼 아래 (m) = 박힘
const FLOAT_LIFT := 0.05 # 땅에 있는 상태에서 두 발 모두 이만큼 위 = 뜸
const PEN_MIN := 0.02 # 몸 캡슐 안으로 이만큼 (m) 이상 들어가면 뚫림 (쉬는 자세 값을 뺀 뒤)
const STRETCH_MAX := 2.2 # 삼각형 변 길이 / 쉬는 길이 가 이 이상 = 늘어남
const STRETCH_MIN := 0.3 # 이 이하 = 찌그러짐
const ELBOW_REV := -25.0 # 팔꿈치·무릎이 자연 굽힘 반대로 이만큼 (°) 넘게 = 반대 굽힘
const FLEX_MAX := 165.0 # 한계 넘게 접힘
const NECK_TWIST := 70.0 # 목 (목+머리) 비틀림 한계
const SPINE_SUM := 80.0 # 척추 (Spine·Spine1·Spine2) 누적 회전 한계 (쉬는 자세 기준)
const SEAM_WIN := 15 # 전환 뒤 이 표본 동안 최고 각속도를 봄 (0.25초)
const FLICKER_S := 0.25 # 상태가 이만큼 (초) 안에 다시 바뀌면 깜빡임


# ---------- 회전 ----------

static func ang(a: Quaternion, b: Quaternion) -> float:
	return R.ang(a, b)


static func rotvec(a: Quaternion, b: Quaternion) -> Vector3:
	return R.rotvec(a, b)


# 비틀림 (축 둘레 회전) 각 °: d 를 축 둘레 (twist) 와 나머지 (swing) 로 가를 때 twist 부분의 부호 있는 각
static func twist_deg(d: Quaternion, axis: Vector3) -> float:
	var ax := axis.normalized()
	var v := Vector3(d.x, d.y, d.z)
	var proj := ax * v.dot(ax)
	var tw := Quaternion(proj.x, proj.y, proj.z, d.w)
	if tw.length() < 1e-9:
		return 180.0
	tw = tw.normalized()
	var a := rad_to_deg(2.0 * atan2(Vector3(tw.x, tw.y, tw.z).dot(ax), tw.w))
	if a > 180.0:
		a -= 360.0
	elif a < -180.0:
		a += 360.0
	return a


# 뼈 이름 → 검출 종류. torso·limb 는 POP_TORSO, end 는 POP_END, cloth 는 별도, skip 은 안 봄 (손가락·끝 뼈)
static func bone_class(n: String) -> String:
	var s := n.trim_prefix("mixamorig_")
	for f in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		if s.contains(f):
			return "skip"
	if s.ends_with("_End"):
		return "skip"
	for f in ["Scarf", "Cape", "Skirt", "Tabard"]:
		if s.begins_with(f):
			return "cloth"
	if s in ["Hips", "Spine", "Spine1", "Spine2"]:
		return "torso"
	if s in ["Head", "Neck"] or s.ends_with("Hand") or s.ends_with("Foot") or s.ends_with("ToeBase"):
		return "end"
	if s.ends_with("Shoulder") or s.ends_with("Arm") or s.ends_with("ForeArm") or s.ends_with("UpLeg") or s.ends_with("Leg"):
		return "limb"
	return "skip"


static func pop_thr(cls: String) -> float:
	match cls:
		"end":
			return POP_END
		"cloth":
			return POP_CLOTH
	return POP_TORSO


# ---------- 팝 (프레임 간 불연속) ----------
# 한 뼈의 회전 열을 먹이면 표본마다 각속도 (°/표본) 와 '새로 임계를 넘은 순간' (위로 올라가는 모서리) 을 알려 줌
class PopDet:
	var thr := 35.0
	var soft_k := 0.5
	var prev: Quaternion
	var w_prev := 0.0
	var have := false
	var over := false
	var soft_over := false

	func _init(thr_ := 35.0, soft_k_ := 0.5) -> void:
		thr = thr_
		soft_k = soft_k_

	func reset() -> void:
		have = false
		over = false
		soft_over = false
		w_prev = 0.0

	# 돌려줌 {w: 각속도, pop: 새로 임계 넘음, soft: 새로 약한 임계 넘음, jerk: |w - 앞 w|}. scale = (1/HZ) / 실제 간격 (간격이 어긋나면 °/표본으로 환산)
	func feed(q: Quaternion, scale := 1.0) -> Dictionary:
		if not have:
			prev = q
			have = true
			w_prev = 0.0
			over = false
			soft_over = false
			return {"w": 0.0, "pop": false, "soft": false, "jerk": 0.0}
		var w: float = R.ang(prev, q) * scale
		prev = q
		var is_over := w > thr
		var is_soft := w > thr * soft_k
		var out := {"w": w, "pop": is_over and not over, "soft": is_soft and not soft_over, "jerk": absf(w - w_prev)}
		over = is_over
		soft_over = is_soft
		w_prev = w
		return out


# ---------- 떨림 ----------
# 한 뼈의 회전 열 → 속도 벡터 (rotvec, °/표본) → 창 (JIT_WIN 표본) 마다 각가속도 RMS 와 방향 뒤집힘 비율
class JitDet:
	var prev: Quaternion
	var have := false
	var v_prev := Vector3.ZERO
	var have_v := false
	var sum2 := 0.0
	var flips := 0
	var steps := 0

	func reset() -> void:
		have = false
		have_v = false
		sum2 = 0.0
		flips = 0
		steps = 0

	# 창이 다 차면 {rms, flip} 을 돌려줌, 아니면 {}
	func feed(q: Quaternion) -> Dictionary:
		if not have:
			prev = q
			have = true
			return {}
		var v: Vector3 = R.rotvec(prev, q)
		prev = q
		if not have_v:
			v_prev = v
			have_v = true
			return {}
		var a := (v - v_prev).length()
		sum2 += a * a
		steps += 1
		if v.length() > JIT_MIN_V and v_prev.length() > JIT_MIN_V and v.dot(v_prev) < 0.0:
			flips += 1
		v_prev = v
		if steps >= JIT_WIN:
			var out := {"rms": sqrt(sum2 / float(steps)), "flip": float(flips) / float(steps)}
			sum2 = 0.0
			flips = 0
			steps = 0
			return out
		return {}


static func jitter_bad(win: Dictionary) -> bool:
	return not win.is_empty() and float(win.rms) > JIT_RMS and float(win.flip) > JIT_FLIP


# ---------- 발 미끄러짐 ----------
# 발 하나: 매 표본 (발 월드 xz, 발 들림 높이, 몸 월드 xz) 을 먹임. 닿은 상태가 끝나면 한 번의 디딤 {len, slide, body, ratio, peak}
class SlideDet:
	var planted := false
	var run := 0
	var foot_prev := Vector2.ZERO
	var body_prev := Vector2.ZERO
	var slide := 0.0
	var body := 0.0
	var peak_step := 0.0

	func reset() -> void:
		planted = false
		run = 0
		slide = 0.0
		body = 0.0
		peak_step = 0.0

	func _done() -> Dictionary:
		if run >= SLIDE_MIN_RUN:
			return {"len": run, "slide": slide, "body": body, "ratio": slide / body if body > 1e-6 else 0.0, "peak": peak_step}
		return {}

	# 끝난 디딤 (길이가 충분할 때만) 을 돌려줌, 아니면 {}
	func feed(foot: Vector2, lift: float, body_xz: Vector2, grounded := true) -> Dictionary:
		var now_pl: bool = grounded and lift < SLIDE_LIFT
		var out := {}
		if now_pl and planted:
			var step := (foot - foot_prev).length()
			slide += step
			body += (body_xz - body_prev).length()
			peak_step = maxf(peak_step, step)
			run += 1
		elif now_pl and not planted:
			planted = true
			run = 1
			slide = 0.0
			body = 0.0
			peak_step = 0.0
		elif not now_pl and planted:
			out = _done()
			planted = false
			run = 0
		foot_prev = foot
		body_prev = body_xz
		return out

	func flush() -> Dictionary:
		var out := _done() if planted else {}
		reset()
		return out


# ---------- 뚫림 ----------
# 점 p 가 캡슐 (선분 a–b, 반지름 r) 안으로 들어간 깊이 (m, 밖이면 0)
static func capsule_depth(p: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-12 else 0.0
	var d := p.distance_to(a + ab * t)
	return maxf(0.0, r - d)


# 신축 비 (현재 길이 / 쉬는 길이)
static func stretch_ratio(a: Vector3, b: Vector3, rest_len: float) -> float:
	return a.distance_to(b) / maxf(rest_len, 1e-9)


# ---------- 관절 한계 ----------
# 경첩 축 (팔꿈치·무릎): 로컬 회전 벡터들 (°, 쉬는 자세 기준) 의 합 방향 = 자연 굽힘 방향. 돌려줌 단위 벡터 (없으면 ZERO)
static func hinge_axis(vecs: Array) -> Vector3:
	var s := Vector3.ZERO
	for v in vecs:
		s += v as Vector3
	return s.normalized() if s.length() > 1e-6 else Vector3.ZERO


# 경첩 굽힘 (°): 회전 벡터를 경첩 축에 내린 길이 (+ = 자연 굽힘, − = 반대) 와, 축에서 벗어난 몫 (옆으로 비틀림·꺾임)
static func hinge_flex(rv: Vector3, axis: Vector3) -> Dictionary:
	var f := rv.dot(axis)
	return {"flex": f, "off": (rv - axis * f).length()}


# 한계 검사: 위반 목록 [{kind, value}] (rev 반대 굽힘 · over 과굽힘 · neck 목 비틂 · spine 척추 누적)
static func limit_flags(flex: float, neck_twist: float, spine_sum: float) -> Array:
	var out := []
	if flex < ELBOW_REV:
		out.append({"kind": "rev", "value": flex})
	if flex > FLEX_MAX:
		out.append({"kind": "over", "value": flex})
	if absf(neck_twist) > NECK_TWIST:
		out.append({"kind": "neck", "value": neck_twist})
	if spine_sum > SPINE_SUM:
		out.append({"kind": "spine", "value": spine_sum})
	return out


# ---------- 요약 도움 ----------
static func pct(vals: Array, p: float) -> float:
	if vals.is_empty():
		return 0.0
	var s := vals.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(float(s.size()) * p))])


static func mean(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var t := 0.0
	for v in vals:
		t += float(v)
	return t / float(vals.size())
