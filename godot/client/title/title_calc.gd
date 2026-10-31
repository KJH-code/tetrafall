# 타이틀 로고 계산 (shared/title.js 그대로): 글자 → 5×7 칸 → 4칸 이하 조각 → 떨어지는 순서·시각 → 높이, 장면 빛·빠져나가기·메뉴 떠돎·테마 고르기.
# 좌표: x 는 왼쪽부터, y 는 아래부터 (게임 좌표 z 위). tests/test_title.gd 가 JS 와 비교
extends RefCounted

const C := preload("res://core/config.gd")

const GLYPH_W := 5
const GLYPH_H := 7
const FONT := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	"-": [".....", ".....", ".....", ".###.", ".....", ".....", "....."],
	" ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}


static func _smooth(k: float) -> float:
	return 0.0 if k <= 0.0 else (1.0 if k >= 1.0 else k * k * (3.0 - 2.0 * k))


# 글자 → {cells: [Vector2i(x, y)], width, height}. gap = 글자 사이 칸, bold = 한 칸을 bold×bold 로
static func cells(text: String, gap := 1, bold := 1) -> Dictionary:
	var out := []
	var ox := 0
	var k := maxi(1, bold)
	for ch in text.to_upper():
		var g: Array = FONT.get(ch, FONT[" "])
		for r in g.size():
			var row: String = g[r]
			for c in GLYPH_W:
				if row[c] != "#":
					continue
				for i in k:
					for j in k:
						out.append(Vector2i(ox + c * k + i, (GLYPH_H - 1 - r) * k + j))
		ox += (GLYPH_W + gap) * k
	return {"cells": out, "width": maxi(0, ox - gap * k), "height": GLYPH_H * k}


static func interval(n: int, build_ms := C.TITLE_BUILD_MS, fall_ms := C.TITLE_FALL_MS, settle_ms := C.TITLE_SETTLE_MS) -> float:
	if n <= 1:
		return 0.0
	return maxf(C.TITLE_DROP_MIN_MS, (build_ms - fall_ms - settle_ms) / (n - 1))


# 로고 폭이 화면 폭의 fill 만큼 차는 카메라 거리 (세로 시야각 fov_deg)
static func cam_dist(world_w: float, fov_deg: float, aspect: float, fill := C.TITLE_FILL) -> float:
	var tan_h := tan(deg_to_rad(fov_deg) / 2.0) * aspect
	return world_w / 2.0 / (fill * tan_h)


# 칸 → 조각: 아래 줄·왼쪽부터, 붙은 칸 (위 먼저) 을 넓이 우선으로 최대 size 개. [{shape, cells: [Vector2i], min_y}]
static func pieces(list: Array, size := 4, shapes := ["I", "O", "T", "S", "Z", "J", "L"]) -> Array:
	var left := {}
	for c in list:
		left[c] = true
	var order := list.duplicate()
	order.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out := []
	for start in order:
		if not left.has(start):
			continue
		var group := []
		var queue := [start]
		left.erase(start)
		while not queue.is_empty() and group.size() < size:
			var c: Vector2i = queue.pop_front()
			group.append(c)
			for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
				var k: Vector2i = c + d
				if left.has(k) and group.size() + queue.size() < size:
					queue.append(k)
					left.erase(k)
		for c in queue:
			left[c] = true
		var min_y := 1 << 30
		for c in group:
			min_y = mini(min_y, c.y)
		out.append({"shape": shapes[out.size() % shapes.size()], "cells": group, "min_y": min_y})
	return out


# 떨어지는 출발 시각 (ms): 바닥 낮은 조각 먼저 (같으면 왼쪽부터)
static func drop_schedule(list: Array, gap_ms := C.TITLE_DROP_INTERVAL_MS) -> Array:
	var idx := []
	for i in list.size():
		var cx := 0.0
		for c in list[i].cells:
			cx += c.x
		idx.append({"i": i, "y": list[i].min_y, "cx": cx / list[i].cells.size()})
	idx.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.cx < b.cx) or (a.y == b.y and a.cx == b.cx and a.i < b.i))
	var start := []
	start.resize(list.size())
	for k in idx.size():
		start[idx[k].i] = k * gap_ms
	return start


