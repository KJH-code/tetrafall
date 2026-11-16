# C7 (겉모습 2 — 바닥 읽힘): 착지 예고 칸의 테. 그림자 채움 (검정 5단·내 것 주황/빨강·위험 빨강) 은 어두운 바닥에서 안 보임 →
# 조각 바깥 윤곽만 얇은 띠로 두름 (칸 사이 안쪽 선은 없음). 테 색은 바닥 밝기에 따라: 어두운 바닥엔 밝게, 밝은 바닥엔 어둡게.
# 그리는 곳 world/pieces_view.gd (띠 MultiMesh 하나, 그림자와 같은 표준 재질). 순수 계산만. 테스트 tests/test_shadow.gd test_c7_*
extends RefCounted

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")

const RIM := {
	"w": 0.09, # 띠 폭 (칸). 칸 안쪽 가장자리에 붙임
	"lift": 0.004, # 그림자 칸 (WC.SHADOW_LIFT) 보다 이만큼 더 위
	"alpha": 0.95,
	"luma_split": 0.55, # 바닥 sRGB 밝기가 이보다 낮으면 '어두운 바닥' (화산·수정·버섯 0.26~0.40 / 성·초원·사막·하늘성 0.65~0.90)
	"cream": 0xfff2b0, # 어두운 바닥의 보통 테
	"ink": 0x2a1f33, # 밝은 바닥의 보통 테
	"whiten": 0.55, # 어두운 바닥에서 내 것·위험 색을 흰 쪽으로
}
const KINDS := ["normal", "fit", "nofit", "danger"] # 보통 · 내 조종 블록 (놓을 수 있음·없음) · 내 머리 위 위험
const DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]] # 변 방향 번호 0 +x · 1 −x · 2 +y · 3 −y


static func _have(cells: Array) -> Dictionary:
	var have := {}
	for c in cells:
		have[Vector2i(roundi(c[0]), roundi(c[1]))] = true
	return have


# 조각의 바깥 변: 그쪽에 같은 조각 칸이 없는 변만. cells = [[x, y, ...]] (같은 x·y 는 한 칸으로). 돌려줌 [[x, y, 방향 번호]]
static func outer_edges(cells: Array) -> Array:
	var have := _have(cells)
	var out := []
	for k in have:
		for d in DIRS.size():
			if not have.has(k + Vector2i(DIRS[d][0], DIRS[d][1])):
				out.append([k.x, k.y, d])
	return out


# 띠 조각들 [[가운데 x, 가운데 y, x 크기, y 크기]] (게임 좌표, 칸 왼쪽 아래가 x·y): 바깥 변마다 폭 w × 길이 1 띠를 칸 안쪽에,
# + 안으로 꺾이는 모서리 (두 이웃은 있고 대각선 칸이 없는 곳) 엔 w × w 조각 — 띠가 모서리에서 끊기지 않게
static func strips(cells: Array, w: float = RIM.w) -> Array:
	var out := []
	for e in outer_edges(cells):
		var dx: int = DIRS[e[2]][0]
		var dy: int = DIRS[e[2]][1]
		out.append([e[0] + 0.5 + dx * (0.5 - w / 2.0), e[1] + 0.5 + dy * (0.5 - w / 2.0), w if dx != 0 else 1.0, w if dy != 0 else 1.0])
	var have := _have(cells)
	for k in have:
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				if have.has(k + Vector2i(sx, 0)) and have.has(k + Vector2i(0, sy)) and not have.has(k + Vector2i(sx, sy)):
					out.append([k.x + 0.5 + sx * (0.5 - w / 2.0), k.y + 0.5 + sy * (0.5 - w / 2.0), w, w])
	return out


# 띠 한 조각의 자리 (1×1 PlaneMesh 를 납작하게): z = 착지 높이
static func strip_xf(s: Array, land_z: float) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3(s[2], 1.0, s[3])), Co.gxyz(s[0], s[1], land_z + WC.SHADOW_LIFT + RIM.lift))


# 바닥 밝기 (sRGB 0..1): 테마 floor.a·b 평균. 바닥 정의가 없으면 기본 지형 색
static func floor_luma(theme: Dictionary) -> float:
	var fl: Dictionary = theme.get("floor", {})
	var a := Co.color(fl.get("a", C.TERRAIN_COLOR))
	return (a.get_luminance() + Co.color(fl.get("b", fl.get("a", C.TERRAIN_COLOR))).get_luminance()) / 2.0


# 테 색. kind: KINDS. 보통은 바닥과 반대 밝기 (크림/잉크), 내 것·위험은 제 색 (그림자 채움과 같은 색) — 어두운 바닥에선 흰 쪽으로
static func rim_color(kind: String, luma: float) -> Color:
	var dark: bool = luma < RIM.luma_split
	var c: Color
	if kind == "fit":
		c = Co.color(WC.PREVIEW_COLOR[0])
	elif kind == "nofit":
		c = Co.color(WC.PREVIEW_COLOR[1])
	elif kind == "danger":
		c = Co.color(WC.DANGER_SHADOW[0])
	else:
		c = Co.color(RIM.cream if dark else RIM.ink)
		c.a = RIM.alpha
		return c
	if dark:
		c = c.lerp(Color.WHITE, RIM.whiten)
	c.a = RIM.alpha
	return c


# 한 조각의 띠들 [[Transform3D, Color]]. shadow = 그림자 칸 [[x, y]], kind = 조각의 종류 (KINDS), danger = {Vector2i 칸: true} 내 머리 위 칸 (그 칸에 놓인 띠만 위험 색)
static func items(shadow: Array, land_z: float, kind: String, danger: Dictionary, luma: float) -> Array:
	var out := []
	var base := rim_color(kind, luma)
	var red := rim_color("danger", luma)
	for s in strips(shadow):
		out.append([strip_xf(s, land_z), red if danger.has(Vector2i(floori(s[0]), floori(s[1]))) else base])
	return out

