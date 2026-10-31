# 건축가 블록 코드 텍스처 (client/bblocks.js planksTexture·stripesTexture·crackMask 자리): 64px Image 에 직접 그림. 같은 씨앗이면 JS 와 같은 판 배치
extends RefCounted

const N := 64


class Rng:
	var s := 1
	func _init(seed: int) -> void:
		s = seed
	func next() -> float:
		s = (s * 16807) % 2147483647
		return s / 2147483647.0


static func _shade(c: int, k: float) -> Color:
	var r := clampi(int(((c >> 16) & 255) * k), 0, 255)
	var g := clampi(int(((c >> 8) & 255) * k), 0, 255)
	var b := clampi(int((c & 255) * k), 0, 255)
	return Color8(r, g, b)


static func _rect(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	img.fill_rect(Rect2i(int(round(x)), int(round(y)), maxi(1, int(round(w))), maxi(1, int(round(h)))).intersection(Rect2i(0, 0, N, N)), c)


# 굵은 선: 선을 따라 굵기만 한 점을 찍음
static func _line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var steps := maxi(1, int(a.distance_to(b) * 2.0))
	var r := width / 2.0
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		for yy in range(int(floor(p.y - r)), int(ceil(p.y + r)) + 1):
			for xx in range(int(floor(p.x - r)), int(ceil(p.x + r)) + 1):
				if xx >= 0 and yy >= 0 and xx < N and yy < N and Vector2(xx + 0.5, yy + 0.5).distance_to(p) <= r + 0.25:
					img.set_pixel(xx, yy, c)


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# 판자: 판 4장, 결, 틈, (버팀목 대각선), 못, 테두리
static func planks(base: int, vertical := false, brace := true, seed := 7) -> ImageTexture:
	var r := Rng.new(seed)
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(_shade(base, 1.0))
	var boards := 4
	for i in boards:
		var a := float(i * N) / boards
		var cb := _shade(base, 0.86 + r.next() * 0.24)
		if vertical:
			_rect(img, a + 1, 0, N / boards - 2, N, cb)
		else:
			_rect(img, 0, a + 1, N, N / boards - 2, cb)
		for k in 3:
			var o := a + 3 + r.next() * (N / boards - 6)
			var d := (r.next() - 0.5) * 3
			if vertical:
				_line(img, Vector2(o, 0), Vector2(o + d, N), 1.0, _shade(base, 0.7))
			else:
				_line(img, Vector2(0, o), Vector2(N, o + d), 1.0, _shade(base, 0.7))
		if vertical:
			_rect(img, a, 0, 1.5, N, _shade(base, 0.45))
		else:
			_rect(img, 0, a, N, 1.5, _shade(base, 0.45))
	if brace:
		_line(img, Vector2(4, N - 4), Vector2(N - 4, 4), 9.0, _shade(base, 0.62))
		_line(img, Vector2(4, N - 4), Vector2(N - 4, 4), 6.0, _shade(base, 1.08))
	for p in [Vector2(6, 6), Vector2(N - 6, 6), Vector2(6, N - 6), Vector2(N - 6, N - 6)]:
		_line(img, p, p, 3.2, Color8(0x3a, 0x3a, 0x3a))
	var e := _shade(base, 0.4)
	_rect(img, 0, 0, N, 3, e)
	_rect(img, 0, N - 3, N, 3, e)
	_rect(img, 0, 0, 3, N, e)
	_rect(img, N - 3, 0, 3, N, e)
	return _tex(img)


# 공사 줄무늬: 흰·검정 사선 (흰 부분에 주인 색이 곱해짐)
static func stripes() -> ImageTexture:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var dark := Color8(0x16, 0x16, 0x1a)
	for y in N:
		for x in N:
			# 평행사변형 (x, n)-(x+10, n)-(x+10+n, 0)-(x+n, 0): 사선 위 x + (N - y) 쪽으로 10 폭, 20 마다
			var u := fposmod(float(x) + 0.5 - (N - (y + 0.5)), 20.0)
			if u < 10.0:
				img.set_pixel(x, y, dark)
	return _tex(img)


# 금 무늬 가리개: 선 밝기 = 그 금이 나타나는 때 (가운데 먼저 → 바깥 나중), 바탕은 흰 1.0
static func crack_mask() -> ImageTexture:
	var r := Rng.new(91)
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for end in [[0.04, 0.22], [0.96, 0.12], [0.86, 0.96], [0.1, 0.88], [0.5, 0.02], [0.98, 0.6]]:
		var p := Vector2(N / 2.0, N / 2.0)
		var steps := 6
		for k in range(1, steps + 1):
			var u := float(k) / steps
			var x: float = N * (0.5 + (end[0] - 0.5) * u) + (r.next() - 0.5) * 6
			var y: float = N * (0.5 + (end[1] - 0.5) * u) + (r.next() - 0.5) * 6
			var v := roundi(20 + 225 * (float(k - 1) / steps))
			_line(img, p, Vector2(x, y), 3.2 - u * 1.4, Color8(v, v, v))
			p = Vector2(x, y)
	return _tex(img)
