# 갈고리 R 덩어리 (뽑힌 블록) 면 그림 — client/textures.js stone·sand 를 64px Image 에 직접 그림 (같은 씨앗 → 매번 같은 무늬).
# JS 는 칸 종류마다 재질이 달라 (지형 돌 · 쌓기 나무 · 설치 블록 모래 · 테트리미노 = 맵 테마 칸 모습), 고도도 같게 (world/hook_fx.gd chunk_look)
extends RefCounted

const N := 64
static var _cache := {}


# JS textures.js rng: 선형 합동 (같은 씨앗 → 같은 줄)
class Lcg:
	var s: int
	func _init(seed: int) -> void:
		s = seed & 0xFFFFFFFF
	func next() -> float:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		return s / 4294967296.0


static func _gray(v: int) -> Color:
	return Color8(v, v, v)


static func _rect(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	var r := Rect2i(int(floor(x)), int(floor(y)), maxi(1, int(round(w))), maxi(1, int(round(h)))).intersection(Rect2i(0, 0, N, N))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, c)


static func _line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var steps := maxi(1, int(a.distance_to(b) * 2.0))
	var r := width / 2.0
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		for yy in range(int(floor(p.y - r)), int(ceil(p.y + r)) + 1):
			for xx in range(int(floor(p.x - r)), int(ceil(p.x + r)) + 1):
				if xx >= 0 and yy >= 0 and xx < N and yy < N and Vector2(xx + 0.5, yy + 0.5).distance_to(p) <= r + 0.25:
					img.set_pixel(xx, yy, c)


# 안쪽 테두리 (JS strokeRect(1.5, 1.5, n-3, n-3), 굵기 3)
static func _frame(img: Image, c: Color) -> void:
	_rect(img, 0, 0, N, 3, c)
	_rect(img, 0, N - 3, N, 3, c)
	_rect(img, 0, 0, 3, N, c)
	_rect(img, N - 3, 0, 3, N, c)


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func stone() -> ImageTexture:
	if _cache.has("stone"):
		return _cache.stone
	var r := Lcg.new(7)
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(_gray(215))
	for i in 90:
		var v := 185 + int(floor(r.next() * 60))
		var s := 2.0 + r.next() * 7.0
		_rect(img, r.next() * N, r.next() * N, s, s, _gray(v))
	for i in 3:
		var x := r.next() * N
		var y := r.next() * N
		var p := Vector2(x, y)
		for k in 4:
			x += (r.next() - 0.5) * 18.0
			y += (r.next() - 0.5) * 18.0
			_line(img, p, Vector2(x, y), 1.5, _gray(150))
			p = Vector2(x, y)
	_frame(img, _gray(105))
	_cache.stone = _tex(img)
	return _cache.stone


static func sand() -> ImageTexture:
	if _cache.has("sand"):
		return _cache.sand
	var r := Lcg.new(23)
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(_gray(230))
	for i in 260:
		_rect(img, r.next() * N, r.next() * N, 1.5, 1.5, _gray(190 + int(floor(r.next() * 60))))
	_frame(img, _gray(130))
	_cache.sand = _tex(img)
	return _cache.sand


# 건축가 판자 (JS this.bb.textures.wood = bblocks 판자 그림, 쌓기 나무 칸·건축가 덩어리)
static func wood() -> ImageTexture:
	if not _cache.has("wood"):
		_cache.wood = preload("res://world/bblock_tex.gd").planks(int(preload("res://core/config.gd").BB_LOOK.wood))
	return _cache.wood
