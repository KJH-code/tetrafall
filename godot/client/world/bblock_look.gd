# 건축가 블록 모습 순수 계산 (shared/bblock-look.js 그대로, 2026-10-30 재혁 시안 A '공사장 나무 상자'): 칸 부품·솟기·금·깜빡임·R 준비·무너짐·조각 수.
# 게임 좌표 (z 위). world/bblocks.gd 가 그림, tests/test_bblocks.gd 가 JS 와 비교
extends RefCounted

const C := preload("res://core/config.gd")

const KINDS := ["wall", "pad", "third", "big"]


# 칸 한 개의 부품: {part, mat?, at [x,y,z] (칸 바닥 가운데에서), size [x,y,z]}. part: base (판자 상자) · corner (쇠 모서리) · band (줄무늬 띠) · plate (R 빛 판)
static func parts(kind: String) -> Array:
	var L: Dictionary = C.BB_LOOK
	var s: float = L.box.get(kind, L.box.wall)
	var mat := "woodPad" if kind == "pad" else ("woodBig" if kind == "big" else "wood")
	var out := [{"part": "base", "mat": mat, "at": [0.0, 0.0, s / 2], "size": [s, s, s]}]
	var c: float = L.corner
	var big := kind == "big"
	for sgn in [[1, 1], [-1, 1], [1, -1], [-1, -1]]:
		var o := 0.44 if big else s / 2 - 0.04
		out.append({"part": "corner", "at": [sgn[0] * o, sgn[1] * o, s / 2], "size": [c, c, s + 0.02]})
	var b: Dictionary = L.band.get(kind, L.band.wall)
	if kind == "third":
		out.append({"part": "band", "at": [0.0, 0.0, s / 2], "size": [s + 0.03, b.w, s + 0.03]})
	else:
		out.append({"part": "band", "at": [0.0, 0.0, s * b.z], "size": [s + 0.03, s + 0.03, b.h]})
	if big:
		out.append({"part": "plate", "at": [0.0, 0.0, s + L.plate.h / 2 - 0.01], "size": [L.plate.size, L.plate.size, L.plate.h]})
	return out


# 솟기: 바닥에서 위로 자라며 살짝 넘쳤다 돌아옴 (u = 0~1)
static func rise_scale(u: float) -> float:
	if u >= 1.0:
		return 1.0
	return maxf(0.05, 1.0 + 0.25 * sin(PI * u) - pow(1.0 - u, 3))


# 금 0 → 1: 사라지기 BB_CRACK_MS 전부터 (left = 남은 ms)
static func crack_of(left) -> float:
	if left == null or not is_finite(float(left)) or float(left) >= C.BB_CRACK_MS:
		return 0.0
	return clampf(1.0 - float(left) / C.BB_CRACK_MS, 0.0, 1.0)


# 하얗게 깜빡 (0 / 0.45): 사라지기 BB_BLINK_MS 전부터, 끝 1/3 은 빠르게
static func flash_of(left, now: float) -> float:
	if left == null or not is_finite(float(left)) or float(left) >= C.BB_BLINK_MS:
		return 0.0
	var period := 70.0 if float(left) < C.BB_BLINK_MS / 3 else 140.0
	return 0.45 if int(floor(now / period)) % 2 != 0 else 0.0


# R 대폭발 준비 (left = 터질 때까지 ms): {k, swell, glow}
static func big_prep(left: float, now: float) -> Dictionary:
	var k := 1.0 - clampf(left / C.BUILDER_BIG_FUSE_MS, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(now / (60.0 - 40.0 * k))
	return {"k": k, "swell": 1.0 + C.BB_BIG_SWELL * k * k + 0.03 * k * sin(now / 30.0), "glow": minf(1.0, 0.25 + 0.75 * k * (0.7 + 0.3 * pulse))}


# 수명 끝 무너짐 (u = 0~1): sz 높이 비율, sink 내려간 칸, tilt 라디안
static func collapse_at(u: float) -> Dictionary:
	var t := clampf(u, 0.0, 1.0)
	return {"sz": maxf(0.08, 1.0 - 0.92 * t * t), "sink": 0.15 * t, "tilt": 0.35 * t * (1.0 - 0.4 * t)}


# 터질 때·무너질 때 판자 조각 수
static func shard_count(kind: String, low := false) -> int:
	var n: float = C.BB_SHARDS.get(kind, C.BB_SHARDS.wall)
	return maxi(1 if low else 0, roundi(n * (C.BB_LOW_FX if low else 1.0)))


# R 빛 판 색: 차가움 → 뜨거움 → (0.7 넘으면) 하양
static func plate_color(glow: float) -> Color:
	var L: Dictionary = C.BB_LOOK
	var c := Color.hex((int(L.plateCold) << 8) | 0xff).lerp(Color.hex((int(L.plateHot) << 8) | 0xff), minf(1.0, glow * 1.4))
	if glow > 0.7:
		c = c.lerp(Color.hex((int(L.plateWhite) << 8) | 0xff), (glow - 0.7) / 0.3)
	return c
