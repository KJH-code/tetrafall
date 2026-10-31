# 격자 칸 값 → 쌓인 블록 색 (client/render.js cellColor 그대로). 값: shared/pieces.js CELL
# 정답 자료: tests/fixtures/cells.json
extends RefCounted

const C := preload("res://core/config.gd")

const TERRAIN := 1
const BUILD := 2
const THROWN := 3
const SHAPE_BASE := 10
const GHOST_BASE := 20
const SHAPE_NAMES := ["I", "O", "T", "S", "Z", "J", "L"] # shared/pieces.js SHAPES 순서


# three.js new Color(hex).multiplyScalar(k).getHex(): 색 관리가 켜져 있어 선형 공간에서 곱함 (sRGB → 선형 → ×k → sRGB)
static func shade(hex: int, k: float) -> int:
	var out := 0
	for sh: int in [16, 8, 0]:
		var c: float = ((hex >> sh) & 0xff) / 255.0
		var lin: float = c * 0.0773993808 if c < 0.04045 else pow(c * 0.9478672986 + 0.0521327014, 2.4)
		lin *= k
		var s: float = lin * 12.92 if lin < 0.0031308 else 1.055 * pow(lin, 0.41666) - 0.055
		out |= clampi(roundi(clampf(s, 0.0, 1.0) * 255.0), 0, 255) << sh
	return out


# colors: 조각 색 표 (맵 테마 piece.colors, 없으면 C.SHAPE_COLORS). 돌려줌 0xRRGGBB
static func cell_color(v: int, colors: Dictionary = C.SHAPE_COLORS) -> int:
	if v == BUILD:
		return int(C.BUILD_COLOR)
	if v >= GHOST_BASE:
		return shade(int(C.PLAYER_PALETTE[(v - GHOST_BASE) % C.PLAYER_PALETTE.size()]), C.BLOCK_LANDED_SHADE)
	if v == THROWN:
		return int(C.THROWN_COLOR)
	var i := v - SHAPE_BASE
	if i >= 0 and i < SHAPE_NAMES.size():
		return shade(int(colors[SHAPE_NAMES[i]]), C.BLOCK_LANDED_SHADE)
	return int(C.TERRAIN_COLOR)


# 맵 id → 테마 표 (WORLD_THEMES 한 줄, 없으면 {})
static func theme_of(map_id: String) -> Dictionary:
	var id = C.WORLD_MAP_THEME.get(map_id, "")
	return C.WORLD_THEMES.get(id, {})


# 테마 조각 색 (없으면 기본)
static func piece_colors(theme: Dictionary) -> Dictionary:
	var out: Dictionary = C.SHAPE_COLORS.duplicate()
	var pc = theme.get("piece", {}).get("colors", {})
	for k in pc:
		out[k] = pc[k]
	return out
