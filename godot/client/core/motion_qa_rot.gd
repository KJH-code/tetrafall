# W44 모션 QA 회전 계산 (motion_qa_math.gd 의 안쪽 클래스가 씀 — 안쪽 클래스는 바깥 static 함수를 못 부름)
extends RefCounted


# 두 회전 사이 각 (°, 0..180) — 작은 각도도 정확하게 (acos 안 씀)
static func ang(a: Quaternion, b: Quaternion) -> float:
	var d := a.inverse() * b
	if d.w < 0.0:
		d = Quaternion(-d.x, -d.y, -d.z, -d.w)
	var s := sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
	return rad_to_deg(2.0 * atan2(s, d.w))


# a 에서 b 로의 회전 벡터 (a 의 로컬 틀, 각도 = 크기, 단위 °)
static func rotvec(a: Quaternion, b: Quaternion) -> Vector3:
	var d := a.inverse() * b
	if d.w < 0.0:
		d = Quaternion(-d.x, -d.y, -d.z, -d.w)
	var s := sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
	if s < 1e-12:
		return Vector3.ZERO
	var a2 := 2.0 * atan2(s, d.w)
	return Vector3(d.x, d.y, d.z) / s * rad_to_deg(a2)
