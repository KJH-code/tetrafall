# 글자 흐린 빛 (CSS text-shadow 0 0 Npx 흉내, W8): 고도 Label 은 그림자·외곽선을 흐리지 못해 굵은 외곽선 겹은 '얇은 띠' 로 보임 (JS 로고는 넓고 부드러운 빛).
# 한 번만: 글자를 SubViewport 에 반 크기로 그려 (투명 바탕) 이미지로 받고 → 흐림 크기만큼 반씩 줄였다 (2×2 평균 = 상자 흐림) 다시 키움 (cubic) → 흰 빛 판.
# 색은 TextureRect self_modulate (테마가 바뀌면 restyle 이 다시 칠함), 더하기 섞기 (빛). 매 프레임 비용 = 로고 칸만 한 판 그리기 3장, 셰이더·SubViewport 없음
extends RefCounted

const BAKE_K := 0.5 # 글자를 이 배율로 그려 굽기 (흐린 빛이라 반 크기로 충분)
const BLUR_K := 1.5
const PAD_K := 1.6 # 판 여백 = 가장 넓은 흐림 × 이만큼 (빛이 판 끝에서 잘리지 않게)


# 흐림: 흐림 px (CSS blur 반지름, 바탕 픽셀 기준) 만큼 반씩 줄였다가 원래 크기로 (가우스 비슷). 크기는 그대로
static func blur(src: Image, px: float) -> Image:
	var im := src.duplicate() as Image
	var w := im.get_width()
	var h := im.get_height()
	var steps := halvings(px)
	for i in steps:
		im.resize(maxi(1, im.get_width() / 2), maxi(1, im.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	# 작게 한 번 더 문질러 계단 없앰 → 원래 크기
	im.resize(w, h, Image.INTERPOLATE_CUBIC)
	return im


# 반으로 줄이는 횟수: 2^n ≈ 흐림 px × 1.5 (CSS 흐림은 반지름의 두 배 가까이 번져 보임 — JS 스샷 대조)
static func halvings(px: float) -> int:
	return maxi(0, int(round(log(maxf(1.0, px * BLUR_K)) / log(2.0))))


static func _up(v: int, q: int) -> int:
	return int(ceil(float(v) / q)) * q


# 굽기 (트리 안 노드 parent 아래에서 한 프레임): text 를 font·size 로 그려 흐린 판들 [{tex, pad}] (layers = [[흐림 px, …], …], 바탕 픽셀 기준).
# pad = 글자 왼쪽 위에서 판 왼쪽 위까지 (바탕 픽셀). parent 가 트리 밖이면 []
static func bake(parent: Node, text: String, font: Font, size: int, layers: Array) -> Array:
	if parent == null or not parent.is_inside_tree():
		return []
	var maxpx := 0.0
	for ly in layers:
		maxpx = maxf(maxpx, float(ly[0]))
	var k := BAKE_K
	var pad := int(ceil(maxpx * PAD_K * k))
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", maxi(4, int(size * k)))
	l.add_theme_color_override("font_color", Color.WHITE)
	vp.add_child(l)
	parent.add_child(vp) # 트리 안에서 재야 글자 폭이 맞음 (밖이면 줄 모양을 덜 잡아 좁게 나옴)
	l.reset_size()
	var m := l.get_combined_minimum_size()
	l.position = Vector2(pad, pad)
	# 반씩 줄일 때 홀수 크기가 잘리면 빛이 오른쪽 아래로 밀림 → 2^(최대 횟수) 배수로 (남는 곳은 오른쪽·아래 빈칸)
	var q := 1 << halvings(maxpx * k)
	vp.size = Vector2i(_up(int(ceil(m.x)) + pad * 2, q), _up(int(ceil(m.y)) + pad * 2, q))
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return []
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return []
	img.convert(Image.FORMAT_RGB8) # 투명 바탕에 흰 글자 → rgb = 덮인 정도. 알파는 버림 (더하기 섞기에서 rgb × 알파 = 제곱이라 가장자리 빛이 죽음)
	var out: Array = []
	for ly in layers:
		var b := blur(img, float(ly[0]) * k)
		out.append({"tex": ImageTexture.create_from_image(b), "pad": pad / k, "scale": 1.0 / k})
	return out


# 흐린 판 하나를 놓을 TextureRect (더하기 섞기, 마우스 무시)
static func rect(tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	t.material = mat
	return t
