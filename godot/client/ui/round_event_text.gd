# 돌발 이벤트 알림 글 (서버 이벤트 roundEvent → 알림 한 줄, 이벤트가 시작할 때 한 번). 순수 계산 — hud_extra.gd 가 toast 로 띄움.
# 스냅샷 roundEvent (진행 중인 이벤트·남은 시간) 는 아직 화면 어디서도 안 읽음 (판 중에 들어온 사람은 진행 중인 이벤트를 모름)
# e = {kind: "rain" | "wind" | "supply", dir: {x, y} (돌풍만, 게임 좌표 단위 벡터)}
extends RefCounted


# yaw: 화면 위쪽이 향하는 게임 방향 (보는 방향 PlayerInput.yaw, 하늘 시점이면 cam_rig.sky_yaw). 돌풍 화살표에만 씀.
# 모르는 종류·방향 없는 돌풍은 "" (안 띄움)
static func text(e: Dictionary, yaw: float) -> String:
	match str(e.get("kind", "")):
		"rain":
			return "블록 폭우!"
		"supply":
			return "보급!"
		"wind":
			var a := arrow(e.get("dir"), yaw)
			return "돌풍 %s" % a if a != "" else ""
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
