# 돌발 이벤트 알림 글 (서버 이벤트 roundEvent → 알림 한 줄, 이벤트가 시작할 때 한 번). 순수 계산 — hud_extra.gd 가 toast 로 띄움.
# 스냅샷 roundEvent (진행 중인 이벤트·남은 시간) 는 status 가 한 줄로 — hud_extra.gd refresh 가 끝날 때까지 위 가운데 띠에 (판 중에 들어온 사람도 봄)
# e = {kind: "rain" | "wind" | "supply" | "lowgrav" | "ice" | "bolt", dir: {x, y} (돌풍만, 게임 좌표 단위 벡터)}
extends RefCounted


# yaw: 화면 위쪽이 향하는 게임 방향 (view_yaw). 돌풍 화살표에만 씀.
# 모르는 종류·방향 없는 돌풍은 "" (안 띄움)
static func text(e: Dictionary, yaw: float) -> String:
	match str(e.get("kind", "")):
		"rain":
			return "블록 폭우!"
		"supply":
			return "보급!"
		"lowgrav":
			return "저중력! 높이 뛰고 멀리 날아감"
		"ice":
			return "빙판! 맞으면 멀리 미끄러짐"
		"bolt":
			return "번개! 바닥 고리 밖으로"
		"wind":
			var a := arrow(e.get("dir"), yaw)
			return "돌풍 %s" % a if a != "" else ""
	return ""


# 진행 중인 이벤트 띠 글: ev = 스냅샷 roundEvent {kind, left (남은 ms), dir} 또는 null. 남은 초는 올림 (0.3초 남아도 1초).
# 진행 중이 아님 (null·left 0 이하)·보급 (한 번에 끝남)·모르는 종류·방향 없는 돌풍은 "" (띠 숨김). 돌풍 화살표는 매번 보는 방향 기준
static func status(ev, yaw: float) -> String:
	if not (ev is Dictionary):
		return ""
	var left := float(ev.get("left", 0.0)) if ev.get("left") != null else 0.0
	if left <= 0.0:
		return ""
	var n := int(ceil(left / 1000.0))
	match str(ev.get("kind", "")):
		"rain":
			return "블록 폭우 %d초" % n
		"lowgrav":
			return "저중력 %d초" % n
		"ice":
			return "빙판 %d초" % n
		"bolt":
			return "번개 %d초" % n
		"wind":
			var a := arrow(ev.get("dir"), yaw)
			return "돌풍 %s %d초" % [a, n] if a != "" else ""
	return ""


# 돌풍 방향 화살표: 게임 (x, y) 방향을 보는 사람 기준으로 (몸이 밀리는 쪽이 화면에서 어느 쪽인지).
# yaw 는 반시계, 앞 = (cos yaw, sin yaw), 오른쪽 = (sin yaw, -cos yaw) (world/cam_rig.gd place). 앞·옆 중 큰 쪽 하나만
static func arrow(dir, yaw: float) -> String:
	if not (dir is Dictionary):
		return ""
	var dx := float(dir.get("x", 0.0))
	var dy := float(dir.get("y", 0.0))
	if is_zero_approx(dx) and is_zero_approx(dy):
		return ""
	var fwd := dx * cos(yaw) + dy * sin(yaw)
	var right := dx * sin(yaw) - dy * cos(yaw)
	if absf(right) >= absf(fwd):
		return "→" if right > 0.0 else "←"
	return "↑" if fwd > 0.0 else "↓"


# 화면 위쪽이 향하는 게임 방향 (world/cam_rig.gd place 와 같은 순서). 해당 없으면 null 을 넘김
# sky_yaw: 하늘 시점이면 cam_rig.sky_yaw (맨 뒤에 섞여 다른 카메라를 덮음)
# close_yaw: 클로즈업 (이모트 셀카·승자) 대상의 몸 yaw — 카메라가 몸 앞에서 돌아보니 화면 앞쪽은 반대 (victory_camera)
# look_yaw: 그 밖 (1·3인칭·관전) 은 보는 방향 PlayerInput.yaw
static func view_yaw(look_yaw: float, sky_yaw = null, close_yaw = null) -> float:
	if sky_yaw != null:
		return float(sky_yaw)
	if close_yaw != null:
		return float(close_yaw) + PI
	return look_yaw