static func done_at(start: Array, fall_ms := C.TITLE_FALL_MS, settle_ms := C.TITLE_SETTLE_MS) -> float:
	if start.is_empty():
		return 0.0
	return float(start.max()) + fall_ms + settle_ms


# t ms 에 조각의 자리 위 높이 (칸): 출발 전 null, 떨어지며 가속, 닿은 뒤 작게 튕김
static func lift(t: float, start: float, fall_ms := C.TITLE_FALL_MS, drop_h := C.TITLE_DROP_H, settle_ms := C.TITLE_SETTLE_MS, bounce := C.TITLE_BOUNCE):
	var u := t - start
	if u < 0.0:
		return null
	if u < fall_ms:
		var k := u / fall_ms
		return drop_h * (1.0 - k * k)
	var s := (u - fall_ms) / settle_ms
	if s >= 1.0:
		return 0.0
	return bounce * sin(PI * s) * (1.0 - s)


static func theme_ids() -> Array:
	return C.TITLE_THEMES.keys()


# 무작위 테마 (rnd = 0~1)
static func pick_theme(rnd: float) -> String:
	var ids := theme_ids()
	return ids[mini(ids.size() - 1, floori(rnd * ids.size()))]


# 그 테마의 맵 (WORLD_MAP_THEME 거꾸로), 없으면 null
static func map_for(theme: String):
	for m in C.WORLD_MAP_THEME:
		if C.WORLD_MAP_THEME[m] == theme:
			return m
	return null


# 장면 빛: lit 밝기, burst 빛 터짐 1 → 0, glow 글자 빛
static func light(t: float, done: float) -> Dictionary:
	var lit := C.TITLE_LIT_START + (1.0 - C.TITLE_LIT_START) * _smooth(t / C.TITLE_DARK_MS)
	var u := t - done
	var burst := 0.0 if u < 0.0 else pow(maxf(0.0, 1.0 - u / C.TITLE_BURST_MS), 2)
	var g0: float = C.TITLE_GLOW[0]
	var g1: float = C.TITLE_GLOW[1]
	var after := 0.0 if u < 0.0 else _smooth(u / 250.0)
	var glow := (g0 + (g1 - g0) * after) * (1.0 + (C.TITLE_BURST_PEAK - 1.0) * burst)
	return {"lit": lit, "burst": burst, "glow": glow}


# Enter 뒤 ms → {push 0~1, white, show, done}. reduced (움직임 줄이기) 면 하얀 페이드
static func exit(ms: float, reduced := false) -> Dictionary:
	if reduced:
		var F: float = C.TITLE_EXIT_FADE_MS
		if ms < F:
			return {"push": 0.0, "white": _smooth(maxf(0.0, ms) / F), "show": false, "done": false}
		var f := (ms - F) / F
		return {"push": 1.0, "white": 1.0 - _smooth(f), "show": true, "done": f >= 1.0}
	var k := clampf(ms / C.TITLE_EXIT_MS, 0.0, 1.0)
	return {"push": _smooth(k), "white": 0.0, "show": k >= C.TITLE_MENU_SHOW_AT, "done": k >= 1.0}


# 메뉴 카메라 떠돎 [옆, 위, 돌림] (날아가기 끝난 뒤 u ms, 64비트 — Vector3 는 32비트)
static func menu_drift(u: float) -> Array:
	var D: Dictionary = C.MENU_DRIFT
	var k := _smooth(maxf(0.0, u) / D.easeMs)
	var t := maxf(0.0, u) / 1000.0
	return [sin(t * D.speed[0]) * D.side * k, sin(t * D.speed[1]) * D.bob * k, sin(t * D.speed[2]) * D.yaw * k]


# t0 < 닿는 시각 <= t1 인 조각 번호들
static func landed_between(start: Array, t0: float, t1: float, fall_ms := C.TITLE_FALL_MS) -> Array:
	var out := []
	for i in start.size():
		var at: float = start[i] + fall_ms
		if at > t0 and at <= t1:
			out.append(i)
	return out
