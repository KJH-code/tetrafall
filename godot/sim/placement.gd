# 자동 블록 자리 점수 (server/game-placement.js placementScorer 그대로 옮김).
# 지금 격자의 기둥 높이·가장 낮은 층(L)의 빈 칸 덩어리를 한 번만 재 두고, score(cells, px, py, z) 를 후보마다 부름.
# 점수가 높을수록 L 층 클리어에 가까움:
# - 밑에 빈칸(구멍)을 만들면 벌점, L 보다 높이 얹으면 높이만큼 약한 벌점
# - L 층에 딱 붙으면 가점, 그걸로 L 층이 다 차면 큰 가점
# - L 층에 남는 빈 덩어리 중 칸 수가 4의 배수가 아닌 덩어리는 벌점 (평평한 4칸 블록으로 영영 못 채움)
# 자리 고르기에서 틱 시간 대부분을 쓰는 곳 → GDExtension 으로 뺄 첫 후보 (README)
extends RefCounted

const C := preload("res://sim/config.gd")

const S_FILL: int = C.CLEAR_SCORE.FILL
const S_CLEAR: int = C.CLEAR_SCORE.CLEAR
const S_BAD_GAP: int = C.CLEAR_SCORE.BAD_GAP
const S_HOLE: int = C.CLEAR_SCORE.HOLE

var W := 0
var D := 0
var N := 0
var tops := PackedInt32Array()
var L := 0
var comp := PackedInt32Array() # 칸 → L 층 빈 칸 덩어리 번호 (-1 = L 층 아님)
var size := PackedInt32Array() # 덩어리 칸 수
var base_remaining := 0
var base_bad := 0
var seen := PackedInt32Array()
var cov := PackedInt32Array()
var stack := PackedInt32Array()
var ring_mark := PackedInt32Array()
var ring := PackedInt32Array()
var stamp := 1
var covered := PackedInt32Array([0, 0, 0, 0])
var out := PackedInt32Array()
var out_n := 0


func _init(w: int, d: int, column_tops: PackedInt32Array) -> void:
	W = w
	D = d
	N = W * D
	tops = column_tops
	L = 1 << 30
	for t in tops:
		L = mini(L, t)
	seen.resize(N)
	cov.resize(N)
	stack.resize(N)
	ring_mark.resize(N)
	ring.resize(16)
	out.resize(N)
	comp.resize(N)
	comp.fill(-1)
	for i in N:
		if tops[i] != L or comp[i] >= 0:
			continue
		var id := size.size()
		var n := 0
		var sp := 0
		stack[sp] = i
		sp += 1
		comp[i] = id
		while sp > 0:
			sp -= 1
			var c := stack[sp]
			n += 1
			for k in 4:
				var q := _nb(c, k)
				if q >= 0 and tops[q] == L and comp[q] < 0:
					comp[q] = id
					stack[sp] = q
					sp += 1
		size.append(n)
		base_remaining += n
		if n % 4 != 0:
			base_bad += 1


# 이웃 칸 (오른쪽·왼쪽·아래·위), 필드 밖이면 -1
func _nb(c: int, k: int) -> int:
	var cx := c % W
	if k == 0:
		return c + 1 if cx + 1 < W else -1
	if k == 1:
		return c - 1 if cx > 0 else -1
	if k == 2:
		return c + W if c + W < N else -1
	return c - W


# 덩어리 id 에서 덮인 칸을 뺀 조각들 크기를 out[0..out_n) 에. 첫 조각이 둘레를 다 만나면 남은 칸 전부 한 조각
func _parts(id: int, covered_in: int, cov_stamp: int) -> void:
	out_n = 0
	stamp += 1
	var rs := stamp
	var nr := 0
	for c in covered:
		for k in 4:
			var q := _nb(c, k)
			if q < 0 or comp[q] != id or cov[q] == cov_stamp or ring_mark[q] == rs:
				continue
			ring_mark[q] = rs
			ring[nr] = q
			nr += 1
	if nr == 0:
		return # 덩어리가 통째로 덮임
	var left := size[id] - covered_in
	stamp += 1
	var ss := stamp
	var found := 0
	for r in nr:
		var r0 := ring[r]
		if seen[r0] == ss:
			continue
		var n := 0
		var head := 0
		var tail := 0
		stack[tail] = r0
		tail += 1
		seen[r0] = ss
		while head < tail:
			var c := stack[head]
			head += 1
			n += 1
			if ring_mark[c] == rs:
				found += 1
				if found == nr and out_n == 0:
					out[0] = left
					out_n = 1
					return
			# 이웃 넷 (함수 호출 없이 펼침: GDScript 는 호출이 비쌈)
			var cx := c % W
			var q := c + 1
			if cx + 1 < W and comp[q] == id and cov[q] != cov_stamp and seen[q] != ss:
				seen[q] = ss
				stack[tail] = q
				tail += 1
			q = c - 1
			if cx > 0 and comp[q] == id and cov[q] != cov_stamp and seen[q] != ss:
				seen[q] = ss
				stack[tail] = q
				tail += 1
			q = c + W
			if q < N and comp[q] == id and cov[q] != cov_stamp and seen[q] != ss:
				seen[q] = ss
				stack[tail] = q
				tail += 1
			q = c - W
			if q >= 0 and comp[q] == id and cov[q] != cov_stamp and seen[q] != ss:
				seen[q] = ss
				stack[tail] = q
				tail += 1
		out[out_n] = n
		out_n += 1
		left -= n


func score(cells: Array, px: int, py: int, z: int) -> int:
	var holes := 0
	for c in cells:
		holes += z - tops[(py + c.y) * W + px + c.x]
	if holes > 0:
		return -S_HOLE * holes - (z - L)
	if z != L:
		return -(z - L)
	# 여기까지 오면 덮인 칸은 모두 가장 낮은 층의 빈 칸
	stamp += 1
	var cov_stamp := stamp
	for k in 4:
		var c: int = (py + cells[k].y) * W + px + cells[k].x
		cov[c] = cov_stamp
		covered[k] = c
	var remaining := base_remaining - 4
	# 빠른 길: 블록 둘레(대각선 포함)가 모두 필드 안 L 층 빈 칸이면 남은 칸은 한 조각 → bad 그대로
	var ring_open := true
	for k in 4:
		if not ring_open:
			break
		var c := covered[k]
		var cx := c % W
		var cy := c / W
		for oy in range(-1, 2):
			if not ring_open:
				break
			for ox in range(-1, 2):
				var x := cx + ox
				var y := cy + oy
				if x < 0 or y < 0 or x >= W or y >= D:
					ring_open = false
					break
				var q := y * W + x
				if cov[q] != cov_stamp and tops[q] != L:
					ring_open = false
					break
	if ring_open:
		return S_FILL + (S_CLEAR if remaining == 0 else 0) - S_BAD_GAP * base_bad
	var bad := base_bad
	for k in 4:
		var id := comp[covered[k]]
		var dup := false
		for j in k:
			if comp[covered[j]] == id:
				dup = true
		if dup:
			continue # 덩어리마다 한 번
		var covered_in := 0
		for j in 4:
			if comp[covered[j]] == id:
				covered_in += 1
		if size[id] % 4 != 0:
			bad -= 1
		_parts(id, covered_in, cov_stamp)
		for i in out_n:
			if out[i] % 4 != 0:
				bad += 1
	return S_FILL + (S_CLEAR if remaining == 0 else 0) - S_BAD_GAP * bad
