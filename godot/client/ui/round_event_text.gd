# 돌발 이벤트 알림 글 (서버 이벤트 roundEvent · 스냅샷 roundEvent → HUD 한 줄). 순수 계산 — hud_extra.gd 가 toast 로 띄움.
# e = {kind: "rain" | "wind" | "supply", dir: {x, y} (돌풍만, 게임 좌표 단위 벡터)}
extends RefCounted

const Coords := preload("res://core/coords.gd")


# 모르는 종류·방향 없는 돌풍은 "" (안 띄움)
static func text(e: Dictionary) -> String:
	match str(e.get("kind", "")):
		"rain":
			return "블록 폭우!"
		"supply":
			return "보급!"
		"wind":
			var a := arrow(e.get("dir"))
			return "돌풍 %s" % a if a != "" else ""
	return ""


# 돌풍 방향 화살표: 게임 (x, y) → 고도 화면 축 (core/coords.gd: 게임 +x = 화면 오른쪽, 게임 +y = 고도 -z = 화면 안쪽·위)
static func arrow(dir) -> String:
	if not (dir is Dictionary):
		return ""
	var g := Coords.gxyz(float(dir.get("x", 0.0)), float(dir.get("y", 0.0)), 0.0)
	if is_zero_approx(g.x) and is_zero_approx(g.z):
		return ""
	if absf(g.x) >= absf(g.z):
		return "→" if g.x > 0.0 else "←"
	return "↑" if g.z < 0.0 else "↓"
