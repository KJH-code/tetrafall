# 게임 좌표 ↔ 고도 좌표, 색 (모든 묶음 공용, G0 가 가짐).
# 게임: x, y 바닥 격자 · z 위 · 한 칸 = 1 · yaw 0 = +x, 반시계 (JS 판 그대로). 고도: y 위 → Vector3(x, z, -y)
# (x 축으로 −90° 돌림 = 손잡이 그대로. (x, z, y) 는 반사라 화면이 JS 와 좌우 거울이 됨)
# 주의: 고도 Vector3 는 32비트 float. 서버 시각(ms)·누적 값은 float 변수(64비트)로
extends RefCounted


static func gpos(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


static func gxyz(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


# 고도 → 게임 (gpos 의 반대)
static func game(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)


# 고도 좌표 → 게임 (x, y 바닥 · z 위)
static func game(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, v.y)


# 고도 카메라 (Node3D) 가 바라보는 쪽 → 게임 yaw
static func yaw_of(n: Node3D) -> float:
	var f := -n.global_transform.basis.z
	return atan2(f.z, f.x)


# 게임 yaw → 고도 Node3D rotation.y (+x 를 보던 몸이 yaw 방향을 봄)
static func rot_y(yaw: float) -> float:
	return yaw


# 게임 방향 (yaw, pitch) → 고도 단위 벡터
static func dir(yaw: float, pitch: float = 0.0) -> Vector3:
	return Vector3(cos(yaw) * cos(pitch), sin(pitch), -sin(yaw) * cos(pitch))


# config 의 0xRRGGBB 숫자 (PLAYER_PALETTE·테마 색) → Color
static func color(c) -> Color:
	var i := int(c)
	return Color8((i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff)
